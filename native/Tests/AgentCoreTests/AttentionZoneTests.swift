import Testing
@testable import AgentCore

// Net-new, beyond blob.js parity: attentionZone/activityAnchor/cursorContactShouldFlee
// turn already-collected perception signals (caret location, typing, scrolling, cursor)
// into the avoidance behavior described in CLAUDE.md's movement-brain plan. Per the
// locked "caret + cursor only" decision, scrolling and frontmostWindow deliberately do
// NOT produce a zone — see attentionZone_scrollingOnly_isNil below.
struct AttentionZoneTests {
    static let bounds = TestFixtures.bounds

    private static func world(
        typing: Bool = false, typingLocation: Rect? = nil,
        scrolling: Bool = false, cursor: Point = Point(x: 0, y: 0)
    ) -> AgentWorld {
        AgentWorld(
            screenBounds: bounds, cursor: cursor, frontmostApp: nil, windowBelow: nil,
            typing: typing, typingLocation: typingLocation, scrolling: scrolling
        )
    }

    // MARK: attentionZone

    @Test func attentionZone_typingWithCaret_isCaretRectPaddedByConstant() {
        let caret = Rect(origin: Point(x: 100, y: 200), size: Size(width: 2, height: 20))
        let w = Self.world(typing: true, typingLocation: caret)
        let zone = attentionZone(from: w)
        let padding = Constants.caretAvoidPadding
        #expect(zone == Rect(
            origin: Point(x: 100 - padding, y: 200 - padding),
            size: Size(width: 2 + padding * 2, height: 20 + padding * 2)
        ))
    }

    @Test func attentionZone_typingButNoCaret_isNil() {
        let w = Self.world(typing: true, typingLocation: nil)
        #expect(attentionZone(from: w) == nil)
    }

    @Test func attentionZone_notTyping_isNilEvenIfCaretPresent() {
        // Defensive: Perception shouldn't produce this combo, but attentionZone's own
        // contract requires both signals, not just a stale cached caret rect.
        let caret = Rect(origin: Point(x: 100, y: 200), size: Size(width: 2, height: 20))
        let w = Self.world(typing: false, typingLocation: caret)
        #expect(attentionZone(from: w) == nil)
    }

    @Test func attentionZone_scrollingOnly_isNil() {
        // Locked decision: scrolling alone never produces a keep-out zone (no precise
        // "where the eyes are" signal while reading).
        let w = Self.world(typing: false, scrolling: true)
        #expect(attentionZone(from: w) == nil)
    }

    @Test func attentionZone_noSignals_isNil() {
        let w = Self.world()
        #expect(attentionZone(from: w) == nil)
    }

    // MARK: activityAnchor

    @Test func activityAnchor_typingWithCaret_isCaretCenter() {
        let caret = Rect(origin: Point(x: 100, y: 200), size: Size(width: 10, height: 20))
        let w = Self.world(typing: true, typingLocation: caret, cursor: Point(x: 900, y: 700))
        #expect(activityAnchor(from: w) == Point(x: 105, y: 210))
    }

    @Test func activityAnchor_noCaret_isCursor() {
        let w = Self.world(cursor: Point(x: 42, y: 84))
        #expect(activityAnchor(from: w) == Point(x: 42, y: 84))
    }

    @Test func activityAnchor_typingFalseWithStaleCaret_isCursor() {
        let caret = Rect(origin: Point(x: 100, y: 200), size: Size(width: 10, height: 20))
        let w = Self.world(typing: false, typingLocation: caret, cursor: Point(x: 42, y: 84))
        #expect(activityAnchor(from: w) == Point(x: 42, y: 84))
    }

    // MARK: cursorContactShouldFlee

    @Test func cursorContactShouldFlee_typingAndHovering_isTrue() {
        let w = Self.world(typing: true, cursor: Point(x: 110, y: 110))
        let flees = cursorContactShouldFlee(
            world: w, position: Point(x: 100, y: 100), size: TestFixtures.blobSize
        )
        #expect(flees)
    }

    @Test func cursorContactShouldFlee_scrollingAndHovering_isTrue() {
        let w = Self.world(scrolling: true, cursor: Point(x: 110, y: 110))
        let flees = cursorContactShouldFlee(
            world: w, position: Point(x: 100, y: 100), size: TestFixtures.blobSize
        )
        #expect(flees)
    }

    @Test func cursorContactShouldFlee_idleAndHovering_isFalse() {
        // Preserves draggability: reaching for the avatar while idle should never flee.
        let w = Self.world(cursor: Point(x: 110, y: 110))
        let flees = cursorContactShouldFlee(
            world: w, position: Point(x: 100, y: 100), size: TestFixtures.blobSize
        )
        #expect(!flees)
    }

    @Test func cursorContactShouldFlee_typingButNotHovering_isFalse() {
        let w = Self.world(typing: true, cursor: Point(x: 900, y: 700))
        let flees = cursorContactShouldFlee(
            world: w, position: Point(x: 100, y: 100), size: TestFixtures.blobSize
        )
        #expect(!flees)
    }
}
