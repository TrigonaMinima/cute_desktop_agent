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
}
