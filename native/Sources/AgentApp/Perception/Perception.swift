import AppKit
import AgentCore

/// Per-tick poll of OS state the click-through overlay can't get from ordinary mouse-move
/// events — a `.ignoresMouseEvents` window receives no move events except while the hit
/// test has it enabled over the avatar, so hover and proximity are driven by polling
/// `NSEvent.mouseLocation` once a frame rather than by `NSResponder` mouse-moved events.
enum Perception {
    static func poll(screenFrame: NSRect) -> (cursor: Point, frontmostApp: AppInfo?) {
        let cursor = CoordinateSpace.webPoint(fromGlobal: NSEvent.mouseLocation, screenFrame: screenFrame)
        let frontmostApp = NSWorkspace.shared.frontmostApplication.map {
            AppInfo(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "?")
        }
        return (cursor, frontmostApp)
    }
}
