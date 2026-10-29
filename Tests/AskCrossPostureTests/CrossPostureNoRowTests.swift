#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels
import Testing

/// A domain whose tools read no rows, as a host without the posture writes
/// one: it names neither associated type, leaves `overview()` and
/// `search(_:context:)` to their defaults, and gives no nothing-to-ask copy.
/// Built under this target's lack of settings, it fails to compile if a
/// stand-in or a default loses the isolation it spells, and its turn runs
/// through the engine as a host's would.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureNoRowTests {
    @Test func aDomainNamingNeitherTypeGetsTheStandIns() {
        #expect(NoRowDomain.Row.self == AskNoRow.self)
        #expect(NoRowDomain.SearchArguments.self == AskNoSearchArguments.self)
        #expect(!NoRowDomain().answersWithoutModel)
        #expect(NoRowDomain().brand.nothingToAskCopy == nil)
    }

    /// A turn whose tool returns text and records no rows: grounded by the
    /// call, and answered with no rows behind it and no tiles.
    @Test func aTurnThatCallsAToolIsAnsweredWithNoRows() async throws {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: NoRowDomain(), seam: NoRowSeam(status: status), log: NoRowQuietSink())
        var events: [AskTurnEvent<AskNoRow>] = []
        for try await event in engine.ask("What time is it in Lisbon?") {
            events.append(event)
        }
        let answer = try #require(events.lazy.compactMap { if case .answer(let answer) = $0 { answer } else { nil } }.first)
        #expect(answer.text == "It is 14:05 in Lisbon.")
        #expect(answer.matches.isEmpty)
        #expect(answer.tiles.isEmpty)
        #expect(events.contains(.activity(.custom(NoRowClockTool.activityKey))))
        #expect(!events.contains { if case .rowsRead = $0 { true } else { false } })
        #expect(!events.contains { if case .restarted = $0 { true } else { false } })
    }

    /// The defaults, called off any actor: nothing counted, and a search that
    /// fails as ungrounded.
    @Test func theDefaultsAreCalledWithoutThePosture() async {
        #expect(await NoRowDomain().overview() == .empty)
        let context = AskToolContext(
            collector: AskCollector<AskNoRow>(), relay: AskActivityRelay(),
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        await #expect(throws: AskError.ungrounded) {
            try await NoRowDomain().search(AskNoSearchArguments(), context: context)
        }
    }

    /// A domain whose answers needn't be grounded, with no tools at all: its
    /// turn answers from the model alone, drawn as it streams, never asked
    /// again, and saying nothing grounded it. Its session's planner stops
    /// the turn if anything asks it to plan.
    @Test func aDomainThatNeedsNoGroundingAnswersATurnThatCallsNoTool() async throws {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: NoRowChatDomain(), seam: NoRowSeam(status: status), log: NoRowQuietSink())
        var events: [AskTurnEvent<AskNoRow>] = []
        for try await event in engine.ask("Hello!") {
            events.append(event)
        }
        let answer = try #require(events.lazy.compactMap { if case .answer(let answer) = $0 { answer } else { nil } }.first)
        #expect(answer.text == NoRowSession.unaided)
        #expect(answer.grounding == AskGrounding.nothing)
        #expect(answer.matches.isEmpty)
        #expect(events.contains(.partial(NoRowSession.unaided)))
        #expect(!events.contains { if case .restarted = $0 { true } else { false } })
        #expect(NoRowChatDomain().grounding == .notRequired)
        #expect(NoRowChatDomain().brand.nothingToAskCopy == nil)
    }

    /// The policy, what an answer records, and what an evaluation asks of it,
    /// built, compared and decoded off any actor.
    @Test func theGroundingPolicyAndWhatAnAnswerRecordsAreUsableWithoutThePosture() throws {
        #expect(NoRowDomain().grounding == .retrieval)
        let policies: [AskGroundingPolicy] = [.retrieval, .toolCall, .notRequired]
        #expect(policies.map(\.rawValue) == ["retrieval", "toolCall", "notRequired"])
        #expect(policies.map(\.rawValue).compactMap(AskGroundingPolicy.init(rawValue:)) == policies)

        let grounding = try JSONEncoder().encode(AskGrounding.followUp)
        #expect(try JSONDecoder().decode(AskGrounding.self, from: grounding) == .followUp)

        let answer = AskAnswer<AskNoRow>(text: "It is 14:05 in Lisbon.", grounding: .toolCall)
        #expect(answer.grounding == .toolCall)
        #expect(answer.replacing(grounding: AskGrounding.nothing).grounding == AskGrounding.nothing)
        let kept = try JSONEncoder().encode(answer)
        #expect(try JSONDecoder().decode(AskAnswer<AskNoRow>.self, from: kept) == answer)

        let scenario = AskScenario(id: "thanks", question: "Thanks!", expectsGrounding: false)
        #expect(scenario.expectsGrounding == false)
        var outcome = AskOutcome(id: scenario.id)
        outcome.grounding = .toolCall
        outcome.misses = [.unexpectedGrounding(.toolCall), .noGrounding]
        #expect(outcome.grounding == .toolCall)
        #expect(!outcome.isGood)
        #expect(outcome.misses.map(\.line) == ["GROUNDED by tool call, expected nothing", "NOT GROUNDED, expected grounding"])
    }

    /// "Nothing grounded it" and "nobody judged it" kept apart in the spelling
    /// a host writes: a bare `.nothing` against the optional grounding is the
    /// case, never nil, and a bare `.hidden` against an optional presentation
    /// is the presentation. The thread file still reads `"none"`.
    @Test func nothingGroundedIsNotNoGroundingRecorded() throws {
        let unjudged = AskAnswer<AskNoRow>(text: "Stopped part-way.")
        let ungrounded = AskAnswer<AskNoRow>(text: "Hello. Ask me anything.", grounding: .nothing)
        #expect(unjudged.grounding != .nothing)
        #expect(ungrounded.grounding == .nothing)
        #expect(ungrounded.grounding != nil)
        #expect(AskGrounding.nothing.rawValue == "none")
        #expect(try JSONDecoder().decode(AskGrounding.self, from: Data(#""none""#.utf8)) == .nothing)

        let chosen: AskEvidencePresentation? = .counted
        let unchosen: AskEvidencePresentation? = nil
        #expect(chosen != .hidden)
        #expect(unchosen != .hidden)
    }

    /// What a domain says about the evidence line, asked off any actor: the
    /// default count, and a domain's own choice by what grounded the answer.
    @Test func aDomainsEvidenceLineIsAskedWithoutThePosture() {
        let grounded = AskAnswer<AskNoRow>(text: "It is 14:05 in Lisbon.", grounding: .toolCall)
        let ungrounded = AskAnswer<AskNoRow>(text: "Hello. Ask me anything.", grounding: AskGrounding.nothing)
        #expect(NoRowDomain().evidence(for: grounded) == .counted)
        #expect(NoRowDomain().evidence(for: ungrounded) == .counted)
        #expect(NoRowChatDomain().evidence(for: grounded) == .line(NoRowChatDomain.toolLine))
        #expect(NoRowChatDomain().evidence(for: ungrounded) == AskEvidencePresentation.hidden)
    }

    /// The stand-ins, built, compared and decoded off any actor, and the
    /// planner's empty arguments made as a host's own session makes them.
    @Test func theStandInsAreUsableWithoutThePosture() throws {
        let row = AskNoRow(id: "Lisbon")
        #expect(row.displayTitle == "Lisbon")
        #expect(try JSONDecoder().decode(AskNoRow.self, from: JSONEncoder().encode(row)) == row)
        _ = AskNoSearchArguments.generationSchema
        _ = try AskNoSearchArguments(GeneratedContent(properties: [:]))
        _ = AskNoSearchArguments()
    }
}

