import Foundation
import Testing
@testable import AgentCore

// The emergent brain's composition root: reflexes on the fast tick (preemptive, never
// gated by arbiter hysteresis), cognition (situation → drives → arbitration) at 8 Hz,
// steering forces into the fixed-step physics body every frame, gaze + shared-store
// habituation recovery every frame, and the classic drag seam. The Brain is the sole
// writer of `state.mind` and (while it drives) of `state.body`/`state.memory` — same
// single-writer discipline as the classic StateMachine.
struct EmergentBrainTests {

    private let avatarSize = TestFixtures.blobSize

    private func makeBrain(
        rng: RandomProvider = ScriptedRandom([]), clock: ManualClock
    ) -> EmergentBrain {
        EmergentBrain(rng: rng, clock: clock, hourOfDay: { 15 })
    }

    private func makeBooted(clock: ManualClock, rng: RandomProvider = ScriptedRandom([])) -> (EmergentBrain, AgentState) {
        let brain = makeBrain(rng: rng, clock: clock)
        let state = brain.makeInitialState(
            screens: TestFixtures.screens, avatarSize: avatarSize,
            temperament: .calm, now: clock.now()
        )
        return (brain, state)
    }

    /// Steps `frames` display frames at 60 fps, advancing the clock in lockstep.
    private func step(
        _ brain: EmergentBrain, _ state: inout AgentState, clock: ManualClock, frames: Int
    ) {
        let dtMs = 1000.0 / 60.0
        for _ in 0..<frames {
            clock.advance(by: dtMs)
            brain.tick(state: &state, dt: dtMs / 1000)
        }
    }

    // MARK: Boot

    @Test func makeInitialState_bootsMindAwakeAndIdleAtPrimaryCenter() {
        let clock = ManualClock()
        let (_, state) = makeBooted(clock: clock)
        #expect(state.mind != nil)
        #expect(state.mind?.power == .awake)
        #expect(state.mind?.behavior == .idle)
        #expect(state.body.position == Point(x: 500, y: 400))
    }

    // MARK: Quiet baseline

