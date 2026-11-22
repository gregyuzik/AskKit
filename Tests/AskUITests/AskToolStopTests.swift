#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import AskUI

/// A tool that stops itself once the turn has drawn prose, through a real
/// `AskEngine` into the store: the turn ends as a stop, its prose kept as a
/// truncated answer (#101). A scripted engine can't pin this, since what it
/// throws is what the test wrote; only the engine says how a tool's own
/// cancellation reaches the store.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskToolStopTests {
    @Test func aToolThatCancelsItselfAfterTheFirstWordsLeavesThemAsATruncatedAnswer() async throws {
        let engine = AskEngine(domain: UIDomain(), seam: OneTierSeam(status: AskModelStatus()))
        let store = makeStore(asker: engine)
        store.ask("Which are on vinyl?")
        await settle(store)
        let turn = try #require(store.turns.last)
        #expect(turn.failure == nil)
        #expect(turn.answer?.isTruncated == true)
        #expect(turn.answer?.text == "Partly")
        // Not the reader's stop: the note under the prose says it was cut
        // short, not that the reader stopped it.
        #expect(!turn.stopped)
    }
}

/// Private Cloud Compute alone, serving, with sessions that call a tool,
/// draw "Partly" and then fail as the tool stopping itself.
nonisolated private final class OneTierSeam: AskModelSeam {
    let status: AskModelStatus

    init(status: AskModelStatus) {
        self.status = status
    }

    func tierStates() async -> [AskTierState] {
        [AskTierState(tier: .privateCloud, speaksLanguage: true)]
    }

    func makeSession(tier: AskTier, tools: [any Tool], instructions: String) async throws -> AskSessionBox? {
        AskSessionBox(session: ToolStoppedSession(), tier: tier)
    }

    func noteTransportFailure(on tier: AskTier) async {}

    func withGeneration<T: Sendable>(
        onDevice: Bool,
        _ body: nonisolated(nonsending) @Sendable () async throws -> T
    ) async throws -> T {
        try await body()
    }

    func refreshStatus() async {}
}

/// A session whose generation calls a tool, as the transcript counts it,
/// writes its first words, and fails as `LanguageModelSession` does for a
/// tool that threw `CancellationError`.
nonisolated private final class ToolStoppedSession: AskSession {
    private let calls = Mutex(0)

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        calls.withLock { $0 += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield(AskReplySnapshot(
                answer: "Partly", questionKind: nil, showsEveryMatch: nil, tiles: nil, followUps: nil
            ))
            continuation.finish(throwing: LanguageModelSession.ToolCallError(
                tool: ShelfTool(), underlyingError: CancellationError()
            ))
        }
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type, instructions: String, prompt: String
    ) async throws -> Arguments {
        throw AskError.couldNotAnswer
    }

    func toolCallCount() async -> Int { calls.withLock { $0 } }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        throw AskError.couldNotAnswer
    }
}

/// The smallest tool a `ToolCallError` can name.
nonisolated private struct ShelfTool: Tool {
    let name = "shelf"
    let description = "Reads the shelf."

    @concurrent func call(arguments: UISearchArguments) async throws -> String { "" }
}

#endif
