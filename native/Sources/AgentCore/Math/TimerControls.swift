import Foundation

// Pure elapsed-time accumulation and on-screen row geometry for Jiggy's timer mode. Kept
// here in AgentCore (not AppKit) so it's unit-testable and shared by every call site that
// needs to agree on it: AvatarView.render (draws the row), AppDelegate.updateHitTest
// (accepts click-through events over it), and AppDelegate's mouseDown routing
// (button-tap vs. drag-start). The plan originally proposed a Render/ directory for this;
// AgentCore has no such directory (only Behavior/State/Math/Mind/Physics), so this lives
// alongside the other AppKit-adjacent pure geometry in Geometry.swift, e.g. `isHovering`.

/// Elapsed time since a timer started, given the shell's raw accumulator state — the pure
/// half of `TimerController.elapsedMs(now:)`. `accumulatedMs` is time banked from prior
/// running segments; `segmentStartedAt` is the clock ms the *current* running segment
/// began, nil while paused. A running timer with a nil `segmentStartedAt` is a
/// caller-side inconsistency (shouldn't happen in practice) and defensively falls back to
/// `accumulatedMs` rather than extrapolating from a missing start time.
public func timerElapsedMs(accumulatedMs: Double, running: Bool, segmentStartedAt: Double?, now: Double) -> Double {
    guard running, let segmentStartedAt else { return accumulatedMs }
    return accumulatedMs + (now - segmentStartedAt)
}

/// Fixed-width slot metrics for the `[button][remaining][total]` row. AgentCore has no
/// font-metrics/text-measurement capability (no AppKit/CoreText), so slots are fixed-width
/// rather than packed to actual text width — a deliberate simplification that keeps this
/// geometry purely testable, accepting a little layout slack in the AppKit renderer.
private enum TimerRowMetrics {
    static let buttonSize = Size(width: 40, height: 34)
    static let remainingWidth: Double = 92
    static let totalWidth: Double = 96
    static let rowHeight: Double = 34
    static let slotGap: Double = 8
    /// Vertical gap between the row's bottom edge and the avatar's top edge.
    static let rowGap: Double = 8
}

/// Total vertical space the row occupies above the avatar's top edge
/// (`rowGap + rowHeight`) — what `AppDelegate.startTimer` offsets the top-right pin
/// position down by, so the row itself (not the avatar) is what clears the menu bar.
public let timerRowClearance: Double = TimerRowMetrics.rowGap + TimerRowMetrics.rowHeight

/// Total horizontal space the row occupies to the right of its own left edge (button +
/// gap + remaining + gap + total) — always wider than the avatar itself. The row is
/// left-aligned with `position.x` (see `timerControlRect`), so pinning the avatar flush
/// against a screen's right edge using only the avatar's own width leaves the
/// `remaining`/`total` slots rendering past the physical screen edge. `AppDelegate.startTimer`
/// must offset the pin's `x` left by this width, not the avatar's, to keep the whole row
/// on screen — sized for the full row (button+remaining+total) even though `total` only
/// shows in overtime, so the row doesn't jump sideways when overtime kicks in.
public let timerRowWidth: Double =
    TimerRowMetrics.buttonSize.width + TimerRowMetrics.slotGap
        + TimerRowMetrics.remainingWidth + TimerRowMetrics.slotGap
        + TimerRowMetrics.totalWidth

/// Travel speed (px/s) `AppDelegate` steps `body.position` toward the pin target at when
/// a timer starts, via `moveToward` — deliberately well above any of the brains' own
/// motor-policy speeds (cruise 120, yield 220, reflex flee 340 — see `MindConstants`) so
/// the hop to the corner reads as "hurrying there," not a redecorated version of normal
/// wandering. The freeze branches in both brains don't need to know this is happening:
/// they just pin to wherever `body.position` currently is each frame, so the shell
/// animating it out from under them for a few frames "just works."
public let timerPinTravelSpeedPxPerSecond: Double = 1400

/// The play/pause button rect — leftmost slot, left-aligned with the avatar, sitting
/// above its top edge by `TimerRowMetrics.rowGap`.
public func timerControlRect(position: Point, size: Size) -> Rect {
    Rect(
        origin: Point(x: position.x, y: position.y - TimerRowMetrics.rowGap - TimerRowMetrics.rowHeight),
        size: TimerRowMetrics.buttonSize
    )
}

/// The middle slot (remaining time), immediately right of the button with `slotGap`
/// between them, sharing the row's top edge.
public func timerRemainingRect(position: Point, size: Size) -> Rect {
    let button = timerControlRect(position: position, size: size)
    return Rect(
        origin: Point(x: button.origin.x + button.size.width + TimerRowMetrics.slotGap, y: button.origin.y),
        size: Size(width: TimerRowMetrics.remainingWidth, height: TimerRowMetrics.rowHeight)
    )
}

/// The rightmost slot (total elapsed, shown only in overtime), immediately right of the
/// remaining slot with `slotGap` between them.
public func timerTotalRect(position: Point, size: Size) -> Rect {
    let remaining = timerRemainingRect(position: position, size: size)
    return Rect(
        origin: Point(x: remaining.origin.x + remaining.size.width + TimerRowMetrics.slotGap, y: remaining.origin.y),
        size: Size(width: TimerRowMetrics.totalWidth, height: TimerRowMetrics.rowHeight)
    )
}

/// Union of the avatar's own box and the full row — what `updateHitTest` checks while a
/// timer is active, so the button (and the rest of the row) stays hittable through an
/// otherwise click-through panel. Load-bearing: hover must stay polled from
/// `state.world.cursor` each frame, never from panel mouse events (see AppDelegate).
public func timerInteractiveRect(position: Point, size: Size) -> Rect {
    let avatar = Rect(origin: position, size: size)
    let button = timerControlRect(position: position, size: size)
    let total = timerTotalRect(position: position, size: size)
    return union(avatar, union(button, total))
}

/// Smallest rect containing both inputs — the general union both timer geometry above
/// and any future multi-rect hit-testing can share.
private func union(_ a: Rect, _ b: Rect) -> Rect {
    let minX = Swift.min(a.origin.x, b.origin.x)
    let minY = Swift.min(a.origin.y, b.origin.y)
    let maxX = Swift.max(a.origin.x + a.size.width, b.origin.x + b.size.width)
    let maxY = Swift.max(a.origin.y + a.size.height, b.origin.y + b.size.height)
    return Rect(origin: Point(x: minX, y: minY), size: Size(width: maxX - minX, height: maxY - minY))
}

/// Point-in-rect classification (both edges inclusive) — the `Rect`-based sibling of
/// `isHovering`, used to tell a button tap apart from a drag-start or an avatar-body hit.
public func isWithin(point: Point, rect: Rect) -> Bool {
    isHovering(cursor: point, position: rect.origin, size: rect.size)
}
