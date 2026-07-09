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
/// a second, event-driven baseline (`lastKeystrokeAt`), and `scrolling`/`scrollVelocity`
/// a third (`lastScrollAt`/`pendingScrollDelta`), for the same reason.
final class Perception {
    private let clock: Clock

    /// Last polled cursor position — the baseline this poll diffs against to derive
    /// `cursorVelocity`. Deliberately separate from `AgentState.world.cursor`, which
    /// `AppDelegate`'s drag handlers also write between ticks; keeping this poll-only
    /// avoids a drag turning into a velocity spike.
    private var lastCursor: Point?

    /// When the most recent keydown fired, per `clock` — `nil` means "none observed
    /// yet." Converted to `AgentCore.isTypingActive`'s `0`-sentinel contract at the call
    /// boundary in `poll`, so the pure helper's tested "0 means none" behavior is
    /// unaffected. Written asynchronously by the global monitor's handler, between
    /// polls, not by `poll` itself.
    private var lastKeystrokeAt: Double?
    private var keyDownMonitor: Any?

    /// `caretLocation` is synchronous cross-process AX IPC — it blocks on the *focused
    /// app's* responsiveness, not just this process's. Querying it every tick (60Hz) risks
    /// stalling the render loop on a slow or hung target app, unlike the cheap, pure
    /// `isTypingActive` check. So it's only queried while `typing` is true (no caret to
    /// report otherwise) and throttled to `caretPollIntervalMs` between queries, with
    /// `cachedTypingLocation` holding the most recent result in between.
    private static let caretPollIntervalMs: Double = 200
    /// `nil` means "not currently throttled" — due to query it immediately. Distinct
    /// from `lastKeystrokeAt`/`lastScrollAt`'s "not yet observed" `nil`: this one is
    /// reset to `nil` on every not-typing frame (see `pollCaretLocation`), not just at
    /// startup, so a throttle window never survives a typing pause.
    private var lastCaretQueryAt: Double?
    private var cachedTypingLocation: Rect?

    /// Same synchronous cross-process AX IPC cost and throttle as `caretLocation` — see
    /// its doc comment. Unlike the caret, there's always a frontmost app to query (no
    /// `typing`-style gate), so this is throttled purely on time, plus an immediate
    /// re-query on app switch (`lastWindowPid` changing) rather than serving up to
    /// `windowPollIntervalMs` of a stale previous app's frame.
    private static let windowPollIntervalMs: Double = 200
    /// `nil` means "not currently throttled" — same reset-on-no-signal shape as
    /// `lastCaretQueryAt`, mirrored here for the no-frontmost-app case.
    private var lastWindowQueryAt: Double?
    private var cachedFrontmostWindow: WindowInfo?
    private var lastWindowPid: pid_t?

    /// When the most recent scroll-wheel event fired, per `clock` — `nil` means "none
    /// observed yet." Converted to `AgentCore.isScrollActive`'s `0`-sentinel contract at
    /// the call boundary in `poll`, mirroring `lastKeystrokeAt`. Written asynchronously
    /// by the global monitor's handler, between polls, not by `poll` itself.
    private var lastScrollAt: Double?
    /// Scroll delta (points) accumulated since the last `poll` call, summed across
    /// however many scroll-wheel events fired in that window; `poll` converts this to
    /// px/sec and resets it. A *mouse* global monitor, unlike `keyDownMonitor` — needs
    /// no Accessibility/Input-Monitoring grant, just the one this process already has.
    private var pendingScrollDelta = Vector(dx: 0, dy: 0)
    private var scrollMonitor: Any?

