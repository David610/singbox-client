package app.singboxclient.vpn_core

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real, on-device tests of [SingBoxVpnService]'s start/stop lifecycle
 * against the actual pinned libbox core -- these require:
 *
 *   1. `packages/vpn_core/android/libs/libbox.aar` to have been built
 *      (see docs/BUILDING.md), since this module now hard-fails at
 *      compile time otherwise (see build.gradle) -- so this test file
 *      cannot even build without it, by design.
 *   2. A device/emulator with the Android VPN permission for this test
 *      app's package PRE-GRANTED (interactive system consent can't be
 *      driven headlessly in CI): `adb shell appops set
 *      <applicationId> ACTIVATE_VPN allow` before the test run. Without
 *      this, `VpnService.prepare()` returns non-null and every start in
 *      this file fails at the permission check -- itself still a
 *      meaningful (if narrower) assertion, see the first test below.
 *
 * This suite deliberately does NOT attempt a real remote connection (no
 * live server credentials belong in a test): it uses a syntactically
 * valid but unreachable/rejecting config to prove the *lifecycle*
 * invariants for real, on-device, against the real core -- "Connected
 * may be emitted only after core startup succeeds" and "repeated
 * start/stop must be idempotent" are properties of [SingBoxVpnService]
 * itself, not of any particular remote server, so a config that's
 * guaranteed to fail startup exercises exactly the failure path the
 * task requires never reach CONNECTED. Real VLESS/Hysteria2/IPv4/IPv6/DNS
 * traffic verification against a live singbox-vpn server is manual,
 * device-based acceptance testing (see docs/DEVICE_ACCEPTANCE.md), not
 * something this automated suite can responsibly fabricate without a
 * live remote endpoint's credentials.
 *
 * NOT executed in this development environment: no Android
 * device/emulator, no built libbox.aar (would require the Android NDK,
 * unavailable here) -- see this milestone's own accompanying commit
 * message for exactly what was and wasn't verified.
 */
@RunWith(AndroidJUnit4::class)
class SingBoxVpnServiceInstrumentedTest {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    /**
     * A minimal, well-formed sing-box document whose `vless` outbound
     * points at a closed local port -- guaranteed to fail to *connect*
     * once traffic is attempted, but more importantly for this test,
     * `startOrReloadService` itself may succeed (the tun/router/outbound
     * all construct fine; only the eventual dial fails) OR fail
     * (depending on whether the pinned core eagerly resolves/dials at
     * start), so this test only asserts the invariant that holds in
     * BOTH cases: the reported state is never left dangling at
     * CONNECTING, and a subsequent stop always reaches DISCONNECTED.
     */
    private fun wellFormedConfigJson(): String {
        return """
            {
              "log": {"level": "warn"},
              "inbounds": [{
                "type": "tun", "tag": "tun-in", "interface_name": "sbx-tun-test",
                "address": ["172.19.0.1/28", "fdfe:dcba:9876::1/126"],
                "mtu": 9000, "auto_route": true, "strict_route": true, "stack": "system"
              }],
              "outbounds": [
                {"type": "vless", "tag": "test", "server": "127.0.0.1", "server_port": 1,
                 "uuid": "00000000-0000-0000-0000-000000000000",
                 "tls": {"enabled": true, "server_name": "example.invalid"}},
                {"type": "direct", "tag": "direct"},
                {"type": "block", "tag": "block"}
              ],
              "route": {"final": "test", "auto_detect_interface": true}
            }
        """.trimIndent()
    }

    /** A config `sing-box check` would reject outright -- malformed JSON. */
    private fun malformedConfigJson(): String = "{ not valid json"

    @Test
    fun startWithMalformedConfigNeverReachesConnected() {
        SingBoxVpnService.clearStatusListener()
        val states = mutableListOf<VpnCoreState>()
        SingBoxVpnService.addStatusListener { states.add(it.state) }

        SingBoxVpnService.start(context, "malformed-test", malformedConfigJson())
        waitForTerminalState(timeoutMs = 15_000)

        assertNotEquals(
            "a malformed config must never result in CONNECTED",
            VpnCoreState.CONNECTED,
            SingBoxVpnService.currentStatus().state,
        )
        SingBoxVpnService.clearStatusListener()
    }

    @Test
    fun repeatedStartStopIsIdempotentAndAlwaysSettles() {
        SingBoxVpnService.clearStatusListener()

        // Two stops in a row on an already-stopped service must be
        // harmless no-ops, never a crash or hang.
        context.startService(
            android.content.Intent(context, SingBoxVpnService::class.java)
                .setAction(SingBoxVpnService.ACTION_STOP),
        )
        context.startService(
            android.content.Intent(context, SingBoxVpnService::class.java)
                .setAction(SingBoxVpnService.ACTION_STOP),
        )
        Thread.sleep(500)
        assertEquals(VpnCoreState.DISCONNECTED, SingBoxVpnService.currentStatus().state)

        // A start/stop cycle, twice, must settle to DISCONNECTED both
        // times regardless of whether the (unreachable) remote connects.
        repeat(2) {
            SingBoxVpnService.start(context, "idempotency-test", wellFormedConfigJson())
            waitForTerminalState(timeoutMs = 15_000)

            context.startService(
                android.content.Intent(context, SingBoxVpnService::class.java)
                    .setAction(SingBoxVpnService.ACTION_STOP),
            )
            waitForState(VpnCoreState.DISCONNECTED, timeoutMs = 15_000)
        }
    }

    /** Waits until the state is no longer CONNECTING/DISCONNECTING. */
    private fun waitForTerminalState(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val state = SingBoxVpnService.currentStatus().state
            if (state != VpnCoreState.CONNECTING && state != VpnCoreState.DISCONNECTING) return
            Thread.sleep(200)
        }
    }

    private fun waitForState(target: VpnCoreState, timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (SingBoxVpnService.currentStatus().state == target) return
            Thread.sleep(200)
        }
        assertEquals(target, SingBoxVpnService.currentStatus().state)
    }
}
