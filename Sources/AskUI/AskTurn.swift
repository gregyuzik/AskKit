#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import CoreGraphics
public import Foundation

/// Where a question came from: what the screen draws for it, and how Try
/// Again asks it again.
///
/// The engine is told only how to run the turn (`AskTurnMode`): Another pick
/// as `.reroll`, and every other origin as `.conversation`.
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskOrigin: Sendable, Equatable {
    /// Typed into the composer.
    case typed
    /// A starter chip, from the first screen or from the coaching under a
    /// failure.
    case starter
    /// A follow-up chip under the last answer, or Ask again.
    case followUp
    /// Sent at once by the host, through
    /// `AskConversationStore.prefill(_:scope:send:)` with `send: true`.
    case prefilled
    /// "Another pick": the last question again, from the button under its
    /// answer, for something other than what the answer chose. The store runs
    /// it as `AskTurnMode.reroll`.
    case reroll

    /// How the engine runs a question from here.
    var mode: AskTurnMode { self == .reroll ? .reroll : .conversation }
}

/// One question and what came back for it.
///
/// **One value per exchange, not one per message.** The question and its answer
/// are the same thing to the thread, which is what makes "the answer above its
/// tiles, both belonging to this question" fall out of the layout for free,
/// and what lets a failure render *beneath* the prose the turn had already
/// written rather than replacing it.
///
/// The store writes the turns on its thread (`AskConversationStore.turns`). A
/// host reads one in the screen's view builders, and only reads it.
nonisolated public struct AskTurn<Row: AskRow>: Identifiable, Sendable {

    /// A turn that ended badly. Kept beside the prose rather than instead of it.
    nonisolated public struct Failure: Equatable, Sendable {
        /// The line the thread shows under the turn, in the reader's language.
        public let message: String
        /// Whether the failure offers Try Again. The thread offers it under
        /// the newest turn only.
        public let isRetryable: Bool
        /// The typed error behind the line, where one is known. Carried so a
        /// restored turn can re-render `message` in the reader's current
        /// language instead of replaying the language they had when it failed.
        public let error: AskError?
        /// The coaching: two starters offered under a refused or ungrounded
        /// failure, so a blocked reader has somewhere to go.
        /// `AskDomain.starters(overview:window:)` supplies them.
        public let coaching: [AskStarter]

        /// A failure that shows `message`, with `error` behind it where one is
        /// known, and `coaching` under it.
        public init(message: String, isRetryable: Bool, error: AskError? = nil, coaching: [AskStarter] = []) {
            self.message = message
            self.isRetryable = isRetryable
            self.error = error
            self.coaching = coaching
        }
    }

    /// The turn's identity: new for every turn made, a turn read back from
    /// disk included.
    public let id: UUID
    /// The question, as asked.
    public let question: String
    /// Where the question came from, which decides how **Try Again** re-asks
    /// it. A turn read back from disk reads `.typed`.
    public let origin: AskOrigin
    /// When the question was asked. A turn read back from an entry that
    /// stored no date takes the time it was read.
    public let askedAt: Date
    /// The photo the reader asked with, as the thread keeps it.
    public let photo: AskQuestionPhoto?
    /// The photo's pixels, while this process has them: what the thumbnail
    /// above the question draws, and what Try Again, Ask again and Another pick
    /// send again. Never written to disk, so a turn read back has none.
    public let photoImage: CGImage?
    /// The part of what the app holds a host asked this from
    /// (`AskConversationStore.prefill(_:scope:send:)`), which Try Again, Ask
    /// again and Another pick ask it with again. Kept as the photo's pixels
    /// are, for this process only: a turn read back has none.
    public let scope: String?

    /// The tier answering, once the engine has chosen one. Nil for an answer
    /// the domain gave without a model.
    public internal(set) var tier: AskTier?
    /// What the turn is doing right now: what its tools report, a restart
    /// (`.restarted`), or the domain's refine pass. The wait row reads it, and
    /// only until the turn's first words, when it gives way to prose, so the
    /// default screen never draws the refine pass, which runs after them.
    public internal(set) var activity: AskActivity?
    /// The prose so far (streamed), then the finished answer's text.
    public internal(set) var text: String = ""
    /// Every row the turn's tools have read so far (`AskTurnEvent.rowsRead`),
    /// which the wait row counts. A `.restarted` empties it, and the answer
    /// leaves it as it is. A turn stopped with prose keeps these as its
    /// answer's `matches`. Not written to disk: a turn read back has none.
    ///
    /// **Never tiles.** The thread draws tiles only from `answer.tiles`, the
    /// rows the model chose, which don't exist until the turn settles.
    public internal(set) var rowsRead: [Row] = []
    /// The finished answer, once it lands, or the prose a stopped turn had
    /// written, kept as a truncated one. Nil while the turn is in flight, and
    /// when it failed.
    public internal(set) var answer: AskAnswer<Row>?
    /// Why the turn ended badly, shown beneath whatever prose it had drawn.
    public internal(set) var failure: Failure?
    /// The reader stopped the turn before it finished: by Stop, by a newer
    /// question, New Chat, or an earlier chat opened over it. What it had said
    /// stays as its answer, and a turn that had said nothing fails as stopped.
    /// A stop the reader didn't ask for, a host's or the engine's, settles the
    /// turn the same way and leaves this false, so the thread says the answer
    /// was cut short rather than that the reader stopped it.
    public internal(set) var stopped = false
    /// The engine started a fresh session with a recap for this turn, and the
    /// thread draws a hairline above it.
    public internal(set) var summarizedBefore = false
    /// How many times a later `.answer` event has replaced the turn's answer.
    /// `AskEngine` sends one per turn, so under it this stays 0. The thread
    /// draws nothing from it; a host's builders may.
    public internal(set) var revision = 0
    /// The reader's thumbs on this answer, if they gave any.
    public internal(set) var feedback: AskFeedback.Sentiment?
    /// What the reader did with the answer's proposal, once they have done
    /// anything: `.performing` from their yes until the app says what came of
    /// it, written to disk with the turn so the yes outlives the screen.
    public internal(set) var proposalOutcome: AskProposalOutcome?
    /// This process is carrying out the proposal the reader confirmed: on the
    /// turn they confirmed it on, and on the same turn read back in its chat
    /// opened again before the app said what came of it. False on a turn read
    /// back where nothing is carrying it out, such as after an app quit, whose
    /// `.performing` then reads as an outcome nobody knows.
    public internal(set) var isPerformingProposal = false
    /// Whether the model answering was sent the photo: the pixels went with the
    /// question and the tier reads photos (`AskTier.readsPhotos`). Set each
    /// time the tier is, so a turn handed down to the on-device model reads
    /// false even though the photo reached Private Cloud Compute first: the
    /// answer on screen isn't the one that saw it.
    public internal(set) var answerSawPhoto = false

    // MARK: - The reveal

    /// The parsed prose the renderer draws.
    var parsed = AttributedString()
    /// Which stretch of it arrived when. Empty once everything has settled,
    /// and on a turn restored from disk, which the renderer paints opaque.
    var chunks: [AskRevealChunk] = []

    /// A turn for `question`, not yet asked: no tier, no prose, no answer.
    /// The store makes the turns on its thread with this.
    public init(
        question: String,
        origin: AskOrigin,
        askedAt: Date = .now,
        photo: AskQuestionPhoto? = nil,
        photoImage: CGImage? = nil,
        scope: String? = nil
    ) {
        self.id = UUID()
        self.question = question
        self.origin = origin
        self.askedAt = askedAt
        self.photo = photo
        self.photoImage = photoImage
        self.scope = scope
    }

    /// Whether the turn has ended: it has an answer or a failure.
    public var isComplete: Bool { answer != nil || failure != nil }

    /// Whether the thread has anything from this turn on screen. A stopped turn
    /// with prose has; one that never got a word has not.
    ///
    /// **Prose, and only prose.** Rows read aren't something the reader can
    /// see. If they counted, a turn stopped after reading forty rows and
    /// before a word would settle as an "answer" with no prose and no tiles,
    /// a bare "From 40 items" where **Try Again** belongs.
    public var hasContent: Bool { !text.isEmpty }

    /// Whether the thread says, under the question, that the answer read only
    /// its words: a photo went with the question and no model that saw it is
    /// answering. Once a tier is chosen, or once the app has answered on its
    /// own, and never before, when nothing is known yet.
    ///
    /// Never taken back once shown: within a turn the tier only moves from
    /// Private Cloud Compute to the on-device model.
    public var answeredWithoutPhoto: Bool {
        photo != nil && !answerSawPhoto && (tier != nil || answer != nil)
    }

    /// Take a snapshot of the prose, so only the new words fade in: what
    /// didn't change keeps its arrival, and chunks older than 0.8 s, all
    /// settled by then, merge into one stretch (`AskArrivals.chunks`).
    mutating func write(_ next: String, at now: TimeInterval) {
        guard next != text else { return }
        let parsedNext = AskArrivals.parse(next)
        chunks = AskArrivals.chunks(chunks, from: parsed, to: parsedNext, at: now)
        parsed = parsedNext
        text = next
    }

    /// The finished answer. It goes through `write` so a last snapshot that
    /// differs from the answer's tidied text still fades rather than pops.
    mutating func settle(_ answer: AskAnswer<Row>, at now: TimeInterval) {
        write(answer.text, at: now)
        self.answer = answer
    }

    /// Whether any of the prose is still drawing in at `now`.
    func isRevealing(at now: TimeInterval) -> Bool {
        AskArrivals.isRevealing(chunks, at: now)
    }

    // MARK: - Disk

    /// The turn as the thread's file keeps it (`AskThreadEntry`). What holds
    /// only for this process stays out, such as the photo's pixels, the scope
    /// and the reveal's timing, and so does the coaching, which the store
    /// derives again.
    public var entry: AskThreadEntry<Row> {
        AskThreadEntry(
            question: question,
            text: text,
            answer: answer,
            failureMessage: failure?.message,
            failure: failure?.error,
            failureIsRetryable: failure?.isRetryable ?? false,
            stopped: stopped,
            tier: tier,
            askedAt: askedAt,
            summarizedBefore: summarizedBefore,
            feedback: feedback,
            proposalOutcome: proposalOutcome,
            photo: photo,
            answerSawPhoto: answerSawPhoto
        )
    }

    /// A turn read back from disk. Already settled: no chunks, so the renderer
    /// draws every run at full opacity whatever the clock says. It gets an id
    /// of its own and reads as `.typed`, with no pixels and no scope.
    public init(entry: AskThreadEntry<Row>) {
        id = UUID()
        question = entry.question
        origin = .typed
        askedAt = entry.askedAt ?? .now
        photo = entry.photo
        photoImage = nil
        scope = nil
        text = entry.text
        parsed = AskArrivals.parse(entry.text)
        answer = entry.answer
        tier = entry.tier
        stopped = entry.stopped
        summarizedBefore = entry.summarizedBefore
        feedback = entry.feedback
        proposalOutcome = entry.proposalOutcome
        answerSawPhoto = entry.answerSawPhoto
        // Re-rendered from the typed error where the thread carries one, so a
        // reader who changed device language doesn't find the old locale's
        // sentence inside a translated screen, and a reworded string reaches
        // turns already on disk. The stored prose is the fallback: an entry
        // stored with no typed error, or one whose case this build doesn't
        // know.
        if let error = entry.failure {
            failure = Failure(
                message: Failure.message(for: error, stoppedByReader: entry.stopped, fallback: entry.failureMessage),
                isRetryable: error.isRetryable,
                error: error
            )
        } else if let message = entry.failureMessage {
            failure = Failure(message: message, isRetryable: entry.failureIsRetryable)
        }
    }
}

