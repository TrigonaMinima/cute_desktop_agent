import Testing
@testable import AgentCore

// Uses Swift Testing (`import Testing`), not XCTest: the CLT SDK ships Testing.framework
// directly in the Swift 6.3 toolchain (Library/Developer/Frameworks/Testing.framework)
// but has no XCTest.swiftmodule — XCTest is an Xcode-distributed framework. Swift Testing
// keeps `swift test` fully Xcode-independent, consistent with the rest of this build.
struct GeometryTests {

    // MARK: clamp

    @Test func clamp_returnsValue_whenWithinRange() {
        #expect(clamp(5, min: 0, max: 10) == 5)
    }

    @Test func clamp_returnsMin_whenBelowRange() {
        #expect(clamp(-5, min: 0, max: 10) == 0)
    }

    @Test func clamp_returnsMax_whenAboveRange() {
        #expect(clamp(15, min: 0, max: 10) == 10)
    }

    // MARK: lerp

    @Test func lerp_atZero_returnsStart() {
        #expect(lerp(10, 20, 0) == 10)
    }

    @Test func lerp_atOne_returnsEnd() {
        #expect(lerp(10, 20, 1) == 20)
    }

    @Test func lerp_atHalf_returnsMidpoint() {
        #expect(lerp(10, 20, 0.5) == 15)
    }

    // MARK: distance

    @Test func distance_ofThreeFourFiveTriangle_isFive() {
        #expect(abs(distance(ax: 0, ay: 0, bx: 3, by: 4) - 5) < 1e-9)
    }

    @Test func distance_ofSamePoint_isZero() {
        #expect(distance(ax: 7, ay: 7, bx: 7, by: 7) == 0)
    }

    // MARK: weightedChoice

    @Test func weightedChoice_atRngZero_returnsFirstKey() {
        let weights: [(String, Double)] = [("idle", 0.5), ("wander", 0.2), ("rest", 0.25), ("peek", 0.05)]
        #expect(weightedChoice(weights, rngValue: 0) == "idle")
    }

    @Test func weightedChoice_justBelowFirstCumulativeBoundary_returnsFirstKey() {
        let weights: [(String, Double)] = [("idle", 0.5), ("wander", 0.2), ("rest", 0.25), ("peek", 0.05)]
        // total = 1.0, first boundary at 0.5 — just under it must still be "idle"
        #expect(weightedChoice(weights, rngValue: 0.499) == "idle")
    }

    @Test func weightedChoice_exactlyAtCumulativeBoundary_returnsThatKey() {
        let weights: [(String, Double)] = [("idle", 0.5), ("wander", 0.2), ("rest", 0.25), ("peek", 0.05)]
        // target <= acc is the tie rule: exactly 0.5 belongs to "idle" (first key whose
        // cumulative sum reaches it), not "wander".
        #expect(weightedChoice(weights, rngValue: 0.5) == "idle")
    }

    @Test func weightedChoice_justAboveBoundary_returnsNextKey() {
        let weights: [(String, Double)] = [("idle", 0.5), ("wander", 0.2), ("rest", 0.25), ("peek", 0.05)]
        #expect(weightedChoice(weights, rngValue: 0.51) == "wander")
    }

    @Test func weightedChoice_atRngOne_returnsLastKey() {
        let weights: [(String, Double)] = [("idle", 0.5), ("wander", 0.2), ("rest", 0.25), ("peek", 0.05)]
        #expect(weightedChoice(weights, rngValue: 1.0) == "peek")
    }

    @Test func weightedChoice_preservesInsertionOrder_notSortedOrder() {
        // Deliberately out-of-alphabetical, out-of-magnitude order — a Dictionary-backed
        // implementation would not preserve this, which is why weights is an ordered
        // array of pairs, matching the JS Object.entries() insertion-order iteration.
        let weights: [(String, Double)] = [("z", 0.9), ("a", 0.1)]
        #expect(weightedChoice(weights, rngValue: 0) == "z")
        #expect(weightedChoice(weights, rngValue: 0.95) == "a")
    }

    // MARK: isHovering
    //
    // Mechanical port of blob.js's updateHoverState's withinX/withinY inequalities
    // (lines 286-287): cursor.x >= state.x && cursor.x <= state.x + BLOB_WIDTH, same for
    // y. Both edges are inclusive, and `position` is the avatar's top-left corner. Pure
    // geometry only — toggling ignoresMouseEvents from the result is AppKit-side (Phase 5).

    @Test func isHovering_cursorWellInsideBounds_returnsTrue() {
        let hit = isHovering(
            cursor: Point(x: 50, y: 40), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        #expect(hit == true)
    }

    @Test func isHovering_cursorWellOutsideBounds_returnsFalse() {
        let hit = isHovering(
            cursor: Point(x: 500, y: 500), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        #expect(hit == false)
    }

    @Test func isHovering_cursorExactlyAtTopLeftCorner_returnsTrue_inclusiveEdge() {
        let hit = isHovering(
            cursor: Point(x: 10, y: 10), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        #expect(hit == true)
    }

    @Test func isHovering_cursorExactlyAtBottomRightCorner_returnsTrue_inclusiveEdge() {
        let hit = isHovering(
            cursor: Point(x: 88, y: 72), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        #expect(hit == true)
    }

    @Test func isHovering_cursorOnePastBottomRightCorner_returnsFalse() {
        let hitX = isHovering(
            cursor: Point(x: 88.01, y: 40), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        let hitY = isHovering(
            cursor: Point(x: 50, y: 72.01), position: Point(x: 10, y: 10), size: Size(width: 78, height: 62)
        )
        #expect(hitX == false)
        #expect(hitY == false)
    }

    // MARK: moveToward

    @Test func moveToward_farFromTarget_stepsByExactlyMaxDistance() {
        let next = moveToward(Point(x: 0, y: 0), Point(x: 100, y: 0), maxDistance: 30)
        #expect(abs(next.x - 30) < 1e-9)
        #expect(next.y == 0)
    }

    @Test func moveToward_withinMaxDistanceOfTarget_snapsExactlyToTarget() {
        let next = moveToward(Point(x: 95, y: 0), Point(x: 100, y: 0), maxDistance: 30)
        #expect(next == Point(x: 100, y: 0))
    }

    @Test func moveToward_alreadyAtTarget_staysAtTarget() {
        let next = moveToward(Point(x: 100, y: 0), Point(x: 100, y: 0), maxDistance: 30)
        #expect(next == Point(x: 100, y: 0))
    }

    @Test func moveToward_diagonalTarget_movesAlongTheStraightLine() {
        // 3-4-5 triangle: distance is 5, so a maxDistance of 2.5 covers exactly half.
        let next = moveToward(Point(x: 0, y: 0), Point(x: 3, y: 4), maxDistance: 2.5)
        #expect(abs(next.x - 1.5) < 1e-9)
        #expect(abs(next.y - 2.0) < 1e-9)
    }

    @Test func moveToward_zeroMaxDistance_doesNotMove() {
        let next = moveToward(Point(x: 10, y: 10), Point(x: 100, y: 100), maxDistance: 0)
        #expect(next == Point(x: 10, y: 10))
    }
}
