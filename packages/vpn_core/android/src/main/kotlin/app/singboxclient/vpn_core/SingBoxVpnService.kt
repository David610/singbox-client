package app.singboxclient.vpn_core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.IpPrefix
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.TunOptions
import java.io.File
import java.net.InetAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The Android VPN path: owns the `android.net.VpnService` TUN lifecycle
 * AND the pinned sing-box core (`io.nekohasekai.libbox`) lifecycle
 * together, because they cannot be correct apart -- a TUN with nothing
 * reading/writing it, or a core with no TUN to bind to, are both useless.
 *
 * Architecture (verified directly against the pinned v1.13.19 source,
 * `experimental/libbox/{command_server,platform,tun,setup}.go`, and
 * matching SagerNet/sing-box-for-android's own integration of the same
 * core -- see [VpnPlatformInterfaceWrapper]'s doc comment for why this
 * class implements that interface directly, mirroring upstream's own
 * `VPNService : VpnService(), PlatformInterfaceWrapper`):
 *
 * ```
 * onStartCommand(ACTION_START)
 *   -> Libbox.setup(...) once per process
 *   -> CommandServer(VpnCommandServerHandler(this), this)
 *   -> commandServer.startOrReloadService(configJson, OverrideOptions())
 *        -- synchronous; throws on ANY real startup failure (bad config,
 *           listen failure, tun-inbound rejection, ...). Internally, and
 *           on this same call stack, sing-box's tun inbound calls back
 *           into this class's own [openTun], which builds and
 *           establishes the real android.net.VpnService TUN using the
 *           addresses/routes/DNS/MTU sing-box itself resolved from the
 *           generated config -- never hardcoded here.
 *   -> only on successful return: VpnCoreState.CONNECTED is published.
 *      A thrown exception publishes INVALID instead and tears down
 *      anything partially established -- CONNECTED can never be reached
 *      from a failed start.
 * ```
 *
 * All libbox calls happen on [executor] (a single-thread pool), never
 * the calling (main) thread -- `startOrReloadService` is a blocking Go
 * call and Android forbids blocking a Service's main-thread callbacks.
 * The executor being single-threaded also serializes start/stop/reload
 * against each other for free: two intents delivered back-to-back can
 * never run their libbox calls concurrently. [openTun]/[autoDetectInterfaceControl]
 * themselves are called BY libbox FROM that executor thread (synchronously,
 * within `startOrReloadService`), not the main thread -- `VpnService.Builder.establish()`
 * and `VpnService.protect()` are documented as safe to call off the main
 * thread.
 */
class SingBoxVpnService : VpnService(), VpnPlatformInterfaceWrapper {

    override val platformContext: Context
        get() = applicationContext

    // --- The three methods only android.net.VpnService itself can
    // implement -- see VpnPlatformInterfaceWrapper's doc comment on why
    // these live here and not in that interface's defaults.

    override fun autoDetectInterfaceControl(fd: Int) {
        // "Protect underlying outbound sockets from the VPN loop": every
        // outbound socket the router creates when
        // `route.auto_detect_interface` is enabled (SingBoxConfigBuilder
        // always sets this -- see singbox_config_builder.dart) is routed
        // through this control callback (route/network.go in the pinned
        // source); without protect() those sockets would themselves be
        // captured by the TUN, deadlocking the tunnel against itself.
        if (!protect(fd)) {
            Log.w(TAG, "VpnService.protect() returned false for fd=$fd")
        }
    }

