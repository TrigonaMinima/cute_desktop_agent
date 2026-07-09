import AppKit
import AgentCore

/// A frozen snapshot of every attached display, taken once at launch and again on each
/// `didChangeScreenParametersNotification` — never queried live mid-frame, so one frame
/// always sees one consistent screen list (mirrors `AgentState`'s frozen-copy-per-frame
/// discipline).
///
/// Two coordinate views per display: `cocoaFrame` (bottom-left origin, y up) for
/// building `OverlayPanel`s, and web-space rects (global top-left origin, y down —
/// `webY = primaryHeight - cocoaY`) for everything AgentCore-facing. Secondary displays
/// routinely have non-zero, even negative, origins in both spaces.
struct ScreenLayout {
    struct Display {
        /// Full frame in Cocoa's global space — what `OverlayPanel`'s contentRect wants.
        let cocoaFrame: NSRect
        /// Full frame in global web space — this display's panel/world render origin.
        let fullFrameWeb: Rect
        /// `visibleFrame` (menu bar and dock excluded) in global web space — the rect
        /// AgentCore confines the avatar to (`ScreenInfo.frame`).
        let visibleFrameWeb: Rect
        let name: String
    }

    let displays: [Display]
    /// The primary display's height (points) — the global y-flip constant. The primary
    /// screen's Cocoa origin is always (0, 0), so its frame height alone defines
    /// `webY = primaryHeight - cocoaY` for every display.
    let primaryHeight: Double

    /// The AgentCore-facing view of this layout — index 0 is the primary display,
    /// matching `NSScreen.screens`' ordering guarantee. Stored, not computed:
    /// `Perception.poll` reads it every frame, so it's built once per snapshot rather
    /// than re-mapped 60 times a second.
    let screens: [ScreenInfo]

    /// Snapshots `NSScreen.screens`. The list can be momentarily empty mid-reconfiguration
    /// (a display unplug races the notification), so callers pass their last-known-good
    /// layout as `fallback` rather than building a zero-screen world —
    /// `AgentWorld.screens` is never-empty by contract. Returns `nil` only when there is
    /// no fallback either (first launch with no display, which cannot happen in practice).
    static func current(fallback: ScreenLayout?) -> ScreenLayout? {
        let nsScreens = NSScreen.screens
        guard let primary = nsScreens.first else { return fallback }
        let primaryHeight = Double(primary.frame.height)
        let displays = nsScreens.map { screen in
            Display(
                cocoaFrame: screen.frame,
                fullFrameWeb: webRect(screen.frame, primaryHeight: primaryHeight),
                visibleFrameWeb: webRect(screen.visibleFrame, primaryHeight: primaryHeight),
                name: screen.localizedName
            )
        }
        return ScreenLayout(
            displays: displays,
            primaryHeight: primaryHeight,
            screens: displays.map { ScreenInfo(frame: $0.visibleFrameWeb, name: $0.name) }
        )
    }

    /// Cocoa rect (bottom-left origin, y up) → global web rect (top-left origin, y
    /// down): x passes through; the web origin is the rect's top-left corner
    /// (`minX`, `maxY`) run through `CoordinateSpace.webPoint` — the single y-flip site.
    private static func webRect(_ rect: NSRect, primaryHeight: Double) -> Rect {
        Rect(
            origin: CoordinateSpace.webPoint(
                fromGlobal: NSPoint(x: rect.minX, y: rect.maxY), primaryHeight: primaryHeight
            ),
            size: Size(width: Double(rect.width), height: Double(rect.height))
        )
    }
}
