import Foundation

/// Injected time source, in milliseconds — matches the JS original's
/// `performance.now()` units, so dwell tables (Constants.modeDwellMsRange, etc.) port
/// over unchanged. Class-constrained for the same reason as RandomProvider.
public protocol Clock: AnyObject {
    func now() -> Double
}

public final class SystemClock: Clock {
    private let start = DispatchTime.now()

    public init() {}

    public func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}

/// Deterministic clock for tests: time only moves when `advance`/`set` is called, so
/// StateMachineTransitionTests (Phase 3) can assert exact behavior at exact instants.
public final class ManualClock: Clock {
    public private(set) var current: Double

    public init(start: Double = 0) {
        self.current = start
    }

    public func now() -> Double {
        current
    }

    public func advance(by milliseconds: Double) {
        current += milliseconds
    }

    public func set(_ milliseconds: Double) {
        current = milliseconds
    }
}
