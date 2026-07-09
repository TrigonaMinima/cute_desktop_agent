import AppKit
import AgentCore

/// The one place the OS's bottom-left-origin global coordinates get flipped into the
/// top-left-origin, y-down "web space" every `AgentCore`/`AgentState` coordinate
/// assumes (see `AgentBody.position`'s doc comment). Web space is GLOBAL: anchored at
/// the primary display's top-left, spanning all displays — `ScreenLayout` builds its
/// per-display web rects through `webPoint` below, so the flip convention lives only here.
enum CoordinateSpace {
    /// Cocoa global point (bottom-left origin, y up) → global web point. One uniform
    /// flip against the primary display's height covers every display, since Cocoa's
    /// global space is itself anchored at the primary display's bottom-left.
    static func webPoint(fromGlobal global: NSPoint, primaryHeight: Double) -> Point {
        Point(
            x: Double(global.x),
            y: primaryHeight - Double(global.y)
        )
    }

    /// Converts an AX-sourced rect (e.g. a caret's `kAXBoundsForRange` result) into web
    /// space. Unlike `webPoint`'s input (`NSEvent.mouseLocation`, Cocoa's bottom-left-origin,
    /// y-up global space), Accessibility geometry attributes are already reported in the
    /// same top-left-origin, y-down convention web space uses (Quartz/CG display
    /// coordinates, anchored at the primary display's top-left) — so no flip here;
    /// applying `webPoint`'s flip to this input would double-flip it. Now that web space
    /// is global (not main-screen-local), this pass-through is correct on all screens.
    static func webRect(fromGlobal global: NSRect) -> Rect {
        Rect(
            origin: Point(x: Double(global.origin.x), y: Double(global.origin.y)),
            size: Size(width: Double(global.width), height: Double(global.height))
        )
    }
}
