import Foundation

/// The doze/sleep power policy's tiers (design doc "Doze/sleep"; decision log D11).
/// `dozing` is brain-internal (cognition throttled, baselines biased down); `sleeping`
/// is the app-shell tier where the frame clock actually stops.
public enum PowerTier: String, Codable, Equatable {
    case awake, dozing, sleeping
}

/// The emergent brain's belief state (decision log D4): a sibling region of
/// world/body/memory on `AgentState`, written only by `EmergentBrain` — the same
/// single-writer discipline `StateMachine` holds over `body`/`memory`. Everything in
/// here is Codable because `AgentState` doubles as the future LLM context object.
public struct MindState: Codable, Equatable {
    /// The active preset vector — swapping presets swaps this value and lets the
    /// drives' own leaky dynamics ease toward the new baselines.
    public var temperament: Temperament
    public var drives: Drives
    public var situation: SituationModel
    /// The one mind-wide habituation store: gaze keys it by target kind, the reflex
    /// arc by stimulus, and the Brain drives recovery once per tick.
    public var habituation: Habituation
    public var gaze: GazeSystem
    public var reflex: ReflexArc
    /// What the arbiter last handed the body to, and when it committed.
    public var behavior: BehaviorKind
    public var behaviorCommittedAt: Double
    /// Where the committed behavior is steering (top-left, web space); nil for
    /// behaviors with no destination (idle, rest-in-place).
    public var behaviorTarget: Point?
    public var wander: WanderState
    public var physics: PhysicsBody
    public var stepper: FixedStepper
    public var power: PowerTier
    /// When the 8 Hz cognition slice last ran (ms).
    public var lastCognitionAt: Double
    /// When set, the next cognition slice re-scores immediately, ignoring commitment —
    /// the "resume or re-arbitrate" rule's re-arbitrate half (reflex end, arrival).
    public var rearbitrateAt: Double?

    public init(temperament: Temperament, position: Point, hourOfDay: Double, now: Double) {
        self.temperament = temperament
        drives = .atBaselines(of: temperament, hourOfDay: hourOfDay)
        situation = SituationModel(now: now)
        habituation = Habituation()
        gaze = GazeSystem(bodyCenter: position, now: now)
        reflex = ReflexArc()
        behavior = .idle
        behaviorCommittedAt = now
        behaviorTarget = nil
        wander = WanderState(heading: 0)
        physics = PhysicsBody(position: position)
        stepper = FixedStepper()
        power = .awake
        lastCognitionAt = now
        rearbitrateAt = nil
    }
}
