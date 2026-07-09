import Testing
@testable import AgentCore

// Mechanical port of blob.js's initial `state`/`cursor` object literals (lines 147-167) —
// the one-time boot state, before any tick runs. Deliberately distinct file from
// StateMachineTransitionTests: these are boot-time seed values, not steady-state
// reschedule logic, and the JS source uses DIFFERENT random ranges for several of them
// than the ongoing update functions do — see Constants' initial* doc comments.
struct InitialStateTests {

    static let screens = TestFixtures.screens
    static let blobSize = TestFixtures.blobSize

    @Test func makeInitialState_positionsAvatarTargetAndCursor_atPrimaryScreenCenter() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 0)
        let center = Point(x: 500, y: 400)
        #expect(state.body.position == center)
        #expect(state.body.target == center)
        #expect(state.world.cursor == center)
    }

    @Test func makeInitialState_nonZeroOriginPrimary_centersOnItsFrame_notTheWebOrigin() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        let state = sm.makeInitialState(
            screens: [TestFixtures.secondScreen], avatarSize: Self.blobSize, now: 0
        )
        // secondScreen frame = origin (1200, 100), 800x600 -> center (1600, 400)
        #expect(state.body.position == Point(x: 1600, y: 400))
        #expect(state.body.target == Point(x: 1600, y: 400))
    }

    @Test func makeInitialState_startsIdleAndNotMoving() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 0)
        #expect(state.body.mode == .idle)
        #expect(state.body.moving == false)
        #expect(state.body.dragging == false)
    }

    @Test func makeInitialState_usesProvidedScreensAndAvatarSize() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        let state = sm.makeInitialState(screens: TestFixtures.twoScreens, avatarSize: Self.blobSize, now: 0)
        #expect(state.world.screens == TestFixtures.twoScreens)
        #expect(state.body.size == Self.blobSize)
    }

    // JS: `modeEndsAt: performance.now() + 1500` — a flat literal, NOT
    // `randomRange(...MODE_DWELL_MS.idle)` (3000-6000) as startMode(.idle) would use.
    @Test func makeInitialState_modeEndsAt_isFixed1500msFromBoot_notIdlesDwellRange() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 2000))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 2000)
        #expect(state.memory.modeEndsAt == 2000 + 1500)
    }

    // JS: `nextBlinkAt: performance.now() + randomRange(2000, 5000)` — distinct from
    // updateBlink's steady-state reschedule range (2500-6000). The two ranges overlap,
    // so a range-bound assertion could pass even if the wrong constant were used
    // (depending on seed) — pin the exact value via an independent same-seed RNG instead.
    @Test func makeInitialState_nextBlinkAt_usesInitialDelayRange_distinctFromSteadyStateRange() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 1000))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 1000)

        let reference = SeededRandom(seed: 1)
        let blinkFraction = reference.nextUnit() // makeInitialState's first randomRange call
        let expected = 1000 + (2000 + blinkFraction * (5000 - 2000))
        #expect(state.memory.nextBlinkAt == expected)
    }

    // JS: `nextQuirkAt: performance.now() + randomRange(4000, 9000)` — distinct from
    // updateEmotionTriggers's steady-state cooldown gap (6000-12000, on top of duration).
    // Same overlap concern as the blink test above — pin the exact value.
    @Test func makeInitialState_nextQuirkAt_usesInitialDelayRange_distinctFromSteadyStateRange() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 1000))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 1000)

        let reference = SeededRandom(seed: 1)
        _ = reference.nextUnit() // makeInitialState's first randomRange call (blink) — consume and discard
        let quirkFraction = reference.nextUnit() // its second randomRange call (quirk)
        let expected = 1000 + (4000 + quirkFraction * (9000 - 4000))
        #expect(state.memory.nextQuirkAt == expected)
    }

    @Test func makeInitialState_happyAndBlinkAndQuirkFields_startAtRestingDefaults() {
        let sm = StateMachine(rng: SeededRandom(seed: 1), clock: ManualClock(start: 0))
        let state = sm.makeInitialState(screens: Self.screens, avatarSize: Self.blobSize, now: 0)
        #expect(state.memory.happyUntil == 0)
        #expect(state.memory.happyResumeMode == .idle)
        #expect(state.memory.blinking == false)
        #expect(state.memory.blinkEndsAt == 0)
        #expect(state.memory.quirkEmotion == nil)
        #expect(state.memory.quirkUntil == 0)
        #expect(state.memory.proximityUntil == 0)
        #expect(state.memory.proximityCooldownUntil == 0)
    }
}
