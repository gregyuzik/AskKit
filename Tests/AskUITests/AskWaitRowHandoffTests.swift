#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Who takes VoiceOver's focus from a wait row that had it as it went, and from
/// the prose a restart takes away (`AskWaitRowHandoff`). The focus itself isn't
/// reachable from a test: these pin which element is asked, and when, and the
/// views take the request once they are in the accessibility tree.
@Suite(.timeLimit(.minutes(1))) struct AskWaitRowHandoffTests {
    private func waiting() -> AskTurn<UIRow> {
        AskTurn<UIRow>(question: "What's the oldest?", origin: .typed)
    }

    private func written() -> AskTurn<UIRow> {
        var turn = waiting()
        turn.write("Going by what you own,", at: 0)
        return turn
    }

    private func failedBeforeAWord() -> AskTurn<UIRow> {
        var turn = waiting()
        turn.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", isRetryable: true)
        return turn
    }

    /// The wait row shows until the turn says something or ends, and the
    /// hand-off is asked when it stops showing.
    @Test func theWaitRowShowsOnlyWhileTheTurnHasSaidNothingAndNotEnded() {
        #expect(waiting().showsWaitRow)
        #expect(!written().showsWaitRow)
        #expect(!failedBeforeAWord().showsWaitRow)
        var answered = waiting()
        answered.settle(AskAnswer(text: "Kind of Blue.", matches: [UIRow("Kind of Blue")]), at: 0)
        #expect(!answered.showsWaitRow)
    }

    /// The first word replaces the wait row with the prose.
    @Test func theFirstWordHandsTheFocusToTheProse() {
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: written()) == .prose)
    }

    /// A turn that ends before a word, by a failure or by the reader's stop,
    /// replaces the wait row with the failure line.
    @Test func aFailureBeforeAWordHandsTheFocusToTheFailureLine() {
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: failedBeforeAWord()) == .failure)

        var stopped = waiting()
        stopped.stopped = true
        stopped.failure = AskTurn<UIRow>.Failure(
            message: AskAnnouncement.stoppedByReader, isRetryable: true, error: .stopped
        )
        #expect(stopped.isReadersStopBeforeAWord)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: stopped) == .failure)
    }

    /// **The prose is first in reading order.** A snapshot that brings words
    /// and a failure at once leaves the failure to its announcement.
    @Test func wordsAndAFailureTogetherHandTheFocusToTheProse() {
        var both = written()
        both.failure = AskTurn<UIRow>.Failure(message: "Try again.", isRetryable: true)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: both) == .prose)
    }

    /// **A reader who wasn't on the wait row keeps their place.** In the field,
    /// or on an earlier turn, they are where they chose to be.
    @Test func aWaitRowWithoutTheFocusHandsOverNothing() {
        #expect(AskWaitRowHandoff.successor(hadFocus: false, leaving: written()) == nil)
        #expect(AskWaitRowHandoff.successor(hadFocus: false, leaving: failedBeforeAWord()) == nil)
        #expect(AskWaitRowHandoff.successor(hadFocus: false, leaving: waiting()) == nil)
    }

    /// With nothing to replace it there is no one to take the focus, so no
    /// request is left standing for an element that never comes.
    @Test func aRowThatIsNotReplacedHandsOverNothing() {
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: waiting()) == nil)
        var wordless = waiting()
        wordless.settle(AskAnswer(text: "", matches: []), at: 0)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: wordless) == nil)
    }

    // MARK: A restart

    /// What `.restarted` does to the turn: the words go, and the turn is
    /// still in flight.
    private func restarted() -> AskTurn<UIRow> {
        var turn = written()
        turn.write("", at: 1)
        return turn
    }

    /// **A restart takes the prose away and brings the wait row back**, so the
    /// reader on the prose is handed to the wait row. Without it they were
    /// left wherever the system put the focus, and heard nothing until the new
    /// attempt ended.
    @Test func aRestartHandsTheProsesFocusBackToTheWaitRow() {
        let turn = restarted()
        #expect(turn.showsWaitRow)
        #expect(AskWaitRowHandoff.returning(proseHadFocus: true, to: turn) == .waitRow)
    }

    /// A reader who wasn't on the prose keeps their place, as one who wasn't
    /// on the wait row does when it goes.
    @Test func aRestartUnderAReaderElsewhereHandsOverNothing() {
        #expect(AskWaitRowHandoff.returning(proseHadFocus: false, to: restarted()) == nil)
    }

    /// No wait row, no one to take the focus: a turn still writing, or one
    /// that has ended.
    @Test func noWaitRowTakesNothingBack() {
        #expect(AskWaitRowHandoff.returning(proseHadFocus: true, to: written()) == nil)
        #expect(AskWaitRowHandoff.returning(proseHadFocus: true, to: failedBeforeAWord()) == nil)
    }

    /// **The hand-off runs both ways for as long as the turn does**: the wait
    /// row the focus came back to hands it on again at the new attempt's first
    /// words, or to the failure line where the new attempt fails before one.
    @Test func theWaitRowTheFocusCameBackToHandsItOnAgain() {
        var again = restarted()
        again.write("From the device,", at: 2)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: again) == .prose)

        var failed = restarted()
        failed.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", isRetryable: true)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: failed) == .failure)
    }

    /// Through the store: Private Cloud Compute wrote, went out, and the
    /// device took the turn over. The prose goes and the wait row is back,
    /// which is what the thread row reads the hand-back from.
    @MainActor
    @Test func aHandDownBringsTheWaitRowBackInThePlaceOfTheProse() async {
        let asker = ScriptedAsker(.init(
            events: [
                .tier(.privateCloud), .partial("Words from the attempt that failed"),
                .restarted(.onDevice), .tier(.onDevice)
            ],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.tier == .onDevice }
        let turn = store.turns.last
        #expect(turn?.showsWaitRow == true)
        #expect(turn.flatMap { AskWaitRowHandoff.returning(proseHadFocus: true, to: $0) } == .waitRow)
        store.stop()
    }
}

#endif