    @Test func tick_quietWorld_staysPutAndUnhurried() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        let start = state.body.position
        step(brain, &state, clock: clock, frames: 240)
        #expect(!state.body.moving)
        #expect(distance(state.body.position, start) < 5)
    }

    // MARK: Cognition cadence

    @Test func tick_cognition_isThrottledToTheCognitionInterval() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        step(brain, &state, clock: clock, frames: 7) // ~117ms — under the 125ms slice
        #expect(state.mind?.lastCognitionAt == 0)
        step(brain, &state, clock: clock, frames: 1) // ~133ms — slice due
        #expect(state.mind!.lastCognitionAt > 0)
    }

    // MARK: Drive-led arbitration

    @Test func tick_lowEnergy_commitsRestAndLooksSleepyOnceSettled() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.mind!.drives.energy = 0.05
        step(brain, &state, clock: clock, frames: 170) // past the 2500ms commitment
        #expect(state.mind?.behavior == .rest)
        #expect(state.body.emotion == .sleepy)
    }

    @Test func tick_highBoredom_wandersAndActuallyMoves() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.mind!.drives.boredom = 0.95
        state.mind!.drives.arousal = 0.7
        state.mind!.drives.energy = 0.9
        let start = state.body.position
        step(brain, &state, clock: clock, frames: 300) // 5s: commit at ~2.6s, then amble
        #expect(state.mind?.behavior == .wander)
        #expect(distance(state.body.position, start) > 15)
    }

    @Test func tick_wanderNeverLeavesTheScreen() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.mind!.drives.boredom = 0.95
        state.mind!.drives.arousal = 0.7
        state.mind!.drives.energy = 0.9
        // Start hard against the right edge so the ambling has an edge to fight.
        state.mind!.physics.position = Point(x: 920, y: 400)
        state.body.position = Point(x: 920, y: 400)
        step(brain, &state, clock: clock, frames: 600)
        let screen = TestFixtures.screen.frame
        #expect(state.body.position.x >= screen.origin.x)
        #expect(state.body.position.x + avatarSize.width <= screen.origin.x + screen.size.width)
        #expect(state.body.position.y >= screen.origin.y)
        #expect(state.body.position.y + avatarSize.height <= screen.origin.y + screen.size.height)
    }

    @Test func tick_engagedGazeAndCuriosity_commitsInspectWithATarget() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        // Idle out the boot commitment first, then present a fresh onset: a stimulus
        // that's already 2.5s stale by the first arbitration would rightly lose to
        // idle (onset pull decays and habituates — that's the design working).
        step(brain, &state, clock: clock, frames: 150)
        state.mind!.drives.curiosity = 0.9
        state.mind!.drives.arousal = 0.7
        state.mind!.drives.energy = 0.9
        state.mind!.gaze.snap(to: Point(x: 850, y: 150), now: clock.now())
        step(brain, &state, clock: clock, frames: 30) // a couple of cognition slices
        #expect(state.mind?.behavior == .inspect)
        #expect(state.mind?.behaviorTarget != nil)
        #expect(state.body.emotion == .curious)
    }

    // MARK: Reflex arc integration (preemption + consequences + re-arbitration)

    private func dartingWorld(bodyCenter: Point) -> AgentWorld {
        AgentWorld(
            screens: TestFixtures.screens,
            cursor: Point(x: bodyCenter.x - 100, y: bodyCenter.y),
            cursorVelocity: Vector(dx: 2200, dy: 0)
        )
    }

    @Test func tick_cursorDart_firesReflexSnapsGazeAndSpikesArousal() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        let arousalBefore = state.mind!.drives.arousal
        let center = Point(
            x: state.body.position.x + avatarSize.width / 2,
            y: state.body.position.y + avatarSize.height / 2
        )
        state.world = dartingWorld(bodyCenter: center)
        step(brain, &state, clock: clock, frames: 1)
        #expect(state.mind?.reflex.active?.kind == .startle)
        #expect(state.mind!.gaze.gazePoint == state.world.cursor)
        #expect(state.mind!.drives.arousal > arousalBefore)
        #expect(state.body.emotion == .surprised)
        #expect(state.mind?.rearbitrateAt != nil)
    }

    @Test func tick_duringStartle_bodyFleesTheSource() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        let center = Point(
            x: state.body.position.x + avatarSize.width / 2,
            y: state.body.position.y + avatarSize.height / 2
        )
        state.world = dartingWorld(bodyCenter: center)
        step(brain, &state, clock: clock, frames: 1)
        state.world.cursorVelocity = Vector(dx: 0, dy: 0)
        step(brain, &state, clock: clock, frames: 20)
        // Source was left of the body: the escape is rightward.
        #expect(state.mind!.physics.velocity.dx > 0)
        #expect(state.body.moving)
    }

    @Test func tick_afterReflexEnds_reArbitrationClearsTheFlag() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        let center = Point(
            x: state.body.position.x + avatarSize.width / 2,
            y: state.body.position.y + avatarSize.height / 2
        )
        state.world = dartingWorld(bodyCenter: center)
        step(brain, &state, clock: clock, frames: 1)
        state.world.cursorVelocity = Vector(dx: 0, dy: 0)
        step(brain, &state, clock: clock, frames: 90) // 1.5s — past the 700ms startle
        #expect(state.mind?.rearbitrateAt == nil)
        #expect(state.body.emotion != .surprised)
    }

    // MARK: Yield (deference's hard override, forced re-arbitration)

    @Test func tick_typingCaretUnderBody_yieldsQuicklyAndMovesAway() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.world.typing = true
        state.world.typingLocation = Rect(
            origin: Point(x: 530, y: 425), size: Size(width: 4, height: 18)
        )
        step(brain, &state, clock: clock, frames: 10) // yield forces past commitment
        #expect(state.mind?.behavior == .yield)
        #expect(state.body.emotion == .annoyed)
        let zone = attentionZone(from: state.world)!
        step(brain, &state, clock: clock, frames: 240) // 4s to escape
        let bodyRect = Rect(origin: state.body.position, size: avatarSize)
        #expect(!rectsOverlap(bodyRect, zone))
    }

    // MARK: Drag seam

    @Test func drag_bodyFollowsCursorAndBlushes_dropLandsGently() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.world.cursor = Point(x: 520, y: 420) // on the body
        brain.beginDrag(state: &state)
        #expect(state.body.dragging)

        state.world.cursor = Point(x: 620, y: 470)
        brain.updateDrag(state: &state)
        step(brain, &state, clock: clock, frames: 1)
        #expect(state.body.position == Point(x: 600, y: 450))
        #expect(state.body.emotion == .blush)

        let comfortBefore = state.mind!.drives.comfort
        brain.endDrag(state: &state, now: clock.now())
        #expect(!state.body.dragging)
        #expect(state.mind!.drives.comfort > comfortBefore)
    }

    // MARK: Shared habituation store (Brain-owned recovery)

    @Test func tick_unattendedHabituation_recoversOverTime() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        state.mind!.habituation.expose("cursorDart", dt: 30, rate: 1)
        let before = state.mind!.habituation.level(for: "cursorDart")
        step(brain, &state, clock: clock, frames: 300) // 5s of quiet
        #expect(state.mind!.habituation.level(for: "cursorDart") < before)
    }

    // MARK: Temperament switching (decision log D10: swap the vector, drives ease over)

    @Test func adoptTemperament_swapsTheVectorWithoutTouchingTheDrives() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        step(brain, &state, clock: clock, frames: 60)
        let before = state.mind!.drives
        brain.adoptTemperament(.gremlin, state: &state)
        #expect(state.mind?.temperament == .gremlin)
        #expect(state.mind?.drives == before)
    }

    @Test func adoptTemperament_drivesEaseTowardTheNewBaselinesOverSeconds() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        brain.adoptTemperament(.gremlin, state: &state)
        step(brain, &state, clock: clock, frames: 80 * 60) // 80s — four arousal taus
        let target = DriveDynamics.effectiveBaselines(temperament: .gremlin, hourOfDay: 15).arousal
        #expect(abs(state.mind!.drives.arousal - target) < 0.05)
    }

    // MARK: Power ladder (decision log D11: doze throttles, sleep hands off to the shell)

    @Test func tick_quietFor90Seconds_dozesAndThrottlesCognition() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        step(brain, &state, clock: clock, frames: 5460) // 91s of no input
        #expect(state.mind?.power == .dozing)
        let lastCognitionAt = state.mind!.lastCognitionAt
        step(brain, &state, clock: clock, frames: 20) // ~333ms — under the doze slice
        #expect(state.mind!.lastCognitionAt == lastCognitionAt)
        step(brain, &state, clock: clock, frames: 15) // ~583ms — doze slice due
        #expect(state.mind!.lastCognitionAt > lastCognitionAt)
    }

    @Test func tick_activityWhileDozing_wakesOnTheNextCognitionSlice() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        step(brain, &state, clock: clock, frames: 5460)
        #expect(state.mind?.power == .dozing)
        state.world.cursor = Point(x: 300, y: 300)
        state.world.cursorVelocity = Vector(dx: 50, dy: 0) // gentle move, no reflex
        step(brain, &state, clock: clock, frames: 35) // one doze slice at most
        #expect(state.mind?.power == .awake)
    }

    @Test func tick_quietForFiveMinutes_fallsAsleepSettledIntoRest() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        step(brain, &state, clock: clock, frames: 18660) // 311s of no input
        #expect(state.mind?.power == .sleeping)
        #expect(state.mind?.behavior == .rest)
        // Doze's baseline bias has been dragging energy down since the 90s mark.
        #expect(state.mind!.drives.energy < 0.5)
    }

    // MARK: Blink keeps running on the emergent path

    @Test func tick_blinkFiresAndReschedules() {
        let clock = ManualClock()
        var (brain, state) = makeBooted(clock: clock)
        let firstBlinkAt = state.memory.nextBlinkAt
        var blinked = false
        for _ in 0..<600 { // 10s
            step(brain, &state, clock: clock, frames: 1)
            if state.memory.blinking { blinked = true }
        }
        #expect(blinked)
        #expect(state.memory.nextBlinkAt > firstBlinkAt)
    }
}
