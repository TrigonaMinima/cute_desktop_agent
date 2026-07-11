import Foundation

/// What the eyes can be on. Raw values double as `Habituation` keys.
public enum GazeTargetKind: String, Codable, Equatable {
    /// The user's pointer — weighted up when fast or near the body.
    case cursor
    /// Something that just changed: a window opened/switched. Novelty's pull, decaying.
    case onset
    /// The user themselves, stood in for by the caret, the focused window, or
    /// front-and-center — "look back at you" is always a candidate.
    case user
    /// On-screen motion; v0's cheap proxy is active scrolling in the frontmost window.
    case motion
    /// Jiggy's own locomotion target — the eyes lead the body when it moves with purpose.
    case locomotion
    /// The resting gaze (ahead, slightly down) that wins when nothing else does.
    case neutral
}

/// Everything the gaze contest scores against, gathered per tick by the Brain. Kept as
/// a struct so the salience math stays a pure function of visible inputs.
public struct GazeContext {
    public var world: AgentWorld
    public var bodyCenter: Point
    /// Where the body is headed when moving with purpose; nil when it isn't.
    public var locomotionTarget: Point?
    public var drives: Drives
    public var temperament: Temperament

    public init(
        world: AgentWorld, bodyCenter: Point, locomotionTarget: Point?,
        drives: Drives, temperament: Temperament
    ) {
        self.world = world
        self.bodyCenter = bodyCenter
        self.locomotionTarget = locomotionTarget
        self.drives = drives
        self.temperament = temperament
    }
}

/// The attention spine (design doc "Gaze: how attention gets allocated"): a small
/// salience contest over candidates, its own switch margin + minimum dwell so attention
/// never strobes, then a fast saccade to acquire and attention-scaled smooth pursuit to
/// hold. Runs on the fast side of cognition — every display frame — because a late
/// glance reads as dead. A reflex `snap` bypasses all hysteresis (the interrupt
/// contract gaze shares with the motor layer).
///
/// Time convention matches the rest of the core: `now` in ms, `dt` in seconds.
public struct GazeSystem: Codable, Equatable {
    /// What the eyes are committed to.
    public private(set) var targetKind: GazeTargetKind
    /// Where the eyes actually look right now — pursues the target, never teleports
    /// (except under `snap`). This is the render layer's input.
    public private(set) var gazePoint: Point
    /// How locked-on, 0…1: chases the winner's salience, scales pursuit tightness.
    /// Internal setter so tests can pin it when isolating pursuit behavior.
    public internal(set) var attention: Double
    /// Where the committed target currently is (moves with the candidate under pursuit).
    var targetPoint: Point
    var lastSwitchAt: Double
    /// Frontmost app+window identity, compared field-by-field per tick for onset
    /// detection — a struct, not a concatenated string key, so no per-frame allocation.
    struct WindowIdentity: Codable, Equatable {
        var app: String?
        var owner: String?
        var title: String?
    }

    /// Frontmost app+window identity last tick, for onset detection.
    var lastWindow: WindowIdentity?
    var lastOnsetAt: Double?
    var onsetPoint: Point?

    public init(bodyCenter: Point, now: Double) {
        let rest = Self.neutralPoint(bodyCenter: bodyCenter)
        targetKind = .neutral
        gazePoint = rest
        attention = 0.2
        targetPoint = rest
        lastSwitchAt = now
    }

    // MARK: Per-frame update

    /// `habituation` is the mind-wide shared store (the reflex arc writes the same one),
    /// borrowed rather than owned so "the same habituation counters" is true by
    /// construction.
    public mutating func update(
        context: GazeContext, habituation: inout Habituation, now: Double, dt: Double
    ) {
        detectOnset(world: context.world, now: now)

        let candidates = scoredCandidates(context: context, habituation: habituation, now: now)
        let incumbent = candidates.first { $0.kind == targetKind }
        let winner = candidates.max { $0.salience < $1.salience }!
        if winner.kind != targetKind,
           Self.shouldSwitch(
               challengerSalience: winner.salience,
               incumbentSalience: incumbent?.salience ?? 0,
               lastSwitchAt: lastSwitchAt, now: now
           ) {
            targetKind = winner.kind
            lastSwitchAt = now
        }

        // Pursue wherever the committed target is *this* frame, so a moving candidate
        // is tracked, not its position at commit time. Derivable from the scans already
        // done: the committed target is the winner iff it holds the committed kind.
        let current = targetKind == winner.kind ? winner : incumbent
        targetPoint = current?.point ?? Self.neutralPoint(bodyCenter: context.bodyCenter)

        habituation.expose(targetKind.rawValue, dt: dt, rate: context.temperament.habituationRate)
        // Recovery for everything unattended is the Brain's once-per-tick job on the
        // shared store — doing it here too would double-decay the reflex keys.

        let salience = current?.salience ?? 0
        attention += (min(1, salience) - attention) * (1 - exp(-dt / MindConstants.attentionTauSeconds))

        moveEyes(now: now, dt: dt)
    }

    /// The reflex override: a startle snaps gaze to its source instantly, ignoring the
    /// margin and the dwell, exactly as reflexes preempt the body.
    public mutating func snap(to point: Point, now: Double) {
        targetKind = .onset
        targetPoint = point
        gazePoint = point
        attention = 1.0
        lastSwitchAt = now
        lastOnsetAt = now
        onsetPoint = point
    }

    /// Normalized look direction for pupil offsets: unit-clamped, full deflection at
    /// `MindConstants.gazeDirectionFullDeflectionPx` of offset from `center`.
    public func direction(from center: Point) -> Vector {
        let dx = gazePoint.x - center.x
        let dy = gazePoint.y - center.y
        let length = distance(center, gazePoint)
        guard length > 0 else { return Vector(dx: 0, dy: 0) }
        let deflection = min(1, length / MindConstants.gazeDirectionFullDeflectionPx)
        return Vector(dx: dx / length * deflection, dy: dy / length * deflection)
    }

