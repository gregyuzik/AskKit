#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// One exchange on the thread: the question, the answer, everything the answer
/// brought with it, and, on the newest turn, the chips it earned.
///
/// **A type of its own, and `Equatable`, so the thread can skip a row whose
/// values haven't changed.** `AskThreadList`'s body runs again on every
/// streamed snapshot, since `store.turns` changes with each one. SwiftUI skips
/// a leaf whose value compares equal, but a leaf holding closures never
/// compares equal. Built inline, every row would be formed again on every
/// snapshot of the newest turn: each question bubble and its menu, and
/// every host tile in every bank. A thread of thirty turns would pay for thirty
/// rows to draw one. So the row states its own equality, over the values it
/// draws from and not the closures it calls, and the thread wraps it in
/// `.equatable()`.
///
/// **Every value the body reads is a stored property here, and every one of them
/// is compared in `==`. That is the whole contract.** A field added to this type
/// and left out of the comparison doesn't make a slow row: it makes a row that
/// draws the wrong thing and goes on drawing it. `turn` carries the same
/// obligation one level down, through `AskTurn ==`. The exception is the state
/// the row owns, VoiceOver's focus on the wait row and on the prose and the
/// hand-off between them (`waitRowHasVoiceOver`, `proseHasVoiceOver`,
/// `waitRowHandoff`): SwiftUI draws the row again for a change to any of them,
/// whatever `==` says, and nothing outside the row sets them.
///
/// Nothing reaches back into the store for a value either: `AskThreadList`
/// reads each one once and hands it over, because a read through `@Observable`
/// from inside this body would tie every row's drawing to `store.turns` again
/// and leave the comparison nothing to save.
///
/// The closures are the exception. The callbacks are safe because nothing they
/// hold goes stale: the store looks a turn up by its id when they run, or reads
/// only what the turn fixed when it was asked. The host's builders can capture
/// a value, and a change to one reaches a finished row only through
/// `buildersToken`, which the host sets (`AskScreen.buildersDepend(on:)`).
struct AskThreadRow<Domain: AskDomain, Mark: View, Tiles: View, Disclosure: View, Footer: View>: View, Equatable {
    typealias Row = Domain.Row

    // MARK: - What the row draws from

    let turn: AskTurn<Row>
    /// The turn above it, for the date line alone. Compared by id: the row
    /// reads only its `askedAt`, which a turn fixes when it is asked.
    let previous: AskTurn<Row>?
    /// Whether this is the newest turn: only its question can have been a chip
    /// a moment ago, and only its failure offers Try Again and the coaching.
    let isLast: Bool
    /// Whether the turn's failure offers Try Again
    /// (`AskTurn.offersRetry(isNewest:whileThinking:)`).
    var offersRetry = false
    /// Whether the answer's follow-ups are showing under it: the stream has
    /// ended and there is something to offer.
    let showsChips: Bool
    let followUps: [AskStarter]
    let offersAnotherPick: Bool
    /// When the answer these pieces belong to ended, or nil on every turn but
    /// the one that ended most recently (`AskArrival`).
    let arrivalEnding: TimeInterval?
    let offersFeedback: Bool
    let proposalPhase: AskProposalPhase?
    /// Whether the reader is waiting on what came of this turn's proposal,
    /// whose line then takes VoiceOver's focus
    /// (`AskConversationStore.proposalOutcomeFocus`).
    let awaitsProposalOutcome: Bool
    /// Whether the evidence rows are open: what `==` compares, read when the
    /// row was built. `evidenceExpansion` is what the line writes.
    let isEvidenceExpanded: Bool
    /// Whether the wait row takes VoiceOver's focus as it appears: on the
    /// turn Try Again, a follow-up, a coaching starter or Another pick started
    /// (`AskThreadList.waitRowFocus`).
    let focusesWaitRow: Bool
    let accent: Color
    /// The host's spectrum, which the caret is drawn in (`AskSpectrum`).
    var spectrum: AskSpectrum?
    /// The geometry a tapped chip shares with the question it becomes.
    let morph: Namespace.ID

