import Foundation

/// Tuning constants for the emergent brain (drives today; situation, gaze, reflex, and
/// arbitration constants join as their layers land). Kept separate from `Constants`,
/// which holds the classic blob.js-parity values — these are net-new and freely tunable,
/// with no JS source to stay byte-faithful to.
public enum MindConstants {

    // MARK: Clock rates (decision log D7)

    /// Fixed physics timestep, seconds (120 Hz).
    public static let physicsStepSeconds: Double = 1.0 / 120.0
    /// Cognition tick interval, seconds (8 Hz — inside the doc's 5-10 Hz band).
    public static let cognitionIntervalSeconds: Double = 0.125

    // MARK: Circadian curve (decision log D8)

    /// Local hour of the circadian trough (deepest sleepy point).
    public static let circadianTroughHour: Double = 3
    /// How far the energy baseline sags at the trough (multiplier at 03:00).
    public static let circadianEnergyNightScale: Double = 0.4
    /// How far the arousal baseline sags at the trough — a gentler swing than energy.
    public static let circadianArousalNightScale: Double = 0.7

    // MARK: Drive relaxation time constants

    /// Per-drive leak time constants in seconds: how long a displaced drive takes to
    /// fall ~63% of the way home. Arousal is fast (a startle fades in under a minute);
    /// energy is glacial (a nap-scale quantity); the rest sit between.
    public static let driveRelaxationTauSeconds = Drives(
        energy: 600, curiosity: 120, sociability: 240,
        comfort: 90, arousal: 20, boredom: 240
    )

    // MARK: Coupling terms (one-directional, weak — see DriveDynamics.tick)

    /// Boredom growth per second at zero arousal (scaled by `1 - arousal`). Against
    /// boredom's 240s leak this equilibrates a fully-idle calm agent around ~0.7.
    public static let boredomGrowthPerSecond: Double = 0.003
    /// Boredom level above which the boredom → curiosity coupling engages.
    public static let boredomCuriosityThreshold: Double = 0.5
    /// Curiosity lift per second per unit of above-threshold boredom.
    public static let boredomCuriosityCouplingPerSecond: Double = 0.02

    // MARK: Situation model (decision log D6)

    /// How long (ms) a raw situation candidate must hold continuously before the
    /// committed mode switches — the situation model's own hysteresis.
    public static let situationSwitchDwellMs: Double = 2000
    /// Seconds without input activity before a quiet desktop reads as idle/away.
    public static let idleAwayAfterSeconds: Double = 60
    /// Seconds of hands-off stillness before a fullscreen surface reads as media.
    public static let mediaStillnessSeconds: Double = 3
    /// Fraction of its nearest screen a window must cover to count as fullscreen-ish.
    public static let fullscreenCoverageRatio: Double = 0.9

    // MARK: Physics body (unit mass, px/sec units)

    /// Linear drag (1/s): the velocity fraction shed per second absent applied force.
    /// Sets the "weight" of the glide — how quickly Jiggy coasts to a stop.
    public static let linearDampingPerSecond: Double = 4.0
    /// Deformation spring stiffness (1/s²) pulling `squash` home to zero.
    public static let squashStiffness: Double = 90
    /// Deformation damping (1/s) — a touch underdamped on purpose, so arrivals carry a
    /// small jelly overshoot (follow-through for free).
    public static let squashDamping: Double = 12
    /// How strongly acceleration excites the deformation spring (s²/px, dimensionless out).
    public static let accelSquashGain: Double = 0.0006
    /// Hard bound on |squash| per axis — an extreme frame can never fold the body.
    public static let maxSquash: Double = 0.35

    // MARK: Steering (decision log D12 — forces, not mode-lerps)

    /// How eagerly a behavior corrects toward its desired velocity (1/s): the force is
    /// `(desired − current) * steeringGain`. Higher = snappier turns, lower = drifty.
    public static let steeringGain: Double = 3.0
    /// Distance (px) inside which `arrive` starts scaling its desired speed down, so
    /// approaches end in a settle instead of an overshoot-and-oscillate.
    public static let arriveSlowRadius: Double = 120
    /// Magnitude (px/s²) of the wander force — a gentle amble, meant to lose to any
    /// purposeful behavior it composes with.
    public static let wanderStrength: Double = 60
    /// How fast the wander heading can drift (rad/s at full jitter draw). Small enough
    /// that the path curves smoothly rather than twitching.
    public static let wanderJitterRadiansPerSecond: Double = 4.0
    /// Distance (px) from a screen edge at which the inward repulsion engages.
    public static let edgeAvoidMargin: Double = 80
    /// Repulsion (px/s²) at full edge penetration; falls off quadratically across the
    /// margin so the boundary feels like a soft cushion, not a wall.
    public static let edgeAvoidStrength: Double = 600
}
