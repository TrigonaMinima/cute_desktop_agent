import Testing
@testable import AgentCore

// Mechanical port of electron-poc/renderer/blob.js lines 25-85 (innerBounds, pickCorner,
// pickBorderPoint, pickEdgeTarget, clampVisible). Fixed bounds/margin/blobSize below are
// shared across cases so the expected numbers are easy to hand-verify against blob.js.
struct TargetPickingTests {
    static let bounds = TestFixtures.bounds
    static let margin = 20.0
    static let blobSize = TestFixtures.blobSize
    // innerBounds -> maxX = 1000 - 20 - 78 = 902, maxY = 800 - 20 - 62 = 718

    // MARK: innerBounds

    @Test func innerBounds_subtractsMarginAndBlobSizeFromBounds() {
        let result = innerBounds(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize)
        #expect(result.maxX == 902)
        #expect(result.maxY == 718)
    }

    // MARK: pickCorner

    @Test func pickCorner_index0_isTopLeft() {
        let p = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 0)
        #expect(p == Point(x: 20, y: 20))
    }

    @Test func pickCorner_index1_isTopRight() {
        let p = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 1)
        #expect(p == Point(x: 902, y: 20))
    }

    @Test func pickCorner_index2_isBottomLeft() {
        let p = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 2)
        #expect(p == Point(x: 20, y: 718))
    }

    @Test func pickCorner_index3_isBottomRight() {
        let p = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 3)
        #expect(p == Point(x: 902, y: 718))
    }

    @Test func pickCorner_indexWrapsModuloFour() {
        let wrapped = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 5)
        let direct = pickCorner(bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize, cornerIndex: 1)
        #expect(wrapped == direct)
    }

    // MARK: pickBorderPoint

    @Test func pickBorderPoint_topStrip_hugsTopEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 0, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 461, y: 27.5))
    }

    @Test func pickBorderPoint_bottomStrip_hugsBottomEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 1, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 461, y: 710.5))
    }

    @Test func pickBorderPoint_leftStrip_hugsLeftEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 2, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 27.5, y: 369))
    }

    @Test func pickBorderPoint_rightStrip_hugsRightEdgeWithinBandDepth() {
        let p = pickBorderPoint(
            bounds: Self.bounds, margin: Self.margin, blobSize: Self.blobSize,
            bandDepth: 15, edgeIndex: 3, rngAlong: 0.5, rngDepth: 0.5
        )
        #expect(p == Point(x: 894.5, y: 369))
    }

    // MARK: pickEdgeTarget

    @Test func pickEdgeTarget_topEdge_mostlyOffscreenAbove() {
        let p = pickEdgeTarget(bounds: Self.bounds, blobSize: Self.blobSize, edgeIndex: 0, rngAlong: 0.5)
        #expect(p == Point(x: 461, y: -37.2))
    }

    @Test func pickEdgeTarget_bottomEdge_mostlyOffscreenBelow() {
        let p = pickEdgeTarget(bounds: Self.bounds, blobSize: Self.blobSize, edgeIndex: 1, rngAlong: 0.5)
        #expect(p == Point(x: 461, y: 775.2))
    }

    @Test func pickEdgeTarget_leftEdge_mostlyOffscreenLeft() {
        let p = pickEdgeTarget(bounds: Self.bounds, blobSize: Self.blobSize, edgeIndex: 2, rngAlong: 0.5)
        #expect(p == Point(x: -46.8, y: 369))
    }

    @Test func pickEdgeTarget_rightEdge_mostlyOffscreenRight() {
        let p = pickEdgeTarget(bounds: Self.bounds, blobSize: Self.blobSize, edgeIndex: 3, rngAlong: 0.5)
        #expect(p == Point(x: 968.8, y: 369))
    }

    // MARK: clampVisible

    @Test func clampVisible_pointFarOffLeftTop_clampsToMinVisibleFloor() {
        let p = clampVisible(
            point: Point(x: -500, y: -500), bounds: Self.bounds, blobSize: Self.blobSize, minVisible: 10
        )
        // -(blobSize.width - minVisible) = -(78-10) = -68; same for y with height 62 -> -52
        #expect(p == Point(x: -68, y: -52))
    }

    @Test func clampVisible_pointFarOffRightBottom_clampsToBoundsMinusMinVisible() {
        let p = clampVisible(
            point: Point(x: 5000, y: 5000), bounds: Self.bounds, blobSize: Self.blobSize, minVisible: 10
        )
        #expect(p == Point(x: 990, y: 790))
    }

    @Test func clampVisible_pointAlreadyOnscreen_isUnchanged() {
        let p = clampVisible(
            point: Point(x: 500, y: 400), bounds: Self.bounds, blobSize: Self.blobSize, minVisible: 10
        )
        #expect(p == Point(x: 500, y: 400))
    }
}
