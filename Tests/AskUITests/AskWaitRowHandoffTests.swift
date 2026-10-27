#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Who takes VoiceOver's focus from a wait row that had it as it went
/// (`AskWaitRowHandoff`). The focus itself isn't reachable from a test: these
/// pin which element is asked, and when, and the views take the request once
/// they are in the accessibility tree.
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
        turn.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", retryable: true)
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
            message: AskAnnouncement.stoppedByReader, retryable: true, error: .stopped
        )
        #expect(stopped.isReadersStopBeforeAWord)
        #expect(AskWaitRowHandoff.successor(hadFocus: true, leaving: stopped) == .failure)
    }

    /// **The prose is first in reading order.** A snapshot that brings words
    /// and a failure at once leaves the failure to its announcement.
    @Test func wordsAndAFailureTogetherHandTheFocusToTheProse() {
        var both = written()
        both.failure = AskTurn<UIRow>.Failure(message: "Try again.", retryable: true)
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
}

#endif
