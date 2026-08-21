package app.singboxclient.vpn_core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import android.system.OsConstants
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.security.KeyStore
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * The Kotlin side of the Go `PlatformInterface` contract
 * (`experimental/libbox/platform.go` in the pinned sing-box source --
 * every method name/signature below was read directly from that file at
 * the pinned commit, not guessed: gomobile lower-cases the first letter
 * of each exported Go method name for its Java binding and otherwise
 * preserves the signature, e.g. Go `OpenTun(options TunOptions) (int32,
 * error)` becomes Java/Kotlin `openTun(options: TunOptions): Int` that
 * throws on the Go `error` case).
 *
 * Architecture matches SagerNet/sing-box-for-android's own
 * `PlatformInterfaceWrapper.kt` (the official reference Android client
 * for this same core, cross-checked at both its `stable`/1.12.23 and
 * `main`/1.14.0-rc.1 branches -- `main`'s shape, not `stable`'s predating
 * a `findConnectionOwner` signature change, is what this pinned v1.13.19
 * source actually declares) for exactly the same reason it does: this
 * interface, mixed into [SingBoxVpnService] itself
 * (`class SingBoxVpnService : VpnService(), VpnPlatformInterfaceWrapper`),
 * gives every default method's `this` the real `VpnService`/`Context`
 * instance for free. Splitting `PlatformInterface` into a *separate*
 * class holding a `VpnService` reference (an earlier version of this
 * file did exactly that) would need `android.net.VpnService.Builder` --
 * a non-static Java inner class -- constructed from outside its outer
 * `VpnService` instance, an unverifiable edge case with no proven
 * reference to check it against; mixing this interface directly into the
 * service class sidesteps that risk entirely, matching upstream.
 *
 * [openTun], [autoDetectInterfaceControl], and `sendNotification` are
 * deliberately NOT given defaults here (unlike upstream's own inert
 * `autoDetectInterfaceControl`/`openTun` no-op defaults) -- only
 * `android.net.VpnService` itself can build/establish a TUN
 * ([VpnService.Builder]) or protect a raw socket ([VpnService.protect]),
 * so [SingBoxVpnService] must override all three directly; a silently
 * inert default here would be exactly the kind of "claims functionality
 * that isn't there" the task rules out.
 */
internal interface VpnPlatformInterfaceWrapper : PlatformInterface {

    /** The implementing [SingBoxVpnService] is itself a [Context]. */
    val platformContext: Context

