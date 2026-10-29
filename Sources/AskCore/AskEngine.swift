#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Synchronization

/// Where a question came from.
///
/// Two origins change how the engine runs the turn: `.standalone` shares
/// nothing with the thread, and `.reroll` asks for a different pick. The
/// others tell the screen where the question came from, and the engine treats
/// them alike.
nonisolated public enum AskOrigin: String, Sendable, Equatable, Codable {
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
    /// A one-shot turn, such as a Siri intent's (`AskEngine.answerOnce(_:)`),
    /// that neither reads nor replaces the kept conversation.
    case standalone
    /// "Another pick": the last question again, over the thread as it stands,
    /// asking for something other than what the last answer chose, at a
    /// higher temperature, so the model has room to choose differently.
    case reroll
}

/// Drives one question through a tier's model with the domain's tools
/// registered, streaming the turn's events.
///
/// One turn at a time, serialized by cancel-and-await: a second question is
/// always the newer intent, and `LanguageModelSession` throws
/// `concurrentRequests` if two generations reach one session. A `.standalone`
/// turn shares nothing and is exempt.
///
/// **The engine never names `LanguageModelSession`.** Everything goes through
/// `AskModelSeam` and `AskSession`, which is what lets the whole turn loop be
/// tested against scripted snapshots with no model in the process.
public actor AskEngine<Domain: AskDomain> {
    /// The domain's row type: what its tools record, and what an answer's
    /// tiles resolve to.
    public typealias Row = Domain.Row
    /// What a turn's stream emits.
    public typealias Event = AskTurnEvent<Row>

    /// What the engine answers for: given once, here, and read by whatever
    /// else needs the same value, such as the store
    /// (`AskConversationStore.init(engine:)`), so a second copy that could
    /// differ from it is never written.
    public nonisolated let domain: Domain
    /// The domain's grounding policy, read once as the engine is built: it is
    /// the domain's for its life, never a turn's (`AskDomain.grounding`).
    private let grounding: AskGroundingPolicy
    /// The reply the domain's turns ask the model for, read once as the
    /// engine is built, for `grounding`'s reason: a session answers in the
    /// shape its first turn asked for (`AskDomain.replyShape`).
    private let replyShape: AskReplyShape
    private let seam: any AskModelSeam
    private let log: any AskLogSink
    /// What a warm session's age is read against (`warmMaxAge`): the
    /// continuous clock, or a test's.
    private let clock: @Sendable () -> ContinuousClock.Instant

    private var conversation: AskConversation<Row>?
    /// What the thread has said, while no kept conversation carries it: a
    /// thread read back from disk, or one whose session was dropped (a turn
    /// stopped, failed on a fresh session, or handed down to another tier).
    ///
    /// A thread with no session starts a fresh one at its next question, and
    /// this is what that session's recap is made from: "is it still on loan?"
    /// the next morning, or "which of those is on vinyl?" after a Stop, has to
    /// know what *it* and *those* were. Consumed by the next conversation
    /// built, which carries it in its own tail from then on. New Chat drops it.
    private var restoredTail: [AskThreadTail] = []
    /// Which chat the thread's state belongs to. `reset()` moves it on, and a
    /// turn begun in an earlier chat writes nothing back: not its session and
    /// not its recap, which the next chat's first question would otherwise
    /// carry on from.
    private var chat = 0
    private var warm: (
        startedAt: ContinuousClock.Instant,
        tier: AskTier,
        box: AskSessionBox,
        collector: AskCollector<Row>,
        relay: AskActivityRelay
    )?
    private var inFlight: (id: Int, task: Task<Void, any Error>)?
    /// The newest question to wait for, or hold, the thread's one turn: each
    /// question but a standalone one takes the next number before it waits
    /// out the turn in flight, and `reset()` takes one too. A waiter that
    /// wakes to a newer number has been overtaken, by a newer question or by
    /// the end of its chat, and stands down rather than cancel the turn the
    /// newer question installed.
    private var newestQuestion = 0
    /// A warm is being made — see `prewarm()`.
    private var isWarming = false
    /// Whether a screen wants a warm: `prewarm()` says so and
    /// `forgetWarmIfEmpty()` takes it back. A warm that lands once nobody
    /// wants it is dropped.
    private var warmIsWanted = false
    private var turnCount = 0
    /// The last generation's stats, as the log sink heard them. `AskEval` reads
    /// its tool count here: counting the activity a domain's tools report
    /// would miss every tool that reports something other than `.searching`.
    /// Cleared when a question begins, so one that never reached a model reads
    /// nil rather than the question before it.
    private(set) var lastTurnStats: AskTurnStats?

    /// A warm session is worth taking for this long. Past it the KV cache has
    /// likely been evicted anyway and a fresh build is honest.
    static var warmMaxAge: Duration { .seconds(300) }

    /// An engine for one thread, answering for `domain` on the tiers `seam`
    /// serves.
    ///
    /// One engine per thread. An evaluation takes an engine of its own
    /// (`AskEval`), because each of its scenarios resets the engine, which on
    /// the thread's engine is New Chat.
    ///
    /// With no `log`, the engine logs through `AskOSLogSink` under the
    /// domain's `AskBrand.logSubsystem`. It logs seven domain mistakes once,
    /// here: question kinds outside `AskQuestionKind.all`, "Another pick"
    /// kinds no answer can have, by its kinds or by its reply shape, a
    /// first-screen policy that answers without a model from a domain that
    /// doesn't implement `deterministicAnswer(for:)`, one that needs owned
    /// rows from a brand with no `nothingToAskCopy`, a domain with no search
    /// arguments under the grounded retry, and one that doesn't retrieve
    /// under a first-screen policy that needs owned rows. Each is a fault
    /// under that subsystem, whatever `log` is, and a `routing` line to a
    /// `log` passed here as well.
    public init(domain: Domain, seam: any AskModelSeam, log: (any AskLogSink)? = nil) {
        self.init(domain: domain, seam: seam, log: log) { ContinuousClock().now }
    }

    /// The engine with the clock a warm session is aged by, so a test can
    /// move it past `warmMaxAge` rather than wait five minutes.
    init(
        domain: Domain,
        seam: any AskModelSeam,
        log: (any AskLogSink)?,
        clock: @escaping @Sendable () -> ContinuousClock.Instant
    ) {
        self.domain = domain
        self.grounding = domain.grounding
        self.replyShape = domain.replyShape
        self.seam = seam
        let osLog = AskOSLogSink(subsystem: domain.brand.logSubsystem)
        self.log = log ?? osLog
        self.clock = clock
        // A mistake in the domain is a bug in the host's code, logged once,
        // here: a fault under the brand's subsystem, which the log store
        // keeps and Console and Xcode set apart, and a routing line to a
        // sink of the host's, which bridges the engine's lines into its own
        // log. With no sink of the host's, the fault is the one line.
        func mistake(_ line: String) {
            osLog.domainMistake(line)
            log?.routing(line)
        }
        // Once, at construction. A kind the shared vocabulary doesn't contain
        // is a typo, and its cost is silent: `normalizedKind` maps the model's
        // correct answer to `other`, so the kind no longer decides whether a
        // count shows tiles (house rule 7), and nothing else says so.
        let strangers = AskQuestionKind.unrecognized(in: domain.questionKinds)
        if !strangers.isEmpty {
            mistake("questionKinds not in the schema vocabulary: \(strangers.joined(separator: ", "))")
        }
        // The same silence for "Another pick". An answer's kind is one of
        // `questionKinds`, a superlative read as a pick where only `pick` is
        // listed, or `other` for any the model gave outside them: a rerollable
        // kind that isn't among them, or a typo of one, is never offered it.
        let unreachable = domain.rerollableKinds.subtracting(domain.questionKinds + [AskQuestionKind.other])
        if !unreachable.isEmpty {
            mistake(
                "rerollableKinds not in questionKinds, never offered Another pick: \(unreachable.sorted().joined(separator: ", "))"
            )
        }
        // And all of them under the prose shape, whose answers the model
        // writes with no kind of its own and no tiles, and "Another pick" is
        // offered only for tiles.
        if replyShape == .prose, !domain.rerollableKinds.isEmpty {
            mistake(
                "rerollableKinds under replyShape .prose — no answer the model writes has a question kind or tiles, so none offers Another pick"
            )
        }
        // And the mistake a domain can make by writing one `true`.
        // `answersWithoutModel` promises the app answers its own starters with
        // no model; `deterministicAnswer` is what actually answers them. A
        // domain claiming the first without implementing the second gets a
        // first screen whose chips fail.
        if domain.firstScreenPolicy.answersWithoutModel, !domain.implementsDeterministicAnswer {
            mistake("firstScreenPolicy.answersWithoutModel is set and deterministicAnswer(for:) is not implemented — the first screen's chips will fail")
        }
        // The same for the nothing-to-ask screen, which needs the host's
        // words: with none, AskUI shows the ready first screen for an empty
        // overview, and a domain that asked for the other one never sees it.
        if domain.firstScreenPolicy.needsOwnedRows, domain.brand.nothingToAskCopy == nil {
            mistake("firstScreenPolicy.needsOwnedRows is set and brand.nothingToAskCopy is nil — an empty overview shows the ready first screen")
        }
        // And a domain with no search under the grounded retry, which a
        // domain that retrieves has: it plans `SearchArguments` and runs
        // `search`. With `AskNoSearchArguments` there is nothing to plan, so no
        // planner is asked, and the default search throws, so a first answer
        // that calls no tool fails all the same, as under `.toolCall`. Under
        // the other policies there is no retry to reach it.
        if grounding == .retrieval, Domain.SearchArguments.self == AskNoSearchArguments.self {
            mistake("SearchArguments is AskNoSearchArguments under the grounded retry — a first answer that calls no tool has no search to plan, and the default search(_:context:) fails it as ungrounded")
        }
        // And a domain that doesn't retrieve under a first screen that reads
        // an empty overview as nothing to ask about: the default policy for
        // it is `.openSubject`, so this one was set by hand, often left
        // behind from `.retrieval`. With the default overview, `.empty`, every
        // reader would get the nothing-to-ask screen.
        if grounding != .retrieval, domain.firstScreenPolicy.needsOwnedRows {
            mistake("firstScreenPolicy.needsOwnedRows is set and grounding is \(grounding.rawValue) — an empty overview shows the nothing-to-ask first screen to a domain that doesn't retrieve")
        }
    }

    // MARK: - Status

    /// The seam's mirror, straight through. The screen reads which tier is next,
    /// why nothing can serve and where the quota stands from here rather than
    /// keeping a copy — a copy can disagree with the seam about who is serving.
    public nonisolated var status: AskModelStatus { seam.status }

    /// Open Apple's limit-increase route, when the seam has one to offer.
    public func showLimitIncrease() async {
        await seam.showLimitIncrease()
    }

    /// Re-probe and republish the mirror the UI reads.
    public func refreshStatus() async {
        await seam.refreshStatus()
    }

    /// Whether a conversation is kept, so a follow-up chip has something to
    /// refer to. A restored tail counts: the next question starts a session
    /// with its recap.
    ///
    /// **This engine's own, never the mirror's.** The seam, and its mirror,
    /// can be shared, and an evaluation's engine resets before every
    /// scenario: whatever another engine on the seam does leaves this one's
    /// answer alone.
    public var hasKeptConversation: Bool {
        conversation != nil || !restoredTail.isEmpty
    }

    // MARK: - Prewarm

    /// Warm a session for the next question. Safe to call again, because a
    /// young warm already waiting, or one still being made, is left alone.
    ///
    /// **Not free, so AskUI calls it only once a question has begun**: as the
    /// draft goes from empty to not (`AskConversationStore.draft`), and as the
    /// screen appears or the app comes back with a question already
    /// half-typed. An appearance alone warms nothing. A warm on Private Cloud
    /// Compute builds a session there, which spends a request of the reader's
    /// daily quota.
    ///
    /// **Consumed once, and never into a kept conversation**: a kept session
    /// already has its cache, and warming beside it builds a second one that is
    /// thrown away. So this does nothing while a conversation is kept.
    ///
    /// **Held to the domain's `turnDeadline`**, counted from the call, though
    /// no reader waits on it: a read of the tiers, a build or the session's
    /// own `prewarm(promptPrefix:)` that never returned would leave a warm
    /// forever being made, and every later call would find it so and do
    /// nothing. A warm given up on isn't kept.
    public func prewarm() async {
        guard conversation == nil else { return }
        // Wanted from here, even when what serves it is a warm already being
        // made: a screen back before that warm lands still wants it.
        warmIsWanted = true
        guard !isWarming else { return }
        let now = clock()
        if let warm, now - warm.startedAt < Self.warmMaxAge { return }
        // Before the first suspension: a second call arriving while this one
        // builds would otherwise build a second session, and on Private Cloud
        // Compute a second request.
        isWarming = true
        defer { isWarming = false }
        let deadline = ContinuousClock().now + domain.turnDeadline
        let seam = self.seam
        guard let states = try? await AskDeadline.run(until: deadline, { await seam.tierStates() }) else {
            // Out of time, or a caller that let go, which needs no line.
            if !Task.isCancelled { log.routing("prewarm ran out of time reading which tier can serve") }
            return
        }
        guard let tier = askServableTiers(from: states).first else { return }
        let collector = AskCollector<Row>()
        let relay = AskActivityRelay()
        let made: AskSessionBox?
        do {
            made = try await makeSession(
                tier: tier, collector: collector, relay: relay, isConversation: true, deadline: deadline
            )
        } catch {
            // A prewarm that can't build a session is not the reader's
            // problem: the first real turn builds its own and reports
            // properly. It is still worth a line: a prewarm failing every time
            // means every turn pays the cold cost, silently.
            log.routing("prewarm could not make a \(tier.rawValue) session: \(AskTriage.tag(for: error))")
            return
        }
        guard let box = made else { return }
        // The session's own warm, inside the same deadline: a host session
        // whose `prewarm` never returns would leave this warm forever being
        // made. One given up on is no warm to hand the next question, which
        // builds its own.
        let session = box.session
        let prefix = domain.promptPrefix
        guard await Self.read(until: deadline, { await session.prewarm(promptPrefix: prefix) }) != nil else {
            if !Task.isCancelled { log.routing("prewarm ran out of time warming its \(tier.rawValue) session") }
            return
        }
        // **Asked again, now that it is built.** A question sent while this
        // was being made, such as a short one typed and sent quickly, found
        // no warm and built a session of its own, and the conversation that
        // question keeps is the one no warm may sit beside. Kept anyway, the
        // warm would outlive the screen too: `forgetWarmIfEmpty` leaves a warm
        // alone while a conversation is kept.
        //
        // And still wanted: the last screen gone while this was being made
        // found no warm to let go, and this one, kept, would outlive them all.
        guard warmIsWanted, conversation == nil, inFlight == nil else { return }
        warm = (now, tier, box, collector, relay)
    }

    /// Whether a warm session is waiting. Test-facing, like
    /// `AskGenerationGate.queueDepth`: a warm kept where it should not be is
    /// otherwise invisible.
    var hasWarm: Bool { warm != nil }

    /// Drop a warm session nobody took, when the screen goes away, and one
    /// still being made as it lands, unless `prewarm()` wants it again first.
    /// A warm is left alone while a conversation is kept.
    public func forgetWarmIfEmpty() {
        warmIsWanted = false
        guard conversation == nil else { return }
        warm = nil
    }

    private func takeWarm(
        for tier: AskTier
    ) -> (box: AskSessionBox, collector: AskCollector<Row>, relay: AskActivityRelay)? {
        guard let warm else { return nil }
        self.warm = nil
        guard warm.tier == tier, clock() - warm.startedAt < Self.warmMaxAge else { return nil }
        return (warm.box, warm.collector, warm.relay)
    }

    // MARK: - Lifecycle

    /// End the chat, for New Chat: the turn in flight is stopped, a question
    /// waiting for it stands down, and the kept conversation, the warm session
    /// and any recap are dropped. The stopped turn writes nothing back as it
    /// winds down, so the next question starts a new conversation, and no
    /// follow-up chip refers to the chat it ended.
    public func reset() async {
        inFlight?.task.cancel()
        chat &+= 1
        // A question waiting out the stopped turn was asked of the chat this
        // ends. It wakes to a newer number and stands down, rather than run as
        // the next chat's first question.
        newestQuestion &+= 1
        conversation = nil
        warm = nil
        restoredTail = []
    }

    /// Carry a thread read back from disk into the next session: its last
    /// three exchanges, newest last, which the first fresh session is told as
    /// a recap. Older ones are dropped.
    ///
    /// Ignored once a conversation exists: its own tail is newer than anything
    /// on disk. Otherwise a conversation reads as kept from here
    /// (`hasKeptConversation`), so a chat opened from history shows its
    /// follow-up chips before its next turn.
    public func resume(from tail: [AskThreadTail]) async {
        guard conversation == nil else { return }
        restoredTail = Array(tail.suffix(AskContinuation.recapDepth))
    }

    /// Cancel the turn in flight, if any. Its session is dropped and what the
    /// thread said is kept, so the next question starts a fresh session with a
    /// recap. A standalone turn is not the turn in flight: its caller stops it
    /// by cancelling the task that reads it.
    public func stop() {
        inFlight?.task.cancel()
    }

    /// Wait out the turn in flight, cancelling it first, for the question
    /// that took `ticket` (`newestQuestion`).
    ///
    /// A loop rather than one pass, so the invariant is *at most one turn in
    /// flight* and not merely *the turn I found is done*: clearing `inFlight`
    /// before awaiting would let a third question in beside the second.
    ///
    /// **Asked again after every wait.** Two questions can wait on one old
    /// turn, and when it ends the actor resumes them in an order of its own,
    /// so the newer can install its turn before the older wakes. The older,
    /// overtaken or let go by its reader, then stops here rather than cancel
    /// the turn it finds, which is the reader's newest.
    private func settleTurn(for ticket: Int) async {
        while let current = inFlight, ticket == newestQuestion, !Task.isCancelled {
            current.task.cancel()
            _ = await current.task.result
            if inFlight?.id == current.id { inFlight = nil }
        }
    }

    // MARK: - Asking

    /// Ask a question, streaming the turn's events.
    ///
    /// **How the stream ends.** After `.answer`, it finishes normally. A turn
    /// that fails finishes it by throwing an `AskError`. A turn stopped before
    /// its answer finishes it by throwing `CancellationError`, whether by
    /// `stop()`, by `reset()`, or by a newer question, which stops the turn in
    /// flight before it starts. So a caller that catches only `AskError`
    /// misses a stop. A reader that lets the stream go stops the turn too, and
    /// hears nothing more.
    ///
    /// **The question is asked as the reader saw it**: what a reader can't
    /// see, such as tag characters and bidi controls, is dropped, and what is
    /// left is trimmed and clamped to 500 characters. A question with nothing
    /// left, empty or only whitespace, throws `AskError.couldNotAnswer`
    /// before any tier is asked, with no event before it.
    ///
    /// A `.standalone` turn stands apart: it doesn't stop the turn in flight,
    /// and `stop()`, `reset()` and a newer question don't stop it. Only
    /// letting its stream go does.
    public nonisolated func ask(
        _ question: String,
        origin: AskOrigin = .typed
    ) -> AsyncThrowingStream<Event, any Error> {
        ask(question, origin: origin, images: [])
    }

    /// Ask a question the reader attached photos to. The stream ends as
    /// `ask(_:origin:)`'s does.
    ///
    /// **The photos go only to a tier that reads them** (`AskTier.readsPhotos`),
    /// on a fresh session, a continued one and a rolled-over one alike, with a
    /// line in the prompt that says so. A turn on the device, whether the first
    /// tier chosen or the one a hand-down lands on, runs on the words alone,
    /// and nothing in its prompt mentions a photo it can't see.
    ///
    /// The grounded retry sends no second copy, since its re-ask runs on the
    /// session that already took the photo, and its planner, on a session of
    /// its own, is sent none.
    public nonisolated func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment]
    ) -> AsyncThrowingStream<Event, any Error> {
        ask(question, origin: origin, images: images, scope: nil)
    }

    /// Ask a question a host asked from one part of what the app holds, such
    /// as a shelf or a category (`AskConversationStore.prefill(_:scope:send:)`).
    /// The stream ends as `ask(_:origin:)`'s does.
    ///
    /// `scope` reaches the model only as the line `AskDomain.scopeLine(for:)`
    /// writes for it, in the prompts that requirement lists; a domain that
    /// writes none asks the question as it would unscoped.
    public nonisolated func ask(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?
    ) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.run(question, origin: origin, images: images, scope: scope, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ question: String,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation
    ) async {
        // Asked before the settle as well as after it. A stream its reader has
        // already let go wants no turn, and settling for it would cancel the
        // newer turn that replaced it, which can reach the actor first.
        guard !Task.isCancelled else {
            continuation.finish(throwing: CancellationError())
            return
        }
        if origin != .standalone {
            newestQuestion &+= 1
            let ticket = newestQuestion
            await settleTurn(for: ticket)
            // Overtaken while it waited. The newer question is the newer
            // intent, and it holds the turn already or is about to; or the
            // chat it was asked of has ended.
            guard ticket == newestQuestion else {
                continuation.finish(throwing: CancellationError())
                return
            }
        }
        guard !Task.isCancelled else {
            continuation.finish(throwing: CancellationError())
            return
        }
        turnCount += 1
        let id = turnCount
        // Read in the same synchronous stretch that installs the turn, so a
        // `reset()` can only land after it, and moves the chat on from under it.
        let chat = self.chat
        let work = Task {
            try await self.turn(
                question, origin: origin, images: images, scope: scope, chat: chat, continuation: continuation
            )
        }
        if origin != .standalone { inFlight = (id, work) }
        // The turn runs in a task of its own, so `stop()` and a newer question
        // can cancel it, and that task is no child of this one: a reader
        // letting the stream go cancels only this task, so this passes it on.
        let outcome = await withTaskCancellationHandler {
            await work.result
        } onCancel: {
            work.cancel()
        }
        if inFlight?.id == id { inFlight = nil }
        // Finished here, once `inFlight` is clear, and not from inside the
        // work: the finish resumes whoever reads the stream, and a reader that
        // acts on the end at once (a verdict on the answer it was just handed)
        // must not find the turn still in flight.
        switch outcome {
        case .success: continuation.finish()
        case .failure(let error): continuation.finish(throwing: error)
        }
    }

    /// One standalone answer, for a caller outside the thread such as a Siri
    /// intent. It shares nothing with the thread: it neither inherits the kept
    /// conversation nor takes it away, and a turn the chat has in flight keeps
    /// generating beside it.
    ///
    /// Throws the turn's `AskError` when it fails. Cancelling the caller's task
    /// stops the turn, and this throws `CancellationError`; a stop from
    /// anywhere else, such as the framework's, is no cancellation of the
    /// caller's, and throws `AskError.couldNotAnswer`. So does a question
    /// with nothing in it once `ask(_:origin:)` has dropped what the reader
    /// can't see and trimmed it, before any tier is asked.
    public func answerOnce(_ question: String) async throws -> AskAnswer<Row> {
        var answer: AskAnswer<Row>?
        let stream = ask(question, origin: .standalone)
        do {
            for try await event in stream {
                if case .answer(let value) = event { answer = value }
            }
        } catch is CancellationError where !Task.isCancelled {
            throw AskError.couldNotAnswer
        }
        // A cancelled caller ends the stream rather than failing it, and is
        // told it was cancelled, not that the question couldn't be answered.
        try Task.checkCancellation()
        guard let answer else { throw AskError.couldNotAnswer }
        return answer
    }

    // MARK: - The turn

    private func turn(
        _ rawQuestion: String,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?,
        chat: Int,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation
    ) async throws {
        // A turn stopped before it began asks nothing.
        try Task.checkCancellation()
        lastTurnStats = nil
        let started = ContinuousClock().now
        // One deadline for the whole turn. The domain's answer without a model,
        // its overview and prompt lines, the read of the tiers, the sessions'
        // builds, the generations, the search the app runs for a model that
        // would not, the domain's refine pass and a hand-down all share it.
        //
        // **Every hook of the host's that awaits is raced against it**, as the
        // refine pass is, and abandoned when it passes. One that never
        // returns, and can't notice it was stopped, would otherwise hold the
        // turn in flight past any deadline and any Stop, and every question
        // after it waits for that turn to end.
        let deadline = started + domain.turnDeadline
        // Only what the reader could see, then clamped: a tag character draws
        // nothing and spells ASCII to a model that reads it, and a bidi
        // control draws the question in another order than it is sent, so
        // neither is the reader's question. Dropped first, so the clamp
        // counts what is left. Everything after this, the prompts, the
        // planner, the tail a recap is made from, takes this question.
        let question = AskPrompt.clampQuestion(AskPrompt.droppingInvisibles(rawQuestion))
        guard !question.isEmpty else { throw AskError.couldNotAnswer }

        // 1. An answer the app can give without a model. Small talk, and the
        //    starters on a device where nothing can serve.
        let domain = self.domain
        guard let deterministic = try await AskDeadline.run(until: deadline, {
            await domain.deterministicAnswer(for: question)
        }) else {
            log.routing("ran out of time waiting for the domain's answer without a model")
            throw AskError.couldNotAnswer
        }
        if let deterministic {
            // Held to what every answer is: no more tiles than a bank lays
            // out, one chip per text, since a chip's text is its id in the
            // chip row, and no more payload, proposal or rows than a tool
            // could have recorded. Then explained like any answer that shows
            // tiles: the domain's basis, unless the answer arrived with its
            // own.
            let held = heldToTheCollectorsLimits(deterministic, from: "the domain's answer without a model")
                .cappingTiles()
                .replacing(followUps: AskAnswer<Row>.dedupedFollowUps(deterministic.followUps))
            continuation.yield(.answer(held.replacing(basis: held.basis ?? basis(for: held))))
            return
        }

        // 2. Who can serve, from ONE read, inside the turn's deadline: the read
        //    can wait on Private Cloud Compute's availability, and on a
        //    stalled network that wait has no end of its own.
        let seam = self.seam
        guard let states = try await AskDeadline.run(until: deadline, { await seam.tierStates() }) else {
            log.routing("ran out of time reading which tier can serve")
            throw AskError.couldNotAnswer
        }
        let servable = askServableTiers(from: states)
        // With nothing servable, a Private Cloud Compute held off only by a
        // cooldown or a spent quota takes the turn (`askHeldTier(from:)`),
        // the tier the mirror names as the next one: an outage with nowhere
        // to hand down was the turn's error, which Try Again retries (house
        // rule 1), and the turn fails, if it fails, retryably and not with
        // the on-device tier's reason, which offers no Try Again.
        let held = servable.isEmpty ? askHeldTier(from: states) : nil
        guard let tier = servable.first ?? held?.tier else {
            refreshStatusAside()
            let why = askUnavailability(from: states)
            log.routing("no tier can serve — \(why.rawValue)")
            throw AskError.modelUnavailable(why)
        }
        continuation.yield(.tier(tier))
        if let held, held.quotaReached {
            // A spent quota is asked nothing: until its reset every request
            // could only fail as the quota, and each would spend one. A
            // cooldown on top changes nothing, since lifting it leaves the
            // quota spent. The turn is still the tier's, as the caption says,
            // and fails as its quota, with the reset the mirror's banner shows
            // beside it. The mirror is refreshed for that banner.
            log.routing("\(tier.rawValue) is out of quota, with no tier below that can serve — asking nothing until its reset")
            refreshStatusAside()
            throw AskError.quotaReached(resetDate: await status.resetDate)
        }
        if held != nil {
            // A cooldown is asked through: the network that went out may be
            // back, and a tier that is back answers. One still out fails the
            // turn as unreachable, and cools the tier again.
            log.routing("\(tier.rawValue) chosen though it is held, with no tier below that can serve")
        } else {
            log.routing("\(tier.rawValue) chosen (servable: \(servable.map(\.rawValue).joined(separator: ", ")))")
        }

        let fallback = servable.dropFirst().first
        // What the thread has said, as this turn found it. Taken here because
        // either path the first attempt takes gives it up before a hand-down
        // can ask: a kept session is dropped with it, and a fresh one drops the
        // kept session before it streams.
        let threadTail = origin == .standalone ? [] : (conversation?.recapTail ?? restoredTail)
        // What the turn has on the reader's screen: the prose and the rows its
        // attempt has sent since the last `.restarted`.
        let drawn = AskDrawn<Row>()

        do {
            try await attempt(
                question, tier: tier, origin: origin, images: images, scope: scope,
                chat: chat, started: started, deadline: deadline, drawn: drawn, continuation: continuation
            )
        } catch let stop as CancellationError {
            logIfCancelledFromBelow(stop, on: tier)
            // A generation cut off mid-stream leaves a transcript the next turn
            // can't build on, so the session goes. What the thread said stays,
            // for the fresh session the next question starts, and so does what
            // the reader saw of this turn, which they keep as its answer. A
            // standalone turn's generation was on a session of its own, and a
            // turn from a chat that has ended leaves the next chat alone.
            if origin != .standalone, isCurrent(chat) {
                dropSession(adding: stoppedExchange(question, on: tier, drawn: drawn))
            }
            throw CancellationError()
        } catch let raw {
            // Everything that is not already an `AskError` is triaged here, not
            // thrown on: session construction reaches this catch raw, and an
            // untriaged error would skip the hand-down below and put an SDK
            // string on the screen. By the tier asked for, since there is no
            // session yet to say which tier it would have run on.
            //
            // What a session's own generations throw is triaged a layer down,
            // by the tier that session runs on (`AskSessionBox.tier`): the
            // stream's in `stream`, because a follow-up's overflow has to be a
            // typed `.contextTooLarge` before `attempt` can roll it over, and
            // the grounded retry's planner in `plannedPrompt`. A router's
            // on-device session answering for Private Cloud Compute fails as
            // the on-device model, and cools nothing. The domain's search
            // fails as an `AskError` of its own.
            let error = triaged(raw, on: tier)

            // An announced outage hands the turn down once. The caption the
            // reader is looking at names the fallback from its `.tier` event,
            // so the cooldown and the mirror's refresh go beside the turn,
            // not ahead of it: both can wait on the tier that just went out,
            // and on a stalled network that wait would hold the very answer
            // the hand-down is for.
            //
            // Anything the tier BELOW would fail at too (a refusal, an
            // overflow, an ungrounded answer) fails where it stands: another
            // model reaches the same verdict, and the reader would just be
            // told it slower.
            //
            // Only a tier that couldn't be reached is noted as a transport
            // failure, handed down or not. A spent quota is no network fault:
            // the tier's state says it is spent (`AskTierState.quotaReached`)
            // until its reset, and a cooldown on top would log a failure there
            // wasn't.
            let unreachable = tier == .privateCloud && error == .privateCloudUnreachable
            guard let fallback, askIsTierOutage(error) else {
                refreshStatusAside(notingTransportFailureOn: unreachable ? tier : nil)
                throw error
            }
            // House rule 5's one exception takes the prose back only for an
            // attempt with time to draw its own. With less than
            // `restartFloor` left the fallback would more likely draw nothing
            // than something, so the failure renders under what was drawn,
            // as it does with no tier to hand down to.
            if !drawn.prose.isEmpty, deadline - ContinuousClock().now < Self.restartFloor {
                log.routing("\(tier.rawValue) went out with too little time left to hand down — keeping what it drew")
                refreshStatusAside(notingTransportFailureOn: unreachable ? tier : nil)
                throw error
            }
            // A session is bound to its model, so the conversation cannot move
            // with the turn: it is dropped and the question is asked on the
            // fallback as the first of a new one. What the thread had said goes
            // along, the way a restored thread's does — a follow-up or an
            // "Another pick" handed down still knows what it follows.
            // A standalone turn never held the thread's session, so it has none
            // to give up.
            if origin != .standalone, isCurrent(chat) {
                restoredTail = threadTail
                conversation = nil
            }
            refreshStatusAside(notingTransportFailureOn: unreachable ? tier : nil)
            let outage = if case .quotaReached = error { "is out of quota" } else { "went out" }
            log.routing("\(tier.rawValue) \(outage) — handing down to \(fallback.rawValue)")
            drawn.restart()
            continuation.yield(.restarted(fallback))
            continuation.yield(.tier(fallback))
            do {
                try await attempt(
                    question, tier: fallback, origin: origin, images: images, scope: scope,
                    chat: chat, started: started, deadline: deadline, drawn: drawn, continuation: continuation
                )
            } catch let stop as CancellationError {
                logIfCancelledFromBelow(stop, on: fallback)
                if origin != .standalone, isCurrent(chat) {
                    dropSession(adding: stoppedExchange(question, on: fallback, drawn: drawn))
                }
                throw CancellationError()
            } catch let raw {
                // Triaged like the first tier's failures: the fallback builds a
                // session and plans the same way, and a raw error from either
                // would otherwise reach a caller such as `answerOnce` as the
                // SDK's own. Nothing is handed down twice.
                let error = triaged(raw, on: fallback)
                refreshStatusAside()
                throw error
            }
        }
        // The mirror refreshed beside the turn: the turn is over when its
        // answer lands.
        refreshStatusAside()
    }

    /// Note a transport failure and refresh the mirror beside the turn
    /// rather than inside it. Both can wait on Private Cloud Compute's
    /// probes, which are network calls, and a turn that waited on them would
    /// hold its stream open past its answer, or a hand-down's first token, for
    /// as long as a stalled network takes. One task, so the cooldown lands
    /// before the refresh that reads it.
    private func refreshStatusAside(notingTransportFailureOn failed: AskTier? = nil) {
        let seam = self.seam
        Task {
            if let failed { await seam.noteTransportFailure(on: failed) }
            await seam.refreshStatus()
        }
    }

    /// A stop that is neither the reader's, which cancels the turn's task,
    /// nor the deadline's, which gives up without throwing, came from below
    /// the engine: the SDK, or the seam. The reader sees it as a stop they
    /// didn't ask for, so the log says where it came from. The tag only.
    private func logIfCancelledFromBelow(_ stop: CancellationError, on tier: AskTier) {
        guard !Task.isCancelled else { return }
        log.routing("\(tier.rawValue) was cancelled from below: \(AskTriage.tag(for: stop))")
    }

    /// Whether a turn begun in `chat` may still write the thread's state.
    private func isCurrent(_ chat: Int) -> Bool {
        self.chat == chat
    }

    /// Drop the kept session and keep what the thread said: its tail moves to
    /// `restoredTail`, and the next session starts with a recap of it.
    ///
    /// `stopped` is a stopped turn's exchange, which joins the tail as its
    /// newest (`AskContinuation.entersTail(tier:prose:)`): remembered by the
    /// kept conversation when there is one, or added to `restoredTail` when
    /// a fresh session's attempt had already dropped it.
    private func dropSession(adding stopped: (tail: AskThreadTail, referent: [String])? = nil) {
        if var kept = conversation {
            if let stopped {
                kept.remember(stopped.tail)
                kept.lastReferent = stopped.referent
            }
            restoredTail = kept.recapTail
        } else if let stopped {
            restoredTail = AskContinuation.appending(stopped.tail, widenedWith: stopped.referent, to: restoredTail)
        }
        conversation = nil
    }

    /// The exchange a stopped turn leaves in the tail: its question and the
    /// prose it had drawn, which the reader keeps as its answer, with no
    /// tiles, and the domain's referent of that prose among the rows it had
    /// read, as AskUI's store keeps the stopped answer. Nil when it drew
    /// nothing.
    private func stoppedExchange(
        _ question: String, on tier: AskTier, drawn: AskDrawn<Row>
    ) -> (tail: AskThreadTail, referent: [String])? {
        let prose = drawn.prose
        guard AskContinuation.entersTail(tier: tier, prose: prose) else { return nil }
        let answer = AskAnswer<Row>(text: prose, matches: drawn.rows, isTruncated: true)
        return (AskThreadTail(question: question, answer: prose, rowTitles: []), domain.referent(from: answer))
    }

    /// What a session on `tier` is sent of the question's photos: a line in
    /// the prompt for each, and each with its label as the seam hands it to
    /// the model. All of them on a tier that reads photos, and none on one
    /// that doesn't (`AskTier.readsPhotos`).
    ///
    /// `tier` is the one the session runs on (`AskSessionBox.tier`), not the
    /// one the turn asked for: a router's on-device session answering a
    /// request for Private Cloud Compute reads no photo, and a prompt that
    /// mentioned one would have it answer as though it had seen it.
    private func photos(
        _ images: [AskImageAttachment], for tier: AskTier
    ) -> (lines: [String], sent: [AskImageAttachment]) {
        let photos = tier.readsPhotos ? images : []
        // Never the label in the log line: it is the app's words for the
        // picture, and they can be the reader's.
        if !images.isEmpty {
            log.routing(photos.isEmpty ? "photo held back — \(tier.rawValue) reads no photos" : "photo sent to \(tier.rawValue)")
        }
        // What the seam is sent beside each picture, which it hands the model
        // as the picture's label, gets what the prompt's line gives it, the
        // clamp and the redaction: the host's words, which can be the
        // reader's (house rule 3).
        let sent = photos.map {
            AskImageAttachment(
                label: AskPrompt.sanitizeForFence(AskPrompt.clamp($0.label, AskPrompt.shortClamp)), image: $0.image
            )
        }
        return (photos.map { AskPrompt.photoLine(label: $0.label) }, sent)
    }

    /// The least of the turn's deadline a hand-down or a rollover needs left
    /// before it takes back prose already drawn: ten seconds.
    ///
    /// **A judgement, not a measured time to first word**, which no tier has
    /// one steady enough to set it by: Private Cloud Compute was measured at
    /// 5 to 20 s to its first word, and an on-device answer at about 13 s
    /// whole, its first words coming after its tool call. Below ten seconds a
    /// fresh attempt is likelier to draw nothing than something, and a turn
    /// that draws nothing ends with no text at all, where the failure would
    /// have rendered under the prose.
    ///
    /// Public and read-only: it is house rule 5's constant, and a host
    /// setting its own `AskDomain.turnDeadline` can read what a restart needs
    /// left of it.
    public nonisolated static var restartFloor: Duration { .seconds(10) }

    /// A failed attempt's error as the reader may be shown it: an `AskError` as
    /// it is, and anything else triaged, with its tag logged. The tag, never
    /// the error: a Foundation Models error's description can quote the
    /// reader's data, and `AskTriage.tag` reads the case name by reflection,
    /// so no SDK prose is materialized.
    ///
    /// An `AskError` isn't logged again: `stream` logs the raw error it
    /// triages, and the engine logs its own where it throws them.
    private func triaged(_ raw: any Error, on tier: AskTier) -> AskError {
        if let error = raw as? AskError { return error }
        log.routing("\(tier.rawValue) failed: \(AskTriage.tag(for: raw))")
        return AskTriage.askError(from: raw, tier: tier)
    }

    /// One attempt on one tier: continue the kept conversation, or build a
    /// fresh session and stream it.
    private func attempt(
        _ question: String,
        tier: AskTier,
        origin: AskOrigin,
        images: [AskImageAttachment],
        scope: String?,
        chat: Int,
        started: ContinuousClock.Instant,
        deadline: ContinuousClock.Instant,
        drawn: AskDrawn<Row>,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation
    ) async throws {
        let scopeLine = scope.flatMap { domain.scopeLine(for: $0) }

        // A standalone turn always builds its own session.
        if origin != .standalone,
           var kept = conversation,
           AskContinuation.shouldContinue(
               keptTier: kept.tier,
               servable: [tier],
               turns: kept.turns,
               maxTurns: domain.maxTurns(for: tier),
               needsFreshSession: kept.needsFreshSession
           ),
           !(await shouldRollOver(kept, deadline: deadline)) {
            // The caption names the model the kept session runs on, as the
            // turn that built it did, and its photos go by that model too.
            if kept.box.tier != tier { continuation.yield(.tier(kept.box.tier)) }
            let (photoLines, sentPhotos) = photos(images, for: kept.box.tier)
            var prompt = AskContinuation.followUpPrompt(
                question: question, referentTitles: kept.lastReferent
            )
            if origin == .reroll {
                prompt = AskContinuation.rerollSteer(excluding: kept.lastReferent) + prompt
            }
            // Ahead of the question, as it rides a fresh prompt: a shelf's
            // question asked into a kept conversation is still that shelf's.
            if let scopeLine { prompt = scopeLine + "\n" + prompt }
            prompt = photoLines.map { $0 + "\n" }.joined() + prompt
            do {
                let (answer, abandoned) = try await stream(
                    question: question, prompt: prompt, images: sentPhotos,
                    box: kept.box, collector: kept.collector, relay: kept.relay,
                    isFollowUp: true, appRetrieved: kept.appRetrieved,
                    temperature: Self.temperature(for: origin),
                    started: started, deadline: deadline, drawn: drawn, continuation: continuation
                )
                kept.turns += 1
                kept.lastReferent = domain.referent(from: answer)
                kept.remember(AskThreadTail(
                    question: question, answer: answer.text,
                    rowTitles: answer.tiles.map(\.displayTitle)
                ))
                // A generation the deadline gave up on may still be writing on
                // this session, and a second request on it throws
                // `concurrentRequests`: the next question starts fresh.
                if abandoned { kept.needsFreshSession = true }
                if isCurrent(chat) { conversation = kept }
                return
            } catch is CancellationError {
                // `turn` drops the session and keeps the thread's tail.
                throw CancellationError()
            } catch let error as AskError where error == .contextTooLarge {
                // Reactive rollover: the transcript outgrew the window. Start
                // over below with this question as the first of a new
                // conversation, once, unasked. What the overflowing generation
                // drew is thrown away with it, so the stream says so, as the
                // grounded retry does: unsaid, that prose would stay on screen
                // until the fresh session's first words replaced it, and be
                // what a Stop before them kept.
                // With too little time left to draw a new answer, the
                // overflow is the turn's error and renders under the prose,
                // as for a hand-down (`restartFloor`).
                if !drawn.prose.isEmpty, deadline - ContinuousClock().now < Self.restartFloor {
                    log.routing("conversation outgrew \(tier.rawValue)'s window with too little time left to roll over — keeping what it drew")
                    if isCurrent(chat) { conversation?.needsFreshSession = true }
                    throw error
                }
                log.routing("conversation outgrew \(tier.rawValue)'s window — rolling over")
                drawn.restart()
                continuation.yield(.restarted(tier))
            } catch {
                // A failed follow-up leaves the conversation standing, marked
                // so the next turn starts a fresh session with a recap of it.
                // A tier outage goes further: `turn` drops the conversation to
                // hand the turn down.
                if isCurrent(chat) { conversation?.needsFreshSession = true }
                throw error
            }
        }

        // A fresh session on this tier — the thread's first, one whose window
        // filled, or one whose last turn failed — carrying what the thread has
        // said so far. The tail survives the session it was built on, and a
        // thread read back from disk carries the tail it had before this
        // process began.
        let carried = origin == .standalone ? [] : (conversation?.recapTail ?? restoredTail)
        let recap = AskContinuation.recap(from: carried, tier: tier)
        let wasSummarized = recap != nil
        if wasSummarized { continuation.yield(.summarized) }
        // The session goes before the fresh one is built, and the tail it
        // carried waits in `restoredTail`: if the fresh one fails, Try Again
        // still starts from what the thread said.
        if origin != .standalone, isCurrent(chat) { dropSession() }

        let collector: AskCollector<Row>
        let relay: AskActivityRelay
        let box: AskSessionBox
        if origin != .standalone, isCurrent(chat), let warmed = takeWarm(for: tier) {
            // The warm session's tools hold the warm session's relay. Minting a
            // new one here would leave every tool reporting into an object
            // nobody listens to.
            (box, collector, relay) = (warmed.box, warmed.collector, warmed.relay)
        } else {
            let fresh = AskCollector<Row>()
            let freshRelay = AskActivityRelay()
            guard let made = try await makeSession(
                tier: tier, collector: fresh, relay: freshRelay, isConversation: origin != .standalone,
                deadline: deadline
            ) else {
                // The seam reported this tier servable and then handed back no
                // session. That is a bug in the seam, not a condition of the
                // reader's — and it is indistinguishable from an ordinary
                // outage by the time it reaches the screen.
                log.routing("\(tier.rawValue) reported servable and made no session")
                throw AskError.modelUnavailable(.unknown)
            }
            (box, collector, relay) = (made, fresh, freshRelay)
        }
        // **The box's tier is the one the turn runs on.** A host's seam may
        // answer a request for one tier with a session on another, and the
        // generation gate, the reasoning level and the caption follow the
        // model that generates, not the one asked for (`makeSession` logs
        // the swap).
        let served = box.tier
        if served != tier { continuation.yield(.tier(served)) }
        let (photoLines, sentPhotos) = photos(images, for: served)

        // **Read here, not at the top of `attempt`.** A follow-up's prompt is
        // its question and its referent and never reads the overview, so it
        // shouldn't wait on one before its first token: a domain's overview can
        // be a count of every category in its store. A follow-up that rolls
        // over reaches this line and reads it then. Inside the turn's
        // deadline, as every hook of the host's that awaits is.
        let domain = self.domain
        guard let overview = try await AskDeadline.run(until: deadline, { await domain.overview() }) else {
            log.routing("ran out of time reading the domain's overview")
            throw AskError.couldNotAnswer
        }
        // Once for the whole attempt: the grounded retry plans with these and
        // re-asks with them. The scope's line goes with them, so the planner
        // choosing the search is told the shelf too: it is the choice the
        // scope is there to steer.
        guard var domainLines = try await AskDeadline.run(until: deadline, {
            await domain.promptLines(question: question, overview: overview)
        }) else {
            log.routing("ran out of time reading the domain's prompt lines")
            throw AskError.couldNotAnswer
        }
        if let scopeLine { domainLines.append(scopeLine) }
        var lines = domainLines
        if let recap { lines.insert(recap, at: 0) }
        // "Another pick" on a session that could not be continued: the steer
        // rides the fresh prompt instead, naming what the last answer chose —
        // and still asking for another when nothing it chose was carried.
        if origin == .reroll {
            lines.append(AskContinuation.rerollSteer(excluding: carried.last?.rowTitles ?? []))
        }
        lines.append(contentsOf: photoLines)
        let prompt = AskPrompt.promptText(prefix: domain.promptPrefix, lines: lines, question: question)

        var appRetrieved = false
        var answer: AskAnswer<Row>
        var abandoned: Bool
        do {
            (answer, abandoned) = try await stream(
                question: question, prompt: prompt, images: sentPhotos,
                box: box, collector: collector, relay: relay,
                isFollowUp: false, appRetrieved: false,
                temperature: Self.temperature(for: origin),
                started: started, deadline: deadline, drawn: drawn, continuation: continuation
            )
        } catch let error as AskError where error == .ungrounded && grounding == .retrieval {
            // The grounded retry: the model would not search, so the app
            // searches for it and re-asks with the rows fenced as data.
            //
            // A domain that retrieves alone has it. Under `.toolCall` the
            // ungrounded answer fails the turn as it stands, with no planner
            // and no second generation; under `.notRequired` the stream never
            // throws it.
            //
            // Two generations, and the first cannot be skipped while there is
            // something to plan: a tool is an offer, a response schema is the
            // shape of the reply, so the plan step asks for the domain's
            // search arguments as structured output and the model has no move
            // that returns nothing. A domain with no arguments has nothing to
            // plan, and `plannedPrompt` asks no planner.
            log.routing("\(served.rawValue) answered without retrieving — searching for it")
            drawn.restart()
            continuation.yield(.restarted(served))
            appRetrieved = true
            let retryPrompt = try await plannedPrompt(
                question: question, domainLines: domainLines, tier: served,
                isConversation: origin != .standalone,
                box: box, collector: collector, relay: relay,
                deadline: deadline, continuation: continuation
            )
            // No photo this time. This generation runs on the session whose
            // transcript took the photo with the first, so it is not sent
            // twice; whether the model reads it back from there is measured on
            // a device, not here.
            (answer, abandoned) = try await stream(
                question: question, prompt: retryPrompt, images: [],
                box: box, collector: collector, relay: relay,
                isFollowUp: false, appRetrieved: true,
                temperature: Self.temperature(for: origin), rowsAlreadyRecorded: true,
                started: started, deadline: deadline, drawn: drawn, continuation: continuation, retried: true
            )
        }

        if origin != .standalone, isCurrent(chat) {
            // Kept for its tail even when the deadline gave up on a generation
            // on it: the next question starts a fresh session with the recap.
            // Kept under the tier asked for, which is what the next turn asks
            // for and continues by; the box says what the session runs on.
            var fresh = AskConversation(
                tier: tier, box: box, collector: collector, relay: relay, turns: 1, tail: carried,
                appRetrieved: appRetrieved, needsFreshSession: abandoned,
                lastReferent: domain.referent(from: answer)
            )
            fresh.remember(AskThreadTail(
                question: question, answer: answer.text,
                rowTitles: answer.tiles.map(\.displayTitle)
            ))
            conversation = fresh
            // The restored tail lives on in this conversation's own now.
            restoredTail = []
        }
    }

    /// The prompt for the second half of a grounded retry: the planner picks
    /// the search arguments, or none is asked when the domain's are
    /// `AskNoSearchArguments`, the app runs the search through the domain's
    /// own code path, and the rows go into the prompt as data. Inside what is
    /// left of the turn's deadline, with the wait row hearing the search the
    /// way it hears a tool the model calls.
    ///
    /// `domainLines` are the attempt's own `promptLines`, and its scope's line
    /// when it has one, before the recap, the steer and the photo lines were
    /// added to its first prompt: the planner is a session of its own that
    /// wants none of those, and the re-ask runs on the session whose
    /// transcript already holds them.
    ///
    /// `isConversation` is the flag the turn's session was built with, so the
    /// search keeps the rules its tools keep: a standalone answer has no card
    /// to show a proposal on.
    private func plannedPrompt(
        question: String,
        domainLines: [String],
        tier: AskTier,
        isConversation: Bool,
        box: AskSessionBox,
        collector: AskCollector<Row>,
        relay: AskActivityRelay,
        deadline: ContinuousClock.Instant,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation
    ) async throws -> String {
        let context = AskToolContext(
            collector: collector, relay: relay,
            rowLimit: domain.rowLimit(for: tier), tier: tier, isConversation: isConversation
        )
        let planPrompt = AskPrompt.promptText(prefix: "", lines: domainLines, question: question)
        let session = box.session
        let planInstructions = domain.searchPlanInstructions
        let seam = self.seam
        let domain = self.domain
        let log = self.log

        // The app's search reports what it is doing the way a tool the model
        // called does, through the collector and the relay, and the wait row
        // hears it the same way. With neither listening, the row would say
        // nothing true for as long as the search took.
        collector.setObserver { event in
            switch event {
            case .tool(let activity): continuation.yield(.activity(activity))
            case .toolsIdle: continuation.yield(.activityEnded)
            }
        }
        defer { collector.setObserver(nil) }

        // Inside the turn's deadline: a stalled planner or search would
        // otherwise hold the turn until the reader tapped Stop.
        let rows: String?
        do {
            defer { await relay.end() }
            await relay.begin { continuation.yield(.activity($0)) }
            rows = try await AskDeadline.run(until: deadline) {
                let arguments: Domain.SearchArguments
                if let none = AskNoSearchArguments() as? Domain.SearchArguments {
                    // **No planner for a domain with no arguments to plan.**
                    // Its schema has nothing to choose, and asking would
                    // spend a generation, a request of the reader's Private
                    // Cloud Compute quota or an on-device turn, choosing
                    // nothing. The domain's search is run all the same: the
                    // default one fails the turn as ungrounded, and one the
                    // domain wrote, which needs no arguments, searches.
                    arguments = none
                } else {
                    // Through the generation gate like any other generation.
                    // It is a second on-device generation inside one turn,
                    // and the generation gate is the only thing keeping it
                    // from landing beside a host's own summary or classifier
                    // on the same runtime.
                    do {
                        arguments = try await seam.withGeneration(onDevice: tier != .privateCloud) {
                            try await session.plan(
                                Domain.SearchArguments.self,
                                instructions: planInstructions,
                                prompt: planPrompt
                            )
                        }
                    } catch let error as AskError {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Triaged here, by the tier the session runs on,
                        // which is what `tier` is: on a router's on-device
                        // session answering for Private Cloud Compute, the
                        // planner's rate limit is the on-device model's, and
                        // read as Private Cloud Compute's it would cool that
                        // tier and hand the turn down to the model that just
                        // failed.
                        log.routing("the grounded retry's planner failed on \(tier.rawValue): \(AskTriage.tag(for: error))")
                        throw AskTriage.askError(from: error, tier: tier)
                    }
                }
                // The rows this records ARE this turn's, and they are recorded
                // before the prompt that carries them exists — so `stream` is
                // told to skip its own `beginTurn`.
                await collector.beginTurn()
                // **The host's failure, not a tier's.** Its search reaches its
                // own store or backend, and a `URLError` from there reaching
                // triage raw reads as Private Cloud Compute unreachable: the
                // tier would be cooled for a minute and the turn handed down
                // for an outage of the host's. So it fails the turn here, an
                // `AskError` already, which nothing hands down. An `AskError`
                // the domain chose, and a stop, go on as they are.
                do {
                    return try await domain.search(arguments, context: context)
                } catch let chosen as AskError {
                    throw chosen
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let tag = AskTriage.tag(for: error)
                    log.routing("the domain's search failed on \(tier.rawValue): \(tag)")
                    throw AskError.model(tag: tag)
                }
            }
        }
        // The first answer read nothing, and under `.retrieval`, the one
        // policy with a retry, it is never shown, so a search that runs out
        // of time leaves nothing to keep.
        guard let rows else {
            log.routing("\(tier.rawValue) ran out of time searching for the model")
            throw AskError.couldNotAnswer
        }
        var lines = domainLines
        lines.append(
            "These are the things the app found for this question — answer only from them, "
            + "and do not search again: <tool_result>"
            // Both, and in this order: `sanitizeForFence` redacts the tags
            // AskKit knows, and `neuteringTags` neuters any other. Here the
            // engine, not a tool, puts rows into a prompt, so it does what
            // house rule 3 asks of a tool's output rather than trust the
            // domain's search to have done it. Not `clamp`: that collapses
            // newlines and truncates, flattening the layout the domain built
            // for the model to read.
            + AskPrompt.neuteringTags(AskPrompt.sanitizeForFence(rows))
            + "</tool_result>"
        )
        return AskPrompt.promptText(prefix: domain.promptPrefix, lines: lines, question: question)
    }

    /// One generation's stats, to the log and to `lastTurnStats`.
    private func logTurn(_ stats: AskTurnStats) {
        lastTurnStats = stats
        log.turn(stats)
    }

    // MARK: - Streaming one generation

    private func stream(
        question: String,
        prompt: String,
        images: [AskImageAttachment],
        box: AskSessionBox,
        collector: AskCollector<Row>,
        relay: AskActivityRelay,
        isFollowUp: Bool,
        appRetrieved: Bool,
        temperature: Double,
        rowsAlreadyRecorded: Bool = false,
        started: ContinuousClock.Instant,
        deadline: ContinuousClock.Instant,
        drawn: AskDrawn<Row>,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation,
        retried: Bool = false
    ) async throws -> (answer: AskAnswer<Row>, abandoned: Bool) {
        // The tier the box's session runs on, which is the one it generates
        // on, whatever tier was asked for.
        let tier = box.tier
        let session = box.session
        if !rowsAlreadyRecorded { await collector.beginTurn() }
        // Two counters, and the session's is the authority.
        //
        // The collector only knows what the domain's tools told it, so a tool
        // that runs its work outside `withToolCall` would silently make every
        // turn ungrounded — and the retry would fire on a turn that really did
        // retrieve. The transcript counts what the MODEL did, which is the fact
        // the grounding rule is about; the collector is the faster read that
        // usually agrees.
        //
        // The transcript's count is the session's to give, inside the turn's
        // deadline like everything else the turn waits on (`read(until:_:)`).
        // Without it this generation is judged by the collector alone, and
        // the race below, with no time left, ends it at once.
        let callsBefore = await collector.toolCallCount
        // Logged only for a read that had time to start: one entered with
        // none left, as after a search that took the whole deadline, is the
        // discard's to say.
        let hadTime = ContinuousClock().now < deadline
        let sessionCallsBefore = await Self.read(until: deadline) { await session.toolCallCount() }
        if sessionCallsBefore == nil, hadTime, !Task.isCancelled {
            log.routing("ran out of time reading \(tier.rawValue)'s tool calls")
        }

        var stats = AskTurnStats(tier: tier)
        stats.retried = retried

        // Everything this generation tells the reader goes out through here,
        // and nothing after its answer. The deadline abandons the snapshot
        // loop rather than waiting for it, and a loop caught between two hops
        // wakes after the truncated answer with a snapshot still to send; the
        // tools' observer is cleared only as this returns. The lock that lets
        // the answer out shuts the rest, as `refine` shuts its announcement.
        let outlet = AskAnswerOutlet(continuation, drawn: drawn)

        // The tools report straight into this turn's stream, by both routes. They
        // have to: a tool call runs BETWEEN stream snapshots, which is exactly
        // the seconds the wait most needs something true to say. A yield onto a
        // finished continuation is dropped, so a tool that outlives its turn
        // can't write into the next one's row.
        //
        // Two routes, because a tool has two kinds of news: its calls, reported
        // to the collector and heard by the observer below, and a narration the
        // collector knows nothing about, such as "12 of 212 read", reported to
        // the relay. One tool often uses both, for different events, in the
        // order `AskToolContext` states.
        let firstTool = Mutex<ContinuousClock.Instant?>(nil)
        // The stream measurements. In a `Mutex` because the loop below runs
        // inside a `@Sendable` closure handed to `AskDeadline.run`, and these
        // are read again after it returns.
        let measuring = Mutex(StreamMeasurements())
        collector.setObserver { event in
            switch event {
            case .tool(let activity):
                firstTool.withLock { if $0 == nil { $0 = ContinuousClock().now } }
                outlet.send(.activity(activity))
            case .toolsIdle:
                // Passed on, not dropped: the engine is the only observer (it
                // installs and clears it per turn), and without this the wait
                // row would hold the last tool's phrase while the model
                // composes.
                outlet.send(.activityEnded)
            }
        }
        defer { collector.setObserver(nil) }
        await relay.begin { activity in
            firstTool.withLock { if $0 == nil { $0 = ContinuousClock().now } }
            outlet.send(.activity(activity))
        }

        // The prose as far as it got, kept OUTSIDE the raced closure: on the
        // ceiling the deadline abandons that closure, and the words the reader
        // has been watching arrive are exactly what a truncated answer is made
        // of.
        let streamed = Mutex(AskReplySnapshot())
        // The transcript's count as the latch last read it, kept outside the
        // raced closure for `streamed`'s reason: on the ceiling the deadline
        // leaves no time to read it again, and a truncated answer only the
        // transcript grounds is still grounded.
        let transcribed = Mutex<Int?>(nil)
        let shape = replyShape
        let isPCC = tier == .privateCloud
        // Where the latch below starts: grounded already when the app
        // retrieved for this conversation, and under a policy that keeps
        // answers nothing grounded, since then no prose is discarded for want
        // of grounding and none need wait for it.
        let startsGrounded = appRetrieved || grounding == .notRequired

        let outcome: AskReplySnapshot?
        do {
            // However the race ends — an answer, the ceiling, a throw — the
            // relay closes with it: before the catch below triages anything,
            // and before a word of the result is read.
            defer { await relay.end() }
            // The race starts the generation before it can see a cancelled
            // caller, so a turn stopped by now sends nothing.
            try Task.checkCancellation()
            // What the turn has left: a retry or a hand-down races the time the
            // generations before it did not use.
            outcome = try await AskDeadline.run(until: deadline) { [weak self] in
                try await self?.seam.withGeneration(onDevice: !isPCC) {
                    var latest = AskReplySnapshot()
                    // Grounding is latched: once true it stays true for the
                    // turn, and the actor hops to ask are not worth paying per
                    // snapshot.
                    //
                    // **A follow-up starts unlatched, like a first turn.** The
                    // verdict below the loop asks whether the turn read
                    // something or names a row the thread has read, and the
                    // same test runs on each snapshot: a follow-up draws from
                    // its first tool call, or from the first snapshot that
                    // names a row the thread has read. Started grounded on the
                    // strength of the kept transcript, its prose would stream
                    // from the first token and the verdict could still throw
                    // `.ungrounded`, so the reader would watch an answer arrive
                    // and then a failure land under it. An answer that would be
                    // discarded never draws at all (house rule 2). Only an
                    // app-retrieved conversation is grounded before its first
                    // snapshot, because it is, and every turn under
                    // `.notRequired`, whose answers are never discarded for
                    // want of grounding: its prose draws from the first token.
                    var grounded = startsGrounded
                    // The thread's rows, read once: the set a follow-up's
                    // prose is checked against is the one an earlier turn
                    // read, and a tool reading more during this turn grounds
                    // it through `recorded` before this list could go stale.
                    let threadRows = await collector.rows
                    var shown = 0
                    let stream = session.stream(
                        prompt: prompt,
                        images: images,
                        temperature: temperature,
                        // Light reasoning on Private Cloud Compute, the level
                        // its grounding was measured at; none is asked of the
                        // on-device model.
                        reasoningLevel: isPCC ? .light : nil,
                        // A follow-up rides a session that has already seen the
                        // schema. Re-sending it is tokens spent on nothing.
                        includeSchemaInPrompt: !isFollowUp,
                        // The domain's, the same on every turn of the session,
                        // so the schema it saw is the one it answers in.
                        shape: shape
                    )
                    for try await snapshot in stream {
                        latest = snapshot
                        streamed.withLock { $0 = snapshot }
                        // Every snapshot; a *growth* is one that added prose.
                        // These feed the turn's `[stream]` log line: snapshots,
                        // growths, the first word and the prose's span.
                        let length = snapshot.answer.map { AskPrompt.partialText($0).count } ?? 0
                        let now = ContinuousClock().now
                        measuring.withLock {
                            $0.snapshots += 1
                            if length > $0.characters {
                                $0.characters = length
                                $0.growths += 1
                                if $0.firstWord == nil { $0.firstWord = now }
                                $0.lastWord = now
                            }
                        }
                        // Only when the set GREW: rows are cumulative within a
                        // turn, so yielding them per snapshot is the same list
                        // redrawn once per token.
                        let rows = await collector.turnRows
                        if rows.count > shown {
                            shown = rows.count
                            outlet.send(.rowsRead(rows))
                        }
                        if !grounded {
                            let recorded = await collector.toolCallCount > callsBefore
                            var called = false
                            if let sessionCallsBefore {
                                let count = await session.toolCallCount()
                                transcribed.withLock { $0 = count }
                                called = count > sessionCallsBefore
                            }
                            // The follow-up half is the verdict's own test —
                            // `isGrounded`, below — asked of the partial, by
                            // a mention the rest of the stream can't unmake.
                            grounded = recorded || called
                                || (isFollowUp && (!rows.isEmpty || Self.partialNamesAThreadRow(
                                    snapshot.answer.map(AskPrompt.partialText), rows: threadRows
                                )))
                        }
                        // **Prose that could be discarded is never drawn.**
                        // Nothing reaches the thread until the turn has read
                        // something, unless the domain keeps answers nothing
                        // grounded (`.notRequired`), so a discarded answer has
                        // nothing on screen to take back.
                        guard grounded, let answer = snapshot.answer, !answer.isEmpty else { continue }
                        let partial = AskPrompt.partialText(answer)
                        guard !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        outlet.send(.partial(partial))
                    }
                    return latest
                } ?? AskReplySnapshot()
            }
        } catch {
            // A raw SDK error becomes an `AskError` here, where the generation
            // threw it, and not in `turn`: `attempt` rolls a follow-up over
            // only on `AskError.contextTooLarge`, so a raw
            // `contextSizeExceeded` has to be triaged before it gets there, or
            // it fails the turn. Logged by its tag here, once: `turn` logs only
            // what reaches it raw.
            if error is CancellationError { throw error }
            if let ask = error as? AskError { throw ask }
            let ask = AskTriage.askError(from: error, tier: tier)
            log.routing("\(tier.rawValue) failed: \(AskTriage.tag(for: error))")
            throw ask
        }

        // Read again in what is left of the deadline, or, once it has passed,
        // as the latch last read it.
        let sessionCallsAfter = await Self.read(until: deadline) { await session.toolCallCount() }
            ?? transcribed.withLock { $0 }
        let calls = max(
            await collector.toolCallCount - callsBefore,
            sessionCallsBefore.flatMap { before in sessionCallsAfter.map { $0 - before } } ?? 0
        )
        let rows = await collector.groundingRows
        let turnRows = await collector.turnRows
        let threadRows = await collector.rows
        let isGrounded = appRetrieved || calls > 0
            || (isFollowUp && (!turnRows.isEmpty || Self.namesAThreadRow(streamed.withLock { $0 }.answer, rows: rows)))
        // What the domain's policy keeps: a grounded answer, or under
        // `.notRequired` any answer, which then records that nothing grounded
        // it. One rule for a finished answer and a truncated one.
        let isKept = isGrounded || grounding == .notRequired

        stats.toolCalls = calls
        stats.rowsRead = rows.count
        let measured = measuring.withLock { $0 }
        stats.snapshots = measured.snapshots
        stats.growths = measured.growths
        stats.timeToFirstWord = measured.firstWord.map { $0 - started }
        stats.timeToLastWord = measured.lastWord.map { $0 - started }
        stats.timeToFirstTool = firstTool.withLock { $0 }.map { $0 - started }
        stats.duration = ContinuousClock().now - started
        // A follow-up is logged as grounded by the thread only when the
        // verdict says so: one discarded as ungrounded logs `.nothing`, as does
        // one `.notRequired` keeps that nothing grounded. The answer records
        // the same.
        stats.grounding = appRetrieved
            ? .appRetrieved
            : (calls > 0 ? .toolCall : (isFollowUp && isGrounded ? .followUp : .nothing))
        // Inside the deadline too, and once it has passed not read at all: a
        // truncated answer goes out without its `[usage]` line rather than
        // waiting on a session that may never say.
        if let usage = await Self.read(until: deadline, { await session.usage() }) ?? nil {
            stats.inputTokens = usage.inputTokens
            stats.cachedTokens = usage.cachedTokens
            stats.outputTokens = usage.outputTokens
            stats.reasoningTokens = usage.reasoningTokens
        }

        // The tiles: none for a kind whose answer is a number or a yes or no,
        // and otherwise the model's titles, resolved against this turn's rows
        // and then the thread's, so a follow-up can show a row an earlier turn
        // read.
        //
        // **Every match is every row THIS turn read.** A follow-up answered
        // from the thread read none, so it found no set to show whole, and
        // the thread's rows in its place would stand every row since the
        // first turn under it: the bank of every row read that `AskCollector`
        // keeps two row sets to prevent. It shows the titles it named, else
        // the rows its prose names.
        //
        // **None under `.prose`**, whatever the snapshot holds: the model was
        // asked for no kind and no tile choice, and a session that streamed
        // the full reply anyway (`AskSession`'s default) chose them for a
        // shape nobody asked for. Nor do the rows its prose names stand in
        // for a choice the domain never asks the model to make.
        func chosenTiles(_ names: [String]?, showsEveryMatch: Bool?, kind: String?, text: String) -> [Row] {
            guard shape == .full else { return [] }
            if let kind, AskQuestionKind.showNoTiles.contains(kind) { return [] }
            return AskAnswer<Row>.tiles(
                named: names ?? [], showsEveryMatch: (showsEveryMatch ?? false) && !turnRows.isEmpty,
                text: text, matches: threadRows, turnMatches: turnRows
            )
        }

        // The ceiling. A stream the policy keeps that had written something
        // is worth more truncated than erased: grounded, it is the reader's
        // own data, correctly, just unfinished (house rule 5). It keeps its tiles once the model
        // has begun its follow-ups, which it writes after them, so the list
        // is finished, and explains them with the basis line as any answer
        // with tiles is. Before that the list may be cut short, and none is
        // kept. The follow-ups themselves are unfinished, and go.
        guard let outcome else {
            let snapshot = streamed.withLock { $0 }
            let partial = AskPrompt.partialText(snapshot.answer ?? "")
            guard isKept, !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                log.discard(AskDiscard(tier: tier, reason: .deadlineWithNothingToKeep, text: partial))
                logTurn(stats)
                throw AskError.couldNotAnswer
            }
            stats.characters = partial.count
            logTurn(stats)
            // The proposal too: the ceiling cut the prose, not the tool that
            // proposed, and nothing is done until the reader confirms.
            let tiles = snapshot.followUps == nil ? [] : chosenTiles(
                snapshot.tiles, showsEveryMatch: snapshot.showsEveryMatch,
                kind: domain.normalizedKind(snapshot.questionKind), text: partial
            )
            var answer = AskAnswer<Row>(
                text: partial, matches: rows, tiles: tiles, followUps: [],
                questionKind: nil, isTruncated: true,
                payload: await collector.turnPayload,
                proposal: await collector.turnProposal,
                grounding: stats.grounding
            )
            answer = answer.replacing(basis: basis(for: answer))
            outlet.answer(answer)
            // Abandoned, not stopped: the generation may still be writing on
            // the session.
            return (answer, true)
        }

        let raw = outcome.answer ?? ""
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.discard(AskDiscard(tier: tier, reason: .empty, text: ""))
            logTurn(stats)
            throw AskError.couldNotAnswer
        }
        guard isKept else {
            log.discard(AskDiscard(tier: tier, reason: .ungrounded, text: raw))
            logTurn(stats)
            throw AskError.ungrounded
        }

        let text = AskPrompt.tidy(raw)
        // A prose reply says no kind, so the answer's is `other`, which
        // decides nothing: no tiles to hold back, and no "Another pick".
        let kind = shape == .prose ? AskQuestionKind.other : domain.normalizedKind(outcome.questionKind)
        let tiles = chosenTiles(outcome.tiles, showsEveryMatch: outcome.showsEveryMatch, kind: kind, text: text)
        stats.characters = text.count
        logTurn(stats)

        var answer = AskAnswer<Row>(
            text: text, matches: rows, tiles: tiles,
            followUps: AskAnswer<Row>.cleanedFollowUps(outcome.followUps ?? []),
            questionKind: kind,
            payload: await collector.turnPayload,
            proposal: await collector.turnProposal,
            grounding: stats.grounding
        )
        answer = answer.replacing(basis: basis(for: answer))

        // A second pass the domain may want, such as a look at photos of the
        // rows the answer chose. A failure keeps the first answer, which is
        // already a good one, and so does a pass the turn's deadline ends.
        //
        // Not `try?`, which would swallow two different things: a pass failing
        // on every turn, after `.refining` was sent,
        // and a stop, which would fall through to keeping a session whose
        // transcript can't be trusted. A failure is logged, and a stop is
        // rethrown, so the stopped turn keeps no session.
        var abandoned = false
        do {
            switch try await refine(
                answer, question: question, tier: tier, box: box, deadline: deadline, continuation: continuation
            ) {
            case .none:
                // Abandoned on the answer's session, which it may still be
                // writing on.
                abandoned = true
                log.routing("the domain's refine pass ran out of time — the first answer kept")
            case .some(.none):
                break
            case .some(.some(let refined)) where refined.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                // A pass that hands back no words, as a blank revision from
                // the model would be, would put an empty bubble where a good
                // answer was. Read as a model's empty answer is: not kept.
                log.routing("the domain's refine pass returned no text — the first answer kept")
            case .some(.some(let refined)):
                // The refined answer is the domain's, built from the first. A
                // payload, a proposal or a grounding it did not carry over is
                // still the first answer's, and the basis is read again for
                // whatever it now shows. Its follow-ups are cleaned as the first pass's
                // were: a pass that writes its own hands back model output.
                // Its tiles are cut to what a bank lays out, as every answer's.
                //
                // Held to the collector's limits first, so a payload or a
                // proposal past them is one it did not carry, and the first
                // answer's, which a tool recorded within them, stands.
                let refined = heldToTheCollectorsLimits(refined, from: "the domain's refine pass")
                var kept = refined.payload == nil ? refined.replacing(payload: answer.payload) : refined
                if kept.proposal == nil { kept = kept.replacing(proposal: answer.proposal) }
                if kept.grounding == nil { kept = kept.replacing(grounding: answer.grounding) }
                kept = kept.replacing(followUps: AskAnswer<Row>.cleanedFollowUps(kept.followUps)).cappingTiles()
                answer = kept.replacing(basis: kept.basis ?? basis(for: kept))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.routing("the domain's refine pass failed: \(AskTriage.tag(for: error))")
        }
        outlet.answer(answer)
        return (answer, abandoned)
    }

    /// The domain's refine pass, inside what is left of the turn's deadline:
    /// nil when the deadline ended it, `.some(nil)` when the domain kept the
    /// answer it had, or when no time was left to ask it.
    private func refine(
        _ answer: AskAnswer<Row>,
        question: String,
        tier: AskTier,
        box: AskSessionBox,
        deadline: ContinuousClock.Instant,
        continuation: AsyncThrowingStream<Event, any Error>.Continuation
    ) async throws -> AskAnswer<Row>?? {
        guard ContinuousClock().now < deadline else {
            log.routing("no time left for the domain's refine pass — the first answer kept")
            return .some(nil)
        }
        // The session the answer was written on, not a new one: the pass shows
        // the model what it just named, and the transcript is what makes that
        // sentence mean anything. Behind the generation gate, because a pass
        // that asks the model again is a second generation inside the turn.
        // The asking is also what the reader is told about: a pass that only
        // reorders what it has asks nothing, and announces nothing.
        //
        // `.refining` must not follow the answer: the store clears the activity
        // when the answer lands, so a late one stays up under a settled turn.
        // A pass the deadline ends is abandoned, not stopped, and can still ask
        // the model after `stream` has yielded the first answer. So the
        // announcement closes under the same lock it is made under, before this
        // returns, and a pass that asks later announces nothing.
        let announcement = Mutex((made: false, closed: false))
        let gated = AskSessionBox(
            session: AskGatedSession(base: box.session, seam: seam, onDevice: tier != .privateCloud) {
                announcement.withLock { state in
                    guard !state.made, !state.closed else { return }
                    state.made = true
                    continuation.yield(.refining)
                }
            },
            tier: box.tier
        )
        defer { announcement.withLock { $0.closed = true } }
        let domain = self.domain
        return try await AskDeadline.run(until: deadline) {
            try await domain.refine(answer, question: question, tier: tier, session: gated)
        }
    }

    // MARK: - Feedback

    /// A reader's thumbs on an answer: always to the log, and, for the newest
    /// answer while the session that wrote it is still kept, to that session's
    /// feedback attachment, the transcript Apple asks for with a model-quality
    /// report.
    ///
    /// Returns the attachment, or nil when no kept session's transcript ends
    /// at that answer, or none is wanted: a restored thread with nothing
    /// asked on it yet, a stopped turn, an older turn, an answer the domain
    /// gave without a model or a caller where no attachment is kept (the
    /// caller says those last three through `isLatestTurn`), and a verdict
    /// that arrives once the next question is already running.
    public func recordFeedback(_ feedback: AskFeedback, isLatestTurn: Bool) async -> Data? {
        log.feedback(feedback)
        guard isLatestTurn, inFlight == nil, let conversation else { return nil }
        return await conversation.box.session.feedbackAttachment(sentiment: feedback.sentiment)
    }

    // MARK: - Helpers

    /// The sampling temperature a turn runs at.
    ///
    /// 0.4 for every question, the temperature grounding was measured at.
    /// "Another pick" is the one turn that wants a different answer to the
    /// same question, and at 0.4 the first choice tends to come straight back:
    /// the steer says what to avoid, and 0.8 gives the model room to find
    /// something else.
    nonisolated static func temperature(for origin: AskOrigin) -> Double {
        origin == .reroll ? 0.8 : 0.4
    }

    /// The domain's basis line for an answer that chose something to show —
    /// never for one whose number or yes-or-no is the answer, since a count, a
    /// total or a yes or no shows no tiles and there is no choice for a basis
    /// to explain.
    private func basis(for answer: AskAnswer<Row>) -> String? {
        guard !answer.tiles.isEmpty else { return nil }
        if let kind = answer.questionKind, AskQuestionKind.showNoTiles.contains(kind) { return nil }
        return domain.basis(for: answer)
    }

    /// An answer the domain built itself, held to what a tool could have
    /// recorded for one the model wrote: a payload past
    /// `AskCollector.maxPayloadBytes` goes, as does a proposal whose payload
    /// is past `AskProposal.maxPayloadBytes`, and its rows stop at
    /// `AskCollector.maxThreadRows`. `source` names it in the line that says
    /// what went.
    ///
    /// The answer rides into the thread file with every turn kept, and the
    /// file is rewritten after every turn: a 1 MB payload a turn would make
    /// that tens of megabytes. A card missing is the smaller failure, as it
    /// is when the collector refuses a tool. The rows stop at the thread's
    /// cap, not the turn's: a follow-up that read nothing stands on the
    /// thread's rows, and a refine pass built from it carries them on.
    private func heldToTheCollectorsLimits(_ answer: AskAnswer<Row>, from source: String) -> AskAnswer<Row> {
        var dropped: [String] = []
        var payload = answer.payload
        if let size = payload?.count, size > AskCollector<Row>.maxPayloadBytes {
            payload = nil
            dropped.append("its \(size)-byte payload dropped")
        }
        var proposal = answer.proposal
        if let size = proposal?.payload.count, size > AskProposal.maxPayloadBytes {
            proposal = nil
            dropped.append("its proposal, with a \(size)-byte payload, dropped")
        }
        var matches = answer.matches
        if matches.count > AskCollector<Row>.maxThreadRows {
            dropped.append("its \(matches.count) rows cut to \(AskCollector<Row>.maxThreadRows)")
            matches = Array(matches.prefix(AskCollector<Row>.maxThreadRows))
        }
        guard !dropped.isEmpty else { return answer }
        log.routing("\(source) was held to what a tool can record: \(dropped.joined(separator: ", "))")
        return AskAnswer(
            text: answer.text, matches: matches, tiles: answer.tiles, followUps: answer.followUps,
            questionKind: answer.questionKind, isTruncated: answer.isTruncated, basis: answer.basis,
            payload: payload, proposal: proposal, grounding: answer.grounding
        )
    }

    /// A session for `tier` with the domain's tools built around
    /// `collector` and `relay`, built inside what is left of `deadline`: the
    /// answer language can wait on Private Cloud Compute's locale probe, a
    /// network call. A turn passes its own, since whatever a turn waits on
    /// before its answer shares the turn's one deadline, and a prewarm passes
    /// the domain's turn deadline counted from its call.
    private func makeSession(
        tier: AskTier,
        collector: AskCollector<Row>,
        relay: AskActivityRelay,
        isConversation: Bool,
        deadline: ContinuousClock.Instant
    ) async throws -> AskSessionBox? {
        let context = AskToolContext(
            collector: collector, relay: relay,
            rowLimit: domain.rowLimit(for: tier), tier: tier, isConversation: isConversation
        )
        let tools = domain.makeTools(context)
        let seam = self.seam
        let domain = self.domain
        let build: @Sendable () async throws -> AskSessionBox? = {
            // Asked of the seam, not of the locale: a tier that cannot write
            // the app's language answers in English rather than spending a
            // request that bounces `unsupportedLanguageOrLocale`, and only the
            // seam knows which.
            let language = await seam.answerLanguage(for: tier)
            // The same `isConversation` the tool set was just built with, so
            // the sentences and the tools cannot disagree about what is
            // registered.
            let instructions = domain.instructions(
                tier: tier, isConversation: isConversation, answerLanguage: language
            )
            return try await seam.makeSession(tier: tier, tools: tools, instructions: instructions)
        }
        guard let made = try await AskDeadline.run(until: deadline, build) else {
            log.routing("ran out of time building a \(tier.rawValue) session")
            throw AskError.couldNotAnswer
        }
        // A seam bridging a host's router may answer with another tier's
        // session. The engine runs the turn on the box's tier, and says so
        // here, since tools and instructions were built for the one asked.
        if let made, made.tier != tier {
            log.routing("asked for a \(tier.rawValue) session and was given a \(made.tier.rawValue) one")
        }
        return made
    }

    /// Whether a follow-up's prose names something the thread has read — the
    /// weaker of the two ways a follow-up can be grounded, and the one that
    /// lets "which of those is on vinyl?" pass without a second search.
    ///
    /// Asked of the finished answer, and of every streamed snapshot until one
    /// passes (`partialNamesAThreadRow(_:rows:)`), so the prose that draws and
    /// the prose that is kept are judged by one rule. `nonisolated static`
    /// because the snapshot loop runs inside the seam's generation closure,
    /// and an actor hop per snapshot to evaluate a pure function is a cost
    /// with nothing behind it.
    nonisolated private static func namesAThreadRow(_ text: String?, rows: [Row]) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return !AskAnswer<Row>.mentioned(in: text, among: rows).isEmpty
    }

    /// `namesAThreadRow(_:rows:)` asked of a streamed partial, counting only
    /// a mention no later snapshot can unmake.
    ///
    /// A title shorter than `AskAnswer.wholeWordBelow` is a mention only as a
    /// whole word, and a partial's end is not yet the end of a word: "Go"
    /// ends "You might like Go", and a snapshot later it is inside "Gothic",
    /// where the verdict on the finished answer finds nothing. Latched on the
    /// first, the prose would draw and then fail as ungrounded under it
    /// (house rule 2). So the partial is read twice, as it stands and with a
    /// letter after it, and a row counts only when both reads name it: a
    /// mention the letter unmakes is one the next snapshot can, and one the
    /// letter completes is in the second read alone. Every other mention
    /// has both its neighbours already, and keeps them.
    nonisolated private static func partialNamesAThreadRow(_ partial: String?, rows: [Row]) -> Bool {
        guard let partial, !partial.isEmpty else { return false }
        let named = AskAnswer<Row>.mentioned(in: partial, among: rows)
        // Nothing named as it stands, nothing to settle: the second read is
        // spent only on a partial that might latch.
        guard !named.isEmpty else { return false }
        let settled = Set(AskAnswer<Row>.mentioned(in: partial + "x", among: rows).map(\.id))
        return named.contains { settled.contains($0.id) }
    }

    /// One of a session's own reads, such as its transcript's tool calls,
    /// its usage or its window, inside the turn's deadline: nil once the
    /// deadline has passed, or when the caller lets go.
    ///
    /// The session is the host's when its seam builds its own, and a read
    /// that never returns would otherwise hold the turn in flight past any
    /// deadline and any Stop, and every question after it.
    nonisolated private static func read<T: Sendable>(
        until deadline: ContinuousClock.Instant,
        _ read: @escaping @Sendable () async -> T
    ) async -> T? {
        try? await AskDeadline.run(until: deadline, read)
    }

    /// Whether the next turn should roll this conversation over rather than
    /// waiting for the overflow: the last response's input and output — the
    /// transcript the next request starts from — against the window, by the
    /// kept tier's rule (`AskContinuation.shouldRollOver(usedTokens:contextSize:tier:)`).
    ///
    /// Both are read inside the turn's deadline. One that runs out of it
    /// reads as a tier that couldn't say, and the turn count decides alone,
    /// as `shouldRollOver(usedTokens:contextSize:tier:)` says: with the
    /// deadline gone there is no time to start a session over either, and
    /// the follow-up fails at once, leaving the session to be started fresh.
    private func shouldRollOver(_ kept: AskConversation<Row>, deadline: ContinuousClock.Instant) async -> Bool {
        let session = kept.box.session
        let usage = await Self.read(until: deadline) { await session.usage() } ?? nil
        let size = await Self.read(until: deadline) { await session.contextSize() } ?? nil
        // The window rule of the model the session runs on.
        return AskContinuation.shouldRollOver(
            usedTokens: usage.flatMap { ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0) },
            contextSize: size,
            tier: kept.box.tier
        )
    }
}

