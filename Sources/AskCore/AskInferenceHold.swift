import Foundation
import Synchronization

/// A host's switch that keeps this process from starting any model call:
/// no session built, no prewarm, no generation, on either tier.
///
/// **For a run that must not depend on a model**, such as a store-screenshot
/// capture: on a simulator the on-device model can take minutes, half-draw an
/// answer or refuse a language outright, and a frame shot then is a frame of
/// that. A host that shows fixed content in such a run turns the hold on, and
/// AskKit stops reaching for a model while it stays on. AskKit has no idea
/// why: the host decides (Klosyt and Kabynyt hold it while a launch carries a
/// seeding flag of their own).
///
/// While it is on:
///
/// - `AppleModelSeam` reads the on-device tier as available and speaking the
///   app's language, and Private Cloud Compute as `.notEntitled`, without
///   reading either model's availability, its languages or its quota, so the
///   screen shows what a reader with a working model sees rather than "Apple
///   Intelligence is off" or "language not supported".
/// - `AppleModelSeam.makeSession` builds nothing, so the engine's `prewarm`
///   warms nothing and a question asked anyway fails as a turn whose tier
///   could not serve.
/// - `AppleModelSeam.withGeneration` and `AskGenerationGate.run` throw
///   `HeldError` without running their body, on either tier, and say so in
///   the log: a host's own generations stop at the same gate as Ask's.
///
/// Off by default, and asked on every read, so it can be a switch. Behind no
/// platform gate, like `AskDevelopmentPark`: a tvOS or watchOS host's shared
/// code can set it beside the other platforms'.
nonisolated public enum AskInferenceHold {
    /// What a held generation throws: `AskGenerationGate.run` and
    /// `AppleModelSeam.withGeneration` while the hold is on.
    nonisolated public struct HeldError: Error, Equatable, Sendable {
        public init() {}
    }

    /// Whether the host holds inference right now.
    public static var isHeld: Bool {
        held.withLock { $0 }()
    }

    /// Let the host's own flag hold inference. The closure is asked on every
    /// read of `isHeld`, so it can be a switch; a repeat call replaces it.
    public static func setHeld(_ isHeld: @escaping @Sendable () -> Bool) {
        held.withLock { $0 = isHeld }
    }

    private static let held = Mutex<@Sendable () -> Bool>({ false })
}
