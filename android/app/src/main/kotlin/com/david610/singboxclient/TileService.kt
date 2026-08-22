package com.david610.singboxclient

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import app.singboxclient.vpn_core.SingBoxVpnService
import app.singboxclient.vpn_core.VpnCoreState

/**
 * Quick Settings tile. Rewritten against the real, pinned-core-backed
 * `app.singboxclient.vpn_core.SingBoxVpnService` (the old
 * `io.nebula.vpn_service.VpnServiceImpl` this referenced no longer
 * exists post-migration -- see docs/ARCHITECTURE.md §9). Status display
 * and disconnect are real: `SingBoxVpnService.currentStatus()`/
 * `ACTION_STOP` are the same in-process static API the Dart-facing
 * plugin channel itself uses, not a fabricated/guessed one.
 *
 * Connecting a NEW tunnel from this tile is NOT wired: unlike the old
 * service, `SingBoxVpnService.start()` requires a `tag` + fully-built
 * `configJson` for the selected profile, which only the running Flutter
 * engine currently knows how to build (see
 * `lib/app/modules/vpn_service_state.dart`/`SingboxConfigBuilder`). There
 * is no persisted "last profile" this tile can safely reconnect with
 * cold, and fabricating one (or faking a CONNECTED state) is worse than
 * leaving this a known, honestly-logged gap -- so `onClick()` only
 * handles the disconnect direction until that config hand-off exists.
 */
@RequiresApi(24)
class TileService : TileService() {
    override fun onClick() {
        super.onClick()
        val state = SingBoxVpnService.currentStatus().state
        if (state == VpnCoreState.CONNECTED || state == VpnCoreState.CONNECTING) {
            val intent =
                    Intent(this, SingBoxVpnService::class.java).setAction(
                            SingBoxVpnService.ACTION_STOP
                    )
            startService(intent)
        } else {
            writeLog(
                    "onClick: starting a new tunnel from the tile isn't wired yet " +
                            "(needs the active profile's tag+configJson from the Flutter " +
                            "side) -- ignoring."
            )
        }
        update()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        update()
    }

    override fun onStartListening() {
        super.onStartListening()
        update()
    }

    // Deliberately does NOT call SingBoxVpnService.addStatusListener/
    // clearStatusListener: that is a single-slot listener already owned by
    // VpnCorePlugin's EventChannel bridge to Flutter (see
    // VpnCorePlugin.kt) -- a second caller registering there would race
    // with and silently replace the plugin's own listener. `currentStatus()`
    // is a plain read with no such side effect, so this tile only polls it,
    // same as the system already does by calling onStartListening()
    // whenever the Quick Settings panel opens.

    private fun update() {
        val state = SingBoxVpnService.currentStatus().state
        qsTile?.apply {
            this.state =
                    when (state) {
                        VpnCoreState.CONNECTED -> Tile.STATE_ACTIVE
                        VpnCoreState.DISCONNECTED -> Tile.STATE_INACTIVE
                        else -> Tile.STATE_UNAVAILABLE
                    }
            updateTile()
        }
    }

    private fun writeLog(message: String) {
        print("TileService writeLog: $message\n")
    }
}
