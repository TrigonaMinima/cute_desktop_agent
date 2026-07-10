import Testing
@testable import AgentCore

// Multi-display behavior: the screen-switch draw when starting wander/rest, the
// single-screen RNG-sequence guarantee (no extra draw, so existing seeded behavior is
// byte-identical), mid-glide dead-zone tolerance via reconcilePosition, arrival/drag
// confinement to the relevant screen's rect. Fixtures: TestFixtures.twoScreens =
// primary (0,0,1000x800 "Main") + secondary (1200,100,800x600 "Side"), 200px dead zone.
struct MultiScreenBehaviorTests {
    static let screens = TestFixtures.twoScreens
    static let blobSize = TestFixtures.blobSize

    // MARK: - startMode: screen-switch draw (only when screens.count > 1)

    @Test func startMode_wander_switchDrawBelowProbability_targetsTheOtherScreen() {
        let sm = StateMachine(rng: ScriptedRandom([0.1]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), screens: Self.screens)
        sm.startMode(.wander, state: &state, now: 0)
        #expect(screenIndex(containing: state.body.target, screens: Self.screens) == 1)
        #expect(state.body.moving == true)
    }

    @Test func startMode_wander_switchDrawAtOrAboveProbability_staysOnCurrentScreen() {
        let sm = StateMachine(rng: ScriptedRandom([0.9]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), screens: Self.screens)
        sm.startMode(.wander, state: &state, now: 0)
        #expect(screenIndex(containing: state.body.target, screens: Self.screens) == 0)
    }

    @Test func startMode_rest_switchDrawBelowProbability_picksCornerOnTheOtherScreen() {
        let sm = StateMachine(rng: ScriptedRandom([0.1]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), screens: Self.screens)
        sm.startMode(.rest, state: &state, now: 0)
        #expect(screenIndex(containing: state.body.target, screens: Self.screens) == 1)
    }

    @Test func startMode_wander_fromTheSecondScreen_switchDrawReturnsToPrimary() {
        let sm = StateMachine(rng: ScriptedRandom([0.1]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 1500, y: 400), screens: Self.screens)
        sm.startMode(.wander, state: &state, now: 0)
        #expect(screenIndex(containing: state.body.target, screens: Self.screens) == 0)
    }

    @Test func startMode_wander_twoScreens_consumesTheSwitchDrawBeforeBiasAlongDepth() {
        // Pin the full draw order (switch, bias tie-break, along, depth) by reproducing
        // the stay-home target from an independent reference computation.
        let sm = StateMachine(rng: ScriptedRandom([0.9, 0.3, 0.6, 0.8]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100), screens: Self.screens)
        sm.startMode(.wander, state: &state, now: 0)

        let home = TestFixtures.screen.frame
        let candidates = (0..<4).map {
            pickBorderPoint(
                screen: home, margin: Constants.roamMargin, blobSize: Self.blobSize,
                bandDepth: Constants.borderBandDepth, edgeIndex: $0, rngAlong: 0.5, rngDepth: 0.5
            )
        }
        let edgeIndex = farthestIndex(anchor: Point(x: 0, y: 0), candidates: candidates, rngValue: 0.3)
        let expected = pickBorderPoint(
            screen: home, margin: Constants.roamMargin, blobSize: Self.blobSize,
            bandDepth: Constants.borderBandDepth, edgeIndex: edgeIndex, rngAlong: 0.6, rngDepth: 0.8
        )
        #expect(state.body.target == expected)
    }

    @Test func startMode_wander_singleScreen_consumesNoSwitchDraw_preservingSeededSequences() {
        // Same scripted values as the two-screen draw-order test above, but with one
        // screen the FIRST value must feed the bias tie-break, not a switch decision —
        // this is what keeps every pre-existing seeded single-screen test byte-identical.
        let sm = StateMachine(rng: ScriptedRandom([0.3, 0.6, 0.8]), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(position: Point(x: 100, y: 100))
        sm.startMode(.wander, state: &state, now: 0)

        let home = TestFixtures.screen.frame
        let candidates = (0..<4).map {
            pickBorderPoint(
                screen: home, margin: Constants.roamMargin, blobSize: Self.blobSize,
                bandDepth: Constants.borderBandDepth, edgeIndex: $0, rngAlong: 0.5, rngDepth: 0.5
            )
        }
        let edgeIndex = farthestIndex(anchor: Point(x: 0, y: 0), candidates: candidates, rngValue: 0.3)
        let expected = pickBorderPoint(
            screen: home, margin: Constants.roamMargin, blobSize: Self.blobSize,
            bandDepth: Constants.borderBandDepth, edgeIndex: edgeIndex, rngAlong: 0.6, rngDepth: 0.8
        )
        #expect(state.body.target == expected)
    }

    // MARK: - updateMovement: arrival snaps fully inside the target's screen

    @Test func updateMovement_arrivalOnSecondScreen_snapsFullyInsideItsRect() {
        let sm = StateMachine(rng: SeededRandom(seed: 3), clock: ManualClock(start: 5000))
        var state = TestFixtures.makeState(
            mode: .wander, position: Point(x: 1979, y: 660), screens: Self.screens
        )
        // Target hugs the secondary's bottom-right corner past full confinement.
        state.body.target = Point(x: 1980, y: 660)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 0.016, now: 5000)
        #expect(state.body.moving == false)
        #expect(state.body.position == Point(x: 1922, y: 638)) // 1200+800-78, 100+600-62
    }

