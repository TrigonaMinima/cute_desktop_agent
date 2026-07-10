import Foundation
import Testing
@testable import AgentCore

// Mechanical port of electron-poc/renderer/blob.js's render() transform math (squash/
// stretch scale + vertical bob) — the frame-clock's per-tick derivation from AgentState,
// independent of the Clock/RandomProvider machinery since it takes `now` directly as an
// argument (like computeDesiredEmotion). Branch priority: dragging > happy mode > moving
// > idle breathing. Literal expected numbers are pinned straight from blob.js, not routed
// back through Constants, so a drifted constant would fail these tests.
struct BodyMotionTests {

    // MARK: dragging

    @Test func dragging_appliesFixedSquashAndNoBob() {
        let state = TestFixtures.makeState(mode: .idle, dragging: true, moving: true)
        let motion = computeBodyMotion(state: state, now: 250)
        #expect(motion.scaleX == 1.05)
        #expect(motion.scaleY == 0.95)
        #expect(motion.bobY == 0)
    }

    @Test func dragging_beatsHappyAndMoving() {
        let state = TestFixtures.makeState(mode: .happy, dragging: true, moving: true, happyUntil: 5000)
        let motion = computeBodyMotion(state: state, now: 1000)
        #expect(motion.scaleX == 1.05)
        #expect(motion.scaleY == 0.95)
    }

    // MARK: happy

    // progress = clamp(1 - (happyUntil - now)/500, 0, 1); at happyUntil-now == 500 -> progress 0
    // -> bounce = sin(0 * pi * 3) * (1 - 0) = 0 -> no scale change.
    @Test func happy_atBounceStart_isUnscaled() {
        let state = TestFixtures.makeState(mode: .happy, happyUntil: 1500)
        let motion = computeBodyMotion(state: state, now: 1000)
        #expect(motion.scaleX == 1)
        #expect(motion.scaleY == 1)
        #expect(motion.bobY == 0)
    }

    // happyUntil-now == 250 -> progress 0.5 -> bounce = sin(1.5*pi) * 0.5 = -1 * 0.5 = -0.5
    @Test func happy_atBounceMidpoint_scalesYUpAndXDown() {
        let state = TestFixtures.makeState(mode: .happy, happyUntil: 1250)
        let motion = computeBodyMotion(state: state, now: 1000)
        #expect(motion.scaleY == 1 + (-0.5) * 0.25)
        #expect(motion.scaleX == 1 - (-0.5) * 0.15)
        #expect(motion.bobY == 0)
    }

    // happyUntil already passed -> progress clamps to 1 -> bounce = sin(3*pi) * 0 = 0.
    @Test func happy_afterHappyUntil_progressClampsToOne_bounceIsZero() {
        let state = TestFixtures.makeState(mode: .happy, happyUntil: 500)
        let motion = computeBodyMotion(state: state, now: 1000)
        #expect(motion.scaleX == 1)
        #expect(motion.scaleY == 1)
    }

    @Test func happy_ignoresWobbleBob_evenWhenNotDragging() {
        let state = TestFixtures.makeState(mode: .happy, happyUntil: 1500)
        let motion = computeBodyMotion(state: state, now: 1000)
        #expect(motion.bobY == 0)
    }

    // MARK: moving

    @Test func moving_appliesFixedSquashAndWobbleBob() {
        let state = TestFixtures.makeState(mode: .wander, moving: true)
        let now = 250.0
        let motion = computeBodyMotion(state: state, now: now)
        let wobble = sin(now / 1000 * 2.2)
        #expect(motion.scaleX == 1.08)
        #expect(motion.scaleY == 0.92)
        #expect(motion.bobY == wobble * 3)
    }

    // MARK: idle

    @Test func idle_atZeroWobble_isUnscaledWithNoBob() {
        let state = TestFixtures.makeState(mode: .idle)
        let motion = computeBodyMotion(state: state, now: 0)
        #expect(motion.scaleX == 1)
        #expect(motion.scaleY == 1)
        #expect(motion.bobY == 0)
    }

    @Test func idle_appliesBreathingWobbleAndBob() {
        let state = TestFixtures.makeState(mode: .idle)
        let now = 250.0
        let motion = computeBodyMotion(state: state, now: now)
        let wobble = sin(now / 1000 * 2.2)
        #expect(motion.scaleY == 1 + wobble * 0.03)
        #expect(motion.scaleX == 1 - wobble * 0.02)
        #expect(motion.bobY == wobble * 3)
    }

    @Test func wander_withoutMoving_usesIdleBreathingBranch() {
        // "moving" is the branch discriminant, not mode — wander that has arrived
        // (moving == false) breathes like idle.
        let state = TestFixtures.makeState(mode: .wander, moving: false)
        let now = 250.0
        let motion = computeBodyMotion(state: state, now: now)
        let wobble = sin(now / 1000 * 2.2)
        #expect(motion.scaleY == 1 + wobble * 0.03)
        #expect(motion.scaleX == 1 - wobble * 0.02)
    }

    // MARK: emergent mind path (physics-driven squash, no canned move-squash clip)

    private func makeMindState(
        squash: Vector = Vector(dx: 0, dy: 0), dragging: Bool = false, moving: Bool = false
    ) -> AgentState {
        var state = TestFixtures.makeState(mode: .idle, dragging: dragging, moving: moving)
        var mind = MindState(
            temperament: .calm, position: state.body.position, hourOfDay: 15, now: 0
        )
        mind.physics.squash = squash
        state.mind = mind
        return state
    }

    @Test func mindPath_physicsSquashMapsStraightToScale() {
        let state = makeMindState(squash: Vector(dx: 0.2, dy: -0.1))
        let motion = computeBodyMotion(state: state, now: 0) // wobble 0
        #expect(motion.scaleX == 1.2)
        #expect(motion.scaleY == 0.9)
    }

    @Test func mindPath_moving_doesNotUseTheFixedMovingSquash() {
        // Deformation follows real acceleration (the physics spring), not a canned
        // moving-scale clip — zero squash while moving renders undeformed.
        let state = makeMindState(moving: true)
        let motion = computeBodyMotion(state: state, now: 0)
        #expect(motion.scaleX == 1)
        #expect(motion.scaleY == 1)
    }

    @Test func mindPath_breathingWobbleComposesWithSquash() {
        let state = makeMindState(squash: Vector(dx: 0.1, dy: 0.1))
        let now = 250.0
        let motion = computeBodyMotion(state: state, now: now)
        let wobble = sin(now / 1000 * 2.2)
        #expect(motion.scaleX == 1 - wobble * 0.02 + 0.1)
        #expect(motion.scaleY == 1 + wobble * 0.03 + 0.1)
        #expect(motion.bobY == wobble * 3)
    }

    @Test func mindPath_dragging_keepsTheClassicDragSquash() {
        let state = makeMindState(squash: Vector(dx: 0.2, dy: 0.2), dragging: true)
        let motion = computeBodyMotion(state: state, now: 250)
        #expect(motion.scaleX == 1.05)
        #expect(motion.scaleY == 0.95)
        #expect(motion.bobY == 0)
    }
}
