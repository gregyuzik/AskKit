#if os(iOS) || os(macOS) || os(visionOS)

// SPI for `AskPrompt.clampQuestion`, which `prefill` clamps a host's question with.
@_spi(AskKitInternal) import AskCore
import CoreGraphics
import Foundation
import Observation
import os
import Synchronization
#if os(iOS) || os(visionOS)
// For `UIApplication.ProtectedDataDidBecomeAvailableMessage`, the moment a
// thread a locked device couldn't read, or write, can be tried again.
import UIKit
#endif

/// What the store needs from an engine: `AskEngine`, or an engine of a host's
/// own, such as a scripted one for previews and tests.
///
/// **A protocol rather than `AskEngine` outright, so the store is testable
/// without a model.** What the thread shows is decided by what arrives on the
/// event stream: a failure renders beneath the prose the turn had drawn, and a
/// stop settles with that prose as its answer, since nothing shown is taken
/// back (house rule 5). A test that builds the stream by hand pins all of it
/// with a scripted engine and a minimal domain, and never constructs an
/// `AskEngine`, a seam or a model session.
///
/// **What the store relies on:**
/// - `ask` streams one turn's events (`AskTurnEvent`), and the store writes
///   each onto the turn as it arrives:
///   - `.partial` is the whole prose so far, not what was added, and comes
///     only for prose the turn will keep: once the turn is grounded (house
///     rule 2), or from the first token under a policy that keeps answers
///     nothing grounded (`AskGroundingPolicy.notRequired`). The store draws
///     every snapshot it gets.
///   - `.tier` names the tier answering, as `.restarted` does for the one
///     taking over. A turn that never gets one reads as one the domain
///     answered without a model: it is left out of the tail the store hands
///     `resume(from:)`, its thumbs pass `isLatestTurn` false, and the thread
///     says a photo asked with it went unread.
///   - `.rowsRead` is every row read so far, which the wait row counts.
///   - `.restarted` throws away the attempt on screen, and the store clears
///     its prose and the rows it read.
///   - `.answer` settles the turn. A later one replaces it
///     (`AskTurn.revision`).
/// - The stream finishes after `.answer`, or ends by throwing:
///   - an `AskError`, which the turn shows as its failure, with the coaching
///     under a refused or ungrounded one;
///   - `CancellationError`, for a turn stopped from the engine's side, which
///     the turn settles as a stop the reader didn't ask for.
///
///   Anything else thrown is logged by its tag and shown as
///   `AskError.couldNotAnswer`. A stream that finishes with no answer shows
///   the same failure, and logs nothing.
/// - Letting a stream go should stop its turn. The store lets one go on Stop,
///   New Chat, an earlier chat opened and a newer question, and asks the newer
///   question at once, without waiting for the old turn to wind down.
/// - `stop()` stops the turn in flight. `reset()` ends the chat, so a turn
///   from it writes nothing into the next one. New Chat, Delete All and
///   opening an earlier chat call `stop()` and then `reset()`, and ask
///   nothing more until both have returned: a question asked between them
///   would be the turn the reset cancels.
/// - `status` is kept current on the main actor: the tier caption, the
///   can't-serve first screen and the quota banner read it.
/// - `hasKeptConversation` says whether the engine keeps a conversation. The
///   store reads it as each turn ends, after a reset, a restore and a seed,
///   and as it refreshes, and the follow-up chips show only while it is
///   true.
///
/// Seven members are required: `ask(_:origin:)`, `stop()`, `reset()`,
/// `prewarm()`, `refreshStatus()`, `status` and `hasKeptConversation`. The
/// rest have defaults for an engine with none of what they're for: photos,
/// scopes, a limit-increase route, a warm session to drop, a thread to resume
/// and a feedback attachment.
nonisolated public protocol AskAsking<Row>: Sendable {
    /// The domain's row type, which the turn's events carry.
    associatedtype Row: AskRow

    /// Ask a question, streaming the turn's events. The store asks one turn at
    /// a time: before it asks again, it settles the turn on screen and lets
    /// that turn's stream go.
    func ask(_ question: String, origin: AskOrigin) -> AsyncThrowingStream<AskTurnEvent<Row>, any Error>
    /// Ask a question the reader attached photos to. Defaulted: an engine
    /// that reads no photos asks without them when there are none, and fails
    /// a question that has one with `AskError.photosNotSupported` rather than
    /// answering as though it had seen it.
    func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment]
    ) -> AsyncThrowingStream<AskTurnEvent<Row>, any Error>
    /// Ask a question a host asked from one part of what the app holds
    /// (`AskConversationStore.prefill(_:scope:send:)`). Defaulted: an engine
    /// that reads no scopes asks without one, and the question still stands
    /// on its own words.
    func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?
    ) -> AsyncThrowingStream<AskTurnEvent<Row>, any Error>
    /// Stop the turn in flight, if any. The store has already settled the
    /// turn on screen, or emptied the thread, and let its stream go.
    func stop() async
    /// End the chat: the conversation, any warm session and anything resumed
    /// go, a question waiting for the stopped turn stands down, and a turn
    /// still winding down writes nothing into the next chat. Always called
    /// after `stop()`. `hasKeptConversation` reads false after it.
    func reset() async
    /// Warm a session for the next question. The store calls it only once the
    /// reader's question has begun: as they start a draft or first edit one a
    /// host prefilled, and as the screen appears or the app comes back with
    /// their question half-typed.
    /// Called while a young warm session waits, or one is being built, it
    /// should leave that one alone.
    func prewarm() async
    /// Drop a warm session no question took, when the last screen up goes
    /// away, and a warm still being built when it finishes. A kept
    /// conversation stays. Defaulted to nothing, for an engine that warms
    /// nothing.
    func forgetWarmIfEmpty() async
    /// Read every tier's state again into `status`. The store calls it as the
    /// screen appears and as the app comes back to the foreground
    /// (`AskConversationStore.refresh()`).
    func refreshStatus() async

    /// The mirror the screen reads, on the main actor: which tier is next,
    /// why nothing can serve and where the quota stands. An engine that never
    /// updates it leaves the first screen unable to show `.cannotServe`, and
    /// the quota banner with nothing to appear on.
    @MainActor var status: AskModelStatus { get }

    /// Whether a conversation is kept, or a thread's tail waits for the next
    /// session's recap, so a follow-up chip has something to refer to: true
    /// once a model has answered on the chat, or `resume(from:)` has seeded a
    /// tail, and false after `reset()`. The store keeps a copy
    /// (`AskConversationStore.hasKeptConversation`), read as each turn's
    /// stream ends, after `reset()` and `resume(from:)`, and in
    /// `AskConversationStore.refresh()`.
    ///
    /// **Required, and the engine's own.** An engine that never said would
    /// show no follow-up chips, so there is no default. And it is never the
    /// mirror's: the seam, and its mirror, can be shared, and one engine's
    /// reset, such as an evaluation's, would hide another's chips.
    var hasKeptConversation: Bool { get async }

    /// Open Apple's limit-increase route: what Show options does, on the
    /// quota banner and on the settings card (`AskPrivateCloudCard`). The
    /// button shows only while `status.hasLimitIncreaseSuggestion` is true.
    func showLimitIncrease() async

    /// Carry a thread read back from disk, or an earlier chat opened, into
    /// the engine, so the first question asked on it starts a session with a
    /// recap of what it said. The store passes the last three exchanges a
    /// model answered, newest last, right after `reset()` when a chat opens.
    /// Defaulted: an engine with no memory of its own has nothing to seed.
    /// An engine that seeds one reads `hasKeptConversation` true after it.
    func resume(from tail: [AskThreadTail]) async

    /// A reader's thumbs on an answer. `isLatestTurn` is true only for the
    /// newest turn, only when a model answered it, and only while the store
    /// keeps feedback attachments (`AskConversationStore.offersFeedback`): it
    /// is the word to take the session's attachment, which the SDK logs and
    /// serializes as it hands it over, so none is taken that nothing keeps.
    /// Returns the attachment when one could be taken, which the store saves
    /// for the diagnostics row to share. Defaulted to none.
    func recordFeedback(_ feedback: AskFeedback, isLatestTurn: Bool) async -> Data?
}

nonisolated extension AskAsking {
    /// Asks without photos, and fails a question that has one with
    /// `AskError.photosNotSupported`.
    public func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment]
    ) -> AsyncThrowingStream<AskTurnEvent<Row>, any Error> {
        guard images.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: AskError.photosNotSupported) }
        }
        return ask(question, origin: origin)
    }

    /// Asks without the scope.
    public func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?
    ) -> AsyncThrowingStream<AskTurnEvent<Row>, any Error> {
        ask(question, origin: origin, images: images)
    }

    /// Does nothing. An engine with no route to offer leaves
    /// `status.hasLimitIncreaseSuggestion` false, so Show options never
    /// shows.
    public func showLimitIncrease() async {}

    /// Does nothing: an engine that warms nothing has nothing to drop.
    public func forgetWarmIfEmpty() async {}

    /// Does nothing: an engine with no memory of its own has nothing to seed.
    public func resume(from tail: [AskThreadTail]) async {}

    /// Takes no attachment, and returns nil.
    public func recordFeedback(_ feedback: AskFeedback, isLatestTurn: Bool) async -> Data? { nil }
}

/// `AskEngine` meets every requirement with a member of its own, photos and
/// scope included, so none of the defaults apply to it.
extension AskEngine: AskAsking {}

/// The Ask thread: the turns, the turn in flight, and the draft in the composer.
///
/// **One per app, held by the app.** A generic type can't have a `static let
/// shared`, and it shouldn't: the iOS `TabView` keeps a tab alive across
/// switches, but a Mac `NavigationSplitView` rebuilds its detail on every
/// sidebar change, so a thread owned by the view would vanish because the
/// reader glanced at another screen. The app owns one instance for the
/// process; a turn in flight keeps running while the reader is elsewhere, and
/// its answer is there on return. Two alive over one thread, such as one per
/// window, write the same files and lose whichever chat saved first: the
/// second is logged as a fault.
///
/// **Nothing the thread has shown is ever taken back** (house rule 5). A
/// failure renders beneath the prose the turn had already written, and a
/// stopped turn keeps its text as its answer. Every mutation happens here, so
/// the view stays a rendering of this state.
///
/// **One exception: `.restarted`.** A hand-down, or a follow-up that outgrew
/// its window and is asked again on a fresh session, clears the prose the
/// abandoned attempt had drawn, grounded or not. The question is asked again
/// from the start on another model or another session, and the answer it
/// gets is the turn's whole answer, sent as whole snapshots: kept, the old
/// prose would only be swapped out under the reader's eyes at the new
/// attempt's first words, and a Stop before them would keep, as the turn's
/// answer, half of one from an attempt that was thrown away.
@Observable
@MainActor
public final class AskConversationStore<Domain: AskDomain> {
    /// The domain's row type.
    public typealias Row = Domain.Row
    /// One question and what came back for it.
    public typealias Turn = AskTurn<Row>

    /// Every turn on the thread, oldest first, so the turn in flight is last.
    ///
    /// It changes with every streamed snapshot, so a view that needs only
    /// whether there are turns, or which is newest, reads `hasTurns` or
    /// `lastTurnID`, which change only with the thread's shape.
    public private(set) var turns: [Turn] = [] {
        // Runs on every change to the thread, in place or whole: the macro
        // runs it for `update`'s in-place write as for an append. The shape is
        // published only when it moves, and `shape` says why the screen reads
        // that instead.
        didSet { shape = ThreadShape(turns) }
    }
    /// Whether a turn is in flight: from the question until its stream ends,
    /// which is a moment after its answer lands. A question waiting for the
    /// saved thread to be read, or for the chat to change (New Chat, Delete
    /// All Chats, an earlier chat opening), counts. The composer's button is
    /// Stop meanwhile.
    public private(set) var isThinking = false
    /// The composer's text. Lives here so a half-typed question survives a trip
    /// to another screen.
    ///
    /// A host putting a question here goes through `prefill(_:scope:send:)`,
    /// which sets the scope with it: a write of its own keeps whatever scope a
    /// prefill left, unless it empties the field. The reader's own question
    /// beginning here warms a session for it while the screen is up
    /// (`prewarm()`); a prefill alone warms nothing.
    public var draft: String = "" {
        didSet {
            // A draft emptied is a new question, whatever the reader goes on to
            // type: the scope a host left with it goes too.
            if draft.isEmpty { draftScope = nil }
            // The reader's question has begun (typed, or put back by Edit &
            // Resend or by a Stop before it was asked), so warm the session it
            // will run on. Once per question, not per keystroke: only the edge
            // into the reader's own draft warms. A prefill isn't that edge: a
            // link can come from anywhere, and a warm on Private Cloud Compute
            // spends a request of the reader's quota though they sent nothing.
            // Their first edit of it is.
            let wasReaders = draftIsReaders
            draftIsReaders = !draft.isEmpty && !isPrefilling
            if draftIsReaders, !wasReaders, wantsWarm {
                Task { [engine] in await engine.prewarm() }
            }
        }
    }
    /// Whether the draft is the reader's own: typed, edited or put back by
    /// Edit & Resend or a Stop, rather than left by a prefill they haven't
    /// touched.
    /// Only the reader's own draft warms a session.
    @ObservationIgnored private var draftIsReaders = false
    /// True while `prefill(_:scope:send:)` writes the draft, so the write
    /// isn't taken for the reader's.
    @ObservationIgnored private var isPrefilling = false
    /// The scope `prefill(_:scope:send:)` left with the draft, for the question
    /// the reader sends from it, edited or not, but not once emptied.
    @ObservationIgnored private var draftScope: String?
    /// Bumped every time the thread is emptied, by New Chat or Delete All, so
    /// the composer can take focus the instant a new chat opens: the composer
    /// of the screen that emptied it, or every screen's where the host did. A
    /// count rather than a flag: two New Chat taps in a row are two events,
    /// and a flag would only be one. Not for an earlier chat opened
    /// (`openThread(_:)`), which is there to be read: on a phone the keyboard
    /// would come up over it.
    public private(set) var threadGeneration = 0
    /// The screen whose New Chat or Delete All bumped `threadGeneration` last,
    /// or nil where the host called `startOver()` or `deleteAllThreads()`
    /// itself, as the Mac's menu bar item does. Only that screen takes the
    /// focus for the new chat, or every screen for the host's call. The
    /// screen in another window on the store shows the same chat ending and
    /// takes no focus (ARCHITECTURE.md, "A host's request for the composer"
    /// has why). Read in the screen's handler, never its body, so nothing
    /// observes it.
    @ObservationIgnored private(set) var threadEndOrigin: UUID?

    /// The turn that most recently ended, with an answer, a failure or a stop:
    /// an event, not a property of the thread. Nil once the thread is emptied
    /// or another chat takes its place. The screen announces each ending as
    /// this changes, and only this turn's pieces arrive (`AskArrival`).
    ///
    /// **Not derived from `turns.last?.isComplete`**, which is true of a thread
    /// read back from disk too: restoring a thread would announce "Answer
    /// ready" at launch, for an answer the reader read the day before. It is
    /// set only where a turn ends: its answer landing, its failure, or a stop
    /// that keeps its prose.
    public private(set) var lastTerminalTurn: UUID?

    /// When `lastTerminalTurn` ended, on `clock`, written in the same mutation
    /// (`noteTerminal`) so the pieces built in the frame a turn ends read the
    /// two together, which is what brings them in rather than drawing them at
    /// rest (`AskArrival`). Set from the screen's own `onChange`, it would land
    /// a frame late, and those pieces would be at rest for good.
    private(set) var lastTerminalTurnEndedAt: TimeInterval?

    /// The thread saved last time couldn't be read on this launch. New Chat
    /// and Delete All clear it.
    ///
    /// A thread whose bytes aren't one this build can decode, or none of
    /// whose turns decode, is set aside beside the thread, whole, and filed
    /// with the earlier chats on a later launch that can read it; the chat on
    /// screen is saved as usual. One that couldn't be read at all (a locked
    /// device) stays where it is, and nothing is written over it until it is
    /// read, as protected data comes back or the screen does (its turns then
    /// go above the ones asked meanwhile), or until New Chat, which sets it
    /// aside, or Delete All, which deletes it. The turns asked meanwhile are
    /// filed with the earlier chats until then, as a chat of their own.
    public private(set) var readFailed = false

