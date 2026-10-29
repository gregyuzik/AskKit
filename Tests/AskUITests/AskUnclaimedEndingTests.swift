#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// When the screen speaks an ending a line on the thread may have spoken
/// first (`AskUnclaimedEnding`): a failure and a proposal's outcome after a
/// beat, and only where no line has claimed them by then.
///
/// **No test waits out the beat.** Each hands the wait a sleep of its own,
/// which does what a line VoiceOver's focus lands on, or another window's
/// screen, would do meanwhile. Whether a second outlasts VoiceOver's move to a
/// line isn't reachable from a test, or from a simulator, which runs no
/// VoiceOver.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskUnclaimedEndingTests {
    /// A ledger of the test's own, since the app's (`AskSpeech.ledger`) is one
    /// for the whole process and every test.
    private final class Ledger {
        var ledger = AskSpeechLedger()
        /// The waits the screen asked to sleep through.
        var sleeps: [Duration] = []

        func claim(_ line: AskSpeechLedger.Line) -> Bool {
            ledger.claim(line)
        }
    }

    /// How many times the screen speaks `line` after `wait`, with `meanwhile`
    /// run while it waits.
    private func timesSpoken(
        _ line: AskSpeechLedger.Line,
        after wait: Duration,
        in ledger: Ledger,
        stands: Bool = true,
        meanwhile: () -> Void = {}
    ) async -> Int {
        var spoken = 0
        await AskUnclaimedEnding.speak(
            line, after: wait,
            sleep: { duration in
                ledger.sleeps.append(duration)
                meanwhile()
            },
            claim: { ledger.claim($0) },
            stands: { stands },
            announce: { spoken += 1 }
        )
        return spoken
    }

    private func waiting() -> AskTurn<UIRow> {
        AskTurn<UIRow>(question: "What's the oldest?", origin: .typed)
    }

    private func failed() -> AskTurn<UIRow> {
        var turn = waiting()
        turn.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", isRetryable: true)
        return turn
    }

    // MARK: A turn's ending

    /// **A beat for a failure, whose line may take VoiceOver's focus from the
    /// wait row and claim it, and none for anything else**, which no line
    /// claims: an answer, and one the reader stopped with its prose kept.
    @Test func aFailureWaitsABeatAndEveryOtherEndingSpeaksAtOnce() {
        #expect(AskUnclaimedEnding.beat > .zero)
        #expect(AskUnclaimedEnding.wait(before: failed()) == AskUnclaimedEnding.beat)

        var stopped = waiting()
        stopped.stopped = true
        stopped.failure = AskTurn<UIRow>.Failure(
            message: AskAnnouncement.stoppedByReader, isRetryable: true, error: .stopped
        )
        #expect(AskUnclaimedEnding.wait(before: stopped) == AskUnclaimedEnding.beat)

        var answered = waiting()
        answered.settle(AskAnswer(text: "Kind of Blue.", matches: [UIRow("Kind of Blue")]), at: 0)
        #expect(AskUnclaimedEnding.wait(before: answered) == .zero)

        var cutShort = waiting()
        cutShort.write("Going by what you own,", at: 0)
        cutShort.stopped = true
        cutShort.settle(AskAnswer(text: "Going by what you own,", matches: [], isTruncated: true), at: 1)
        #expect(cutShort.failure == nil)
        #expect(AskUnclaimedEnding.wait(before: cutShort) == .zero)
    }

    /// **The interim double, gone.** A failure line that takes the focus from
    /// the wait row during the beat claims the ending as VoiceOver reads it,
    /// and the screen says nothing over it.
    @Test func aFailureLineVoiceOverLandsOnDuringTheBeatIsNotSpokenAgain() async {
        let ledger = Ledger()
        let turn = failed()
        let spoken = await timesSpoken(
            .ending(turn.id), after: AskUnclaimedEnding.wait(before: turn), in: ledger
        ) {
            _ = ledger.claim(.ending(turn.id))
        }
        #expect(spoken == 0)
        #expect(ledger.sleeps == [AskUnclaimedEnding.beat])
    }

    /// **House rule 8's silent case, closed.** A focus move that missed
    /// claims nothing, and the screen speaks the failure once the beat is
    /// over.
    @Test func aFailureNoLineClaimedIsSpokenAfterTheBeat() async {
        let ledger = Ledger()
        let turn = failed()
        let spoken = await timesSpoken(.ending(turn.id), after: AskUnclaimedEnding.wait(before: turn), in: ledger)
        #expect(spoken == 1)
        #expect(ledger.sleeps == [AskUnclaimedEnding.beat])
        #expect(ledger.ledger.claimed == [.ending(turn.id)])
    }

    /// An answer's ending isn't held for a beat nobody needs.
    @Test func anEndingNoLineClaimsIsSpokenWithoutAWait() async {
        let ledger = Ledger()
        let spoken = await timesSpoken(.ending(UUID()), after: .zero, in: ledger)
        #expect(spoken == 1)
        #expect(ledger.sleeps.isEmpty)
    }

    /// Two windows' screens on one store each hear the ending, and it is
    /// spoken once.
    @Test func twoScreensSpeakAnEndingOnce() async {
        let ledger = Ledger()
        let id = UUID()
        let first = await timesSpoken(.ending(id), after: AskUnclaimedEnding.beat, in: ledger)
        let second = await timesSpoken(.ending(id), after: AskUnclaimedEnding.beat, in: ledger)
        #expect(first + second == 1)
    }

    /// An ending New Chat or another chat took off the screen during the
    /// beat is neither spoken nor claimed.
    @Test func anEndingThatLeftTheScreenDuringTheBeatIsNotSpoken() async {
        let ledger = Ledger()
        let spoken = await timesSpoken(.ending(UUID()), after: AskUnclaimedEnding.beat, in: ledger, stands: false)
        #expect(spoken == 0)
        #expect(ledger.ledger.claimed.isEmpty)
    }

    // MARK: A proposal's outcome

    /// **The outcome the reader waited on at the card**, read in the update it
    /// arrives in, before the card lets the store's request go: a yes, whose
    /// request was made at the tap and whose outcome comes later, and a not
    /// now, whose request and outcome come in one change. Once the card has
    /// let the request go, nothing new is to be spoken.
    @Test func anOutcomeTheReaderWaitedOnIsTheScreensToSpeak() {
        typealias Watch = AskUnclaimedEnding.ProposalWatch
        let turn = UUID()
        let earlier = AskProposalAnnouncement(line: "That's done")
        let done = AskProposalAnnouncement(line: "Lent to Sam")

        let yes = Watch(announcement: earlier, awaitedTurn: turn)
        #expect(AskUnclaimedEnding.outcomeToSpeak(from: yes, to: Watch(announcement: done, awaitedTurn: turn)) == done)

        let notNow = AskProposalAnnouncement(line: "Not done")
        #expect(
            AskUnclaimedEnding.outcomeToSpeak(
                from: Watch(announcement: nil, awaitedTurn: nil), to: Watch(announcement: notNow, awaitedTurn: turn)
            ) == notNow
        )

        #expect(
            AskUnclaimedEnding.outcomeToSpeak(
                from: Watch(announcement: done, awaitedTurn: turn), to: Watch(announcement: done, awaitedTurn: nil)
            ) == nil
        )
        #expect(AskUnclaimedEnding.outcomeToSpeak(from: Watch(), to: Watch(awaitedTurn: turn)) == nil)
    }

    /// **An outcome nobody waited on at the card is left alone**: a hand-off,
    /// whose editor takes the focus; a host's own control, which speaks it
    /// itself; and one that lands after a question dropped the request.
    @Test func anOutcomeNobodyWaitedOnAtTheCardIsLeftAlone() {
        typealias Watch = AskUnclaimedEnding.ProposalWatch
        let opened = AskProposalAnnouncement(line: "Opened in the app")
        #expect(AskUnclaimedEnding.outcomeToSpeak(from: Watch(), to: Watch(announcement: opened)) == nil)

        let turn = UUID()
        let asked = Watch(announcement: nil, awaitedTurn: nil)
        #expect(AskUnclaimedEnding.outcomeToSpeak(from: Watch(awaitedTurn: turn), to: asked) == nil)
        let late = AskProposalAnnouncement(line: "That's done")
        #expect(AskUnclaimedEnding.outcomeToSpeak(from: asked, to: Watch(announcement: late)) == nil)
    }

    /// **The card's line claims what it read**, by the store's newest
    /// announcement where the words match (`AskSpeechLedger.Line`), and the
    /// screen says nothing more. A line that missed leaves it to the screen.
    @Test func anOutcomeTheCardsLineReadIsNotSpokenAgain() async throws {
        let outcome = AskProposalAnnouncement(line: "That's done")
        let heard = try #require(AskSpeechLedger.Line.proposalOutcome(heard: outcome.line, newest: outcome))

        let claimedByTheCard = Ledger()
        let spokenOverTheCard = await timesSpoken(
            .proposalOutcome(outcome.id), after: AskUnclaimedEnding.beat, in: claimedByTheCard
        ) {
            _ = claimedByTheCard.claim(heard)
        }
        #expect(spokenOverTheCard == 0)

        let missed = Ledger()
        #expect(await timesSpoken(.proposalOutcome(outcome.id), after: AskUnclaimedEnding.beat, in: missed) == 1)
    }

    /// The same words again, a failure retried on the same card, are an
    /// outcome of their own, and spoken where nothing claimed them.
    @Test func theSameWordsAgainAreAnotherOutcome() async {
        let ledger = Ledger()
        let first = AskProposalAnnouncement(line: "That didn't work")
        let second = AskProposalAnnouncement(line: "That didn't work")
        #expect(await timesSpoken(.proposalOutcome(first.id), after: AskUnclaimedEnding.beat, in: ledger) == 1)
        #expect(await timesSpoken(.proposalOutcome(second.id), after: AskUnclaimedEnding.beat, in: ledger) == 1)
    }
}

#endif
