import Foundation

/// The shared seam between the app shell and whichever brain drives the agent — the
/// classic blob.js-parity `StateMachine` or the `EmergentBrain`. The shell holds one
/// `AgentBrain` existential picked from config at launch, so swapping brains is pure
/// configuration: the frame driver and drag wiring never branch on which one is live.
///
/// `AnyObject`-bound because both conformers are reference types holding injected
/// RNG/clock, and the shell needs stable identity across the app's lifetime.
public protocol AgentBrain: AnyObject {
    /// Boots the full `AgentState` at the primary display's center. Conformers that
    /// need extra boot inputs (the emergent brain's temperament) take them at
    /// construction time.
    func makeInitialState(screens: [ScreenInfo], avatarSize: Size, now: Double) -> AgentState

    /// Advances one display frame. `dt` in seconds; the brain reads `now` from its
    /// injected clock.
    func tick(state: inout AgentState, dt: Double)

    /// Whether the shell should stop driving frames entirely (decision log D18's sleep
    /// tier). The shell keys the frame clock's lifecycle off this one bit instead of
    /// reading any brain-internal state; defaults to never, so the classic brain sleeps
    /// by contract rather than by accident.
    func wantsRuntimeSleep(state: AgentState) -> Bool

    // The drag seam — the one interaction that bypasses the normal tick flow, driven
    // straight from the shell's mouse callbacks.
    func beginDrag(state: inout AgentState)
    func updateDrag(state: inout AgentState)
    func endDrag(state: inout AgentState, now: Double)
}

extension AgentBrain {
    public func wantsRuntimeSleep(state: AgentState) -> Bool { false }
}

/// Optional brain capability: live temperament switching (decision log D10/D19). The
/// shell keys the "Temperament" menu's presence off `brain as? TemperamentControlling`,
/// never off a concrete brain type — the next brain capability is another protocol
/// like this one, not another downcast.
public protocol TemperamentControlling: AgentBrain {
    /// Swaps the temperament vector in place; drives ease toward the new baselines via
    /// their own dynamics.
    func adoptTemperament(_ temperament: Temperament, state: inout AgentState)
}

extension StateMachine: AgentBrain {}

extension EmergentBrain: AgentBrain, TemperamentControlling {
    /// Sleep is the power ladder's bottom tier — the brain has already committed the
    /// rest pose by the time it reports `.sleeping` (see `runCognition`). An active timer
    /// vetoes sleep even at that tier — the shell must keep the frame clock running so
    /// the on-screen row keeps counting and the pause button stays clickable.
    public func wantsRuntimeSleep(state: AgentState) -> Bool {
        state.mind?.power == .sleeping && state.timer?.active != true
    }
}
