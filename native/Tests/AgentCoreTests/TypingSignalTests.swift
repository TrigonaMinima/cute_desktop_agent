import Testing
@testable import AgentCore

// Typing is a derived perceived signal, mirroring cursorVelocity in CursorMotionTests.swift:
// AgentApp's Perception layer polls a raw timestamp (last keydown), and AgentCore decides
// whether that still counts as "typing right now" against the current tick's `now`. The
// decision is time-relative (unlike cursorMoving, which only needs the current velocity),
// so it can't be a computed property on AgentWorld — it's a pure function taking `now`.
struct TypingSignalTests {

    @Test func isTypingActive_justInsideTimeout_isTrue() {
        let active = isTypingActive(lastKeystrokeAt: 1000, now: 1000 + 1499, timeoutMs: 1500)
        #expect(active == true)
    }

    @Test func isTypingActive_pastTimeout_isFalse() {
        let active = isTypingActive(lastKeystrokeAt: 1000, now: 1000 + 1501, timeoutMs: 1500)
        #expect(active == false)
    }

    @Test func isTypingActive_exactlyAtTimeout_isFalse() {
        // Boundary is exclusive — `now - lastKeystrokeAt < timeoutMs`, not `<=`.
        let active = isTypingActive(lastKeystrokeAt: 1000, now: 1000 + 1500, timeoutMs: 1500)
        #expect(active == false)
    }

    @Test func isTypingActive_noKeystrokeYet_isFalse() {
        // lastKeystrokeAt == 0 is the "never typed" baseline (mirrors Perception's
        // lastCursor == nil case) — must not read as "typed at time zero".
        let active = isTypingActive(lastKeystrokeAt: 0, now: 500, timeoutMs: 1500)
        #expect(active == false)
    }

    @Test func isTypingActive_rightAtKeystroke_isTrue() {
        let active = isTypingActive(lastKeystrokeAt: 1000, now: 1000, timeoutMs: 1500)
        #expect(active == true)
    }
}