nonisolated extension AskTurn {
    /// Whether the turn failed because the reader stopped it before its first
    /// word: the failure says "You stopped this answer"
    /// (`Failure.message(for:stoppedByReader:fallback:)` decides it from the
    /// same two facts), and the thread draws no warning beside it
    /// (`AskFailureRow`).
    var isReadersStopBeforeAWord: Bool {
        stopped && failure?.error == .stopped
    }
}

nonisolated extension AskError {
    /// Whether a failure with this error offers the coaching
    /// (`AskTurn.Failure.coaching`): a refusal or an ungrounded answer, which
    /// asking again won't change, so a blocked reader has somewhere to go.
    var isCoached: Bool {
        self == .refused || self == .ungrounded
    }
}

nonisolated extension AskTurn.Failure {
    /// The line a failure shows for `error`: its own, or `fallback` where it
    /// has none. A stop the reader asked for before the turn had a word says
    /// so ("You stopped this answer", `AskAnnouncement.stoppedByReader`): the
    /// line `AskError.stopped` has of its own says the app couldn't answer,
    /// which isn't what happened, and a reader's stop called something else
    /// is untrue. Try Again stays under it either way.
    static func message(for error: AskError, stoppedByReader: Bool, fallback: String? = nil) -> String {
        if error == .stopped, stoppedByReader { return AskAnnouncement.stoppedByReader }
        return error.errorDescription ?? fallback ?? ""
    }
}

