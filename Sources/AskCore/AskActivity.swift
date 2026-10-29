import Foundation

/// What a turn is actually doing while the reader waits.
///
/// The stretch before the first word of prose is tool calls and reasoning, and
/// on Private Cloud Compute it is the longest part of a turn. One fixed line,
/// such as "Looking through your collection…", would be true and say nothing,
/// and say it for just as long whether the model read four rows or four
/// hundred.
///
/// These are the events the tools really raise, reported as they happen. No
/// timers, no invented stages, nothing added to the wait to have something to
/// show. A tool call runs *between* stream snapshots, so nothing else can know
/// about it: the tools report, and the relay carries it to whoever is drawing
/// the wait.
///
/// `scope` is what the lookup is about (a category, a shelf) as the domain
/// names it, or nil where the lookup takes in everything. The reader sees it:
/// the domain turns an activity into the phrase on the wait row
/// (`AskDomain.phrase(for:)`), and AskUI's own fallbacks ("Reading …",
/// "Searching your …") set `scope` into a sentence. So it is a noun in the
/// host's own words and language, which a translation of those sentences
/// quotes as it is and cannot inflect.
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskActivity: Sendable, Equatable {
    /// A retrieval has started.
    case searching(scope: String?)
    /// It came back: `shown` rows handed to the model out of `total` matches,
    /// before the row budget capped them.
    case reading(shown: Int, total: Int, scope: String?)
    /// Something only this domain does. The payload is a key the domain's
    /// `phrase(for:)` recognizes, never text for the screen. AskUI also sets
    /// `.custom(AskActivity.refiningKey)` while a domain's refine pass asks
    /// the model (`AskTurnEvent.refining`).
    case custom(String)
    /// The turn threw away what it had and started over: the model answered
    /// without reading anything and the app is searching for it, the tier
    /// serving the turn went out and the one below is taking the question, or
    /// a follow-up outgrew its conversation's window and is asked again on a
    /// fresh session. Whatever prose the abandoned attempt had drawn is
    /// cleared (`AskTurnEvent.restarted` says why).
    ///
    /// No tool raises it: the store sets it when the engine reports
    /// `AskTurnEvent.restarted` between two attempts. The only case that
    /// moves the wait backwards.
    case restarted(AskTier)

    /// The key AskUI records a domain's refine pass under while it asks the
    /// model (`AskTurnEvent.refining`): the turn's `activity` reads
    /// `.custom(AskActivity.refiningKey)`. A domain's `phrase(for:)` matches
    /// `.custom(AskActivity.refiningKey)` to word it, for a host that shows
    /// `AskTurn.activity` once the prose has begun: the pass runs after the
    /// default wait row has given way to the prose.
    public static let refiningKey = "refining"
}

/// The tools' live commentary, relayed to whoever is drawing the wait.
///
/// **A stable object with a swappable sink, not a closure on the tool.** The
/// tool set is built once per session and must stay identical across a
/// conversation's turns, or the session's cached prefix is thrown away
/// (house rule 6), so a tool can't be rebuilt per turn to capture this turn's
/// listener. The session holds one relay for life; each turn points it at its
/// own sink and takes it back at the end, so a finished turn can never write
/// into the next one's wait row.
///
/// The engine awaits `end()` rather than firing it into an unstructured
/// `Task`: fired that way, a slow last report from the turn just finished
/// could land in the next turn's row.
public actor AskActivityRelay {
    private var sink: (@Sendable (AskActivity) async -> Void)?

    /// A relay pointed at nothing yet. One per session, handed to the tools in
    /// `AskToolContext`; the engine points it at each turn's listener.
    public init() {}

    /// Point the relay at a listener, or at nothing (nil), where reports go
    /// nowhere.
    ///
    /// The engine points it at the turn's events before each answer it
    /// streams and before the grounded retry's search, and a tool that called
    /// it would take the wait row's reports. SPI (`AskKitInternal`), for a
    /// host's tests that listen to what its tools report.
    @_spi(AskKitInternal) public func begin(_ sink: (@Sendable (AskActivity) async -> Void)?) {
        self.sink = sink
    }

    /// Point the relay at nothing once that answer or search ends: a report
    /// after this goes nowhere.
    func end() {
        sink = nil
    }

    /// Tell the wait row what the calling tool is doing; the domain words it
    /// (`AskDomain.phrase(for:)`). It goes nowhere while no turn is
    /// listening.
    ///
    /// A tool hands its phrase back from `AskToolContext.withToolCall(_:_:)`'s
    /// body rather than reporting here itself: `withToolCall` reports it once
    /// the call has finished, and a report made while the call is still open
    /// is cleared at once (`AskToolContext` says why).
    public func report(_ activity: AskActivity) async {
        await sink?(activity)
    }
}
