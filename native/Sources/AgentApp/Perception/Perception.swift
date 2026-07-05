import AppKit
import AgentCore

/// Per-tick poll of OS state the click-through overlay can't get from ordinary mouse-move
/// events — a `.ignoresMouseEvents` window receives no move events except while the hit
/// test has it enabled over the avatar, so hover and proximity are driven by polling
/// `NSEvent.mouseLocation` once a frame rather than by `NSResponder` mouse-moved events.
///
/// A class, not an enum namespace, because deriving `cursorVelocity` needs a tick-to-tick
/// baseline — mirrors `FrameClock`, which owns `lastTimestamp` the same way rather than
/// making its caller thread a "previous" value through each call.
final class Perception {
    /// Last polled cursor position — the baseline this poll diffs against to derive
    /// `cursorVelocity`. Deliberately separate from `AgentState.world.cursor`, which
    /// `AppDelegate`'s drag handlers also write between ticks; keeping this poll-only
    /// avoids a drag turning into a velocity spike.
    private var lastCursor: Point?

    /// `dt` is this frame's delta (seconds) — macOS has no cursor-velocity API, so velocity
    /// is derived here via `AgentCore.cursorVelocity` rather than read from the OS. The
    /// first poll has no prior frame to diff against; `cursorVelocity` floors that (and any
    /// `dt <= 0`) to zero rather than dividing by zero/negative.
    func poll(screenFrame: NSRect, dt: Double) -> (cursor: Point, cursorVelocity: Vector, frontmostApp: AppInfo?) {
        let cursor = CoordinateSpace.webPoint(fromGlobal: NSEvent.mouseLocation, screenFrame: screenFrame)
        // No prior sample on the first poll (`lastCursor == nil`) — fall back to `cursor`
        // itself so `from == to` and the numerator is zero, letting `cursorVelocity` own all
        // zero-velocity logic in one place instead of special-casing "no baseline yet" here too.
        let velocity = AgentCore.cursorVelocity(from: lastCursor ?? cursor, to: cursor, dt: dt)
        lastCursor = cursor
        let frontmostApp = NSWorkspace.shared.frontmostApplication.map {
            AppInfo(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "?")
        }
        return (cursor, velocity, frontmostApp)
    }
}
