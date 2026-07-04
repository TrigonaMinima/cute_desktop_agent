import AppKit
import QuartzCore
import AgentCore

/// Wraps `CADisplayLink` (via `NSView.displayLink(target:selector:)`, the recipe proven
/// in the Phase 0 spike) and clamps `dt` to `[0, 0.1]` seconds, mirroring the POC's
/// `tick()` — guards against a huge dt after the app is backgrounded or the display
/// sleeps, which would otherwise let the state machine (movement, timers) leap forward
/// in one step.
///
/// Deliberately does NOT derive `now` from `link.timestamp` (`CACurrentMediaTime`,
/// an arbitrary absolute time base in seconds) — every `Constants`/`AgentMemory` timer
/// assumes milliseconds since app launch (`performance.now()` in the JS original), so
/// `now` is read once per frame from the same injected `Clock` the `StateMachine` uses.
/// `dt`, by contrast, only needs to be a consistent seconds-denominated delta, which
/// `link.timestamp` deltas give directly.
public final class FrameClock {
    public typealias Tick = (_ now: Double, _ dt: Double) -> Void

    private weak var hostView: NSView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let clock: Clock
    private let onTick: Tick

    public init(hostView: NSView, clock: Clock, onTick: @escaping Tick) {
        self.hostView = hostView
        self.clock = clock
        self.onTick = onTick
    }

    public func start() {
        guard let hostView else { return }
        let link = hostView.displayLink(target: self, selector: #selector(handleTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func handleTick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let rawDt = lastTimestamp.map { timestamp - $0 } ?? 0
        lastTimestamp = timestamp
        let dt = min(max(rawDt, 0), 0.1)
        onTick(clock.now(), dt)
    }
}
