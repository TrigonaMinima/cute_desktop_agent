// Phase 0 — RAW-binary window spike. THROWAWAY code, not shipped.
//
// Proves, with a plain colored square, that a Command-Line-Tools-only build can produce
// an overlay window that:
//   (a) floats over everything including native-fullscreen apps, on all Spaces
//   (b) is click-through by default, with a per-tick hit-test toggle over the square
//   (c) does NOT steal app activation when clicked (frontmost app stays the real one)
//   (d) drives a live per-frame animation via CADisplayLink (fallback: CVDisplayLink)
//
// Run with `swift run --package-path native Spike` and manually verify against a
// fullscreen app. See native/README.md for the checklist. If any check fails, STOP —
// see the plan's Phase 0 gate.

import AppKit
import QuartzCore

// stdout is fully buffered when not attached to a TTY (e.g. piped to a log file for
// this spike's automated checks) — force line buffering so prints show up live.
setvbuf(stdout, nil, _IOLBF, 0)

/// NSPanel subclass that can never become key/main, so clicking it cannot activate
/// this app or steal focus from whatever the user was using — the perception signal
/// (frontmost app) must stay truthful even while the overlay is being interacted with.
final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SquareView: NSView {
    let square = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        square.backgroundColor = NSColor.systemPink.cgColor
        square.frame = CGRect(x: 0, y: 0, width: 78, height: 62)
        square.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(square)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        print("[spike] (c) square clicked — frontmost app is still: \(front) (should NOT be this spike)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: ClickThroughPanel!
    var squareView: SquareView!
    var displayLink: CADisplayLink?
    var hitTestTimer: Timer?
    var watchdogTimer: Timer?
    var hovering = false
    let startTime = CFAbsoluteTimeGetCurrent()
    var frameCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main else { fatalError("no screen") }
        let frame = screen.frame // full frame, not visibleFrame — matches the POC

        panel = ClickThroughPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true // click-through by default
        panel.isReleasedWhenClosed = false

        squareView = SquareView(frame: NSRect(origin: .zero, size: frame.size))
        panel.contentView = squareView
        panel.orderFrontRegardless()

        startFrameClock()
        startHitTestPolling()

        print("[spike] launched. screen frame = \(frame)")
        print("[spike] (a) now switch to fullscreen apps / other Spaces and confirm the pink square stays on top")
        print("[spike] (b) move the cursor over the pink square — it should become clickable there only")
    }

    /// (d) primary choice: NSView.displayLink(target:selector:), macOS 14+.
    private func startFrameClock() {
        let link = squareView.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.frameCount == 0 {
                print("[spike] (d) FAILED — CADisplayLink never fired in 2s. Fall back to CVDisplayLink.")
            } else {
                print("[spike] (d) OK — CADisplayLink fired \(self.frameCount) times in ~2s")
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        frameCount += 1
        let t = CFAbsoluteTimeGetCurrent() - startTime
        CATransaction.begin()
        CATransaction.setDisableActions(true) // avoid implicit-animation smear
        let scale = 1.0 + 0.15 * sin(t * 2.0)
        squareView.square.transform = CATransform3DMakeScale(scale, scale, 1)
        squareView.square.position = CGPoint(
            x: squareView.bounds.midX + 60 * sin(t * 0.5),
            y: squareView.bounds.midY
        )
        CATransaction.commit()
    }

    /// Click-through window receives no mouse-move events except over the pet's rect
    /// (see plan's "critical port difference") — poll the global cursor instead.
    private func startHitTestPolling() {
        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateHitTest()
        }
    }

    private func updateHitTest() {
        let mouseLocation = NSEvent.mouseLocation // global, bottom-left origin
        let squareFrame = squareView.square.presentation()?.frame ?? squareView.square.frame
        guard let panelOrigin = panel?.frame.origin else { return }
        let squareGlobal = CGRect(
            x: panelOrigin.x + squareFrame.origin.x,
            y: panelOrigin.y + squareFrame.origin.y,
            width: squareFrame.width,
            height: squareFrame.height
        )
        let isHovering = squareGlobal.contains(mouseLocation)
        if isHovering != hovering {
            hovering = isHovering
            panel.ignoresMouseEvents = !isHovering
            print("[spike] (b) hover=\(isHovering) — ignoresMouseEvents=\(!isHovering)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
