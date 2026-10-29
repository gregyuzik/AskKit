#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// What the card under a proposing answer shows
/// (`AskConversationStore.proposalPhase(for:)`).
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskProposalPhase: Equatable, Sendable {
    /// Waiting for the reader: the action, and Not now.
    case awaiting
    /// The reader confirmed and the app is carrying it out.
    case performing
    /// Carried out. The app's line, or nil for "That's done".
    case done(String?)
    /// The reader confirmed a hand-off and the app opened its own editor. The
    /// app's line, or nil for a generic one. It never becomes `done`: what the
    /// reader does in the editor never comes back.
    case handedOff(String?)
    /// The reader said not now.
    case declined
    /// The app couldn't carry it out. The app's line, or nil for a generic
    /// one. `canRetry` holds while the turn is the newest and nothing else is
    /// being asked, and the action is then offered again.
    case failed(String?, canRetry: Bool)
    /// Left unanswered when the reader asked something else.
    case notDone
    /// The reader confirmed, and nothing says what came of it: the app was
    /// asked to carry it out and quit before it said, so the turn was read
    /// back with the perform still out (`AskProposalOutcome.performing`). It
    /// takes no tap, since confirmed again it could be done twice, and the
    /// card draws the proposal alone, with no buttons and no line.
    case outcomeUnknown

    /// Whether the card's buttons do anything.
    public var takesATap: Bool {
        switch self {
        case .awaiting: true
        case .failed(_, let canRetry): canRetry
        case .performing, .done, .handedOff, .declined, .notDone, .outcomeUnknown: false
        }
    }
}

/// The card under an answer that offers to do something: what it would do,
/// and the reader's yes or not now.
///
/// **Nothing here acts.** The buttons call back, the store asks the domain,
/// and the card shows what came of it. The title and detail are the app's own
/// words about its own rows (`AskProposal`), drawn verbatim.
///
/// **Confirming forks on the proposal's kind, and the fork is here rather than
/// in the store.** A `.perform` goes to `AskDomain.perform(_:)` by way of
/// `onConfirm`. A `.handOff` never reaches the domain: it opens the host's
/// editor through `askDraftOpener`, which is an environment value, and
/// `AskConversationStore.confirmProposal` runs in a task that has no
/// environment to read it from. For the same reason the enabling test is here
/// too: `AskProposalPhase.takesATap` can't see whether a host wired an opener,
/// so a hand-off with nowhere to go has its action disabled rather than
/// offering a tap that does nothing. Not now stays live: saying no needs
/// nowhere to go (`AskConfirmationTaps`).
///
/// **Content, so `AskAnswerCard`**: a fill and a hairline, never glass.
///
/// **The status line keeps the buttons' room.** Once there is nothing left to
/// tap, the buttons leave and the line takes the height they had, so a card
/// that settles above the question the reader has just asked does not move
/// the thread under them. They leave rather than fade: a button at zero
/// opacity is still in the accessibility tree, and VoiceOver still lands on
/// it. Only a failure that offers the action again adds a line, and only on
/// the newest turn, at the foot of the thread. A card whose outcome is unknown
/// has neither, and is read back that way rather than settling into it.
struct AskConfirmationCard: View {
    let proposal: AskProposal
    let phase: AskProposalPhase
    let accent: Color
    /// Whether the reader said yes or not now on this card and is waiting on
    /// what came of it, so the outcome line takes VoiceOver's focus once it
    /// is there (`AskConversationStore.proposalOutcomeFocus`). The store's
    /// rather than this card's: a question asked meanwhile drops it, and a
    /// card rebuilt while the app worked still takes it.
    let awaitsOutcome: Bool
    let onConfirm: () -> Void
    /// The host's editor is open; the turn records that and nothing more.
    let onHandOff: () -> Void
    let onDecline: () -> Void
    /// The outcome line has been asked to take the focus `awaitsOutcome`
    /// waited for, so the store can let the request go.
    let onOutcomeFocused: () -> Void
    /// VoiceOver's focus has landed on the outcome line, which VoiceOver
    /// reads then, handed the line's words (`AskSpeechLedger`).
    let onOutcomeHeard: (String) -> Void

    /// Where a hand-off goes. Nil in a host that wired none, which disables
    /// the action rather than dropping the reader's tap.
    @Environment(\.askDraftOpener) private var draftOpener