    // MARK: - What it calls

    /// Held rather than read from the store: `domain` is a `let` there, so
    /// `@Observable` doesn't track it, and holding it ties this body to nothing.
    let domain: Domain
    let mark: (Bool) -> Mark
    /// Handed this turn with the rows its answer chose, so a tile that needs
    /// the question has it without reaching back into the store.
    let tiles: (AskTurn<Row>, [Row]) -> Tiles
    let evidenceDisclosure: (AskTurn<Row>) -> Disclosure
    let answerFooter: (AskTurn<Row>) -> Footer
    /// What the builders draw from besides the turn, compared with the values
    /// above: the one way a change the host makes reaches a finished row.
    let buildersToken: AskBuildersToken?
    let onFollowUp: (AskStarter) -> Void
    /// A starter offered under a refused or ungrounded failure, asked through
    /// the store's own `ask(_ starter:)`, which also keeps it from being
    /// offered again in this thread.
    let onCoaching: (AskStarter) -> Void
    let onDecline: (AskStarter) -> Void
    let onRerollPick: () -> Void
    let onRetry: () -> Void
    /// Stops the turn in flight: VoiceOver's Magic Tap on the wait row or on
    /// prose still being written.
    let onStop: () -> Void
    /// The wait row has taken the focus `focusesWaitRow` asked for.
    let onWaitRowFocused: () -> Void
    /// VoiceOver's focus has landed on the failure line, which VoiceOver
    /// reads as it lands, so the screen announces nothing more
    /// (`AskSpeechLedger`): from the wait row, going as the turn ended before
    /// a word, or the reader's own swipe.
    let onFailureTakesFocus: () -> Void
    let onRate: (AskFeedback.Sentiment) -> Void
    let onCopy: (String) -> Void
    /// Copies the answer's words as they stand when it runs, which is what a
    /// bubble SwiftUI has skipped since they grew needs
    /// (`AskEquatableQuestionBubble`).
    let onCopyAnswer: () -> Void
    let onEdit: () -> Void
    let onAskAgain: () -> Void
    /// Whether this turn's evidence rows are open, as a binding into the
    /// screen's set of them (`AskScreen.expandedEvidence`), for the line to
    /// open and close. Made from a key path, so SwiftUI can compare it and the
    /// line isn't built again whenever the row is; left out of `==` with the
    /// callbacks, since `isEvidenceExpanded` carries its value.
    let evidenceExpansion: Binding<Bool>
    let onConfirmProposal: () -> Void
    let onHandOffProposal: () -> Void
    let onDeclineProposal: () -> Void
    /// The proposal's outcome line has asked for the focus
    /// `awaitsProposalOutcome` waited for.
    let onProposalOutcomeFocused: () -> Void
    /// VoiceOver's focus has landed on the proposal's outcome line, handed
    /// the words it read there (`AskSpeechLedger.Line.proposalOutcome`).
    var onProposalOutcomeHeard: (String) -> Void = { _ in }

    // MARK: - What it owns

    /// VoiceOver's focus on the wait row, held here and handed to it because
    /// the row is gone when it would be asked whether it had the focus
    /// (`waitRowHandoff`).
    @AccessibilityFocusState private var waitRowHasVoiceOver: Bool
    /// VoiceOver's focus on the prose, held here for the same reason: a turn
    /// that restarts takes its prose away, and the wait row that comes back
    /// takes the focus the prose had.
    @AccessibilityFocusState private var proseHasVoiceOver: Bool
    /// Who takes VoiceOver's focus from the wait row or the prose that had it
    /// as it went, until they have (`AskWaitRowHandoff`).
    @State private var waitRowHandoff: AskWaitRowHandoff?

