import Foundation

/// Perception region: what the agent currently senses about the outside world. Written
/// once per tick by `AgentApp`'s Perception layer, never by `StateMachine`.
public struct AgentWorld: Codable, Equatable {
    public var screenBounds: Size
    public var cursor: Point
    public var frontmostApp: AppInfo?
    /// Reserved — see WindowInfo.swift. Always `nil` this round.
    public var windowBelow: WindowInfo?

    public init(screenBounds: Size, cursor: Point, frontmostApp: AppInfo? = nil, windowBelow: WindowInfo? = nil) {
        self.screenBounds = screenBounds
        self.cursor = cursor
        self.frontmostApp = frontmostApp
        self.windowBelow = windowBelow
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

    public init(
        position: Point, mode: Mode, target: Point, moving: Bool, emotion: Emotion,
        dragging: Bool, dragOffset: Vector, size: Size
    ) {
        self.position = position
        self.mode = mode
        self.target = target
        self.moving = moving
        self.emotion = emotion
        self.dragging = dragging
        self.dragOffset = dragOffset
        self.size = size
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

    public init(
        modeEndsAt: Double, happyUntil: Double, happyResumeMode: Mode, pendingReturn: Bool,
        nextBlinkAt: Double, blinking: Bool, blinkEndsAt: Double, quirkEmotion: Emotion?,
        quirkUntil: Double, nextQuirkAt: Double, proximityUntil: Double, proximityCooldownUntil: Double
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
