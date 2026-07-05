import Testing
@testable import AgentCore

// Scrolling is a derived perceived signal, mirroring typing in TypingSignalTests.swift:
// AgentApp's Perception layer polls a raw timestamp (last scroll-wheel event), and
// AgentCore decides whether that still counts as "scrolling right now" against the
// current tick's `now`. Scroll events arrive in discrete bursts (trackpad phases +
// momentum), so this needs the same decay-window treatment as typing, not an
// instantaneous computed property like `cursorMoving`.
struct ScrollSignalTests {

    @Test func isScrollActive_justInsideTimeout_isTrue() {
        let active = isScrollActive(lastScrollAt: 1000, now: 1000 + 399, timeoutMs: 400)
        #expect(active == true)
    }

    @Test func isScrollActive_pastTimeout_isFalse() {
        let active = isScrollActive(lastScrollAt: 1000, now: 1000 + 401, timeoutMs: 400)
        #expect(active == false)
    }

    @Test func isScrollActive_exactlyAtTimeout_isFalse() {
        // Boundary is exclusive — `now - lastScrollAt < timeoutMs`, not `<=`.
        let active = isScrollActive(lastScrollAt: 1000, now: 1000 + 400, timeoutMs: 400)
        #expect(active == false)
    }

    @Test func isScrollActive_noScrollYet_isFalse() {
        // lastScrollAt == 0 is the "never scrolled" baseline (mirrors isTypingActive's
        // lastKeystrokeAt == 0 case) — must not read as "scrolled at time zero".
        let active = isScrollActive(lastScrollAt: 0, now: 500, timeoutMs: 400)
        #expect(active == false)
    }

    @Test func isScrollActive_rightAtScrollEvent_isTrue() {
        let active = isScrollActive(lastScrollAt: 1000, now: 1000, timeoutMs: 400)
        #expect(active == true)
    }
}
