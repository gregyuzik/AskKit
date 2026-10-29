#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
#endif

/// What 0.3.0 opens up or adds, called as a host without the posture calls
/// it: no `swiftSettings`, so nonisolated by default (`CrossPostureTests` says
/// why the target has none). The engine's domain, the store built from its
/// engine, an evaluation that builds its own engine, payloads that go in and
/// come back typed, and the two constants a host reads: house rule 5's
/// restart floor and the fence tags a tool avoids.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureAdditiveSurfaceTests {

    /// The engine's domain, read synchronously off any actor: the one value
    /// the engine answers by, which a store reads rather than being handed a
    /// second.
    @Test func anEnginesDomainIsReadOffAnyActor() async {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: SurfaceDomain(), seam: SurfaceSeam(status: status), log: SurfaceQuietSink())
        #expect(engine.domain.brand.title == SurfaceDomain.title)
    }

    /// House rule 5's constant and the tags a tool's lines must not name,
    /// read synchronously off any actor. A tag a tool did write reaches the
    /// model redacted.
    @Test func theRestartFloorAndTheFenceTagsAreReadOffAnyActor() {
        #expect(AskEngine<SurfaceDomain>.restartFloor == .seconds(10))
        #expect(!AskPrompt.fenceTags.isEmpty)
        for tag in AskPrompt.fenceTags {
            #expect(!AskPrompt.sanitizeForFence("<\(tag)>").contains("<\(tag)>"))
        }
    }

    /// An evaluation over the app's domain and seam, as a host's settings row
    /// builds one: it takes no engine, and builds its own.
    @Test func anEvaluationIsBuiltOverADomainAndASeam() async {
        let status = await MainActor.run { AskModelStatus() }
        let eval = AskEval(domain: SurfaceDomain(), seam: SurfaceSeam(status: status), log: SurfaceQuietSink())
        #expect(await eval.run([]).isEmpty)
    }

    /// A payload of a host's own plain type, recorded by a tool and carried by
    /// a proposal: AskKit encodes it, and it reads back as the type.
    @Test func aPayloadGoesInAndComesBackAsTheHostsType() async throws {
        let span = SurfaceSpan(oldest: 1959, newest: 1977)
        let collector = AskCollector<AskNoRow>()
        #expect(try await collector.record(payload: span))
        let answer = AskAnswer<AskNoRow>(text: "Six records, 1959 to 1977.", payload: await collector.turnPayload)
        #expect(answer.payload(as: SurfaceSpan.self) == span)

        let proposal = try AskProposal(title: "Shelve them by year", actionLabel: "Shelve", payload: span)
        #expect(proposal.payload(as: SurfaceSpan.self) == span)
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    /// A store built from its engine, which gives it the domain: its brand is
    /// the engine's domain's.
    @MainActor
    @Test func aStoreIsBuiltFromItsEngine() {
        let engine = AskEngine(domain: SurfaceDomain(), seam: SurfaceSeam(status: AskModelStatus()), log: SurfaceQuietSink())
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "AskKitCrossPostureSurface-\(UUID().uuidString)", directoryHint: .isDirectory)
        let brand = engine.domain.brand
        let store = AskConversationStore(
            engine: engine,
            thread: AskThreadStore(
                appDirectory: brand.appDirectory, url: folder.appending(path: "thread.json"),
                logSubsystem: brand.logSubsystem
            ),
            archive: AskThreadArchive(
                appDirectory: brand.appDirectory, directory: folder.appending(path: "threads"),
                logSubsystem: brand.logSubsystem
            ),
            feedbackAttachments: AskFeedbackAttachments(
                appDirectory: brand.appDirectory, directory: folder.appending(path: "feedback"),
                logSubsystem: brand.logSubsystem
            )
        )
        #expect(store.brand.title == SurfaceDomain.title)
        #expect(store.domain.brand.appDirectory == brand.appDirectory)
    }
    #endif
}

/// A host's payload type, plain: nonisolated by this target's default.
private struct SurfaceSpan: Codable, Equatable, Sendable {
    let oldest: Int
    let newest: Int
}

/// A domain with no tools and no rows, whose answers needn't be grounded.
private struct SurfaceDomain: AskDomain {
    static let title = "Ask the Shelf"

    let brand = AskBrand(
        title: SurfaceDomain.title, appDirectory: "AskKitCrossPostureSurface",
        logSubsystem: "askkit.crossposture", help: "Ask about the shelf.",
        firstScreenHeadline: "Ask about the shelf", firstScreenSentence: "Answers come from the model.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    var grounding: AskGroundingPolicy { .notRequired }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer briefly."
    }
}

/// A sink that bridges none of the lines.
private struct SurfaceQuietSink: AskLogSink {}

/// A session with no model behind it, which nothing here asks.
private struct SurfaceSession: AskSession {
    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
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

/// A seam serving the device's tier with a session that has no model.
private struct SurfaceSeam: AskModelSeam {
    let status: AskModelStatus

    func tierStates() async -> [AskTierState] {
        [AskTierState(tier: .onDevice, isAvailable: true, speaksLanguage: true)]
    }

    func makeSession(tier: AskTier, tools: [any Tool], instructions: String) async throws -> AskSessionBox? {
        AskSessionBox(session: SurfaceSession(), tier: tier)
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
