import Testing
@testable import AgentCore

// Target-picking geometry (innerBounds, pickCorner, pickBorderPoint) against a screen
// *rect* rather than a size-from-origin — secondary displays have non-zero origins in
// global web space, so every helper is exercised twice: once on the origin-anchored
// primary (numbers hand-verifiable against blob.js lines 25-85) and once on an offset
// screen (same numbers shifted by the origin).
struct TargetPickingTests {
    static let screen = TestFixtures.screen.frame // origin (0,0), 1000x800
    static let offsetScreen = TestFixtures.secondScreen.frame // origin (1200,100), 800x600
    static let margin = 20.0
    static let blobSize = TestFixtures.blobSize
    // primary innerBounds -> minX/minY = 20, maxX = 1000 - 20 - 78 = 902, maxY = 800 - 20 - 62 = 718
    // offset innerBounds  -> minX = 1220, minY = 120, maxX = 1200 + 800 - 20 - 78 = 1902,
    //                        maxY = 100 + 600 - 20 - 62 = 618

    // MARK: innerBounds

    @Test func innerBounds_originScreen_insetsMarginAndBlobSize() {
        let result = innerBounds(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize)
        #expect(result.minX == 20)
        #expect(result.minY == 20)
        #expect(result.maxX == 902)
        #expect(result.maxY == 718)
    }

    @Test func innerBounds_offsetScreen_insetsRelativeToScreenOrigin() {
        let result = innerBounds(screen: Self.offsetScreen, margin: Self.margin, blobSize: Self.blobSize)
        #expect(result.minX == 1220)
        #expect(result.minY == 120)
        #expect(result.maxX == 1902)
        #expect(result.maxY == 618)
    }

    // MARK: pickCorner

    @Test func pickCorner_index0_isTopLeft() {
        let p = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 0)
        #expect(p == Point(x: 20, y: 20))
    }

    @Test func pickCorner_index1_isTopRight() {
        let p = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 1)
        #expect(p == Point(x: 902, y: 20))
    }

    @Test func pickCorner_index2_isBottomLeft() {
        let p = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 2)
        #expect(p == Point(x: 20, y: 718))
    }

    @Test func pickCorner_index3_isBottomRight() {
        let p = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 3)
        #expect(p == Point(x: 902, y: 718))
    }

    @Test func pickCorner_indexWrapsModuloFour() {
        let wrapped = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 5)
        let direct = pickCorner(screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 1)
        #expect(wrapped == direct)
    }

    @Test func pickCorner_offsetScreen_cornersShiftWithOrigin() {
        let topLeft = pickCorner(screen: Self.offsetScreen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 0)
        #expect(topLeft == Point(x: 1220, y: 120))
        let bottomRight = pickCorner(screen: Self.offsetScreen, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 3)
        #expect(bottomRight == Point(x: 1902, y: 618))
    }

    // MARK: pickBorderPoint

    @Test func pickBorderPoint_topStrip_hugsTopEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 0, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 461, y: 27.5))
    }

    @Test func pickBorderPoint_bottomStrip_hugsBottomEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 1, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 461, y: 710.5))
    }

    @Test func pickBorderPoint_leftStrip_hugsLeftEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 2, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 27.5, y: 369))
    }

    @Test func pickBorderPoint_rightStrip_hugsRightEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            screen: Self.screen, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 3, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 894.5, y: 369))
    }

    @Test func pickBorderPoint_offsetScreen_topStripShiftsWithOrigin() {
        let p = pickBorderPoint(
            screen: Self.offsetScreen, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 0, rngAlong: 0.5, rngDepth: 0.5
        )
        // x = lerp(1220, 1902, 0.5) = 1561; y = lerp(120, 135, 0.5) = 127.5
        #expect(p == Point(x: 1561, y: 127.5))
    }
}
