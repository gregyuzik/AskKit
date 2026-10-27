#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Which of the card's two buttons take a tap: the action, and Not now.
@Suite(.timeLimit(.minutes(1))) struct AskConfirmationCardTests {
    /// **Not now does not depend on the host.** A hand-off in a host that
    /// wired no editor has nowhere to go, so its action is off. Switched off
    /// with it, Not now would leave the card under the answer with nothing the
    /// reader could tap, not even to say no.
    @Test func aHandOffWithNowhereToGoCanStillBeDeclined() {
        let taps = AskConfirmationTaps(phase: .awaiting, kind: .handOff, hasDraftOpener: false)
        #expect(!taps.confirms)
        #expect(taps.declines)
    }

    @Test func aHandOffWithAnEditorAndAPerformOfferBoth() {
        let handOff = AskConfirmationTaps(phase: .awaiting, kind: .handOff, hasDraftOpener: true)
        #expect(handOff.confirms && handOff.declines)
        // A perform always has the domain to go to, wired opener or not.
        let perform = AskConfirmationTaps(phase: .awaiting, kind: .perform, hasDraftOpener: false)
        #expect(perform.confirms && perform.declines)
    }

    /// A failure that offers the action again offers Not now with it, and a
    /// hand-off with nowhere to go still offers only Not now.
    @Test func aFailureThatOffersTheActionAgainOffersNotNowWithIt() {
        let perform = AskConfirmationTaps(phase: .failed(nil, canRetry: true), kind: .perform, hasDraftOpener: false)
        #expect(perform.confirms && perform.declines)
        let handOff = AskConfirmationTaps(phase: .failed(nil, canRetry: true), kind: .handOff, hasDraftOpener: false)
        #expect(!handOff.confirms)
        #expect(handOff.declines)
    }

    /// While the app carries it out, neither: the store ignores a decline
    /// then too (`AskConversationStore.declineProposal`).
    @Test func nothingTakesATapWhileTheAppCarriesItOut() {
        let taps = AskConfirmationTaps(phase: .performing, kind: .perform, hasDraftOpener: false)
        #expect(!taps.confirms)
        #expect(!taps.declines)
    }

    /// **A yes whose outcome nobody knows draws the proposal alone.** No
    /// button, since even switched off one reads as something still to do,
    /// and no line, since none of the card's is true of it.
    @Test func aCardWhoseOutcomeIsUnknownDrawsNoButtonsAndNoLine() {
        #expect(!AskProposalPhase.outcomeUnknown.takesATap)
        #expect(!AskConfirmationCard.drawsButtons(for: .outcomeUnknown))
        #expect(AskConfirmationCard.status(for: .outcomeUnknown) == nil)
        let taps = AskConfirmationTaps(phase: .outcomeUnknown, kind: .perform, hasDraftOpener: true)
        #expect(!taps.confirms && !taps.declines)
        // Every other phase with no line keeps its buttons.
        for phase: AskProposalPhase in [.awaiting, .performing, .failed(nil, canRetry: true)] {
            #expect(AskConfirmationCard.drawsButtons(for: phase), "\(phase)")
        }
    }
}

#endif
