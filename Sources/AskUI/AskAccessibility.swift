#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import Foundation

/// Accessibility identifiers for the Ask screen.
///
/// One namespace for every host, so one UI-test recipe drives them all: the
/// demo's smoke tests and a host's own UI tests query these exact strings.
/// Adding one here is cheap; renaming one breaks every host's tests at once.
///
/// Query by these, never by label: labels are translated, and a query by an
/// English label fails in a run in another language, such as one launched
/// with `-AppleLanguages (he)`.
nonisolated public enum AskAccessibility {
    /// The screen's content: the thread or the first screen, with any banner
    /// above it.
    ///
    /// **Query it by identifier alone, never by element type.** Which XCUI type
    /// it lands on follows whatever the thread's container collapses to, and
    /// that moves with the state: a scroll view on the first screen and on a
    /// thread, a plain "other" when the first screen doesn't scroll. Asking for
    /// `otherElements["ask.root"]` passes until a layout change that breaks
    /// nothing, and then fails everywhere at once.
    ///
    /// It sits on that content rather than on the whole screen, so the
    /// composer is outside it: an identifier applied over the composer's
    /// `safeAreaBar` overwrites what the bar's own contents set, and
    /// `ask.send` would report `ask.root`.
    public static let root = "ask.root"
    /// A question's bubble in the thread.
    public static let question = "ask.question"
    /// An answer's prose. Its label says whether it is still arriving.
    public static let answer = "ask.answer"
    /// The composer's circle at the end of the field, whatever it shows: send,
    /// stop, or the glyphs that focus the field and put the keyboard away. Its
    /// label says which.
    public static let send = "ask.send"
    /// The line on the face in the slot (`askComposerSlot`) that raises the
    /// composer. The face's line and circle have identifiers of their own, so
    /// a query for `send` always means the composer's. Its accessory button
    /// keeps the composer's (`attach`, or a host accessory's own).
    public static let slotField = "ask.slot.field"
    /// The circle on the face in the slot, beside that line.
    public static let slotSend = "ask.slot.send"
    /// The photo button, on the domains that accept attachments: the
    /// composer's, and the one on the face in the slot.
    public static let attach = "ask.attach"
    /// The wait row, which stands in for an answer until it has words.
    public static let thinking = "ask.thinking"
    /// The bank of tiles under an answer: one element that contains the
    /// tiles.
    public static let results = "ask.results"
    /// New Chat, over the thread (`AskNewChatButton`).
    ///
    /// Its string is `ask.clear`, which `clear` names too, so a test that
    /// queries either finds the button.
    public static let newChat = "ask.clear"
    /// New Chat, by another name: the same string as `newChat`.
    public static let clear = "ask.clear"
    /// Done, which leads the navigation bar on iOS while the composer's field
    /// is focused, and puts the keyboard away.
    public static let done = "ask.done"
    /// Try Again, under a failure on the newest turn that can be asked again.
    public static let retry = "ask.retry"
    /// The pill: "Jump to latest", shown when the newest text is out of view.
    public static let jumpToLatest = "ask.jumpToLatest"
    /// The starters' bank on the first screen. The three chip banks have
    /// identifiers of their own, so a UI test's "tap a chip" query names the
    /// bank it means.
    public static let starters = "ask.starters"
    /// The follow-ups' bank, under the last answer.
    public static let followUps = "ask.followUps"
    /// The coaching's bank, under a refused or ungrounded failure.
    public static let coaching = "ask.coaching"
    /// "Another pick", first in the follow-up bank under an answer that chose
    /// something. Its own identifier, so a count of the bank's follow-ups can
    /// leave it out.
    public static let anotherPick = "ask.anotherPick"
    /// The basis line under an answer's tiles.
    public static let basis = "ask.basis"
    /// The thumbs-up under an answer.
    public static let feedbackPositive = "ask.feedback.positive"
    /// The thumbs-down under an answer.
    public static let feedbackNegative = "ask.feedback.negative"
    /// The toolbar button that lists the reader's chats, on a domain that
    /// keeps them.
    public static let history = "ask.history"
    /// The list of chats that button opens, in a sheet.
    ///
    /// Its search field has no identifier: SwiftUI's `searchable` takes none,
    /// and an identifier applied beside it lands on the list. It is the
    /// sheet's one search field, so a test reaches it as `searchFields`'
    /// first match, with no label.
    public static let historyList = "ask.history.list"
    /// The sheet's Close.
    public static let historyClose = "ask.history.close"
    /// The chat on screen: leading the sheet's list under a heading of its
    /// own, and in its place among the others in the pane's.
    public static let historyCurrent = "ask.history.current"
    /// An earlier chat, which opens on a tap: every row of the sheet's list
    /// and the pane's but the chat on screen. Each row shares it, and its
    /// label is the chat's first question, the reader's own words.
    public static let historyRow = "ask.history.row"
    /// Delete on an earlier chat: its swipe action and its menu item.
    public static let historyDelete = "ask.history.delete"
    /// Delete All Chats: in the sheet's bar, and beside the pane's title.
    public static let historyDeleteAll = "ask.history.deleteAll"
    /// The button in the dialog Delete All Chats opens, which deletes them.
    public static let historyDeleteAllConfirm = "ask.history.deleteAll.confirm"
    /// The list of chats in the pane beside iPhone Duo's fold, where the
    /// toolbar has no button for them.
    public static let historyPane = "ask.history.pane"
    /// The card under an answer that offers to do something.
    public static let proposal = "ask.proposal"
    /// The card's action.
    public static let proposalConfirm = "ask.proposal.confirm"
    /// The card's Not now.
    public static let proposalDecline = "ask.proposal.decline"
    /// The line that says what came of the card: in place of its buttons once
    /// there is nothing left to tap, or above them while a failure offers the
    /// action again.
    public static let proposalOutcome = "ask.proposal.outcome"
    /// The photo waiting in the composer.
    public static let pendingPhoto = "ask.photo.pending"
    /// The button that takes the waiting photo back out.
    public static let removePhoto = "ask.photo.remove"
    /// The photo above a question asked with one.
    public static let questionPhoto = "ask.question.photo"
    /// The line under that question when the answer read only its words.
    public static let photoUnread = "ask.photo.unread"
    /// The composer's text field.
    public static let field = "ask.field"
    /// The question's menu, on its long press: Copy.
    public static let questionCopy = "ask.question.copy"
    /// The question's menu: Copy answer, once the answer has words.
    public static let questionCopyAnswer = "ask.question.copyAnswer"
    /// The question's menu: Edit & Resend.
    public static let questionEdit = "ask.question.edit"
    /// The question's menu: Ask again.
    public static let questionAskAgain = "ask.question.askAgain"
    /// The evidence line under an answer: "From N items", the domain's own
    /// words, or "Not from this app's data". A disclosure where the host
    /// draws the items behind it and the line has some, and a line where it
    /// doesn't.
    public static let evidence = "ask.evidence"
    /// "Don't suggest this", on a starter's or a follow-up's long press.
    public static let declineSuggestion = "ask.chip.decline"
    /// "Try asking", the heading over the first screen's starters.
    public static let tryAsking = "ask.tryAsking"
    /// The nothing-to-ask screen's button, where the host gives it one.
    public static let nothingAction = "ask.nothingAction"
    /// "Show options" on the banner over the thread once Private Cloud
    /// Compute's daily quota is spent.
    public static let quotaShowOptions = "ask.quota.showOptions"
    /// `AskPrivateCloudCard`'s "Show options", once the quota is spent.
    public static let privateCloudShowOptions = "ask.privateCloud.showOptions"
    /// `AskPrivateCloudCard`'s evaluation run, with diagnostics on.
    public static let privateCloudRunEval = "ask.privateCloud.runEval"
    /// `AskPrivateCloudCard`'s share of the evaluation's results.
    public static let privateCloudShareResults = "ask.privateCloud.shareResults"
    /// `AskPrivateCloudCard`'s share of the feedback attachments.
    public static let privateCloudShareFeedback = "ask.privateCloud.shareFeedback"
}

