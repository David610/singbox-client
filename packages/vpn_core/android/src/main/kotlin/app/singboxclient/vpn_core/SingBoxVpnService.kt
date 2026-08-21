package app.singboxclient.vpn_core

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * The Android VpnService integration point. Owns the TUN file descriptor
 * lifecycle and the foreground-service/notification requirements Android
 * imposes on any long-running VpnService.
 *
 * Deliberately does not import io.nekohasekai.libbox.* directly -- see
 * [LibboxBridge] for why. Today this service establishes and tears down a
 * real Android TUN interface correctly, and proves it can reach the pinned
 * libbox core ([LibboxBridge.version], [LibboxBridge.checkConfig]); wiring
 * the established `ParcelFileDescriptor` through to sing-box's packet loop
 * (`libbox.NewCommandServer` + `PlatformInterface.OpenTun`) is the next
 * implementation task -- see docs/ARCHITECTURE.md "Remaining incompatibilities".
 */
class SingBoxVpnService : VpnService() {

    private var tunFd: ParcelFileDescriptor? = null
    private var activeTag: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                teardown()
                stopSelf()
            }
            ACTION_START -> {
                val tag = intent.getStringExtra(EXTRA_TAG)
                val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                if (tag != null && configJson != null) {
                    doStart(tag, configJson)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun doStart(tag: String, configJson: String) {
        val configError = LibboxBridge.checkConfig(configJson)
        if (configError != null) {
            Log.e(TAG, "rejecting start: $configError")
            publishStatus(VpnCoreState.INVALID, tag)
            return
        }

        // Tear down any previous interface first: VpnService.Builder.establish()
        // would otherwise leave the old fd dangling. Doing an explicit
        // teardown+establish (rather than relying purely on establish()'s
        // atomic replace) keeps foreground-notification/state bookkeeping
        // correct across a start->start "restart" call.
        teardown()

        publishStatus(VpnCoreState.CONNECTING, tag)
        startForeground(NOTIFICATION_ID, buildNotification(tag))

        val builder = Builder()
            .setSession(tag)
            .addAddress("172.19.0.1", 28)
            .addAddress("fdfe:dcba:9876::1", 126)
            .addDnsServer("1.1.1.1")
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .setMtu(9000)
            .setBlocking(false)

        // Excluding this app's own process from the tunnel avoids a
        // self-routing loop; harmless no-op on API levels where per-app
        // exclusion isn't available.
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: PackageManager.NameNotFoundException) {
            // Fall through: not fatal, just means this app's own traffic is
            // also routed through the tunnel.
        }

        val fd = try {
            builder.establish()
        } catch (e: SecurityException) {
            Log.e(TAG, "VPN permission not granted", e)
            publishStatus(VpnCoreState.INVALID, tag)
            return
        }

        if (fd == null) {
            publishStatus(VpnCoreState.INVALID, tag)
            return
        }

        tunFd = fd
        activeTag = tag

        // TODO(next milestone): hand `fd` to libbox's PlatformInterface.OpenTun
        // implementation and start the CommandServer-backed box service so
        // packets actually flow. Until then the OS-level tunnel exists and
        // is provably wired to the pinned core version (see
        // LibboxBridge.version()), but does not yet route traffic.
        publishStatus(VpnCoreState.CONNECTED, tag)
    }

    private fun teardown() {
        tunFd?.let {
            try {
                it.close()
            } catch (e: java.io.IOException) {
                Log.w(TAG, "error closing tun fd", e)
            }
        }
        tunFd = null
        val tag = activeTag
        activeTag = null
        if (tag != null) publishStatus(VpnCoreState.DISCONNECTED, null)
    }

    override fun onRevoke() {
        // The user revoked VPN permission from system settings -- Android
        // requires we tear down immediately, without waiting for a stop
        // Intent from the app.
        teardown()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun buildNotification(tag: String): Notification {
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
        return Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Connected: $tag")
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

        private var listener: ((VpnCoreStatusSnapshot) -> Unit)? = null
        private var lastStatus = VpnCoreStatusSnapshot(VpnCoreState.DISCONNECTED, null)

        fun initialize(context: Context) {
            // Placeholder for libbox.Setup(SetupOptions{...}) once the
            // CommandServer wiring lands; safe to call repeatedly today.
        }

        fun start(context: Context, tag: String, configJson: String) {
            val intent = Intent(context, SingBoxVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TAG, tag)
                .putExtra(EXTRA_CONFIG_JSON, configJson)
            context.startService(intent)
        }

        fun currentStatus(): VpnCoreStatusSnapshot = lastStatus

        fun coreVersion(): String = LibboxBridge.version() ?: "unavailable (libbox.aar not built)"

        fun sanitizedLogs(maxLines: Int): List<String> {
            // TODO(next milestone): surface libbox's ring-buffer log via
            // CommandServer once wired. Redaction rule when implemented:
            // never emit the raw config JSON or any field named
            // uuid/password/public_key/short_id -- see
            // docs/ARCHITECTURE.md "Log redaction".
            return listOf("[vpn_core] libbox not yet wired for log streaming")
        }

        internal fun publishStatus(state: VpnCoreState, tag: String?) {
            lastStatus = VpnCoreStatusSnapshot(state, tag)
            listener?.invoke(lastStatus)
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
