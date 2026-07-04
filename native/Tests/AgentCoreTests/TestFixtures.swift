@testable import AgentCore

// Shared fixtures for AgentCoreTests: the standard screen bounds + avatar footprint used
// by most StateMachine/InitialState/TargetPicking tests, and a resting-default AgentState
// factory. AgentStateCodableTests deliberately keeps its own populated fixture (different
// bounds, populated context/frontmostApp) since it exists to exercise JSON round-trip
// fidelity, not to share the "resting default" shape these tests build on.
enum TestFixtures {
    static let bounds = Size(width: 1000, height: 800)
    static let blobSize = Size(width: 78, height: 62)

    static func makeState(
        mode: Mode = .idle,
        position: Point = Point(x: 100, y: 100),
        cursor: Point = Point(x: 0, y: 0),
        dragging: Bool = false,
        moving: Bool = false,
        quirkEmotion: Emotion? = nil,
        quirkUntil: Double = 0,
        proximityUntil: Double = 0,
        happyUntil: Double = 0
    ) -> AgentState {
        AgentState(
            world: AgentWorld(screenBounds: bounds, cursor: cursor, frontmostApp: nil, windowBelow: nil),
            body: AgentBody(
                position: position, mode: mode, target: position, moving: moving, emotion: .neutral,
                dragging: dragging, dragOffset: Vector(dx: 0, dy: 0), size: blobSize
            ),
            memory: AgentMemory(
                modeEndsAt: 0, happyUntil: happyUntil, happyResumeMode: .idle, pendingReturn: false,
                nextBlinkAt: 0, blinking: false, blinkEndsAt: 0, quirkEmotion: quirkEmotion,
                quirkUntil: quirkUntil, nextQuirkAt: 0, proximityUntil: proximityUntil,
                proximityCooldownUntil: 0
            )
        )
    }
}