    // MARK: Commit rule

    /// Gaze's hysteresis in one place: the challenger must clear the incumbent by the
    /// switch margin AND the current target must have been held for the minimum dwell.
    static func shouldSwitch(
        challengerSalience: Double, incumbentSalience: Double,
        lastSwitchAt: Double, now: Double
    ) -> Bool {
        challengerSalience >= incumbentSalience + MindConstants.gazeSwitchMargin
            && now - lastSwitchAt >= MindConstants.gazeMinDwellMs
    }

    // MARK: Salience scoring

    struct Candidate {
        var kind: GazeTargetKind
        var point: Point
        var salience: Double
    }

    /// Scores every present candidate. Non-neutral scores are scaled by arousal (low
    /// arousal flattens everything, so the eyes drift home) and suppressed by their own
    /// habituation; neutral is a fixed floor that wins when nothing else clears it.
    func scoredCandidates(context: GazeContext, habituation: Habituation, now: Double) -> [Candidate] {
        let world = context.world
        let drives = context.drives
        let arousalGain = lerp(MindConstants.gazeLowArousalGainFloor, 1.0, drives.arousal)

        func modulated(_ kind: GazeTargetKind, _ base: Double) -> Double {
            let fatigue = 1 - MindConstants.gazeHabituationStrength * habituation.level(for: kind.rawValue)
            return base * arousalGain * fatigue
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(6) // one per GazeTargetKind — no growth reallocations
        candidates.append(Candidate(
            kind: .neutral,
            point: Self.neutralPoint(bodyCenter: context.bodyCenter),
            salience: 0.18
        ))

        let cursorSpeed = world.cursorVelocity.magnitude
        let speedPull = min(0.45, cursorSpeed / MindConstants.cursorSalienceSpeedScale * 0.75)
        let cursorDistance = distance(world.cursor, context.bodyCenter)
        let proximityPull = 0.4 * max(0, 1 - cursorDistance / MindConstants.cursorSalienceProximityRadius)
        candidates.append(Candidate(
            kind: .cursor, point: world.cursor,
            salience: modulated(.cursor, 0.25 + speedPull + proximityPull)
        ))

        if let onsetPoint, let lastOnsetAt {
            // Onset beats motion beats static — but only briefly, and curiosity is what
            // keeps novelty interesting (calm's low curiosity weights it down).
            let age = max(0, now - lastOnsetAt) / 1000
            let freshness = exp(-age / MindConstants.onsetSalienceDecaySeconds)
            candidates.append(Candidate(
                kind: .onset, point: onsetPoint,
                salience: modulated(.onset, 1.0 * freshness * (0.5 + drives.curiosity))
            ))
        }

        if let userPoint = Self.userProxyPoint(world: world) {
            candidates.append(Candidate(
                kind: .user, point: userPoint,
                salience: modulated(.user, 0.4 * lerp(0.5, 1.6, drives.sociability))
            ))
        }

        if world.scrolling, let window = world.frontmostWindow {
            candidates.append(Candidate(
                kind: .motion, point: center(of: window.frame),
                salience: modulated(.motion, 0.6)
            ))
        }

        if let locomotionTarget = context.locomotionTarget {
            candidates.append(Candidate(
                kind: .locomotion, point: locomotionTarget,
                salience: modulated(.locomotion, 0.6)
            ))
        }

        return candidates
    }

    /// The user's stand-in: the active caret when exposed, else the focused window's
    /// center, else front-and-center of the screen the body is on — so "look back at
    /// you" is always a candidate.
    static func userProxyPoint(world: AgentWorld) -> Point? {
        if let caret = world.typingLocation {
            return center(of: caret)
        }
        if let window = world.frontmostWindow {
            return center(of: window.frame)
        }
        return world.screens.first.map { center(of: $0.frame) }
    }

    static func neutralPoint(bodyCenter: Point) -> Point {
        Point(x: bodyCenter.x, y: bodyCenter.y + MindConstants.neutralGazeDropPx)
    }

    // MARK: Eye motion (saccade, then attention-scaled pursuit)

    private mutating func moveEyes(now: Double, dt: Double) {
        let saccading = now - lastSwitchAt <= MindConstants.saccadeDurationMs
        let tau: Double
        if saccading {
            tau = MindConstants.saccadeTauSeconds
        } else {
            tau = lerp(
                MindConstants.pursuitLooseTauSeconds,
                MindConstants.pursuitTightTauSeconds,
                attention
            )
        }
        // Low attention tracks loosely purely via the slow tau; "drifts back toward
        // neutral" happens through the arbiter — flattened salience lets the neutral
        // candidate win, and the eyes glide home.
        let approach = 1 - exp(-dt / tau)
        gazePoint.x += (targetPoint.x - gazePoint.x) * approach
        gazePoint.y += (targetPoint.y - gazePoint.y) * approach
    }

    // MARK: Onset detection

    private mutating func detectOnset(world: AgentWorld, now: Double) {
        let identity = WindowIdentity(
            app: world.frontmostApp?.bundleIdentifier ?? world.frontmostApp?.name,
            owner: world.frontmostWindow?.ownerName,
            title: world.frontmostWindow?.title
        )
        defer { lastWindow = identity }
        // First frame establishes the baseline — launching next to an open window is
        // not an event.
        guard let lastWindow, lastWindow != identity else { return }
        lastOnsetAt = now
        onsetPoint = world.frontmostWindow.map { center(of: $0.frame) } ?? world.cursor
    }
}
