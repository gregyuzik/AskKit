#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels
import Testing

/// The prose reply shape, as a host without the posture reaches it: the
/// shape and the prose reply, built and read off any actor, a domain naming
/// either shape, and a turn of a prose domain through the engine, on a session
/// written before shapes that streams the full reply whatever it is asked.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureProseTests {
    /// The shapes, compared and named off any actor, and the domain default.
    @Test func theShapesAreUsableWithoutThePosture() {
        let shapes: [AskReplyShape] = [.full, .prose]
        #expect(shapes.map(\.rawValue) == ["full", "prose"])
        #expect(AskReplyShape(rawValue: "prose") == .prose)
        #expect(ShapeUnnamedDomain().replyShape == .full)
        #expect(ProseDomain().replyShape == .prose)
    }

    /// The prose reply, as a host's own session builds it from generated
    /// content, and its schema, read off any actor.
    @Test func aProseReplyIsBuiltFromGeneratedContentWithoutThePosture() throws {
        _ = AskProseReply.generationSchema
        let reply = try AskProseReply(GeneratedContent(properties: [
            "answer": "It is 14:05 in Lisbon.", "followUps": ["And in Tokyo?", "What day is it?"]
        ]))
        #expect(reply.answer == "It is 14:05 in Lisbon.")
        #expect(reply.followUps == ["And in Tokyo?", "What day is it?"])
    }

    /// The shaped stream's default, asked off any actor of a session that
    /// writes only the words-only stream: that stream, for either shape.
    @Test func theShapedStreamsDefaultIsAskedWithoutThePosture() async throws {
        let session: any AskSession = FullReplySession()
        var answers: [String?] = []
        for try await snapshot in session.stream(
            prompt: "q", images: [], temperature: 0.4, reasoningLevel: nil, includeSchemaInPrompt: true, shape: .prose
        ) {
            answers.append(snapshot.answer)
        }
        #expect(answers == [FullReplySession.answer])
    }

    /// A prose domain's turn, from a session that streams the full reply with
    /// a kind and a tile: the answer keeps its words and its follow-ups, says
    /// `other`, and shows nothing.
    @Test func aProseDomainsTurnShowsNoTiles() async throws {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: ProseDomain(), seam: ProseSeam(status: status), log: ProseQuietSink())
        var events: [AskTurnEvent<AskNoRow>] = []
        for try await event in engine.ask("What time is it in Lisbon?") {
            events.append(event)
        }
        let answer = try #require(events.lazy.compactMap { if case .answer(let answer) = $0 { answer } else { nil } }.first)
        #expect(answer.text == FullReplySession.answer)
        #expect(answer.tiles.isEmpty)
        #expect(answer.questionKind == AskQuestionKind.other)
        #expect(answer.followUps == FullReplySession.followUps)
        #expect(events.contains(.partial(FullReplySession.answer)))
    }
}

/// A domain that names no reply shape, as every domain written before there
/// was one.
private struct ShapeUnnamedDomain: AskDomain {
    var brand: AskBrand { ProseDomain().brand }
    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
}

/// A domain with no rows and no tools whose answers are prose alone, kept
/// whatever grounded them.
private struct ProseDomain: AskDomain {
    var brand: AskBrand {
        AskBrand(
            title: "Ask Prose", shortLabel: "Ask", appDirectory: "AskKitCrossPosture",
            logSubsystem: "AskKit.crossPosture", help: "help",
            firstScreenHeadline: "headline", firstScreenSentence: "sentence",
            disclosureSentence: "disclosure", scopeCaveat: "caveat"
        )
    }

    var grounding: AskGroundingPolicy { .notRequired }
    var replyShape: AskReplyShape { .prose }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
}

/// A sink that bridges none of the lines.
private struct ProseQuietSink: AskLogSink {}

/// A session written before reply shapes, with only the members `AskSession`
/// has no default for: it streams the full reply, a kind and a tile included,
/// whatever shape it is asked for.
private struct FullReplySession: AskSession {
    static let answer = "It is 14:05 in Lisbon."
    static let followUps = ["And in Tokyo?", "What day is it?"]

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(AskReplySnapshot(
                answer: Self.answer, questionKind: AskQuestionKind.count, showsEveryMatch: true,
                tiles: ["Lisbon"], followUps: Self.followUps
            ))
            continuation.finish()
        }
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        throw CancellationError()
    }

    func toolCallCount() async -> Int { 0 }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        throw CancellationError()
    }
}

/// A seam serving the device's tier with a session written before shapes.
private struct ProseSeam: AskModelSeam {
    let status: AskModelStatus

    func tierStates() async -> [AskTierState] {
        [AskTierState(tier: .onDevice, isAvailable: true, speaksLanguage: true)]
    }

    func makeSession(tier: AskTier, tools: [any Tool], instructions: String) async throws -> AskSessionBox? {
        AskSessionBox(session: FullReplySession(), tier: tier)
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

#endif