    @Test func updateMovement_midGlide_doesNotClampThroughTheDeadZone() {
        // Gliding from primary toward the secondary: after one step the position sits in
        // the dead zone between the two frames — it must NOT be yanked into either screen.
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            mode: .wander, position: Point(x: 990, y: 400), screens: Self.screens
        )
        state.body.target = Point(x: 1500, y: 400)
        state.body.moving = true
        sm.updateMovement(state: &state, dt: 1.0, now: 0) // step = 80px -> x = 1070, in the dead zone
        #expect(state.body.position.x > 1000)
        #expect(state.body.position.x < 1200)
        #expect(state.body.moving == true)
    }

    // MARK: - reconcilePosition (top of tick, skipped while dragging)

    @Test func reconcilePosition_movingThroughDeadZone_leavesPositionAndValidTargetAlone() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            mode: .wander, position: Point(x: 1050, y: 400), moving: true, screens: Self.screens
        )
        state.body.target = Point(x: 1500, y: 400)
        sm.reconcilePosition(state: &state)
        #expect(state.body.position == Point(x: 1050, y: 400))
        #expect(state.body.target == Point(x: 1500, y: 400))
    }

    @Test func reconcilePosition_moving_reclampsTargetOntoASurvivingScreen() {
        // The secondary display was unplugged mid-glide: the target it pointed at must
        // re-clamp into the nearest surviving screen; the in-flight position is left alone.
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            mode: .wander, position: Point(x: 900, y: 400), moving: true,
            screens: [TestFixtures.screen]
        )
        state.body.target = Point(x: 1500, y: 400) // was on the now-gone secondary
        sm.reconcilePosition(state: &state)
        #expect(state.body.target == Point(x: 922, y: 400)) // 1000 - 78
        #expect(state.body.position == Point(x: 900, y: 400))
    }

    @Test func reconcilePosition_notMoving_clampsAStrandedPositionIntoTheNearestScreen() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            position: Point(x: 1500, y: 400), moving: false, screens: [TestFixtures.screen]
        )
        sm.reconcilePosition(state: &state)
        #expect(state.body.position == Point(x: 922, y: 400))
    }

    @Test func reconcilePosition_notMoving_alreadyFullyInside_isUntouched() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            position: Point(x: 1500, y: 400), moving: false, screens: Self.screens
        )
        sm.reconcilePosition(state: &state)
        #expect(state.body.position == Point(x: 1500, y: 400))
    }

    @Test func tick_notMoving_belowEdgePosition_isReconciledFullyInside() {
        // The below-the-edge regression, end to end: a resting avatar whose position has
        // ended up past the bottom edge is pulled fully back inside on the next tick.
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(position: Point(x: 500, y: 790))
        state.memory.modeEndsAt = 999_999 // keep maybeAdvanceMode from firing mid-test
        sm.tick(state: &state, dt: 0.016)
        #expect(state.body.position == Point(x: 500, y: 738)) // 800 - 62
    }

    @Test func tick_whileDragging_skipsReconcile() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 1000))
        var state = TestFixtures.makeState(position: Point(x: 500, y: 790), dragging: true)
        sm.tick(state: &state, dt: 0.016)
        #expect(state.body.position == Point(x: 500, y: 790))
    }

    // MARK: - updateDrag: confined to the cursor's screen

    @Test func updateDrag_cursorOnSecondScreen_clampsIntoThatScreensRect() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            position: Point(x: 1900, y: 600), cursor: Point(x: 1980, y: 690), screens: Self.screens
        )
        state.body.dragging = true
        state.body.dragOffset = Vector(dx: 0, dy: 0)
        sm.updateDrag(state: &state)
        #expect(state.body.position == Point(x: 1922, y: 638))
    }

    @Test func updateDrag_cursorInDeadZone_clampsIntoTheNearestScreen() {
        // x=1150 is 50px from the secondary's left edge vs 150px from the primary's
        // right edge — the secondary is the cursor's nearest screen.
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        var state = TestFixtures.makeState(
            position: Point(x: 1000, y: 400), cursor: Point(x: 1150, y: 400), screens: Self.screens
        )
        state.body.dragging = true
        state.body.dragOffset = Vector(dx: 0, dy: 0)
        sm.updateDrag(state: &state)
        #expect(state.body.position == Point(x: 1200, y: 400))
    }
}
