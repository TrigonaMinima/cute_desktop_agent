import AppKit

/// Full-screen, click-through, always-on-top host window. Adapted from the Phase 0
/// spike's `ClickThroughPanel` recipe (`native/Sources/Spike/main.swift`).
///
/// `canBecomeKey`/`canBecomeMain` are pinned to `false` so nothing about this window can
/// ever steal activation from whatever app the user is actually using — perception's
/// `frontmostApplication` read must stay truthful even while the avatar is on screen.
///
/// Starts with mouse events ignored (fully click-through). `AppDelegate.updateHitTest`
/// flips `ignoresMouseEvents` off once a frame while the cursor is hovering the avatar
/// (or a drag is in progress) and back on otherwise, so the window only intercepts
/// events right around the avatar itself.
public final class OverlayPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(screenFrame: NSRect, contentView: NSView) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        self.contentView = contentView
    }
}