/// What the clock tool is asked.
@Generable
private struct NoRowClockArguments: Sendable {
    @Guide(description: "A city's name")
    var city: String
}

/// A tool that reads no rows: it returns text, clamped, and records nothing.
private struct NoRowClockTool: Tool {
    static let activityKey = "clock"

    let name = "local_time"
    let description = "The time now in a city."
    let context: AskToolContext<AskNoRow>

    func call(arguments: NoRowClockArguments) async throws -> String {
        await context.withToolCall(.custom(Self.activityKey)) { _ in
            ("\(AskPrompt.clamp(arguments.city, AskPrompt.shortClamp)): 14:05", report: nil)
        }
    }
}

/// The smallest domain without rows: the three members left without a
/// default, with no nothing-to-ask copy in its brand, since its subject
/// isn't the reader's rows.
private struct NoRowDomain: AskDomain {
    let brand = AskBrand(
        title: "Ask the Clock", appDirectory: "AskKitCrossPostureNoRow",
        logSubsystem: "askkit.crossposture", help: "Ask the time anywhere.",
        firstScreenHeadline: "Ask the time anywhere", firstScreenSentence: "Any city, any time zone.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] {
        [NoRowClockTool(context: context)]
    }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Call local_time before you answer."
    }
}

/// A domain whose answers needn't be grounded and which has no tools: a
/// chat over what the model knows. It names its grounding policy, gives no
/// nothing-to-ask copy, and words its own evidence line: none
/// under an answer nothing grounded, and its own under one a tool did.
private struct NoRowChatDomain: AskDomain {
    static let toolLine = "From the clock, read just now"

    let brand = AskBrand(
        title: "Ask Anything", appDirectory: "AskKitCrossPostureNoRowChat",
        logSubsystem: "askkit.crossposture", help: "Ask anything.",
        firstScreenHeadline: "Ask anything", firstScreenSentence: "Answers come from the model.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    var grounding: AskGroundingPolicy { .notRequired }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer briefly."
    }

    func evidence(for answer: AskAnswer<AskNoRow>) -> AskEvidencePresentation {
        answer.grounding == .nothing ? .hidden : .line(Self.toolLine)
    }
}

/// A sink that bridges none of the lines.
private struct NoRowQuietSink: AskLogSink {}

/// A session standing in for a model that calls the clock and answers from
/// it: the call goes through the tool, so the collector counts it and the
/// turn is grounded by it. With no clock on the session, it answers from
/// nothing.
private struct NoRowSession: AskSession {
    /// What it answers with no tool to call.
    static let unaided = "Hello. Ask me anything."

    let clock: NoRowClockTool?

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [clock] in
                do {
                    _ = try await clock?.call(arguments: NoRowClockArguments(city: "Lisbon"))
                    let answer = clock == nil ? Self.unaided : "It is 14:05 in Lisbon."
                    continuation.yield(AskReplySnapshot(answer: answer, questionKind: "lookup", followUps: []))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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

/// A seam serving the device's tier, whose sessions call the clock tool the
/// engine built for them.
private struct NoRowSeam: AskModelSeam {
    let status: AskModelStatus

    func tierStates() async -> [AskTierState] {
        [AskTierState(tier: .onDevice, speaksLanguage: true)]
    }

    func makeSession(tier: AskTier, tools: [any Tool], instructions: String) async throws -> AskSessionBox? {
        AskSessionBox(session: NoRowSession(clock: tools.lazy.compactMap { $0 as? NoRowClockTool }.first), tier: tier)
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