    /// What holds the thread's place on disk that is nowhere else, so that
    /// nothing may be written over it.
    private enum HeldThread {
        /// The thread saved last time, which couldn't be read at all on this
        /// launch (a locked device). Read again as protected data comes back
        /// and as the screen does (`retryWhatWaitsOnTheDisk()`). The turns
        /// asked meanwhile are filed beside it (`heldTurnsFiling`).
        case unreadable
        /// A chat New Chat ended and couldn't file or set aside (a locked
        /// device, a full disk). The thread file is its last copy on disk, or
        /// an older save of it where it couldn't be written either (the chat
        /// itself then waits in `filingsOwed`), and is set aside before
        /// anything is written in its place (`freeTheThreadsPlace()`). The
        /// turns asked while it won't move are filed beside it
        /// (`heldTurnsFiling`).
        case unfiled
    }

    /// What holds the thread's place, if anything: nothing may be written
    /// there while it does. New Chat sets it aside and Delete All deletes it.
    @ObservationIgnored private var heldThread: HeldThread?

    /// Whether the first screen says the thread saved last time couldn't be
    /// read: from a failed read until the reader asks something, opens an
    /// earlier chat or starts a new one, since each of those puts something
    /// in the empty place it explains. Read from the thread's shape, so the
    /// screen reading it doesn't hear every snapshot (`shape`).
    var showsUnreadableThreadNotice: Bool { readFailed && shape.ids.isEmpty }

    /// The last write queued. Each later one waits for it rather than racing
    /// it, so the writes land in the order they were made, and a test can
    /// await the last. Out of order, a save landing after New Chat's clear
    /// would bring the ended chat back on the next launch.
    private var persisting: Task<Void, Never>?
    /// The last save of the thread failed: on the iOS family, complete file
    /// protection fails every write while the device is locked. Saved again
    /// as protected data comes back and as the screen does, since nothing
    /// else writes the thread until the next turn ends.
    @ObservationIgnored private var saveOwed = false
    /// Chats New Chat ended that are on disk nowhere: the archive refused
    /// them, and they couldn't be kept in the thread's place, which refused
    /// the write or held what won't move or is owed a delete. Filed when the
    /// archive takes them. Delete All Chats drops them, and a store whose
    /// archive has no folder owes none (`oweFiling`).
    ///
    /// **Only for this process, because keeping one is the write that
    /// failed.** Outliving a relaunch means writing the chat down, and the
    /// archive and the thread's place, both in the app's folder, have just
    /// refused it; a file beside them fails under the same lock, permission
    /// or full disk. An app quit with one owed loses it.
    @ObservationIgnored private(set) var filingsOwed: [[AskThreadEntry<Row>]] = []
    /// What the disk wouldn't delete: what Delete All Chats couldn't (the
    /// files set aside beside the thread, the thread itself), the thread a
    /// chat New Chat filed was still in, and the feedback attachments a chat
    /// left. Tried again when a save is. A thread saved since stands in the
    /// deleted one's place, so a save pays off the thread's share, and
    /// nothing else does: New Chat deletes it too, and never sets it aside or
    /// holds it.
    ///
    /// **Only for this process**: a thread or a set-aside file that never
    /// goes comes back on a later launch, the thread as the chat on screen
    /// and the file filed with the earlier chats
    /// (`AskThreadStore.recoverSetAside`). A marker saying what is owed would
    /// have to outlive the failure that blocked the delete, and a marker file
    /// in the same folder fails under the same lock or permission. Kept
    /// anywhere else, such as the host's defaults, it would be storage of
    /// AskKit's own outside its folder, which it doesn't keep, so nothing
    /// marks it and a relaunch forgets it.
    @ObservationIgnored private var deletionOwed = DeletionOwed()
    private struct DeletionOwed: Equatable {
        /// The names of the files beside the thread that Delete All Chats
        /// couldn't delete, as they stood when it ran: a retry removes these
        /// and never a file set aside since, such as a chat New Chat couldn't
        /// file (`AskThreadStore.removeEverySetAside()`).
        var setAside: Set<String> = []
        var thread = false
        /// The names of the attachments that wouldn't go with their chat: a
        /// retry removes these and never one a verdict in a later chat kept
        /// since (`AskFeedbackAttachments.removeEvery()`).
        var attachments: Set<String> = []
        var isEmpty: Bool { self == DeletionOwed() }
    }
    #if os(iOS) || os(visionOS)
    /// Listening for protected data coming back, while a thread waits on it
    /// (`watchForProtectedData()`).
    @ObservationIgnored private var protectedDataObservation: NotificationCenter.ObservationToken?
    #endif
    /// What the app knows about the library right now, for the first screen and
    /// the starters. Read again by `refresh()`.
    public private(set) var overview = AskOverview.empty
    /// Whether `overview` has been read yet. Until it has, every library reads
    /// as empty, and the stage says the first screen isn't known yet
    /// (`AskStage.firstScreenIsKnown`).
    private(set) var hasReadOverview = false
    /// Whether the first read of the overview ran past the domain's turn
    /// deadline with none read before it, so the first screen waits for it no
    /// longer (`AskStage.firstScreenIsKnown`).
    private(set) var overviewIsOverdue = false
    /// How many reads of the overview have begun, and the newest of them to
    /// have landed, so one begun earlier that lands later changes nothing.
    @ObservationIgnored private var overviewReadsBegun = 0
    @ObservationIgnored private var overviewReadLanded = 0
    /// Whether the engine's first `refreshStatus()` has returned. With the
    /// mirror having heard from its seam (`AskModelStatus.hasHeardFromSeam`),
    /// it is what `statusIsRead` stands on.
    private(set) var hasRefreshedStatus = false
    /// The starters the domain offers for the library as it stands
    /// (`AskDomain.starters(overview:window:)`): the first screen's, and the
    /// coaching under a refused or ungrounded failure. `availableStarters`
    /// leaves out the ones the reader has asked or passed over.
    public private(set) var starters: [AskStarter] = []
    /// The starters and coaching the reader has asked or passed over, by id:
    /// they don't come back in this thread. A follow-up passed over is kept
    /// apart (`declinedFollowUps`).
    public private(set) var declinedStarters: Set<String> = []
    /// The follow-ups the reader passed over, by their words: they don't come
    /// back in this thread. Apart from `declinedStarters`, whose ids are the
    /// host's, such as a slug ("vinyl"): in one set, a follow-up worded as a
    /// starter's id would hide that starter, and the starter the follow-up.
    private var declinedFollowUps: Set<String> = []
    /// Whether the thread has been read back from disk yet. True once the read
    /// has finished, not once it has begun: a question asked in between waits
    /// for it.
    public private(set) var hasRestored = false
    /// A host's request to put the reader in the composer: made by
    /// `prefill(_:scope:send:)` or `focusComposer()`, and taken by one screen,
    /// which focuses its field (`claimComposerFocus(_:)`).
    ///
    /// A token rather than a flag, so two prefills in a row are two requests;
    /// optional rather than a counter, so a screen that appears after the
    /// request was made still finds it waiting. The usual entry point switches
    /// to the Ask tab and prefills in the same breath.
    ///
    /// **One screen takes it, in the window the reader is in.** The screen in
    /// every window on the store hears the request, and the first whose window
    /// appears active claims it (`AskScreen.deliverComposerFocus(_:)`), and
    /// hands it on if the reader's tap brings another window to the front just
    /// after (`AskHostFocusHandOver`). ARCHITECTURE.md, "A host's request for
    /// the composer", says why not every screen. The draft stays the store's:
    /// every window shows it.
    public private(set) var composerFocusRequest: UUID?
    /// The reader's earlier chats, newest first: what the history list shows
    /// under the chat on screen. Always empty on a domain that keeps no chats.
    public private(set) var history: [AskThreadSummary] = []

    /// The domain this thread asks about.
    public let domain: Domain
    /// The domain's `brand`, read once as the store is made: its copy, its
    /// folder in Application Support and its log subsystem.
    public let brand: AskBrand

    @ObservationIgnored private let engine: any AskAsking<Row>
    @ObservationIgnored private let thread: AskThreadStore<Row>
    @ObservationIgnored private let archive: AskThreadArchive<Row>
    /// The chat on screen's identity in the history list. Only the list reads
    /// it, and only to tell its rows apart.
    @ObservationIgnored private let currentChatID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The read of the saved thread, begun by whichever comes first (the
    /// screen appearing, a host's own call, a question) and awaited by the
    /// rest.
    @ObservationIgnored private var restoring: Task<Void, Never>?
    /// The chat on screen giving way to another: New Chat, Delete All Chats
    /// or an earlier chat opening, from the reader's tap until the engine has
    /// been stopped, reset and handed the new chat's tail. Each waits for the
    /// one before it (`queueChatChange`), so they reach the screen, the disk
    /// and the engine in the order they were asked for, and a question asked
    /// meanwhile waits for the last (`start`).
    ///
    /// **Stop's word to the engine rides here too**, though no chat changes
    /// (`stop(byReader:)`): the engine's `stop()` cancels whatever it is
    /// asking when it lands, so a question asked in the same tick has to
    /// reach the engine after it, as one asked after New Chat does.
    @ObservationIgnored private var changingChat: Task<Void, Never>?
    /// How many chat changes have been queued, so the last can tell it is the
    /// last and clear `changingChat`.
    @ObservationIgnored private var chatChangesQueued = 0
    /// Bumped by every New Chat, Delete All Chats and earlier chat asked for,
    /// so a change still reading or filing when the reader asked for
    /// something else gives way to it (`open`), and a thread read again
    /// meanwhile isn't put back into a chat that has ended
    /// (`rereadHeldThread`).
    @ObservationIgnored private var chatRequests = 0
    /// Bumped each time the thread on screen ends: New Chat, Delete All
    /// Chats, an earlier chat taking its place. A save queued before it then
    /// writes nothing when it runs, since the change's own writes file or
    /// delete that chat and own its place from then on (`persist()`).
    @ObservationIgnored private var threadEnds = 0
    /// The earlier chat on screen, which the list leaves out while it is
    /// there: its filing stays when it couldn't be written as the thread, or
    /// when some of its turns didn't decode, since the filing is then their
    /// only copy (`open`).
    @ObservationIgnored private var openedChatID: UUID?
    /// The filing that keeps the turns asked while the thread's place is held
    /// (`heldThread`), by a thread that couldn't be read or a chat New Chat
    /// couldn't file and that won't move aside, which the list leaves out
    /// while they are on screen. It goes once they are
    /// written as the thread (`AskThreadArchive.endProvisional`), or once New
    /// Chat or an earlier chat opening files their chat over it
    /// (`AskThreadArchive.fileTheChatOnScreen`). Taken before
    /// the filing is awaited and cleared as the chat ends, never set after
    /// an await (`fileBesideTheHeldThread`).
    @ObservationIgnored private var heldTurnsFiling: UUID?
    /// The question waiting to be asked (`start`), if any. An earlier chat
    /// opening opens with it still waiting, to be asked there, rather than
    /// settling it as a turn of the chat it replaces. Stop, or a newer
    /// question, puts it back in the composer
    /// (`returnTheWaitingQuestion()`). Observed, since the newest card's
    /// phase reads whether there is one (`proposalPhase(for:)`).
    private var waitingQuestion: WaitingQuestion?
    /// Whether a question waits to be asked.
    private var questionWaits: Bool { waitingQuestion != nil }

    /// A question asked before it could reach the engine: its words, and
    /// what goes with them.
    private struct WaitingQuestion {
        let text: String
        let photo: AskQuestionPhoto?
        let image: CGImage?
        let scope: String?
    }
    /// Whether a host's own `prewarm()` wants a session warm for the next
    /// question, until its `releaseWarmSession()`.
    @ObservationIgnored private var keepsWarm = false
    /// The screens up that want a session warm for their next question, by
    /// the identity each holds: from `prewarm(for:)` until
    /// `screenDisappeared(_:)`. A set, not a flag, so one window of several
    /// closing doesn't let go of the warm the others' questions will take.
    @ObservationIgnored private var warmingScreens: Set<UUID> = []
    /// Whether anything up wants a session warm: a screen, or a host's own
    /// `prewarm()`. `rewarm()` and the reader's question beginning (`draft`)
    /// ask it.
    private var wantsWarm: Bool { keepsWarm || !warmingScreens.isEmpty }
    /// The clock the reveal is measured on. One `TimeInterval` origin for the
    /// whole thread, so every chunk is comparable.
    @ObservationIgnored private let clock: @Sendable () -> TimeInterval
    /// Where a rated answer's feedback attachment is kept for the diagnostics
    /// row to share.
    @ObservationIgnored private let feedbackAttachments: AskFeedbackAttachments
    /// The verdict on its way to the engine, so a test can await it.
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    /// Whether a `.perLaunch` domain's attachments from the launch before
    /// have been sent after their chat (`forgetLastLaunchsAttachments()`).
    @ObservationIgnored private var forgotLastLaunchsAttachments = false
    /// Bumped each time the feedback attachments change: one saved, or all
    /// removed with their chat. The settings card reads the list again on it
    /// (`AskPrivateCloudCard`), so Share never offers a file that has gone.
    private(set) var feedbackRevision = 0

    /// The thread for `engine`'s domain (`AskEngine.domain`), asked through
    /// `engine`: what a host builds.
    ///
    /// Make one for the life of the app, and hold it outside any view: the
    /// type's note says why. Nothing is read or asked here. The screen reads
    /// the saved thread, the library and the model's state as it appears
    /// (`restoreIfNeeded()`, `refresh()`), and a host may call either first.
    ///
    /// **The domain is given once, to the engine.** The store reads the
    /// engine's, so the rules the engine answers by (its grounding policy,
    /// what its tools read and write) and the ones the store draws and keeps
    /// by (its brand, its folder, its persistence, `perform(_:)`) are one
    /// value's.
    ///
    /// The last three default to the domain's folder in Application Support
    /// (`AskBrand.appDirectory`), logging under `AskBrand.logSubsystem`. A
    /// test passes its own, in a folder of its own.
    ///
    /// - Parameters:
    ///   - engine: What asks the questions, and what the thread asks about.
    ///     The screen reads the model's state from its `status`.
    ///   - thread: Where the thread on screen is kept, for a domain whose
    ///     `persistence` is `.thread`.
    ///   - archive: Where the earlier chats are kept, for the same domains.
    ///   - feedbackAttachments: Where a rated answer's feedback attachment is
    ///     kept, for the diagnostics row to share.
    public convenience init(
        engine: AskEngine<Domain>,
        thread: AskThreadStore<Row>? = nil,
        archive: AskThreadArchive<Row>? = nil,
        feedbackAttachments: AskFeedbackAttachments? = nil
    ) {
        self.init(
            domain: engine.domain, engine: engine, thread: thread, archive: archive,
            feedbackAttachments: feedbackAttachments
        )
    }

    /// The thread for `domain`, asked through an engine of the host's own
    /// (`AskAsking`), such as a scripted one for previews and tests.
    ///
    /// **Not for an `AskEngine`**, which carries its domain: build the store
    /// from it with `init(engine:thread:archive:feedbackAttachments:)`. Here
    /// only the row type ties `domain` to `engine`, and nothing checks the
    /// rest: an engine answering by another domain's folder, grounding policy
    /// or tools would answer by rules the store doesn't draw or keep by.
    ///
    /// Everything else is as `init(engine:thread:archive:feedbackAttachments:)`
    /// says.
    ///
    /// - Parameters:
    ///   - domain: What the thread asks about.
    ///   - engine: What asks the questions. The screen reads the model's
    ///     state from its `status`.
    ///   - thread: Where the thread on screen is kept, for a domain whose
    ///     `persistence` is `.thread`.
    ///   - archive: Where the earlier chats are kept, for the same domains.
    ///   - feedbackAttachments: Where a rated answer's feedback attachment is
    ///     kept, for the diagnostics row to share.
    public convenience init(
        domain: Domain,
        engine: any AskAsking<Row>,
        thread: AskThreadStore<Row>? = nil,
        archive: AskThreadArchive<Row>? = nil,
        feedbackAttachments: AskFeedbackAttachments? = nil
    ) {
        self.init(
            domain: domain, engine: engine, thread: thread, archive: archive,
            feedbackAttachments: feedbackAttachments,
            clock: { Date.timeIntervalSinceReferenceDate }
        )
    }

    /// The same, with the reveal measured on `clock`. For tests.
    ///
    /// **Not public.** The views measure the reveal against the wall clock
    /// (`Date.timeIntervalSinceReferenceDate`), so a store on any other clock
    /// draws every answer at once, or never.
    init(
        domain: Domain,
        engine: any AskAsking<Row>,
        thread: AskThreadStore<Row>? = nil,
        archive: AskThreadArchive<Row>? = nil,
        feedbackAttachments: AskFeedbackAttachments? = nil,
        clock: @escaping @Sendable () -> TimeInterval
    ) {
        self.domain = domain
        self.brand = domain.brand
        self.engine = engine
        let thread = thread ?? AskThreadStore<Row>(
            appDirectory: domain.brand.appDirectory, logSubsystem: domain.brand.logSubsystem
        )
        self.thread = thread
        self.archive = archive ?? AskThreadArchive<Row>(
            appDirectory: domain.brand.appDirectory, logSubsystem: domain.brand.logSubsystem
        )
        self.feedbackAttachments = feedbackAttachments ?? AskFeedbackAttachments(
            appDirectory: domain.brand.appDirectory, logSubsystem: domain.brand.logSubsystem
        )
        self.clock = clock
        let place = domain.persistence == .thread ? thread.fileURL?.standardizedFileURL.path(percentEncoded: false) : nil
        censusPlace = place
        if let place, storeCensus.withLock({ $0.arrive(place) }) {
            Logger(subsystem: domain.brand.logSubsystem, category: "ask").fault("""
                a second AskConversationStore is alive over the Ask thread in \
                \(domain.brand.appDirectory, privacy: .public) — one store per app: two write the same \
                thread and earlier chats, and the last save wins
                """)
        }
    }

    deinit {
        if let censusPlace { storeCensus.withLock { $0.leave(censusPlace) } }
    }

    /// The thread file this store keeps, as the process's census of stores
    /// counts it (`AskStoreCensus`), or nil for a store that keeps none.
    @ObservationIgnored private let censusPlace: String?

    // MARK: - Asking

    /// The photo waiting in the composer for the reader's next question.
    public private(set) var pendingPhoto: AskPendingPhoto?

    /// Ask a question, as a new turn at the foot of the thread. Everything the
    /// turn does arrives as events; the store only writes them onto the turn.
    ///
    /// A question that is only whitespace asks nothing. A turn in flight is
    /// stopped first, and keeps what it had said. A question asked before the
    /// saved thread is read, or as the chat changes (New Chat, Delete All
    /// Chats, an earlier chat opening), waits for it, and is thinking
    /// meanwhile; one still waiting when another is asked goes back to the
    /// composer, as Stop puts it back (`stop(byReader:)`).
    ///
    /// A question from the composer (`.typed`, or `.prefilled` from an entry
    /// point's `prefill(_:scope:send:)`) empties the draft and takes the photo
    /// waiting there, and a `.typed` one takes the scope a prefill left with
    /// the draft. A starter or a chip is a question of its own, so the draft
    /// and the photo wait on for the next one.
    ///
    /// Two origins are how the engine runs a turn, not where a question came
    /// from, and are asked as `.typed`, the default: `.standalone`, a
    /// one-shot that shares nothing with the thread, which a turn on the
    /// thread can't be (`AskEngine.answerOnce(_:)` asks one), and `.reroll`,
    /// which is Another pick's (`rerollPick(_:)`).
    public func ask(_ question: String, origin: AskOrigin = .typed) {
        let origin = origin == .standalone || origin == .reroll ? .typed : origin
        // The composer's send carries the scope a host left in the draft. Read
        // here, before the draft is emptied, and the scope with it.
        ask(question, origin: origin, scope: origin == .typed ? draftScope : nil)
    }

    private func ask(_ question: String, origin: AskOrigin, scope: String?) {
        let fromComposer = origin == .typed || origin == .prefilled
        let pending = fromComposer ? pendingPhoto : nil
        start(
            question, origin: origin, photo: pending?.photo, image: pending?.image, scope: scope,
            emptyingTheComposer: fromComposer
        )
    }

    /// Put a photo in the composer, to go with the reader's next question: the
    /// host's `onAttach`, once the reader has chosen one. A second photo
    /// replaces the first.
    ///
    /// Only on a domain that accepts photos. `acceptsPhotoAttachments` decides
    /// whether the composer offers the button, and here whether a photo can
    /// reach the engine at all.
    ///
    /// - Parameters:
    ///   - image: the photo's pixels: what the thumbnail above the question
    ///     draws, and what goes to a model that reads photos. Held for this
    ///     process only, and never written to disk.
    ///   - label: what the photo shows, in the app's words. The model is told
    ///     it with the picture, and VoiceOver reads it for the thumbnail.
    ///   - reference: where the host keeps the photo, for
    ///     `AskDomain.photoThumbnail(for:)` to draw it again in a thread read
    ///     back from disk. Nil for a photo kept nowhere.
    public func attachPhoto(_ image: CGImage, label: String, reference: String? = nil) {
        guard domain.acceptsPhotoAttachments else { return }
        pendingPhoto = AskPendingPhoto(photo: AskQuestionPhoto(label: label, reference: reference), image: image)
    }

    /// Take the waiting photo back out of the composer.
    public func removePhoto() {
        pendingPhoto = nil
    }

    /// Start a turn: the question, the photo it goes with, and the pixels where
    /// this process still has them. False for a question with nothing in it,
    /// which starts nothing. `emptyingTheComposer` for the composer's own
    /// question, which leaves it: the draft and the photo waiting there.
    @discardableResult
    private func start(
        _ question: String,
        origin: AskOrigin,
        photo: AskQuestionPhoto?,
        image: CGImage?,
        scope: String?,
        emptyingTheComposer: Bool = false
    ) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Before a question still waiting comes back to the composer, below.
        // Only for the composer's question: Try Again comes through here too,
        // with a question of its own, and leaves the draft alone.
        if emptyingTheComposer {
            draft = ""
            if pendingPhoto != nil { pendingPhoto = nil }
        }
        // A question asked is the reader's attention elsewhere: an outcome that
        // lands after it leaves their focus where they took it.
        proposalOutcomeFocus = nil
        // A question asked over a turn in flight settles that one first, so the
        // thread never holds two unfinished turns. The reader's question cut it
        // short, so the stop is theirs. Saved now, as Stop saves it: its own
        // task ends without a save once let go, and the newer turn's save
        // comes only when that turn ends, after an app killed meanwhile. One
        // still waiting has no turn to keep it, and goes back to the composer.
        returnTheWaitingQuestion()
        if settleTurnInFlight(byReader: true) { persist() }

        // A question can come before the saved thread has been read: an entry
        // point that sends as it opens Ask gets here ahead of the screen.
        // Asked at once, it would keep the thread from coming back or be
        // replaced by it, and the save after its answer would write over the
        // thread on disk. So it waits for the read, which also hands the
        // engine the thread's tail before the question.
        //
        // And a question asked as the chat changes (New Chat, Delete All
        // Chats, an earlier chat opening) waits for the change. Asked at
        // once, it would reach the engine between the change's `stop()` and
        // its `reset()`, and the reset would cancel it; or it would go onto
        // the chat being replaced and be lost with it. A question asked right
        // after Stop waits the same way, for Stop's `stop()`, which would
        // otherwise land after it and cancel it.
        //
        // It is thinking from the tap, as a turn asked at once would be, and
        // the wait is the turn's task, so Stop and New Chat cancel it the way
        // they cancel a turn.
        let waitsForTheRead = keepsThread && !hasRestored
        guard !waitsForTheRead, changingChat == nil else {
            isThinking = true
            waitingQuestion = WaitingQuestion(text: trimmed, photo: photo, image: image, scope: scope)
            // Begun at the tap, not a hop later.
            if waitsForTheRead { _ = restoration() }
            task = Task { [weak self] in
                await self?.readyForAQuestion()
                guard !Task.isCancelled else { return }
                self?.waitingQuestion = nil
                self?.begin(trimmed, origin: origin, photo: photo, image: image, scope: scope)
            }
            return true
        }
        begin(trimmed, origin: origin, photo: photo, image: image, scope: scope)
        return true
    }

