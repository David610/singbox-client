package app.singboxclient.vpn_core

import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.SystemProxyStatus

/**
 * The Go `CommandServerHandler` contract
 * (`experimental/libbox/command_server.go` in the pinned source):
 *
 * ```go
 * type CommandServerHandler interface {
 *     ServiceStop() error
 *     ServiceReload() error
 *     GetSystemProxyStatus() (*SystemProxyStatus, error)
 *     SetSystemProxyEnabled(enabled bool) error
 *     WriteDebugMessage(message string)
 * }
 * ```
 *
 * These callbacks only ever fire from `CommandServer`'s own gRPC
 * `StopService`/`ReloadService` RPC handlers (`daemon/started_service.go`
 * `StopService`/`ReloadService`), which in turn require
 * `CommandServer.start()` to have been called to open its Unix-socket
 * listener. This module never calls `start()` -- [SingBoxVpnService] and
 * [VpnCorePlugin] run in the same Android process (no separate
 * UI/tunnel-process split, unlike upstream's own client, which supports a
 * standalone CLI/companion talking to a running tunnel process over that
 * socket) -- so these are not reachable via that path today. They are
 * still implemented for real, routed into the same stop/reload path
 * [SingBoxVpnService] itself uses, both because the interface requires an
 * implementation and so a future command-socket consumer (if ever added)
 * gets correct behavior for free rather than a silent no-op.
 *
 * "System proxy" (Android's HTTP proxy override, distinct from the VPN
 * tunnel itself) is not a feature this client exposes -- [getSystemProxyStatus]
 * honestly reports it as unavailable rather than fabricating support.
 */
internal class VpnCommandServerHandler(
    private val vpnService: SingBoxVpnService,
) : CommandServerHandler {

    override fun serviceStop() {
        vpnService.requestStop()
    }

    override fun serviceReload() {
        vpnService.requestReload()
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        return SystemProxyStatus().apply {
            available = false
            enabled = false
        }
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        // No-op: system proxy isn't supported (see class doc). Silently
        // ignoring rather than throwing matches upstream's own tolerance
        // for a no-op reload here, and setSystemProxyEnabled is only ever
        // invoked in response to the same unreachable RPC path described
        // above.
    }

    override fun writeDebugMessage(message: String?) {
        if (message != null) {
            android.util.Log.d("libbox", message)
        }
    }
}
