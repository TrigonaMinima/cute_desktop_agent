import Foundation

/// The response tiers one habituating mechanism produces from one stimulus: full
/// startle, small flinch, eyes-only wary watch — and below that, nothing.
public enum ReflexKind: String, Codable, Equatable {
    case startle, flinch, waryWatch
}

/// A fired reflex: what tier, where it came from, how hard (post-gain, post-habituation),
/// and when the body is released again.
public struct ReflexEvent: Codable, Equatable {
    public var kind: ReflexKind
    public var source: Point
    public var intensity: Double
    public var firedAt: Double
    public var endsAt: Double
}

/// The reflex arc (design doc layer 2): rule-based, evaluated on the fast tick, straight
/// from perception to motor — it can seize the body mid-motion, and arbiter hysteresis
/// never gates it. Effective intensity is `raw × temperament.reflexGain × (1 − habituation)`,
/// so repeated stimuli walk down the startle → flinch → wary-watch → nothing ladder and
/// rest walks them back up: the interrupt system and the anti-repetition system are the
/// same mechanism.
///
/// v0 detects one stimulus — the cursor darting at the body — keyed as "cursorDart" in
/// the shared `Habituation` store (the same store gaze scores against). The arc only
/// *detects and times* events; the Brain applies the consequences (gaze snap, arousal
/// impulse, emotion, and re-arbitration when the event ends).
public struct ReflexArc: Codable, Equatable {
    public private(set) var active: ReflexEvent?

    static let dartKey = "cursorDart"

    public init() {}

    /// One fast tick: detect, gate through habituation, and fire. Returns the newly
    /// fired event, if any — `nil` means the body stays with whoever had it.
    public mutating func tick(
        world: AgentWorld, bodyCenter: Point, habituation: inout Habituation,
        temperament: Temperament, now: Double
    ) -> ReflexEvent? {
        // Refractory: an active event runs to completion, and a fresh stimulus right on
        // its heels is part of the same poke, not a new one.
        if let active, now < active.endsAt + MindConstants.reflexRefractoryMs {
            return nil
        }
        active = nil

        guard let raw = Self.dartIntensity(world: world, bodyCenter: bodyCenter) else {
            return nil
        }
        // Even a tuned-out stimulus deepens habituation — being ignored is still being
        // experienced.
        let familiarity = habituation.level(for: Self.dartKey)
        habituation.expose(
            Self.dartKey,
            dt: MindConstants.reflexEventExposureSeconds,
            rate: temperament.habituationRate
        )

        let intensity = raw * temperament.reflexGain * (1 - familiarity)
        guard let kind = Self.tier(for: intensity) else { return nil }
        let event = ReflexEvent(
            kind: kind, source: world.cursor, intensity: min(1, intensity),
            firedAt: now, endsAt: now + Self.duration(of: kind)
        )
        active = event
        return event
    }

    /// The motor seize: while a startle or flinch is live, an escape force away from
    /// the source, scaled by intensity. Wary watch is eyes-only — no force. `nil` hands
    /// the body back to the arbiter.
    public func steeringForce(
        bodyCenter: Point, velocity: Vector, maxSpeed: Double, now: Double
    ) -> Vector? {
        guard let active, now < active.endsAt, active.kind != .waryWatch else { return nil }
        return Steering.flee(
            position: bodyCenter, velocity: velocity, threat: active.source,
            maxSpeed: maxSpeed * active.intensity
        )
    }

    /// Raw dart intensity in 0…1, or nil when the cursor isn't darting at the body:
    /// must be close, and *closing* fast (velocity projected onto the cursor→body line —
    /// a fast cursor racing away is not a threat).
    static func dartIntensity(world: AgentWorld, bodyCenter: Point) -> Double? {
        let dx = bodyCenter.x - world.cursor.x
        let dy = bodyCenter.y - world.cursor.y
        let separation = (dx * dx + dy * dy).squareRoot()
        guard separation > 0, separation <= MindConstants.reflexDartDistancePx else {
            return nil
        }
        let closingSpeed = (world.cursorVelocity.dx * dx + world.cursorVelocity.dy * dy) / separation
        guard closingSpeed >= MindConstants.reflexDartMinClosingSpeed else { return nil }
        return min(1, closingSpeed / MindConstants.reflexDartFullClosingSpeed)
    }

    static func tier(for intensity: Double) -> ReflexKind? {
        if intensity >= MindConstants.reflexStartleThreshold { return .startle }
        if intensity >= MindConstants.reflexFlinchThreshold { return .flinch }
        if intensity >= MindConstants.reflexWaryWatchThreshold { return .waryWatch }
        return nil
    }

    static func duration(of kind: ReflexKind) -> Double {
        switch kind {
        case .startle: return MindConstants.startleDurationMs
        case .flinch: return MindConstants.flinchDurationMs
        case .waryWatch: return MindConstants.waryWatchDurationMs
        }
    }
}
