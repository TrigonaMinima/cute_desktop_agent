import Testing
@testable import AgentCore

// Cursor motion is a derived perceived signal, not something AgentApp's Perception layer
// reads from the OS directly (macOS has no "cursor velocity" API) — it's computed here in
// AgentCore from two polled positions and a frame dt, so the math is pure and unit-tested
// like the rest of Geometry.swift's helpers.
struct CursorMotionTests {

    // MARK: cursorVelocity

    @Test func cursorVelocity_stationaryCursor_isZero() {
        let v = cursorVelocity(from: Point(x: 100, y: 100), to: Point(x: 100, y: 100), dt: 0.1)
        #expect(v.dx == 0)
        #expect(v.dy == 0)
    }

    @Test func cursorVelocity_movingRight_isPositiveDxInPixelsPerSecond() {
        // 50px over 0.5s == 100 px/sec, matching the px/sec convention of Constants.moveSpeed.
        let v = cursorVelocity(from: Point(x: 0, y: 0), to: Point(x: 50, y: 0), dt: 0.5)
        #expect(v.dx == 100)
        #expect(v.dy == 0)
    }

    @Test func cursorVelocity_movingBackward_isNegative() {
        let v = cursorVelocity(from: Point(x: 100, y: 100), to: Point(x: 80, y: 90), dt: 0.5)
        #expect(v.dx == -40)
        #expect(v.dy == -20)
    }

    @Test func cursorVelocity_zeroDt_isZero_notNaNOrInfinite() {
        // Guards the first-frame case (no previous dt yet) and FrameClock's dt==0 floor.
        let v = cursorVelocity(from: Point(x: 0, y: 0), to: Point(x: 50, y: 50), dt: 0)
        #expect(v.dx == 0)
        #expect(v.dy == 0)
    }

    @Test func cursorVelocity_negativeDt_isZero() {
        // Defensive: should never happen (FrameClock clamps dt to [0, 0.1]), but the guard
        // is `dt > 0`, not `dt != 0` — confirm negative dt doesn't slip through.
        let v = cursorVelocity(from: Point(x: 0, y: 0), to: Point(x: 50, y: 50), dt: -0.1)
        #expect(v.dx == 0)
        #expect(v.dy == 0)
    }

    // MARK: Vector.magnitude

    @Test func vectorMagnitude_ofThreeFourVector_isFive() {
        #expect(Vector(dx: 3, dy: 4).magnitude == 5)
    }

    @Test func vectorMagnitude_ofZeroVector_isZero() {
        #expect(Vector(dx: 0, dy: 0).magnitude == 0)
    }

    // MARK: AgentWorld.cursorMoving

    @Test func cursorMoving_velocityBelowThreshold_isFalse() {
        let world = AgentWorld(
            screenBounds: Size(width: 1000, height: 800), cursor: Point(x: 0, y: 0),
            cursorVelocity: Vector(dx: 1, dy: 0)
        )
        #expect(world.cursorMoving == false)
    }

    @Test func cursorMoving_velocityAboveThreshold_isTrue() {
        let world = AgentWorld(
            screenBounds: Size(width: 1000, height: 800), cursor: Point(x: 0, y: 0),
            cursorVelocity: Vector(dx: 100, dy: 0)
        )
        #expect(world.cursorMoving == true)
    }

    @Test func cursorMoving_zeroVelocity_isFalse() {
        let world = AgentWorld(screenBounds: Size(width: 1000, height: 800), cursor: Point(x: 0, y: 0))
        #expect(world.cursorMoving == false)
    }
}