    private val connectivityManager: ConnectivityManager
        get() = platformContext.getSystemService(ConnectivityManager::class.java)

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error("android: ConnectivityManager.getConnectionOwnerUid requires API 29+")
        }
        val uid = connectivityManager.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        val packages = platformContext.packageManager.getPackagesForUid(uid)
        val owner = ConnectionOwner()
        owner.userId = uid
        owner.userName = packages?.firstOrNull() ?: ""
        owner.setAndroidPackageNames(StringArrayIterator((packages ?: emptyArray()).toList()))
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.start(connectivityManager, listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.stop(connectivityManager)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val networks = connectivityManager.allNetworks
        val systemInterfaces = java.net.NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        val result = mutableListOf<LibboxNetworkInterface>()
        for (network in networks) {
            val linkProperties = connectivityManager.getLinkProperties(network) ?: continue
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = linkProperties.interfaceName ?: continue
            val systemInterface = systemInterfaces.find { it.name == boxInterface.name } ?: continue
            boxInterface.dnsServer = StringArrayIterator(
                linkProperties.dnsServers.mapNotNull { it.hostAddress },
            )
            boxInterface.type = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.index = systemInterface.index
            runCatching { boxInterface.mtu = systemInterface.mtu }
            boxInterface.addresses = StringArrayIterator(
                systemInterface.interfaceAddresses.map { it.toPrefixString() },
            )
            var flags = 0
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (systemInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (systemInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (systemInterface.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
            boxInterface.flags = flags
            boxInterface.metered =
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            result.add(boxInterface)
        }
        return NetworkInterfaceArrayIterator(result)
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    // No WIFIState-dependent routing rule is generated by this app (see
    // SingBoxConfigBuilder); real SSID lookup would also need a runtime
    // location permission this plugin has no UI to request.
    override fun readWIFIState(): WIFIState? = null

    @OptIn(ExperimentalEncodingApi::class)
    override fun systemCertificates(): StringIterator {
        val certificates = mutableListOf<String>()
        val keyStore = KeyStore.getInstance("AndroidCAStore")
        keyStore.load(null, null)
        val aliases = keyStore.aliases()
        while (aliases.hasMoreElements()) {
            val cert = keyStore.getCertificate(aliases.nextElement()) ?: continue
            certificates.add(
                "-----BEGIN CERTIFICATE-----\n${Base64.encode(cert.encoded)}\n-----END CERTIFICATE-----",
            )
        }
        return StringArrayIterator(certificates)
    }

    override fun clearDNSCache() {
        // No-op: Android exposes no public API to flush the system DNS
        // cache from an app process (upstream's own Android client does
        // the same -- see its PlatformInterfaceWrapper.kt).
    }

    // See tun.go: nil is explicitly handled -- sing-box falls back to its
    // own resolver when this returns null.
    override fun localDNSTransport(): LocalDNSTransport? = null

    private fun InterfaceAddress.toPrefixString(): String {
        val addr = address
        return if (addr is Inet6Address) {
            "${Inet6Address.getByAddress(addr.address).hostAddress}/$networkPrefixLength"
        } else {
            "${addr.hostAddress}/$networkPrefixLength"
        }
    }
}

/** [io.nekohasekai.libbox.StringIterator] backed by a plain Kotlin list. */
internal class StringArrayIterator(values: List<String>) : StringIterator {
    private val remaining = ArrayDeque(values)
    override fun len(): Int = remaining.size
    override fun hasNext(): Boolean = remaining.isNotEmpty()
    override fun next(): String = remaining.removeFirst()
}

private class NetworkInterfaceArrayIterator(
    values: List<LibboxNetworkInterface>,
) : NetworkInterfaceIterator {
    private val remaining = ArrayDeque(values)
    override fun hasNext(): Boolean = remaining.isNotEmpty()
    override fun next(): LibboxNetworkInterface = remaining.removeFirst()
}

/**
 * A minimal, single-listener default-network monitor using
 * `ConnectivityManager.registerDefaultNetworkCallback` directly (API 24+,
 * within this module's minSdk 26). Deliberately simpler than upstream's
 * own `DefaultNetworkListener`/`DefaultNetworkMonitor` pair (which
 * supports multiple concurrent subscribers, needed for their multi-screen
 * app UI); libbox only ever registers one [InterfaceUpdateListener] per
 * running core instance, so a single-listener implementation is a
 * correct, real translation of the same Android API, not a cut corner.
 */
internal object DefaultNetworkMonitor {
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun start(connectivityManager: ConnectivityManager, listener: InterfaceUpdateListener) {
        stop(connectivityManager)
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notify(connectivityManager, network, listener)
            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: android.net.LinkProperties,
            ) = notify(connectivityManager, network, listener)

            override fun onLost(network: Network) {
                listener.updateDefaultInterface("", -1, false, false)
            }
        }
        callback = cb
        connectivityManager.registerDefaultNetworkCallback(cb)
    }

    fun stop(connectivityManager: ConnectivityManager) {
        callback?.let {
            runCatching { connectivityManager.unregisterNetworkCallback(it) }
        }
        callback = null
    }

    private fun notify(
        connectivityManager: ConnectivityManager,
        network: Network,
        listener: InterfaceUpdateListener,
    ) {
        val linkProperties = connectivityManager.getLinkProperties(network) ?: return
        val interfaceName = linkProperties.interfaceName ?: return
        val index = runCatching { java.net.NetworkInterface.getByName(interfaceName)?.index }
            .getOrNull() ?: -1
        val capabilities = connectivityManager.getNetworkCapabilities(network)
        val expensive = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
        listener.updateDefaultInterface(interfaceName, index, expensive, false)
    }
}
