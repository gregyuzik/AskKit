#if canImport(FoundationModels) && !os(tvOS)

import CoreGraphics
import Foundation
import FoundationModels

/// What a session's tools are given: where to record what they read, where to
/// say what they are doing, and the budgets for this tier.
///
/// Built once per session and handed to `AskDomain.makeTools(_:)`, because the
/// tool set stays the same for the session's life: changing it would throw
/// away the session's cached prefix (house rule 6). That is why the activity
/// relay is a stable object whose listener the engine swaps each turn, rather
/// than a closure captured per turn.
///
/// **A tool runs each call's work in `withToolCall(_:_:)`**, the one public
/// way to report a call. It keeps the bookkeeping in the one order that
/// works: the call noted with the collector, the work, the call finished
/// however the work ends, and only then the phrase the work hands back
/// reported to the relay. The two rules below are why.
///
/// **The relay hears last, after the call has finished, not before.** The
/// two routes aren't independent: the collector's in-flight count reaching
/// zero raises `.activityEnded`, and `AskConversationStore` applies that by
/// clearing the turn's activity. So a `relay.report(.reading(…))` made while
/// the calling tool is still open is set and then cleared one await later: it
/// draws for no frames, and the wait row reads "Thinking…" through the whole
/// compose. Reported after the finish, it stands until the next event or the
/// first word of prose, which is what the relay is for.
///
/// **The finish comes however the call ends.** A call that threw before it
/// was finished would leave the count above zero for the rest of the turn,
/// and every later tool's idle signal with it.
nonisolated public struct AskToolContext<Row: AskRow>: Sendable {
    /// Where the tools record the rows they read and report each call.
    public let collector: AskCollector<Row>
    /// Where a tool says what it is doing, for the wait row, once its call has
    /// finished (see above). `withToolCall(_:_:)` reports here for it.
    public let relay: AskActivityRelay
    /// How many rows one tool result may show the model on this tier. Never
    /// negative, so `prefix(rowLimit)` in a tool can't trap.
    public let rowLimit: Int
    /// The tier the session runs on.
    public let tier: AskTier
    /// Whether this session belongs to the thread. False for a one-shot
    /// answer (`AskTurnMode.standalone`), such as a Siri intent's, which has
    /// no card to confirm a proposal on (`AskProposal`). Its session's tools
    /// and its grounded retry's search are told the same.
    public let isConversation: Bool

    /// A context over a session's collector and relay, with the tier's
    /// budgets. The engine builds one for each session, and one for each
    /// grounded retry's search. A negative `rowLimit`, such as a domain's
    /// `rowLimit(for:)` that miscounted, reads as zero.
    public init(
        collector: AskCollector<Row>,
        relay: AskActivityRelay,
        rowLimit: Int,
        tier: AskTier,
        isConversation: Bool
    ) {
        self.collector = collector
        self.relay = relay
        self.rowLimit = max(0, rowLimit)
        self.tier = tier
        self.isConversation = isConversation
    }
}

nonisolated extension AskToolContext {
    /// Run one tool call's work inside its bookkeeping, in the order this
    /// type states: the call noted with the collector, with `activity` for
    /// the wait row, `body` run with the collector to record into, the call
    /// finished whether `body` returns or throws, and then the phrase `body`
    /// handed back reported to the relay. A nil phrase reports nothing.
    ///
    /// `body` hands back the tool's result with the phrase, since the phrase
    /// usually says what the work found (`.reading(shown:total:scope:)`). A
    /// throw from `body` reaches the caller once the call has finished, with
    /// nothing reported.
    ///
    /// **`body` runs on its caller's executor**, as `nonisolated(nonsending)`
    /// says: off every actor from a tool's `@concurrent` call, on the main
    /// actor from a main-actor caller, and never on the collector or the
    /// relay. That is spelled out rather than left to
    /// `NonisolatedNonsendingByDefault`, which a host may not build with. It
    /// never leaves its caller, so it needn't be `@Sendable` and may touch
    /// the caller's own state.
    nonisolated(nonsending) public func withToolCall<T>(
        _ activity: AskActivity? = nil,
        _ body: nonisolated(nonsending) (AskCollector<Row>) async throws -> (T, report: AskActivity?)
    ) async rethrows -> T {
        let outcome: (T, report: AskActivity?)
        do {
            // `await` directly in an async `defer` (SE-0493). A `Task` around
            // the finish would leave it unordered against the report below,
            // and the idle signal could clear the phrase as it lands.
            defer { await collector.noteToolFinished() }
            await collector.noteToolCall(activity)
            outcome = try await body(collector)
        }
        if let report = outcome.report { await relay.report(report) }
        return outcome.0
    }
}

