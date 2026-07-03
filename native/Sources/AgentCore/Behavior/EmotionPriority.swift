import Foundation

// Mechanical port of blob.js's computeDesiredEmotion. Pure: reads a frozen AgentState,
// touches no RNG/Clock, so — unlike the rest of StateMachine's ported functions — it
// lives as a free function rather than a method, alongside Math/Geometry.swift's other
// pure helpers.

/// Priority ladder (highest first): dragging -> surprised, happy mode -> happy, active
/// quirk, active proximity startle, else the base emotion for the mode.
func computeDesiredEmotion(state: AgentState, now: Double) -> Emotion {
    if state.body.dragging { return .surprised }
    if state.body.mode == .happy { return .happy }
    if now < state.memory.quirkUntil, let quirk = state.memory.quirkEmotion { return quirk }
    if now < state.memory.proximityUntil { return .surprised }
    return Constants.baseEmotionByMode[state.body.mode] ?? .neutral
}