/// The line VoiceOver hears when a turn reaches a terminal state.
///
/// **Every ending gets one**: an answer, an answer the reader stopped, one the
/// deadline cut short, and a failure (house rule 8). A value rather than a
/// view's decision, so a test can pin every path.
///
/// An answer to a question asked with a photo that no model saw says so, as
/// the note under the question does (`AskTurn.answeredWithoutPhoto`): a reader
/// who cannot see that note would otherwise hear "ready" and take the photo to
/// have been read.
///
/// It says nothing for a turn still in flight: a wait row isn't an ending, and
/// announcing one would interrupt the reader mid-question.
nonisolated public enum AskAnnouncement {

    /// The line for `turn`'s ending, or nil when there is no turn or it is
    /// still in flight. A failure is heard as its `message`.
    public static func terminal<Row: AskRow>(for turn: AskTurn<Row>?) -> String? {
        guard let turn, turn.isComplete else { return nil }
        if let failure = turn.failure { return failure.message }
        if turn.answer?.isTruncated == true {
            // The same distinction the note on screen makes: the deadline and
            // a stop both set `isTruncated`, and saying "the time limit
            // stopped it" to someone who tapped Stop is simply untrue.
            return turn.stopped
                ? stoppedByReader
                : String(
                    localized: "Answer cut short",
                    bundle: #bundle,
                    comment: "Note under an Ask answer that was cut short before it finished: by the time limit, or by a stop the reader didn't ask for."
                )
        }
        if turn.answeredWithoutPhoto {
            return String(
                localized: "Answer ready. It read your words only.",
                bundle: #bundle,
                comment: "Spoken by VoiceOver when an Ask answer has finished arriving for a question the reader asked with a photo, and the model that answered did not see the photo: the on-device model reads no photos, and the app can answer on its own. Says in speech what the note under the question says on screen (\"This answer read your words only.\"). \"It\" is the answer; \"your words\" are the words the reader typed."
            )
        }
        return String(
            localized: "Answer ready",
            bundle: #bundle,
            comment: "Spoken by VoiceOver when an Ask answer has finished arriving."
        )
    }

    /// The line for a turn the reader stopped: the note under what it had
    /// written, and the line a turn stopped before its first word shows in
    /// place of a failure's (`AskTurn.Failure`). VoiceOver hears the same.
    static var stoppedByReader: String {
        String(
            localized: "You stopped this answer",
            bundle: #bundle,
            comment: "Note under an Ask answer the reader stopped before it finished."
        )
    }

    /// What came of a proposal, as the card says it and VoiceOver speaks it:
    /// the app's own line where it gave one. Nil for a perform that hasn't
    /// returned (`AskProposalOutcome.performing`): nothing has come of it yet,
    /// and a card read back with it says nothing it can't know.
    public static func proposal(_ outcome: AskProposalOutcome) -> String? {
        switch outcome {
        case .confirmed(let line):
            line ?? String(
                localized: "That's done",
                bundle: #bundle,
                comment: "Line on the card under an Ask answer once the app has done what the answer offered, when the app gave no line of its own. Also spoken by VoiceOver."
            )
        case .handedOff(let line):
            line ?? String(
                localized: "Opened in the app",
                bundle: #bundle,
                comment: "Line on the card under an Ask answer once the reader confirmed and the app opened its own form for them to finish, when the app gave no line of its own. Never says the thing was done: nothing is saved until they finish. Also spoken by VoiceOver."
            )
        case .declined:
            String(
                localized: "Not done",
                bundle: #bundle,
                comment: "Line on the card under an Ask answer when the reader said not now to what it offered, or asked something else instead. Also spoken by VoiceOver."
            )
        case .failed(let line):
            line ?? String(
                localized: "That didn't work",
                bundle: #bundle,
                comment: "Line on the card under an Ask answer when the app could not do what the answer offered. Also spoken by VoiceOver."
            )
        case .performing:
            nil
        }
    }
}