/// The search arguments of a domain with no search of its own: the default
/// `AskDomain.SearchArguments`, with nothing for the grounded retry's planner
/// to choose.
///
/// With it, `AskDomain.search(_:context:)` has a default, which fails the turn
/// as ungrounded.
@Generable
nonisolated public struct AskNoSearchArguments: Sendable {
    /// No arguments.
    public init() {}
}

/// Everything about Ask that is one app's rather than every app's.
///
/// The engine, the screen, the seam, the store, the grounding policies and
/// the error copy are AskKit's. The tools and the words are the host's, and so
/// are the data and the tiles where it has rows to show, and they arrive
/// through here.
///
/// **A domain whose tools read no rows** names neither associated type, so
/// `Row` is `AskNoRow` and `SearchArguments` is `AskNoSearchArguments`, and
/// leaves `overview()` and `search(_:context:)` to their defaults. Its
/// `grounding` says what becomes of a first answer that calls no tool: under
/// `.retrieval`, the default, the grounded retry has nothing to search and
/// the answer fails as ungrounded; under `.toolCall` it fails at once; under
/// `.notRequired` it is kept. Its overview is empty, so under `.retrieval` it
/// sets `firstScreenPolicy` to `.openSubject`, which the other two policies
/// get by default.
///
/// Inside the Foundation Models platform gate, because it names `Tool` and
/// `Generable`.
nonisolated public protocol AskDomain: Sendable {
    /// The host's row type: a book, a record, a tool. `AskNoRow` by default,
    /// for a domain whose tools read no rows.
    associatedtype Row: AskRow = AskNoRow
    /// The arguments the domain's own search takes, asked for as structured
    /// output when a first turn skips retrieval and the app has to search for
    /// the model, under `AskGroundingPolicy.retrieval`. The same type, with
    /// the same `@Guide`s, the tool would have been called with.
    ///
    /// `AskNoSearchArguments` by default, for a domain with no search, which
    /// then has a default `search(_:context:)` as well.
    associatedtype SearchArguments: Generable & Sendable = AskNoSearchArguments

    // MARK: Identity

    /// The host's own copy, the Application Support folder the thread is kept
    /// in, and the log subsystem every AskKit logger writes under.
    var brand: AskBrand { get }
    /// Whether the thread survives the process.
    var persistence: AskPersistence { get }
    /// The subset of `AskQuestionKind.all` this domain's questions really come
    /// in. Anything the model returns outside it is normalized to `other`.
    var questionKinds: [AskQuestionKind] { get }
    /// How long one turn may run, counted from the question: the domain's
    /// `deterministicAnswer(for:)`, `overview()` and
    /// `promptLines(question:overview:)`, every generation in it, the tools
    /// they call, the grounded retry's search, the refine pass and a
    /// hand-down to the other tier all share it. When it passes during the
    /// answer, the prose on screen, all of it prose the domain's `grounding`
    /// keeps, becomes the answer, marked truncated; with none, the turn
    /// fails. A refine pass it cuts short leaves the first answer.
    var turnDeadline: Duration { get }
    /// Whether the composer offers a photo attachment, and whether the store
    /// takes a photo at all (`AskConversationStore.attachPhoto`).
    var acceptsPhotoAttachments: Bool { get }
    /// Which answers the engine keeps, by what grounded them
    /// (`AskGroundingPolicy`): whether prose waits for a retrieval, whether a
    /// first answer that read nothing gets the grounded retry, and whether a
    /// turn nothing grounded fails as ungrounded or is kept.
    ///
    /// **Per domain, and fixed for its life.** The engine reads it once, as it
    /// is built. Never per question: a policy chosen from the question's
    /// words would be a host's word list deciding what is kept after
    /// generation (house rule 7), and the tools a turn is grounded by are
    /// fixed for a session's life (house rule 6).
    var grounding: AskGroundingPolicy { get }
    /// Which reply the model writes for each turn (`AskReplyShape`): the full
    /// one, which says what kind of question it was and which rows to show as
    /// tiles, or `.prose`, the answer and its follow-ups alone.
    ///
    /// Under `.prose` no answer the model writes shows tiles, even with rows
    /// behind it, and its question kind is `other`, so none offers "Another
    /// pick". The rows a turn read are still its evidence, and a follow-up
    /// still refers to the ones its prose names (`referent(from:)`). An
    /// answer the domain builds itself, in `deterministicAnswer(for:)` or a
    /// refine pass, is the domain's to shape.
    ///
    /// **Per domain, and fixed for its life.** The engine reads it once, as
    /// it is built: a follow-up isn't sent the reply's schema again, so a
    /// session answers in the shape its first turn asked for, and the schema
    /// is part of the prefix a session caches (house rule 6).
    var replyShape: AskReplyShape { get }
    /// What the first screen may show: whether an empty library means there is
    /// nothing to ask about, and whether the starters work with no model.
    var firstScreenPolicy: AskFirstScreenPolicy { get }

    // MARK: Budgets

    /// How many rows one tool result may show the model on `tier`
    /// (`AskToolContext.rowLimit`).
    func rowLimit(for tier: AskTier) -> Int
    /// How many turns one session carries before the thread rolls over with a
    /// recap.
    func maxTurns(for tier: AskTier) -> Int

    // MARK: Data

    /// What the reader has to ask about: scopes and counts. Read when the
    /// screen appears and when the app comes back to the foreground, and
    /// before a fresh session's first prompt is built.
    ///
    /// `.empty` by default, for a domain whose subject isn't rows the reader
    /// keeps. Under a first-screen policy that needs owned rows, the default
    /// one for a domain that retrieves, an empty overview is the
    /// nothing-to-ask first screen, so such a domain under `.retrieval` sets
    /// `AskFirstScreenPolicy.openSubject`.
    ///
    /// The read before a prompt runs inside the turn's deadline
    /// (`turnDeadline`): one still running when it passes is abandoned, and
    /// the turn fails. AskUI's store gives its own read the same time, off
    /// the main actor, and one still running then is abandoned while the
    /// overview read before it stands.
    func overview() async -> AskOverview

    // MARK: The model's side

    /// The tools a session offers the model, built around `context`. Three
    /// rules:
    ///
    /// 1. **Built once per session.** The engine calls this as it builds a
    ///    session, a warm one nobody takes included, and the session keeps
    ///    the tools for its life (house rule 6). So a tool captures nothing
    ///    per turn: it keeps `context` and reaches each turn through the
    ///    collector and the relay, whose listeners the engine swaps.
    /// 2. **No proposing tool outside a conversation.** When
    ///    `context.isConversation` is false, leave out any tool that records
    ///    an `AskProposal` (which says why), and name only the tools you
    ///    return in `instructions(tier:isConversation:answerLanguage:)`.
    /// 3. **Every call reported to the collector.** A tool runs each call's
    ///    work in `context.withToolCall(_:_:)`, which notes the call as it
    ///    starts, finishes it however the work ends, and only then reports
    ///    the phrase the work hands back to the relay, in the order
    ///    `AskToolContext` states. Inside it, the tool records every row it
    ///    shows the model with `record(rows:)`, since an answer's tiles
    ///    resolve only against recorded rows.
    ///
    /// What a tool returns reaches the model as it stands, and its rows are
    /// the reader's own data: show at most `context.rowLimit` of them, and
    /// clamp or neuter each field with `AskPrompt` (house rule 3).
    func makeTools(_ context: AskToolContext<Row>) -> [any Tool]
    /// The session's instructions: the host's own words, **short**, and never
    /// mixed with the reader's. Measured on Private Cloud Compute, three
    /// sentences of instructions grounded 3 of 3 runs where about 1,100 words
    /// grounded 0 of 3 (house rule 3). Mappings such as which word means
    /// which category belong in the tools' `@Guide`s, not restated here.
    ///
    /// `isConversation` is the same flag `makeTools` gets, and it is here for
    /// the same reason: a domain whose tool set narrows for a one-shot must be
    /// able to narrow the sentences describing it. Naming a tool the session
    /// doesn't hold is not a spare sentence: the model calls it, the runtime
    /// has no such tool, and the turn spends its budget failing.
    ///
    /// `answerLanguage` is the English name of the language to answer in, or
    /// nil for English (`AskModelSeam.answerLanguage(for:)`). Only the domain
    /// can phrase it.
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String
    /// The static opening of every prompt: what `prewarm(promptPrefix:)`
    /// caches ahead of the question. **Byte-stable**, or the warm session's KV
    /// cache is thrown away.
    ///
    /// Empty by default: a fresh session's prompt then opens with the recap
    /// and the domain's lines, and a warm session caches no words ahead of
    /// them.
    var promptPrefix: String { get }
    /// The domain's lines between the prefix and the fenced question, such as
    /// today's date or what the reader has.
    ///
    /// Asked when a question starts a fresh session (the thread's first, a
    /// rollover, a hand-down), and reused by that attempt's grounded retry. A
    /// follow-up on a kept session sends none: the session's transcript
    /// already holds the lines its first prompt carried.
    ///
    /// It runs inside the turn's deadline (`turnDeadline`): one still running
    /// when it passes is abandoned, and the turn fails.
    func promptLines(question: String, overview: AskOverview) async -> [String]
    /// The line for a question a host asked from one part of what the app
    /// holds, such as a shelf's "Ask About My Records"
    /// (`AskConversationStore.prefill(_:scope:send:)`), saying which, and how
    /// the tools keep to it. `scope` is the id the host passed: the app's own
    /// words, never the reader's, so it is not fenced.
    ///
    /// It rides every prompt the question is asked with: the first of a fresh
    /// session, the grounded retry's plan and its re-ask, and ahead of a
    /// follow-up's. Nil, the default, adds nothing, and the question goes as it
    /// would unscoped: a scope means something only to the tools that can
    /// keep to it, which only the domain knows the arguments of.
    func scopeLine(for scope: String) -> String?

    // MARK: The grounded retry
    //
    // Only a domain whose `grounding` is `.retrieval` has one: under the other
    // policies these two are never asked.

    /// How to choose search arguments, for the planner session that has no
    /// tools. Short around the argument rules: everything about writing an
    /// answer is beside the point for a reply that is a few arguments, and it
    /// must never name a tool, since there is none on that session.
    ///
    /// By default one sentence asking for the search that would find what the
    /// question is about, which names no tool: the `@Guide`s on
    /// `SearchArguments` then carry the argument rules alone.
    var searchPlanInstructions: String { get }
    /// Run the grounded retry's search, through the same code path the tool
    /// takes, and return what the model would have been shown. Recording the
    /// rows into the collector is the domain's job here, exactly as the tool
    /// does it.
    ///
    /// `arguments` are the ones the planner chose. A domain whose
    /// `SearchArguments` is `AskNoSearchArguments` has none to choose, so no
    /// planner is asked, and this runs with the empty value.
    ///
    /// Defaulted only for a domain whose `SearchArguments` is
    /// `AskNoSearchArguments`. A domain that names its own arguments writes
    /// this.
    func search(_ arguments: SearchArguments, context: AskToolContext<Row>) async throws -> String

    // MARK: The reader's side

    /// The questions the first screen offers, and the coaching pair under a
    /// refused or ungrounded answer. Asked when the screen appears and when
    /// the app comes back to the foreground, with a fresh `overview`.
    ///
    /// `window` is the most starters the first screen shows at once: three on
    /// iPhone and iPad, eight on the Mac and Apple Vision Pro
    /// (`AskLayout.starterBank`). A short layout shows fewer, such as two
    /// beside the copy on a phone on its side over a host's slot. It is a
    /// ceiling, not a quota: return fewer when there are fewer good questions
    /// to ask. The screen shows the first of the starters the reader hasn't
    /// tapped or dismissed ("Don't suggest this"), as many as it has room for,
    /// so any past that move up as the reader dismisses chips, and the
    /// coaching pair is the first two of those same starters.
    ///
    /// None by default: the first screen shows its copy and the composer, and
    /// a refused or ungrounded answer has no chips under it.
    func starters(overview: AskOverview, window: Int) -> [AskStarter]
    /// The phrase the wait row shows for a tool event, or nil to leave the row
    /// on its default.
    ///
    /// **Resolve it against your own bundle.** This returns a resolved
    /// `String`, so the lookup happens in the domain. In a Swift package, a
    /// bare `String(localized:)` searches the host app's main bundle, finds
    /// nothing, and returns the key. That failure is silent, and it is per
    /// locale: English reads correctly because the key is the English text.
    /// Write `String(localized: "…", bundle: #bundle)`.
    ///
    /// Why not `LocalizedStringResource?`: ARCHITECTURE.md, Rejected designs.
    func phrase(for activity: AskActivity) -> String?
    /// The titles a follow-up refers back to: "which of those…" needs a list,
    /// not an inference.
    ///
    /// By default the titles of the tiles the answer showed, or, when it
    /// showed none, of the rows its prose names (`AskAnswer.mentioned`).
    func referent(from answer: AskAnswer<Row>) -> [String]

    /// What to call the part of the reader's data an answer read, for the
    /// evidence line: "From 12 items in your Vinyl Records". Nil when the rows
    /// span more than one part, or when the app has no such division: the line
    /// then names the count alone.
    ///
    /// It is the domain's because only the domain knows when the rows are
    /// uniform: a domain might name the shelf when every row shares a
    /// category, and say nothing when they don't. Asked only for AskKit's
    /// counted line (`AskEvidencePresentation.counted`).
    func evidenceScope(from answer: AskAnswer<Row>) -> String?

    /// What the evidence line under `answer` says: AskKit's count (`.counted`,
    /// the default), the domain's own resolved line (`.line`), or nothing
    /// (`.hidden`). The line opens onto the rows behind the answer whichever
    /// words it reads, where there are some and the host draws them.
    ///
    /// Under `.counted`, an answer nothing grounded (`AskGrounding.nothing`)
    /// reads "Not from this app's data" in place of a count. A domain whose
    /// rows aren't items words the line itself, and one that attributes its
    /// answers another way leaves it out; `answer.grounding` tells it which
    /// answers nothing grounded.
    ///
    /// Asked each time the answer's row is drawn, so return a value you
    /// already have. Resolve a `.line` against your own bundle, for the
    /// reason `phrase(for:)` gives.
    func evidence(for answer: AskAnswer<Row>) -> AskEvidencePresentation

    /// One factual sentence about why an answer chose what it shows ("Your
    /// highest-rated jazz record"), written from the rows' own fields. Never
    /// sentiment, never a percentage. Nil for no line, which is the default.
    ///
    /// Asked only of an answer that shows tiles and whose kind isn't in
    /// `AskQuestionKind.showNoTiles`. Resolve it against your own bundle, for
    /// the reason `phrase(for:)` gives.
    func basis(for answer: AskAnswer<Row>) -> String?

    /// The question kinds whose answers offer "Another pick". **None by
    /// default**: a domain opts in with the kinds whose answers are choices,
    /// such as an outfit or a recommendation. Never a count or a total: the
    /// number is the answer, and there is no other pick to ask for.
    ///
    /// Not `pick` by default, obvious as it looks: "my oldest record" has one
    /// right answer, so another pick of it is a wrong one, and a domain that
    /// doesn't list `superlative` in `questionKinds` gets its superlatives as
    /// picks. Such a domain listing `pick` here says which of its picks are
    /// superlatives in `isRerollable`; one that lists `superlative` gets them
    /// apart from the model, and can still check.
    var rerollableKinds: Set<AskQuestionKind> { get }

    /// Whether this answer offers "Another pick": by default, whether its kind
    /// is in `rerollableKinds`. A domain that can tell a superlative from a
    /// recommendation, from its tool's arguments, its rows or its payload,
    /// says so here. Asked only of a settled answer that shows tiles, isn't
    /// truncated, and isn't a count, a total or a yes or no.
    func isRerollable(_ answer: AskAnswer<Row>, question: String) -> Bool

    // MARK: Actions

    /// Carry out a proposal the reader confirmed, and return the line the card
    /// shows once it is done ("Marked The Dispossessed as lent."), or nil for "That's done".
    ///
    /// **Called only from the reader's tap**, never from a tool: a proposing
    /// tool records an `AskProposal` and returns (`AskProposal` says how). Throw
    /// `AskProposalFailure` with the line the card should show when it can't be
    /// done; anything else thrown reads a generic line, and either way the card
    /// on the newest turn offers the action again. Resolve lines against your
    /// own bundle, for the reason `phrase(for:)` gives.
    ///
    /// **At most once for each yes.** The store saves the reader's yes with
    /// the turn (`AskProposalOutcome.performing`) and calls this only once
    /// that write has landed; a thread kept for the process only, which no
    /// relaunch reads back, saves nothing first. A yes the disk refuses is
    /// never carried out, and the card says it couldn't be done. An app
    /// killed while this runs, or before its outcome is written, reads the
    /// card back as unknown, and it takes no tap. So this runs again only on
    /// a new yes after it threw: one that throws having done part of its work
    /// should be safe to run again from there.
    ///
    /// **Off the main actor.** The store calls it from a `@concurrent`
    /// function of its own, so a `nonisolated` perform runs off the main
    /// actor whatever the host's concurrency settings, and a slow network
    /// call or write hitches nothing on screen.
    ///
    /// The default throws: a domain that proposes nothing is never asked, and
    /// one that proposes without saying how to perform fails on the card
    /// rather than claiming it succeeded.
    func perform(_ proposal: AskProposal) async throws -> String?

    // MARK: Optional hooks

    /// An answer the app can give without a model: small talk, or a starter on
    /// a device where nothing can serve. An answer returned here is the whole
    /// turn, and no model is asked.
    ///
    /// It runs inside the turn's deadline (`turnDeadline`): one still running
    /// when it passes is abandoned, and the turn fails.
    func deterministicAnswer(for question: String) async -> AskAnswer<Row>?
    /// Whether this domain overrides `deterministicAnswer(for:)`: set it true
    /// alongside the override.
    var implementsDeterministicAnswer: Bool { get }
    /// A second pass over an answer the app already has, such as a look at
    /// photos of the rows it chose. Return nil to keep the first answer, which
    /// a failure keeps too.
    ///
    /// `session` is the one the answer was written on, so the pass can show the
    /// model what it just named and ask it to revise. A fresh session would
    /// have no such transcript, and a revision anchored to nothing would rest
    /// on no retrieval, which a domain that retrieves never shows (house
    /// rule 2).
    ///
    /// The pass runs inside the turn's deadline (`turnDeadline`): one still
    /// running when it lands is abandoned, and the first answer kept. A
    /// generation it asks of `session` goes through the generation gate on
    /// device, and the first one sends `AskTurnEvent.refining`. The engine
    /// keeps the first answer's payload, proposal and grounding where the
    /// refined one has none, asks `basis(for:)` again unless it brings its
    /// own, and cleans its follow-ups as it cleaned the first answer's. A pass that chooses between its follow-ups and the
    /// first answer's, keeping those when its own clean to nothing, cleans its
    /// own first with `AskAnswer.cleanedFollowUps(_:)`.
    func refine(
        _ answer: AskAnswer<Row>,
        question: String,
        tier: AskTier,
        session: AskSessionBox
    ) async throws -> AskAnswer<Row>?
    /// The thumbnail above a question asked with a photo, once the thread has
    /// been read back from disk and no longer has the pixels. `photo.reference`
    /// is what the host handed `AskConversationStore.attachPhoto`. Nil, the
    /// default, draws a glyph in the thumbnail's place.
    ///
    /// **A read of the reader's own photo**, so it goes through the app's
    /// guarded read. The thumbnail asks it from a `@concurrent` function of
    /// its own, as the store asks `perform`, so a `nonisolated` one runs off
    /// the main actor whatever the host's concurrency settings.
    func photoThumbnail(for photo: AskQuestionPhoto) async -> CGImage?
}

