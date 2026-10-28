#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation

/// When the screen speaks an ending that a line on the thread may have spoken
/// first, apart from the view so it can be tested: a failure, whose line
/// VoiceOver reads as its focus lands there from the wait row, and what came
/// of a proposal, whose line on the card VoiceOver reads as its focus lands
/// there after the reader's yes or not now (`AskSpeechLedger`).
///
/// **A beat after the ending, and only if nothing has claimed it by then.**
/// Each line claims its ending as VoiceOver's focus lands on it, which is a
/// task and a move of VoiceOver's own after the ending: the line asks for the
/// focus once it is in the accessibility tree (`AskFailureRow`,
/// `AskConfirmationCard`). Claimed a main-actor turn after the ending, as the
/// screen claimed a failure before, the screen spoke a failure line that was
/// about to take the focus, and VoiceOver read it again as the focus landed.
/// Left to the lines alone, as a proposal's outcome was, a move that missed
/// left the ending unspoken (house rule 8). So the screen waits for the move,
/// and speaks what no line has claimed: a second window's screen finds it
/// claimed too.
///
/// **Every other ending at once.** No line claims an answer's ending, so a
/// wait would only make it late.
nonisolated enum AskUnclaimedEnding {
    /// How long the screen leaves a line to claim its ending.
    ///
    /// **Chosen, not measured.** It has to outlast the line's own task, which
    /// asks for the focus once the line is in the accessibility tree, and
    /// VoiceOver's move to it, and neither has been timed: no simulator runs
    /// VoiceOver. Too short, and a line that takes the focus is announced and
    /// then read; too long, and a reader whose focus went elsewhere hears the
    /// ending late.
    static let beat: Duration = .seconds(1)

    /// How long the screen waits before it speaks `turn`'s ending: a beat for
    /// a failure, whose line may take VoiceOver's focus and claim it, and none
    /// for any other ending, which no line claims.
    static func wait<Row: AskRow>(before turn: AskTurn<Row>) -> Duration {
        turn.failure == nil ? .zero : beat
    }

    /// What the screen watches of a proposal's outcome: the store's newest
    /// announcement of one (`AskConversationStore.proposalAnnouncement`), and
    /// the turn whose card the reader said yes or not now on, while they wait
    /// on what comes of it (`AskConversationStore.proposalOutcomeFocus`).
    struct ProposalWatch: Equatable {
        var announcement: AskProposalAnnouncement?
        var awaitedTurn: UUID?
    }

    /// The outcome the screen speaks if the card's line doesn't claim it
    /// within a beat: one that has just come, while the reader waits on it.
    ///
    /// **Read as the outcome arrives.** The card lets the store's request go
    /// once its line has asked for the focus, in an action of the update the
    /// outcome arrives in, so the watch the screen read for that update still
    /// holds the turn the reader waited on. A not now records the request and
    /// the outcome in one change.
    ///
    /// **Nil for an outcome nobody waited on at the card.** A hand-off opens
    /// the host's editor, which takes the focus, and an announcement would
    /// speak over what VoiceOver reads there. A host's own control that
    /// confirms or declines leaves the speaking to the host, which hears
    /// `proposalAnnouncement` itself. And a question asked while the app
    /// worked drops the request: the reader is waiting on their question now,
    /// and the outcome's line on the card is left for them to come back to.
    static func outcomeToSpeak(from old: ProposalWatch, to new: ProposalWatch) -> AskProposalAnnouncement? {
        guard let announcement = new.announcement, announcement != old.announcement,
              new.awaitedTurn != nil else { return nil }
        return announcement
    }

    /// Speaks `line` after `wait`, through `announce`, unless it no longer
    /// stands then or something has claimed it: a line on the thread that
    /// VoiceOver's focus has landed on, or another window's screen.
    ///
    /// - Parameters:
    ///   - sleep: How the wait passes. The screen runs this in a task it never
    ///     cancels, so a later ending, or the screen going, doesn't take this
    ///     one's turn to be spoken. A test passes its own.
    ///   - claim: The app's ledger's claim (`AskSpeech`), or a test's.
    ///   - stands: Whether the ending is still on the screen once the wait is
    ///     over: New Chat, or another chat opening, takes it away, and with it
    ///     the reason to speak it.
    @MainActor static func speak(
        _ line: AskSpeechLedger.Line,
        after wait: Duration,
        sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        claim: (AskSpeechLedger.Line) -> Bool = { AskSpeech.ledger.claim($0) },
        stands: () -> Bool,
        announce: () -> Void
    ) async {
        if wait > .zero { await sleep(wait) }
        guard stands(), claim(line) else { return }
        announce()
    }
}

#endif
