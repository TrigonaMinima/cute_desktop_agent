import Foundation

/// Perception region: what the agent currently senses about the outside world. Written
/// once per tick by `AgentApp`'s Perception layer, never by `StateMachine`. `cursorVelocity`,
/// `typing`, and `scrolling`/`scrollVelocity` are the fields here that are derived rather
/// than polled directly — see their doc comments.
public struct AgentWorld: Codable, Equatable {
    public var screenBounds: Size
    public var cursor: Point
    /// Cursor speed in px/sec, web space — derived tick-to-tick from `cursor` by
    /// `AgentCore.cursorVelocity`, not read from the OS directly (macOS has no
    /// cursor-velocity API). Zero on the first frame (no prior cursor to diff against).
    public var cursorVelocity: Vector
    public var frontmostApp: AppInfo?
    /// Reserved — see WindowInfo.swift. Always `nil` this round.
    public var windowBelow: WindowInfo?
    /// The frontmost app's focused/main window: title + frame (web space), best-effort
    /// via the Accessibility API — see WindowInfo.swift. Unlike `windowBelow`, this is
    /// populated when available and degrades to `nil` exactly like `typingLocation` (no
    /// AX window exposed by the frontmost app).
    public var frontmostWindow: WindowInfo?
    /// Whether the user is actively typing (in any app, not necessarily this one) — a
    /// global keydown timestamp aged against `Constants.typingIdleTimeoutMs` by
    /// `AgentCore.isTypingActive`. Solid: only needs an Accessibility/Input-Monitoring
    /// grant, not a per-app cooperating text field. `false` (not merely absent) when
    /// there's no signal, matching `cursor`'s always-present convention.
    public var typing: Bool
    /// Caret bounds (web space) where the user is typing, best-effort via the
    /// Accessibility API. Unlike `typing`, this needs the focused app to expose caret
    /// bounds — many Electron/web views don't — so it degrades to `nil` exactly like
    /// `windowBelow`: reserved shape, populated when available, omitted from JSON when not.
    public var typingLocation: Rect?
    /// Whether the user is actively scrolling (in any app) — a global scroll-wheel
    /// timestamp aged against `Constants.scrollActiveTimeoutMs` by
    /// `AgentCore.isScrollActive`. Same decay-window shape as `typing`: scroll events
    /// arrive in discrete bursts (trackpad phases + momentum), so this smooths the gaps
    /// between them rather than reading as an instantaneous velocity check.
    public var scrolling: Bool
    /// This frame's scroll speed/direction in px/sec, web space — derived from the
    /// scroll delta accumulated since the last poll, divided by `dt`. Unlike `scrolling`,
    /// this is instantaneous: it reads zero on any frame with no scroll events, even
    /// while `scrolling` is still true from a recent burst. Mirrors `cursorVelocity`.
    public var scrollVelocity: Vector

    public init(
        screenBounds: Size, cursor: Point, cursorVelocity: Vector = Vector(dx: 0, dy: 0),
        frontmostApp: AppInfo? = nil, windowBelow: WindowInfo? = nil,
        frontmostWindow: WindowInfo? = nil,
        typing: Bool = false, typingLocation: Rect? = nil,
        scrolling: Bool = false, scrollVelocity: Vector = Vector(dx: 0, dy: 0)
    ) {
        self.screenBounds = screenBounds
        self.cursor = cursor
        self.cursorVelocity = cursorVelocity
        self.frontmostApp = frontmostApp
        self.windowBelow = windowBelow
        self.frontmostWindow = frontmostWindow
        self.typing = typing
        self.typingLocation = typingLocation
        self.scrolling = scrolling
        self.scrollVelocity = scrollVelocity
    }

    /// True when this frame's cursor speed exceeds `Constants.cursorMovingThreshold` —
    /// instantaneous motion, not a "recently moved" decay window: flips back to false the
    /// moment the cursor pauses. Computed, not stored, so it can never drift out of sync
    /// with `cursorVelocity`.
    public var cursorMoving: Bool {
        cursorVelocity.magnitude > Constants.cursorMovingThreshold
    }
}

