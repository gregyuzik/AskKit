#if canImport(FoundationModels) && !os(tvOS)

public import Foundation
public import FoundationModels
import Synchronization

/// `AskSession` over a real `LanguageModelSession`.
///
/// One request at a time on the session, which the engine's own
/// serialization keeps true. Plain `Sendable`: on SDK 27 `LanguageModelSession`
/// is `Sendable`, and every stored property here is a `let` of a `Sendable`
/// type.
///
/// Public for a host whose own model router builds its sessions: its
/// `AskModelSeam.makeSession` wraps each one in this and keeps the streaming,
/// the photo prompt, the planner, the usage reading and the feedback
/// attachment `AppleModelSeam` uses.
///
/// Behind the Foundation Models platform gate alone, not the seam's stricter
/// one: it names nothing the watch's SDK marks unavailable, so it builds on
/// watchOS too, where `AppleModelSeam` doesn't.
nonisolated public final class AppleAskSession: AskSession, Sendable {
    private let session: LanguageModelSession
    /// The model's context window, read by the seam when it built this
    /// session — see `contextSize()`.
    private let window: Int?
    /// Builds a tool-free planner on the model this session runs on. Supplied by
    /// the seam, which owns model construction and the entitlement check.
    private let makePlanner: @Sendable (String) -> LanguageModelSession
    /// Hands every raw failure back to the seam that built this session, before
    /// the engine triages it: a spent quota's reset and a rate limit's are on
    /// the SDK's error and nowhere else. Nil for an on-device session.
    private let noteFailure: (@Sendable (any Error) async -> Void)?
    /// The most tokens one answer — a streamed turn or a refine pass — may run
    /// to, or nil for the model's whole window. The on-device session's is
    /// `AskContinuation.onDeviceAnswerCap`; Private Cloud Compute's is nil.
    private let answerCap: Int?
    /// The same for the planner's reply (`AskContinuation.onDevicePlanCap`).
    private let planCap: Int?
    /// The newest response's token counts — see `usage()`.
    private let newestUsage = Mutex<AskUsage?>(nil)

    /// The on-device answer cap `AppleModelSeam` gives its sessions, in
    /// tokens: a guard against a runaway answer in the device's small window,
    /// which the engine's rollover allows for.
    public static let onDeviceAnswerCap = AskContinuation.onDeviceAnswerCap

    /// The on-device planner cap `AppleModelSeam` gives its sessions, in
    /// tokens: a plan is a handful of search arguments.
    public static let onDevicePlanCap = AskContinuation.onDevicePlanCap

    /// A session the engine can run turns on.
    ///
    /// - Parameters:
    ///   - session: the session the turns stream on, built with the tools and
    ///     instructions the seam's `makeSession` was handed.
    ///   - contextSize: the model's context window, read when the session was
    ///     built. Nil leaves the domain's turn count as the only budget.
    ///   - answerCap: the most tokens one answer may run to, or nil for the
    ///     model's whole window. An on-device session takes
    ///     `onDeviceAnswerCap`.
    ///   - planCap: the same for the grounded retry's planner. An on-device
    ///     session takes `onDevicePlanCap`.
    ///   - noteFailure: hears every raw failure before the engine triages it,
    ///     which drops a quota's or a rate limit's reset date
    ///     (`AskTriage.retryAfter(from:)` reads it).
    ///   - makePlanner: a session with no tools, on the same model, with the
    ///     instructions it is handed: the grounded retry plans its search on
    ///     it.
    public init(
        session: LanguageModelSession,
        contextSize: Int?,
        answerCap: Int? = nil,
        planCap: Int? = nil,
        noteFailure: (@Sendable (any Error) async -> Void)? = nil,
        makePlanner: @escaping @Sendable (String) -> LanguageModelSession
    ) {
        self.session = session
        self.window = contextSize
        self.answerCap = answerCap
        self.planCap = planCap
        self.noteFailure = noteFailure
        self.makePlanner = makePlanner
    }

    /// One generation of `AskReply`, with no photos.
    public func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt,
            images: [],
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    /// One generation of `AskReply`, with `images` after the prompt's words:
    /// the shaped stream below, in the full shape.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt,
            images: images,
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt,
            shape: .full
        )
    }

    /// One generation of the reply `shape` names, `AskReply` or
    /// `AskProseReply`, with `images` after the prompt's words, capped at
    /// `answerCap` tokens. The snapshots update `usage()` as they arrive, and
    /// a failure goes to `noteFailure` before the stream throws it. Letting
    /// the stream go cancels the generation. Read inside
    /// `AskGenerationGate.run`, the generation gate moves on only once the
    /// generation has returned, not when the reader lets go.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        switch shape {
        case .full:
            generate(
                AskReply.self, prompt: prompt, images: images, temperature: temperature,
                reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
            ) { reply in
                AskReplySnapshot(
                    answer: reply.answer,
                    questionKind: reply.questionKind,
                    showsEveryMatch: reply.showsEveryMatch,
                    tiles: reply.tiles,
                    followUps: reply.followUps
                )
            }
        case .prose:
            generate(
                AskProseReply.self, prompt: prompt, images: images, temperature: temperature,
                reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
            ) { reply in
                AskReplySnapshot(answer: reply.answer, followUps: reply.followUps)
            }
        }
    }

    /// One streamed generation of `type`, each snapshot of it turned into an
    /// `AskReplySnapshot` by `snapshot`.
    private func generate<Reply: Generable>(
        _ type: Reply.Type,
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        snapshot: @escaping @Sendable (Reply.PartiallyGenerated) -> AskReplySnapshot
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        // The generation gate's holder this stream is read under, if any:
        // read here, in the reader's task, where the holder bound it.
        let producers = AskGenerationProducers.current
        return AsyncThrowingStream { continuation in
            let task = Task { [session, answerCap, self] in
                do {
                    let options = GenerationOptions(temperature: temperature, maximumResponseTokens: answerCap)
                    let context = ContextOptions(
                        includeSchemaInPrompt: includeSchemaInPrompt,
                        reasoningLevel: Self.level(reasoningLevel)
                    )
                    // A question with no photo goes as a plain string, so
                    // what a warm session cached is what arrives. One with a
                    // photo puts the words first, for the same cache
                    // (`AskSession` says so).
                    let stream: LanguageModelSession.ResponseStream<Reply>
                    if images.isEmpty {
                        stream = session.streamResponse(
                            to: prompt,
                            generating: type,
                            options: options,
                            contextOptions: context
                        )
                    } else {
                        stream = session.streamResponse(
                            to: Prompt {
                                prompt
                                for attachment in images {
                                    Attachment(attachment.image).label(attachment.label)
                                }
                            },
                            generating: type,
                            options: options,
                            contextOptions: context
                        )
                    }
                    for try await partial in stream {
                        // Every snapshot, not only the last: on the device each
                        // one already carries the request's whole input and the
                        // output so far, so a stream the deadline abandons still
                        // leaves its size behind.
                        self.noteUsage(partial.usage)
                        continuation.yield(snapshot(partial.content))
                    }
                    continuation.finish()
                } catch {
                    // Before the throw, so the tier is held before the next
                    // read of the tiers can find it servable.
                    await self.noteFailure?(error)
                    continuation.finish(throwing: error)
                }
            }
            // Letting the stream go only cancels this task, and the reader's
            // loop ends at once while `streamResponse` is still unwinding. So
            // the holder waits for the task itself before the generation gate
            // lets the next generation in (`AskGenerationProducers`).
            producers?.adopt(task)
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func level(_ level: AskReasoningLevel?) -> ContextOptions.ReasoningLevel? {
        switch level {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        case nil: nil
        }
    }

    /// The grounded retry's plan: one response of `type` from a new session
    /// with no tools, on this session's model, capped at `planCap` tokens.
    public func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        // A session of its own, with NO tools, so the model's only possible
        // reply is the search arguments. On the tier's own model, since the
        // answer it plans for is the one that model will write.
        let planner = makePlanner(instructions)
        do {
            return try await planner.respond(
                to: prompt, generating: type, options: GenerationOptions(maximumResponseTokens: planCap)
            ).content
        } catch {
            await noteFailure?(error)
            throw error
        }
    }

    /// One response of `type` on this session, with `images` ahead of the
    /// prompt, capped at `answerCap` tokens. Its usage becomes `usage()`'s
    /// reading.
    public func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        let response: LanguageModelSession.Response<Content>
        do {
            response = try await session.respond(
                to: Prompt {
                    for attachment in images {
                        Attachment(attachment.image).label(attachment.label)
                    }
                    prompt
                },
                generating: type,
                options: GenerationOptions(temperature: temperature, maximumResponseTokens: answerCap),
                contextOptions: ContextOptions(reasoningLevel: Self.level(reasoningLevel))
            )
        } catch {
            await noteFailure?(error)
            throw error
        }
        // The refine pass is a response on THIS session, and the newest one:
        // what the next turn's request starts from includes it.
        noteUsage(response.usage)
        return response.content
    }

    /// The tool calls in the session's transcript, across all its turns. One
    /// transcript entry holds every call the model made at once, so this counts
    /// the calls in each entry, not the entries.
    public func toolCallCount() async -> Int {
        session.transcript.reduce(into: 0) { count, entry in
            if case .toolCalls(let calls) = entry { count += calls.count }
        }
    }

    /// The newest response's counts, never the session's.
    ///
    /// **`session.usage` is a running total**: every request's input, added
    /// up, and each request's input is the whole transcript so far, so the
    /// total counts the thread once per turn. Measured on the on-device model,
    /// four short turns read 70, 160, 270 and 400 input tokens while
    /// `tokenCount(for:)` put the transcript at 72, 92, 112 and 132. Set
    /// against the window, the running total would roll a conversation over,
    /// onto a cold cache and a recap, long before the window filled, and each
    /// turn's `[usage]` line would report it as that turn's cost.
    ///
    /// A response's own usage is what the next request starts from: its input
    /// was the transcript, its output is the newest entry. Nil until this
    /// session has answered anything.
    public func usage() async -> AskUsage? {
        newestUsage.withLock { $0 }
    }

    /// Keep a response's counts, unless it has not reported its input yet.
    ///
    /// **The input, not the total.** The SDK counts output as the text
    /// arrives, so a provider that sends the request's size only once it has
    /// finished streams snapshots with an output count and an input of zero
    /// (measured with a scripted provider), and a reading of zero input is an
    /// empty window to the rollover check. Until the input arrives, the last
    /// response's reading stands.
    private func noteUsage(_ usage: LanguageModelSession.Usage) {
        guard usage.input.totalTokenCount > 0 else { return }
        newestUsage.withLock { $0 = Self.askUsage(from: usage) }
    }

    nonisolated static func askUsage(from usage: LanguageModelSession.Usage) -> AskUsage {
        AskUsage(
            inputTokens: usage.input.totalTokenCount,
            cachedTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount,
            reasoningTokens: usage.output.reasoningTokenCount
        )
    }

    /// The window the seam read when it built this session: 8,192 tokens on
    /// device and 32,768 on Private Cloud Compute in the 27 releases, read
    /// rather than hardcoded because both move with the OS.
    public func contextSize() async -> Int? {
        window
    }

    /// An empty prefix warms the model with nothing cached ahead of the
    /// question, rather than caching an empty prompt.
    public func prewarm(promptPrefix: String) async {
        await Self.prewarm(session, promptPrefix: promptPrefix)
    }

    /// The warm itself, off the caller's actor: under
    /// `NonisolatedNonsendingByDefault` `prewarm` runs on the engine's.
    /// `@concurrent` rather than a detached task, so it keeps its caller's
    /// priority and cancellation.
    @concurrent nonisolated private static func prewarm(_ session: LanguageModelSession, promptPrefix: String) async {
        session.prewarm(promptPrefix: promptPrefix.isEmpty ? nil : Prompt(promptPrefix))
    }

    /// `logFeedbackAttachment` records the verdict against this session's
    /// transcript and hands back the attachment a Feedback Assistant report
    /// takes.
    public func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data? {
        let verdict: LanguageModelFeedback.Sentiment = switch sentiment {
        case .positive: .positive
        case .negative: .negative
        }
        return session.logFeedbackAttachment(sentiment: verdict)
    }
}

#endif
