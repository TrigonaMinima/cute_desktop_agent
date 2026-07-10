import Foundation

/// The frozen mode taxonomy (design doc "Situation model" + build path Phase 1): these
/// labels and their meanings are a stable contract. A later learned classifier may swap
/// the *detector's* internals, but never this label set — per-context stores (liveliness
/// floors today, learned preference fields in Phase 2) are keyed to it, so renaming or
/// adding cases orphans data. String-backed for JSON legibility, like `Mode`/`Emotion`.
public enum SituationMode: String, Codable, CaseIterable, Equatable {
    /// The user is actively typing into a focused app — deference wins.
    case focusTyping
    /// The user is watching something: fullscreen-ish surface, hands off the keyboard.
    case mediaWatching
    /// The user is idle or gone.
    case idleAway
    /// Everything else: pottering about, browsing, light interaction.
    case casualBrowsing
}