/// The agent's own condition: position, current behavior mode, and what it's doing.
/// `size` is the active avatar's footprint (e.g. 78x62 for slime), sourced from
/// `Avatar.intrinsicSize` at launch, not hard-coded here.
public struct AgentBody: Codable, Equatable {
    /// Top-left corner, web space (top-left origin, y grows down) — see
    /// AgentApp/Perception/CoordinateSpace.swift for the one place this gets flipped.
    public var position: Point
    public var mode: Mode
    public var target: Point
    public var moving: Bool
    public var emotion: Emotion
    public var dragging: Bool
    public var dragOffset: Vector
    public var size: Size
    /// The region (web space) the agent is currently avoiding — derived each tick from
    /// `AgentWorld` by `attentionZone(from:)` (see Behavior/Attention.swift). Beyond
    /// blob.js parity: net-new attention-avoidance state. Lives in `body`, not `world`,
    /// because it's a StateMachine-derived belief, not a raw perceived signal — honors
    /// the single-writer rule (Perception owns `world` exclusively). `nil` when there's
    /// nothing to avoid this frame.
    public var attentionZone: Rect?

    public init(
        position: Point, mode: Mode, target: Point, moving: Bool, emotion: Emotion,
        dragging: Bool, dragOffset: Vector, size: Size, attentionZone: Rect? = nil
    ) {
        self.position = position
        self.mode = mode
        self.target = target
        self.moving = moving
        self.emotion = emotion
        self.dragging = dragging
        self.dragOffset = dragOffset
        self.size = size
        self.attentionZone = attentionZone
    }
}

/// Timers, cooldowns, and other transient bookkeeping the state machine needs across
/// ticks but that isn't part of the agent's outwardly-visible condition.
public struct AgentMemory: Codable, Equatable {
    public var modeEndsAt: Double
    public var happyUntil: Double
    public var happyResumeMode: Mode
    /// True while a `peek` is lingering at the edge, waiting to hand off to `wander`.
    public var pendingReturn: Bool
    /// When the *next* blink starts (2500-6000ms out). The JS original fires a
    /// `setTimeout(..., 120)` to end each blink; a polled, single-writer tick has no
    /// fire-and-forget timers, so the 120ms blink-off is state too — `blinkEndsAt`.
    public var nextBlinkAt: Double
    public var blinking: Bool
    /// When the *current* blink ends, valid only while `blinking` is true.
    public var blinkEndsAt: Double
    public var quirkEmotion: Emotion?
    public var quirkUntil: Double
    public var nextQuirkAt: Double
    public var proximityUntil: Double
    public var proximityCooldownUntil: Double
    /// Short lockout (ms timestamp) after a flee resolves, before another overlap can
    /// re-trigger `.flee` — prevents frame-to-frame thrashing while the caret keeps
    /// moving near the avatar. Beyond blob.js parity: see Behavior/Attention.swift.
    public var yieldCooldownUntil: Double

    public init(
        modeEndsAt: Double, happyUntil: Double, happyResumeMode: Mode, pendingReturn: Bool,
        nextBlinkAt: Double, blinking: Bool, blinkEndsAt: Double, quirkEmotion: Emotion?,
        quirkUntil: Double, nextQuirkAt: Double, proximityUntil: Double, proximityCooldownUntil: Double,
        yieldCooldownUntil: Double = 0
    ) {
        self.modeEndsAt = modeEndsAt
        self.happyUntil = happyUntil
        self.happyResumeMode = happyResumeMode
        self.pendingReturn = pendingReturn
        self.nextBlinkAt = nextBlinkAt
        self.blinking = blinking
        self.blinkEndsAt = blinkEndsAt
        self.quirkEmotion = quirkEmotion
        self.quirkUntil = quirkUntil
        self.nextQuirkAt = nextQuirkAt
        self.proximityUntil = proximityUntil
        self.proximityCooldownUntil = proximityCooldownUntil
        self.yieldCooldownUntil = yieldCooldownUntil
    }
}

/// The single source of truth for both rendering and — by design, though nothing
/// consumes it this way yet — a future LLM/agent's context object. `StateMachine` is
/// the sole writer (see Behavior/StateMachine.swift, Phase 3); everything else reads a
/// frozen copy each frame. `Codable`/`Equatable` and String-backed enums keep the JSON
/// human- and LLM-legible.
public struct AgentState: Codable, Equatable {
    public var world: AgentWorld
    public var body: AgentBody
    public var memory: AgentMemory
    /// Open extension bag for future signals. Empty today; no consumer reads it yet.
    public var context: [String: JSONValue]

    public init(world: AgentWorld, body: AgentBody, memory: AgentMemory, context: [String: JSONValue] = [:]) {
        self.world = world
        self.body = body
        self.memory = memory
        self.context = context
    }

    /// Pretty-printed JSON snapshot — proves the "serializable brain context" claim
    /// even without a consumer. Not used by rendering; a debugging/future-sidecar seam.
    public func snapshotJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
