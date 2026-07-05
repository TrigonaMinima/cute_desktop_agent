import Foundation

// Mechanical port of the avatar-agnostic constants in electron-poc/renderer/blob.js
// (lines 90-124). Deliberately excludes BLOB_WIDTH/BLOB_HEIGHT/BLOB_SIZE — the active
// avatar's footprint flows in as `AgentBody.size` (set from `Avatar.intrinsicSize` at
// launch), not a hard-coded constant, so a future non-slime avatar with a different
// footprint needs no change here.
public enum Constants {
    /// Shorthand for the (min, max) ms ranges `randomRange` draws from — used
    /// throughout this file and by `StateMachine.randomRange`.
    public typealias MsRange = (min: Double, max: Double)

    /// Inset (px) kept from the screen edges while wandering to a border spot.
    public static let roamMargin: Double = 24
    /// Inset (px) kept from the screen edges while resting in a corner.
    public static let restMargin: Double = 24
    /// How deep (px) the "stay near the edge" wander/rest band is.
    public static let borderBandDepth: Double = 160
    /// px of the avatar guaranteed on-screen at all times (clampVisible's floor).
    public static let minVisible: Double = 20
    /// Roaming speed in px/sec — slow, calm movement.
    public static let moveSpeed: Double = 80
    /// Distance (px) at which a moving agent is considered "arrived" at its target.
    public static let arriveThreshold: Double = 4

    /// Fixed duration (ms) of the happy bounce triggered by a drag-drop.
    public static let happyDurationMs: Double = 500
    /// (min, max) dwell (ms) once `happy` ends and the prior mode resumes. This is a
    /// distinct literal from `modeDwellMsRange` in the JS original — NOT looked up by
    /// the resumed mode's own dwell range. Preserved here exactly, not "fixed."
    public static let happyResumeDwellMsRange: MsRange = (800, 1500)

    /// Fixed duration (ms) an eye-closed blink stays visible.
    public static let blinkActiveMs: Double = 120
    /// (min, max) gap (ms) between blinks.
    public static let blinkIntervalMsRange: MsRange = (2500, 6000)

    /// (min, max) duration (ms) an idle-only quirk emotion stays active.
    public static let quirkDurationMsRange: MsRange = (1200, 2200)
    /// (min, max) extra gap (ms), added on top of the quirk's own duration, before the
    /// next quirk may fire.
    public static let quirkCooldownGapMsRange: MsRange = (6000, 12000)

    /// Cursor-to-avatar-center distance (px) that triggers a proximity startle.
    public static let proximityRadius: Double = 70
    /// Fixed duration (ms) a proximity startle stays active.
    public static let proximityDurationMs: Double = 900
    /// (min, max) cooldown (ms) before another proximity startle may trigger.
    public static let proximityCooldownMsRange: MsRange = (8000, 15000)

    /// Speed (px/sec) above which `AgentWorld.cursorMoving` reports true. A stationary
    /// cursor polls to exactly the same position each frame (velocity == 0), so this is
    /// mainly a jitter floor for sub-pixel/OS-reported drift, not a real motion threshold.
    public static let cursorMovingThreshold: Double = 5

    // The three constants below seed the ONE-TIME boot state (JS's inline `state`
    // object literal, blob.js lines 147-165) and are deliberately DIFFERENT from the
    // steady-state reschedule literals above — not a typo, preserved exactly.

    /// Fixed ms until the *first* idle mode timeout, from boot. A flat literal in the
    /// JS original, NOT `randomRange` over `modeDwellMsRange[.idle]` (3000-6000).
    public static let initialModeEndsAtDelayMs: Double = 1500
    /// (min, max) ms until the *first* blink, from boot — distinct from
    /// `blinkIntervalMsRange` (2500-6000) used by every subsequent reschedule.
    public static let initialBlinkDelayMsRange: MsRange = (2000, 5000)
    /// (min, max) ms until the *first* quirk may fire, from boot — distinct from the
    /// steady-state `quirkCooldownGapMsRange` (6000-12000, added on top of duration).
    public static let initialQuirkDelayMsRange: MsRange = (4000, 9000)

    /// Favor sitting still (idle/rest) over roaming; ordered array (not a Dictionary)
    /// so `weightedChoice`'s tie-breaking stays deterministic — see Geometry.swift.
    public static let modeWeights: [(Mode, Double)] = [
        (.idle, 0.5), (.wander, 0.2), (.rest, 0.25), (.peek, 0.05),
    ]

    /// (min, max) dwell time in ms once a mode's target is reached (or immediately,
    /// for idle). `happy` is excluded — its duration is a fixed 500 ms handled
    /// separately by the state machine's `triggerHappy`/`updateHappy`.
    public static let modeDwellMsRange: [Mode: MsRange] = [
        .idle: (3000, 6000),
        .wander: (2500, 5000),
        .rest: (6000, 12000),
        .peek: (800, 1600),
    ]

    /// The ambient emotion for each mode, before quirks/proximity/drag/happy layer on
    /// top (see the priority ladder in Emotion.swift's doc comment).
    public static let baseEmotionByMode: [Mode: Emotion] = [
        .idle: .neutral, .wander: .neutral, .rest: .sleepy, .peek: .curious,
    ]

    /// Randomized idle-only ambient quirks (blush/thinking/annoyed), layered over the
    /// base emotion when idle and awake.
    public static let quirkEmotions: [Emotion] = [.blush, .thinking, .annoyed]

    /// Speech-bubble glyph shown per emotion; emotions absent here show no bubble.
    public static let bubbleByEmotion: [Emotion: String] = [
        .surprised: "!",
        .curious: "?",
        .sleepy: "\u{1F4A4}",
        .thinking: "\u{22EF}",
        .annoyed: "\u{1F4A2}",
        .blush: "\u{2661}",
        .happy: "\u{266A}",
    ]

    /// Which blush treatment each emotion wears; falls back to `.none`.
    public static let blushStyleByEmotion: [Emotion: BlushStyle] = [
        .neutral: .none,
        .curious: .none,
        .surprised: .none,
        .annoyed: .none,
        .sleepy: .plain,
        .thinking: .plain,
        .blush: .hatch,
        .happy: .hatch,
    ]

    // MARK: Render — squash/stretch (mechanical port of blob.js's render(), lines ~200+)

    /// Angular frequency applied to `now/1000` for the idle/moving breathing wobble.
    public static let wobbleFrequency: Double = 2.2
    /// Amplitude (px) of the vertical bob, `wobble * bobAmplitude` — zeroed while
    /// dragging or in `happy` mode.
    public static let bobAmplitude: Double = 3

    /// Squash applied while dragging: (scaleX, scaleY).
    public static let dragScale: (x: Double, y: Double) = (1.05, 0.95)
    /// Squash applied while mid-transit to a target (not dragging/happy): (scaleX, scaleY).
    public static let movingScale: (x: Double, y: Double) = (1.08, 0.92)
    /// Idle breathing wobble amplitude applied to scaleY (+) and scaleX (-) respectively.
    public static let idleWobbleScaleY: Double = 0.03
    public static let idleWobbleScaleX: Double = 0.02

    /// Happy-bounce amplitude applied to scaleY (+) and scaleX (-) respectively, scaled
    /// by the decaying `bounce` term — see `computeBodyMotion`.
    public static let happyBounceScaleY: Double = 0.25
    public static let happyBounceScaleX: Double = 0.15
}
