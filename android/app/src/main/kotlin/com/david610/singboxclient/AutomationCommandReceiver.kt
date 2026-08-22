package com.david610.singboxclient

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import app.singboxclient.vpn_core.SingBoxVpnService
import app.singboxclient.vpn_core.VpnCoreState

/**
 * External automation entry point (Tasker-style broadcast intents).
 * Rewritten against the real `app.singboxclient.vpn_core.SingBoxVpnService`
 * -- the old `io.nebula.vpn_service.VpnServiceImpl` this referenced no
 * longer exists post-migration (see docs/ARCHITECTURE.md §9), including
 * its allowed-sender-package allowlist file, which does not have an
 * equivalent here.
 *
 * DISCONNECT is real (`SingBoxVpnService.ACTION_STOP`, the same API the
 * Flutter-facing plugin channel itself uses). CONNECT/RECONNECT are NOT:
 * `SingBoxVpnService.start()` requires a `tag` + fully-built `configJson`
 * for the selected profile, which only the running Flutter engine
 * currently knows how to build (see
 * `lib/app/modules/vpn_service_state.dart`/`SingboxConfigBuilder`). There
 * is no persisted "last profile" this receiver can safely reconnect with
 * cold, and fabricating one (or faking a CONNECTED state) is worse than
 * leaving this a known, honestly-logged gap.
 */
class AutomationCommandReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_CONNECT = "com.david610.singboxclient.action.CONNECT"
        const val ACTION_DISCONNECT = "com.david610.singboxclient.action.DISCONNECT"
        const val ACTION_RECONNECT = "com.david610.singboxclient.action.RECONNECT"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_CONNECT -> connect(context)
            ACTION_DISCONNECT -> disconnect(context)
            ACTION_RECONNECT -> reconnect(context)
        }
    }

    private fun connect(context: Context) {
        print(
            "AutomationCommandReceiver: CONNECT isn't wired yet (needs the active " +
                "profile's tag+configJson from the Flutter side) -- ignoring.\n"
        )
    }

    private fun disconnect(context: Context) {
        if (SingBoxVpnService.currentStatus().state == VpnCoreState.DISCONNECTED) return
        val intent = Intent(context, SingBoxVpnService::class.java).setAction(SingBoxVpnService.ACTION_STOP)
        context.startService(intent)
    }

    private fun reconnect(context: Context) {
        disconnect(context)
        connect(context)
    }
}
