import Foundation
import Testing
@testable import AgentCore

// The gaze + attention spine (design doc "Gaze: how attention gets allocated"): a
// salience contest over candidates (cursor, onset, user proxy, scroll motion, own
// locomotion target, neutral rest), committed through a switch margin + minimum dwell so
// attention never strobes, then rendered as a fast saccade followed by attention-scaled
// smooth pursuit. A reflex snap bypasses all hysteresis. Habituation lives in the
// mind-wide shared store the Brain owns; each test creates one and lends it to `update`.
// Time convention matches the rest of the core: `now` in ms, `dt` in seconds.
struct GazeSystemTests {

    private let bodyCenter = Point(x: 500, y: 400)

    private func neutralDrives(arousal: Double = 0.5, sociability: Double = 0.5) -> Drives {
        Drives(energy: 0.7, curiosity: 0.5, sociability: sociability,
               comfort: 0.6, arousal: arousal, boredom: 0.3)
    }

    private func makeWorld(
        cursor: Point = Point(x: 0, y: 0),
        cursorVelocity: Vector = Vector(dx: 0, dy: 0),
        frontmostApp: AppInfo? = nil,
        frontmostWindow: WindowInfo? = nil,
        typing: Bool = false,
        typingLocation: Rect? = nil,
        scrolling: Bool = false
    ) -> AgentWorld {
        AgentWorld(
            screens: TestFixtures.screens, cursor: cursor, cursorVelocity: cursorVelocity,
            frontmostApp: frontmostApp, frontmostWindow: frontmostWindow,
            typing: typing, typingLocation: typingLocation, scrolling: scrolling
        )
    }

    private func makeContext(
        world: AgentWorld,
        locomotionTarget: Point? = nil,
        drives: Drives? = nil,
        temperament: Temperament = .calm
    ) -> GazeContext {
        GazeContext(
            world: world, bodyCenter: bodyCenter, locomotionTarget: locomotionTarget,
            drives: drives ?? neutralDrives(), temperament: temperament
        )
    }

    /// Runs `update` at 60 fps for `seconds`, starting at `from` ms, returning end time.
    @discardableResult
    private func simulate(
        _ gaze: inout GazeSystem, _ habituation: inout Habituation,
        context: GazeContext, from: Double, seconds: Double
    ) -> Double {
        let dt = 1.0 / 60.0
        var now = from
        for _ in 0..<Int(seconds * 60) {
            now += dt * 1000
            gaze.update(context: context, habituation: &habituation, now: now, dt: dt)
        }
        return now
    }

    // MARK: Resting state

    @Test func init_startsOnNeutralGaze() {
        let gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        #expect(gaze.targetKind == .neutral)
    }

