import AgentCore

/// One tick's worth of OS-observed signals — everything `Perception.poll(...)` derives
/// from a single frame. A value type rather than the labeled tuple `poll` used to return,
/// so `AppDelegate` maps it into `AgentWorld` with one call (`apply(_:)` below) instead of
/// copying eight fields by hand.
///
/// Lives here, not in `AgentCore` — it's a shell-side transport for what `Perception`
/// observed, not part of the behavior core's own state model. `AgentWorld` (AgentCore)
/// stays the single source of truth; this is just how a poll's results travel there.
struct PerceptionSnapshot {
    /// The current display list (from the `ScreenLayout` snapshot `AppDelegate` caches
    /// and hands to each poll) — stamped every frame like any other perceived signal, so
    /// a display change flows into `world.screens` through the same single-writer path
    /// as the cursor, and `StateMachine.reconcilePosition` sees it next tick.
    var screens: [ScreenInfo]
    var cursor: Point
    var cursorVelocity: Vector
    var frontmostApp: AppInfo?
    var frontmostWindow: WindowInfo?
    var typing: Bool
    var typingLocation: Rect?
    var scrolling: Bool
    var scrollVelocity: Vector
}

extension AgentWorld {
    /// Applies one poll's signals to `self` — the single mapping site `AppDelegate`'s
    /// per-frame tick calls instead of copying `PerceptionSnapshot`'s fields one by one.
    mutating func apply(_ snapshot: PerceptionSnapshot) {
        screens = snapshot.screens
        cursor = snapshot.cursor
        cursorVelocity = snapshot.cursorVelocity
        frontmostApp = snapshot.frontmostApp
        frontmostWindow = snapshot.frontmostWindow
        typing = snapshot.typing
        typingLocation = snapshot.typingLocation
        scrolling = snapshot.scrolling
        scrollVelocity = snapshot.scrollVelocity
    }
}