    /// The values, and nothing else. The callbacks are left out because
    /// closures can't be compared, and `domain` because it is the store's `let`.
    ///
    /// **`buildersToken` stands in for the host's builders.** SwiftUI can't
    /// compare them either, so a value a builder captures would never reach a
    /// row this comparison has called unchanged. The host names that value
    /// (`AskScreen.buildersDepend(on:)`), a change to it fails this comparison
    /// on every row, and the rows on screen draw again with the new value.
    static func == (lhs: AskThreadRow, rhs: AskThreadRow) -> Bool {
        lhs.turn == rhs.turn
            && lhs.previous?.id == rhs.previous?.id
            && lhs.isLast == rhs.isLast
            && lhs.offersRetry == rhs.offersRetry
            && lhs.showsChips == rhs.showsChips
            && lhs.followUps == rhs.followUps
            && lhs.offersAnotherPick == rhs.offersAnotherPick
            && lhs.arrivalEnding == rhs.arrivalEnding
            && lhs.offersFeedback == rhs.offersFeedback
            && lhs.proposalPhase == rhs.proposalPhase
            && lhs.awaitsProposalOutcome == rhs.awaitsProposalOutcome
            && lhs.isEvidenceExpanded == rhs.isEvidenceExpanded
            && lhs.focusesWaitRow == rhs.focusesWaitRow
            && lhs.accent == rhs.accent
            && lhs.spectrum == rhs.spectrum
            && lhs.morph == rhs.morph
            && lhs.buildersToken == rhs.buildersToken
    }

    var body: some View {
        // The turn, and on the last one the chips its answer earned, inside
        // the row and at the thread's own gap between turns. Inside, the last
        // turn's measured height includes them, so the follow keeps them above
        // the composer with the answer (`AskThreadList`), and they take their
        // arrival from the answer above them.
        VStack(alignment: .leading, spacing: AskScrollFollow.turnSpacing) {
            turnBody
            if showsChips {
                // "Another pick" leads the bank when the answer chose
                // something. A fill, not glass, as everything in the thread
                // is (`AskChipRow.Surface`).
                AskChipRow(
                    starters: followUps, kind: .followUp,
                    identifier: AskAccessibility.followUps,
                    morph: morph,
                    leading: offersAnotherPick ? anotherPick : nil,
                    surface: .fill
                ) {
                    onFollowUp($0)
                } onDecline: {
                    onDecline($0)
                }
                // **After the answer's own pieces, not with them.** The chips
                // carry `askArrival` of their own, and counted from zero they
                // would come up out of their blur in the same breath as the
                // tiles. They are the last wave in reading order, so they
                // start where the answer's pieces stop: `answerBody` spends
                // `evidenceStep + 3` at most, on the confirmation card.
                .environment(\.askArrivalFirstStep, evidenceStep + 4)
            }
        }
        // Whether what this turn brings with it arrives drawn in
        // (`AskArrival`): only on the turn that has just ended, so a restored
        // thread, a chat opened from history and every turn above the newest
        // draw at rest. `lastTerminalTurn` and not "the last turn is complete",
        // which is also true of a thread read back from disk (the store's note
        // on it says why that matters). When it ended rides along, so a row the
        // lazy stack rebuilds later draws its pieces at rest instead of
        // bringing them in again (`AskArrival.liveWindow`).
        //
        // **Set here rather than on the row from outside**, so a change to it is
        // a change to this value: `==` sees it, the body runs again, and the
        // pieces beneath read the new ending. Applied outside `.equatable()` it
        // would be an environment change over a view that had just declared
        // itself unchanged.
        .environment(\.askArrivalEnding, arrivalEnding)
    }

    // MARK: - The turn

