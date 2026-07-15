import Foundation

/// The emergent brain's composition root (design doc "The architecture", decision log
/// D3/D15): drives the whole stack once per display frame —
///
/// 1. reflex arc on the fast tick (preemptive; arbiter hysteresis never gates it),
/// 2. cognition (situation → drives → arbitration) at 8 Hz,
/// 3. steering forces into the fixed-step physics body,
/// 4. gaze contest + the once-per-tick habituation recovery on the shared store,
/// 5. blink, emotion ladder, and the `state.body` write-back the render seam reads.
///
/// Sole writer of `state.mind`, and — while it is the active driver — of `state.body`
/// and `state.memory`, mirroring the classic `StateMachine`'s single-writer contract.
/// RNG, clock, and wall-hour are injected (D8/D9) so every behavior is deterministic
/// under test. Time convention: `now` in ms, `dt` in seconds.
public final class EmergentBrain {
    private let rng: RandomProvider
    private let clock: Clock
    private let hourOfDay: () -> Double
    /// The temperament `makeInitialState` boots with — the shell passes the persisted
    /// preset here, since the protocol's `makeInitialState` has no temperament parameter.
    private let bootTemperament: Temperament

    public init(
        rng: RandomProvider, clock: Clock, hourOfDay: @escaping () -> Double,
        bootTemperament: Temperament = .calm
    ) {
        self.rng = rng
        self.clock = clock
        self.hourOfDay = hourOfDay
        self.bootTemperament = bootTemperament
    }

    // MARK: - Boot

    /// Boots at the primary display's center with the configured `bootTemperament`,
    /// drives exactly at that temperament's effective baselines (the doc's "waking up
    /// rested" persistence boundary). The classic memory timers are seeded too — blink
    /// keeps running on this path; quirks don't (drive-flavored idling replaces them),
    /// so their timers stay inert at 0.
    public func makeInitialState(
        screens: [ScreenInfo], avatarSize: Size, now: Double
    ) -> AgentState {
        let bootCenter = center(of: screens[0].frame)
        return AgentState(
            world: AgentWorld(screens: screens, cursor: bootCenter),
            body: AgentBody(
                position: bootCenter, mode: .idle, target: bootCenter, moving: false,
                emotion: .neutral, dragging: false, dragOffset: Vector(dx: 0, dy: 0),
                size: avatarSize
            ),
            memory: AgentMemory(
                modeEndsAt: 0, happyUntil: 0, happyResumeMode: .idle,
                nextBlinkAt: now + randomRange(Constants.initialBlinkDelayMsRange),
                blinking: false, blinkEndsAt: 0,
                quirkEmotion: nil, quirkUntil: 0, nextQuirkAt: 0,
                proximityUntil: 0, proximityCooldownUntil: 0, yieldCooldownUntil: 0
            ),
            mind: MindState(
                temperament: bootTemperament, position: bootCenter,
                hourOfDay: hourOfDay(), now: now
            )
        )
    }

    // MARK: - Frame tick

    public func tick(state: inout AgentState, dt: Double) {
        guard var mind = state.mind else { return }
        // Take, don't copy: with `state.mind` still holding the original, `mind`'s
        // copy-on-write internals (the habituation dictionary) would clone on every
        // frame's first mutation. The defer write-back restores it on every path out.
        state.mind = nil
        defer { state.mind = mind }
        let now = clock.now()

        // Derived belief the menus surface regardless of what the body is doing.
        state.body.attentionZone = attentionZone(from: state.world)

        if state.body.dragging || state.timer?.active == true {
            // Something outside the brain owns position — the user's hand (see
            // updateDrag), or the shell's timer pin (start's top-right corner, or
            // wherever the user last dragged it while timing). Either way it must stay
            // put — no steering, no locomotion — while perception-side systems keep
            // running so the eyes and face stay alive.
            mind.physics.position = state.body.position
            mind.physics.velocity = Vector(dx: 0, dy: 0)
            updateGaze(state: state, mind: &mind, now: now, dt: dt)
            updateBlink(state: &state, now: now)
            writeBack(state: &state, mind: mind, now: now)
            return
        }

        // 1. Reflex arc — fast tick, straight from perception, preempts everything.
        if let event = mind.reflex.tick(
            world: state.world, bodyCenter: bodyCenter(of: mind, size: state.body.size),
            habituation: &mind.habituation, temperament: mind.temperament, now: now
        ) {
            mind.gaze.snap(to: event.source, now: now)
            DriveDynamics.apply(
                .startle(intensity: event.intensity), to: &mind.drives,
                temperament: mind.temperament
            )
            // "Resume or re-arbitrate" (default re-arbitrate): when the event releases
            // the body, the next cognition slice re-scores instead of blindly resuming.
            mind.rearbitrateAt = event.endsAt
        }

        // 2. Cognition at 8 Hz awake, throttled to the doze slice below the awake tier
        // (D11) — the reflex arc above and the motor/gaze systems below stay per-frame.
        let cognitionInterval = mind.power == .awake
            ? MindConstants.cognitionIntervalSeconds
            : MindConstants.dozeCognitionIntervalSeconds
        if now - mind.lastCognitionAt >= cognitionInterval * 1000 {
            runCognition(state: state, mind: &mind, now: now)
        }

        // 3. Steering → fixed-step physics → hard confinement.
        advanceBody(state: state, mind: &mind, now: now, dt: dt)

        // 4. Gaze + the Brain's once-per-tick recovery pass on the shared store.
        updateGaze(state: state, mind: &mind, now: now, dt: dt)

        // 5. Blink and the body/emotion write-back.
        updateBlink(state: &state, now: now)
        writeBack(state: &state, mind: mind, now: now)
    }

