import Testing
@testable import AgentCore

// Multi-screen geometry: full confinement of the avatar inside one screen's rect
// (the below-edge regression fix), plus screen lookup by containment and by nearest
// clamped-point distance. All rects are visibleFrames in global web space (top-left
// origin, y-down), so non-zero and negative origins are the norm for secondary
// displays — the fixtures below exercise both.
struct ScreensTests {
    static let blobSize = TestFixtures.blobSize // 78 x 62

    // The shared fixtures: primary "Main" (1000x800) at the web-space origin;
    // secondary "Side" (800x600) at (1200, 100) — to its right, shorter, with a
    // 200px horizontal dead zone between them (non-aligned displays).
    static let primary = TestFixtures.screen
    static let secondary = TestFixtures.secondScreen
    static let screens = TestFixtures.twoScreens

    // MARK: clampToScreen — zero-tolerance full confinement

    @Test func clampToScreen_pointFullyInside_isUnchanged() {
        let p = clampToScreen(point: Point(x: 400, y: 300), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 400, y: 300))
    }

    @Test func clampToScreen_pointPastLeftEdge_clampsToScreenMinX() {
        let p = clampToScreen(point: Point(x: -50, y: 300), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 0, y: 300))
    }

    @Test func clampToScreen_pointPastTopEdge_clampsToScreenMinY() {
        let p = clampToScreen(point: Point(x: 400, y: -50), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 400, y: 0))
    }

    @Test func clampToScreen_pointPastRightEdge_clampsSoBlobStaysFullyInside() {
        let p = clampToScreen(point: Point(x: 950, y: 300), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 922, y: 300)) // 1000 - 78
    }

    @Test func clampToScreen_pointPastBottomEdge_clampsSoBlobStaysFullyInside() {
        let p = clampToScreen(point: Point(x: 400, y: 790), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 400, y: 738)) // 800 - 62 — no minVisible tolerance, ever
    }

    @Test func clampToScreen_pointExactlyAtFarLimit_isUnchanged() {
        let p = clampToScreen(point: Point(x: 922, y: 738), screen: Self.primary, blobSize: Self.blobSize)
        #expect(p == Point(x: 922, y: 738))
    }

    @Test func clampToScreen_nonZeroOriginScreen_clampsIntoThatScreensRect() {
        let low = clampToScreen(point: Point(x: 0, y: 0), screen: Self.secondary, blobSize: Self.blobSize)
        #expect(low == Point(x: 1200, y: 100))
        let high = clampToScreen(point: Point(x: 5000, y: 5000), screen: Self.secondary, blobSize: Self.blobSize)
        #expect(high == Point(x: 1922, y: 638)) // 1200+800-78, 100+600-62
    }

    @Test func clampToScreen_blobLargerThanScreen_pinsToScreenOrigin() {
        let tiny = ScreenInfo(
            frame: Rect(origin: Point(x: 300, y: 200), size: Size(width: 50, height: 40)),
            name: "Tiny"
        )
        let p = clampToScreen(point: Point(x: 600, y: 600), screen: tiny, blobSize: Self.blobSize)
        #expect(p == Point(x: 300, y: 200))
    }

    // MARK: screenIndex(containing:) — hit, miss, edge conventions

    @Test func screenIndex_pointInsidePrimary_returnsZero() {
        #expect(screenIndex(containing: Point(x: 500, y: 400), screens: Self.screens) == 0)
    }

    @Test func screenIndex_pointInsideSecondary_returnsOne() {
        #expect(screenIndex(containing: Point(x: 1500, y: 400), screens: Self.screens) == 1)
    }

    @Test func screenIndex_pointInDeadZoneBetweenScreens_returnsNil() {
        #expect(screenIndex(containing: Point(x: 1100, y: 400), screens: Self.screens) == nil)
    }

    @Test func screenIndex_pointAtScreenOrigin_isContained() {
        #expect(screenIndex(containing: Point(x: 1200, y: 100), screens: Self.screens) == 1)
    }

    @Test func screenIndex_pointExactlyAtFarEdge_isNotContained() {
        // Far edges are exclusive so a point on the seam of two flush-adjacent
        // screens belongs to exactly one of them.
        #expect(screenIndex(containing: Point(x: 1000, y: 800), screens: Self.screens) == nil)
    }

    // MARK: nearestScreenIndex — containment wins, else clamped-point distance

    @Test func nearestScreenIndex_containedPoint_returnsContainingScreen() {
        #expect(nearestScreenIndex(to: Point(x: 1500, y: 400), screens: Self.screens) == 1)
    }

    @Test func nearestScreenIndex_deadZonePoint_returnsClosestScreenByClampedDistance() {
        // x=1150 is 150px from primary's right edge (1000), 50px from secondary's
        // left edge (1200) — secondary wins.
        #expect(nearestScreenIndex(to: Point(x: 1150, y: 400), screens: Self.screens) == 1)
    }

    @Test func nearestScreenIndex_equidistantPoint_tieBreaksToLowerIndex() {
        // x=1100 is exactly 100px from both facing edges at y=400 (inside both
        // screens' vertical ranges).
        #expect(nearestScreenIndex(to: Point(x: 1100, y: 400), screens: Self.screens) == 0)
    }

    @Test func nearestScreenIndex_singleScreen_alwaysReturnsZero() {
        #expect(nearestScreenIndex(to: Point(x: -5000, y: -5000), screens: [Self.primary]) == 0)
    }
}
