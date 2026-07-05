import AppKit
import ApplicationServices
import AgentCore

/// Per-tick poll of OS state the click-through overlay can't get from ordinary mouse-move
/// events — a `.ignoresMouseEvents` window receives no move events except while the hit
/// test has it enabled over the avatar, so hover and proximity are driven by polling
/// `NSEvent.mouseLocation` once a frame rather than by `NSResponder` mouse-moved events.
///
/// A class, not an enum namespace, because deriving `cursorVelocity` needs a tick-to-tick
/// baseline — mirrors `FrameClock`, which owns `lastTimestamp` the same way rather than
/// making its caller thread a "previous" value through each call. `typing` detection adds
/// a second, event-driven baseline (`lastKeystrokeAt`) for the same reason.
final class Perception {
    private let clock: Clock

    /// Last polled cursor position — the baseline this poll diffs against to derive
    /// `cursorVelocity`. Deliberately separate from `AgentState.world.cursor`, which
    /// `AppDelegate`'s drag handlers also write between ticks; keeping this poll-only
    /// avoids a drag turning into a velocity spike.
    private var lastCursor: Point?

    /// When the most recent keydown fired, per `clock` — 0 means "none observed yet"
    /// (see `AgentCore.isTypingActive`'s doc comment). Written asynchronously by the
    /// global monitor's handler, between polls, not by `poll` itself.
    private var lastKeystrokeAt: Double = 0
    private var keyDownMonitor: Any?

    /// `caretLocation` is synchronous cross-process AX IPC — it blocks on the *focused
    /// app's* responsiveness, not just this process's. Querying it every tick (60Hz) risks
    /// stalling the render loop on a slow or hung target app, unlike the cheap, pure
    /// `isTypingActive` check. So it's only queried while `typing` is true (no caret to
    /// report otherwise) and throttled to `caretPollIntervalMs` between queries, with
    /// `cachedTypingLocation` holding the most recent result in between.
    private static let caretPollIntervalMs: Double = 200
    private var lastCaretQueryAt: Double = -.infinity
    private var cachedTypingLocation: Rect?

    /// Installs a global keydown monitor and prompts for Accessibility once — both the
    /// typing signal and `caretLocation` need that grant. A *global*, not local, monitor:
    /// this is a background accessory with no key window of its own, so it only ever sees
    /// keys the user presses in other apps via the global monitor.
    init(clock: Clock) {
        self.clock = clock
        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(promptOptions)
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.lastKeystrokeAt = self?.clock.now() ?? 0
        }
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    /// `dt` is this frame's delta (seconds) — macOS has no cursor-velocity API, so velocity
    /// is derived here via `AgentCore.cursorVelocity` rather than read from the OS. The
    /// first poll has no prior frame to diff against; `cursorVelocity` floors that (and any
    /// `dt <= 0`) to zero rather than dividing by zero/negative.
    func poll(
        screenFrame: NSRect, dt: Double
    ) -> (cursor: Point, cursorVelocity: Vector, frontmostApp: AppInfo?, typing: Bool, typingLocation: Rect?) {
        let cursor = CoordinateSpace.webPoint(fromGlobal: NSEvent.mouseLocation, screenFrame: screenFrame)
        // No prior sample on the first poll (`lastCursor == nil`) — fall back to `cursor`
        // itself so `from == to` and the numerator is zero, letting `cursorVelocity` own all
        // zero-velocity logic in one place instead of special-casing "no baseline yet" here too.
        let velocity = AgentCore.cursorVelocity(from: lastCursor ?? cursor, to: cursor, dt: dt)
        lastCursor = cursor
        let frontmostApp = NSWorkspace.shared.frontmostApplication.map {
            AppInfo(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "?")
        }
        let now = clock.now()
        let typing = isTypingActive(
            lastKeystrokeAt: lastKeystrokeAt, now: now, timeoutMs: Constants.typingIdleTimeoutMs
        )
        let typingLocation = pollCaretLocation(typing: typing, now: now)
        return (cursor, velocity, frontmostApp, typing, typingLocation)
    }

    /// Gates and throttles the expensive AX caret query — see `caretPollIntervalMs`'s doc
    /// comment. Not typing at all means no caret to report, so the cache is dropped
    /// immediately rather than left stale for the next typing burst.
    private func pollCaretLocation(typing: Bool, now: Double) -> Rect? {
        guard typing else {
            cachedTypingLocation = nil
            lastCaretQueryAt = -.infinity
            return nil
        }
        if now - lastCaretQueryAt >= Self.caretPollIntervalMs {
            cachedTypingLocation = caretLocation()
            lastCaretQueryAt = now
        }
        return cachedTypingLocation
    }

    /// Best-effort caret bounds via the Accessibility API: system-wide focused element ->
    /// its selected text range -> that range's screen bounds. Every step is guarded and
    /// falls through to `nil` — the expected, common outcome for apps (many Electron/web
    /// views included) that don't implement the AX text attributes, exactly like
    /// `AgentWorld.windowBelow` is expected to stay unpopulated absent Screen Recording. No
    /// `screenFrame` param, unlike `webPoint` — see `CoordinateSpace.webRect`'s doc comment
    /// on why AX geometry needs no screen-relative offset here.
    private func caretLocation() -> Rect? {
        let systemWide = AXUIElementCreateSystemWide()

        // `as!`, not `as?`: the Swift compiler rejects `as?` here outright ("conditional
        // downcast will always succeed") because AXUIElement/AXValue are toll-free-bridged
        // CF types with no CFTypeID check wired into the bridge — so neither cast form
        // performs a real runtime check; this is purely a static relabeling. The actual
        // safety gate is the `== .success` check just before each one: Apple's AX docs
        // guarantee the concrete type these attributes hand back on success, and any
        // non-`.success` result already returns `nil` before the cast is reached.
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef
        else { return nil }
        let element = focusedElement as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef
        else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef
        ) == .success, let boundsValue = boundsRef else { return nil }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else { return nil }
        guard bounds.width > 0 || bounds.height > 0 else { return nil }

        return CoordinateSpace.webRect(fromGlobal: bounds)
    }
}
