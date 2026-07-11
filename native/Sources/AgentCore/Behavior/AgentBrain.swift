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
    /// need extra boot inputs (the emergent brain's temperament) expose richer
    /// overloads; this one uses their defaults.
    func makeInitialState(screens: [ScreenInfo], avatarSize: Size, now: Double) -> AgentState

    /// Advances one display frame. `dt` in seconds; the brain reads `now` from its
    /// injected clock.
    func tick(state: inout AgentState, dt: Double)

    // The drag seam — the one interaction that bypasses the normal tick flow, driven
    // straight from the shell's mouse callbacks.
    func beginDrag(state: inout AgentState)
    func updateDrag(state: inout AgentState)
    func endDrag(state: inout AgentState, now: Double)
}

extension StateMachine: AgentBrain {}

extension EmergentBrain: AgentBrain {
    /// Protocol boot: the brain's configured boot temperament (`.calm` unless the shell
    /// passed the persisted preset at construction).
    public func makeInitialState(
        screens: [ScreenInfo], avatarSize: Size, now: Double
    ) -> AgentState {
        makeInitialState(
            screens: screens, avatarSize: avatarSize, temperament: bootTemperament, now: now
        )
    }
}
