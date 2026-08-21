package app.singboxclient.vpn_core

/**
 * The Android VPN lifecycle's state machine, extracted as a pure Kotlin
 * class (no Android/libbox dependency) specifically so it's unit-testable
 * on the plain JVM (see `src/test/kotlin/.../VpnLifecycleStateTest.kt`) --
 * the property under test ("start failure cannot result in Connected",
 * "repeated start/stop must be idempotent") is a property of this state
 * machine's transition table, independent of whether libbox is actually
 * present.
 *
 * Mirrors [VpnCoreState] (the wire-visible enum) but is a distinct type:
 * this one additionally tracks in-flight start attempts so a second
 * concurrent `start()` while one is already running is rejected rather
 * than racing two libbox instances against the same TUN.
 */
internal enum class VpnLifecycleState {
    /** No active or in-flight tunnel. A legal entry point for a start. */
    DISCONNECTED,

    /** A start attempt is in progress: TUN not yet (or partially) established. */
    CONNECTING,

    /** libbox's `StartOrReloadService` returned successfully. */
    CONNECTED,

    /** A stop (or teardown-before-retry) is in progress. */
    DISCONNECTING,

    /** The most recent start attempt failed, or config/permission was rejected. */
    INVALID,
}

/**
 * Legal actions against the state machine. [START] covers both a fresh
 * connect and a reconnect/restart with a new config (matching
 * `VpnCorePlugin.restart`, which is implemented as a plain `start()` --
 * see that file's own comment on why no separate stop is needed).
 */
internal enum class VpnLifecycleAction { START, START_SUCCEEDED, START_FAILED, STOP, STOP_COMPLETED }

/**
 * A minimal, explicit transition table. [reduce] never throws: an action
 * that isn't legal from the current state returns the current state
 * unchanged (a no-op), which is exactly the idempotency the task requires
 * -- e.g. [VpnLifecycleAction.STOP] while already [VpnLifecycleState.DISCONNECTED]
 * is a no-op, not an error, and a second [VpnLifecycleAction.START] while
 * one is already [VpnLifecycleState.CONNECTING] is rejected (returns
 * `false` from [VpnLifecycleStateMachine.tryStart], see below) rather
 * than accepted and raced.
 */
internal object VpnLifecycleTransitions {
    fun reduce(current: VpnLifecycleState, action: VpnLifecycleAction): VpnLifecycleState {
        return when (action) {
            VpnLifecycleAction.START -> when (current) {
                // CONNECTED is a legal START source, not just DISCONNECTED/
                // INVALID: VpnCorePlugin's `restart` is implemented as a
                // plain `start()` with a new config, which libbox's own
                // `StartOrReloadService` treats as "close the running
                // instance, then start the new one" -- see
                // daemon/started_service.go. Rejecting it here would
                // break restart-while-connected.
                VpnLifecycleState.DISCONNECTED,
                VpnLifecycleState.INVALID,
                VpnLifecycleState.CONNECTED,
                -> VpnLifecycleState.CONNECTING
                // Already connecting/disconnecting: no-op, the caller
                // must check tryStart()'s return first to detect this and
                // reject the duplicate/racing request outright (see
                // VpnLifecycleStateMachine.tryStart).
                else -> current
            }
            VpnLifecycleAction.START_SUCCEEDED -> when (current) {
                VpnLifecycleState.CONNECTING -> VpnLifecycleState.CONNECTED
                else -> current
            }
            VpnLifecycleAction.START_FAILED -> when (current) {
                VpnLifecycleState.CONNECTING -> VpnLifecycleState.INVALID
                else -> current
            }
            VpnLifecycleAction.STOP -> when (current) {
                VpnLifecycleState.CONNECTED, VpnLifecycleState.CONNECTING -> VpnLifecycleState.DISCONNECTING
                // Already disconnected/invalid/disconnecting: no-op --
                // this is the idempotent-stop requirement.
                else -> current
            }
            VpnLifecycleAction.STOP_COMPLETED -> when (current) {
                VpnLifecycleState.DISCONNECTING -> VpnLifecycleState.DISCONNECTED
                else -> current
            }
        }
    }
}

/**
 * NOT thread-confined: [SingBoxVpnService] calls `tryStart`/`tryStop`
 * from Android's main thread (inside `onStartCommand`) but
 * `startSucceeded`/`startFailed`/`stopCompleted` from its single-thread
 * libbox executor -- two different threads mutating the same state
 * genuinely can interleave (e.g. a stop request arriving while a start is
 * mid-flight on the executor). Every method that reads-then-writes
 * [state] is `@Synchronized` on `this` for exactly that reason: a plain
 * `var` here would be a real lost-update race, not a theoretical one.
 */
internal class VpnLifecycleStateMachine(initial: VpnLifecycleState = VpnLifecycleState.DISCONNECTED) {
    @Volatile
    var state: VpnLifecycleState = initial
        private set

    /**
     * Returns true and transitions to CONNECTING if a start (fresh
     * connect, retry after failure, or reload/restart while already
     * connected) may proceed. Only rejects a start that would race one
     * already in flight (CONNECTING) or a stop in progress (DISCONNECTING).
     */
    @Synchronized
    fun tryStart(): Boolean {
        if (state == VpnLifecycleState.CONNECTING || state == VpnLifecycleState.DISCONNECTING) return false
        state = VpnLifecycleTransitions.reduce(state, VpnLifecycleAction.START)
        return true
    }

    @Synchronized
    fun startSucceeded() {
        state = VpnLifecycleTransitions.reduce(state, VpnLifecycleAction.START_SUCCEEDED)
    }

    @Synchronized
    fun startFailed() {
        state = VpnLifecycleTransitions.reduce(state, VpnLifecycleAction.START_FAILED)
    }

    /** Returns true if a teardown should actually run (state was CONNECTED/CONNECTING). */
    @Synchronized
    fun tryStop(): Boolean {
        if (state != VpnLifecycleState.CONNECTED && state != VpnLifecycleState.CONNECTING) return false
        state = VpnLifecycleTransitions.reduce(state, VpnLifecycleAction.STOP)
        return true
    }

    @Synchronized
    fun stopCompleted() {
        state = VpnLifecycleTransitions.reduce(state, VpnLifecycleAction.STOP_COMPLETED)
    }
}
