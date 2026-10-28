#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The thread's rows: the one view on the screen that reads `turns`.
///
/// **A view of its own, so a streamed snapshot re-runs this body and not the
/// screen's.** `turns` changes with every snapshot, and built inside
/// `AskScreen.body`, the rows' read would tie the whole screen (its toolbar,
/// its composer bar, every modifier on it) to each token. The store's `shape`
/// has the measurement. A snapshot re-runs this body instead, each row
/// compares itself (`AskThreadRow`) and only the one being written is built
/// again, and the screen hears the thread's shape and nothing finer.
///
/// It sits inside the screen's `LazyVStack` where an inline `ForEach` would,
/// at no cost: counted the same way, opening a thread of thirty turns built
/// thirty rows through this view, as many as through the `ForEach` inline.
struct AskThreadList<Domain: AskDomain, Mark: View, Tiles: View, Disclosure: View, Footer: View>: View {
    typealias Row = Domain.Row

    let store: AskConversationStore<Domain>
    let follow: AskScrollFollow
    /// Held on the screen and not here or on the row: the screen outlives a
    /// thread the rows are rebuilt for.
    @Binding var expandedEvidence: Set<UUID>
    /// Whether the thread's first turn takes VoiceOver's focus on its wait
    /// row: a starter tapped on the first screen, which goes as the thread
    /// takes its place, with focus to wherever the system put it. Held by the
    /// screen, since this view doesn't exist until the thread does
    /// (`AskScreen.starterFocusesWaitRow`). Cleared once the wait row has it.
    @Binding var firstWaitRowFocus: Bool
    let accent: Color
    /// The host's spectrum, which the caret is drawn in (`AskSpectrum`).
    var spectrum: AskSpectrum?
    let morph: Namespace.ID
    let mark: (Bool) -> Mark
    let tiles: (AskTurn<Row>, [Row]) -> Tiles
    let evidenceDisclosure: (AskTurn<Row>) -> Disclosure
    let answerFooter: (AskTurn<Row>) -> Footer
    /// What the builders draw from besides the turn, when the host names it
    /// (`AskScreen.buildersDepend(on:)`).
    var buildersToken: AskBuildersToken?
    let onCopy: (String) -> Void
    let onEdit: (AskTurn<Row>) -> Void

    /// Where the turn a control under the last turn starts goes, set as the
    /// reader presses it, so that turn's wait row takes VoiceOver's focus.
    /// Try Again goes with its failed turn, and a follow-up, a coaching
    /// starter or Another pick with its bank, and VoiceOver's focus went with
    /// each, to wherever the system put it. Cleared once the wait row has it.
    ///
    /// **By the turn before it, not by its id**, which doesn't exist yet when
    /// the control is pressed: Try Again's turn takes the failed one's place,
    /// after the same turn, and a chip's comes after the turn it was under. A
    /// turn asked later comes after another, so a press whose turn never
    /// showed a wait row hands its focus to nothing.
    @State private var waitRowFocus: AskWaitRowFocus?