    /// How tall the buttons were while they were shown.
    @State private var buttonsHeight: CGFloat?
    /// Whether the outcome has come and its line is to take VoiceOver's focus:
    /// a request that the line, once it is in the accessibility tree, takes
    /// and clears.
    @State private var focusesOutcome = false
    /// VoiceOver's focus on the outcome line.
    @AccessibilityFocusState private var outcomeIsFocused: Bool

    /// Which of the two buttons take a tap.
    private var taps: AskConfirmationTaps {
        AskConfirmationTaps(phase: phase, kind: proposal.kind, hasDraftOpener: draftOpener != nil)
    }

    /// The reader's yes, down whichever of the two paths this proposal is on.
    /// `onConfirm` asks the store to wait on the outcome for the focus.
    private func confirm() {
        switch proposal.kind {
        case .perform:
            onConfirm()
        case .handOff:
            guard let draftOpener else { return }
            // No focus to move: the host's editor opens over the thread and
            // takes VoiceOver with it, and a focus set behind it would pull
            // the reader back out.
            draftOpener(proposal)
            onHandOff()
        }
    }

    var body: some View {
        AskAnswerCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                if case .failed(let line, canRetry: true) = phase, let retryLine = AskAnnouncement.proposal(.failed(line)) {
                    statusLabel(retryLine, systemImage: "exclamationmark.triangle")
                }
                if let status {
                    statusLabel(status.line, systemImage: status.systemImage)
                        .frame(minHeight: buttonsHeight, alignment: .leading)
                } else if Self.drawsButtons(for: phase) {
                    buttons
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
                }
            }
        }
        .accessibilityIdentifier(AskAccessibility.proposal)
        // **The outcome takes VoiceOver's focus from the button the reader
        // pressed.** That button leaves as the line arrives, and VoiceOver's
        // focus would go wherever the system put it, often the top of the
        // screen. Only for a yes or a not now on this card: an outcome the
        // reader didn't wait on here, such as "Not done" once they asked
        // something else, leaves their focus where it is. A failure that
        // offers the action again keeps the buttons, and its line takes the
        // focus all the same, since it is what the reader is waiting to hear.
        //
        // **A request, taken by the line** (`statusLabel`): the line is
        // inserted in this same update, and a focus set on an element that
        // isn't in the accessibility tree yet goes nowhere. So the line says
        // when the focus has landed on it, and claims the outcome only then
        // (`AskSpeechLedger.Line.proposalOutcome`); a focus that missed leaves
        // it unclaimed, and the screen speaks it a beat later
        // (`AskUnclaimedEnding`), so the reader still hears whether their tap
        // took.
        //
        // **Initial too**, for a card rebuilt while the app worked, such as a
        // lazy row the thread made again: it appears with the outcome already
        // there, and the store still waiting on it.
        .onChange(of: AskConfirmationOutcomeFocus.requested(awaitsOutcome: awaitsOutcome, arriving: phase), initial: true) { _, requested in
            guard requested else { return }
            focusesOutcome = true
            onOutcomeFocused()
        }
    }

    /// One stop for VoiceOver: what the app would do, without the icon's name.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let systemImage = proposal.systemImage {
                Label {
                    title
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else {
                title
            }
            if let detail = proposal.detail {
                Text(verbatim: detail)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(verbatim: proposal.title)
            .fontWeight(.semibold)
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                confirmButton
                declineButton
            }
            VStack(alignment: .leading, spacing: 8) {
                confirmButton
                declineButton
            }
        }
    }

    private var confirmButton: some View {
        Button(action: confirm) {
            Text(verbatim: proposal.actionLabel)
                // **Room to wrap**, as Try Again's label has it
                // (`AskFailureRow`): the app's own words, which at an
                // accessibility size can be wider than the column, where a
                // button can hold its label to one line.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(phase == .performing ? 0 : 1)
                .overlay {
                    if phase == .performing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                // The style's white, or black where white falls under 4.5:1
                // on the host's accent, as it does on the system blue, the
                // spinner with it (`AskOnAccentLabel`).
                .modifier(AskOnAccentLabel(accent: accent))
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(!taps.confirms)
        .accessibilityIdentifier(AskAccessibility.proposalConfirm)
    }

    private var declineButton: some View {
        Button(action: onDecline) {
            Text("Not now", bundle: #bundle, comment: "Button on the card under an Ask answer that offers to do something: leaves it undone.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        // The label is the tint: the style draws it so and ignores a foreground
        // style set on it, and its fill follows the tint too. The default's
        // system blue on its gray is 2.67:1 in light and 3.78:1 in dark, which
        // Apple's audit fails and nearly passes; `.primary` on its gray is
        // 12.56:1 and 8.05:1, and still the quiet button beside the accent's.
        .tint(.primary)
        .disabled(!taps.declines)
        .accessibilityIdentifier(AskAccessibility.proposalDecline)
    }

    /// The line where the buttons were, once there is nothing left to tap.
    private var status: (line: String, systemImage: String)? {
        Self.status(for: phase)
    }

    /// The line a phase draws in place of the buttons, or nil while they stay
    /// or where it has none.
    static func status(for phase: AskProposalPhase) -> (line: String, systemImage: String)? {
        let outcome: (AskProposalOutcome, String)
        switch phase {
        case .done(let line): outcome = (.confirmed(line), "checkmark.circle.fill")
        // Not a checkmark: nothing was saved, and the reader may yet cancel in
        // the editor. The mark says a door opened, which is all that happened.
        case .handedOff(let line): outcome = (.handedOff(line), "arrow.up.forward.app")
        case .declined, .notDone: outcome = (.declined, "minus.circle")
        case .failed(let line, canRetry: false): outcome = (.failed(line), "exclamationmark.triangle")
        // No line it can say: none of the card's is true of an outcome
        // nobody knows, and one saying so is a string still to be written.
        case .awaiting, .performing, .failed, .outcomeUnknown: return nil
        }
        return AskAnnouncement.proposal(outcome.0).map { ($0, outcome.1) }
    }

    /// Whether a phase with no line draws the buttons: every one but an
    /// outcome nobody knows, which draws the proposal alone. Its buttons,
    /// even switched off, would read as something the reader could still do.
    static func drawsButtons(for phase: AskProposalPhase) -> Bool {
        phase != .outcomeUnknown
    }

    /// One element whose label is the line alone: SF Symbols carry names of
    /// their own ("Selected" for the checkmark), which are not what happened.
    private func statusLabel(_ line: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: line)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line))
        .accessibilityFocused($outcomeIsFocused)
        .accessibilityIdentifier(AskAccessibility.proposalOutcome)
        // In a task, once the line is in the accessibility tree
        // (`AskThinkingRow` says why). Not watched under VoiceOver: no
        // simulator runs it.
        .task(id: focusesOutcome) {
            guard focusesOutcome else { return }
            outcomeIsFocused = true
            focusesOutcome = false
        }
        // The focus landing, not the ask: the state reads true only once an
        // assistive technology has moved its focus here (`AskFailureRow`
        // says how that was measured).
        .onChange(of: outcomeIsFocused) { _, focused in
            if focused { onOutcomeHeard(line) }
        }
    }
}

