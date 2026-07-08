import Testing
@testable import AgentCore

// Net-new, beyond blob.js parity: pure geometry backing the attention-avoidance behavior
// (escapePoint, farthestIndex) — mirrors Math/TargetPicking.swift's style: fixed
// bounds/blobSize below, expected numbers hand-verifiable via the comments alongside them.
struct AvoidanceTests {
    static let bounds = TestFixtures.bounds
    static let blobSize = TestFixtures.blobSize

    // MARK: rectsOverlap

    @Test func rectsOverlap_overlapping_isTrue() {
        let a = Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
        let b = Rect(origin: Point(x: 5, y: 5), size: Size(width: 10, height: 10))
        #expect(rectsOverlap(a, b))
    }

    @Test func rectsOverlap_touchingEdgesOnly_isFalse() {
        let a = Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
        let b = Rect(origin: Point(x: 10, y: 0), size: Size(width: 10, height: 10))
        #expect(!rectsOverlap(a, b))
    }

    @Test func rectsOverlap_farApart_isFalse() {
        let a = Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
        let b = Rect(origin: Point(x: 500, y: 500), size: Size(width: 10, height: 10))
        #expect(!rectsOverlap(a, b))
    }

    // MARK: escapePoint

    @Test func escapePoint_zoneBelowIsNearest_choosesDown() {
        // avatar x:[400,478] y:[400,462]; zone x:[410,460] y:[405,425] sits inside the
        // avatar. Candidate distances from (400,400): left=78, right=70, up=67, down=35 —
        // down is smallest and clears the zone (avatar would sit at y:[435,497] vs zone
        // y:[405,425]).
        let p = escapePoint(
            avatarPosition: Point(x: 400, y: 400), avatarSize: Self.blobSize,
            zone: Rect(origin: Point(x: 410, y: 405), size: Size(width: 50, height: 20)),
            bounds: Self.bounds, padding: 10, minVisible: 20
        )
        #expect(p == Point(x: 400, y: 435))
    }

    @Test func escapePoint_zoneBelowAvatarCenter_choosesUp() {
        // avatar x:[500,578] y:[500,562]; zone x:[490,590] y:[530,610]. Candidate
        // distances from (500,500): up=42, down=120, left=98, right=100 — up is smallest
        // and clears (avatar would sit at y:[458,520] vs zone y:[530,610]).
        let p = escapePoint(
            avatarPosition: Point(x: 500, y: 500), avatarSize: Self.blobSize,
            zone: Rect(origin: Point(x: 490, y: 530), size: Size(width: 100, height: 80)),
            bounds: Self.bounds, padding: 10, minVisible: 20
        )
        #expect(p == Point(x: 500, y: 458))
    }

    @Test func escapePoint_result_alwaysStaysOnScreenPerMinVisible() {
        let p = escapePoint(
            avatarPosition: Point(x: 5, y: 5), avatarSize: Self.blobSize,
            zone: Rect(origin: Point(x: 0, y: 0), size: Size(width: 20, height: 20)),
            bounds: Self.bounds, padding: 10, minVisible: 20
        )
        #expect(p.x >= -(Self.blobSize.width - 20))
        #expect(p.y >= -(Self.blobSize.height - 20))
        #expect(p.x <= Self.bounds.width - 20)
        #expect(p.y <= Self.bounds.height - 20)
    }

    @Test func escapePoint_zoneCoversEntireScreen_returnsOnScreenFallbackWithoutCrashing() {
        // Degenerate case: no candidate can clear a full-screen zone. Must still return a
        // point respecting the on-screen floor rather than crashing or returning garbage.
        let p = escapePoint(
            avatarPosition: Point(x: 500, y: 400), avatarSize: Self.blobSize,
            zone: Rect(origin: Point(x: 0, y: 0), size: Self.bounds),
            bounds: Self.bounds, padding: 10, minVisible: 20
        )
        #expect(p.x >= -(Self.blobSize.width - 20))
        #expect(p.y >= -(Self.blobSize.height - 20))
        #expect(p.x <= Self.bounds.width - 20)
        #expect(p.y <= Self.bounds.height - 20)
    }

    // MARK: farthestIndex

    @Test func farthestIndex_uniqueFarthestCandidate_isPicked() {
        // Same corner points as TargetPickingTests' pickCorner (margin 20, blobSize 78x62).
        let corners = [
            Point(x: 20, y: 20), Point(x: 902, y: 20),
            Point(x: 20, y: 718), Point(x: 902, y: 718),
        ]
        let index = farthestIndex(anchor: Point(x: 0, y: 0), candidates: corners, rngValue: 0.5)
        #expect(index == 3)
    }

    @Test func farthestIndex_tiedCandidates_tieBreaksByRngValue() {
        // Both candidates are equidistant (341.5) from the anchor.
        let candidates = [Point(x: 461, y: 27.5), Point(x: 461, y: 710.5)]
        let anchor = Point(x: 461, y: 369)
        #expect(farthestIndex(anchor: anchor, candidates: candidates, rngValue: 0.0) == 0)
        #expect(farthestIndex(anchor: anchor, candidates: candidates, rngValue: 0.99) == 1)
    }
}
