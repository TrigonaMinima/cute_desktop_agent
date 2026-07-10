import AppKit

/// The shell half of the sleep tier (decision log D11): while the brain reports
/// `.sleeping`, `AppDelegate` stops the `FrameClock` outright — no display link, no
/// perception polling, no rendering — and this controller keeps just enough plumbing
/// alive to notice the user coming back. Any wake signal fires `onWake` (which restarts
/// the clock); a stale signal that carried no real input is harmless, because the next
/// cognition slice still reads `.sleeping` and the shell simply goes dormant again.
final class PowerController {
    private let onWake: () -> Void
    private var eventMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
    }

    /// Installs the wake listeners. Two families, because "the user is back" arrives
    /// two ways: raw input (a global event monitor — sleep must not swallow the first
    /// mouse twitch), and system transitions that imply presence before any input
    /// lands (machine wake, displays wake, fast-user-switch in, screen unlock).
    func beginSleep() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] _ in
            self?.onWake()
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceWakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        workspaceObservers = workspaceWakeNames.map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.onWake()
            }
        }
        // Screen unlock only surfaces on the distributed center, and only by string name.
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.onWake()
        }
    }

    /// Removes everything `beginSleep` installed. Block observers must be removed via
    /// the center that created them, hence the two removal paths.
    func endSleep() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
    }
}