    @ViewBuilder
    private var turnBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if AskDateLine.shows(above: turn, after: previous) {
                AskDateLine(date: turn.askedAt)
            }
            if turn.summarizedBefore {
                AskSummarizedMarker()
            }
            // The question and what is said about it, trailing with it: the
            // photo it went with above, and the line under it when the answer
            // read only the words.
            VStack(alignment: .trailing, spacing: 4) {
                AskEquatableQuestionBubble(
                    question: turn.question,
                    accent: accent,
                    // Only the newest turn, only while it is in flight, and only
                    // one a chip could have become. `AskChipMorph.matches` says
                    // why each is load-bearing.
                    morph: AskChipMorph.matches(turn, isNewest: isLast) ? morph : nil,
                    photo: turn.photo,
                    photoImage: turn.photoImage,
                    photoThumbnail: AskQuestionThumbnail.loader(for: domain),
                    // Not until there is prose to copy, which keeps the item out
                    // of the menu on a turn still waiting for its first words
                    // or one that failed before writing anything.
                    hasAnswerText: !turn.text.isEmpty,
                    onCopy: { onCopy(turn.question) },
                    onCopyAnswer: onCopyAnswer,
                    onEdit: onEdit,
                    onAskAgain: onAskAgain
                )
                .equatable()
                if turn.answeredWithoutPhoto {
                    AskPhotoUnreadNote()
                }
            }
            answerBody
        }
    }

    /// The step the rest of the answer arrives on (`AskArrival`), in reading
    /// order. The host's tiles count from 0, and the lines under them start a
    /// step behind the first tile rather than the last: a grid's second row can
    /// still be coming in as the evidence line lands, and a long grid never
    /// holds the line back. With no tiles, the line leads.
    ///
    /// Spelled once, because the chips count from it too.
    private var evidenceStep: Int {
        turn.answer.map { answer in
            answer.tiles.isEmpty ? 0 : (answer.basis == nil ? 1 : 2)
        } ?? 0
    }

    @ViewBuilder
    private var answerBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The wait row shows only while the turn has said nothing. The
            // frame the first words land, it gives way to prose.
            if turn.showsWaitRow {
                AskThinkingRow(
                    phrase: AskActivityPhrase.text(for: turn.activity, domain: domain),
                    rowsRead: turn.rowsRead.count,
                    accent: accent,
                    hasVoiceOver: $waitRowHasVoiceOver,
                    // Asked for by the control that started the turn, or by
                    // the prose it comes back in place of.
                    takesFocus: focusesWaitRow || waitRowHandoff == .waitRow,
                    onFocusTaken: {
                        if waitRowHandoff == .waitRow { waitRowHandoff = nil }
                        onWaitRowFocused()
                    },
                    onStop: onStop,
                    mark: { mark(true) }
                )
            }
            if !turn.text.isEmpty {
                AskAnswerProse(
                    attributed: turn.parsed,
                    chunks: turn.chunks,
                    isComplete: turn.isComplete,
                    accent: accent,
                    spectrum: spectrum,
                    hasVoiceOver: $proseHasVoiceOver,
                    takesFocus: waitRowHandoff == .prose,
                    onFocusTaken: { waitRowHandoff = nil },
                    onStop: onStop,
                    onCopy: onCopyAnswer
                )
            }
            // Tiles below the prose: the sentence is the answer, the tiles are
            // what it stood on.
            //
            // **`answer.tiles`, never `turn.rowsRead`.** `turn.rowsRead`
            // fills with every row the tools read as they read it, which is
            // the wait row's counter and not a selection, and a stopped turn
            // keeps those rows beside an answer that chose none.
            // Drawn as a grid, it would put forty tiles under a streaming
            // answer and take thirty-seven of them back the moment the model
            // chose its three, a bank assembling itself and vanishing, which
            // house rule 5 forbids. Reading the answer means the grid can't
            // draw before something is chosen, so there is never anything to
            // take back.
            if let chosen = turn.answer?.tiles, !chosen.isEmpty {
                tiles(turn, chosen)
                // Why this pick, between what it chose and how much it read,
                // and only under tiles, so never under a count or a total.
                if let basis = turn.answer?.basis {
                    AskBasisLine(basis)
                        .askArrival(1, as: .line)
                }
            }
            // Attribution on every answer, including one that shows no tiles.
            // A count question ("how many records do I own?") reads a hundred
            // rows and shows none of them, and it is exactly the answer a
            // reader most wants the basis for. An answer nothing grounded
            // says so, and the domain may word the line or leave it out
            // (`AskEvidenceLine`).
            //
            // **Inserted with the answer**, though before one the line has
            // nothing to say and draws nothing anyway. A piece that is
            // already on screen when its turn ends counts as drawn at rest and
            // never arrives, so a line standing empty from the question
            // onwards would be the one part of the answer that popped.
            if turn.answer != nil {
                evidenceRow
                    .askArrival(evidenceStep, as: .line)
            }
            if turn.answer?.isTruncated == true, turn.failure == nil {
                AskTruncatedNote(byReader: turn.stopped)
                    .askArrival(evidenceStep + 1, as: .line)
            }
            if let failure = turn.failure {
                // **Try Again and the coaching only on the newest turn**, as
                // the follow-ups are. Try Again on an older failure would stop
                // the turn streaming below it, and either take that turn out
                // of the middle of the thread, if it drew nothing, or ask its
                // question again at the thread's foot, far below the prose it
                // drew and kept. The store does nothing for one
                // (`AskConversationStore.retry`). The line saying what went
                // wrong stays on every turn.
                AskFailureRow(
                    message: failure.message,
                    readerStopped: turn.isReadersStopBeforeAWord,
                    retryable: offersRetry,
                    coaching: isLast ? failure.coaching : [],
                    takesFocus: waitRowHandoff == .failure,
                    onRetry: onRetry,
                    onCoaching: onCoaching,
                    onFocusTaken: { waitRowHandoff = nil },
                    onLineFocused: onFailureTakesFocus
                )
                .askArrival(evidenceStep + 1, as: .line)
            }
            // The disclosure is what the chevron opens, so it draws only while
            // this turn is expanded. A host that supplies none gets no chevron,
            // and its `EmptyView` is drawn as it is, so nothing is ever left
            // shut behind a chevron that isn't there.
            if Disclosure.self == EmptyView.self || isEvidenceExpanded {
                evidenceDisclosure(turn)
            }
            // The footer is always drawn. Its pieces count their steps on from
            // the lines above it.
            answerFooter(turn)
                .environment(\.askArrivalFirstStep, evidenceStep + 1)
            // What the answer offers to do comes last: the reader has read
            // what it found before being asked to act on it. Two steps behind
            // the footer's first piece, which leaves room for a footer of two.
            if let proposal = turn.answer?.proposal, let proposalPhase {
                AskConfirmationCard(
                    proposal: proposal, phase: proposalPhase, accent: accent,
                    awaitsOutcome: awaitsProposalOutcome,
                    onConfirm: onConfirmProposal,
                    onHandOff: onHandOffProposal,
                    onDecline: onDeclineProposal,
                    onOutcomeFocused: onProposalOutcomeFocused,
                    onOutcomeHeard: onProposalOutcomeHeard
                )
                .askArrival(evidenceStep + 3)
            }
        }
        // **A wait row that goes while it has VoiceOver's focus hands it to
        // what replaces it**: the prose, or the failure where the turn ended
        // before a word. Otherwise the focus goes to wherever the system puts
        // it, and a reader waiting on the wait row loses their place on the
        // thread at the first word. **And the prose hands it back** where the
        // turn restarts, a hand-down or a rollover, which takes the prose
        // away and brings the wait row back (`AskTurnEvent.restarted`).
        // Read here, in the update that removes the one that had it, and not
        // from it, which is gone by the time it could be asked. A request, not
        // a focus set: the replacement is inserted in this same update and
        // takes the focus once it is in the accessibility tree
        // (`AskWaitRowHandoff`). Not watched under VoiceOver: no simulator
        // runs it.
        .onChange(of: turn.showsWaitRow) { _, shows in
            waitRowHandoff = shows
                ? AskWaitRowHandoff.returning(proseHadFocus: proseHasVoiceOver, to: turn)
                : AskWaitRowHandoff.successor(hadFocus: waitRowHasVoiceOver, leaving: turn)
        }
    }

    /// The evidence line, with the thumbs at its trailing end once the turn
    /// has an answer to rate.
    ///
    /// **On one line where the two fit, and the thumbs under the line where
    /// they don't.** Side by side, the thumbs take their width first and the
    /// line wraps in what is left, which at the largest text sizes in a
    /// phone's column is a character's width: "From 8 items" a letter a line
    /// down the leading edge. Under it, the line has the column to wrap in.
    @ViewBuilder
    private var evidenceRow: some View {
        if offersFeedback, turn.answer != nil, turn.failure == nil {
            let thumbs = AskFeedbackButtons(selection: turn.feedback, onRate: onRate)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    evidenceLine
                    Spacer(minLength: 0)
                    thumbs
                }
                VStack(alignment: .trailing, spacing: 0) {
                    evidenceLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    thumbs
                }
            }
        } else {
            evidenceLine
        }
    }

    private var evidenceLine: AskEvidenceLine {
        AskEvidenceLine(
            // Asked of the domain here, as the row draws, and not kept on the
            // turn: what it says follows from the answer, which `==` compares
            // through `turn`, and the domain, which is the store's `let`.
            content: turn.answer.flatMap { AskEvidenceLine.Content(answer: $0, domain: domain) },
            // A chevron only where the host supplies an `evidenceDisclosure`,
            // and the line takes it only over rows (`Content.opensOntoRows`).
            // Expansion is per turn and held by the screen
            // (`AskScreen.expandedEvidence`, reached through `AskThreadList`'s
            // binding) rather than the row, whose own state doesn't outlive
            // the lazy stack rebuilding it.
            isExpanded: Disclosure.self == EmptyView.self ? nil : evidenceExpansion
        )
    }

    /// The chip that asks the question again for something else.
    private var anotherPick: AskChipRow.Action {
        AskChipRow.Action(
            title: Text("Another pick", bundle: #bundle, comment: "Chip under an Ask answer that recommended something: asks the same question again for a different recommendation."),
            systemImage: "arrow.trianglehead.2.clockwise",
            hint: Text("Asks for a different pick", bundle: #bundle, comment: "VoiceOver hint on the Another pick chip under an Ask answer."),
            identifier: AskAccessibility.anotherPick,
            perform: onRerollPick
        )
    }
}

extension AskTurn {
    /// Whether the thread draws the wait row for this turn: it has said
    /// nothing and not ended. The frame the first words land, or the turn
    /// ends, it gives way, and it comes back where a restart takes the words
    /// away (`AskWaitRowHandoff`).
    nonisolated var showsWaitRow: Bool {
        !isComplete && text.isEmpty
    }

    /// Whether this turn's failure offers Try Again: one that can be asked
    /// again, on the newest turn, while the store isn't thinking.
    ///
    /// **Not while a question waits to be asked**, for the saved thread to be
    /// read or for the chat to change. It has no turn yet, so the failed turn
    /// is still the newest, and `AskConversationStore.retry` does nothing
    /// until the question has been asked: a Try Again shown then would take
    /// the reader's tap and do nothing with it. A failure stops the store
    /// thinking in the update that writes it, so a turn that has just failed
    /// offers it at once.
    nonisolated func offersRetry(isNewest: Bool, whileThinking isThinking: Bool) -> Bool {
        failure?.retryable == true && isNewest && !isThinking
    }
}

/// Who takes VoiceOver's focus from a wait row that had it as it went, or
/// from the prose a restart takes away (`AskThreadRow.waitRowHandoff`), apart
/// from the view so it can be tested.
///
/// **The element that replaces the one that went, in reading order.** For the
/// wait row, the first word's prose, or, for a turn that ended before one (a
/// failure, or the reader's stop), the failure line. Where a snapshot brings
/// both, the prose: it is first, and the failure is announced anyway (house
/// rule 8). For the prose, the wait row that comes back in its place.
nonisolated enum AskWaitRowHandoff: Equatable {
    case prose
    case failure
    /// The wait row, back on a turn that restarted, which took away the prose
    /// that had the focus.
    case waitRow

    /// Who takes the focus when the wait row leaves `turn`, or nil when no
    /// one does.
    ///
    /// **Nil when the wait row didn't have it.** A reader in the field, or
    /// anywhere else on the thread, is where they chose to be, and the turn
    /// moving on takes nothing from them. Nil too when nothing replaces the
    /// row and so nothing could take the focus.
    static func successor<Row: AskRow>(hadFocus: Bool, leaving turn: AskTurn<Row>) -> Self? {
        guard hadFocus else { return nil }
        if !turn.text.isEmpty { return .prose }
        return turn.failure == nil ? nil : .failure
    }

    /// Who takes the focus when the wait row comes back to `turn`, as a
    /// restart takes its prose away: the wait row, where the prose had it,
    /// or nil.
    ///
    /// **The wait row, so the reader isn't stranded.** A reader on the prose
    /// as Private Cloud Compute drops, or the conversation rolls over, would
    /// otherwise be left wherever the system put the focus, with nothing
    /// spoken until the new attempt ends. On the wait row they hear the turn
    /// start again, and it hands them on at the new attempt's first words.
    /// Nil when the prose didn't have it, for the reason `successor` gives.
    static func returning<Row: AskRow>(proseHadFocus: Bool, to turn: AskTurn<Row>) -> Self? {
        proseHadFocus && turn.showsWaitRow ? .waitRow : nil
    }
}

/// The question bubble as the row draws it, compared on what it draws.
///
/// **The row's body runs on every snapshot of the turn it holds**, since its
/// prose is what grows, and the question above the prose doesn't change once
/// it is asked. Built inline, the bubble (its fill, its menu and the items in
/// it) would be formed again with every snapshot: counted beside the store's
/// `shape`, a turn of 40 snapshots formed 45 bubble bodies inline, and 2
/// compared. It is formed again when the question, its photo, the chip morph,
/// the accent, or whether the answer has words yet changes.
///
/// **So no closure here may hold a value that goes on changing.** A bubble
/// SwiftUI skips keeps the closures it was built with, and "Copy answer" built
/// over `turn.text` would copy the first words of an answer finished long
/// since. `onCopyAnswer` looks the words up when it runs; the others read only
/// what the turn fixed when it was asked: its question, photo and scope.
struct AskEquatableQuestionBubble: View, Equatable {
    let question: String
    let accent: Color
    let morph: Namespace.ID?
    let photo: AskQuestionPhoto?
    let photoImage: CGImage?
    let photoThumbnail: @Sendable (AskQuestionPhoto) async -> CGImage?
    let hasAnswerText: Bool
    let onCopy: () -> Void
    let onCopyAnswer: () -> Void
    let onEdit: () -> Void
    let onAskAgain: () -> Void

    /// The values, and nothing else, as `AskThreadRow ==` is. The thumbnail
    /// loader asks the domain, which is the store's `let`.
    static func == (lhs: AskEquatableQuestionBubble, rhs: AskEquatableQuestionBubble) -> Bool {
        lhs.question == rhs.question
            && lhs.accent == rhs.accent
            && lhs.morph == rhs.morph
            && lhs.photo == rhs.photo
            && lhs.photoImage === rhs.photoImage
            && lhs.hasAnswerText == rhs.hasAnswerText
    }

    var body: some View {
        AskQuestionBubble(
            question: question,
            accent: accent,
            morph: morph,
            photo: photo,
            photoImage: photoImage,
            photoThumbnail: photoThumbnail,
            onCopy: onCopy,
            onCopyAnswer: hasAnswerText ? onCopyAnswer : nil,
            onEdit: onEdit,
            onAskAgain: onAskAgain
        )
    }
}

#endif
