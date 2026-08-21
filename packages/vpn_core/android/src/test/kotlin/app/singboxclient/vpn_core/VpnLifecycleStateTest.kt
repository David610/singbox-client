package app.singboxclient.vpn_core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-JVM unit tests for [VpnLifecycleStateMachine] -- no Android
 * framework, no libbox, so these run under a plain `test` source set
 * (`./gradlew :vpn_core:testDebugUnitTest`), not `androidTest`. They
 * verify exactly the properties the task requires of the state machine
 * itself: a failed start can never reach CONNECTED, and repeated
 * start/stop is idempotent (a no-op, not a crash or a second concurrent
 * attempt).
 */
class VpnLifecycleStateTest {

    @Test
    fun `fresh machine starts disconnected`() {
        val machine = VpnLifecycleStateMachine()
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)
    }

    @Test
    fun `successful start reaches connected only through connecting`() {
        val machine = VpnLifecycleStateMachine()
        assertTrue(machine.tryStart())
        assertEquals(VpnLifecycleState.CONNECTING, machine.state)
        machine.startSucceeded()
        assertEquals(VpnLifecycleState.CONNECTED, machine.state)
    }

    @Test
    fun `a failed start never reaches connected`() {
        val machine = VpnLifecycleStateMachine()
        assertTrue(machine.tryStart())
        machine.startFailed()
        assertEquals(VpnLifecycleState.INVALID, machine.state)
        // startSucceeded() arriving late (e.g. a stray callback after the
        // failure path already ran) must not resurrect CONNECTED from a
        // non-CONNECTING state.
        machine.startSucceeded()
        assertEquals(VpnLifecycleState.INVALID, machine.state)
    }

    @Test
    fun `start_succeeded from a non-connecting state is a no-op`() {
        val machine = VpnLifecycleStateMachine()
        machine.startSucceeded()
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)
    }

    @Test
    fun `a second concurrent start is rejected, not raced`() {
        val machine = VpnLifecycleStateMachine()
        assertTrue(machine.tryStart())
        assertFalse(
            "a second start while the first is still CONNECTING must be rejected",
            machine.tryStart(),
        )
        assertEquals(VpnLifecycleState.CONNECTING, machine.state)
    }

    @Test
    fun `starting again once connected is allowed -- restart is a reload, not rejected`() {
        // VpnCorePlugin.restart is implemented as a plain start() while
        // already connected; libbox's own StartOrReloadService treats
        // this as "close the running instance, then start the new one",
        // so the state machine must allow it rather than reject it.
        val machine = VpnLifecycleStateMachine()
        machine.tryStart()
        machine.startSucceeded()
        assertTrue(machine.tryStart())
        assertEquals(VpnLifecycleState.CONNECTING, machine.state)
        machine.startSucceeded()
        assertEquals(VpnLifecycleState.CONNECTED, machine.state)
    }

    @Test
    fun `stop from connected completes to disconnected`() {
        val machine = VpnLifecycleStateMachine()
        machine.tryStart()
        machine.startSucceeded()
        assertTrue(machine.tryStop())
        assertEquals(VpnLifecycleState.DISCONNECTING, machine.state)
        machine.stopCompleted()
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)
    }

    @Test
    fun `repeated stop is idempotent -- a no-op, not an error`() {
        val machine = VpnLifecycleStateMachine()
        assertFalse(
            "stop on an already-disconnected machine must be a harmless no-op",
            machine.tryStop(),
        )
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)

        machine.tryStart()
        machine.startSucceeded()
        assertTrue(machine.tryStop())
        machine.stopCompleted()
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)

        // A second stop call after the first already completed teardown.
        assertFalse(machine.tryStop())
        assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)
    }

    @Test
    fun `stop while still connecting is honored (cancel an in-flight start)`() {
        val machine = VpnLifecycleStateMachine()
        machine.tryStart()
        assertTrue(machine.tryStop())
        assertEquals(VpnLifecycleState.DISCONNECTING, machine.state)
    }

    @Test
    fun `a full start-stop-start-stop cycle is repeatable`() {
        val machine = VpnLifecycleStateMachine()
        repeat(3) {
            assertTrue(machine.tryStart())
            machine.startSucceeded()
            assertEquals(VpnLifecycleState.CONNECTED, machine.state)
            assertTrue(machine.tryStop())
            machine.stopCompleted()
            assertEquals(VpnLifecycleState.DISCONNECTED, machine.state)
        }
    }

    @Test
    fun `restarting after a failure is allowed`() {
        val machine = VpnLifecycleStateMachine()
        machine.tryStart()
        machine.startFailed()
        assertEquals(VpnLifecycleState.INVALID, machine.state)
        assertTrue(
            "INVALID must be a legal entry point for a retry start",
            machine.tryStart(),
        )
        machine.startSucceeded()
        assertEquals(VpnLifecycleState.CONNECTED, machine.state)
    }
}
