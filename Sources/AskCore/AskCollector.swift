#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Synchronization

/// What the collector tells whoever is drawing the wait. SPI
/// (`AskKitInternal`) with `AskCollector.setObserver(_:)`, its only way out.
@_spi(AskKitInternal) nonisolated public enum AskCollectorEvent: Sendable, Equatable {
    /// A tool was called and says what it is doing.
    case tool(AskActivity)
    /// The last outstanding tool returned, and the model is composing again.
    case toolsIdle
}

/// The rows a thread's tools have read, and the tool traffic behind them.
///
/// **Two row sets, not one.** With one cumulative set for the tile chooser, a
/// follow-up would show the previous turn's rows, a `showsEveryMatch` answer
/// would show every row since the first turn, and past the cap a later turn
/// would record nothing at all.
///
/// - `turnRows` is what THIS turn read, in reading order: the tiles' pool and
///   the wait's count. A row an earlier turn already read is recorded again when
///   this turn reads it: the turn showed it to the model, so it is this turn's
///   evidence too.
/// - `rows` is what the THREAD has read, first-seen order: the grounding set,
///   and what rides into the thread on disk.
///
/// The collector is built once per session and the tools are bound to it for
/// the session's life (the tool set must stay identical across turns or the KV
/// cache goes), so `beginTurn()` resets rather than replaces. `AskToolContext`
/// says in what order a tool reports here and to the relay, and its
/// `withToolCall(_:_:)` keeps that order.
public actor AskCollector<Row: AskRow> {
    /// How many rows one turn may record: every row it put in front of the
    /// model, not the far smaller number it will show (`AskAnswer.maxTiles`).
    ///
    /// Two numbers, because a pairing question reads more than it shows.
    /// "What goes with this record?" reads the record, then others of its
    /// genre, then others by its players, then others on its label. With one
    /// 24-row budget, the record and 23 of its genre would fill it before the
    /// rest were fetched, and the answer would name a pick that can't resolve
    /// to a tile, because the collector had stopped recording.
    public static var maxTurnRows: Int { 80 }

    /// The thread's ceiling. The cumulative set only has to answer "did this
    /// turn name something the thread has read", and every row of it rides into
    /// the thread on disk, so it is bounded, generously, rather than left to
    /// grow with the conversation.
    public static var maxThreadRows: Int { 200 }

    private var seen = Set<Row.ID>()
    /// What the thread has read on this session, in first-seen order, up to
    /// `maxThreadRows`. A fresh session starts a new collector.
    public private(set) var rows: [Row] = []

    private var seenThisTurn = Set<Row.ID>()
    /// What this turn has read, in reading order, up to `maxTurnRows`.
    public private(set) var turnRows: [Row] = []

    /// The most a turn's payload may weigh. It rides into the thread on disk
    /// with its answer, for up to fifty turns, so it is what a card needs to
    /// draw, never a second copy of the rows.
    public static var maxPayloadBytes: Int { 16_384 }

    /// What a tool also knows about this turn that a list of rows can't carry
    /// (a breakdown, a span of years, a series), encoded by the domain.
    /// Cleared when a turn begins; handed out on the answer.
    public private(set) var turnPayload: Data?

    /// What this turn offers to do, if anything: the first proposal a tool
    /// recorded. Cleared when a turn begins; handed out on the answer.
    public private(set) var turnProposal: AskProposal?

    /// Every tool call reported here, across the session's turns: one of the
    /// two counts a turn's grounding is judged by, beside the session
    /// transcript's own (`AskSession.toolCallCount()`).
    public private(set) var toolCallCount = 0
    /// Tools called but not yet returned, so `toolsIdle` fires when the last
    /// one does rather than after each.
    private var toolsInFlight = 0

    /// Who is watching this turn.
    ///
    /// A `Mutex` rather than actor state so a turn can set and clear it
    /// synchronously from a `defer`: the tools are bound to this collector once
    /// per session and the session outlives the turn, but the listener does not.
    private let observer = Mutex<(@Sendable (AskCollectorEvent) -> Void)?>(nil)

    /// An empty collector. The engine builds one per session and hands it to
    /// the tools in `AskToolContext`.
    public init() {}

    /// Watch this turn's tool calls and rows; `nil` stops watching.
    ///
    /// The engine sets it for each turn, and a tool that set it would take the
    /// wait row's events. SPI (`AskKitInternal`), for a host's tests of its
    /// own tools.
    @_spi(AskKitInternal) public nonisolated func setObserver(_ observer: (@Sendable (AskCollectorEvent) -> Void)?) {
        self.observer.withLock { $0 = observer }
    }

    /// A turn is starting on this thread: its own row set begins empty.
    ///
    /// The engine calls it as each turn starts, and a tool that called it
    /// would wipe the rows its turn had read. SPI (`AskKitInternal`), for a
    /// host's tests that run its tools across turns.
    @_spi(AskKitInternal) public func beginTurn() {
        turnRows = []
        seenThisTurn = []
        toolsInFlight = 0
        turnPayload = nil
        turnProposal = nil
    }

    /// Record this turn's payload, replacing any earlier one. JSON, so
    /// `AskAnswer.payload(as:)` can read it back.
    ///
    /// **A tool adding to what another recorded uses `mergePayload(as:_:)`,
    /// not this.** Reading `turnPayload` in one call and recording here in the
    /// next lets another tool record in between, and this record then drops
    /// its half.
    ///
    /// Refused over `maxPayloadBytes`, and the refusal is returned: a card
    /// missing is a smaller failure than a thread file that grows by megabytes
    /// a turn.
    @discardableResult
    public func record(payload: Data) -> Bool {
        guard payload.count <= Self.maxPayloadBytes else { return false }
        turnPayload = payload
        return true
    }

    /// Add to this turn's payload, keeping what another tool put there: the
    /// payload decoded as `Value` (nil while the turn has none) is handed to
    /// `combine`, and what `combine` leaves is recorded in its place. Leaving
    /// nil clears it.
    ///
    /// **One actor turn from read to record, which is the whole point.** A
    /// tool that reads `turnPayload` in one call and records the combined
    /// payload in the next can interleave with another tool doing the same,
    /// and the later record drops the other's half: two summary tools running
    /// at once lost one's breakdown in 16 of 50 runs that way. `combine` is
    /// synchronous so that nothing can suspend between the read and the
    /// record, and `@Sendable` because it runs on the collector: it carries
    /// what the tool read in by value, and hands nothing back but the payload.
    ///
    /// Refused (`false`, and the payload exactly as it was) when what is there
    /// doesn't decode as `Value`, since `combine` could only drop what it
    /// can't read; when the result doesn't encode; and over `maxPayloadBytes`,
    /// as `record(payload:)` is. A `combine` that throws records nothing, and
    /// the error reaches the caller.
    ///
    /// The payload is decoded and encoded here, on the collector, so `Value`'s
    /// `Codable` conformance has to be usable off the main actor: a type in a
    /// package with MainActor default isolation is declared `nonisolated`, as
    /// a tool encoding it for itself already needs.
    @discardableResult
    public func mergePayload<Value: Codable & Sendable>(
        as type: Value.Type,
        _ combine: @Sendable (inout Value?) throws -> Void
    ) rethrows -> Bool {
        var value: Value?
        if let turnPayload {
            guard let recorded = try? JSONDecoder().decode(type, from: turnPayload) else { return false }
            value = recorded
        }
        try combine(&value)
        guard let value else {
            turnPayload = nil
            return true
        }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return record(payload: data)
    }

    /// Record what this turn offers to do. **Nothing is done here**: the
    /// answer carries the proposal to a card, and only the reader's tap reaches
    /// `AskDomain.perform(_:)`. The tool then returns `AskProposal.modelReceipt`.
    ///
    /// One card to an answer, so the first proposal in a turn is kept and a
    /// second is refused, as is one whose payload is over
    /// `AskProposal.maxPayloadBytes`. The refusal is returned, for the tool to
    /// tell the model.
    @discardableResult
    public func record(proposal: AskProposal) -> Bool {
        guard turnProposal == nil, proposal.payload.count <= AskProposal.maxPayloadBytes else { return false }
        turnProposal = proposal
        return true
    }

    /// A tool was called. `activity`, when given, is what the wait row shows
    /// for it.
    ///
    /// What `AskToolContext.withToolCall(_:_:)` calls as a call starts, which
    /// is how a host's tool reports one: it pairs this with
    /// `noteToolFinished()` in the order `AskToolContext` states. SPI
    /// (`AskKitInternal`), for a host's tests of its collector.
    @_spi(AskKitInternal) public func noteToolCall(_ activity: AskActivity? = nil) {
        toolCallCount += 1
        toolsInFlight += 1
        if let activity { observer.withLock { $0 }?(.tool(activity)) }
    }

    /// A tool returned. When it was the last one outstanding, the wait row goes
    /// back to "Thinking…" while the model composes.
    ///
    /// `AskToolContext.withToolCall(_:_:)` calls this once the work ends,
    /// however it ends, and before it reports to the relay. SPI
    /// (`AskKitInternal`), for a host's tests of its collector.
    @_spi(AskKitInternal) public func noteToolFinished() {
        toolsInFlight = max(0, toolsInFlight - 1)
        guard toolsInFlight == 0 else { return }
        observer.withLock { $0 }?(.toolsIdle)
    }

    /// Record the rows a tool showed the model. An answer's tiles resolve only
    /// against recorded rows, so a row the model saw that nobody recorded can
    /// never become a tile.
    public func record(rows newRows: [Row]) {
        for row in newRows {
            if turnRows.count < Self.maxTurnRows, seenThisTurn.insert(row.id).inserted {
                turnRows.append(row)
            }
            if rows.count < Self.maxThreadRows, seen.insert(row.id).inserted {
                rows.append(row)
            }
        }
    }

    /// The rows behind an answer: this turn's, or, for a follow-up the model
    /// answered from rows an earlier turn read, everything the thread has read.
    public var groundingRows: [Row] {
        turnRows.isEmpty ? rows : turnRows
    }
}

#endif
