#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// Reading a failed turn back off disk.
///
/// `AskThreadEntry` carries a failure twice: as the typed `AskError`, and as
/// the prose that error produced when the turn was written. Which of the two a
/// restored turn renders is the whole point of storing both, and
/// `AskThreadStore`'s own tests only round-trip the entry. These pin the
/// choice, so a change that quietly replays the stored prose fails here
/// instead of showing the reader a sentence in the language the device had
/// when the turn was written.
@Suite(.timeLimit(.minutes(1))) struct AskTurnRestoreTests {

    /// The line comes from the error, in the reader's language *now* — the
    /// stored sentence is not consulted, and neither is the stored flag.
    @Test func aRestoredFailureRerendersFromTheTypedError() {
        // Both stored fields are deliberately wrong for the case: prose from
        // another locale, and a retryable flag that contradicts the error. If
        // either reaches the turn, this test says which.
        let entry = AskThreadEntry<UIRow>(
            question: "What did I listen to?",
            text: "You played three records —",
            answer: nil,
            failureMessage: "Ikke nok plads til det spørgsmål.",
            failure: .contextTooLarge,
            failureIsRetryable: true
        )

        let turn = AskTurn(entry: entry)

        #expect(turn.failure?.message == AskError.contextTooLarge.errorDescription)
        #expect(turn.failure?.message != entry.failureMessage)
        #expect(turn.failure?.isRetryable == false)
        // Carried, not consumed — a second restore re-renders again.
        #expect(turn.failure?.error == .contextTooLarge)
        // House rule 5: the prose the turn had already written survives.
        #expect(turn.text == "You played three records —")
    }

    /// The fallback, for an entry stored with no typed error: the stored
    /// sentence is all there is.
    @Test func aFailureWithNoTypedErrorReplaysItsStoredProse() {
        let entry = AskThreadEntry<UIRow>(
            question: "What did I listen to?",
            text: "",
            answer: nil,
            failureMessage: "Couldn't answer that just now.",
            failure: nil,
            failureIsRetryable: true
        )

        let turn = AskTurn(entry: entry)

        #expect(turn.failure?.message == "Couldn't answer that just now.")
        #expect(turn.failure?.isRetryable == true)
        #expect(turn.failure?.error == nil)
    }

    /// A request the model couldn't take reads back with its own line, no Try
    /// Again and no coaching: a reworded question or a starter goes to the
    /// same model with the same request, and fails the same way. The flag
    /// stored beside a typed error never decides.
    @Test func aRestoredRequestTheModelCantTakeOffersNoTryAgain() {
        let turn = AskTurn(entry: AskThreadEntry<UIRow>(
            question: "Which records do I own?",
            text: "",
            answer: nil,
            failureMessage: "Couldn't answer that just now. Please try again.",
            failure: .requestNotSupported,
            failureIsRetryable: true
        ))
        #expect(turn.failure?.message == AskError.requestNotSupported.errorDescription)
        #expect(turn.failure?.isRetryable == false)
        #expect(AskError.requestNotSupported.isCoached == false)
    }

    /// A stop before the first word reads back as it read when it happened:
    /// the reader's own says so, and one they didn't ask for says the app
    /// couldn't answer. Both keep Try Again.
    @Test func aRestoredStopSaysWhoseItWas() {
        func restored(stoppedByReader: Bool) -> AskTurn<UIRow>.Failure? {
            AskTurn(entry: AskThreadEntry<UIRow>(
                question: "What did I listen to?",
                text: "",
                answer: nil,
                failureMessage: "Ikke nok plads til det spørgsmål.",
                failure: .stopped,
                failureIsRetryable: true,
                stopped: stoppedByReader
            )).failure
        }

        #expect(restored(stoppedByReader: true)?.message == AskAnnouncement.stoppedByReader)
        #expect(restored(stoppedByReader: false)?.message == AskError.stopped.errorDescription)
        #expect(restored(stoppedByReader: true)?.isRetryable == true)
        #expect(restored(stoppedByReader: false)?.isRetryable == true)
    }

    /// The warning beside a failure goes only for the reader's own stop, read
    /// from the turn and not from its line: a stored line from another locale
    /// changes nothing.
    @Test func onlyTheReadersOwnStopDrawsNoWarning() {
        func restored(stoppedByReader: Bool, failure: AskError) -> AskTurn<UIRow> {
            AskTurn(entry: AskThreadEntry<UIRow>(
                question: "What did I listen to?",
                text: "",
                answer: nil,
                failureMessage: AskAnnouncement.stoppedByReader,
                failure: failure,
                failureIsRetryable: true,
                stopped: stoppedByReader
            ))
        }

        #expect(restored(stoppedByReader: true, failure: .stopped).isReadersStopBeforeAWord)
        #expect(!restored(stoppedByReader: false, failure: .stopped).isReadersStopBeforeAWord)
        #expect(!restored(stoppedByReader: true, failure: .couldNotAnswer).isReadersStopBeforeAWord)
        #expect(AskFailureRow.glyph(readerStopped: true) == nil)
        #expect(AskFailureRow.glyph(readerStopped: false) != nil)
    }

    /// A turn that failed cleanly, with no prose written before it did.
    @Test func aRestoredTurnWithNoFailureCarriesNone() {
        let entry = AskThreadEntry<UIRow>(
            question: "What did I listen to?",
            text: "Three records.",
            answer: nil
        )

        #expect(AskTurn(entry: entry).failure == nil)
    }
}

/// The comparison the thread skips a row on.
///
/// `AskTurn ==` is the thread's skip contract, not a convenience: the thread
/// wraps each `AskThreadRow` in `.equatable()`, so a field the comparison
/// leaves out is a row that draws the old value and goes on drawing it. These
/// pin a field the row draws from, and make the next stored property anyone
/// adds fail here until they have decided which side of the line it is on.
@Suite(.timeLimit(.minutes(1))) struct AskTurnEqualityTests {

    private func turn() -> AskTurn<UIRow> {
        AskTurn(question: "What did I listen to?", origin: .typed)
    }

    /// The hairline above a recapped turn. The store sets this on a turn already
    /// in the thread, on `.summarized`, which the engine sends before the model
    /// has produced a word, so an uncompared flag would leave the hairline
    /// waiting on the first token: seconds of waiting, on the cloud tier.
    @Test func aRecapIsAChangeTheThreadCanSee() {
        // A copy of the same turn, never a second one: `turn()` mints a fresh
        // `id` each call, and two ids differing would carry this on its own
        // whatever the flag did.
        let before = turn()
        var recapped = before
        #expect(before == recapped)

        recapped.summarizedBefore = true

        #expect(before != recapped)
    }

    /// Every stored property there is, so that adding one fails here rather than
    /// quietly joining the five the comparison leaves out.
    ///
    /// Those five are `question`, `origin`, `askedAt` and `photoImage`, which
    /// are fixed when the turn is made, so its `id` stands for them, and
    /// `parsed`, which moves only when `text` moves; `AskTurn ==` carries the
    /// reasoning. Everything else in this list is compared, and a name arriving
    /// here is a decision to make, not a line to add.
    @Test func everyStoredPropertyIsAccountedFor() {
        let found = Set(Mirror(reflecting: turn()).children.compactMap(\.label))

        #expect(found == [
            "id", "question", "origin", "askedAt", "photo", "photoImage", "scope",
            "tier", "activity", "text", "rowsRead", "answer", "failure",
            "stopped", "summarizedBefore", "revision", "feedback",
            "proposalOutcome", "isPerformingProposal", "answerSawPhoto",
            "parsed", "chunks"
        ])
    }
}

#endif