    var body: some View {
        // Paired by the store, from one read, and never indexed back into
        // the live array from in here (`pairedTurns`).
        ForEach(store.pairedTurns, id: \.turn.id) { pair in
            // **Every value the row draws from is read here, once, and
            // handed over.** `AskThreadRow` is a type of its own, and
            // `Equatable`, so that a streamed snapshot redraws the turn
            // it belongs to rather than every turn on the thread. The
            // reads have to be on this side of the line: one made from
            // inside the row would tie that row's drawing back to
            // `store.turns` through `@Observable` and leave the
            // comparison nothing to save.
            let isLast = pair.turn.id == store.lastTurnID
            AskThreadRow(
                turn: pair.turn,
                previous: pair.previous,
                isLast: isLast,
                offersRetry: pair.turn.offersRetry(isNewest: isLast, whileThinking: store.isThinking),
                showsChips: isLast && !store.isThinking
                    && (!store.followUps.isEmpty || store.offersAnotherPick),
                // Empty on every turn but the newest, so the follow-ups
                // arriving isn't a change to every row above them.
                followUps: isLast ? store.followUps : [],
                offersAnotherPick: isLast && store.offersAnotherPick,
                arrivalEnding: pair.turn.id == store.lastTerminalTurn
                    ? store.lastTerminalTurnEndedAt : nil,
                offersFeedback: store.offersFeedback,
                proposalPhase: store.proposalPhase(for: pair.turn),
                awaitsProposalOutcome: store.proposalOutcomeFocus == pair.turn.id,
                isEvidenceExpanded: expandedEvidence.contains(pair.turn.id),
                focusesWaitRow: isLast && focusesWaitRow(after: pair.previous?.id),
                accent: accent,
                spectrum: spectrum,
                morph: morph,
                domain: store.domain,
                mark: mark,
                tiles: tiles,
                evidenceDisclosure: evidenceDisclosure,
                answerFooter: answerFooter,
                buildersToken: buildersToken,
                onFollowUp: {
                    waitRowFocus = AskWaitRowFocus(after: pair.turn.id)
                    store.ask($0.text, origin: .followUp)
                },
                onCoaching: {
                    waitRowFocus = AskWaitRowFocus(after: pair.turn.id)
                    store.ask($0)
                },
                onDecline: { store.decline($0) },
                onRerollPick: {
                    waitRowFocus = AskWaitRowFocus(after: pair.turn.id)
                    store.rerollPick(pair.turn)
                },
                onRetry: {
                    waitRowFocus = AskWaitRowFocus(after: pair.previous?.id)
                    store.retry(pair.turn)
                },
                onStop: { store.stop(byReader: true) },
                onWaitRowFocused: {
                    waitRowFocus = nil
                    firstWaitRowFocus = false
                },
                // Claimed for the failure line as VoiceOver's focus lands on
                // it, which is when VoiceOver reads it (`AskSpeechLedger`).
                onFailureTakesFocus: { _ = AskSpeech.ledger.claim(.ending(pair.turn.id)) },
                onRate: { store.rate(pair.turn, $0) },
                onCopy: onCopy,
                onCopyAnswer: { copyAnswer(of: pair.turn.id) },
                onEdit: { onEdit(pair.turn) },
                onAskAgain: { store.askAgain(pair.turn) },
                evidenceExpansion: $expandedEvidence[contains: pair.turn.id],
                // The card's own yes and not now wait on the outcome for
                // VoiceOver's focus; a host's control confirming leaves it.
                onConfirmProposal: { store.confirmProposal(pair.turn, awaitingTheOutcome: true) },
                onHandOffProposal: { store.handOffProposal(pair.turn) },
                onDeclineProposal: { store.declineProposal(pair.turn, awaitingTheOutcome: true) },
                onProposalOutcomeFocused: { store.proposalOutcomeFocused(pair.turn.id) },
                // Claimed as VoiceOver's focus lands on the outcome line, as
                // the failure line's ending is, where the line says what the
                // store's newest announcement says.
                onProposalOutcomeHeard: { line in
                    guard let heard = AskSpeechLedger.Line.proposalOutcome(heard: line, newest: store.proposalAnnouncement) else { return }
                    _ = AskSpeech.ledger.claim(heard)
                }
            )
                .equatable()
                .id(pair.turn.id)
                // What triggers the follow: the layout of the last
                // turn actually growing, which a keyboard, a composer
                // gaining a line and a bar resolving its height can't
                // do. On every turn, with the last-turn test inside the
                // action: a conditional modifier changes the view's
                // identity, and a row that gains one the moment it
                // becomes last is a row that is rebuilt at exactly the
                // wrong time.
                //
                // The chips are inside the row, so they're inside this
                // measurement: what the follow keeps above the composer
                // is the whole of the last turn, chips included, rather
                // than the answer alone.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard pair.turn.id == store.lastTurnID else { return }
                    follow.lastTurnHeightChanged(height)
                }
        }
    }

    private func focusesWaitRow(after previous: UUID?) -> Bool {
        AskWaitRowFocus.takes(waitRowFocus, firstTurn: firstWaitRowFocus, after: previous)
    }

    /// The answer's words as they stand when the reader asks for them, and
    /// not as they stood when the row was built: a question bubble SwiftUI
    /// skips keeps the closure it was made with (`AskEquatableQuestionBubble`).
    /// What goes on the pasteboard is what the reader reads
    /// (`AskTurn.drawnText`), not the model's markdown.
    private func copyAnswer(of id: UUID) {
        guard let turn = store.turns.first(where: { $0.id == id }) else { return }
        let text = turn.drawnText
        guard !text.isEmpty else { return }
        onCopy(text)
    }
}

private extension Set {
    /// Whether the set holds `element`, written by inserting or removing it:
    /// what a key-path binding to one turn's evidence expansion reads and
    /// writes (`AskThreadRow.evidenceExpansion`).
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set {
            if newValue {
                insert(element)
            } else {
                remove(element)
            }
        }
    }
}

extension AskTurn {
    /// The prose as the screen draws it, as plain text: the characters of
    /// `parsed`, which `AskAnswerProse` is handed and VoiceOver reads. The
    /// markdown marks are gone, and a link keeps its label and loses its
    /// destination, which `AskArrivals.parse` strips from every link. A "- "
    /// list stays dashes, as it is drawn.
    nonisolated var drawnText: String {
        String(parsed.characters)
    }
}

/// The turn whose wait row takes VoiceOver's focus, by the turn it comes
/// after: nil for the thread's first (`AskThreadList.waitRowFocus`).
struct AskWaitRowFocus: Equatable {
    let after: UUID?

    /// Whether the wait row of the turn after `previous` takes VoiceOver's
    /// focus: the thread's first turn's where `firstTurn` asks for it (a
    /// starter on the first screen), or the turn `request` names.
    ///
    /// **Nothing without a request.** Compared as `request?.after ==
    /// previous`, a nil request would match the thread's first turn, whose
    /// `previous` is nil too, and every first question would take the focus
    /// from the field it was typed in.
    static func takes(_ request: AskWaitRowFocus?, firstTurn: Bool, after previous: UUID?) -> Bool {
        if previous == nil, firstTurn { return true }
        guard let request else { return false }
        return request.after == previous
    }
}

#endif