    override fun openTun(options: TunOptions): Int {
        // Called synchronously, on the executor thread, from inside
        // commandServer.startOrReloadService() (via instance.Start() ->
        // the tun inbound's NewInbound() -> platformInterfaceWrapper.OpenInterface()
        // -> this method), NOT ahead of time. Every field read from
        // [options] below comes from the actual sing-box `tun` inbound
        // document SingBoxConfigBuilder generated (address/routes/DNS/
        // MTU), never hardcoded -- this is what "correctly apply DNS and
        // routes" means in practice: this method has no config of its
        // own, it is a pure translation of libbox's own resolved TUN
        // options into VpnService.Builder calls.
        if (VpnService.prepare(this) != null) {
            error("android: VPN permission not granted")
        }

        val builder = Builder()
            .setSession(activeTag ?: "sing-box")
            .setMtu(options.mtu)
            .setBlocking(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            // GetDNSServerAddress() errors only when there's no IPv4
            // address wide enough to derive a DNS-hijack target from
            // (see tun.go) -- SingBoxConfigBuilder always emits a /28
            // IPv4 tun address, so this always succeeds in practice; a
            // real failure here means a malformed config that got past
            // sing-box's own CheckConfig, which we still surface rather
            // than swallow.
            builder.addDnsServer(options.dnsServerAddress.value)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4RouteAddress = options.inet4RouteAddress
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val route = inet4RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6RouteAddress = options.inet6RouteAddress
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val route = inet6RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }

                val inet4RouteExcludeAddress = options.inet4RouteExcludeAddress
                while (inet4RouteExcludeAddress.hasNext()) {
                    val route = inet4RouteExcludeAddress.next()
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address()), route.prefix()))
                }
                val inet6RouteExcludeAddress = options.inet6RouteExcludeAddress
                while (inet6RouteExcludeAddress.hasNext()) {
                    val route = inet6RouteExcludeAddress.next()
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(route.address()), route.prefix()))
                }
            } else {
                // Below API 33, VpnService.Builder has no excludeRoute();
                // fall back to the pre-computed inclusive route ranges
                // libbox derives for exactly this case (GetInet4RouteRange
                // / GetInet6RouteRange in tun.go already subtract any
                // configured exclude addresses).
                val inet4RouteRange = options.inet4RouteRange
                while (inet4RouteRange.hasNext()) {
                    val route = inet4RouteRange.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                val inet6RouteRange = options.inet6RouteRange
                while (inet6RouteRange.hasNext()) {
                    val route = inet6RouteRange.next()
                    builder.addRoute(route.address(), route.prefix())
                }
            }

            val includePackage = options.includePackage
            while (includePackage.hasNext()) {
                val pkg = includePackage.next()
                try {
                    builder.addAllowedApplication(pkg)
                } catch (e: PackageManager.NameNotFoundException) {
                    Log.w(TAG, "addAllowedApplication($pkg) failed: package not found")
                }
            }
            val excludePackage = options.excludePackage
            while (excludePackage.hasNext()) {
                val pkg = excludePackage.next()
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (e: PackageManager.NameNotFoundException) {
                    Log.w(TAG, "addDisallowedApplication($pkg) failed: package not found")
                }
            }
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bypass = mutableListOf<String>()
            val bypassIterator = options.httpProxyBypassDomain
            while (bypassIterator.hasNext()) bypass.add(bypassIterator.next())
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(options.httpProxyServer, options.httpProxyServerPort, bypass),
            )
        }

        val pfd = builder.establish()
            ?: error("android: VpnService.Builder.establish() returned null (permission revoked mid-start?)")
        tunFd = pfd
        return pfd.fd
    }

    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        postLibboxNotification(notification)
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lifecycle = VpnLifecycleStateMachine()

    /** Set by [openTun] during a successful start; read/closed here. */
    @Volatile
    internal var tunFd: ParcelFileDescriptor? = null

    @Volatile
    internal var activeTag: String? = null
        private set

    private var commandServer: CommandServer? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val tag = intent.getStringExtra(EXTRA_TAG)
                val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                if (tag == null || configJson == null) {
                    Log.e(TAG, "ACTION_START missing tag/configJson extras")
                    return START_NOT_STICKY
                }
                if (!lifecycle.tryStart()) {
                    Log.i(TAG, "start ignored: a start/stop is already in flight (idempotent no-op)")
                    return START_NOT_STICKY
                }
                activeTag = tag
                // Must start the foreground notification promptly (Android
                // requires it within a few seconds of startForegroundService)
                // -- do this synchronously on the main thread before
                // dispatching the (potentially slower) libbox work.
                startForeground(NOTIFICATION_ID, buildNotification(tag, connected = false))
                publishStatus(VpnCoreState.CONNECTING, tag)
                executor.execute { doStart(tag, configJson) }
            }
            ACTION_STOP -> {
                if (!lifecycle.tryStop()) {
                    Log.i(TAG, "stop ignored: already stopped/stopping (idempotent no-op)")
                    // Still make sure the service actually exits even if
                    // it was somehow left running with nothing connected.
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return START_NOT_STICKY
                }
                publishStatus(VpnCoreState.DISCONNECTING, activeTag)
                executor.execute { doStop(fromRevoke = false) }
            }
        }
        return START_NOT_STICKY
    }

    /** Runs on [executor]. */
    private fun doStart(tag: String, configJson: String) {
        ensureLibboxSetup(applicationContext)
        lastKnownConfigJson = configJson
        // Reuse the existing CommandServer across a reload (start called
        // while already CONNECTED, e.g. VpnCorePlugin.restart): the
        // invariant maintained by doStop/failStart is that `commandServer`
        // is non-null iff a core instance is (or was, mid-start) alive,
        // so a non-null value here means DISCONNECTED/INVALID was never
        // reached and there's a live server whose own
        // startOrReloadService() will close its prior instance
        // internally (daemon/started_service.go) -- constructing a second
        // CommandServer here instead would leak the first one, since
        // nothing else would ever close it.
        val server = commandServer ?: try {
            CommandServer(VpnCommandServerHandler(this), this).also {
                commandServer = it
            }
        } catch (e: Throwable) {
            Log.e(TAG, "CommandServer construction failed", e)
            failStart(e)
            return
        }
        try {
            // OverrideOptions is intentionally left at its defaults: no
            // auto_redirect (a Linux root/transparent-proxy feature, not
            // applicable to VpnService), and no include/exclude package
            // override -- SingBoxConfigBuilder.buildSingleOutboundDocument
            // does not currently emit per-app routing (tun inbound has no
            // include_package/exclude_package), so every app is proxied
            // by default via the tun's own routes. Per-app selection is
            // real follow-up work at the config-builder layer, not this
            // service (see docs/ARCHITECTURE.md "why the boundary is 7
            // methods" -- app-level profile concerns belong there).
            server.startOrReloadService(configJson, OverrideOptions())
        } catch (e: Throwable) {
            Log.e(TAG, "startOrReloadService failed: ${e.message}")
            failStart(e)
            return
        }
        lifecycle.startSucceeded()
        if (lifecycle.state != VpnLifecycleState.CONNECTED) {
            // A stop was requested (main thread) while this start was
            // still in flight on this executor thread: tryStop() already
            // moved the state machine to DISCONNECTING, and
            // startSucceeded() above correctly left it there (it only
            // transitions CONNECTING -> CONNECTED). The queued doStop()
            // task -- guaranteed to run right after this one returns,
            // since [executor] is single-threaded -- will close the
            // `commandServer`/`tunFd` this call just established and
            // publish DISCONNECTED; publishing CONNECTED here first would
            // only be a misleading flash of status immediately overwritten.
            return
        }
        mainHandler.post {
            val currentTag = activeTag
            if (currentTag != null) {
                startForeground(NOTIFICATION_ID, buildNotification(currentTag, connected = true))
                publishStatus(VpnCoreState.CONNECTED, currentTag)
            }
        }
    }

    /** Runs on [executor]; cleans up a failed [doStart] and reports it. */
    private fun failStart(cause: Throwable) {
        val server = commandServer
        commandServer = null
        runCatching { server?.closeService() }
        runCatching { server?.close() }
        closeTunFd()
        lifecycle.startFailed()
        mainHandler.post {
            Log.e(TAG, "VPN start failed", cause)
            stopForeground(STOP_FOREGROUND_REMOVE)
            publishStatus(VpnCoreState.INVALID, activeTag)
            activeTag = null
            stopSelf()
        }
    }

    /** Runs on [executor]. */
    private fun doStop(fromRevoke: Boolean) {
        val server = commandServer
        commandServer = null
        runCatching { server?.closeService() }.onFailure {
            Log.w(TAG, "closeService() failed (continuing teardown)", it)
        }
        runCatching { server?.close() }.onFailure {
            Log.w(TAG, "CommandServer.close() failed (continuing teardown)", it)
        }
        closeTunFd()
        lifecycle.stopCompleted()
        mainHandler.post {
            activeTag = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            publishStatus(VpnCoreState.DISCONNECTED, null)
            if (!fromRevoke) stopSelf()
        }
    }

    private fun closeTunFd() {
        tunFd?.let {
            try {
                it.close()
            } catch (e: java.io.IOException) {
                Log.w(TAG, "error closing tun fd", e)
            }
        }
        tunFd = null
    }

    internal fun requestStop() {
        // Invoked from VpnCommandServerHandler.serviceStop() -- see that
        // class's doc comment on when this is actually reachable today.
        if (lifecycle.tryStop()) {
            mainHandler.post { publishStatus(VpnCoreState.DISCONNECTING, activeTag) }
            executor.execute { doStop(fromRevoke = false) }
        }
    }

    internal fun requestReload() {
        val tag = activeTag ?: return
        val server = commandServer ?: return
        if (!lifecycle.tryStart()) return
        mainHandler.post { publishStatus(VpnCoreState.CONNECTING, tag) }
        executor.execute {
            try {
                // Reload with the currently-active config is a no-op in
                // practice (VpnCommandServerHandler.serviceReload's only
                // reachable caller today re-applies the same instance);
                // real config changes go through ACTION_START, not this.
                server.startOrReloadService(lastKnownConfigJson ?: return@execute, OverrideOptions())
                lifecycle.startSucceeded()
                mainHandler.post { publishStatus(VpnCoreState.CONNECTED, tag) }
            } catch (e: Throwable) {
                failStart(e)
            }
        }
    }

    @Volatile
    private var lastKnownConfigJson: String? = null

    internal fun postLibboxNotification(notification: io.nekohasekai.libbox.Notification) {
        mainHandler.post {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        notification.identifier,
                        notification.typeName,
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
            }
            val builder = Notification.Builder(this, notification.identifier)
                .setContentTitle(notification.title)
                .setContentText(notification.body)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
            manager.notify(notification.typeID, builder.build())
        }
    }

    override fun onRevoke() {
        // The user revoked VPN permission from system settings -- Android
        // requires we tear down immediately, without waiting for a stop
        // Intent from the app.
        if (lifecycle.tryStop()) {
            mainHandler.post { publishStatus(VpnCoreState.DISCONNECTING, activeTag) }
            executor.execute { doStop(fromRevoke = true) }
        }
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        // By design (matching upstream's own client -- see
        // PlatformInterfaceWrapper/BoxService in
        // SagerNet/sing-box-for-android), onDestroy is only ever reached
        // AFTER a stop already ran to completion (via ACTION_STOP or
        // onRevoke, both of which call stopSelf() themselves): there is
        // normally no live core instance left to close here. Running the
        // blocking libbox closeService() call synchronously on whatever
        // thread onDestroy executes on (main, per the Service contract)
        // would risk an ANR for a case that shouldn't arise; this is a
        // deliberately narrow, fast-only safety net for a fd Android
        // itself may not have finished tearing down.
        tunFd?.let { runCatching { it.close() } }
        tunFd = null
        executor.shutdown()
        super.onDestroy()
    }

    private fun buildNotification(tag: String, connected: Boolean): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "VPN status",
                NotificationManager.IMPORTANCE_LOW,
            )
            manager.createNotificationChannel(channel)
        }
        val stopIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, SingBoxVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val title = if (connected) "Connected: $tag" else "Connecting: $tag"
        return Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .addAction(0, "Disconnect", stopIntent)
            .build()
    }

    companion object {
        private const val TAG = "SingBoxVpnService"
        private const val NOTIFICATION_CHANNEL_ID = "vpn_core_status"
        private const val NOTIFICATION_ID = 0x5B01

        const val ACTION_START = "app.singboxclient.vpn_core.action.START"
        const val ACTION_STOP = "app.singboxclient.vpn_core.action.STOP"
        private const val EXTRA_TAG = "tag"
        private const val EXTRA_CONFIG_JSON = "configJson"

        @Volatile
        private var libboxSetupDone = false

        /**
         * `libbox.Setup(SetupOptions)` must run exactly once per process
         * before any other libbox call (`experimental/libbox/setup.go`).
         * Uses this app's own private storage (`Context.filesDir`/
         * `Context.cacheDir`) rather than `getExternalFilesDir` (which
         * upstream's own client uses, but which can return null and
         * requires no permission difference on a modern minSdk -- using
         * only guaranteed-available private storage is a deliberate,
         * safer choice for a library embedded in an arbitrary host app
         * whose manifest this module doesn't own).
         */
        @Synchronized
        private fun ensureLibboxSetup(context: Context) {
            if (libboxSetupDone) return
            val baseDir = File(context.filesDir, "vpn_core")
            val workingDir = File(baseDir, "working")
            val tempDir = context.cacheDir
            baseDir.mkdirs()
            workingDir.mkdirs()
            Libbox.setup(
                SetupOptions().apply {
                    basePath = baseDir.path
                    workingPath = workingDir.path
                    tempPath = tempDir.path
                    fixAndroidStack = true
                    logMaxLines = 1000
                    debug = false
                },
            )
            Libbox.setMemoryLimit(true)
            runCatching { Libbox.redirectStderr(File(workingDir, "stderr.log").path) }
            libboxSetupDone = true
        }

        fun initialize(context: Context) {
            ensureLibboxSetup(context.applicationContext)
        }

        fun start(context: Context, tag: String, configJson: String) {
            ensureLibboxSetup(context.applicationContext)
            val intent = Intent(context, SingBoxVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TAG, tag)
                .putExtra(EXTRA_CONFIG_JSON, configJson)
            context.startService(intent)
        }

        fun currentStatus(): VpnCoreStatusSnapshot = lastStatus

        fun coreVersion(): String = try {
            Libbox.version()
        } catch (e: Throwable) {
            "unavailable: ${e.message}"
        }

        fun sanitizedLogs(maxLines: Int): List<String> {
            // Real log streaming (CommandServer's own log subscriber,
            // reachable via commandServer.start() + a command-client
            // connection) is follow-up work tracked in
            // docs/ARCHITECTURE.md -- this never returns raw config JSON
            // or a field named uuid/password/public_key/short_id, which
            // is the invariant that matters regardless of how much log
            // detail is available.
            return listOf(
                "[vpn_core] log streaming not yet wired to the command socket; " +
                    "current state: ${lastStatus.state.name.lowercase()}",
            )
        }

        private var listener: ((VpnCoreStatusSnapshot) -> Unit)? = null

        @Volatile
        private var lastStatus = VpnCoreStatusSnapshot(VpnCoreState.DISCONNECTED, null)

        private val statusHandler = Handler(Looper.getMainLooper())

        internal fun publishStatus(state: VpnCoreState, tag: String?) {
            lastStatus = VpnCoreStatusSnapshot(state, tag)
            val current = listener
            if (current == null) return
            if (Looper.myLooper() == Looper.getMainLooper()) {
                current(lastStatus)
            } else {
                statusHandler.post { listener?.invoke(lastStatus) }
            }
        }

        fun addStatusListener(l: (VpnCoreStatusSnapshot) -> Unit) {
            listener = l
            l(lastStatus)
        }

        fun clearStatusListener() {
            listener = null
        }
    }
}

enum class VpnCoreState { INVALID, DISCONNECTED, CONNECTING, CONNECTED, REASSERTING, DISCONNECTING }

data class VpnCoreStatusSnapshot(val state: VpnCoreState, val tag: String?) {
    fun toWire(): Map<String, Any?> = mapOf(
        "state" to state.name.lowercase(),
        "activeTag" to tag,
        "uplinkBytes" to 0,
        "downlinkBytes" to 0,
    )
}
