#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// When the confirmation card's outcome line is asked to take VoiceOver's
/// focus (`AskConfirmationOutcomeFocus`). The line takes the request once it
/// is in the accessibility tree; these pin when it is made.
@Suite(.timeLimit(.minutes(1))) struct AskConfirmationOutcomeFocusTests {
    private let outcomes: [AskProposalPhase] = [
        .done(nil), .done("Added to your list."),
        .handedOff(nil), .handedOff("Opened the editor."),
        .declined,
        .failed(nil, canRetry: false), .failed("Couldn't save it.", canRetry: false),
        .failed(nil, canRetry: true), .failed("Couldn't save it.", canRetry: true),
        .notDone
    ]

    /// Every outcome a reader's yes or not now waited on asks for the focus.
    @Test func everyOutcomeAReaderWaitedOnAsksForTheFocus() {
        for phase in outcomes {
            #expect(AskConfirmationOutcomeFocus.requested(awaitsOutcome: true, arriving: phase), "\(phase)")
        }
    }

    /// The card still waiting on the reader, or on the app, has no outcome
    /// yet, and one read back with its perform still out has no line to say.
    @Test func aPhaseThatIsNotAnOutcomeAsksForNothing() {
        #expect(!AskConfirmationOutcomeFocus.requested(awaitsOutcome: true, arriving: .awaiting))
        #expect(!AskConfirmationOutcomeFocus.requested(awaitsOutcome: true, arriving: .performing))
        #expect(!AskConfirmationOutcomeFocus.requested(awaitsOutcome: true, arriving: .outcomeUnknown))
    }

    /// **An outcome the reader didn't wait on leaves their focus where it is**:
    /// "Not done" once they asked something else, and a card read back from
    /// disk.
    @Test func anOutcomeNobodyWaitedOnAsksForNothing() {
        for phase in outcomes {
            #expect(!AskConfirmationOutcomeFocus.requested(awaitsOutcome: false, arriving: phase), "\(phase)")
        }
    }

    /// **A request always has a line to take it.** Made for a phase that drew
    /// no line, it would stand until some later phase drew one and then move
    /// the reader's focus without a tap.
    @Test func everyPhaseThatAsksForTheFocusDrawsALineToTakeIt() {
        let phases: [AskProposalPhase] = outcomes + [.awaiting, .performing, .outcomeUnknown]
        for phase in phases where AskConfirmationOutcomeFocus.requested(awaitsOutcome: true, arriving: phase) {
            var drawsALine = AskConfirmationCard.status(for: phase) != nil
            // A failure that offers the action again keeps the buttons and
            // draws its line above them.
            if case .failed(_, canRetry: true) = phase { drawsALine = true }
            #expect(drawsALine, "\(phase)")
        }
    }
}

#endif
