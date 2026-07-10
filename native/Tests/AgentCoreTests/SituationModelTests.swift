import Testing
@testable import AgentCore

// The situation model (design doc layer 3): collapses cheap perception signals into one
// of the four frozen SituationMode labels, with its own hysteresis so the mode never
// flickers. Rule-based thresholds for v0; the labels are the stable contract, the
// detector is replaceable (decision log D6).
struct SituationModelTests {

    private let dwellMs = MindConstants.situationSwitchDwellMs

    private func typingWorld() -> AgentWorld {
        var world = TestFixtures.makeState(typing: true).world
        world.typing = true
        return world
    }

    private func quietWorld() -> AgentWorld {
        TestFixtures.makeState().world
    }

    /// A frontmost window covering (essentially) the whole primary screen.
    private func fullscreenWorld(typing: Bool = false) -> AgentWorld {
        var world = TestFixtures.makeState(typing: typing).world
        world.frontmostWindow = WindowInfo(
            ownerName: "TV", title: "Movie",
            frame: TestFixtures.screen.frame
        )
        return world
    }

    /// Drives `model` with `world` for `seconds`, stepping at the cognition rate.
    private func run(
        _ model: inout SituationModel, world: AgentWorld, from startMs: Double, seconds: Double
    ) -> Double {
        let stepMs = MindConstants.cognitionIntervalSeconds * 1000
        var now = startMs
        for _ in 0..<Int(seconds * 1000 / stepMs) {
            now += stepMs
            model.update(world: world, now: now)
        }
        return now
    }

    // MARK: Boot

    @Test func initialMode_isCasualBrowsing() {
        #expect(SituationModel(now: 0).mode == .casualBrowsing)
    }

    // MARK: focus/typing

    @Test func typing_switchesToFocusTyping_afterDwell() {
        var model = SituationModel(now: 0)
        _ = run(&model, world: typingWorld(), from: 0, seconds: dwellMs / 1000 + 1)
        #expect(model.mode == .focusTyping)
    }

    @Test func typing_doesNotSwitchBeforeDwell_hysteresis() {
        var model = SituationModel(now: 0)
        model.update(world: typingWorld(), now: 100)
        #expect(model.mode == .casualBrowsing)
    }

    @Test func flickeringCandidate_resetsDwell_modeHolds() {
        var model = SituationModel(now: 0)
        var now: Double = 0
        // Alternate typing/quiet every cognition tick — the candidate never survives a
        // full dwell window, so the committed mode never moves.
        for i in 0..<Int(dwellMs / 125 * 4) {
            now += 125
            model.update(world: i % 2 == 0 ? typingWorld() : quietWorld(), now: now)
        }
        #expect(model.mode == .casualBrowsing)
    }

    // MARK: media/watching

    @Test func fullscreenAndHandsOff_becomesMediaWatching() {
        var model = SituationModel(now: 0)
        _ = run(
            &model, world: fullscreenWorld(), from: 0,
            seconds: MindConstants.mediaStillnessSeconds + dwellMs / 1000 + 1
        )
        #expect(model.mode == .mediaWatching)
    }

    @Test func fullscreenWhileTyping_isFocusTyping_notMedia() {
        var model = SituationModel(now: 0)
        _ = run(&model, world: fullscreenWorld(typing: true), from: 0, seconds: dwellMs / 1000 + 1)
        #expect(model.mode == .focusTyping)
    }

    @Test func fullscreenHandsOffForHours_staysMediaWatching_neverIdleAway() {
        var model = SituationModel(now: 0)
        _ = run(&model, world: fullscreenWorld(), from: 0, seconds: 2 * 60 * 60)
        #expect(model.mode == .mediaWatching)
    }

    @Test func smallWindow_isNotMedia() {
        var model = SituationModel(now: 0)
        var world = quietWorld()
        world.frontmostWindow = WindowInfo(
            ownerName: "Notes", title: nil,
            frame: Rect(origin: Point(x: 100, y: 100), size: Size(width: 400, height: 300))
        )
        _ = run(&model, world: world, from: 0, seconds: 30)
        #expect(model.mode == .casualBrowsing)
    }

    // MARK: idle/away

    @Test func quietDesktop_becomesIdleAway_afterThreshold() {
        var model = SituationModel(now: 0)
        _ = run(
            &model, world: quietWorld(), from: 0,
            seconds: MindConstants.idleAwayAfterSeconds + dwellMs / 1000 + 1
        )
        #expect(model.mode == .idleAway)
    }

    @Test func quietDesktop_staysCasual_beforeIdleThreshold() {
        var model = SituationModel(now: 0)
        _ = run(&model, world: quietWorld(), from: 0, seconds: MindConstants.idleAwayAfterSeconds / 2)
        #expect(model.mode == .casualBrowsing)
    }

    @Test func cursorMotion_countsAsActivity_resetsIdle() {
        var model = SituationModel(now: 0)
        var now = run(
            &model, world: quietWorld(), from: 0, seconds: MindConstants.idleAwayAfterSeconds - 5
        )
        var moving = quietWorld()
        moving.cursorVelocity = Vector(dx: 300, dy: 0)
        now += 125
        model.update(world: moving, now: now)
        _ = run(&model, world: quietWorld(), from: now, seconds: MindConstants.idleAwayAfterSeconds - 5)
        #expect(model.mode == .casualBrowsing)
    }

    @Test func idleAway_recoversToCasual_onActivity() {
        var model = SituationModel(now: 0)
        var now = run(
            &model, world: quietWorld(), from: 0,
            seconds: MindConstants.idleAwayAfterSeconds + dwellMs / 1000 + 1
        )
        #expect(model.mode == .idleAway)
        now = run(&model, world: typingWorld(), from: now, seconds: dwellMs / 1000 + 1)
        #expect(model.mode == .focusTyping)
    }

    // MARK: secondsSinceActivity readout (consumed by the power policy later)

    @Test func secondsSinceActivity_growsWhileQuiet() {
        var model = SituationModel(now: 0)
        let now = run(&model, world: quietWorld(), from: 0, seconds: 10)
        #expect(model.secondsSinceActivity(now: now) > 9)
    }

    @Test func secondsSinceActivity_isNearZeroWhileTyping() {
        var model = SituationModel(now: 0)
        let now = run(&model, world: typingWorld(), from: 0, seconds: 10)
        #expect(model.secondsSinceActivity(now: now) < 1)
    }
}
