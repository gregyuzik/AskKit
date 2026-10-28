#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels

/// A session whose generations wait their turn at the seam's generation gate.
///
/// What `AskEngine` hands a domain's `refine`: the session the answer was
/// written on, so the pass can ask about what it just said. A pass that asks
/// the model again is a second generation inside the turn, so it goes through
/// the generation gate: on device it must not land beside a host's other
/// generations on the same runtime, which is what the generation gate is for.
/// Only the calls that generate take it. A pass that reads a count or reorders
/// what it has holds nothing, and keeps no other generation waiting on it.
nonisolated struct AskGatedSession: AskSession {
    /// The session underneath: the one the turn streamed on.
    let base: any AskSession
    let seam: any AskModelSeam
    let onDevice: Bool
    /// Called as each generation is asked for, before it waits at the
    /// generation gate.
    let onGeneration: @Sendable () -> Void

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        let base = self.base
        return gated {
            base.stream(
                prompt: prompt,
                temperature: temperature,
                reasoningLevel: reasoningLevel,
                includeSchemaInPrompt: includeSchemaInPrompt
            )
        }
    }

    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        let base = self.base
        return gated {
            base.stream(
                prompt: prompt,
                images: images,
                temperature: temperature,
                reasoningLevel: reasoningLevel,
                includeSchemaInPrompt: includeSchemaInPrompt
            )
        }
    }

    /// Passed on with its shape: the default would stream the full reply
    /// whatever a pass asked for.
    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        let base = self.base
        return gated {
            base.stream(
                prompt: prompt,
                images: images,
                temperature: temperature,
                reasoningLevel: reasoningLevel,
                includeSchemaInPrompt: includeSchemaInPrompt,
                shape: shape
            )
        }
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        // A pass the turn has already given up on starts nothing: a generation
        // nobody will read would still hold the generation gate.
        try Task.checkCancellation()
        onGeneration()
        let base = self.base
        return try await seam.withGeneration(onDevice: onDevice) {
            try await base.plan(type, instructions: instructions, prompt: prompt)
        }
    }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        try Task.checkCancellation()
        onGeneration()
        let base = self.base
        return try await seam.withGeneration(onDevice: onDevice) {
            try await base.respond(
                type, images: images, prompt: prompt, temperature: temperature, reasoningLevel: reasoningLevel
            )
        }
    }

    func toolCallCount() async -> Int { await base.toolCallCount() }

    func usage() async -> AskUsage? { await base.usage() }

    func contextSize() async -> Int? { await base.contextSize() }

    func prewarm(promptPrefix: String) async { await base.prewarm(promptPrefix: promptPrefix) }

    func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data? {
        await base.feedbackAttachment(sentiment: sentiment)
    }

    /// A generation's snapshots, begun once the generation gate lets it
    /// through, and ended before it lets the next one in. A reader that
    /// lets the stream go ends the generation with it, and the generation
    /// gate waits for the generation, not only the reader: an
    /// `AppleAskSession` hands the task running `streamResponse` to the
    /// holder (`AskGenerationProducers`). A host's own session that streams
    /// from a task it keeps to itself is waited for only until its stream
    /// ends.
    private func gated(
        _ generation: @escaping @Sendable () -> AsyncThrowingStream<AskReplySnapshot, any Error>
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        guard !Task.isCancelled else {
            return AsyncThrowingStream { $0.finish(throwing: CancellationError()) }
        }
        onGeneration()
        let (snapshots, continuation) = AsyncThrowingStream<AskReplySnapshot, any Error>.makeStream()
        let seam = self.seam
        let onDevice = self.onDevice
        let producer = Task {
            do {
                try Task.checkCancellation()
                try await seam.withGeneration(onDevice: onDevice) {
                    for try await snapshot in generation() { continuation.yield(snapshot) }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in producer.cancel() }
        return snapshots
    }
}

#endif
