/// Which model served a turn.
///
/// Behind no platform gate, on purpose: the types that carry it, such as
/// `AskThreadEntry`, `AskTierState` and `AskTurnStats`, are behind none
/// either, and a host's shared code names them on tvOS and watchOS, where
/// Foundation Models is absent or has no on-device model. Everything that
/// names `LanguageModelSession` lives behind
/// `#if canImport(FoundationModels) && !os(tvOS)`.
///
/// The raw values are spelled out because they are written into
/// `ask-thread.json`: renaming a case must not silently change what is on disk.
///
/// `nonisolated`, like every value type in AskCore. Without it, the package's
/// main-actor default isolation would reach `readsPhotos`, and neither the
/// engine, which reads it on its own actor, nor a host's code off the main
/// actor could read it. Its `Codable` conformance would stay usable off the
/// main actor either way, because a raw-value enum takes it from the
/// standard library. A synthesized one, such as `AskError`'s, would not
/// (measured on Swift 6.4).
nonisolated public enum AskTier: String, Codable, Sendable, CaseIterable {
    /// Apple's Private Cloud Compute. Preferred whenever it can serve.
    case privateCloud = "privateCloud"
    /// The on-device system model. Used only when Private Cloud Compute can't
    /// serve at the start of a turn, or for the rest of a turn handed down
    /// from it.
    case onDevice = "onDevice"

    /// Whether a photo attached to a question goes to this tier's model.
    ///
    /// Private Cloud Compute only.
    ///
    /// The engine sends a photo by this and the thread says what came of one
    /// by it, so the two can't disagree about whether an answer saw the
    /// picture.
    public var readsPhotos: Bool { self == .privateCloud }
}
