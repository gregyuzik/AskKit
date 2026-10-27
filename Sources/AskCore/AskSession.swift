#if canImport(FoundationModels) && !os(tvOS)

import CoreGraphics
import Foundation
import FoundationModels

/// What a session's newest response cost, as the tier reports it: its input
/// (the whole transcript it was sent, and how much of that was cached) and its
/// output. Never the session's running total: `AskSession.usage()` says why.
nonisolated public struct AskUsage: Sendable, Equatable {
    /// The tokens the response was sent: the whole transcript so far.
    public var inputTokens: Int?
    /// How many of the input tokens the tier had cached.
    public var cachedTokens: Int?
    /// The tokens the response wrote.
    public var outputTokens: Int?
    /// How many of the output tokens went to reasoning.
    public var reasoningTokens: Int?

    /// A reading, with nil for each count the tier doesn't report.
    public init(
        inputTokens: Int? = nil,
        cachedTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedTokens = cachedTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

/// A model session, as the engine needs it.
///
/// **This exists so the engine never names `LanguageModelSession`.** Everything
/// the turn loop does (hold prose back until the policy keeps it, count tool
/// calls, race a deadline, hand down on an outage, roll over on overflow) is
/// logic that must be tested without a model, and a `swift test` runner can't
/// reach Private Cloud Compute at all. The seam builds one of these; the tests
/// build one that emits scripted snapshots.
///
/// One request at a time, per session: `LanguageModelSession` throws
/// `concurrentRequests` otherwise, and the engine's own serialization is what
/// keeps that true.
nonisolated public protocol AskSession: Sendable {
    /// Stream one generation of `AskReply`.
    ///
    /// Snapshots are cumulative, not deltas: replace state, never append. The
    /// same holds for the two streams below.
    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error>

    /// The same generation with labelled photos in the prompt: a question the
    /// reader asked with a picture.
    ///
    /// **The words go first and the pictures after them.** The words open with
    /// the domain's byte-stable prefix, which is what `prewarm(promptPrefix:)`
    /// cached, and a picture ahead of it would throw that cache away.
    ///
    /// Defaulted, so a session built outside AskKit needs no change, and the
    /// default refuses a photo rather than dropping it. With no images it is
    /// the stream above; with any, it fails with `AskError.photosNotSupported`,
    /// because a session that can't see a picture must not answer as though it
    /// had.
    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error>

    /// The same generation in the reply shape the domain asks for
    /// (`AskDomain.replyShape`): `AskReply` for `.full`, `AskProseReply` for
    /// `.prose`. The engine streams every turn through this one.
    ///
    /// Defaulted, so a session built outside AskKit needs no change, and the
    /// default streams the full reply whatever the shape: it is the stream
    /// above, with the photos as that one takes them. Under `.prose` that is
    /// harmless, since `AskReply` holds both of `AskProseReply`'s fields and
    /// the engine reads nothing else of a prose turn: the answer and its
    /// follow-ups are the same, and only the window the other fields cost is
    /// spent anyway.
    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error>

    /// One structured response with no tools offered: the grounded retry's
    /// planner step, which asks for the domain's search arguments directly,
    /// because a tool is an offer and a response schema is the shape of the
    /// reply.
    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments

    /// How many tool calls this session's transcript holds, across all its
    /// turns. The engine reads it before and after a generation, so a turn
    /// whose tool never reported to the collector still counts as having
    /// called one, and is grounded.
    func toolCallCount() async -> Int

    /// The newest response's token counts, when the tier reports them, and nil
    /// before the session has answered anything.
    ///
    /// **The newest response's, never the session's total.** A request's
    /// input is the whole transcript so far, so a running total counts the
    /// thread once per turn and reads far past what the window holds.
    /// `AskEngine` sets this against `contextSize()` to decide a rollover, and
    /// logs it as the turn's `[usage]` line.
    ///
    /// Nil by default. A session that reports no usage never rolls over early,
    /// so its conversation runs to the domain's `maxTurns(for:)`, or to an
    /// overflow, which rolls it over then.
    func usage() async -> AskUsage?

    /// The model's context window, so budgets are read at runtime rather than
    /// hardcoded: 8,192 tokens on device and 32,768 on Private Cloud Compute in
    /// the 27 releases, and both move with the OS.
    ///
    /// Nil by default, which has the same effect as no usage: nothing to set
    /// the usage against, so the turn count is the budget.
    func contextSize() async -> Int?

    /// One structured response with labelled images attached, **on this
    /// session**: a second pass that can see what the turn already said.
    ///
    /// It has to be the same session, not a fresh one. A pass that asks the
    /// model to look at pictures of the rows it named, and revise its
    /// recommendation, needs the transcript in which it named them. A new
    /// session has named nothing and read nothing, so its revision would be
    /// incoherent, and it would be an answer with no retrieval behind it,
    /// which a domain that retrieves never shows (house rule 2).
    ///
    /// Not part of `stream`: this pass is short, its result is small, and
    /// nothing on screen animates on it, since the prose it may replace has
    /// already landed.
    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content

    /// Warm the session against a byte-stable prefix. An empty prefix warms
    /// the model with nothing cached ahead of the question.
    ///
    /// Does nothing by default: the session's first request then pays the
    /// cold start, and nothing else changes.
    func prewarm(promptPrefix: String) async

    /// The attachment a model-quality report carries (this session's
    /// transcript, with the reader's verdict), or nil where there is none to
    /// give. Defaulted, so a session built outside AskKit needs no change.
    func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data?
}

nonisolated extension AskSession {
    /// Nil: no attachment.
    public func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data? { nil }

    /// Nothing reported, so no early rollover.
    public func usage() async -> AskUsage? { nil }

    /// No window known, so the turn count is the budget.
    public func contextSize() async -> Int? { nil }

    /// Nothing warmed.
    public func prewarm(promptPrefix: String) async {}

    /// The words alone when there are no photos, and a refusal when there are.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        guard images.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: AskError.photosNotSupported) }
        }
        return stream(
            prompt: prompt,
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    /// The full reply whatever the shape: the stream with photos, `shape`
    /// left unread.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt,
            images: images,
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt
        )
    }
}