    /// Installs a global keydown monitor and prompts for Accessibility once — both the
    /// typing signal and `caretLocation` need that grant. A *global*, not local, monitor:
    /// this is a background accessory with no key window of its own, so it only ever sees
    /// keys the user presses in other apps via the global monitor. Also installs a global
    /// scroll-wheel monitor for the `scrolling`/`scrollVelocity` signals, same rationale.
    init(clock: Clock) {
        self.clock = clock
        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(promptOptions)
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            guard let self else { return }
            self.lastKeystrokeAt = self.clock.now()
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            self.lastScrollAt = self.clock.now()
            self.pendingScrollDelta.dx += Double(event.scrollingDeltaX)
            self.pendingScrollDelta.dy += Double(event.scrollingDeltaY)
        }
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    /// `dt` is this frame's delta (seconds) — macOS has no cursor-velocity API, so velocity
    /// is derived here via `AgentCore.cursorVelocity` rather than read from the OS. The
    /// first poll has no prior frame to diff against; `cursorVelocity` floors that (and any
    /// `dt <= 0`) to zero rather than dividing by zero/negative.
    func poll(layout: ScreenLayout, dt: Double) -> PerceptionSnapshot {
        let cursor = CoordinateSpace.webPoint(fromGlobal: NSEvent.mouseLocation, primaryHeight: layout.primaryHeight)
        // No prior sample on the first poll (`lastCursor == nil`) — fall back to `cursor`
        // itself so `from == to` and the numerator is zero, letting `cursorVelocity` own all
        // zero-velocity logic in one place instead of special-casing "no baseline yet" here too.
        let velocity = AgentCore.cursorVelocity(from: lastCursor ?? cursor, to: cursor, dt: dt)
        lastCursor = cursor
        // Read once, not twice: `frontmostApp` (AgentCore-facing) and `frontmostWindow`'s AX
        // query both derive from the same `NSRunningApplication` snapshot.
        let frontmostRunningApp = NSWorkspace.shared.frontmostApplication
        let frontmostApp = frontmostRunningApp.map {
            AppInfo(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "?")
        }
        let now = clock.now()
        let frontmostWindow = pollFrontmostWindow(app: frontmostRunningApp, now: now)
        // `?? 0` converts this class's "not observed yet" `nil` to
        // `isTypingActive`/`isScrollActive`'s own "not observed yet" `0` sentinel —
        // their tested contract stays untouched, only the boundary crossing it.
        let typing = isTypingActive(
            lastKeystrokeAt: lastKeystrokeAt ?? 0, now: now, timeoutMs: Constants.typingIdleTimeoutMs
        )
        let typingLocation = pollCaretLocation(typing: typing, now: now)
        let scrolling = isScrollActive(
            lastScrollAt: lastScrollAt ?? 0, now: now, timeoutMs: Constants.scrollActiveTimeoutMs
        )
        // Reuses `cursorVelocity`'s tested dt<=0 guard via its Vector-delta overload
        // rather than re-deriving it.
        let scrollVelocity = AgentCore.cursorVelocity(from: pendingScrollDelta, dt: dt)
        pendingScrollDelta = Vector(dx: 0, dy: 0)
        return PerceptionSnapshot(
            screens: layout.screens, cursor: cursor, cursorVelocity: velocity,
            frontmostApp: frontmostApp, frontmostWindow: frontmostWindow,
            typing: typing, typingLocation: typingLocation, scrolling: scrolling, scrollVelocity: scrollVelocity
        )
    }

    /// Gates and throttles the expensive AX caret query — see `caretPollIntervalMs`'s doc
    /// comment. Not typing at all means no caret to report, so the cache is dropped
    /// immediately rather than left stale for the next typing burst.
    private func pollCaretLocation(typing: Bool, now: Double) -> Rect? {
        guard typing else {
            cachedTypingLocation = nil
            lastCaretQueryAt = nil
            return nil
        }
        if Self.isDue(lastCaretQueryAt, now: now, interval: Self.caretPollIntervalMs) {
            cachedTypingLocation = caretLocation()
            lastCaretQueryAt = now
        }
        return cachedTypingLocation
    }

