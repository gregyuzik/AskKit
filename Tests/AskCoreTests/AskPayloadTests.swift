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

    /// A payload of one key, whose JSON has one order to be written in.
    nonisolated private struct Shelf: Codable, Sendable {
        let shelf: Int
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

    /// What a tool records is its value, and AskKit encodes it as the JSON a
    /// default `JSONEncoder` writes, as domains encoded their payloads for the
    /// chat files 0.2.0 wrote: compact, with no strategies. The order of an
    /// object's keys is the one thing that encoder leaves open, from one
    /// encoding to the next, so a payload of one key is pinned to the byte
    /// (the on-disk fixture's), and one of two as the object it parses to.
    /// The answer reads it back as the value.
    @Test func aRecordedValueIsKeptAsTheJSONADefaultEncoderWrites() async throws {
        let collector = AskCollector<FakeRow>()
        #expect(try await collector.record(payload: Shelf(shelf: 2)))
        #expect(await collector.turnPayload == Data(#"{"shelf":2}"#.utf8))

        let span = YearSpan(oldest: 1959, newest: 1977)
        #expect(try await collector.record(payload: span))
        let recorded = try #require(await collector.turnPayload)
        #expect(try JSONDecoder().decode([String: Int].self, from: recorded) == ["oldest": 1959, "newest": 1977])
        #expect(!recorded.contains(UInt8(ascii: " ")) && !recorded.contains(UInt8(ascii: "\n")))
        #expect(AskAnswer<FakeRow>(text: "Six records.", encodedPayload: recorded).payload(as: YearSpan.self) == span)
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
        let answer = AskAnswer<FakeRow>(text: "You own six records.", encodedPayload: await collector.turnPayload)
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
        let answer = AskAnswer<FakeRow>(text: "You own six records.", basis: "From your records", encodedPayload: Data("{}".utf8))
        let decoded = try JSONDecoder().decode(AskAnswer<FakeRow>.self, from: JSONEncoder().encode(answer))
        #expect(decoded.basis == "From your records")
        #expect(decoded.payload == Data("{}".utf8))
    }

    @Test func replacingOneFieldKeepsEveryOther() throws {
        let answer = AskAnswer<FakeRow>(
            text: "a", matches: [FakeRow("Rumours")], tiles: [FakeRow("Rumours")], followUps: ["Why?"],
            questionKind: AskQuestionKind.pick, isTruncated: false, basis: "b", encodedPayload: Data("p".utf8)
        )
        let rebased = answer.replacing(basis: "c")
        #expect(rebased.basis == "c")
        #expect(rebased.payload == answer.payload)
        #expect(rebased.tiles.map(\.displayTitle) == ["Rumours"])
        #expect(rebased.followUps == ["Why?"])
        #expect(rebased.questionKind == AskQuestionKind.pick)

        let emptied = answer.replacing(encodedPayload: nil)
        #expect(emptied.payload == nil)
        #expect(emptied.basis == "b")

        // A value in place of what was there, encoded as the initializer
        // encodes one, and everything else kept.
        let reshelved = try answer.replacing(payload: Shelf(shelf: 3))
        #expect(reshelved.payload == Data(#"{"shelf":3}"#.utf8))
        #expect(reshelved.basis == "b")
        #expect(reshelved.tiles.map(\.displayTitle) == ["Rumours"])
        #expect(reshelved.followUps == ["Why?"])
        #expect(reshelved.questionKind == AskQuestionKind.pick)
    }

    // MARK: - An answer the domain builds

    /// An answer the domain builds itself, in `deterministicAnswer(for:)` or
    /// a refine pass, takes its payload as a value, as a tool's collector
    /// does, and AskKit encodes it to the bytes the collector would: the
    /// JSON a default `JSONEncoder` writes. It reads back as the value.
    @Test func anAnswersPayloadIsEncodedAsACollectorEncodesIt() async throws {
        #expect(try AskAnswer<FakeRow>(text: "Shelf two.", payload: Shelf(shelf: 2)).payload == Data(#"{"shelf":2}"#.utf8))

        let span = YearSpan(oldest: 1959, newest: 1977)
        let answer = try AskAnswer<FakeRow>(text: "Six records.", payload: span)
        let collector = AskCollector<FakeRow>()
        try await collector.record(payload: span)
        let recorded = try #require(await collector.turnPayload)
        let built = try #require(answer.payload)
        #expect(try JSONDecoder().decode([String: Int].self, from: built) == JSONDecoder().decode([String: Int].self, from: recorded))
        #expect(answer.payload(as: YearSpan.self) == span)
    }

    /// A value JSON can't hold, or a payload already encoded, throws from the
    /// initializer and from `replacing(payload:)`, so the domain hears of it
    /// rather than an answer arriving without its card; the answer it would
    /// have replaced keeps what it had.
    @Test func anAnswersPayloadThatDoesNotEncodeThrows() throws {
        #expect(throws: EncodingError.self) { try AskAnswer<FakeRow>(text: "x", payload: Reading(value: .infinity)) }
        #expect(throws: EncodingError.self) { try AskAnswer<FakeRow>(text: "x", payload: Reading(value: .nan)) }
        let json = try JSONEncoder().encode(YearSpan(oldest: 1959, newest: 1977))
        #expect(throws: EncodingError.self) { try AskAnswer<FakeRow>(text: "x", payload: json) }

        let answer = try AskAnswer<FakeRow>(text: "x", payload: Shelf(shelf: 2))
        #expect(throws: EncodingError.self) { try answer.replacing(payload: Reading(value: .nan)) }
        #expect(throws: EncodingError.self) { try answer.replacing(payload: json) }
        #expect(answer.payload == Data(#"{"shelf":2}"#.utf8))
    }
}

#endif