/// `nonisolated`, as the type is: under the package's main-actor default, a
/// conformance spelled without it is main-actor isolated, and a host without
/// AskKit's posture couldn't compare two turns off the main actor.
nonisolated extension AskTurn: Equatable {
    /// **The thread's skip contract, not a convenience.** `AskThreadRow` states
    /// its own equality and the thread wraps it in `.equatable()`, so a turn
    /// that compares equal is a row SwiftUI doesn't rebuild, and a field the
    /// row draws from that this leaves out is a row that goes on drawing the old
    /// value. Add a stored property, add it here.
    ///
    /// Five are left out on purpose:
    ///
    /// - `question`, `origin`, `askedAt` and `photoImage`, which are `let`s,
    ///   fixed when the turn is made, so `id` stands for them. The other
    ///   `let`s, `photo` and `scope`, are compared anyway.
    /// - `parsed`, which moves only when `text` moves: `write(_:at:)` returns
    ///   early unless the prose changed and then sets both, and `init(entry:)`
    ///   is the only other writer. Comparing an `AttributedString` on every row
    ///   of every snapshot to learn what `text` has already said would be the
    ///   expensive half of the work this comparison exists to skip.
    ///
    /// `AskTurnEqualityTests` lists every stored property, so a new one fails
    /// it until someone decides which side of this line it's on.
    public static func == (lhs: AskTurn<Row>, rhs: AskTurn<Row>) -> Bool {
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.rowsRead == rhs.rowsRead
            && lhs.answer == rhs.answer
            && lhs.failure == rhs.failure
            && lhs.tier == rhs.tier
            && lhs.activity == rhs.activity
            && lhs.stopped == rhs.stopped
            && lhs.summarizedBefore == rhs.summarizedBefore
            && lhs.revision == rhs.revision
            && lhs.feedback == rhs.feedback
            && lhs.proposalOutcome == rhs.proposalOutcome
            && lhs.isPerformingProposal == rhs.isPerformingProposal
            && lhs.photo == rhs.photo
            && lhs.scope == rhs.scope
            && lhs.answerSawPhoto == rhs.answerSawPhoto
            && lhs.chunks == rhs.chunks
    }
}

#endif
