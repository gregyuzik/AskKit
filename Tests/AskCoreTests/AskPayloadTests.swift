#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Testing

@_spi(AskKitInternal) @testable import AskCore

/// What a tool also knew about a turn, carried out of it on the answer — and
/// the basis line that rides beside it.
@Suite(.timeLimit(.minutes(1))) struct AskPayloadTests {

    private struct YearSpan: Codable, Equatable {
        let oldest: Int
        let newest: Int
    }

    // MARK: - The collector

    @Test func aTurnsPayloadIsKeptUntilTheNextTurnBegins() async {
        let collector = AskCollector<FakeRow>()
        let payload = Data(#"{"oldest":1959,"newest":1977}"#.utf8)
        #expect(await collector.record(payload: payload))
        #expect(await collector.turnPayload == payload)
        await collector.beginTurn()
        #expect(await collector.turnPayload == nil)
    }

    @Test func anOversizedPayloadIsRefusedWhole() async {
        let collector = AskCollector<FakeRow>()
        #expect(await collector.record(payload: Data("kept".utf8)))
        let oversized = Data(count: AskCollector<FakeRow>.maxPayloadBytes + 1)
        #expect(await collector.record(payload: oversized) == false)
        // Refused rather than truncated — and what was there stays.
        #expect(await collector.turnPayload == Data("kept".utf8))
    }

    // MARK: - The answer

    @Test func aPayloadReadsBackAsTheDomainsOwnType() throws {
        let span = YearSpan(oldest: 1959, newest: 1977)
        let answer = AskAnswer<FakeRow>(text: "You own six records.", payload: try JSONEncoder().encode(span))
        #expect(answer.payload(as: YearSpan.self) == span)
        // The wrong type is no card, never a failed answer.
        #expect(answer.payload(as: [String].self) == nil)
        #expect(AskAnswer<FakeRow>(text: "Nothing else known.").payload(as: YearSpan.self) == nil)
    }

    @Test func anAnswerSavedBeforePayloadsDecodes() throws {
        let answer = try JSONDecoder().decode(
            AskAnswer<FakeRow>.self, from: Data(#"{"text":"You own six records.","matches":[],"tiles":[]}"#.utf8)
        )
        #expect(answer.payload == nil)
        #expect(answer.basis == nil)
    }

    @Test func aPayloadAndABasisSurviveTheThread() throws {
        let answer = AskAnswer<FakeRow>(text: "You own six records.", basis: "From your records", payload: Data("{}".utf8))
        let decoded = try JSONDecoder().decode(AskAnswer<FakeRow>.self, from: JSONEncoder().encode(answer))
        #expect(decoded.basis == "From your records")
        #expect(decoded.payload == Data("{}".utf8))
    }

    @Test func replacingOneFieldKeepsEveryOther() {
        let answer = AskAnswer<FakeRow>(
            text: "a", matches: [FakeRow("Rumours")], tiles: [FakeRow("Rumours")], followUps: ["Why?"],
            questionKind: AskQuestionKind.pick, isTruncated: false, basis: "b", payload: Data("p".utf8)
        )
        let rebased = answer.replacing(basis: "c")
        #expect(rebased.basis == "c")
        #expect(rebased.payload == answer.payload)
        #expect(rebased.tiles.map(\.displayTitle) == ["Rumours"])
        #expect(rebased.followUps == ["Why?"])
        #expect(rebased.questionKind == AskQuestionKind.pick)

        let emptied = answer.replacing(payload: nil)
        #expect(emptied.payload == nil)
        #expect(emptied.basis == "b")
    }
}

#endif
