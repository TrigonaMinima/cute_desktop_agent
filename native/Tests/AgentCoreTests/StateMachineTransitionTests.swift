import Testing
@testable import AgentCore

// Ported behavior from electron-poc/renderer/blob.js's startMode/transitionToNextMode/
// updateMovement/maybeAdvanceMode/triggerHappy/updateHappy/updateBlink/
// updateEmotionTriggers, plus drag handling. These tests exercise `StateMachine`'s
// internal (module-testable) functions at the same granularity as the JS source, so a
// failure points at exactly which ported function regressed. `SeededRandom` +
// `ManualClock` make every timer/branch deterministic.
struct StateMachineTransitionTests {

    // MARK: - startMode: idle sets modeEndsAt at mode start; wander/rest/peek don't.

    @Test func startMode_idle_setsModeEndsAtAtModeStart_andDoesNotMove() {
        let sm = StateMachine(rng: SeededRandom(seed: 42), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        sm.startMode(.idle, state: &state, now: 1000)
        #expect(state.body.mode == .idle)
        #expect(state.body.moving == false)
        let range = Constants.modeDwellMsRange[.idle]!
        #expect(state.memory.modeEndsAt >= 1000 + range.min)
        #expect(state.memory.modeEndsAt <= 1000 + range.max)
    }

    @Test func startMode_wander_setsTargetAndMoving_leavesModeEndsAtUntouched() {
        let sm = StateMachine(rng: SeededRandom(seed: 7), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.modeEndsAt = 999 // sentinel: startMode must not touch this for wander
        sm.startMode(.wander, state: &state, now: 1000)
        #expect(state.body.mode == .wander)
        #expect(state.body.moving == true)
        #expect(state.memory.modeEndsAt == 999)
    }

    @Test func startMode_rest_setsTargetAndMoving_leavesModeEndsAtUntouched() {
        let sm = StateMachine(rng: SeededRandom(seed: 8), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.modeEndsAt = 999
        sm.startMode(.rest, state: &state, now: 1000)
        #expect(state.body.mode == .rest)
        #expect(state.body.moving == true)
        #expect(state.memory.modeEndsAt == 999)
    }

    @Test func startMode_peek_setsTargetAndMoving_leavesModeEndsAtUntouched() {
        let sm = StateMachine(rng: SeededRandom(seed: 9), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.modeEndsAt = 999
        sm.startMode(.peek, state: &state, now: 1000)
        #expect(state.body.mode == .peek)
        #expect(state.body.moving == true)
        #expect(state.memory.modeEndsAt == 999)
    }

    // MARK: - updateMovement: arrival sets modeEndsAt for the *current* mode; peek sets pendingReturn.

    @Test func updateMovement_onArrival_setsModeEndsAtForCurrentMode() {
        let sm = StateMachine(rng: SeededRandom(seed: 3), clock: ManualClock(start: 5000))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: 100, y: 100))
        state.body.target = Point(x: 101, y: 100) // within ARRIVE_THRESHOLD (4)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.016, now: 5000)
        #expect(state.body.moving == false)
        let range = Constants.modeDwellMsRange[.wander]!
        #expect(state.memory.modeEndsAt >= 5000 + range.min)
        #expect(state.memory.modeEndsAt <= 5000 + range.max)
    }

    @Test func updateMovement_onArrival_snapsToClampVisibleSafeTarget() {
        let sm = StateMachine(rng: SeededRandom(seed: 3), clock: ManualClock(start: 5000))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: -998, y: 100))
        // Target sits just off the left edge past minVisible's floor; arrival must snap
        // to clampVisible's safe point, not the raw (unsafe) target.
        state.body.target = Point(x: -1000, y: 100)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.016, now: 5000)
        let safe = clampVisible(point: Point(x: -1000, y: 100), bounds: TestFixtures.bounds, blobSize: TestFixtures.blobSize, minVisible: Constants.minVisible)
        #expect(state.body.position == safe)
    }

    @Test func updateMovement_onArrival_whilePeek_setsPendingReturnTrue() {
        let sm = StateMachine(rng: SeededRandom(seed: 11), clock: ManualClock(start: 2000))
        var state = TestFixtures.makeState(mode: .peek, position: Point(x: -50, y: 100))
        state.body.target = Point(x: -49, y: 100)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.016, now: 2000)
        #expect(state.memory.pendingReturn == true)
    }

    @Test func updateMovement_onArrival_whileNotPeek_leavesPendingReturnFalse() {
        let sm = StateMachine(rng: SeededRandom(seed: 12), clock: ManualClock(start: 2000))
        var state = TestFixtures.makeState(mode: .rest, position: Point(x: 100, y: 100))
        state.body.target = Point(x: 101, y: 100)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.016, now: 2000)
        #expect(state.memory.pendingReturn == false)
    }

    @Test func updateMovement_notYetArrived_stepsTowardTargetAtMoveSpeed() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: 0, y: 0))
        state.body.target = Point(x: 100, y: 0)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.5, now: 0) // step = 80 * 0.5 = 40; t = 40/100 = 0.4
        #expect(state.body.position.x.isApproximately(40))
        #expect(state.body.position.y.isApproximately(0))
        #expect(state.body.moving == true)
    }

    @Test func updateMovement_whileNotMoving_doesNothing() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: 5, y: 5))
        state.body.target = Point(x: 500, y: 500)
        state.body.moving = false
        sm.updateMovement(state: &state, dt: 1.0, now: 0)
        #expect(state.body.position == Point(x: 5, y: 5))
    }

    // MARK: - maybeAdvanceMode

    @Test func maybeAdvanceMode_peekPendingReturn_pastModeEndsAt_transitionsToWander() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 10_000))
        var state = TestFixtures.makeState(mode: .peek)
        state.body.moving = false
        state.memory.pendingReturn = true
        state.memory.modeEndsAt = 9_999
        sm.maybeAdvanceMode(state: &state, now: 10_000)
        #expect(state.body.mode == .wander)
        #expect(state.memory.pendingReturn == false)
        #expect(state.body.moving == true)
    }

    @Test func maybeAdvanceMode_whileMoving_doesNothingEvenPastModeEndsAt() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 100))
        var state = TestFixtures.makeState(mode: .wander)
        state.body.moving = true
        state.memory.modeEndsAt = 0
        sm.maybeAdvanceMode(state: &state, now: 100)
        #expect(state.body.mode == .wander)
    }

    @Test func maybeAdvanceMode_beforeModeEndsAt_doesNothing() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 100))
        var state = TestFixtures.makeState(mode: .idle)
        state.body.moving = false
        state.memory.modeEndsAt = 5_000
        sm.maybeAdvanceMode(state: &state, now: 100)
        #expect(state.body.mode == .idle)
    }

    @Test func maybeAdvanceMode_pastModeEndsAt_transitionsViaWeightedChoice() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 100))
        var state = TestFixtures.makeState(mode: .idle)
        state.body.moving = false
        state.memory.modeEndsAt = 0
        sm.maybeAdvanceMode(state: &state, now: 100)
        #expect(Mode.allCases.contains(state.body.mode))
    }

    // MARK: - triggerHappy / updateHappy

    @Test func triggerHappy_savesCurrentModeAsResume_setsFixed500msWindow() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 2000))
        var state = TestFixtures.makeState(mode: .wander)
        sm.triggerHappy(state: &state, now: 2000)
        #expect(state.body.mode == .happy)
        #expect(state.memory.happyResumeMode == .wander)
        #expect(state.memory.happyUntil == 2000 + Constants.happyDurationMs)
        #expect(state.body.moving == false)
    }

    @Test func triggerHappy_whileAlreadyHappy_keepsOriginalResumeMode() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 2000))
        var state = TestFixtures.makeState(mode: .happy)
        state.memory.happyResumeMode = .rest
        sm.triggerHappy(state: &state, now: 2000)
        #expect(state.memory.happyResumeMode == .rest)
    }

    @Test func updateHappy_pastHappyUntil_resumesPriorMode_withHardcodedDwellRange_notModesOwnRange() {
        let sm = StateMachine(rng: SeededRandom(seed: 9), clock: ManualClock(start: 3000))
        var state = TestFixtures.makeState(mode: .happy)
        state.memory.happyResumeMode = .rest
        state.memory.happyUntil = 2999
        sm.updateHappy(state: &state, now: 3000)
        #expect(state.body.mode == .rest)
        // This is Constants.happyResumeDwellMsRange (800-1500), a distinct literal from
        // Constants.modeDwellMsRange[.rest] (6000-12000) — the resumed mode's own dwell
        // table must NOT be consulted here.
        #expect(state.memory.modeEndsAt >= 3000 + Constants.happyResumeDwellMsRange.min)
        #expect(state.memory.modeEndsAt <= 3000 + Constants.happyResumeDwellMsRange.max)
    }

    @Test func updateHappy_stillWithinHappyUntil_doesNothing() {
        let sm = StateMachine(rng: SeededRandom(seed: 9), clock: ManualClock(start: 3000))
        var state = TestFixtures.makeState(mode: .happy)
        state.memory.happyUntil = 3500
        sm.updateHappy(state: &state, now: 3000)
        #expect(state.body.mode == .happy)
    }

    @Test func updateHappy_whileNotHappy_doesNothing() {
        let sm = StateMachine(rng: SeededRandom(seed: 9), clock: ManualClock(start: 3000))
        var state = TestFixtures.makeState(mode: .idle)
        state.memory.happyUntil = 0
        sm.updateHappy(state: &state, now: 3000)
        #expect(state.body.mode == .idle)
    }

    // MARK: - updateBlink

    @Test func updateBlink_pastNextBlinkAt_startsBlink_forFixed120ms_andReschedulesNext() {
        let sm = StateMachine(rng: SeededRandom(seed: 5), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.nextBlinkAt = 999
        sm.updateBlink(state: &state, now: 1000)
        #expect(state.memory.blinking == true)
        #expect(state.memory.blinkEndsAt == 1000 + Constants.blinkActiveMs)
        #expect(state.memory.nextBlinkAt >= 1000 + Constants.blinkIntervalMsRange.min)
        #expect(state.memory.nextBlinkAt <= 1000 + Constants.blinkIntervalMsRange.max)
    }

    @Test func updateBlink_pastBlinkEndsAt_turnsBlinkOff() {
        let sm = StateMachine(rng: SeededRandom(seed: 5), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.blinking = true
        state.memory.blinkEndsAt = 999
        state.memory.nextBlinkAt = 5000
        sm.updateBlink(state: &state, now: 1000)
        #expect(state.memory.blinking == false)
    }

    @Test func updateBlink_beforeNextBlinkAt_doesNotStartBlink() {
        let sm = StateMachine(rng: SeededRandom(seed: 5), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState()
        state.memory.nextBlinkAt = 5000
        sm.updateBlink(state: &state, now: 1000)
        #expect(state.memory.blinking == false)
    }

    // MARK: - updateEmotionTriggers: quirks

    @Test func updateEmotionTriggers_idleAndQuirkDue_setsQuirkEmotionAndSchedulesNext() {
        let sm = StateMachine(rng: SeededRandom(seed: 21), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle)
        state.memory.quirkUntil = 0
        state.memory.nextQuirkAt = 0
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.quirkEmotion != nil)
        #expect(Constants.quirkEmotions.contains(state.memory.quirkEmotion!))
        #expect(state.memory.quirkUntil > 1000)
        #expect(state.memory.nextQuirkAt > state.memory.quirkUntil)
    }

    @Test func updateEmotionTriggers_whileDragging_doesNotTriggerQuirk() {
        let sm = StateMachine(rng: SeededRandom(seed: 21), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle)
        state.body.dragging = true
        state.memory.quirkUntil = 0
        state.memory.nextQuirkAt = 0
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.quirkEmotion == nil)
    }

    @Test func updateEmotionTriggers_notIdleMode_doesNotTriggerQuirk() {
        let sm = StateMachine(rng: SeededRandom(seed: 21), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .wander)
        state.memory.quirkUntil = 0
        state.memory.nextQuirkAt = 0
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.quirkEmotion == nil)
    }

    @Test func updateEmotionTriggers_quirkStillActive_doesNotRetrigger() {
        let sm = StateMachine(rng: SeededRandom(seed: 21), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle)
        state.memory.quirkEmotion = .blush
        state.memory.quirkUntil = 5000
        state.memory.nextQuirkAt = 0
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.quirkEmotion == .blush)
        #expect(state.memory.quirkUntil == 5000)
    }

    // MARK: - updateEmotionTriggers: proximity

    @Test func updateEmotionTriggers_cursorWithinProximityRadius_triggersStartle() {
        let sm = StateMachine(rng: SeededRandom(seed: 33), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle, position: Point(x: 100, y: 100))
        // avatar center = (100 + 39, 100 + 31) = (139, 131); put cursor 10px away.
        state.world.cursor = Point(x: 149, y: 131)
        state.memory.proximityCooldownUntil = 0
        // Push the quirk timer far out so this test isolates the proximity branch.
        state.memory.quirkUntil = 0
        state.memory.nextQuirkAt = 999_999
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.proximityUntil == 1000 + Constants.proximityDurationMs)
        #expect(state.memory.proximityCooldownUntil >= 1000 + Constants.proximityCooldownMsRange.min)
        #expect(state.memory.proximityCooldownUntil <= 1000 + Constants.proximityCooldownMsRange.max)
    }

    @Test func updateEmotionTriggers_cursorFarAway_doesNotTriggerProximity() {
        let sm = StateMachine(rng: SeededRandom(seed: 33), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle, position: Point(x: 100, y: 100))
        state.world.cursor = Point(x: 900, y: 700)
        state.memory.proximityCooldownUntil = 0
        state.memory.nextQuirkAt = 999_999
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.proximityUntil == 0)
    }

    @Test func updateEmotionTriggers_duringProximityCooldown_doesNotRetrigger() {
        let sm = StateMachine(rng: SeededRandom(seed: 33), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .idle, position: Point(x: 100, y: 100))
        state.world.cursor = Point(x: 149, y: 131)
        state.memory.proximityCooldownUntil = 5000
        state.memory.proximityUntil = 0
        state.memory.nextQuirkAt = 999_999
        sm.updateEmotionTriggers(state: &state, now: 1000)
        #expect(state.memory.proximityUntil == 0)
    }

    // MARK: - drag: hard-clamped to [0, bounds - blobSize], no clampVisible negative floor.

    @Test func beginDrag_capturesOffsetFromCursorToPosition_andStopsMovement() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: 100, y: 100), cursor: Point(x: 130, y: 150))
        state.body.moving = true
        sm.beginDrag(state: &state)
        #expect(state.body.dragging == true)
        #expect(state.body.moving == false)
        #expect(state.body.dragOffset == Vector(dx: 30, dy: 50))
    }

    @Test func updateDrag_followsCursorMinusOffset() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), cursor: Point(x: 240, y: 260))
        state.body.dragging = true
        state.body.dragOffset = Vector(dx: 10, dy: 10)
        sm.updateDrag(state: &state)
        #expect(state.body.position == Point(x: 230, y: 250))
    }

    @Test func updateDrag_cursorFarOffTopLeft_hardClampsToZero_notClampVisibleNegativeFloor() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), cursor: Point(x: -500, y: -500))
        state.body.dragging = true
        state.body.dragOffset = Vector(dx: 10, dy: 10)
        sm.updateDrag(state: &state)
        #expect(state.body.position == Point(x: 0, y: 0))
    }

    @Test func updateDrag_cursorFarOffBottomRight_clampsToBoundsMinusBlobSize() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), cursor: Point(x: 5000, y: 5000))
        state.body.dragging = true
        state.body.dragOffset = Vector(dx: 0, dy: 0)
        sm.updateDrag(state: &state)
        #expect(state.body.position == Point(x: TestFixtures.bounds.width - TestFixtures.blobSize.width, y: TestFixtures.bounds.height - TestFixtures.blobSize.height))
    }

    @Test func endDrag_stopsDragging_andTriggersHappyBounce() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 4000))
        var state = TestFixtures.makeState(mode: .wander)
        state.body.dragging = true
        sm.endDrag(state: &state, now: 4000)
        #expect(state.body.dragging == false)
        #expect(state.body.mode == .happy)
        #expect(state.memory.happyResumeMode == .wander)
        #expect(state.memory.happyUntil == 4000 + Constants.happyDurationMs)
    }

    // MARK: - tick: dragging gates movement/mode-advance/happy-resume, not blink/emotion.

    @Test func tick_whileDragging_skipsMovement_butStillBlinksAndSetsEmotionToSurprised() {
        let sm = StateMachine(rng: SeededRandom(seed: 2), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .wander, position: Point(x: 0, y: 0))
        state.body.target = Point(x: 500, y: 0)
        state.body.moving = true
        state.body.dragging = true
        state.memory.nextBlinkAt = 999
        sm.tick(state: &state, dt: 1.0)
        #expect(state.body.position == Point(x: 0, y: 0))
        #expect(state.body.moving == true)
        #expect(state.body.emotion == .surprised)
        #expect(state.memory.blinking == true)
    }

    @Test func tick_notDragging_setsEmotionFromCurrentMode() {
        let sm = StateMachine(rng: SeededRandom(seed: 4), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(mode: .rest, position: Point(x: 0, y: 0))
        // Keep modeEndsAt safely in the future so maybeAdvanceMode doesn't transition
        // away from .rest mid-tick — this test isolates emotion-from-mode, not advancement.
        state.memory.modeEndsAt = 10_000
        sm.tick(state: &state, dt: 0.5)
        #expect(state.body.emotion == .sleepy)
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.0001) -> Bool {
        abs(self - other) <= tolerance
    }
}