    /// Wait until the saved thread is read and no chat is changing: what a
    /// question asked before either waits for.
    ///
    /// A loop, since a change queued while this waits is waited for too. New
    /// Chat cancels the question anyway, as it settles the turn in flight at
    /// the tap; an earlier chat opens with the question waiting, to be asked
    /// on it (`questionWaits`).
    private func readyForAQuestion() async {
        if keepsThread, !hasRestored { await restoration().value }
        while let pending = changingChat, !Task.isCancelled {
            await pending.value
            if changingChat == pending { changingChat = nil }
        }
    }

    /// Whether the domain keeps its thread on disk (`AskPersistence.thread`).
    private var keepsThread: Bool { domain.persistence == .thread }

    /// Put the question on the thread and ask the engine.
    private func begin(
        _ trimmed: String,
        origin: AskOrigin,
        photo: AskQuestionPhoto?,
        image: CGImage?,
        scope: String?
    ) {
        let turn = Turn(question: trimmed, origin: origin, photo: photo, photoImage: image, scope: scope)
        turns.append(turn)
        isThinking = true
        let id = turn.id
        // Pixels only with the photo they belong to, never for a turn read
        // back from disk, which has none to send.
        var images: [AskImageAttachment] = []
        if let photo, let image { images = [AskImageAttachment(label: photo.label, image: image)] }

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in self.engine.ask(trimmed, origin: origin, images: images, scope: scope) {
                    if Task.isCancelled { return }
                    self.apply(event, to: id)
                }
                if Task.isCancelled { return }
                // The stream finished without an answer event: a turn that
                // produced nothing at all, rather than one that failed.
                if self.turn(id)?.isComplete != true {
                    self.fail(id, with: .couldNotAnswer)
                }
            } catch is CancellationError {
                // Cancelled by this store, which settled the turn first. Any
                // other cancellation came from the engine's side, a host
                // resetting it or another store asking it something, and the
                // turn is stopped where it stands, as Stop would leave it,
                // though not as the reader's stop.
                if Task.isCancelled { return }
                self.markStopped(id, byReader: false)
            } catch let error as AskError {
                if Task.isCancelled { return }
                self.fail(id, with: error)
            } catch {
                if Task.isCancelled { return }
                // `AskEngine` triages every SDK error into an `AskError` before
                // it gets here, so this is a fault in the engine, not the
                // model's, and the reader is about to get the same line as an
                // ordinary timeout. This line in the log is the only way to
                // tell the two apart afterwards. The tag, never the error:
                // `AskTriage.tag` reads the case name by reflection, where
                // `String(describing:)` would materialize SDK prose that can
                // quote model output.
                Logger(subsystem: self.brand.logSubsystem, category: "ask")
                    .error("a turn failed with an untriaged error: \(AskTriage.tag(for: error), privacy: .public)")
                self.fail(id, with: .couldNotAnswer)
            }
            // What the engine keeps now that the turn is over, read before the
            // store stops thinking: the follow-up chips wait on it. A turn
            // this store let go returned above, and whatever replaced it reads
            // it in turn.
            await self.readKeptConversation()
            // Let go during that hop: by Stop, or an earlier chat opening,
            // with a question asked after it waiting for its turn. That
            // question has no turn yet, so this is still the last one, and
            // going on would stop the store thinking for it and drop the task
            // Stop cancels it by.
            guard !Task.isCancelled else { return }
            // Only if this is still the thread's last turn. A backstop: what
            // replaces the last turn cancels this task first, and the checks
            // above return on that. Without it, a turn ending after a newer one
            // began would unset `isThinking` for the newer turn. `AskEngine`
            // keeps the same invariant with its id check.
            guard self.turns.last?.id == id else { return }
            self.isThinking = false
            self.task = nil
            self.persist()
            self.forgetChunksOnceSettled(id)
        }
    }

    /// Drop a finished turn's arrival stamps once the last of them has faded:
    /// sleep until every chunk has settled
    /// (`AskArrivals.timeUntilSettled(_:at:)`), then 0.05 s more, and clear.
    ///
    /// **A view can't do this for itself.** `AskStreamingText` runs a
    /// `TimelineView` while a turn has chunks, and a timeline re-evaluates its
    /// own body rather than the view that built it, so nothing would ever tell
    /// the view to stop. Left alone, every finished turn on the thread costs a
    /// frame's work per frame for the life of the screen.
    ///
    /// **The wait is read from the chunks, not a constant.** Clearing the stamps
    /// paints every run opaque, and a chunk sweeps for as long as it is long
    /// (`AskArrivals.stagger(forLength:)`). A fixed wait of
    /// `AskArrivals.settle`, 0.33 s, would snap a long chunk to full part-way
    /// through a drawing-in that takes up to 0.75 s. Read before the sleep:
    /// the turn is settled by the time this is called, so nothing more arrives
    /// to lengthen it. And read on `clock`, the clock the chunks were stamped
    /// on: on another, the wait would be the gap between two clocks.
    private func forgetChunksOnceSettled(_ id: UUID) {
        let remaining = AskArrivals.timeUntilSettled(turn(id)?.chunks ?? [], at: clock())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.05))
            guard let self, self.turn(id)?.isComplete == true else { return }
            self.update(id) { $0.chunks = [] }
        }
    }

    /// Ask a starter, as `.starter`, and don't offer it again in this thread.
    public func ask(_ starter: AskStarter) {
        declinedStarters.insert(starter.id)
        ask(starter.text, origin: .starter)
    }

    /// Pass over a chip: it doesn't come back in this thread. A follow-up on
    /// offer is passed over by its words, and any other chip by its id
    /// (`declinedFollowUps`).
    public func decline(_ starter: AskStarter) {
        if followUps.contains(starter) {
            declinedFollowUps.insert(starter.text)
        } else {
            declinedStarters.insert(starter.id)
        }
    }

    /// Try Again: ask a failed turn's question again, the way it was first
    /// asked. A failed turn that drew nothing, a message and never an answer,
    /// gives its place to the re-ask. One that drew prose before it failed
    /// keeps it, and the question is asked again below it, as Ask again asks
    /// it: nothing shown is taken back (house rule 5). The composer's draft is
    /// left as it is; the question is the turn's.
    ///
    /// For the newest turn once it has failed. It does nothing for an older
    /// turn, which asked again would be pulled out of the middle of the thread
    /// and would stop the turn streaming below it, and nothing for a turn that
    /// hasn't failed: an answer, or a turn in flight, would lose its prose.
    /// Nor while a question waits to be asked (the saved thread being read,
    /// the chat changing, Stop's word on its way to the engine): it is newer
    /// though it has no turn yet, and asking again would cancel it.
    ///
    /// Try Again, Ask again and Another pick carry the turn's photo and scope,
    /// and send the photo again while this process has its pixels. A turn
    /// read back from disk has neither its pixels nor its scope, so its
    /// question goes on the words alone, and the thread says so under it when
    /// a photo went with it.
    public func retry(_ turn: Turn) {
        guard !questionWaits, let last = turns.last, last.id == turn.id, last.failure != nil else { return }
        if !last.hasContent { turns.removeLast() }
        start(turn.question, origin: turn.origin, photo: turn.photo, image: turn.photoImage, scope: turn.scope)
    }

    /// Ask again: the same question over the thread as it stands, as a new
    /// turn asked as `.followUp`. The reader wants a different answer, not
    /// the failed one retried.
    public func askAgain(_ turn: Turn) {
        start(turn.question, origin: .followUp, photo: turn.photo, image: turn.photoImage, scope: turn.scope)
    }

    /// "Another pick": the question again, over the thread as it stands, for
    /// something other than what the answer chose. The engine runs it hotter
    /// and tells the model what not to choose again.
    public func rerollPick(_ turn: Turn) {
        start(turn.question, origin: .reroll, photo: turn.photo, image: turn.photoImage, scope: turn.scope)
    }

    /// Edit & Resend: the question back in the composer, with the scope it was
    /// asked in and the photo it went with while this process still has its
    /// pixels. Whatever the composer held goes, the scope a prefill left with
    /// the draft and a photo waiting for another question included: the draft
    /// is this question now.
    func edit(_ turn: Turn) {
        draft = turn.question
        draftScope = turn.scope
        if let photo = turn.photo, let image = turn.photoImage {
            attachPhoto(image, label: photo.label, reference: photo.reference)
        } else {
            pendingPhoto = nil
        }
    }

    /// Put a question in the composer, and the reader in front of it.
    ///
    /// For a host's entry points: "Ask about this" on an item, an Ask link
    /// (`AskLink`), a notification action. The question lands in the draft,
    /// which every window on the store shows, and the screen in the window the
    /// reader is in focuses its field (`composerFocusRequest`), so it arrives
    /// with the keyboard up and the thread untouched, and the reader sends it.
    /// `send: true` asks it at once, as `.prefilled`, for an entry point whose
    /// tap already was the reader choosing to ask, and never for a link, which
    /// can come from anywhere.
    ///
    /// Clamped like any question, and an empty one does nothing. A draft the
    /// reader was halfway through is replaced: the entry point is the newer
    /// intent. A question left in the composer warms no session until the
    /// reader edits it (`draft`).
    ///
    /// **`scope` is the part of what the app holds the question was asked
    /// from**, such as the id of the shelf whose "Ask About My Records" was
    /// tapped, and the domain says what it means to the prompt
    /// (`AskDomain.scopeLine(for:)`). Always the app's own id, never words
    /// from a link. Sent at once, the turn is asked with it; left in the
    /// composer, it goes with the question the reader sends from there,
    /// edited or not, unless they empty the field first. The turn keeps it
    /// for Try Again, Ask again and Another pick.
    public func prefill(_ question: String, scope: String? = nil, send: Bool = false) {
        let clamped = AskPrompt.clampQuestion(question)
        guard !clamped.isEmpty else { return }
        if send {
            ask(clamped, origin: .prefilled, scope: scope)
        } else {
            isPrefilling = true
            draft = clamped
            isPrefilling = false
            draftScope = scope
            composerFocusRequest = UUID()
        }
    }

    /// Put the reader in the composer with no question for it: a Control
    /// Center control's "Ask", a keyboard shortcut. `prefill(_:scope:send:)` is
    /// the way in with a question, and it refuses an empty one, so this is the
    /// way in without. Whatever the reader left in the draft is still there.
    /// The screen in the window the reader is in takes it, as it takes a
    /// prefill (`composerFocusRequest`).
    public func focusComposer() {
        composerFocusRequest = UUID()
    }

    /// A screen takes the request it heard, if it is still the one waiting:
    /// true once, for the first screen to claim it, which then focuses its
    /// field. The screen in another window on the store hears the same request
    /// in the same update, and its claim fails, as does one for a request a
    /// newer one has replaced.
    func claimComposerFocus(_ request: UUID) -> Bool {
        guard composerFocusRequest == request else { return false }
        composerFocusRequest = nil
        return true
    }

    /// A screen that took a host's request in a window the reader has just
    /// left asks again, for the screen in the window in front now
    /// (`AskHostFocusHandOver`). A new token, so every screen hears it as a
    /// request of its own; the draft stays as it is.
    func repostComposerFocus() {
        composerFocusRequest = UUID()
    }

    /// The reader's thumbs on an answer. A turn with no answer, or a failed
    /// one, takes none.
    ///
    /// Kept on the turn and persisted with the thread, and logged through the
    /// engine. Where diagnostics are on (`offersFeedback`), the newest answer
    /// a model wrote, while its session is still kept and idle, has its
    /// feedback attachment saved too, for the diagnostics row to share; with
    /// them off there is no row to share it from, and none is taken. An answer
    /// the domain gave without a model has no transcript of its own, and the
    /// session's would describe some other exchange. The other thumb replaces
    /// the verdict; the same thumb again changes nothing.
    public func rate(_ turn: Turn, _ sentiment: AskFeedback.Sentiment) {
        guard let current = self.turn(turn.id), let answer = current.answer, current.failure == nil,
              current.feedback != sentiment else { return }
        update(turn.id) { $0.feedback = sentiment }
        persist()
        let feedback = AskFeedback(
            sentiment: sentiment, tier: current.tier, questionKind: answer.questionKind,
            tilesShown: answer.tiles.count, rowsRead: answer.matches.count,
            wasTruncated: answer.isTruncated
        )
        // No tier is an answer the domain gave without a model. And no
        // attachment is taken that nothing would keep: the SDK logs and
        // serializes the session's transcript as it hands it over.
        let keepsAttachment = offersFeedback
        let takesAttachment = keepsAttachment && turns.last?.id == turn.id && current.tier != nil
        // Last launch's go first, ahead of this verdict's in the queue.
        forgetLastLaunchsAttachments()
        let previous = feedbackTask
        feedbackTask = Task { [weak self, engine, feedbackAttachments] in
            // In order: two quick taps are two lines in the log, oldest first.
            await previous?.value
            guard let data = await engine.recordFeedback(feedback, isLatestTurn: takesAttachment), keepsAttachment else {
                return
            }
            guard await feedbackAttachments.save(data, sentiment: sentiment) != nil else { return }
            self?.feedbackRevision += 1
        }
    }

    /// Wait for the verdict on its way to the engine, or New Chat's removal of
    /// the attachments, if any. For tests.
    func flushFeedback() async {
        await feedbackTask?.value
    }

    /// Every feedback attachment kept, newest first: what the settings card's
    /// diagnostics row shares (`AskPrivateCloudCard`). Read from the
    /// attachments this store was handed, so a store given another folder
    /// lists its own.
    func feedbackAttachmentURLs() async -> [URL] {
        await feedbackAttachments.urls()
    }

    // MARK: - Proposals

    /// What came of a proposal, as VoiceOver words it, new each time an
    /// outcome is set.
    ///
    /// The card moves VoiceOver's focus to the same line where the reader
    /// said yes or not now, and the screen speaks this only where that line
    /// hasn't claimed it a beat after it came (`AskUnclaimedEnding`). Nothing
    /// speaks it for a hand-off, where the host's editor takes the focus, nor
    /// for an outcome nobody waited on at the card. A host whose own control
    /// confirms or declines a proposal can speak it.
    public private(set) var proposalAnnouncement: AskProposalAnnouncement?

    /// The turn whose card the reader said yes or not now on, while they wait
    /// on what came of it: its outcome line takes VoiceOver's focus once it
    /// is there (`AskConfirmationCard`), and lets the request go
    /// (`proposalOutcomeFocused(_:)`).
    ///
    /// **Here rather than in the card.** A question asked meanwhile, or the
    /// chat changing, drops it, as a question asked drops every request still
    /// waiting, so an outcome that lands later leaves the reader's focus where
    /// they took it. And a card the thread rebuilt while the app worked, a
    /// lazy row made again, still takes it.
    private(set) var proposalOutcomeFocus: UUID?

    /// The performs under way, each with the write of what came of it, so a
    /// test can wait for them all: a chat can change while one runs, and the
    /// next chat's card can start another beside it.
    @ObservationIgnored private var proposalTasks: [UUID: Task<Void, Never>] = [:]

    /// The proposals this process is carrying out, by their turn as the disk
    /// knows it. A turn read back while its perform is out, its chat opened
    /// again, reads as carrying it out (`readBack`), not as an outcome nobody
    /// knows, and takes no tap.
    @ObservationIgnored private var performingProposals: Set<DiskTurn> = []

    /// What came of the proposals whose turn had left the screen when their
    /// perform returned, by their turn as the disk knows it.
    ///
    /// Written into the filing that holds the turn, and kept here as well, so
    /// a chat read back before that write lands, or from a copy it didn't
    /// reach, still says what came of it (`withLateOutcomes`). In memory only:
    /// the write it backs is the one the disk may have refused.
    @ObservationIgnored private var lateProposalOutcomes: [DiskTurn: AskProposalOutcome] = [:]

    /// A turn as its chat's file knows it: its question, and when it was asked
    /// to the fraction of a second, as `AskThreadEntry.merging` knows one. A
    /// turn read back gets an `id` of its own, so this is what still names a
    /// turn once its chat has ended and opened again.
    private struct DiskTurn: Hashable {
        let question: String
        let askedAt: Date

        init(_ turn: Turn) {
            question = turn.question
            askedAt = turn.askedAt
        }
    }

    /// What the card under this turn's answer shows, or nil for no card: the
    /// answer proposed nothing, or the turn failed.
    ///
    /// **Only the newest turn's card takes a tap**, from the moment its answer
    /// lands. A proposal was made about the thread as it stood. Once the
    /// reader has asked something else, one they left unanswered reads "Not
    /// done": still on screen, since nothing the thread has shown is taken
    /// back, but no longer something to confirm. A question waiting to be
    /// asked counts, though it has no turn yet.
    ///
    /// A chat read back from disk offers its newest turn's card again, unless
    /// the reader had confirmed it: while that perform is still out in this
    /// process the card is carrying it out, and read back where nothing is,
    /// what came of it is unknown and the card takes no tap.
    public func proposalPhase(for turn: Turn) -> AskProposalPhase? {
        guard let current = self.turn(turn.id), current.failure == nil, current.answer?.proposal != nil else {
            return nil
        }
        if current.isPerformingProposal { return .performing }
        let isNewest = turns.last?.id == current.id && !questionWaits
        switch current.proposalOutcome {
        case .confirmed(let line): return .done(line)
        case .handedOff(let line): return .handedOff(line)
        case .declined: return .declined
        case .failed(let line): return .failed(line, canRetry: isNewest)
        case .performing: return .outcomeUnknown
        case nil: return isNewest ? .awaiting : .notDone
        }
    }

    /// The reader said yes: the domain carries the proposal out, and the card
    /// says what came of it. A card that takes no tap ignores one, and so does
    /// a card whose proposal is already being carried out.
    ///
    /// **At most once.** The yes is saved with the turn before the domain is
    /// asked (`AskProposalOutcome.performing`), and the domain is asked only
    /// once that write has landed, so a chat that ends, or an app that quits,
    /// while it works never offers the action again. A yes the disk refused
    /// is never carried out, and nor is one whose chat ended before it was
    /// saved (New Chat, Delete All Chats or an earlier chat opening in the
    /// same moment): the card says it couldn't be done (`.failed(nil)`), as
    /// a perform that failed does. The task holds the store until the domain
    /// returns, and what came of it is written onto the turn wherever it is
    /// by then: on screen, read back in a chat opened again, or in the filing
    /// of a chat that has ended. Nothing waits for the domain: New Chat and
    /// an earlier chat opening go ahead while it works, so a perform that
    /// never returns holds up no chat. It is asked off the main actor
    /// (`perform(_:of:logSubsystem:)`).
    ///
    /// A `.handOff` is never performed: the card opens the host's editor and
    /// calls `handOffProposal(_:line:)`, and a tap that reaches here for one
    /// is ignored rather than handed to `AskDomain.perform(_:)`.
    public func confirmProposal(_ turn: Turn) {
        confirmProposal(turn, awaitingTheOutcome: false)
    }

    /// `confirmProposal(_:)`, from the card itself when `awaitingTheOutcome`,
    /// whose outcome line then takes VoiceOver's focus
    /// (`proposalOutcomeFocus`).
    func confirmProposal(_ turn: Turn, awaitingTheOutcome: Bool) {
        guard let current = self.turn(turn.id), let proposal = current.answer?.proposal,
              proposal.kind != .handOff,
              proposalPhase(for: current)?.takesATap == true else { return }
        let id = turn.id
        let diskTurn = DiskTurn(current)
        performingProposals.insert(diskTurn)
        update(id) { turn in
            turn.isPerformingProposal = true
            turn.proposalOutcome = .performing
        }
        proposalOutcomeFocus = awaitingTheOutcome ? id : nil
        // A thread kept for the process only has no quit to outlive.
        let saving = keepsThread ? saveTheYes() : nil
        let run = UUID()
        proposalTasks[run] = Task { [domain, brand] in
            let outcome: AskProposalOutcome
            if let saving, await !saving.value {
                Logger(subsystem: brand.logSubsystem, category: "ask")
                    .error("a proposal's yes could not be saved with its chat, so it was not carried out")
                outcome = .failed(nil)
            } else {
                outcome = await Self.perform(proposal, of: domain, logSubsystem: brand.logSubsystem)
            }
            await self.settleProposal(of: id, diskTurn, with: outcome)
            self.proposalTasks[run] = nil
        }
    }

    /// Save the reader's yes as the thread, after every write queued before
    /// it, and say whether it is on disk with its chat still on screen once
    /// the write has returned: only then is the domain asked.
    ///
    /// **A chat that ended before the write ran, or while it ran, is a
    /// refusal.** The chat's own writes (New Chat's, Delete All Chats', an
    /// earlier chat opening's) file or delete it from then on, and an
    /// earlier chat opening may have filed it before the yes was given, so
    /// nothing here can say the yes is on disk.
    private func saveTheYes() -> Task<Bool, Never> {
        let ends = threadEnds
        return queueWrite { store in
            // Before the read nothing is written (`persist()`), and no card
            // takes a tap then, since a question waits for the read.
            guard store.hasRestored, store.threadEnds == ends else { return false }
            let saved = await store.writeThread(store.turns.filter(\.isComplete).map(\.entry))
            return saved && store.threadEnds == ends
        }
    }

    /// Carry `proposal` out off every actor, as `overview(of:)` reads the
    /// overview: a plain `nonisolated async` perform runs where it is called
    /// from, and a slow one on the main actor would hitch the screen. Says
    /// what came of it: the domain's line, an `AskProposalFailure`'s, or a
    /// failure with no words of its own for any other error.
    @concurrent nonisolated private static func perform(
        _ proposal: AskProposal, of domain: Domain, logSubsystem: String
    ) async -> AskProposalOutcome {
        do {
            return .confirmed(try await domain.perform(proposal))
        } catch let failure as AskProposalFailure {
            return .failed(failure.line)
        } catch {
            // Never the error's own words; `AskProposalFailure` says why. The
            // tag, so the log can tell a host's own fault from one it meant
            // to report.
            Logger(subsystem: logSubsystem, category: "ask")
                .error("a proposal failed with an error it didn't explain: \(AskTriage.tag(for: error), privacy: .public)")
            return .failed(nil)
        }
    }

    /// The host has opened its own editor for a `.handOff`, and the turn
    /// records that much. `line` is what the card then says, or nil for its
    /// own ("Opened in the app").
    ///
    /// **The card opens the door, not this.** `AskConfirmationCard` calls
    /// `askDraftOpener`, an environment value that `confirmProposal`'s task
    /// couldn't read, and then calls here so the thread keeps what happened.
    /// The domain is never asked: there is nothing to perform and nothing to
    /// fail, so the outcome is recorded at once rather than through a task.
    ///
    /// What the reader then does in the editor never comes back, which is why
    /// the outcome is `handedOff` and not `confirmed`.
    public func handOffProposal(_ turn: Turn, line: String? = nil) {
        guard let current = self.turn(turn.id), current.answer?.proposal?.kind == .handOff,
              proposalPhase(for: current)?.takesATap == true else { return }
        // The editor takes the focus, and no line waits for it.
        proposalOutcomeFocus = nil
        recordProposalOutcome(turn.id, .handedOff(line))
    }

    /// The reader said not now. Nothing is carried out, and the card says so.
    public func declineProposal(_ turn: Turn) {
        declineProposal(turn, awaitingTheOutcome: false)
    }

    /// `declineProposal(_:)`, from the card itself when `awaitingTheOutcome`,
    /// as `confirmProposal(_:awaitingTheOutcome:)` is.
    func declineProposal(_ turn: Turn, awaitingTheOutcome: Bool) {
        guard let current = self.turn(turn.id), proposalPhase(for: current)?.takesATap == true else { return }
        proposalOutcomeFocus = awaitingTheOutcome ? turn.id : nil
        recordProposalOutcome(turn.id, .declined)
    }

    /// The card under this turn has asked its outcome line to take the focus
    /// `proposalOutcomeFocus` held for it.
    func proposalOutcomeFocused(_ id: UUID) {
        guard proposalOutcomeFocus == id else { return }
        proposalOutcomeFocus = nil
    }

    /// Wait for every confirmed proposal to be carried out, and what came of
    /// it written. For tests.
    func flushProposal() async {
        while !proposalTasks.isEmpty, !Task.isCancelled {
            for task in Array(proposalTasks.values) { await task.value }
        }
    }

    /// What came of a proposal, written onto its turn wherever the turn is
    /// now: on screen, as the turn that made it or as the same turn read back
    /// in its chat opened again, and in the filing of its chat where that
    /// chat has ended since. Lost there, it would leave the filed card
    /// offering the action again, and a second yes would carry it out twice.
    private func settleProposal(of id: UUID, _ diskTurn: DiskTurn, with outcome: AskProposalOutcome) async {
        performingProposals.remove(diskTurn)
        let leftTheScreen = turn(id) == nil
        if leftTheScreen { lateProposalOutcomes[diskTurn] = outcome }
        if let onScreen = turns.first(where: { DiskTurn($0) == diskTurn && $0.proposalOutcome == .performing }) {
            recordProposalOutcome(onScreen.id, outcome)
        }
        // Its chat ended while the domain worked (New Chat, or an earlier chat
        // opened in its place), filed with the turn waiting on this. Queued
        // after the writes that filed it. Delete All Chats leaves nothing to
        // write it into, which is what the reader asked for.
        guard leftTheScreen, keepsThread else { return }
        await queueWrite { await $0.writeLateOutcome(outcome, for: diskTurn) }.value
    }

    /// Write what came of a proposal into the copies of its chat kept off
    /// screen: its filing, and a chat waiting in memory to be filed
    /// (`filingsOwed`). A chat New Chat could only set aside or hold in the
    /// thread's place keeps the yes as it was written, and reads back on a
    /// later launch with what came of it unknown. In the write queue.
    private func writeLateOutcome(_ outcome: AskProposalOutcome, for diskTurn: DiskTurn) async {
        filingsOwed = filingsOwed.map { chat in
            AskThreadEntry.settlingProposal(asked: diskTurn.question, at: diskTurn.askedAt, with: outcome, in: chat) ?? chat
        }
        await archive.settleProposal(asked: diskTurn.question, at: diskTurn.askedAt, with: outcome)
    }

    private func recordProposalOutcome(_ id: UUID, _ outcome: AskProposalOutcome) {
        update(id) { turn in
            turn.isPerformingProposal = false
            turn.proposalOutcome = outcome
        }
        persist()
        if let line = AskAnnouncement.proposal(outcome) {
            proposalAnnouncement = AskProposalAnnouncement(line: line)
        }
    }

    /// `entries`, read back, with what came of a proposal this process
    /// carried out after they were written in place of the yes they hold
    /// (`lateProposalOutcomes`).
    private func withLateOutcomes(_ entries: [AskThreadEntry<Row>]) -> [AskThreadEntry<Row>] {
        lateProposalOutcomes.reduce(entries) { entries, late in
            AskThreadEntry.settlingProposal(
                asked: late.key.question, at: late.key.askedAt, with: late.value, in: entries
            ) ?? entries
        }
    }

    /// A turn read back from disk, carrying out its proposal where this
    /// process still is (`performingProposals`).
    private func readBack(_ entry: AskThreadEntry<Row>) -> Turn {
        var turn = Turn(entry: entry)
        if turn.proposalOutcome == .performing, performingProposals.contains(DiskTurn(turn)) {
            turn.isPerformingProposal = true
        }
        return turn
    }

    private func apply(_ event: AskTurnEvent<Row>, to id: UUID) {
        let now = clock()
        update(id) { turn in
            switch event {
            case .tier(let tier):
                turn.tier = tier
                // With the tier, every time: a hand-down moves both.
                turn.answerSawPhoto = turn.photoImage != nil && tier.readsPhotos
            case .activity(let activity):
                turn.activity = activity
            case .activityEnded:
                turn.activity = nil
            case .partial(let text):
                // Not once the answer has landed, as for `.rowsRead` and
                // `.restarted`: a late snapshot would write over the answer's
                // tidied prose. `AskEngine` sends none after it; an engine of
                // a host's own might.
                if turn.answer == nil { turn.write(text, at: now) }
            case .rowsRead(let rows):
                // Everything the turn has read so far: the wait row counts
                // them, and a turn the reader stops keeps them as its
                // grounding. **Not a bank to draw:** the grid draws
                // `answer.tiles`, the rows the model chose, and only once it
                // has chosen them (`AskThreadRow.answerBody`).
                if turn.answer == nil { turn.rowsRead = rows }
            case .restarted(let tier):
                // The attempt that wrote what is on screen was thrown away, and
                // the one taking over has drawn nothing yet. So its prose
                // goes, and the rows it read go with it: a Stop before the new
                // attempt's first words keeps none of the old.
                // Grounded prose too, after a hand-down or a rollover: the one
                // exception to house rule 5, and the type's note says why.
                if turn.answer == nil {
                    turn.write("", at: now)
                    turn.rowsRead = []
                }
                turn.tier = tier
                turn.answerSawPhoto = turn.photoImage != nil && tier.readsPhotos
                turn.activity = .restarted(tier)
            case .summarized:
                turn.summarizedBefore = true
            case .refining:
                turn.activity = .custom(AskActivity.refiningKey)
            case .answer(let answer):
                if turn.answer != nil { turn.revision += 1 }
                turn.settle(answer, at: now)
                turn.activity = nil
            }
        }
        if case .answer = event { noteTerminal(id, at: now) }
    }

    // MARK: - Lifecycle

    /// Stop the turn in flight where it stands. What it had said stays as its
    /// answer; a turn that had said nothing offers Try Again. Nothing leaves
    /// the thread.
    ///
    /// - Parameter byReader: whether the reader asked for the stop, as the
    ///   screen's Stop buttons do: the note under the prose the turn kept, or
    ///   the line of a turn stopped before its first word, then reads "You
    ///   stopped this answer". Any other stop, such as a host's own, says
    ///   nothing of the reader: the prose it kept reads "Answer cut short",
    ///   and a turn stopped before its first word shows `AskError.stopped`'s
    ///   own line ("Couldn't answer that just now"), with Try Again either
    ///   way.
    ///
    /// A question still waiting to be asked, for the saved thread's read or a
    /// chat change, has no turn to keep it, and goes back to the composer,
    /// with its scope and its photo, unless the reader has begun another
    /// there (`returnTheWaitingQuestion()`).
    ///
    /// A question asked after it, at once or not, reaches the engine after
    /// the engine has stopped.
    public func stop(byReader: Bool = false) {
        // A question asked after it waits in `start`.
        returnTheWaitingQuestion()
        settleTurnInFlight(byReader: byReader)
        // Queued as a chat change is, not sent from a task of its own: the
        // engine's `stop()` cancels whatever it is asking when it lands, and
        // sent beside a question asked in the same tick, it could land second
        // and cancel that question (`changingChat`).
        queueChatChange { [engine] _ in await engine.stop() }
        persist()
    }

    /// New Chat: put the screen back the way it opened. The turn in flight is
    /// stopped where it stands and goes with the chat, the chat's turns are
    /// filed with the earlier chats on a domain that keeps them, the composer
    /// empties, and the next question starts a new conversation. The feedback
    /// attachments the chat produced go with it. Called before the saved
    /// thread has been read, it ends the chat once the read has landed.
    ///
    /// A question asked after it, at once or not, waits until the engine has
    /// been reset for the new chat.
    public func startOver() {
        // A question asked after it waits in `start`.
        startOver(from: nil)
    }

    /// New Chat from the screen with this id, or from the host where it's
    /// nil (`startOver()`): that screen's composer takes the focus for the
    /// new chat, or every screen's for the host's (`threadEndOrigin`).
    func startOver(from screen: UUID?) {
        // The turn in flight first, as opening an earlier chat settles it, so
        // the chat is filed with it and comes back whole. Before the read, it
        // is a question waiting for the read, and it goes with the chat.
        settleTurnInFlight(byReader: true)
        chatRequests &+= 1
        emptyComposer(from: screen)
        // After the saved thread is read. Before it, the chat on screen is
        // still empty: New Chat would file nothing, clear a thread the reader
        // never saw, and the read landing afterwards would put it back. Queued
        // rather than waiting on the read beside whatever else does, so a
        // question asked after it is asked after it.
        guard hasRestored || !keepsThread else {
            queueChatChange { store in
                await store.restoration().value
                store.endThread(filing: true)
                await store.resetEngine()
            }
            return
        }
        endThread(filing: true)
        queueChatChange { await $0.resetEngine() }
    }

    /// Delete All Chats: forget the earlier chats, and the one on screen,
    /// which ends the way New Chat ends it and isn't filed on the way out. A
    /// thread that couldn't be read goes too, whether set aside or still in
    /// the thread's place: deleting it is the reader's own instruction. Does
    /// nothing on a domain that keeps no chats.
    public func deleteAllThreads() {
        deleteAllThreads(from: nil)
    }

    /// Delete All Chats from the screen with this id, or from the host where
    /// it's nil (`deleteAllThreads()`), named as New Chat names it
    /// (`startOver(from:)`).
    func deleteAllThreads(from screen: UUID?) {
        guard offersHistory else { return }
        settleTurnInFlight(byReader: true)
        chatRequests &+= 1
        emptyComposer(from: screen)
        // After the saved thread is read, for `startOver`'s reason: the read
        // landing afterwards would put back a chat the reader deleted.
        guard hasRestored else {
            queueChatChange { store in
                await store.restoration().value
                store.endThread(filing: false)
                await store.resetEngine()
            }
            return
        }
        endThread(filing: false)
        queueChatChange { await $0.resetEngine() }
    }

    /// The composer and what the screen keeps of the chat besides its turns,
    /// put back the way a new chat opens: at the tap, before the saved thread
    /// is read as after. Named for the screen that asked, ahead of the bump
    /// the screens hear (`threadEndOrigin`).
    private func emptyComposer(from screen: UUID?) {
        draft = ""
        pendingPhoto = nil
        isThinking = false
        declinedStarters = []
        declinedFollowUps = []
        lastTerminalTurn = nil
        lastTerminalTurnEndedAt = nil
        proposalOutcomeFocus = nil
        threadEndOrigin = screen
        threadGeneration += 1
    }

    /// End the thread on screen, once it has been read: its turns go, filed
    /// first with the earlier chats when `filing`, or deleted with them when
    /// not, which is Delete All Chats. The feedback attachments it produced
    /// go too. The writes are queued after every write before them.
    ///
    /// Whatever holds the thread's place (`heldThread`) is set aside by New
    /// Chat, never deleted, since it is nowhere else, and deleted by Delete
    /// All Chats.
    private func endThread(filing: Bool) {
        // The chat's turns go to the list before the chat goes, taken here,
        // before they are cleared. That includes what was asked after the
        // saved thread couldn't be read: it is the reader's, and it read fine.
        let outgoing = filing && offersHistory ? turns.filter(\.isComplete).map(\.entry) : []
        turns = []
        threadEnds &+= 1
        readFailed = false
        let held = heldThread
        heldThread = nil
        openedChatID = nil
        heldTurnsFiling = nil
        forgetFeedbackAttachments()
        guard keepsThread else { return }
        if filing {
            queueWrite { await $0.endingWrites(filing: outgoing, held: held) }
        } else {
            history = []
            queueWrite { await $0.deletingWrites() }
        }
    }

    /// The engine's side of a chat ending: its turn stopped, then the chat
    /// reset, then a warm for a question already begun.
    private func resetEngine() async {
        // Stopped before it is reset: a turn left running would finish unseen
        // and spend its request.
        await engine.stop()
        await engine.reset()
        await readKeptConversation()
        // The warm went with the chat. The composer is empty now, so this
        // warms nothing; the next question's first keystroke will, after the
        // reset rather than before it.
        await rewarm()
    }

    /// New Chat's writes: the chat filed, then the thread's place emptied.
    ///
    /// **Never the only copy deleted.** The thread is cleared only once the
    /// chat is filed, and a clear that fails then is owed (`deletionOwed`):
    /// left in place, the chat would come back on screen at the next launch
    /// beside its own filing. Not filed (a locked device, a full disk), the
    /// chat is written as the thread and set aside beside it, for the next
    /// launch to file (`AskThreadStore.recoverSetAside`). Written and not
    /// moved, the thread's place is held (`HeldThread.unfiled`) and nothing is
    /// written over it until it moves. Not written either, the chat waits in
    /// `filingsOwed`, and so does one the place couldn't take because what
    /// holds it won't move. What held the place before New Chat is set aside
    /// first, the same way, and never deleted, unless it is what is owed a
    /// delete (`deletionOwed`): that is deleted.
    private func endingWrites(filing outgoing: [AskThreadEntry<Row>], held tapped: HeldThread?) async {
        // What holds the place now, not only at the tap: a New Chat before
        // this one may have found its own held thread wouldn't move, and held
        // it again.
        var held = tapped ?? heldThread
        let filed = outgoing.isEmpty ? true : await archive.fileTheChatOnScreen(outgoing, at: .now, sparing: nil) != nil
        // The turns filed beside a thread that couldn't be read are in this
        // filing now, which took their filing's place in the same write.
        // Where it failed, theirs stays, an ordinary filing from here on, so
        // what of the chat was on disk still is; with nothing to file (a
        // domain that keeps no list), it goes with the chat.
        await archive.endProvisional(removing: filed)
        var placeHoldsDeleted = false
        if deletionOwed.thread {
            // What is owed a delete still holds the place: what Delete All
            // Chats couldn't delete, or a chat filed already. It's deleted,
            // never set aside for a later launch to file or held for a later
            // write to.
            deletionOwed.thread = await !thread.clear()
            placeHoldsDeleted = deletionOwed.thread
            held = nil
            heldThread = nil
            if placeHoldsDeleted { watchForProtectedData() }
        }
        if held != nil, await !thread.setAside() {
            // Still in the thread's place, and still nowhere else, so the
            // chat can't be written there either.
            heldThread = held
            if !filed {
                Logger(subsystem: brand.logSubsystem, category: "ask")
                    .error("a chat New Chat ended could not be filed, and waits to be filed while the thread's place is held")
                oweFiling(outgoing)
            }
            watchForProtectedData()
            await loadHistory()
            return
        }
        // Moved aside, so the place is free, whoever held it.
        if held != nil { heldThread = nil }
        if filed {
            // Cleared already, or owed, when what is owed a delete held it.
            if held == nil, !placeHoldsDeleted, await !thread.clear() {
                deletionOwed.thread = true
                watchForProtectedData()
            }
            await loadHistory()
            return
        }
        if await thread.save(outgoing) {
            // Written over whatever was owed a delete.
            deletionOwed.thread = false
            if await thread.setAside() {
                await loadHistory()
                return
            }
            Logger(subsystem: brand.logSubsystem, category: "ask")
                .error("a chat New Chat ended could not be filed or set aside, and is kept as the thread")
        } else {
            // On disk nowhere: the place is empty, or holds an older save of
            // this chat or what is owed a delete. The chat waits here to be
            // filed.
            Logger(subsystem: brand.logSubsystem, category: "ask")
                .error("a chat New Chat ended could not be filed or written, and waits to be filed")
            oweFiling(outgoing)
            // Holding the place would keep what is owed a delete in it, for a
            // later write to set aside.
            if placeHoldsDeleted {
                await loadHistory()
                return
            }
        }
        // Held, so nothing is written over what the place holds of this chat,
        // its copy or an older save of it, until that is set aside.
        heldThread = .unfiled
        watchForProtectedData()
        await loadHistory()
    }

    /// Keep a chat that is on disk nowhere until the archive takes it
    /// (`filingsOwed`), unless the archive has no folder: a store built from a
    /// folder name that isn't one folder keeps nothing, and owing it every
    /// chat would hold each one New Chat ends in memory for the life of the
    /// process.
    private func oweFiling(_ chat: [AskThreadEntry<Row>]) {
        guard archive.folderURL != nil else { return }
        filingsOwed.append(chat)
    }

    /// Delete All Chats' writes. A chat file or an index that won't go needs
    /// nothing more: the archive keeps every chat off the list and tries
    /// again. What the thread store couldn't delete is owed, and tried again
    /// (`retryWhatWaitsOnTheDisk()`).
    private func deletingWrites() async {
        await archive.removeAll()
        filingsOwed = []
        // What wouldn't go is owed by name, so the retry spares a chat a later
        // New Chat sets aside beside it.
        deletionOwed.setAside = await thread.removeEverySetAside()
        deletionOwed.thread = await !thread.clear()
        // Whatever held the place was the reader's to delete: gone, or owed,
        // and never held again. A New Chat before this one may have held it
        // again after the tap.
        heldThread = nil
        if !deletionOwed.isEmpty { watchForProtectedData() }
        await loadHistory()
    }

    /// Queue a chat change after the one before it, and say when it is done.
    /// The last one queued clears `changingChat` as it ends.
    @discardableResult
    private func queueChatChange(
        _ change: @escaping @MainActor (AskConversationStore) async -> Void
    ) -> Task<Void, Never> {
        let previous = changingChat
        chatChangesQueued &+= 1
        let mine = chatChangesQueued
        let next = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await change(self)
            if self.chatChangesQueued == mine { self.changingChat = nil }
        }
        changingChat = next
        return next
    }

    /// Queue a write after every write before it, and hand back its result.
    ///
    /// The store is held until the write has run: a write queued is a write
    /// made, whatever becomes of the screen.
    @discardableResult
    private func queueWrite<Result: Sendable>(
        _ write: @escaping @MainActor (AskConversationStore) async -> Result
    ) -> Task<Result, Never> {
        let previous = persisting
        let next = Task { () -> Result in
            await previous?.value
            return await write(self)
        }
        persisting = Task { _ = await next.value }
        return next
    }

    /// A transcript of a chat no longer on screen has no business outliving
    /// it. After any verdict still on its way, so a thumb tapped a moment
    /// before is removed rather than written afterwards.
    private func forgetFeedbackAttachments() {
        let pendingVerdict = feedbackTask
        feedbackTask = Task { [weak self, feedbackAttachments] in
            await pendingVerdict?.value
            let owed = self?.deletionOwed.attachments ?? []
            let left = await feedbackAttachments.removeEvery(also: owed)
            guard let self else { return }
            self.feedbackRevision += 1
            // A transcript still on the device is tried again, by name. Those
            // owed before were tried too, and only the ones that went leave
            // the debt: a retry may have paid some off meanwhile.
            self.deletionOwed.attachments.subtract(owed.subtracting(left))
            self.deletionOwed.attachments.formUnion(left)
            if !left.isEmpty { self.watchForProtectedData() }
        }
    }

    /// A `.perLaunch` chat ends with its process, and the attachments it left
    /// go with it: a transcript of a whole session would otherwise stay on
    /// the device, and shareable from the settings card, after the chat it
    /// describes is gone. Once, at the first of `restoreIfNeeded()` and a
    /// verdict, and queued ahead of that verdict's save.
    private func forgetLastLaunchsAttachments() {
        guard !keepsThread, !forgotLastLaunchsAttachments else { return }
        forgotLastLaunchsAttachments = true
        forgetFeedbackAttachments()
    }

    /// Settle the turn in flight, and say whether there was one to settle,
    /// which is then a turn to save.
    @discardableResult
    private func settleTurnInFlight(byReader: Bool) -> Bool {
        task?.cancel()
        task = nil
        waitingQuestion = nil
        guard isThinking else { return false }
        isThinking = false
        guard let last = turns.last else { return false }
        // The overtaken turn's reveal chunks have to be forgotten by whoever
        // settles it, an answered one included: its own task returns on
        // cancellation, and the answer can land a moment before the stream
        // ends. Left behind, the settled turn keeps rendering
        // `TimelineView(.animation(paused: false))` for the life of the screen,
        // its renderer drawing every run of an answer long since drawn, frame
        // after frame, which is the cost this mechanism exists to prevent.
        defer { forgetChunksOnceSettled(last.id) }
        // A turn to save either way, one whose answer landed before its stream
        // ended included: the task that would have saved it returns on the
        // cancellation.
        if !last.isComplete { markStopped(last.id, byReader: byReader) }
        return true
    }

    /// Put the question still waiting to be asked back in the composer, as
    /// Stop or a newer question lets it go: it has no turn to keep it, as a
    /// stopped turn keeps its question, and the draft it came from was
    /// emptied as it was sent. Its scope comes back with it, and its photo
    /// where none waits there. Only into an empty draft: one the reader has
    /// begun since is the newer question, and the waiting one goes.
    private func returnTheWaitingQuestion() {
        guard let waiting = waitingQuestion, draft.isEmpty else { return }
        draft = waiting.text
        draftScope = waiting.scope
        if pendingPhoto == nil, let photo = waiting.photo, let image = waiting.image {
            attachPhoto(image, label: photo.label, reference: photo.reference)
        }
    }

    /// Settle a turn that was stopped before it finished. What it had written
    /// is its answer; a turn that had written nothing offers Try Again, under
    /// a line that says the reader stopped it when they did.
    /// `byReader` is whether the reader asked for the stop (`AskTurn.stopped`).
    private func markStopped(_ id: UUID, byReader: Bool) {
        guard let stopped = turn(id), !stopped.isComplete else { return }
        if stopped.hasContent {
            // The text it had written is its answer. The rows it had read stay
            // with it as `matches`, so the evidence line can still say what the
            // prose stood on; the model never got to choose which to show, so
            // the grid draws none of them.
            update(id) { turn in
                turn.stopped = byReader
                turn.activity = nil
                turn.answer = AskAnswer(
                    text: turn.text, matches: turn.rowsRead, tiles: [],
                    followUps: [], questionKind: nil, isTruncated: true
                )
            }
            noteTerminal(id, at: clock())
        } else {
            update(id) { turn in
                turn.stopped = byReader
                turn.activity = nil
            }
            // The reader's own stop says so, and offers Try Again all the
            // same: "Couldn't answer" would be untrue (`AskTurn.Failure`).
            fail(id, with: .stopped, stoppedByReader: byReader)
        }
    }

    private func fail(_ id: UUID, with error: AskError, stoppedByReader: Bool = false) {
        // A turn ends once. An engine that answers and then throws breaks the
        // stream's contract, and its answer stays without a failure under it.
        guard let failing = turn(id), !failing.isComplete else {
            Logger(subsystem: brand.logSubsystem, category: "ask")
                .error("a turn that had ended failed again: \(AskTriage.tag(for: error), privacy: .public)")
            return
        }
        // A refused or ungrounded failure has somewhere to go: the coaching,
        // two starters under the line, so a blocked reader isn't left at a
        // dead end.
        let coaching = error.isCoached ? Array(availableStarters.prefix(2)) : []
        update(id) { turn in
            turn.activity = nil
            turn.failure = AskTurn.Failure(
                message: Turn.Failure.message(for: error, stoppedByReader: stoppedByReader),
                retryable: error.isRetryable,
                error: error,
                coaching: coaching
            )
        }
        noteTerminal(id, at: clock())
        // As in `begin`: never clear the flag on behalf of a turn that has
        // been overtaken.
        if turns.last?.id == id { isThinking = false }
    }

    // MARK: - The library, the model, the disk

    /// Read the library's overview and the starters again, give a failure
    /// read back from disk its coaching, and have the engine read every
    /// tier's state again (`AskAsking.refreshStatus()`). The screen calls it
    /// as it appears and as the app comes back to the foreground. A host may
    /// call it too, such as when its library changes while the screen is up.
    ///
    /// Beside those, what the disk refused is tried again: a thread the
    /// device was too locked to read, a save, a chat New Chat couldn't file,
    /// what Delete All Chats couldn't delete, and the feedback attachments a
    /// chat that ended left. The screen coming back is
    /// the moment the reader is looking, on every platform.
    ///
    /// **The overview holds back nothing else.** It is the host's hook, and
    /// one that counts a library over the network, or never returns, would
    /// keep a device that can't serve from saying so and leave a refused
    /// save waiting. So the three run at once, and the overview gets the
    /// domain's turn deadline (`AskDomain.turnDeadline`), the time its hooks
    /// have within a turn: one still out then is abandoned, and the overview
    /// read before it stands. The overview is read off the main actor.
    public func refresh() async {
        async let overviewRead: Void = readOverview()
        async let statusRead: Void = readStatus()
        async let diskRetry: Void = retryWhatWaitsOnTheDisk()
        _ = await (overviewRead, statusRead, diskRetry)
    }

    /// `refresh()`'s read of the overview and the starters it gives.
    private func readOverview() async {
        overviewReadsBegun &+= 1
        let read = overviewReadsBegun
        let domain = domain
        let fresh = try? await AskDeadline.run(domain.turnDeadline) { await Self.overview(of: domain) }
        guard let fresh else {
            guard !Task.isCancelled else { return }
            Logger(subsystem: brand.logSubsystem, category: "ask")
                .error("the domain's overview did not return within its turn deadline, so the last one read stands")
            // Before any read has landed, the first screen waits no longer: it
            // opens as on a library it knows nothing of, never one it calls
            // empty (`AskStage.firstScreenIsKnown`).
            if !hasReadOverview { overviewIsOverdue = true }
            return
        }
        guard read > overviewReadLanded else { return }
        overviewReadLanded = read
        overview = fresh
        // Ask for as many as the first screen can show, or a domain that
        // windows by this number hands back a phone's three on a Mac.
        starters = domain.starters(overview: fresh, window: AskLayout.starterBank)
        hasReadOverview = true
        restoreCoaching()
    }

    /// The domain's overview, read off every actor: a plain `nonisolated
    /// async` overview runs where it is called from, and a count over a large
    /// store on the main actor would hitch every return to the foreground.
    @concurrent nonisolated private static func overview(of domain: Domain) async -> AskOverview {
        await domain.overview()
    }

    /// `refresh()`'s read of every tier's state, and of whether the engine
    /// keeps a conversation.
    private func readStatus() async {
        await engine.refreshStatus()
        await readKeptConversation()
        // After the refresh, not before: until it returns, a mirror nobody
        // has published to reads as a tier serving (`statusIsRead`).
        hasRefreshedStatus = true
    }

    /// Whether the first screen can trust the mirror yet: its seam has
    /// published to it, or the engine's refresh has returned, for an engine
    /// whose refresh publishes nothing. Before either, nothing serving and
    /// nothing known look alike, and a device that can't serve would open on
    /// the ready screen for the length of a Private Cloud Compute probe.
    var statusIsRead: Bool { hasRefreshedStatus || status.hasHeardFromSeam }

    /// Give the coaching back to a refused or ungrounded failure that has
    /// none, such as one read back from disk.
    ///
    /// The coaching isn't persisted: it is `AskStarter`s the domain makes from
    /// the library, and frozen on disk it would pin a suggestion to a library
    /// that has since changed. So it is derived again here, or a failure read
    /// back would leave the reader at the dead end the coaching exists to
    /// avoid. Here rather than in `restoreIfNeeded`, because `starters` is
    /// empty until `refresh()` has read them.
    private func restoreCoaching() {
        let offered = Array(availableStarters.prefix(2))
        guard !offered.isEmpty else { return }
        for turn in turns where turn.failure?.coaching.isEmpty == true {
            guard let failure = turn.failure, failure.error?.isCoached == true else { continue }
            update(turn.id) { turn in
                turn.failure = AskTurn.Failure(
                    message: failure.message, retryable: failure.retryable,
                    error: failure.error, coaching: offered
                )
            }
        }
    }

    /// Keep a session warm on the host's behalf: one is warmed as the reader's
    /// question begins (`draft`), or now if they have one half-typed, until
    /// `releaseWarmSession()`. `AskScreen` warms for itself; call this only to
    /// keep warming while no Ask screen is up.
    ///
    /// **An appearance alone warms nothing.** A warm on Private Cloud Compute
    /// spends a request of the reader's daily quota, and most appearances,
    /// returns to the app and New Chats ask nothing. The cost is a cold start
    /// for a first question nobody typed, such as a starter. Nor does a
    /// question a prefill left that the reader hasn't touched.
    public func prewarm() async {
        keepsWarm = true
        await warmForTheReadersDraft()
    }

    /// `prewarm()` for the screen that holds `screen`, until it disappears
    /// (`screenDisappeared(_:)`).
    func prewarm(for screen: UUID) async {
        warmingScreens.insert(screen)
        await warmForTheReadersDraft()
    }

    private func warmForTheReadersDraft() async {
        guard draftIsReaders else { return }
        await engine.prewarm()
    }

    /// Warm again, while a screen still wants a warm session and the reader's
    /// question has begun: as the app comes back to the foreground with a
    /// half-typed question, where a warm made before it left may be past
    /// `AskEngine.warmMaxAge`, 300 s, and a younger one the engine leaves
    /// alone. As a chat ends the warm goes with it and the composer is empty,
    /// so this warms nothing until the next keystroke. Never once every screen
    /// has gone: a warm nobody will take is retained until a screen next
    /// disappears.
    func rewarm() async {
        guard wantsWarm, draftIsReaders else { return }
        await engine.prewarm()
    }

    /// Undo the host's `prewarm()`: stop warming for it, and drop a warm
    /// session no question took (`AskAsking.forgetWarmIfEmpty()`), unless an
    /// Ask screen that is up still wants one. A kept conversation stays. Kept,
    /// a warm session nobody takes would hold its tool set, its collector and
    /// its relay for the life of the process.
    public func releaseWarmSession() async {
        keepsWarm = false
        guard !wantsWarm else { return }
        await engine.forgetWarmIfEmpty()
    }

    // MARK: - The screens
    //
    // What a screen hands the face in a host's slot, its style and whether its
    // composer is raised over it, isn't kept here: one store stands behind a
    // screen in each of an app's windows, and each window has a slot of its
    // own, which holds what its own screen reports (`askComposerSlot`).

    /// The screen holding `screen` has gone: its warm session goes unless
    /// another screen wants it (`releaseWarmSession()`).
    func screenDisappeared(_ screen: UUID) async {
        warmingScreens.remove(screen)
        guard !wantsWarm else { return }
        await engine.forgetWarmIfEmpty()
    }

    /// Open Apple's limit-increase route: what Show options does, on the
    /// quota banner and on the settings card.
    public func showLimitIncrease() async {
        await engine.showLimitIncrease()
    }

    /// Read the thread back from disk, once. A domain that keeps its thread
    /// for the process only (`AskPersistence.perLaunch`) restores nothing.
    ///
    /// Every caller waits for the same read, so a host that awaits this before
    /// asking never puts its question into a thread the read then replaces.
    /// The screen calls it as it appears, and a host may call it first.
    public func restoreIfNeeded() async {
        await restoration().value
    }

    /// The read of the saved thread: begun on the first call, shared by every
    /// call after it.
    private func restoration() -> Task<Void, Never> {
        if let restoring { return restoring }
        let read = Task { [weak self] in
            guard let self else { return }
            await self.restore()
        }
        restoring = read
        return read
    }

    private func restore() async {
        defer { hasRestored = true }
        guard keepsThread else {
            forgetLastLaunchsAttachments()
            return
        }
        // Listening before the read, not once it has failed: protected data
        // coming back between the two would reach nobody, and a thread that
        // reads by then would stay held, its notice up, until the screen next
        // came back. A word that lands while the read is under way waits for
        // it (`retryWhatWaitsOnTheDisk()`), and the listening stops here
        // where the read left nothing waiting.
        watchForProtectedData()
        defer { if heldThread == nil, !writesAreOwed { stopWatchingForProtectedData() } }
        // Before the list is read, so a thread set aside on an earlier launch
        // that reads now is in it.
        await thread.recoverSetAside(into: archive)
        await loadHistory()
        guard turns.isEmpty else { return }
        switch await thread.load() {
        case .thread(let entries, _):
            // Read in part, it opens with the turns that decode: the thread
            // store has kept the file whole beside it, and a launch that reads
            // the rest puts them back (`AskThreadStore.load()`), so saving
            // these over it costs the reader nothing. Filed too, it opens
            // joined with its filing (`takeIn`).
            let filing = await filingOfTheChat(in: entries)
            let restored = withLateOutcomes(filing.map { AskThreadEntry.merging($0.entries, into: entries) } ?? entries)
            turns = restored.map(readBack)
            if let filing { takeIn(filing) }
            // The session died with the process; the thread didn't. Handing
            // the engine the tail is what lets the first question on a
            // restored thread start its session with a recap rather than with
            // nothing: "is it still on loan?" the next morning has an *it*.
            let tail = Self.recapTail(from: restored, domain: domain)
            if !tail.isEmpty {
                await engine.resume(from: tail)
                await readKeptConversation()
            }
        case .empty:
            break
        case .unreadable:
            // There is a thread and it couldn't be read. Restoring nothing is
            // right; *writing* over it is not. A thread this build can make
            // nothing of (bytes that aren't one, or no turn that decodes) is
            // set aside so the next answer has its place. One that couldn't
            // be read at all may be a good one, and stays where it is until
            // it can be read (`retryWhatWaitsOnTheDisk()`).
            readFailed = true
            // Still listening, from before the read.
            if await !thread.setAsideIfNotAThread() { heldThread = .unreadable }
        }
    }

    /// What the engine is told a restored thread said: its last exchanges
    /// by the rule the engine keeps its own tail by (`AskContinuation`), a
    /// model's answer with prose, the one the reader stopped included, newest
    /// last. The newest one's titles are widened to the domain's referent,
    /// which is the list a follow-up's "those" resolves against.
    static func recapTail(from entries: [AskThreadEntry<Row>], domain: Domain) -> [AskThreadTail] {
        AskContinuation.tail(from: entries, referent: domain.referent(from:))
    }

    /// Write the thread out, off the main actor in `AskThreadStore`, after
    /// every write queued before it.
    ///
    /// Writes the thread as it stands when the write runs, not when it was
    /// queued: a thread read back meanwhile is in it, and a later state is
    /// never older than an earlier one. Unless the thread has ended since
    /// (`threadEnds`): written then, the empty thread New Chat leaves would
    /// clear the chat before New Chat's own writes file it.
    ///
    /// Writes nothing in the thread's place while it is held (`heldThread`),
    /// which it checks when the write runs, since New Chat's own writes can
    /// hold it: the turns are filed beside what holds it
    /// (`heldTurnsFiling`). A read that failed leaves `turns` empty,
    /// which is indistinguishable from a fresh thread, and the next completed
    /// turn would write a one-entry array over a conversation that is still
    /// on disk and may read fine once the device is unlocked.
    ///
    /// Declines until the read has finished, for the same reason: before it,
    /// `turns` is just as empty and the thread on disk just as whole.
    func persist() {
        guard keepsThread, hasRestored else { return }
        let ends = threadEnds
        // Chained, not cancelled and replaced: cancelling a task does not stop
        // a write it has already handed the actor, so two saves could land in
        // either order and the older could win. In order, the newest is last.
        queueWrite { store in
            guard store.threadEnds == ends else { return }
            _ = await store.writeThread(store.turns.filter(\.isComplete).map(\.entry))
        }
    }

    /// Write `entries` as the thread, unless the thread's place is held, and
    /// say whether they are on disk. In the write queue. Held, they are filed
    /// beside what holds it instead (`fileBesideTheHeldThread`), once a chat
    /// New Chat couldn't file has been tried aside and wouldn't move.
    ///
    /// A false from the thread store is owed: saved again as protected data
    /// comes back and as the screen does (`retryWhatWaitsOnTheDisk()`).
    private func writeThread(_ entries: [AskThreadEntry<Row>]) async -> Bool {
        switch heldThread {
        case .unreadable: return await fileBesideTheHeldThread(entries)
        case .unfiled: guard await freeTheThreadsPlace() else { return await fileBesideTheHeldThread(entries) }
        case nil: break
        }
        let saved = await thread.save(entries)
        saveOwed = !saved
        if saved {
            // What was owed a delete is written over now.
            deletionOwed.thread = false
            // And the turns filed while a thread that couldn't be read held
            // the place are in the thread now, so their filing goes.
            if heldTurnsFiling != nil {
                heldTurnsFiling = nil
                await archive.endProvisional(removing: true)
                await loadHistory()
            }
        } else {
            watchForProtectedData()
        }
        return saved
    }

    /// Keep the turns asked while the thread's place is held, by a thread
    /// that couldn't be read or a chat New Chat couldn't file and that won't
    /// move, without writing over it: filed with the earlier chats as a chat
    /// of their own, under one ID that each turn files again over, and left
    /// out of the list while they are on screen (`heldTurnsFiling`). Say
    /// whether they are on disk.
    ///
    /// Kept only in memory, they would go with a process that ended before
    /// New Chat filed them or the place came free, and nothing on screen
    /// says they weren't kept: the notice that the thread couldn't be read
    /// goes at the first question, and a chat New Chat couldn't file has
    /// none. Filed provisionally (`AskThreadArchive.fileProvisionally`): a
    /// copy of what is on screen, it takes no earlier chat's place in a full
    /// list, and New Chat files the chat over it
    /// (`AskThreadArchive.fileTheChatOnScreen`).
    ///
    /// The ID is taken before the filing is awaited, and nothing here
    /// touches it after: a New Chat while the archive works has cleared it
    /// for good, and its own writes, queued behind this one, end the filing.
    private func fileBesideTheHeldThread(_ entries: [AskThreadEntry<Row>]) async -> Bool {
        guard !entries.isEmpty else {
            saveOwed = false
            return true
        }
        let id = heldTurnsFiling ?? UUID()
        heldTurnsFiling = id
        let ends = threadEnds
        let filed = await archive.fileProvisionally(entries, as: id) != nil
        saveOwed = !filed
        guard filed else {
            watchForProtectedData()
            return false
        }
        if threadEnds == ends { await loadHistory() }
        return true
    }

    /// Set aside the chat that holds the thread's place because New Chat
    /// couldn't file it, for a later launch to file
    /// (`AskThreadStore.recoverSetAside`), and say whether the place is free.
    private func freeTheThreadsPlace() async -> Bool {
        if await thread.setAside() {
            heldThread = nil
            return true
        }
        // Gone already, if New Chat couldn't write it at all: nothing holds
        // the place.
        if case .empty = await thread.load() {
            heldThread = nil
            return true
        }
        return false
    }

    /// Try again what the disk refused: a thread the device was too locked to
    /// read, a save it failed, a chat New Chat couldn't file, and what Delete
    /// All Chats couldn't delete. As protected data comes back
    /// (`UIApplication`'s `.protectedDataDidBecomeAvailable`, on the iOS
    /// family) and as the screen does (`refresh()`). Does nothing when
    /// nothing waits. A domain that keeps no thread can still owe the
    /// feedback attachments a chat left, and those are tried again too.
    ///
    /// Asked while the saved thread is still being read, it waits for the
    /// read rather than doing nothing, since what the read leaves held is
    /// what it is for; a read nothing has begun, it doesn't begin.
    func retryWhatWaitsOnTheDisk() async {
        if keepsThread, !hasRestored, let restoring { await restoring.value }
        guard !keepsThread || hasRestored else { return }
        if heldThread == .unreadable { await rereadHeldThread() }
        if writesAreOwed {
            let ends = threadEnds
            await queueWrite { await $0.retryOwedWrites(ifTheThreadStill: ends) }.value
        }
        if heldThread == nil, !writesAreOwed { stopWatchingForProtectedData() }
    }

    private var writesAreOwed: Bool {
        heldThread == .unfiled || saveOwed || !deletionOwed.isEmpty || !filingsOwed.isEmpty
    }

    /// The writes the disk refused, again, in the write queue. The thread is
    /// saved only while it hasn't ended since the retry was queued, as
    /// `persist()` saves it.
    private func retryOwedWrites(ifTheThreadStill ends: Int) async {
        if !deletionOwed.setAside.isEmpty {
            deletionOwed.setAside = await thread.removeSetAside(named: deletionOwed.setAside)
        }
        if deletionOwed.thread {
            deletionOwed.thread = await !thread.clear()
        }
        var stillOwed: [[AskThreadEntry<Row>]] = []
        for chat in filingsOwed {
            let filed = await archive.archive(chat) != nil
            if !filed { stillOwed.append(chat) }
        }
        if stillOwed.count != filingsOwed.count {
            filingsOwed = stillOwed
            await loadHistory()
        }
        if !deletionOwed.attachments.isEmpty {
            // Only the names that went leave the debt: a New Chat meanwhile
            // may have added its own.
            let owed = deletionOwed.attachments
            let left = await feedbackAttachments.remove(named: owed)
            deletionOwed.attachments.subtract(owed.subtracting(left))
        }
        if heldThread == .unfiled || saveOwed, threadEnds == ends {
            _ = await writeThread(turns.filter(\.isComplete).map(\.entry))
        }
    }

    /// Read the thread that couldn't be read at all again, and when it reads,
    /// put its turns above the ones asked since, so neither is lost, and let
    /// the thread be saved again.
    ///
    /// Not if the chat has changed meanwhile: New Chat sets that thread aside
    /// and Delete All Chats deletes it, and either ends the chat it would
    /// have gone into.
    private func rereadHeldThread() async {
        let requests = chatRequests
        let read = await thread.load()
        var filing: Filing?
        if case .thread(let entries, _) = read { filing = await filingOfTheChat(in: entries) }
        guard heldThread == .unreadable, requests == chatRequests else { return }
        switch read {
        case .thread(let onDisk, _):
            let askedSince = turns
            // Joined with its filing, as a launch joins it (`takeIn`).
            let entries = withLateOutcomes(filing.map { AskThreadEntry.merging($0.entries, into: onDisk) } ?? onDisk)
            turns = entries.map(readBack) + askedSince
            heldThread = nil
            readFailed = false
            restoreCoaching()
            if let filing { takeIn(filing) } else { persist() }
            // The engine is handed the thread's tail as a launch hands it,
            // unless the reader has asked since: the conversation that holds
            // is newer than anything on disk.
            if askedSince.isEmpty, !isThinking {
                let tail = Self.recapTail(from: entries, domain: domain)
                if !tail.isEmpty {
                    await engine.resume(from: tail)
                    await readKeptConversation()
                }
            }
        case .empty:
            // Gone meanwhile: nothing holds the place, and nothing explains.
            heldThread = nil
            readFailed = false
            persist()
        case .unreadable:
            // Read now, and not a thread: set aside as a launch would set it
            // aside. Still locked, it waits on.
            guard await thread.setAsideIfNotAThread() else { return }
            heldThread = nil
            persist()
        }
    }

    /// Listen for protected data coming back while a thread waits on it, or
    /// is being read: on the iOS family, complete file protection refuses
    /// every read and write of the thread while the device is locked.
    /// Elsewhere `refresh()` alone tries again.
    private func watchForProtectedData() {
        #if os(iOS) || os(visionOS)
        guard protectedDataObservation == nil else { return }
        protectedDataObservation = NotificationCenter.default.addObserver(
            of: UIApplication.self, for: .protectedDataDidBecomeAvailable
        ) { [weak self] _ in
            self?.protectedDataBecameAvailable()
        }
        #endif
    }

    private func stopWatchingForProtectedData() {
        #if os(iOS) || os(visionOS)
        guard let protectedDataObservation else { return }
        NotificationCenter.default.removeObserver(protectedDataObservation)
        self.protectedDataObservation = nil
        #endif
    }

    /// Protected data is back: try again what the disk refused.
    func protectedDataBecameAvailable() {
        Task { await retryWhatWaitsOnTheDisk() }
    }

    /// Wait for the pending write, if any. For tests, which would otherwise
    /// have nothing to await but a sleep.
    func flushPersistence() async {
        await persisting?.value
    }

    // MARK: - Earlier chats

    /// Whether this domain keeps chats to go back to. A per-launch domain
    /// forgets a chat with the process, so there is nothing to list.
    public var offersHistory: Bool { domain.persistence == .thread }

    /// The chat on screen as the history list shows it, above the earlier
    /// ones: the turns New Chat would file. Nil until one of them has ended.
    ///
    /// Read from the thread's shape, so a view that reads it, the toolbar's
    /// chats and the pane beside iPhone Duo's fold, hears a turn end and not
    /// every snapshot of one.
    public var currentSummary: AskThreadSummary? {
        // The shape: `shape`.
        guard offersHistory, let ended = shape.ended else { return nil }
        return AskThreadSummary(
            id: currentChatID, title: ended.title, startedAt: ended.startedAt,
            updatedAt: ended.updatedAt, turnCount: ended.count
        )
    }

    /// Read the list of earlier chats again. The earlier chat on screen is
    /// left out of it while it is there.
    public func loadHistory() async {
        guard offersHistory else { return }
        // The earlier chat on screen is `openedChatID`.
        let summaries = await archive.summaries()
        history = summaries.filter { $0.id != openedChatID && $0.id != heldTurnsFiling }
    }

    /// Go back to an earlier chat from the history list.
    ///
    /// The turn in flight stops where it stands, and the chat on screen is
    /// filed first, so nothing the reader leaves is discarded to open another:
    /// a chat that can't be filed stays on screen, and nothing opens. The
    /// chosen chat becomes the thread and comes off the list, the composer
    /// empties, and the engine is handed the chat's tail the way a relaunch
    /// hands one, so the next question starts its session with a recap. A
    /// filing of the chat on screen itself, which an interrupted write can
    /// leave, joins the screen's turns instead, and the chat goes on.
    ///
    /// A chat gone from disk leaves the list. One that won't read stays on it
    /// untouched, and nothing opens. Nothing opens either while the thread's
    /// place on disk holds what is nowhere else (a saved thread a locked
    /// device couldn't read, or a chat New Chat couldn't file): opening would
    /// write over it. Does nothing on a domain that keeps no chats.
    ///
    /// Queued behind any chat change before it, and given way to by any asked
    /// for while it reads or files, so the reader's last tap wins and two
    /// opens never file the same chat over the one between them.
    public func openThread(_ summary: AskThreadSummary) async {
        guard offersHistory else { return }
        chatRequests &+= 1
        let request = chatRequests
        await queueChatChange { store in
            // After the saved thread is read. Before it, the chat on screen is
            // still empty, so the thread on disk would be written over without
            // being filed, and the read landing afterwards would replace the
            // chat opened.
            await store.restoration().value
            await store.open(summary, request: request)
        }.value
        // The reset took the warm, and the composer is empty, so this warms
        // nothing until the reader types; a chat that rejoined its own filing
        // kept both, and warms as a return to the app would. Last, so the chat
        // is on screen before anything could wait on a session being built.
        await rewarm()
    }

    /// `openThread`'s change: the chat on screen filed, then the screen, then
    /// the disk, then the engine.
    private func open(_ summary: AskThreadSummary, request: Int) async {
        // Read once the writes before it have run: New Chat's run on the write
        // queue, not this one, and may still be about to hold the place for a
        // chat they couldn't file or move (`endingWrites`).
        await persisting?.value
        guard heldThread == nil else { return }
        let read = await archive.entries(for: summary.id)
        // The reader asked for something else while it read.
        guard request == chatRequests else { return }
        guard case .thread(let onDisk, let dropped) = read, !onDisk.isEmpty else {
            if case .empty = read { await archive.remove(summary.id) }
            await loadHistory()
            return
        }
        // A question waiting to be asked waits on, to be asked on this chat,
        // whenever it was asked: no turn of the chat on screen yet, it would
        // go with nothing left of it. A turn in flight is settled, and goes
        // with the chat it is on.
        let settled = !questionWaits && settleTurnInFlight(byReader: true)
        let outgoing = turns.filter(\.isComplete).map(\.entry)
        if AskThreadSummary.of(onDisk, id: summary.id, fallbackDate: .distantPast)?.isSameChat(as: outgoing) == true {
            rejoin(onDisk, filed: summary.id, dropped: dropped)
            return
        }
        // Filed before anything leaves the screen, and awaited: unfiled (a
        // locked device, a full disk), the chat on screen stays there, since
        // opening the other would write over its last copy.
        if !outgoing.isEmpty {
            // Turns filed beside a thread that couldn't be read, and read since,
            // are in this filing, which takes their filing's place.
            let filed = await queueWrite { [archive] _ in
                await archive.fileTheChatOnScreen(outgoing, at: .now, sparing: summary.id) != nil
            }.value
            guard filed else {
                Logger(subsystem: brand.logSubsystem, category: "ask")
                    .error("the chat on screen could not be filed, so an earlier chat did not open")
                // The chat stays, with the turn this stopped: saved as Stop
                // saves one, since its own task returned without a save.
                if settled { persist() }
                return
            }
            // Filed, and still the reader's last request: anything asked for
            // meanwhile files this chat again, which replaces this filing.
            guard request == chatRequests else { return }
        }

        // With what came of a proposal whose perform returned after the chat
        // was filed, where the filing doesn't hold it yet. Here, past the last
        // wait: a perform that returns during the filing above finds no turn
        // on screen to settle, and leaves its outcome to this.
        let entries = withLateOutcomes(onDisk)
        turns = entries.map(readBack)
        threadEnds &+= 1
        // Filed with the chat just now, if any: that filing is the reader's.
        // With nothing on screen to file, it is an ordinary one from here on,
        // as its turns are on screen no more (`endProvisional`, below).
        heldTurnsFiling = nil
        draft = ""
        pendingPhoto = nil
        declinedStarters = []
        declinedFollowUps = []
        lastTerminalTurn = nil
        lastTerminalTurnEndedAt = nil
        proposalOutcomeFocus = nil
        openedChatID = summary.id
        forgetFeedbackAttachments()

        // Written, then taken off the list: interrupted between, a chat is in
        // two places rather than none, and filing it again replaces the
        // earlier filing (`AskThreadArchive.archive`). Its filing stays when
        // it couldn't be written, and when some of its turns didn't decode,
        // since the filing is then their only copy; the list leaves it out
        // while the chat is on screen. Queued before a question waiting on
        // this change is asked, so its turn is saved after the chat it joins,
        // not under it.
        queueWrite { [archive] store in
            await archive.endProvisional(removing: false)
            if await store.writeThread(entries), dropped == 0 {
                await archive.remove(summary.id)
            }
            await store.loadHistory()
        }

        // The engine after the screen, and a question asked of the chat now
        // showing waits for all of it (`start`): its turn stopped, its session
        // gone and the chosen chat's tail handed over first.
        await engine.stop()
        await engine.reset()
        let tail = Self.recapTail(from: entries, domain: domain)
        if !tail.isEmpty { await engine.resume(from: tail) }
        await readKeptConversation()
    }

    /// A filing read back: its turns, and how many didn't decode.
    private struct Filing {
        let id: UUID
        let entries: [AskThreadEntry<Row>]
        let dropped: Int
    }

    /// A filing of the chat the thread holds, as read: a New Chat that filed
    /// the chat and couldn't clear the thread after leaves it in both places,
    /// and so does an open interrupted between writing the chat it opened and
    /// taking its filing off the list. Nil where the list holds none, or it
    /// won't read.
    private func filingOfTheChat(in entries: [AskThreadEntry<Row>]) async -> Filing? {
        guard let summary = history.first(where: { $0.isSameChat(as: entries) }),
              case .thread(let filed, let dropped) = await archive.entries(for: summary.id), !filed.isEmpty
        else { return nil }
        return Filing(id: summary.id, entries: filed, dropped: dropped)
    }

    /// Take the filing of the chat the thread holds into the chat, as `rejoin`
    /// takes one into the chat on screen: its turns are on screen already,
    /// joined with the thread's (`AskThreadEntry.merging`), so the chat is
    /// written as the thread, and the filing then comes off the list, kept on
    /// disk where the write failed or some of its turns didn't decode.
    ///
    /// Left as the thread alone, the chat would be filed over its filing by
    /// the next New Chat or the next chat opened, with only what the thread
    /// holds: a turn New Chat stopped, or an outcome or a verdict whose save
    /// failed, would go.
    private func takeIn(_ filing: Filing) {
        openedChatID = filing.id
        history.removeAll { $0.id == filing.id }
        let ends = threadEnds
        // Ended before this runs, the chat is filed by its New Chat or the
        // open that ended it, over this filing, which holds no turn it lacks.
        queueWrite { [archive] store in
            guard store.threadEnds == ends else { return }
            if await store.writeThread(store.turns.filter(\.isComplete).map(\.entry)), filing.dropped == 0 {
                await archive.remove(filing.id)
            }
            await store.loadHistory()
        }
    }

    /// Open the filing of the chat on screen: a chat in two places that the
    /// read of the thread didn't join (`filingOfTheChat`, `takeIn`), its
    /// filing unreadable then, say, or one a write interrupted between filing
    /// the chat and taking it off the screen left.
    ///
    /// **The screen's turns stay**, but for a failure Try Again replaced.
    /// Filed beside the filing and replaced by it, the chat would lose every
    /// turn asked since the filing was made. So the turns only the filing
    /// holds join the screen's, a turn both hold keeps the outcome and
    /// verdict only the filing's had, and every turn is in the order asked
    /// (`AskThreadEntry.merging`), that is written as the thread, and the
    /// filing then comes off the list as an opened chat's does, kept on disk
    /// where it couldn't be written or some of its turns didn't decode. The
    /// chat goes on: the engine keeps its conversation, and the composer and
    /// the feedback attachments stay.
    private func rejoin(_ filed: [AskThreadEntry<Row>], filed id: UUID, dropped: Int) {
        let onScreen = turns.filter(\.isComplete)
        let merged = withLateOutcomes(AskThreadEntry.merging(filed, into: onScreen.map(\.entry)))
        if merged != onScreen.map(\.entry) {
            // The screen's own turns keep what a turn read back lacks: their
            // photos' pixels and their scopes. Found by question and date, as
            // `merged` may leave one out, a failure Try Again replaced.
            var kept = onScreen
            turns = merged.map { entry in
                guard let index = kept.firstIndex(where: {
                    $0.entry.question == entry.question && $0.entry.askedAt == entry.askedAt
                }) else { return readBack(entry) }
                var next = kept.remove(at: index)
                next.proposalOutcome = entry.proposalOutcome
                next.isPerformingProposal = entry.proposalOutcome == .performing
                    && performingProposals.contains(DiskTurn(next))
                next.feedback = entry.feedback
                return next
            }
            restoreCoaching()
        }
        openedChatID = id
        queueWrite { [archive] store in
            if await store.writeThread(merged), dropped == 0 {
                await archive.remove(id)
            }
            await store.loadHistory()
        }
    }

    /// Forget an earlier chat. Does nothing on a domain that keeps no chats.
    public func deleteThread(_ summary: AskThreadSummary) async {
        guard offersHistory else { return }
        history.removeAll { $0.id == summary.id }
        await archive.remove(summary.id)
        await loadHistory()
    }

    // MARK: - What the view reads

    /// The thread reduced to what the screen reads of it besides its rows.
    struct ThreadShape: Equatable {
        var ids: [UUID] = []
        var lastHasText = false
        var lastIsComplete = false
        var lastTier: AskTier?
        /// The turns that have ended, as the history list sums them up
        /// (`currentSummary`). Nil until one has.
        var ended: Ended?

        /// The first ended turn's question and when it was asked, when the
        /// last was, and how many have ended.
        struct Ended: Equatable {
            var title: String
            var startedAt: Date
            var updatedAt: Date
            var count: Int
        }

        init() {}

        init(_ turns: [Turn]) {
            ids = turns.map(\.id)
            lastHasText = !(turns.last?.text.isEmpty ?? true)
            lastIsComplete = turns.last?.isComplete ?? false
            lastTier = turns.last?.tier
            for turn in turns where turn.isComplete {
                if ended == nil {
                    ended = Ended(title: turn.question, startedAt: turn.askedAt, updatedAt: turn.askedAt, count: 1)
                } else {
                    ended?.updatedAt = turn.askedAt
                    ended?.count += 1
                }
            }
        }
    }

    /// What the stage, the caption, New Chat, the follow, the chats in the
    /// toolbar and the pane, and the unreadable thread's notice read of the
    /// thread, kept beside `turns` rather than derived from it on every read.
    ///
    /// **Derived, it would tie the whole screen to every token.** Each of those
    /// would read `turns`, which changes with every streamed snapshot, so
    /// `AskScreen.body` (its toolbar, its composer bar, every modifier on it)
    /// would run once a snapshot to draw one row's new words. Counted with
    /// the screen in an `NSHostingView`, a turn of 40 snapshots on a thread of
    /// four ran it 44 times derived, and 5 times reading this. Swift 6.4's
    /// `@Observable` publishes an `Equatable` write only when the value
    /// differs (`AskScrollFollow` has the probe), so this is written on
    /// every change to `turns` and heard only when a turn arrives or goes,
    /// writes its first words, ends, or changes tier.
    private var shape = ThreadShape()

    /// Whether the thread has anything on it: what New Chat and a host's own
    /// command enable on. Read this rather than `turns.isEmpty`, which ties
    /// whoever reads it to every streamed snapshot.
    public var hasTurns: Bool { !shape.ids.isEmpty }

    /// The newest turn's identity: the key the thread's follow and its scroll
    /// to the end start on. Read this rather than `turns.last?.id`, for
    /// `hasTurns`'s reason.
    public var lastTurnID: UUID? { shape.ids.last }

    /// The thread's stage: the screen's one layout animation key a turn can
    /// reach (`AskStage`), and which first screen shows, if any. It changes
    /// with the thread's shape, with a turn starting or ending, and with
    /// which first screen applies, never with a snapshot's words alone.
    public var stage: AskStage {
        AskStage.of(
            turnIDs: shape.ids, lastHasText: shape.lastHasText,
            lastIsComplete: shape.lastIsComplete, isThinking: isThinking,
            overview: overview, unavailability: unavailability,
            policy: domain.firstScreenPolicy, hasNothingToAskCopy: brand.nothingToAskCopy != nil,
            overviewIsRead: hasReadOverview, overviewIsOverdue: overviewIsOverdue, statusIsRead: statusIsRead
        )
    }

    /// Whether the composer is disabled: only on the can't-serve first screen
    /// (`AskStage.Phase.cannotServe`), and only when the domain can't answer
    /// without a model. A domain that can keeps it live, since its own data
    /// can still route a typed question. A thread with turns never disables
    /// it, a turn in flight included. The composer and its face in the slot
    /// both read this.
    var composerIsDisabled: Bool {
        if case .cannotServe = stage.phase {
            return !domain.firstScreenPolicy.answersWithoutModel
        }
        return false
    }

    /// The engine's mirror (`AskAsking.status`), which the tier caption, the
    /// can't-serve first screen and the quota banner read. Read straight
    /// through rather than copied, so the screen can never disagree with the
    /// engine about who is serving.
    public var status: AskModelStatus { engine.status }

    /// Whether the engine keeps a conversation, so a follow-up chip has
    /// something to refer to (`AskAsking.hasKeptConversation`), as the store
    /// last read it: as each turn's stream ended, after the engine's reset, a
    /// restore and a seed, and in `refresh()`. The follow-up chips read it.
    ///
    /// **The engine's, never the mirror's.** The seam, and its mirror, can be
    /// shared with another engine, such as an evaluation's, whose resets would
    /// otherwise hide this thread's chips.
    public private(set) var hasKeptConversation = false

    /// The newest read of the engine's `hasKeptConversation`. A read that
    /// lands after a newer one began changes nothing: the newer one read the
    /// engine later.
    @ObservationIgnored private var keptConversationReads = 0

    /// Read the engine's `hasKeptConversation` into the copy the chips read.
    private func readKeptConversation() async {
        keptConversationReads &+= 1
        let read = keptConversationReads
        let kept = await engine.hasKeptConversation
        guard read == keptConversationReads else { return }
        hasKeptConversation = kept
    }

    /// The reason nothing can serve, or nil while something can.
    public var unavailability: AskUnavailability? { status.unavailability }

    /// Which tier the caption names: the one answering the turn in flight, and
    /// otherwise the one that would answer next.
    ///
    /// **Who is answering, or who would.** The last turn's tier is right only
    /// while that turn is in flight, and stale the moment it lands: a thread
    /// whose last answer came from Private Cloud Compute would go on saying so
    /// after the quota was spent, and tell the reader the wrong thing about
    /// the question they are about to ask, the only question the caption is
    /// for.
    ///
    /// The inner fallback is what stops it blinking. A turn is appended before
    /// the engine's `.tier` event arrives (that event waits on
    /// `tierStates()`), so for those frames the turn's own tier is nil, and
    /// reading it alone would empty the subtitle on every send. The mirror
    /// already knows who the turn is about to run on.
    ///
    /// **Only a turn still running is in flight.** While a question waits for
    /// the saved thread to be read or the chat to change, the store is
    /// thinking, but the newest turn on screen belongs to another chat, and
    /// its tier says nothing about the question waiting.
    public var captionTier: AskTier? {
        guard isThinking, !shape.ids.isEmpty, !shape.lastIsComplete else { return status.nextTier }
        return shape.lastTier ?? status.nextTier
    }

    /// Each turn beside the one before it, from **one** read of the thread.
    ///
    /// The date line is decided by comparing a turn with its predecessor, and
    /// the obvious way to write that in a `ForEach` (enumerate, then reach
    /// back into `turns[index - 1]` inside the row builder) reads the array
    /// *live*. `ForEach` holds the sequence it was given, but the builder
    /// closure runs later and against whatever `turns` is by then: New Chat
    /// empties it while rows are still mounted, the next body evaluation
    /// indexes an emptied array, and the app traps with
    /// `Fatal error: Index out of range`.
    ///
    /// Written that way, it traps on every New Chat, and a test that drives
    /// the store never sees it: the store is fine, and the trap is in a view
    /// builder holding a stale index. Pairing here makes each row a value that
    /// can't go out of date.
    var pairedTurns: [(turn: Turn, previous: Turn?)] {
        let all = turns
        return all.enumerated().map { index, turn in
            (turn, index > 0 ? all[index - 1] : nil)
        }
    }

    /// The starters the reader hasn't asked or passed over.
    public var availableStarters: [AskStarter] {
        starters.filter { !declinedStarters.contains($0.id) }
    }

    /// The follow-ups the last answer offered, while there is a kept
    /// conversation to answer them against, less any the reader passed over.
    ///
    /// **An answered last turn isn't enough: the chips also wait on
    /// `hasKeptConversation`.** With no conversation kept and no tail for a
    /// recap, a chip's "which of those…" would reach a model with nothing to
    /// resolve "those" against.
    public var followUps: [AskStarter] {
        guard let last = turns.last, last.isComplete, last.failure == nil else { return [] }
        guard hasKeptConversation else { return [] }
        // A follow-up the reader said not to suggest stays gone for the thread,
        // the way a declined starter does.
        return (last.answer?.followUps ?? [])
            .filter { !declinedFollowUps.contains($0) }
            .map { AskStarter(text: $0, bank: "followUp") }
    }

    /// Whether the last answer offers "Another pick": its stream has ended, it
    /// chose something to show, it wasn't cut short, and the domain says it
    /// can be rerolled (`AskDomain.isRerollable`). Never a count, a total or a
    /// yes or no, whatever a domain says: the number or the word is the
    /// answer, and there is no other pick to ask for.
    ///
    /// Not gated on a kept conversation, unlike the follow-ups: the reroll asks
    /// the whole question again, and a session built fresh (the thread's next,
    /// or one handed down to the other tier) carries the recap and the steer.
    /// An answer the domain gave without a model offers it too, and the
    /// domain's own answer decides what comes back.
    public var offersAnotherPick: Bool {
        guard !isThinking, let last = turns.last, last.failure == nil,
              let answer = last.answer, !answer.isTruncated, !answer.tiles.isEmpty else { return false }
        if let kind = answer.questionKind, AskQuestionKind.showNoTiles.contains(kind) { return false }
        return domain.isRerollable(answer, question: last.question)
    }

    /// Whether answers carry the feedback thumbs: while
    /// `AskDiagnostics.isEnabled`, the switch that also shows the settings
    /// card's diagnostics row. That is a Debug build, a TestFlight build on
    /// iOS or visionOS, or a host that turns it on
    /// (`AskDiagnostics.enabledByApp`). A verdict keeps the session's feedback
    /// attachment only while it holds (`rate`).
    public var offersFeedback: Bool { diagnosticsOverride ?? AskDiagnostics.isEnabled }

    /// What `offersFeedback` reads in place of `AskDiagnostics.isEnabled`. For
    /// tests, which run a Debug build, where that is always true.
    @ObservationIgnored var diagnosticsOverride: Bool?

    /// Whether the newest turn's prose is still drawing in at `now`. The turns
    /// above it aren't checked.
    func isRevealing(at now: TimeInterval) -> Bool {
        turns.last?.isRevealing(at: now) ?? false
    }

    // MARK: - Plumbing

    private func turn(_ id: UUID) -> Turn? {
        turns.first { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    /// A turn reached a terminal state: which, and when, in one mutation
    /// (`lastTerminalTurnEndedAt` says why).
    private func noteTerminal(_ id: UUID, at time: TimeInterval) {
        lastTerminalTurn = id
        lastTerminalTurnEndedAt = time
    }
}

/// The stores alive in the process, by the thread each keeps. A second one
/// over the same thread is the misuse the store's "One per app" warns of,
/// which its `init` logs once for that thread. At file scope, since a generic
/// type can't have a stored static.
nonisolated private let storeCensus = Mutex(AskStoreCensus())

/// Who counts the stores alive over each thread, so the second over one is
/// reported, once for that thread.
///
/// A fault in the log and no more: two stores lose a chat only once both have
/// written, and a host that builds one per window still works, so trapping
/// would take down an app that a log line can point at its mistake.
nonisolated struct AskStoreCensus: Sendable {
    private(set) var alive: [String: Int] = [:]
    private var reported: Set<String> = []

    /// A store over the thread at `place` was built. True only the first
    /// time a second one is alive over it.
    mutating func arrive(_ place: String) -> Bool {
        let count = alive[place, default: 0] + 1
        alive[place] = count
        guard count > 1 else { return false }
        return reported.insert(place).inserted
    }

    /// A store over the thread at `place` was let go.
    mutating func leave(_ place: String) {
        let count = alive[place, default: 0] - 1
        alive[place] = count > 0 ? count : nil
    }
}

#endif