/// One labelled image on its way to a model.
///
/// The label is what the model is told the picture shows, such as a row's
/// title, so it can name it back.
///
/// Plain `Sendable`, checked: `CGImage` is `Sendable` on SDK 27, and
/// `@unchecked` on a public value type would let through any stored property
/// added later that isn't.
nonisolated public struct AskImageAttachment: Sendable {
    /// What the model is told the picture shows.
    public let label: String
    /// The picture the model is sent, under `label`.
    public let image: CGImage

    /// A picture, and what the model is told it shows.
    public init(label: String, image: CGImage) {
        self.label = label
        self.image = image
    }
}

/// How much the tier should reason before answering:
/// `ContextOptions.ReasoningLevel`'s levels, in a type of AskKit's own so a
/// test's session needs no SDK type.
nonisolated public enum AskReasoningLevel: String, Sendable, Equatable {
    /// Brief reasoning. The engine asks for it on Private Cloud Compute, and
    /// for no level on device.
    case light
    /// More reasoning than `light`.
    case moderate
    /// The most reasoning the tier offers.
    case deep
}

/// A session and the tier it's bound to, as `AskModelSeam.makeSession`
/// returns it.
nonisolated public struct AskSessionBox: Sendable {
    /// The session the engine runs turns on.
    public let session: any AskSession
    /// The tier the session is bound to. A session can't move between tiers,
    /// which is why an outage drops the conversation rather than moving it.
    ///
    /// The engine runs a turn on this tier, whatever tier it asked the seam
    /// for: a router that answers a request for Private Cloud Compute with an
    /// on-device session says so here, and that generation goes through the
    /// generation gate and the caption names the on-device model.
    public let tier: AskTier

    /// A box for `session`, bound to `tier`.
    public init(session: any AskSession, tier: AskTier) {
        self.session = session
        self.tier = tier
    }
}

#endif