// MARK: - Defaults

nonisolated extension AskDomain {
    /// `.thread`: the thread is kept on disk and restored at launch.
    public var persistence: AskPersistence { .thread }
    /// `AskQuestionKind.default`: lookup, count, pick, every match, yes or no,
    /// and other.
    public var questionKinds: [AskQuestionKind] { AskQuestionKind.default }
    /// 45 seconds. Measured, Private Cloud Compute takes 5 to 20 s to its first
    /// word, and a pairing question answered on device takes about 13 s, so
    /// 45 s clears the slow end of both without holding a wedged turn forever.
    /// A grounded retry or a hand-down runs on what is left of it. A domain
    /// whose tools wait on the network sets a longer one.
    public var turnDeadline: Duration { .seconds(45) }
    /// False: the composer has no photo button.
    public var acceptsPhotoAttachments: Bool { false }
    /// `.retrieval`: an answer with no retrieval behind it is never shown,
    /// and the app searches for a model that didn't (house rule 2).
    public var grounding: AskGroundingPolicy { .retrieval }
    /// `.full`: the model says what kind of question it was and chooses the
    /// tiles.
    public var replyShape: AskReplyShape { .full }
    /// Follows `grounding`. `.ownedLibrary` for a domain that retrieves: an
    /// empty library means there is nothing to ask about, and the starters
    /// need a model. `.openSubject` for one that doesn't: the ready first
    /// screen whatever the overview counts.
    public var firstScreenPolicy: AskFirstScreenPolicy {
        grounding == .retrieval ? .ownedLibrary : .openSubject
    }

    /// 40 rows on Private Cloud Compute and 12 on device. Forty rows are a few
    /// thousand tokens of Private Cloud Compute's 32,768-token window. On
    /// device, a session's fixed cost measured about 3,560 of its 8,192 tokens
    /// before any tool runs, and twelve rows keep a follow-up at its worst to
    /// about 1,800 tokens, which the on-device rollover allows for.
    public func rowLimit(for tier: AskTier) -> Int {
        switch tier {
        case .privateCloud: 40
        case .onDevice: 12
        }
    }

    /// 8 turns on Private Cloud Compute, whose window is four times the
    /// device's, and 3 on device. Measured on device, three turns ended at
    /// 4,272, 5,061 and 5,908 of the 8,192-token window, and after the third,
    /// one more worst-case turn would pass the on-device rollover's 85%
    /// ceiling anyway. A session that reports its usage rolls over sooner when
    /// its window fills; for one that doesn't (`AskSession.usage()`), the turn
    /// limit is the whole budget.
    public func maxTurns(for tier: AskTier) -> Int {
        switch tier {
        case .privateCloud: 8
        case .onDevice: 3
        }
    }

    /// `.empty`: nothing counted, for a domain whose subject isn't rows the
    /// reader keeps.
    public func overview() async -> AskOverview { .empty }

    /// No lines of the domain's own between the prefix and the question.
    public func promptLines(question: String, overview: AskOverview) async -> [String] { [] }

    /// No words of the domain's own ahead of the lines.
    public var promptPrefix: String { "" }

    /// One sentence naming no tool, since the planner has none.
    public var searchPlanInstructions: String {
        "Choose the search that would find what the question is about."
    }

    /// No starters, and so no coaching chips.
    public func starters(overview: AskOverview, window: Int) -> [AskStarter] { [] }

    /// What the answer showed, or failing that what its prose named.
    public func referent(from answer: AskAnswer<Row>) -> [String] {
        answer.tiles.isEmpty ? answer.mentioned.map(\.displayTitle) : answer.tiles.map(\.displayTitle)
    }

    /// Nil: the wait row keeps its default phrase.
    public func phrase(for activity: AskActivity) -> String? { nil }

    /// Nil: the evidence line names the count alone.
    public func evidenceScope(from answer: AskAnswer<Row>) -> String? { nil }

    /// `.counted`: AskKit's "From N items" under an answer with rows behind
    /// it, and "Not from this app's data" under one nothing grounded.
    public func evidence(for answer: AskAnswer<Row>) -> AskEvidencePresentation { .counted }

    /// Nil: no basis line.
    public func basis(for answer: AskAnswer<Row>) -> String? { nil }

    /// None: no answer offers "Another pick".
    public var rerollableKinds: Set<AskQuestionKind> { [] }

    /// Whether the answer's kind is in `rerollableKinds`.
    public func isRerollable(_ answer: AskAnswer<Row>, question: String) -> Bool {
        answer.questionKind.map { rerollableKinds.contains($0) } ?? false
    }

    /// Throws `AskProposalFailure` with no line, so the card reads the generic
    /// failure rather than a success nothing performed.
    public func perform(_ proposal: AskProposal) async throws -> String? {
        throw AskProposalFailure()
    }

    /// Nil: every question goes to a model.
    public func deterministicAnswer(for question: String) async -> AskAnswer<Row>? { nil }

    /// False, matching the default `deterministicAnswer(for:)`.
    ///
    /// A domain overriding `deterministicAnswer(for:)` overrides this too: one
    /// line, and without it the protocol can't tell "not implemented" from
    /// "implemented and returned nil", which
    /// `firstScreenPolicy.answersWithoutModel` needs to know when the engine is
    /// built rather than at the reader's first tap.
    public var implementsDeterministicAnswer: Bool { false }

    /// Nil: the first answer stands.
    public func refine(
        _ answer: AskAnswer<Row>,
        question: String,
        tier: AskTier,
        session: AskSessionBox
    ) async throws -> AskAnswer<Row>? {
        nil
    }

    /// Nil: a glyph in the thumbnail's place.
    public func photoThumbnail(for photo: AskQuestionPhoto) async -> CGImage? { nil }

    /// Nil: a scoped question goes as it would unscoped.
    public func scopeLine(for scope: String) -> String? { nil }

    /// Normalize the word the model claimed (`AskReplySnapshot.questionKind`)
    /// against what this domain actually asks, into its kind. A kind outside
    /// the domain's list is `other`: the schema's vocabulary is shared by
    /// every host, so an answer can claim `totalValue` in a domain that has
    /// nothing with a value.
    ///
    /// **Except a superlative, for a domain that asks in picks.** A domain
    /// listing `pick` without `superlative` gets its superlatives as picks:
    /// mapped to `other`, "my oldest record" would lose whatever the domain
    /// does with a pick.
    func normalizedKind(_ raw: String?) -> AskQuestionKind? {
        guard let raw, !raw.isEmpty else { return nil }
        let kind = AskQuestionKind(rawValue: raw)
        if questionKinds.contains(kind) { return kind }
        if kind == .superlative, questionKinds.contains(.pick) { return .pick }
        return .other
    }
}

nonisolated extension AskDomain where SearchArguments == AskNoSearchArguments {
    /// Throws `AskError.ungrounded`: a domain with no search has nothing for
    /// the grounded retry to read. The retry, which only `.retrieval` has,
    /// reaches it after a first answer that called no tool, and that answer
    /// fails as ungrounded, with coaching, rather than standing on nothing
    /// (house rule 2). A domain whose tools ground every first answer, or
    /// whose `grounding` is another policy, never reaches it.
    public func search(_ arguments: AskNoSearchArguments, context: AskToolContext<Row>) async throws -> String {
        throw AskError.ungrounded
    }
}

#endif