    // MARK: - Cognition (situation → drives → arbitration)

    private func runCognition(state: AgentState, mind: inout MindState, now: Double) {
        let cognitionDt = (now - mind.lastCognitionAt) / 1000
        mind.lastCognitionAt = now

        let previousSituation = mind.situation.mode
        mind.situation.update(world: state.world, now: now)
        if mind.situation.mode != previousSituation {
            if mind.situation.mode == .idleAway {
                DriveDynamics.apply(.userLeft, to: &mind.drives, temperament: mind.temperament)
            } else if previousSituation == .idleAway {
                DriveDynamics.apply(.userReturned, to: &mind.drives, temperament: mind.temperament)
            }
        }
        // The power tier follows the same activity clock the situation model keeps —
        // recomputed every slice, so fresh input reads as awake within one slice with
        // no event plumbing.
        mind.power = PowerPolicy.tier(
            secondsSinceActivity: mind.situation.secondsSinceActivity(now: now)
        )
        DriveDynamics.tick(
            &mind.drives, temperament: mind.temperament, hourOfDay: hourOfDay(),
            dt: cognitionDt,
            baselineScale: mind.power == .awake ? 1 : MindConstants.dozeDriveBaselineScale
        )

        // Asleep: settle into rest and stop arbitrating. The shell reads `.sleeping`
        // as its cue to stop the frame clock, so this is the posture it freezes in.
        if mind.power == .sleeping {
            if mind.behavior != .rest {
                commit(.rest, state: state, mind: &mind, now: now)
            }
            return
        }

        // While a startle/flinch holds the body, arbitration waits — the reflex is not
        // a behavior and never competes with them.
        if let active = mind.reflex.active, now < active.endsAt, active.kind != .waryWatch {
            return
        }

        let overlaps = overlapsUserZone(state: state, mind: mind)
        let forced = mind.rearbitrateAt.map { now >= $0 } ?? false
            || (overlaps && mind.behavior != .yield)
            || (!overlaps && mind.behavior == .yield)
        let committed = now - mind.behaviorCommittedAt < MindConstants.behaviorMinCommitmentMs
        guard forced || !committed else { return }
        mind.rearbitrateAt = nil

        let scores = BehaviorScoring.scores(
            drives: mind.drives, situation: mind.situation.mode,
            temperament: mind.temperament, gazeKind: mind.gaze.targetKind,
            gazeAttention: mind.gaze.attention, overlapsUserZone: overlaps
        )
        let picked = BehaviorScoring.pick(
            scores: scores, incumbent: mind.behavior, rngValue: rng.nextUnit()
        )
        if picked != mind.behavior {
            commit(picked, state: state, mind: &mind, now: now)
        }
    }

    private func commit(
        _ behavior: BehaviorKind, state: AgentState, mind: inout MindState, now: Double
    ) {
        mind.behavior = behavior
        mind.behaviorCommittedAt = now
        switch behavior {
        case .idle, .rest:
            mind.behaviorTarget = nil
        case .wander:
            // No destination — wander is the heading-noise force. A fresh heading draw
            // per commit keeps consecutive ambles from repeating a direction.
            mind.behaviorTarget = nil
            mind.wander = WanderState(heading: rng.nextUnit() * 2 * .pi)
        case .inspect:
            mind.behaviorTarget = inspectTarget(state: state, mind: mind)
        case .yield:
            if let zone = attentionZone(from: state.world) {
                let screen = nearestScreen(
                    to: bodyCenter(of: mind, size: state.body.size),
                    screens: state.world.screens
                )
                mind.behaviorTarget = escapePoint(
                    avatarPosition: mind.physics.position, avatarSize: state.body.size,
                    zone: zone, screen: screen, padding: Constants.caretAvoidPadding
                )
            } else {
                mind.behaviorTarget = nil
            }
        }
    }