    /// Gates and throttles the AX window-geometry query — see `windowPollIntervalMs`'s doc
    /// comment. No frontmost app at all means no window to report, mirroring
    /// `pollCaretLocation`'s "drop the cache" behavior for the no-signal case.
    private func pollFrontmostWindow(app: NSRunningApplication?, now: Double) -> WindowInfo? {
        guard let app else {
            cachedFrontmostWindow = nil
            lastWindowQueryAt = nil
            lastWindowPid = nil
            return nil
        }
        let pidChanged = app.processIdentifier != lastWindowPid
        if pidChanged || Self.isDue(lastWindowQueryAt, now: now, interval: Self.windowPollIntervalMs) {
            cachedFrontmostWindow = frontmostWindowInfo(app: app)
            lastWindowQueryAt = now
            lastWindowPid = app.processIdentifier
        }
        return cachedFrontmostWindow
    }

    /// Shared throttle check for `pollCaretLocation`/`pollFrontmostWindow`: `nil` means "not
    /// currently throttled" (due immediately), otherwise due once `interval` has elapsed
    /// since `lastAt`.
    private static func isDue(_ lastAt: Double?, now: Double, interval: Double) -> Bool {
        lastAt.map { now - $0 >= interval } ?? true
    }

    /// Best-effort frontmost-window geometry via the Accessibility API: the app's AX
    /// element -> its focused window (falling back to the main window, e.g. a dialog
    /// that isn't itself focused) -> that window's position + size. Every step is
    /// guarded and falls through to `nil` — the expected outcome for apps that don't
    /// implement the AX window attributes, exactly like `caretLocation` degrades for
    /// apps without AX text attributes.
    ///
    /// Unlike `caretLocation`'s single `kAXBoundsForRange` rect, a window has no rect
    /// attribute — position and size are two separate AXValues (`.cgPoint`/`.cgSize`),
    /// read and combined here.
    private func frontmostWindowInfo(app: NSRunningApplication) -> WindowInfo? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var windowRef: CFTypeRef?
        var windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowResult != .success || windowRef == nil {
            windowResult = AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard windowResult == .success, let windowElement = windowRef else { return nil }
        // See `caretLocation`'s doc comment on why `as!`, not `as?`, is the correct cast here.
        let window = windowElement as! AXUIElement

        var origin = CGPoint.zero
        guard axValue(window, kAXPositionAttribute, as: .cgPoint, into: &origin) else { return nil }

        var size = CGSize.zero
        guard axValue(window, kAXSizeAttribute, as: .cgSize, into: &size) else { return nil }

        var titleRef: CFTypeRef?
        let title: String?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleString = titleRef as? String, !titleString.isEmpty {
            title = titleString
        } else {
            title = nil
        }

        let frame = CGRect(origin: origin, size: size)
        return WindowInfo(
            ownerName: app.localizedName ?? "?",
            title: title,
            frame: CoordinateSpace.webRect(fromGlobal: frame)
        )
    }

    /// Reads an AX attribute already known to hold a `.cgPoint`-typed `AXValue` into `out` —
    /// factors out the position/size duplication in `frontmostWindowInfo` above. See
    /// `caretLocation`'s doc comment for why `as!` here is a safe static relabeling, not a
    /// runtime check — the `== .success` guard just before it is the real safety gate.
    ///
    /// Overloaded on `out`'s concrete type (`CGPoint`/`CGSize`), not generic: `AXValueGetValue`
    /// writes through a raw pointer, and Swift can't prove an unconstrained generic parameter
    /// contains no object reference, so a generic version of this would (rightly) warn.
    private func axValue(_ element: AXUIElement, _ attribute: String, as type: AXValueType, into out: inout CGPoint) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref
        else { return false }
        return AXValueGetValue(value as! AXValue, type, &out)
    }

    /// `CGSize` counterpart to the `CGPoint` overload just above — see its doc comment.
    private func axValue(_ element: AXUIElement, _ attribute: String, as type: AXValueType, into out: inout CGSize) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref
        else { return false }
        return AXValueGetValue(value as! AXValue, type, &out)
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
