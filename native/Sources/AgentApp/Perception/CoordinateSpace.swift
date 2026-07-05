import AppKit
import AgentCore

/// The one place the OS's bottom-left-origin global cursor coordinate gets flipped into
/// the top-left-origin, y-down "web space" every `AgentCore`/`AgentState` coordinate
/// assumes (see `AgentBody.position`'s doc comment).
enum CoordinateSpace {
    static func webPoint(fromGlobal global: NSPoint, screenFrame: NSRect) -> Point {
        Point(
            x: Double(global.x - screenFrame.origin.x),
            y: Double(screenFrame.height - (global.y - screenFrame.origin.y))
        )
    }

    /// Converts an AX-sourced rect (e.g. a caret's `kAXBoundsForRange` result) into web
    /// space. Unlike `webPoint`'s input (`NSEvent.mouseLocation`, Cocoa's bottom-left-origin,
    /// y-up global space), Accessibility geometry attributes are already reported in the
    /// same top-left-origin, y-down convention web space uses (Quartz/CG display
    /// coordinates) — so no flip here; applying `webPoint`'s flip to this input would
    /// double-flip it. This only holds relative to the main screen's origin, which is what
    /// `AppDelegate` restricts perception to today — multi-monitor support would need this
    /// revisited.
    static func webRect(fromGlobal global: NSRect) -> Rect {
        Rect(
            origin: Point(x: Double(global.origin.x), y: Double(global.origin.y)),
            size: Size(width: Double(global.width), height: Double(global.height))
        )
    }
}
