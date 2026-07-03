import Foundation

/// Injected randomness — every call the JS original made to `Math.random()` becomes a
/// `rng.nextUnit()` call here, so `StateMachine` (Phase 3) can be driven deterministically
/// in tests via `SeededRandom`. Class-constrained so `StateMachine` can hold a `let rng:
/// RandomProvider` reference rather than threading `inout` through every call.
public protocol RandomProvider: AnyObject {
    /// A uniform random Double in [0, 1) — matches `Math.random()`'s range/semantics.
    func nextUnit() -> Double
}

public final class SystemRandom: RandomProvider {
    public init() {}

    public func nextUnit() -> Double {
        Double.random(in: 0..<1)
    }
}

/// Deterministic RNG for tests: same seed -> same sequence, every run, on every
/// machine. A small dependency-free xorshift64* generator — good enough for behavior
/// tests, not for anything security-sensitive.
public final class SeededRandom: RandomProvider {
    private var state: UInt64

    public init(seed: UInt64) {
        // xorshift64* is undefined at state == 0; fold a zero seed to a fixed nonzero one.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public func nextUnit() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let scrambled = state &* 0x2545_F491_4F6C_DD1D
        // Top 53 bits -> a Double uniformly distributed in [0, 1).
        return Double(scrambled >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
