#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Testing

@_spi(AskKitInternal) @testable import AskCore

/// What an answer offers to do: recorded by a tool, carried on the answer, kept
/// with the thread, and carried out by nothing but the reader's yes.
@Suite(.timeLimit(.minutes(1))) struct AskProposalTests {

    private static let lend = AskProposal(
        title: "Mark The Peregrine as lent", detail: "It stays with your books, marked as out on loan.",
        actionLabel: "Mark as lent", systemImage: "book.closed", encodedPayload: Data(#"{"book":"b6"}"#.utf8)
    )

    // MARK: - The value

    @Test func aProposalRoundTripsAndReadsItsPayloadBack() throws {
        let decoded = try JSONDecoder().decode(AskProposal.self, from: JSONEncoder().encode(Self.lend))
        #expect(decoded == Self.lend)
        #expect(decoded.payload(as: [String: String].self) == ["book": "b6"])
        #expect(decoded.payload(as: [Int].self) == nil)
    }

    /// A payload goes in as the domain's value and comes back as it, through
    /// AskKit's JSON: byte for byte what a default `JSONEncoder` writes, so a
    /// proposal kept in a thread file reads back across the change.
    @Test func aPayloadGoesInAndComesBackAsTheValue() throws {
        let proposal = try AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent", payload: ["book": "b6"])
        #expect(proposal.payload == (try JSONEncoder().encode(["book": "b6"])))
        #expect(proposal.payload(as: [String: String].self) == ["book": "b6"])
        let decoded = try JSONDecoder().decode(AskProposal.self, from: JSONEncoder().encode(proposal))
        #expect(decoded.payload(as: [String: String].self) == ["book": "b6"])
    }

    /// A proposal made without a payload carries none, and reads back none.
    @Test func aProposalMadeWithoutAPayloadCarriesNone() {
        let proposal = AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent")
        #expect(proposal.payload.isEmpty)
        #expect(proposal.payload(as: String.self) == nil)
    }

    /// A payload JSON can't hold, or one the domain already encoded, is never
    /// proposed: the initializer throws, rather than offering a card whose
    /// `perform` would read nil.
    @Test func aPayloadThatDoesNotEncodeIsNeverProposed() throws {
        #expect(throws: EncodingError.self) {
            try AskProposal(title: "Lend it", actionLabel: "Lend", payload: Double.infinity)
        }
        let propertyList = try PropertyListEncoder().encode(["book": "b6"])
        #expect(throws: EncodingError.self) {
            try AskProposal(title: "Lend it", actionLabel: "Lend", payload: propertyList)
        }
    }

    @Test func everyOutcomeRoundTrips() throws {
        let outcomes: [AskProposalOutcome] = [
            .confirmed("Marked The Peregrine as lent."), .confirmed(nil), .declined, .failed("Not on the shelf"), .failed(nil),
            .handedOff("Opened in Add"), .handedOff(nil), .performing
        ]
        for outcome in outcomes {
            #expect(try JSONDecoder().decode(AskProposalOutcome.self, from: JSONEncoder().encode(outcome)) == outcome)
        }
    }

    // MARK: - The kind

    /// Why `kind` is additive: a proposal filed before it existed carries no
    /// such field, and must read back as the only thing it could ever have
    /// been.
    @Test func aProposalFiledBeforeKindsExistedReadsBackAsPerform() throws {
        let filed = Data(#"{"id":"\#(UUID().uuidString)","title":"Mark The Peregrine as lent","actionLabel":"Mark as lent"}"#.utf8)
        let decoded = try JSONDecoder().decode(AskProposal.self, from: filed)
        #expect(decoded.kind == .perform)
        #expect(decoded.title == "Mark The Peregrine as lent")
    }

    @Test func aHandOffKeepsItsKindAcrossTheThreadFile() throws {
        let handOff = AskProposal(
            kind: .handOff, title: "Add Kind of Blue", actionLabel: "Add",
            encodedPayload: Data(#"{"title":"Kind of Blue"}"#.utf8)
        )
        let decoded = try JSONDecoder().decode(AskProposal.self, from: JSONEncoder().encode(handOff))
        #expect(decoded.kind == .handOff)
        #expect(decoded == handOff)
    }

    /// Two receipts, and neither may let an answer claim the thing happened.
    /// The hand-off's has one more thing to deny, since a door being open is
    /// also a claim.
    @Test func neitherReceiptLetsAnAnswerSayItIsDone() {
        #expect(AskProposal.modelReceipt.contains("never say it is done"))
        #expect(AskProposal.handOffReceipt.contains("never say it is done"))
        #expect(AskProposal.handOffReceipt.contains("never say anything is open"))
    }

    @Test func anAnswerAndAnEntryWrittenBeforeProposalsStillDecode() throws {
        let answer = try JSONDecoder().decode(
            AskAnswer<FakeRow>.self, from: Data(#"{"text":"The Peregrine is on your shelf."}"#.utf8)
        )
        #expect(answer.proposal == nil)
        let entry = try JSONDecoder().decode(
            AskThreadEntry<FakeRow>.self, from: Data(#"{"question":"Where is The Peregrine?","text":"The Peregrine is on your shelf."}"#.utf8)
        )
        #expect(entry.proposalOutcome == nil)
    }

    @Test func whatANewerBuildWroteCostsTheCardNeverTheTurn() throws {
        let answer = try JSONDecoder().decode(
            AskAnswer<FakeRow>.self, from: Data(#"{"text":"The Peregrine is on your shelf.","proposal":{"title":7}}"#.utf8)
        )
        #expect(answer.text == "The Peregrine is on your shelf.")
        #expect(answer.proposal == nil)

        let entry = try JSONDecoder().decode(
            AskThreadEntry<FakeRow>.self,
            from: Data(#"{"question":"Where is The Peregrine?","text":"The Peregrine is on your shelf.","proposalOutcome":{"postponed":{}}}"#.utf8)
        )
        #expect(entry.question == "Where is The Peregrine?")
        // Not none, which would offer the action again: what the newer build
        // wrote may say it ran (`anOutcomeALaterBuildWroteReadsAsPerforming`).
        #expect(entry.proposalOutcome == .performing)
    }

    @Test func everyCopyOfAnAnswerKeepsItsProposal() {
        let answer = AskAnswer<FakeRow>(text: "The Peregrine is on your shelf.", proposal: Self.lend)
        #expect(answer.replacing(basis: "b").proposal == Self.lend)
        #expect(answer.replacing(payload: Data("p".utf8)).proposal == Self.lend)
        #expect(answer.replacing(proposal: nil).proposal == nil)
    }

    // MARK: - The collector

    @Test func theFirstProposalInATurnIsTheOneKept() async {
        let collector = AskCollector<FakeRow>()
        let another = AskProposal(title: "Mark Rumours as lent", actionLabel: "Mark as lent")
        #expect(await collector.record(proposal: Self.lend))
        #expect(await collector.record(proposal: another) == false)
        #expect(await collector.turnProposal == Self.lend)

        await collector.beginTurn()
        #expect(await collector.turnProposal == nil)
        #expect(await collector.record(proposal: another))
    }

    @Test func aProposalCarryingMoreThanAnIntentIsRefused() async {
        let collector = AskCollector<FakeRow>()
        let heavy = AskProposal(
            title: "Mark The Peregrine as lent", actionLabel: "Mark as lent", encodedPayload: Data(count: AskProposal.maxPayloadBytes + 1)
        )
        #expect(await collector.record(proposal: heavy) == false)
        #expect(await collector.turnProposal == nil)
    }

    // MARK: - The domain

    @Test func aDomainThatNeverSaidHowToCarryOneOutRefuses() async {
        await #expect(throws: AskProposalFailure()) {
            try await FakeDomain().perform(Self.lend)
        }
    }
}

#endif
