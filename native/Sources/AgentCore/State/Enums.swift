import Foundation

// String-backed so AgentState's JSON is human- and LLM-legible (see AgentState.swift).

/// The agent's current behavior-machine mode. `happy` is transient — triggered by a
/// drop after a drag, not chosen by `weightedChoice`. `flee` is also transient and
/// beyond blob.js parity (net-new attention-avoidance behavior, see Attention.swift) —
/// triggered when the avatar overlaps the user's attention zone, never chosen by
/// `weightedChoice` (excluded from `Constants.modeWeights`).
public enum Mode: String, Codable, CaseIterable, Equatable {
    case idle, wander, rest, peek, happy, flee
}

/// The agent's current displayed emotion. Priority ladder (highest first) lives in the
/// state machine (Phase 3): dragging -> surprised, happy mode -> happy, active quirk,
/// active proximity startle, else the base emotion for the current mode.
public enum Emotion: String, Codable, CaseIterable, Equatable {
    case neutral, happy, curious, surprised, sleepy, thinking, annoyed, blush
}

/// Which blush treatment (if any) an emotion wears on the avatar's face.
public enum BlushStyle: String, Codable, Equatable {
    case none, plain, hatch
}