/// What came of a proposal, as VoiceOver hears it. Each outcome is a value of
/// its own, so the same line twice in a row is spoken twice.
nonisolated public struct AskProposalAnnouncement: Equatable, Sendable {
    /// This announcement's identity, new for each one.
    public let id: UUID
    /// What VoiceOver says, as `AskAnnouncement.proposal(_:)` words it.
    public let line: String

    /// An announcement of `line`.
    public init(line: String) {
        id = UUID()
        self.line = line
    }
}

/// What VoiceOver has already been told, so each thing is spoken once however
/// many screens hear it (`AskScreen`).
///
/// **One announcement for every window.** Every `AskScreen` on a store hears a
/// turn end, and an announcement is the app's and not a window's: with two
/// windows on one store (iPad, the Mac, visionOS) each posted its own, and
/// VoiceOver said each line twice or cut the first off. The first screen to
/// claim an ending speaks it, and the rest find it claimed.
///
/// **A line VoiceOver reads as its focus lands claims what it says then, and
/// not when the move is asked for.** A wait row that goes while it has the
/// focus hands it to the failure line (`AskWaitRowHandoff`), and the card moves
/// it to its outcome line after the reader's yes or not now
/// (`AskConfirmationCard`). VoiceOver reads each line as the focus lands, so an
/// announcement of the same words would be heard twice, or cut into that
/// reading. Claimed when the move was asked for, a move that missed left the
/// ending claimed and never spoken (house rule 8). Claimed as it lands, it
/// would come after a claim the screen made as the turn ended, so the screen
/// waits a beat before it speaks a failure or an outcome the reader waited
/// on, and speaks only what no line has claimed by then
/// (`AskUnclaimedEnding`): a line that takes the focus is read once.
nonisolated struct AskSpeechLedger {
    /// Something VoiceOver is told once.
    enum Line: Hashable {
        /// A turn's terminal announcement (`AskAnnouncement.terminal(for:)`).
        case ending(UUID)
        /// The quota banner's line, once each time the quota is spent.
        case quotaReached
        /// What came of a proposal, by its announcement
        /// (`AskConversationStore.proposalAnnouncement`), which is new for each
        /// outcome: a failure retried on the same card is a line of its own.
        case proposalOutcome(UUID)

        /// What an outcome line VoiceOver's focus has landed on claims: the
        /// store's newest announcement, where it says the words the line said,
        /// or nothing. Matched on the words, so an older card's line the reader
        /// passes claims the newest outcome only where it says the same thing,
        /// which they have then heard.
        static func proposalOutcome(heard line: String, newest: AskProposalAnnouncement?) -> Line? {
            guard let newest, newest.line == line else { return nil }
            return .proposalOutcome(newest.id)
        }
    }

    /// How many lines it remembers: enough for every screen to have claimed a
    /// line before it is let go.
    static let capacity = 16

    private(set) var claimed: [Line] = []

    /// Whether `line` is to be spoken now: true the first time it is claimed,
    /// and false after, until it is forgotten or crowded out.
    mutating func claim(_ line: Line) -> Bool {
        guard !claimed.contains(line) else { return false }
        claimed.append(line)
        if claimed.count > Self.capacity { claimed.removeFirst(claimed.count - Self.capacity) }
        return true
    }

    /// Lets `line` be spoken again: the quota's, once the quota is back.
    mutating func forget(_ line: Line) {
        claimed.removeAll { $0 == line }
    }
}

/// The app's one ledger (`AskSpeechLedger`), on the main actor that posts
/// every announcement.
@MainActor enum AskSpeech {
    static var ledger = AskSpeechLedger()
}

#endif
