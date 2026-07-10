@testable import AgentCore

// Shared fixtures for AgentCoreTests: the standard screen bounds + avatar footprint used
// by most StateMachine/InitialState/TargetPicking tests, and a resting-default AgentState
// factory. AgentStateCodableTests deliberately keeps its own populated fixture (different
// bounds, populated context/frontmostApp) since it exists to exercise JSON round-trip
// fidelity, not to share the "resting default" shape these tests build on.
enum TestFixtures {
    static let bounds = Size(width: 1000, height: 800)
    static let blobSize = Size(width: 78, height: 62)

    /// The standard single-display world: one primary screen at the web-space origin.
    static let screen = ScreenInfo(
        frame: Rect(origin: Point(x: 0, y: 0), size: bounds), name: "Main"
    )
    static let screens = [screen]
    /// A secondary display to the primary's right with a 200px dead zone and a
    /// non-zero origin — pass `screens: TestFixtures.twoScreens` for multi-display cases.
    static let secondScreen = ScreenInfo(
        frame: Rect(origin: Point(x: 1200, y: 100), size: Size(width: 800, height: 600)),
        name: "Side"
    )
    static let twoScreens = [screen, secondScreen]

    static func makeState(
        mode: Mode = .idle,
        position: Point = Point(x: 100, y: 100),
        cursor: Point = Point(x: 0, y: 0),
        dragging: Bool = false,
        moving: Bool = false,
        quirkEmotion: Emotion? = nil,
        quirkUntil: Double = 0,
        proximityUntil: Double = 0,
        happyUntil: Double = 0,
        typing: Bool = false,
        typingLocation: Rect? = nil,
        screens: [ScreenInfo] = screens
    ) -> AgentState {
        AgentState(
            world: AgentWorld(
                screens: screens, cursor: cursor, frontmostApp: nil, windowBelow: nil,
                typing: typing, typingLocation: typingLocation
            ),
            body: AgentBody(
                position: position, mode: mode, target: position, moving: moving, emotion: .neutral,
                dragging: dragging, dragOffset: Vector(dx: 0, dy: 0), size: blobSize
            ),
            memory: AgentMemory(
                modeEndsAt: 0, happyUntil: happyUntil, happyResumeMode: .idle,
                nextBlinkAt: 0, blinking: false, blinkEndsAt: 0, quirkEmotion: quirkEmotion,
                quirkUntil: quirkUntil, nextQuirkAt: 0, proximityUntil: proximityUntil,
                proximityCooldownUntil: 0
            )
        )
    }
}

/// Returns queued values in order, then 0.5 forever — lets a test pin exact draws
/// (e.g. one wander-jitter or screen-switch decision) without hunting for a seed that
/// happens to produce them.
final class ScriptedRandom: RandomProvider {
    private var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    func nextUnit() -> Double {
        values.isEmpty ? 0.5 : values.removeFirst()
    }
}
