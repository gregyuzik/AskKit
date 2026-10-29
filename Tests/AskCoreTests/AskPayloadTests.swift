#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Testing

@_spi(AskKitInternal) @testable import AskCore

/// What a tool also knew about a turn, carried out of it on the answer — and
/// the basis line that rides beside it.
@Suite(.timeLimit(.minutes(1))) struct AskPayloadTests {

    /// `nonisolated`, as a domain's payload type has to be in a target with
    /// MainActor default isolation: the collector encodes it off the main
    /// actor.
    nonisolated private struct YearSpan: Codable, Equatable, Sendable {
        let oldest: Int
        let newest: Int
    }

    /// A payload with a `Double` in it, which JSON can't hold when it is
    /// infinite or NaN.
    nonisolated private struct Reading: Codable, Sendable {
        let value: Double
    }

    // MARK: - The collector

    @Test func aTurnsPayloadIsKeptUntilTheNextTurnBegins() async throws {
        let collector = AskCollector<FakeRow>()
        #expect(try await collector.record(payload: YearSpan(oldest: 1959, newest: 1977)))
        #expect(await collector.turnPayload != nil)
        await collector.beginTurn()
        #expect(await collector.turnPayload == nil)
    }

    /// What a tool records is its value, and AskKit encodes it: as JSON, byte
    /// for byte what a default `JSONEncoder` writes, which is how domains
    /// encoded their payloads for the chat files 0.2.0 wrote. The answer
    /// reads it back as the value.
    @Test func aRecordedValueIsKeptAsTheJSONADefaultEncoderWrites() async throws {
        let collector = AskCollector<FakeRow>()
        let span = YearSpan(oldest: 1959, newest: 1977)
        #expect(try await collector.record(payload: span))
        let recorded = try #require(await collector.turnPayload)
        #expect(recorded == (try JSONEncoder().encode(span)))
        #expect(AskAnswer<FakeRow>(text: "Six records.", payload: recorded).payload(as: YearSpan.self) == span)
    }

    /// A value JSON can't hold throws, so the domain hears of it rather than
    /// a card going missing without a word, and what was there stays.
    @Test func aValueThatDoesNotEncodeThrowsAndThePayloadStands() async throws {
        let collector = AskCollector<FakeRow>()
        #expect(try await collector.record(payload: YearSpan(oldest: 1959, newest: 1977)))
        let earlier = await collector.turnPayload
        await #expect(throws: EncodingError.self) {
            try await collector.record(payload: Reading(value: .infinity))
        }
        await #expect(throws: EncodingError.self) {
            try await collector.record(payload: Reading(value: .nan))
        }
        #expect(await collector.turnPayload == earlier)
    }

    /// A payload a domain encoded itself, in a property list or in JSON, is a
    /// `Data`. Encoded again, it would be a base64 string that reads back as
    /// nothing but `Data`, and `payload(as:)` would read nil: so it throws.
    @Test func aPayloadAlreadyEncodedIsRefusedWithAThrow() async throws {
        let collector = AskCollector<FakeRow>()
        let span = YearSpan(oldest: 1959, newest: 1977)
        let propertyList = try PropertyListEncoder().encode(span)
        await #expect(throws: EncodingError.self) { try await collector.record(payload: propertyList) }
        let json = try JSONEncoder().encode(span)
        await #expect(throws: EncodingError.self) { try await collector.record(payload: json) }
        #expect(await collector.turnPayload == nil)
    }

    @Test func anOversizedPayloadIsRefusedWhole() async throws {
        let collector = AskCollector<FakeRow>()
        #expect(try await collector.record(payload: "kept"))
        let kept = await collector.turnPayload
        // Its JSON is the string in quotes, two bytes over the limit.
        let oversized = String(repeating: "x", count: AskCollector<FakeRow>.maxPayloadBytes)
        #expect(try await collector.record(payload: oversized) == false)
        // Refused rather than truncated — and what was there stays.
        #expect(await collector.turnPayload == kept)
    }

    // MARK: - The answer

    @Test func aPayloadReadsBackAsTheDomainsOwnType() async throws {
        let collector = AskCollector<FakeRow>()
        let span = YearSpan(oldest: 1959, newest: 1977)
        try await collector.record(payload: span)
        let answer = AskAnswer<FakeRow>(text: "You own six records.", payload: await collector.turnPayload)
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
