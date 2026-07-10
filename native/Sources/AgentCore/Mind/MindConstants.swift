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

    // MARK: Habituation (shared by gaze salience and the reflex arc)

    /// Seconds of continuous exposure (at temperament rate 1) for interest fatigue to
    /// reach ~63%. Calm's 1.6 rate shortens this to ~5s — it glances, then moves on.
    public static let habituationGrowTauSeconds: Double = 8
    /// Seconds for a habituated stimulus to recover ~63% of its freshness once unattended.
    public static let habituationRecoveryTauSeconds: Double = 20

    // MARK: Gaze salience contest (design doc "Gaze: how attention gets allocated")

    /// How much a challenger must clear the incumbent's salience by to steal the eyes —
    /// gaze's own hysteresis, so attention never flips on a hair.
    public static let gazeSwitchMargin: Double = 0.15
    /// Minimum ms a newly acquired target is held before another switch is allowed.
    public static let gazeMinDwellMs: Double = 350
    /// Ms after a switch during which the eyes move at saccade speed, then pursuit.
    public static let saccadeDurationMs: Double = 120
    /// Gaze-approach time constant (s) during a saccade — effectively a snap.
    public static let saccadeTauSeconds: Double = 0.04
    /// Pursuit time constant (s) at full attention: glued to the target.
    public static let pursuitTightTauSeconds: Double = 0.08
    /// Pursuit time constant (s) at zero attention: loose, dreamy tracking.
    public static let pursuitLooseTauSeconds: Double = 0.35
    /// Time constant (s) for the attention level chasing the winner's salience.
    public static let attentionTauSeconds: Double = 0.6
    /// Seconds for an onset's pull to fade — a window opening is old news in a few beats.
    public static let onsetSalienceDecaySeconds: Double = 4.0
    /// How strongly full habituation suppresses a candidate (1 = to zero).
    public static let gazeHabituationStrength: Double = 0.7
    /// Cursor speed (px/s) at which its motion contribution saturates.
    public static let cursorSalienceSpeedScale: Double = 2000
    /// Distance (px) within which cursor proximity to the body adds salience.
    public static let cursorSalienceProximityRadius: Double = 400
    /// Arousal near zero scales all non-neutral salience to this floor — sleepiness
    /// flattens everything, and the eyes drift home to neutral. Kept low enough that
    /// even a fast nearby cursor (salience ≈ 1) can't clear the neutral-plus-margin bar.
    public static let gazeLowArousalGainFloor: Double = 0.25
    /// The neutral resting gaze sits this many px below body center (ahead, slightly down).
    public static let neutralGazeDropPx: Double = 60
    /// Gaze offset (px) at which `direction(from:)` reports full pupil deflection.
    public static let gazeDirectionFullDeflectionPx: Double = 150

    // MARK: Arbitration (design doc layer 5 — softmax + hysteresis)

    /// Softmax temperature over behavior scores: low enough that a clear winner nearly
    /// always wins, high enough that near-ties stay genuinely stochastic.
    public static let behaviorSoftmaxTemperature: Double = 0.15
    /// Flat score bonus the incumbent behavior gets — the arbiter's hysteresis, so a
    /// marginal challenger doesn't flip the body every cognition tick.
    public static let behaviorIncumbentBonus: Double = 0.15
    /// Minimum ms a committed behavior holds before re-scoring (unless a forced
    /// re-arbitration — reflex end, arrival, yield trigger — cuts it short).
    public static let behaviorMinCommitmentMs: Double = 2500
    /// The idle candidate's constant score: doing nothing is always on the table.
    public static let idleBehaviorScore: Double = 0.25
    /// Yield's score when the body overlaps the user's working zone — far above
    /// anything the drive-led candidates can reach, because sitting on the user's
    /// caret is never acceptable.
    public static let yieldBehaviorScore: Double = 3.0
    /// Energy deficit subtracted from the rest score before it competes: rest only
    /// outbids idle once energy has genuinely sagged, not at an average baseline.
    public static let restEnergySlack: Double = 0.3

    // MARK: Brain motor policy (behavior → desired speed / target geometry)

    /// Everyday locomotion speed cap (px/s), scaled by `Temperament.tempo`.
    public static let cruiseSpeedPxPerSecond: Double = 120
    /// Yield moves with urgency — getting off the user's caret shouldn't dawdle.
    public static let yieldSpeedPxPerSecond: Double = 220
    /// Reflex flight is the fastest thing the body ever does.
    public static let reflexFleeSpeedPxPerSecond: Double = 340
    /// Speed (px/s) above which the body reads as "moving" for render/status purposes.
    public static let bodyMovingThresholdPxPerSecond: Double = 8
    /// Inspect approaches its object of interest to this stand-off distance (px),
    /// leaning in to look rather than sitting on the thing.
    public static let inspectStandOffPx: Double = 140
    /// Within this distance (px) of a behavior target the trip counts as arrived,
    /// clearing the target and forcing a re-arbitration.
    public static let arriveRadiusPx: Double = 12

    // MARK: Power ladder (decision log D11)

    /// Seconds of no user input before the brain drops to the doze tier.
    public static let powerDozeAfterSeconds: Double = 90
    /// Seconds of no user input before the sleep tier (shell stops the frame clock).
    public static let powerSleepAfterSeconds: Double = 300
    /// Cognition slice while dozing — a quarter of the awake rate.
    public static let dozeCognitionIntervalSeconds: Double = 0.5
    /// Multiplier on the energy/arousal baselines while dozing or asleep — the "drive
    /// baselines biased down" half of the doze tier.
    public static let dozeDriveBaselineScale: Double = 0.6

    // MARK: Reflex arc (design doc layer 2)

    /// Cursor must be within this many px of body center for a dart to register.
    public static let reflexDartDistancePx: Double = 250
    /// Closing speed (px/s) below which cursor motion isn't a dart at all.
    public static let reflexDartMinClosingSpeed: Double = 600
    /// Closing speed (px/s) at which a dart's raw intensity saturates at 1.
    public static let reflexDartFullClosingSpeed: Double = 2000
    /// Post-gain intensity tiers: the startle → flinch → wary-watch → nothing ladder.
    public static let reflexStartleThreshold: Double = 0.5
    public static let reflexFlinchThreshold: Double = 0.25
    public static let reflexWaryWatchThreshold: Double = 0.12
    /// How long each response tier holds the body (or, for wary watch, the eyes), ms.
    public static let startleDurationMs: Double = 700
    public static let flinchDurationMs: Double = 350
    public static let waryWatchDurationMs: Double = 900
    /// Dead time (ms) after an event ends before the arc may fire again — one poke is
    /// one reaction, not a machine-gun of them across consecutive frames.
    public static let reflexRefractoryMs: Double = 400
    /// Habituation exposure (equivalent seconds) each detected stimulus deposits —
    /// event-based, unlike gaze's continuous per-tick exposure of the same store.
    public static let reflexEventExposureSeconds: Double = 3
}
