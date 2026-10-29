import Foundation
import Testing

@testable import AskCore

/// The thread's form on disk, pinned.
///
/// Every install holds turns written in it, in `ask-thread.json` and in each
/// filing under `threads/`, and the list of those filings in
/// `threads/index.json`; a build that writes or reads them differently
/// costs those readers their chats on the first launch after an update. So
/// the form changes only on purpose: a change here fails these tests, and the
/// fixtures (`AskOnDiskFormatFixtures`) change with it, in the same commit,
/// with a decoder that still reads the old form.
///
/// Pinned as JSON values, not bytes: `JSONEncoder` promises no key order, so
/// both sides are compared as what they parse to. The encoder is the one
/// `AskThreadStore.save(_:)` and the archive write with, as they make it:
/// dates as seconds since 2001, data as base64. The cases' associated values
/// are spelled as the compiler synthesizes them, `_0` for an unlabelled one,
/// and those keys are on disk.
@Suite(.timeLimit(.minutes(1))) struct AskOnDiskFormatTests {

    nonisolated private struct Row: AskRow {
        let id: String
        let displayTitle: String
    }

    /// Three turns: one answered, from a photo, with a proposal the reader
    /// confirmed, one that failed with prose drawn, and one the reader
    /// thumbed down that handed its proposal to the app.
    private func thread() throws -> [AskThreadEntry<Row>] {
        let proposalID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let handOffID = try #require(UUID(uuidString: "0E984725-C51C-4BF4-9960-E1C80E27ABA0"))
        return [
            AskThreadEntry(
                question: "Which of my records are from 1969?",
                text: "Two: Abbey Road and Let It Be.",
                answer: AskAnswer(
                    text: "Two: Abbey Road and Let It Be.",
                    matches: [Row(id: "abbey-road", displayTitle: "Abbey Road"), Row(id: "let-it-be", displayTitle: "Let It Be")],
                    tiles: [Row(id: "abbey-road", displayTitle: "Abbey Road")],
                    followUps: ["Which is on vinyl?"],
                    questionKind: "which",
                    isTruncated: false,
                    basis: "Both came out in 1969.",
                    payload: Data(#"{"shelf":2}"#.utf8),
                    proposal: AskProposal(
                        id: proposalID,
                        kind: .perform,
                        title: "Mark Abbey Road as lent",
                        detail: "To Sam, until Friday",
                        actionLabel: "Mark as lent",
                        systemImage: "arrow.up.forward.circle",
                        payload: Data(#"{"id":"abbey-road"}"#.utf8)
                    ),
                    grounding: .toolCall
                ),
                tier: .privateCloud,
                askedAt: Date(timeIntervalSinceReferenceDate: 783_000_000.25),
                summarizedBefore: true,
                feedback: .positive,
                proposalOutcome: .confirmed("Marked Abbey Road as lent."),
                photo: AskQuestionPhoto(label: "A shelf of records", reference: "photo-1"),
                answerSawPhoto: true
            ),
            AskThreadEntry(
                question: "And the oldest?",
                text: "The oldest is",
                answer: nil,
                failureMessage: "You've reached today's limit.",
                failure: .quotaReached(resetDate: Date(timeIntervalSinceReferenceDate: 783_086_400)),
                failureIsRetryable: true,
                stopped: false,
                tier: .onDevice,
                askedAt: Date(timeIntervalSinceReferenceDate: 783_000_060.5)
            ),
            AskThreadEntry(
                question: "Can I add a note to Let It Be?",
                text: "Open it to add one.",
                answer: AskAnswer(
                    text: "Open it to add one.",
                    matches: [Row(id: "let-it-be", displayTitle: "Let It Be")],
                    proposal: AskProposal(
                        id: handOffID,
                        kind: .handOff,
                        title: "Add a note to Let It Be",
                        actionLabel: "Open"
                    )
                ),
                tier: .privateCloud,
                askedAt: Date(timeIntervalSinceReferenceDate: 783_000_120),
                feedback: .negative,
                proposalOutcome: .handedOff("Opened in the app.")
            )
        ]
    }

    /// The list of filings: one chat dated, one written before turns
    /// carried a date, and a chat whose deletion hasn't taken yet.
    private func index() throws -> AskThreadIndex {
        try AskThreadIndex(
            threads: [
                AskThreadSummary(
                    id: #require(UUID(uuidString: "8D7C6B5A-4E3F-4A1B-9C2D-0E1F2A3B4C5D")),
                    title: "Which of my records are from 1969?",
                    startedAt: Date(timeIntervalSinceReferenceDate: 783_000_000.25),
                    updatedAt: Date(timeIntervalSinceReferenceDate: 783_000_120),
                    turnCount: 3
                ),
                AskThreadSummary(
                    id: #require(UUID(uuidString: "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D")),
                    title: "What do I own?",
                    startedAt: nil,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 782_000_000),
                    turnCount: 1
                )
            ],
            deleted: [#require(UUID(uuidString: "F1E2D3C4-B5A6-4978-8695-A4B3C2D1E0F9"))]
        )
    }

    /// Every failure a turn can be written with.
    private let failures: [AskError] = [
        .modelUnavailable(.offline),
        .couldNotAnswer,
        .ungrounded,
        .refused,
        .privateCloudUnreachable,
        .contextTooLarge,
        .photosNotSupported,
        .requestNotSupported,
        .quotaReached(resetDate: Date(timeIntervalSinceReferenceDate: 783_086_400)),
        .quotaReached(resetDate: nil),
        .model(tag: "offline"),
        .stopped
    ]

    /// Every reason the model can be unavailable, as a failure holds it.
    /// Listed rather than taken from `allCases`, so the order of the cases
    /// in the source isn't pinned with them.
    private let unavailable: [AskError] = [
        .modelUnavailable(.appleIntelligenceOff),
        .modelUnavailable(.deviceNotEligible),
        .modelUnavailable(.modelNotReady),
        .modelUnavailable(.systemNotReady),
        .modelUnavailable(.languageNotSupported),
        .modelUnavailable(.notEntitled),
        .modelUnavailable(.offline),
        .modelUnavailable(.unknown)
    ]

    /// A thread as an earlier build wrote it, before turns carried a date,
    /// a verdict, an outcome, a photo or a typed failure, with a proposal
    /// from before proposals had a kind.
    private func olderThread() throws -> [AskThreadEntry<Row>] {
        try [
            AskThreadEntry(
                question: "Which records do I own?",
                text: "Rumours and Abbey Road.",
                answer: AskAnswer(
                    text: "Rumours and Abbey Road.",
                    matches: [Row(id: "rumours", displayTitle: "Rumours")],
                    proposal: AskProposal(
                        id: #require(UUID(uuidString: "3B2A1C0D-9E8F-4A7B-8C6D-5E4F3A2B1C0D")),
                        title: "Mark Rumours as lent",
                        actionLabel: "Mark as lent"
                    )
                ),
                tier: .onDevice
            ),
            AskThreadEntry(question: "And the oldest?", text: "", answer: nil, failureMessage: "Couldn't answer that.")
        ]
    }

    /// The list of filings as an earlier build wrote it, before deletions
    /// were remembered and before a summary had its first turn's date or a
    /// count of turns.
    private func olderIndex() throws -> AskThreadIndex {
        try AskThreadIndex(threads: [
            AskThreadSummary(
                id: #require(UUID(uuidString: "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D")),
                title: "What do I own?",
                startedAt: nil,
                updatedAt: Date(timeIntervalSinceReferenceDate: 782_000_000),
                turnCount: 0
            )
        ])
    }

    /// Every outcome a proposal can be written with, with its line and
    /// without.
    private let outcomes: [AskProposalOutcome] = [
        .confirmed("Marked Abbey Road as lent."),
        .confirmed(nil),
        .handedOff("Opened in the app."),
        .handedOff(nil),
        .declined,
        .failed("The library couldn't be reached."),
        .failed(nil),
        .performing
    ]

    /// Every grounding an answer can be written with. Listed rather than
    /// taken from `allCases`, so the order of the cases in the source isn't
    /// pinned with them.
    private let groundings: [AskGrounding] = [.toolCall, .appRetrieved, .followUp, .nothing]

    @Test func aThreadIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(thread())
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.thread.utf8)))
    }

    @Test func thePinnedFormOfAThreadReadsBackWhole() throws {
        let data = Data(AskOnDiskFormatFixtures.thread.utf8)
        #expect(try JSONDecoder().decode([AskThreadEntry<Row>].self, from: data) == thread())
        // As the thread store reads it, entry by entry, with none dropped.
        let (entries, dropped, _) = try AskThreadStore<Row>.decodeEntries(from: data)
        #expect(entries == (try thread()))
        #expect(dropped == 0)
    }

    @Test func everyFailureIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(failures)
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.failures.utf8)))
    }

    @Test func thePinnedFormOfEveryFailureReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.failures.utf8)
        #expect(try JSONDecoder().decode([AskError].self, from: data) == failures)
    }

    @Test func everyReasonTheModelIsUnavailableIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(unavailable)
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.unavailable.utf8)))
    }

    @Test func thePinnedFormOfEveryReasonTheModelIsUnavailableReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.unavailable.utf8)
        #expect(try JSONDecoder().decode([AskError].self, from: data) == unavailable)
    }

    @Test func everyReasonTheModelCanBeUnavailableIsPinned() {
        // A reason added is written in a form nothing pins until it is here.
        let pinned = Set(unavailable.compactMap { failure -> AskUnavailability? in
            guard case .modelUnavailable(let reason) = failure else { return nil }
            return reason
        })
        #expect(pinned == Set(AskUnavailability.allCases))
    }

    /// A reason a later build wrote, which this build has no case for, reads
    /// back as one it can't name, inside a failure and inside a turn.
    @Test func aReasonALaterBuildWroteReadsAsUnknown() throws {
        #expect(try JSONDecoder().decode(AskUnavailability.self, from: Data(#""pausedForMaintenance""#.utf8)) == .unknown)
        let written = try #require(String(bytes: JSONEncoder().encode(AskError.modelUnavailable(.offline)), encoding: .utf8))
        let later = Data(written.replacingOccurrences(of: "offline", with: "pausedForMaintenance").utf8)
        #expect(try JSONDecoder().decode(AskError.self, from: later) == .modelUnavailable(.unknown))
        let entry = AskThreadEntry<Row>(
            question: "q", text: "", answer: nil, failureMessage: "Paused.", failure: .modelUnavailable(.offline),
            tier: .onDevice
        )
        let turn = try #require(String(bytes: JSONEncoder().encode(entry), encoding: .utf8))
        let read = try JSONDecoder().decode(
            AskThreadEntry<Row>.self, from: Data(turn.replacingOccurrences(of: "offline", with: "pausedForMaintenance").utf8)
        )
        #expect(read.failure == .modelUnavailable(.unknown))
        #expect(read.failureMessage == "Paused.")
    }

    /// An outcome a later build wrote, which this build has no case for,
    /// reads back as a perform nothing has answered, whose card takes no tap,
    /// and so does one that won't decode at all. Read as no outcome, the
    /// newest turn's card would offer again an action that may have run.
    @Test func anOutcomeALaterBuildWroteReadsAsPerforming() throws {
        let proposalID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let entry = AskThreadEntry<Row>(
            question: "Can I lend Abbey Road to Sam?",
            text: "Abbey Road is on your shelf.",
            answer: AskAnswer(
                text: "Abbey Road is on your shelf.",
                proposal: AskProposal(id: proposalID, title: "Mark Abbey Road as lent", actionLabel: "Mark as lent")
            ),
            tier: .privateCloud,
            askedAt: Date(timeIntervalSinceReferenceDate: 783_000_300.5),
            proposalOutcome: .confirmed("Lent to Sam.")
        )
        let turn = try #require(String(bytes: JSONEncoder().encode([entry]), encoding: .utf8))
        #expect(turn.contains(#""confirmed""#))
        let later = Data(turn.replacingOccurrences(of: #""confirmed""#, with: #""scheduled""#).utf8)
        let (entries, dropped, _) = try AskThreadStore<Row>.decodeEntries(from: later)
        #expect(dropped == 0)
        #expect(entries.map(\.proposalOutcome) == [.performing])
        #expect(entries.map(\.question) == [entry.question])
        #expect(entries.first?.answer == entry.answer)

        let damaged = try JSONDecoder().decode(
            AskThreadEntry<Row>.self, from: Data(#"{"question":"q","proposalOutcome":12}"#.utf8)
        )
        #expect(damaged.proposalOutcome == .performing)
        // No outcome written is still none: the card asks.
        for absent in [#"{"question":"q"}"#, #"{"question":"q","proposalOutcome":null}"#] {
            #expect(try JSONDecoder().decode(AskThreadEntry<Row>.self, from: Data(absent.utf8)).proposalOutcome == nil)
        }
    }

    @Test func aThreadAnEarlierBuildWroteReadsBackWhole() throws {
        let data = Data(AskOnDiskFormatFixtures.olderThread.utf8)
        let (entries, dropped, _) = try AskThreadStore<Row>.decodeEntries(from: data)
        #expect(entries == (try olderThread()))
        #expect(dropped == 0)
    }

    @Test func aListOfFilingsAnEarlierBuildWroteReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.olderIndex.utf8)
        #expect(try JSONDecoder().decode(AskThreadIndex.self, from: data) == olderIndex())
    }

    @Test func theListOfFilingsIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(index())
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.index.utf8)))
    }

    @Test func thePinnedFormOfTheListOfFilingsReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.index.utf8)
        #expect(try JSONDecoder().decode(AskThreadIndex.self, from: data) == index())
    }

    @Test func everyProposalOutcomeIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(outcomes)
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.outcomes.utf8)))
    }

    @Test func thePinnedFormOfEveryProposalOutcomeReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.outcomes.utf8)
        #expect(try JSONDecoder().decode([AskProposalOutcome].self, from: data) == outcomes)
    }

    /// A proposal whose perform hadn't returned when its turn was written: an
    /// entry in the form `performing` added, written and read back as it is,
    /// while the forms written before it read as they did
    /// (`aThreadAnEarlierBuildWroteReadsBackWhole`).
    @Test func aProposalInFlightIsWrittenInThePinnedFormAndReadsBack() throws {
        let proposalID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let entry = AskThreadEntry<Row>(
            question: "Can I lend Abbey Road to Sam?",
            text: "Abbey Road is on your shelf.",
            answer: AskAnswer(
                text: "Abbey Road is on your shelf.",
                proposal: AskProposal(id: proposalID, title: "Mark Abbey Road as lent", actionLabel: "Mark as lent")
            ),
            tier: .privateCloud,
            askedAt: Date(timeIntervalSinceReferenceDate: 783_000_300.5),
            proposalOutcome: .performing
        )
        let fixture = Data(AskOnDiskFormatFixtures.proposalInFlight.utf8)
        #expect(try canonical(JSONEncoder().encode([entry])) == canonical(fixture))
        let (entries, dropped, _) = try AskThreadStore<Row>.decodeEntries(from: fixture)
        #expect(entries == [entry])
        #expect(dropped == 0)
    }

    @Test func everyGroundingIsWrittenInThePinnedForm() throws {
        let written = try JSONEncoder().encode(groundings)
        #expect(try canonical(written) == canonical(Data(AskOnDiskFormatFixtures.groundings.utf8)))
    }

    @Test func thePinnedFormOfEveryGroundingReadsBack() throws {
        let data = Data(AskOnDiskFormatFixtures.groundings.utf8)
        #expect(try JSONDecoder().decode([AskGrounding].self, from: data) == groundings)
    }

    @Test func everyGroundingIsPinned() {
        // A grounding added is written in a form nothing pins until it is here.
        #expect(Set(groundings) == Set(AskGrounding.allCases))
    }

    /// An answer written before answers recorded what grounded them reads as
    /// recording nothing, and so does one written with none: the field is
    /// left out, never written as null.
    @Test func anAnswerWrittenWithoutAGroundingReadsAsNone() throws {
        let (older, dropped, _) = try AskThreadStore<Row>.decodeEntries(from: Data(AskOnDiskFormatFixtures.olderThread.utf8))
        #expect(older.first?.answer != nil)
        #expect(older.first?.answer?.grounding == nil)
        #expect(dropped == 0)

        let (current, _, _) = try AskThreadStore<Row>.decodeEntries(from: Data(AskOnDiskFormatFixtures.thread.utf8))
        #expect(current.map { $0.answer?.grounding } == [.toolCall, nil, nil])
        let written = try #require(String(bytes: JSONEncoder().encode(thread()[2]), encoding: .utf8))
        #expect(!written.contains("grounding"))
    }

    /// The JSON value `data` holds, written one way: keys sorted, indented.
    private func canonical(_ data: Data) throws -> String {
        let value = try JSONSerialization.jsonObject(with: data)
        let written = try JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        return try #require(String(bytes: written, encoding: .utf8))
    }
}