    @Test func update_quietWorld_staysNeutral() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        simulate(&gaze, &habituation, context: makeContext(world: makeWorld()), from: 0, seconds: 2)
        #expect(gaze.targetKind == .neutral)
    }

    // MARK: Candidate capture

    @Test func update_fastNearbyCursor_capturesGaze() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(world: makeWorld(
            cursor: Point(x: 600, y: 400), cursorVelocity: Vector(dx: 1200, dy: 0)
        ))
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .cursor)
    }

    @Test func update_stillDistantCursor_staysNeutral() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(world: makeWorld(cursor: Point(x: 50, y: 50)))
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .neutral)
    }

    @Test func update_windowOnset_capturesGaze() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let windowA = WindowInfo(
            ownerName: "Editor", title: "notes",
            frame: Rect(origin: Point(x: 100, y: 100), size: Size(width: 400, height: 300))
        )
        let windowB = WindowInfo(
            ownerName: "Browser", title: "docs",
            frame: Rect(origin: Point(x: 300, y: 200), size: Size(width: 500, height: 400))
        )
        let now = simulate(
            &gaze, &habituation, context: makeContext(world: makeWorld(frontmostWindow: windowA)),
            from: 0, seconds: 1
        )
        simulate(
            &gaze, &habituation, context: makeContext(world: makeWorld(frontmostWindow: windowB)),
            from: now, seconds: 0.5
        )
        #expect(gaze.targetKind == .onset)
    }

    // "Eyes that ... drift to a window that just opened, then settle back on the user."
    // The stale onset must not hold the eyes; with a focused window still present, the
    // user proxy is what they settle back on.
    @Test func update_onsetAttendedLong_releasesToTheUser() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let windowA = WindowInfo(
            ownerName: "Editor", title: "notes",
            frame: Rect(origin: Point(x: 100, y: 100), size: Size(width: 400, height: 300))
        )
        let windowB = WindowInfo(
            ownerName: "Browser", title: "docs",
            frame: Rect(origin: Point(x: 300, y: 200), size: Size(width: 500, height: 400))
        )
        var now = simulate(
            &gaze, &habituation, context: makeContext(world: makeWorld(frontmostWindow: windowA)),
            from: 0, seconds: 1
        )
        let contextB = makeContext(world: makeWorld(frontmostWindow: windowB))
        now = simulate(&gaze, &habituation, context: contextB, from: now, seconds: 0.5)
        #expect(gaze.targetKind == .onset)
        simulate(&gaze, &habituation, context: contextB, from: now, seconds: 30)
        #expect(gaze.targetKind == .user)
    }

    @Test func update_ownLocomotionTarget_leadsTheBody() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(world: makeWorld(), locomotionTarget: Point(x: 800, y: 200))
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .locomotion)
    }

    @Test func update_scrolling_looksAtTheActiveWindow() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let window = WindowInfo(
            ownerName: "Browser", title: "feed",
            frame: Rect(origin: Point(x: 200, y: 100), size: Size(width: 600, height: 500))
        )
        // Window present from the very first update, so it registers as the baseline
        // (no onset) and scrolling is the only pull.
        let context = makeContext(world: makeWorld(frontmostWindow: window, scrolling: true))
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .motion)
    }

    // MARK: Drive and temperament modulation

    @Test func update_typingUser_needyPetLooksAtThem() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let caret = Rect(origin: Point(x: 300, y: 200), size: Size(width: 4, height: 18))
        let context = makeContext(
            world: makeWorld(typing: true, typingLocation: caret),
            drives: neutralDrives(sociability: Temperament.needyPet.baselines.sociability),
            temperament: .needyPet
        )
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .user)
    }

    @Test func update_typingUser_aloofCatStaysNeutral() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let caret = Rect(origin: Point(x: 300, y: 200), size: Size(width: 4, height: 18))
        let context = makeContext(
            world: makeWorld(typing: true, typingLocation: caret),
            drives: neutralDrives(sociability: Temperament.aloofCat.baselines.sociability),
            temperament: .aloofCat
        )
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .neutral)
    }

    @Test func update_nearZeroArousal_flattensEverything_staysNeutral() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(
            world: makeWorld(cursor: Point(x: 600, y: 400), cursorVelocity: Vector(dx: 1200, dy: 0)),
            drives: neutralDrives(arousal: 0.02)
        )
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        #expect(gaze.targetKind == .neutral)
    }

    // MARK: Commit hysteresis (margin + dwell)

    @Test func shouldSwitch_challengerBelowMargin_holdsCurrentTarget() {
        let allowed = GazeSystem.shouldSwitch(
            challengerSalience: 0.30, incumbentSalience: 0.25,
            lastSwitchAt: 0, now: 10_000
        )
        #expect(!allowed)
    }

    @Test func shouldSwitch_withinMinimumDwell_holdsCurrentTarget() {
        let allowed = GazeSystem.shouldSwitch(
            challengerSalience: 0.9, incumbentSalience: 0.2,
            lastSwitchAt: 10_000, now: 10_000 + MindConstants.gazeMinDwellMs / 2
        )
        #expect(!allowed)
    }

    @Test func shouldSwitch_clearMarginAfterDwell_allowsSwitch() {
        let allowed = GazeSystem.shouldSwitch(
            challengerSalience: 0.9, incumbentSalience: 0.2,
            lastSwitchAt: 10_000, now: 10_000 + MindConstants.gazeMinDwellMs * 2
        )
        #expect(allowed)
    }

    // MARK: Reflex snap (interrupt contract)

    @Test func snap_bypassesMarginAndDwell_immediately() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        gaze.update(context: makeContext(world: makeWorld()), habituation: &habituation,
                    now: 16, dt: 1.0 / 60.0)
        let source = Point(x: 900, y: 100)
        gaze.snap(to: source, now: 20)
        #expect(gaze.gazePoint == source)
        #expect(gaze.attention == 1.0)
    }

    // MARK: Saccade then pursuit

    @Test func update_justAfterSwitch_saccadeClosesMostOfTheGapFast() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(world: makeWorld(
            cursor: Point(x: 650, y: 400), cursorVelocity: Vector(dx: 1200, dy: 0)
        ))
        // Let the switch commit, note the gap, then give it 0.15s of saccade.
        var now = simulate(&gaze, &habituation, context: context, from: 0, seconds: 0.4)
        #expect(gaze.targetKind == .cursor)
        let initialGap = distance(gaze.gazePoint, Point(x: 650, y: 400))
        now = simulate(&gaze, &habituation, context: context, from: now, seconds: 0.15)
        let remainingGap = distance(gaze.gazePoint, Point(x: 650, y: 400))
        #expect(remainingGap < initialGap * 0.2 + 1.0)
    }

    @Test func update_pursuit_staysLockedOnMovingCursor() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        var cursor = Point(x: 600, y: 400)
        let velocity = Vector(dx: 60, dy: 0)
        var now: Double = 0
        let dt = 1.0 / 60.0
        for _ in 0..<180 {
            cursor.x += velocity.dx * dt
            now += dt * 1000
            let context = makeContext(world: makeWorld(cursor: cursor, cursorVelocity: velocity))
            gaze.update(context: context, habituation: &habituation, now: now, dt: dt)
        }
        #expect(gaze.targetKind == .cursor)
        #expect(distance(gaze.gazePoint, cursor) < 40)
    }

    @Test func update_higherAttention_tracksTighterThanLower() {
        let context = makeContext(world: makeWorld(
            cursor: Point(x: 700, y: 400), cursorVelocity: Vector(dx: 1200, dy: 0)
        ))
        var locked = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var drowsy = locked
        var lockedHabituation = Habituation()
        var drowsyHabituation = Habituation()
        simulate(&locked, &lockedHabituation, context: context, from: 0, seconds: 1)
        simulate(&drowsy, &drowsyHabituation, context: context, from: 0, seconds: 1)
        locked.attention = 1.0
        drowsy.attention = 0.1
        // Jump the target and give both one identical pursuit second (past the saccade
        // window so the attention-scaled tau is what's being measured).
        let moved = makeContext(world: makeWorld(
            cursor: Point(x: 200, y: 700), cursorVelocity: Vector(dx: 0, dy: 0)
        ))
        var nowA = 1000.0
        var nowB = 1000.0
        let dt = 1.0 / 60.0
        for _ in 0..<60 {
            nowA += dt * 1000
            nowB += dt * 1000
            locked.update(context: moved, habituation: &lockedHabituation, now: nowA, dt: dt)
            drowsy.update(context: moved, habituation: &drowsyHabituation, now: nowB, dt: dt)
            locked.attention = 1.0
            drowsy.attention = 0.1
        }
        let target = Point(x: 200, y: 700)
        #expect(distance(locked.gazePoint, target) < distance(drowsy.gazePoint, target))
    }

    // MARK: Render seam

    @Test func direction_pointsTowardGazeAndIsClamped() {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        gaze.snap(to: Point(x: 900, y: 400), now: 0)
        let direction = gaze.direction(from: bodyCenter)
        #expect(direction.dx > 0.5)
        #expect(abs(direction.dy) < 0.05)
        #expect(direction.magnitude <= 1.000001)
    }

    @Test func codable_roundTripsExactly() throws {
        var gaze = GazeSystem(bodyCenter: bodyCenter, now: 0)
        var habituation = Habituation()
        let context = makeContext(world: makeWorld(
            cursor: Point(x: 600, y: 400), cursorVelocity: Vector(dx: 800, dy: 0)
        ))
        simulate(&gaze, &habituation, context: context, from: 0, seconds: 1)
        let data = try JSONEncoder().encode(gaze)
        let decoded = try JSONDecoder().decode(GazeSystem.self, from: data)
        #expect(decoded == gaze)
    }
}