    /// Approach whatever the eyes are on, but stop `inspectStandOffPx` short — leaning
    /// in to look, not sitting on the thing. Returns nil when already that close.
    private func inspectTarget(state: AgentState, mind: MindState) -> Point? {
        let point = mind.gaze.targetPoint
        let bodyCenter = bodyCenter(of: mind, size: state.body.size)
        let gap = distance(point, bodyCenter)
        guard gap > MindConstants.inspectStandOffPx else { return nil }
        let standCenter = Point(
            x: point.x + (bodyCenter.x - point.x) / gap * MindConstants.inspectStandOffPx,
            y: point.y + (bodyCenter.y - point.y) / gap * MindConstants.inspectStandOffPx
        )
        let topLeft = Point(
            x: standCenter.x - state.body.size.width / 2,
            y: standCenter.y - state.body.size.height / 2
        )
        let screen = nearestScreen(to: standCenter, screens: state.world.screens)
        return clampToScreen(point: topLeft, screen: screen, blobSize: state.body.size)
    }

    private func overlapsUserZone(state: AgentState, mind: MindState) -> Bool {
        guard let zone = attentionZone(from: state.world) else { return false }
        return rectsOverlap(Rect(origin: mind.physics.position, size: state.body.size), zone)
    }

    // MARK: - Motor (steering → physics → confinement)

    private func advanceBody(state: AgentState, mind: inout MindState, now: Double, dt: Double) {
        let size = state.body.size
        let center = bodyCenter(of: mind, size: size)
        let screen = nearestScreen(to: center, screens: state.world.screens)

        var force: Vector
        var maxSpeed = MindConstants.cruiseSpeedPxPerSecond * mind.temperament.tempo
        if let reflexForce = mind.reflex.steeringForce(
            bodyCenter: center, velocity: mind.physics.velocity,
            maxSpeed: MindConstants.reflexFleeSpeedPxPerSecond, now: now
        ) {
            force = reflexForce
            maxSpeed = MindConstants.reflexFleeSpeedPxPerSecond
        } else {
            switch mind.behavior {
            case .idle, .rest:
                force = Vector(dx: 0, dy: 0)
            case .wander:
                force = mind.wander.steer(rng: rng, dt: dt)
            case .inspect:
                force = arriveForce(mind: mind, maxSpeed: maxSpeed)
            case .yield:
                maxSpeed = MindConstants.yieldSpeedPxPerSecond
                force = arriveForce(mind: mind, maxSpeed: maxSpeed)
            }
        }
        let cushion = Steering.avoidEdges(
            position: mind.physics.position, size: size, screen: screen.frame
        )
        force = Vector(dx: force.dx + cushion.dx, dy: force.dy + cushion.dy)

        mind.stepper.advance(&mind.physics, force: force, maxSpeed: maxSpeed, frameDt: dt)
        mind.physics.position = clampToScreen(
            point: mind.physics.position, screen: screen, blobSize: size
        )

        // Arrival ends the behavior's business — force a re-score rather than idling
        // inside a stale commitment ("resume or re-arbitrate", the arrival case).
        if let target = mind.behaviorTarget,
           distance(mind.physics.position, target) < MindConstants.arriveRadiusPx {
            mind.behaviorTarget = nil
            mind.rearbitrateAt = now
        }
    }

    private func arriveForce(mind: MindState, maxSpeed: Double) -> Vector {
        guard let target = mind.behaviorTarget else { return Vector(dx: 0, dy: 0) }
        return Steering.arrive(
            position: mind.physics.position, velocity: mind.physics.velocity,
            target: target, maxSpeed: maxSpeed
        )
    }

    // MARK: - Gaze + shared-store recovery

    private func updateGaze(state: AgentState, mind: inout MindState, now: Double, dt: Double) {
        let size = state.body.size
        // The eyes lead the body only when it moves with purpose — a destination, not
        // a wander heading. Gaze points are world points, so re-center the target.
        let locomotion = mind.behaviorTarget.map { center(of: Rect(origin: $0, size: size)) }
        let onsetBefore = mind.gaze.lastOnsetAt
        let context = GazeContext(
            world: state.world, bodyCenter: bodyCenter(of: mind, size: size),
            locomotionTarget: locomotion, drives: mind.drives, temperament: mind.temperament
        )
        mind.gaze.update(context: context, habituation: &mind.habituation, now: now, dt: dt)
        if mind.gaze.lastOnsetAt != onsetBefore {
            DriveDynamics.apply(.novelty, to: &mind.drives, temperament: mind.temperament)
        }
        // The Brain's once-per-tick recovery on the shared store: everything the eyes
        // are not on right now — reflex keys included — walks back toward fresh.
        mind.habituation.recover(dt: dt, except: mind.gaze.targetKind.rawValue)
    }

