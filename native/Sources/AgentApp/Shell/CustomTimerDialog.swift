import AppKit

/// Replaces `NSAlert`'s generic system chrome (default app icon, red-tinted primary
/// button) for the "Custom…" duration entry with a small borderless panel styled to
/// match Jiggy's own palette — dark background, the same orange the on-screen timer row
/// uses for overtime, rounded everything. Modal, mirrors the `NSAlert.runModal()` call
/// site it replaces: returns the chosen minutes, or `nil` if the user cancelled or typed
/// something that isn't a positive number.
enum CustomTimerDialog {
    private static let panelSize = CGSize(width: 260, height: 176)

    static func run() -> Double? {
        let panel = KeyableBorderlessPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // `.modalPanel`, not the avatar overlay's `.screenSaver`-tier level: this panel is
        // interactive (needs real key-window/keyboard-focus status for the text field), and
        // WindowServer key-focus semantics get unreliable that high up — it's exactly why
        // `OverlayPanel` (same super-high level) hardcodes `canBecomeKey = false` and never
        // takes keyboard input at all.
        panel.level = .modalPanel
        // Forces dark-appropriate defaults for anything not explicitly colored below —
        // `calibratedWhite` alone rendered washed-out light in testing (legacy color-space
        // quirk converting to `.cgColor`), so this is a deliberate belt-and-suspenders fix,
        // not just cosmetic.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.center()

        let content = NSView(frame: NSRect(origin: .zero, size: panelSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.98).cgColor
        content.layer?.cornerRadius = 16
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        panel.contentView = content

        let title = NSTextField(labelWithString: "Custom Timer")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .white
        title.frame = NSRect(x: 20, y: panelSize.height - 42, width: panelSize.width - 40, height: 22)
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "How many minutes?")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = NSColor(white: 1, alpha: 0.55)
        subtitle.frame = NSRect(x: 20, y: panelSize.height - 64, width: panelSize.width - 40, height: 16)
        content.addSubview(subtitle)

        let field = NSTextField(frame: NSRect(x: 20, y: panelSize.height - 108, width: panelSize.width - 40, height: 34))
        field.placeholderString = "e.g. 20"
        field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        field.alignment = .center
        field.focusRingType = .none
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = .white
        field.wantsLayer = true
        field.layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        field.layer?.cornerRadius = 9
        content.addSubview(field)

        let cancelButton = ClosureButton(title: "Cancel") { NSApp.stopModal(withCode: .abort) }
        style(cancelButton, primary: false)
        cancelButton.frame = NSRect(x: 20, y: 20, width: 104, height: 32)
        cancelButton.keyEquivalent = "\u{1b}"
        content.addSubview(cancelButton)

        let startButton = ClosureButton(title: "Start") { NSApp.stopModal(withCode: .continue) }
        style(startButton, primary: true)
        startButton.frame = NSRect(x: panelSize.width - 20 - 104, y: 20, width: 104, height: 32)
        startButton.keyEquivalent = "\r"
        content.addSubview(startButton)

        // `AppDelegate` runs under `.accessory` activation policy, so without this the
        // panel becomes its own key window but the process never becomes frontmost —
        // keystrokes keep routing to whatever app was active before, and the field
        // silently never receives them.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)

        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)

        guard response == .continue, let minutes = Double(field.stringValue), minutes > 0 else { return nil }
        return minutes
    }

    /// Flat rounded-rect buttons instead of the system bezel — `Start` in the same
    /// accent orange the on-screen row switches to for overtime, tying the dialog back
    /// to the timer it's configuring; `Cancel` a quiet translucent-white twin.
    private static func style(_ button: NSButton, primary: Bool) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = (primary ? NSColor.systemOrange : NSColor(white: 1, alpha: 0.12)).cgColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: primary ? NSColor.black : NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
    }
}

/// A plain borderless `NSPanel` reports `canBecomeKey == false` (confirmed via
/// `-[NSWindow makeKeyWindow]` AppKit console warnings) — the actual cause of both the
/// field silently rejecting keystrokes and clicks passing through to whatever window was
/// behind it. Borderless-but-interactive panels (search fields, HUDs) all need this
/// override; it's not automatic just because the class is `NSPanel` rather than `NSWindow`.
private final class KeyableBorderlessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// `NSButton` only takes a target/selector pair, not a closure — this wraps one in the
/// minimal object needed to be its own target.
private final class ClosureButton: NSButton {
    private var handler: () -> Void = {}

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.handler = handler
        self.target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { handler() }
}
