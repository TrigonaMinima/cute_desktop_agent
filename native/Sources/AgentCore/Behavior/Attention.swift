import Foundation

// Net-new, beyond blob.js parity: turns already-collected perception signals (caret
// location, typing, scrolling, cursor) into the region the agent should avoid occupying
// — see CLAUDE.md's movement-brain plan. Pure — no rng/clock — so these live as free
// functions alongside Math/Avoidance.swift's geometry and EmotionPriority.swift's ladder.
//
// Deliberate scope: only the caret produces a keep-out zone. Scrolling and
// `frontmostWindow` are NOT precise enough — a maximized/fullscreen window's frame is the
// whole screen, which would leave the avatar nowhere to go, and there is no signal for
// "where the eyes are" while passively reading. Cursor contact is handled separately
// (`cursorContactShouldFlee`), gated on active work so idle contact never flees — that's
// what keeps the avatar draggable.

/// The region (web space) the user's typing is anchored to, padded by
/// `Constants.caretAvoidPadding` on every side. `nil` when there's no precise signal to
/// avoid this frame (not typing, or typing without a caret rect — many apps don't expose
/// one via the Accessibility API).
public func attentionZone(from world: AgentWorld) -> Rect? {
    guard world.typing, let caret = world.typingLocation else { return nil }
    let padding = Constants.caretAvoidPadding
    return Rect(
        origin: Point(x: caret.origin.x - padding, y: caret.origin.y - padding),
        size: Size(width: caret.size.width + padding * 2, height: caret.size.height + padding * 2)
    )
}

/// The point the "polite" target-picking bias should steer away from: the caret's center
/// when precisely known, otherwise the cursor (always present, so this always resolves).
public func activityAnchor(from world: AgentWorld) -> Point {
    if world.typing, let caret = world.typingLocation {
        return Point(x: caret.origin.x + caret.size.width / 2, y: caret.origin.y + caret.size.height / 2)
    }
    return world.cursor
}

/// Whether cursor contact with the avatar should trigger a flee. Gated on active work
/// (typing or scrolling) — reaching over to grab/pet the avatar while idle never flees;
/// only the existing proximity *emotion* startle fires then (see
/// `StateMachine.updateEmotionTriggers`). This preserves draggability.
public func cursorContactShouldFlee(world: AgentWorld, position: Point, size: Size) -> Bool {
    guard world.typing || world.scrolling else { return false }
    return isHovering(cursor: world.cursor, position: position, size: size)
}