/// One generation's way out to the reader's stream, shut by its answer: what
/// is sent after the answer is dropped, so no `.partial`, `.rowsRead` or
/// `.activity` ever follows `.answer`. The answer goes out under the same
/// lock that shuts it, so nothing sent from another task can land between.
///
/// What it lets out of the prose and the rows read, it notes in `drawn`: what
/// the reader has on screen.
nonisolated private final class AskAnswerOutlet<Row: AskRow>: Sendable {
    private let continuation: AsyncThrowingStream<AskTurnEvent<Row>, any Error>.Continuation
    private let drawn: AskDrawn<Row>
    private let isOpen = Mutex(true)

    init(_ continuation: AsyncThrowingStream<AskTurnEvent<Row>, any Error>.Continuation, drawn: AskDrawn<Row>) {
        self.continuation = continuation
        self.drawn = drawn
    }

    /// Send `event`, unless the answer is already out.
    func send(_ event: AskTurnEvent<Row>) {
        isOpen.withLock { open in
            guard open else { return }
            continuation.yield(event)
            switch event {
            case .partial(let text): drawn.drew(text)
            case .rowsRead(let rows): drawn.read(rows)
            default: break
            }
        }
    }

    /// Send the answer, and shut the outlet.
    func answer(_ answer: AskAnswer<Row>) {
        isOpen.withLock { open in
            open = false
            continuation.yield(.answer(answer))
        }
    }
}

/// What one turn has on the reader's screen: the prose of the last `.partial`
/// and the rows of the last `.rowsRead` it sent, since its last `.restarted`,
/// which clears both, as AskUI's store clears them.
///
/// A turn keeps one across its attempts, so the engine can tell a hand-down
/// or a rollover whether there is prose to take back, and a stop which words
/// the reader keeps as its answer.
nonisolated final class AskDrawn<Row: AskRow>: Sendable {
    private let state = Mutex<(prose: String, rows: [Row])>(("", []))

    /// The prose drawn, as the last `.partial` sent it.
    var prose: String { state.withLock { $0.prose } }
    /// The rows read, as the last `.rowsRead` sent them.
    var rows: [Row] { state.withLock { $0.rows } }

    func drew(_ prose: String) {
        state.withLock { $0.prose = prose }
    }

    func read(_ rows: [Row]) {
        state.withLock { $0.rows = rows }
    }

    /// The attempt that drew them was thrown away (`AskTurnEvent.restarted`).
    func restart() {
        state.withLock { $0 = ("", []) }
    }
}

#endif
