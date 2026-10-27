#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels

/// The process's model facts, behind one protocol: which tiers can serve and
/// why not, building sessions, the cooldown after a transport failure, the
/// quota, the generation gate, and the mirror the screen reads.
///
/// **One per process, not one per Ask.** A host's other model features, such
/// as a summary, a classifier or a photo lookup, share these facts with Ask:
/// on the on-device model they wait at the same generation gate, and on
/// Private Cloud Compute they sit out the same cooldown and quota hold.
/// `AppleModelSeam` implements this on Foundation Models. A host that already
/// routes its own model calls bridges its router to this protocol, wrapping
/// each session in `AppleAskSession`, rather than running `AppleModelSeam`
/// beside it: two seams mean two cooldowns on one Private Cloud Compute, and
/// two generation gates on one on-device model.
nonisolated public protocol AskModelSeam: Sendable {
    /// Every tier's state, most preferred first, from one read, so the tier a
    /// turn runs on, the one it would hand down to and the reason the reader is
    /// told can't disagree.
    func tierStates() async -> [AskTierState]

    /// A session on `tier` with `tools` registered and `instructions` set, or
    /// nil when the tier can't serve. Build it off the main actor: the first
    /// availability read can load a manifest. An error it throws is triaged
    /// like a generation's.
    func makeSession(
        tier: AskTier,
        tools: [any Tool],
        instructions: String
    ) async throws -> AskSessionBox?

    /// A network or service failure: sit the tier out for a while and let the
    /// one below answer. The mirror learns of it now, and again when the
    /// cooldown lifts, so the tier caption comes and goes with it.
    func noteTransportFailure(on tier: AskTier) async

    /// Run `body` at the generation gate when `onDevice` is true, so on-device
    /// generations run one at a time. Private Cloud Compute passes straight
    /// through, since it contends for none of the on-device runtime.
    ///
    /// `body` runs on its caller's actor, as `nonisolated(nonsending)` says.
    /// That is spelled out rather than left to `NonisolatedNonsendingByDefault`,
    /// which AskKit builds with and a host may not: a conformance copied from
    /// this line conforms under either posture. Under the feature, a plain
    /// `@Sendable () async throws -> T` is the same type.
    func withGeneration<T: Sendable>(
        onDevice: Bool,
        _ body: nonisolated(nonsending) @Sendable () async throws -> T
    ) async throws -> T

    /// Read every tier's state again and publish it to `status`.
    func refreshStatus() async

    /// The mirror: the main-actor copy of this seam's state that the screen
    /// reads.
    var status: AskModelStatus { get }

    /// Open Apple's limit-increase route, when there is one.
    ///
    /// Does nothing by default. A seam with no route to offer never sets the
    /// mirror's `hasLimitIncreaseSuggestion`, so nothing offers the route to
    /// the reader.
    func showLimitIncrease() async

    /// The English name of the language this tier should answer in, or nil for
    /// English. Nil too when the tier can't write the app's language, so the
    /// answer degrades to English rather than spending a request that bounces
    /// `unsupportedLanguageOrLocale`.
    ///
    /// It reaches the model through
    /// `AskDomain.instructions(tier:isConversation:answerLanguage:)`, which is
    /// the only place an app can phrase it.
    func answerLanguage(for tier: AskTier) async -> String?
}

nonisolated extension AskModelSeam {
    /// Nil, so the instructions name no language.
    public func answerLanguage(for tier: AskTier) async -> String? { nil }

    /// Does nothing.
    public func showLimitIncrease() async {}
}

#endif