/// Whether a phase is the outcome whose line takes VoiceOver's focus, apart
/// from the view so it can be tested (`AskConfirmationCard.focusesOutcome`).
nonisolated enum AskConfirmationOutcomeFocus {
    /// Whether `phase`, which the card is at, is the outcome of a yes or a not
    /// now the reader gave on it and is waiting on (`awaitsOutcome`).
    ///
    /// **Every phase but the two that wait, and an outcome nobody knows, draws
    /// an outcome line** (`AskConfirmationCard.status(for:)`, or the line
    /// above the buttons of a failure that offers the action again), so a
    /// request made here always has a line to take it. Made for a phase that
    /// drew none, it would sit until the next one did and take the focus from
    /// wherever the reader had gone.
    static func requested(awaitsOutcome: Bool, arriving phase: AskProposalPhase) -> Bool {
        awaitsOutcome && phase != .performing && phase != .awaiting && phase != .outcomeUnknown
    }
}

/// Which of the confirmation card's two buttons take a tap, apart from the view
/// so it can be tested.
nonisolated struct AskConfirmationTaps: Equatable {
    /// The action: while the card takes a tap, and only where confirming has
    /// somewhere to go. A `.perform` always has the domain; a `.handOff` has
    /// only the editor the host wired (`askDraftOpener`).
    let confirms: Bool
    /// Not now: whenever the card takes a tap. **Never on the host's opener.**
    /// Switched off with the action, a hand-off with nowhere to go would leave
    /// the reader nothing to tap, not even to say no.
    let declines: Bool

    init(phase: AskProposalPhase, kind: AskProposalKind, hasDraftOpener: Bool) {
        confirms = phase.takesATap && (kind == .perform || hasDraftOpener)
        declines = phase.takesATap
    }
}

#endif