    // MARK: - Blink (same rhythm as the classic path)

    private func updateBlink(state: inout AgentState, now: Double) {
        if state.memory.blinking, now >= state.memory.blinkEndsAt {
            state.memory.blinking = false
        }
        if !state.memory.blinking, now >= state.memory.nextBlinkAt {
            state.memory.blinking = true
            state.memory.blinkEndsAt = now + Constants.blinkActiveMs
            state.memory.nextBlinkAt = now + randomRange(Constants.blinkIntervalMsRange)
        }
    }

    /// One rng draw uniformly inside `range` — same helper the classic path keeps
    /// privately; re-declared here because `StateMachine` is a frozen mechanical port.
    private func randomRange(_ range: Constants.MsRange) -> Double {
        lerp(range.min, range.max, rng.nextUnit())
    }

    // MARK: - Body write-back (the render seam)

    private func writeBack(state: inout AgentState, mind: MindState, now: Double) {
        state.body.position = mind.physics.position
        state.body.target = mind.behaviorTarget ?? mind.physics.position
        state.body.moving = mind.physics.velocity.magnitude
            > MindConstants.bodyMovingThresholdPxPerSecond
        state.body.mode = Self.displayMode(for: mind.behavior)
        state.body.emotion = emotion(state: state, mind: mind, now: now)
    }

    /// The classic `Mode` the status surfaces show for each behavior — inspect reads as
    /// wandering-with-purpose, yield as the flee it is.
    static func displayMode(for behavior: BehaviorKind) -> Mode {
        switch behavior {
        case .idle: return .idle
        case .rest: return .rest
        case .wander, .inspect: return .wander
        case .yield: return .flee
        }
    }

    /// The emotion ladder (decision log D5 — existing faces only, highest first):
    /// in-hand blush, reflex surprise (wary watch reads as sharpened curiosity), then
    /// what the committed behavior feels like.
    private func emotion(state: AgentState, mind: MindState, now: Double) -> Emotion {
        if state.body.dragging { return .blush }
        if let active = mind.reflex.active, now < active.endsAt {
            return active.kind == .waryWatch ? .curious : .surprised
        }
        switch mind.behavior {
        case .yield: return .annoyed
        case .inspect: return .curious
        case .rest: return state.body.moving ? .neutral : .sleepy
        case .idle, .wander: return .neutral
        }
    }

    private func bodyCenter(of mind: MindState, size: Size) -> Point {
        center(of: Rect(origin: mind.physics.position, size: size))
    }

    // MARK: - Temperament switching (decision log D10)

    /// Swaps the temperament vector in place and nothing else: the drives keep their
    /// current values and ease toward the new baselines over seconds via their own
    /// leaky dynamics — switching preset is a mood shift, not a personality transplant.
    /// A brain method (not a raw `state.mind` write from the shell) to keep the
    /// single-writer discipline: like the drag seam, this is the Brain being told.
    public func adoptTemperament(_ temperament: Temperament, state: inout AgentState) {
        state.mind?.temperament = temperament
    }

    // MARK: - Drag seam (mirrors the classic StateMachine's signatures)

    public func beginDrag(state: inout AgentState) {
        state.body.dragging = true
        state.body.moving = false
        state.body.dragOffset = Vector(
            dx: state.world.cursor.x - state.body.position.x,
            dy: state.world.cursor.y - state.body.position.y
        )
    }

    public func updateDrag(state: inout AgentState) {
        let raw = Point(
            x: state.world.cursor.x - state.body.dragOffset.dx,
            y: state.world.cursor.y - state.body.dragOffset.dy
        )
        let screen = nearestScreen(to: state.world.cursor, screens: state.world.screens)
        state.body.position = clampToScreen(point: raw, screen: screen, blobSize: state.body.size)
        state.mind?.physics.position = state.body.position
        state.mind?.physics.velocity = Vector(dx: 0, dy: 0)
    }

    public func endDrag(state: inout AgentState, now: Double) {
        state.body.dragging = false
        guard var mind = state.mind else { return }
        state.mind = nil // take pattern — see tick()
        DriveDynamics.apply(.droppedGently, to: &mind.drives, temperament: mind.temperament)
        // Being put down is new information — re-score rather than resuming whatever
        // was committed before the hand closed.
        mind.rearbitrateAt = now
        state.mind = mind
    }
}
