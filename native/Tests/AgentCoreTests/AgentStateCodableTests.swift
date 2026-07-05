import Testing
import Foundation
@testable import AgentCore

// AgentState is the round's centerpiece: a Codable struct that is both the render
// source-of-truth today and, by design, shaped as a future LLM/agent brain's context
// object — even though nothing consumes it that way yet. These tests exist to prove
// that "serializable brain context" claim, not just exercise Codable mechanically.
struct AgentStateCodableTests {

    static func populatedState() -> AgentState {
        AgentState(
            world: AgentWorld(
                screenBounds: Size(width: 1920, height: 1080),
                cursor: Point(x: 400, y: 300),
                cursorVelocity: Vector(dx: 120, dy: -45),
                frontmostApp: AppInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal"),
                windowBelow: nil,
                frontmostWindow: WindowInfo(
                    ownerName: "Terminal", title: "bash",
                    frame: Rect(origin: Point(x: 20, y: 40), size: Size(width: 800, height: 600))
                ),
                typing: true,
                typingLocation: Rect(origin: Point(x: 410, y: 305), size: Size(width: 2, height: 16)),
                scrolling: true,
                scrollVelocity: Vector(dx: 0, dy: -240)
            ),
            body: AgentBody(
                position: Point(x: 100, y: 200),
                mode: .wander,
                target: Point(x: 500, y: 600),
                moving: true,
                emotion: .curious,
                dragging: false,
                dragOffset: Vector(dx: 0, dy: 0),
                size: Size(width: 78, height: 62)
            ),
            memory: AgentMemory(
                modeEndsAt: 12_345,
                happyUntil: 0,
                happyResumeMode: .idle,
                pendingReturn: false,
                nextBlinkAt: 15_000,
                blinking: false,
                blinkEndsAt: 0,
                quirkEmotion: nil,
                quirkUntil: 0,
                nextQuirkAt: 20_000,
                proximityUntil: 0,
                proximityCooldownUntil: 0
            ),
            context: ["lastGreeting": .string("hello"), "interactionCount": .number(3)]
        )
    }

    @Test func agentState_roundTripsThroughJSON_preservingAllFields() throws {
        let original = Self.populatedState()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentState.self, from: data)
        #expect(decoded == original)
    }

    @Test func agentState_windowBelow_isReservedAndOmittedWhenNil() throws {
        let state = Self.populatedState()
        #expect(state.world.windowBelow == nil)

        // Swift's synthesized Codable uses encodeIfPresent for Optional properties, so
        // a nil windowBelow drops the key entirely rather than emitting JSON null.
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let world = json?["world"] as? [String: Any]
        #expect(world?["windowBelow"] == nil)

        // And it still decodes back to nil, so "reserved and unpopulated" round-trips.
        let decoded = try JSONDecoder().decode(AgentState.self, from: data)
        #expect(decoded.world.windowBelow == nil)
    }

    @Test func agentState_frontmostWindow_isOmittedWhenNil() throws {
        // Own fixture, not populatedState() — that one deliberately populates
        // frontmostWindow to prove round-trip fidelity; this one proves the opposite
        // (nil) case, mirroring agentState_windowBelow_isReservedAndOmittedWhenNil.
        var state = Self.populatedState()
        state.world.frontmostWindow = nil
        #expect(state.world.frontmostWindow == nil)

        // Swift's synthesized Codable uses encodeIfPresent for Optional properties, so
        // a nil frontmostWindow drops the key entirely rather than emitting JSON null.
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let world = json?["world"] as? [String: Any]
        #expect(world?["frontmostWindow"] == nil)

        // And it still decodes back to nil, so "best-effort and unpopulated" round-trips.
        let decoded = try JSONDecoder().decode(AgentState.self, from: data)
        #expect(decoded.world.frontmostWindow == nil)
    }

    @Test func agentState_typingLocation_isReservedAndOmittedWhenNil() throws {
        // Own fixture, not populatedState() — that one deliberately populates
        // typingLocation to prove round-trip fidelity; this one proves the opposite
        // (nil) case, mirroring agentState_windowBelow_isReservedAndOmittedWhenNil.
        var state = Self.populatedState()
        state.world.typing = false
        state.world.typingLocation = nil
        #expect(state.world.typingLocation == nil)

        // Swift's synthesized Codable uses encodeIfPresent for Optional properties, so
        // a nil typingLocation drops the key entirely rather than emitting JSON null.
        let data = try JSONEncoder().encode(state)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let world = json?["world"] as? [String: Any]
        #expect(world?["typingLocation"] == nil)

        // And it still decodes back to nil, so "best-effort and unpopulated" round-trips.
        let decoded = try JSONDecoder().decode(AgentState.self, from: data)
        #expect(decoded.world.typingLocation == nil)
    }

    @Test func mode_isStringBacked_forHumanAndLLMLegibleJSON() throws {
        let data = try JSONEncoder().encode(Mode.wander)
        let string = String(data: data, encoding: .utf8)
        #expect(string == "\"wander\"")
    }

    @Test func emotion_isStringBacked_forHumanAndLLMLegibleJSON() throws {
        let data = try JSONEncoder().encode(Emotion.curious)
        let string = String(data: data, encoding: .utf8)
        #expect(string == "\"curious\"")
    }

    @Test func jsonValue_roundTripsAllCases() throws {
        let values: [JSONValue] = [
            .string("hello"),
            .number(3.5),
            .bool(true),
            .null,
            .array([.string("a"), .number(1)]),
            .object(["k": .string("v")]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test func snapshotJSON_containsWorldBodyMemoryContextKeys() throws {
        let json = try Self.populatedState().snapshotJSON()
        for key in ["world", "body", "memory", "context"] {
            #expect(json.contains("\"\(key)\""))
        }
    }

    @Test func snapshotJSON_containsCursorVelocity_asAPerceivedSignal() throws {
        let json = try Self.populatedState().snapshotJSON()
        #expect(json.contains("\"cursorVelocity\""))
        #expect(json.contains("120"))
    }

    @Test func snapshotJSON_containsTyping_asAPerceivedSignal() throws {
        let json = try Self.populatedState().snapshotJSON()
        #expect(json.contains("\"typing\""))
        #expect(json.contains("\"typingLocation\""))
    }

    @Test func snapshotJSON_containsScrolling_asAPerceivedSignal() throws {
        let json = try Self.populatedState().snapshotJSON()
        #expect(json.contains("\"scrolling\""))
        #expect(json.contains("\"scrollVelocity\""))
        #expect(json.contains("-240"))
    }
}
