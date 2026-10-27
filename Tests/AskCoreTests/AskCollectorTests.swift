#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Synchronization
import Testing

@_spi(AskKitInternal) @testable import AskCore

@Suite(.timeLimit(.minutes(1))) struct AskCollectorTests {

    @Test func recordsRowsIntoBothSets() async {
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: FakeRow.six)
        #expect(await collector.rows.count == 6)
        #expect(await collector.turnRows.count == 6)
    }

    @Test func beginTurnClearsOnlyTheTurnsRows() async {
        // The thread set is the grounding; the turn set is the tiles' pool. As
        // one set, a follow-up would show the previous turn's rows.
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: FakeRow.six)
        await collector.beginTurn()
        #expect(await collector.turnRows.isEmpty)
        #expect(await collector.rows.count == 6)
    }

    @Test func aRowAnEarlierTurnReadIsRecordedAgainThisTurn() async {
        // The turn showed it to the model, so it is this turn's evidence too.
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: [FakeRow("Rumours")])
        await collector.beginTurn()
        await collector.record(rows: [FakeRow("Rumours")])
        #expect(await collector.turnRows.count == 1)
        #expect(await collector.rows.count == 1)
    }

    @Test func rowsAreRecordedOncePerTurn() async {
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: [FakeRow("Rumours"), FakeRow("Rumours")])
        #expect(await collector.turnRows.count == 1)
    }

    @Test func theTurnBudgetIsFarLargerThanTheTileBudget() async {
        // With one 24-row budget, one record and then 23 more would fill it
        // before the books were fetched, and the answer would name a book that
        // can't resolve to a tile.
        #expect(AskCollector<FakeRow>.maxTurnRows > AskAnswer<FakeRow>.maxTiles)
    }

    @Test func theTurnSetIsCapped() async {
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: (0..<200).map { FakeRow("Row \($0)") })
        #expect(await collector.turnRows.count == AskCollector<FakeRow>.maxTurnRows)
    }

    @Test func theThreadSetIsCapped() async {
        let collector = AskCollector<FakeRow>()
        for turn in 0..<10 {
            await collector.beginTurn()
            await collector.record(rows: (0..<50).map { FakeRow("Row \(turn)-\($0)") })
        }
        #expect(await collector.rows.count == AskCollector<FakeRow>.maxThreadRows)
    }

    @Test func groundingRowsFallBackToTheThreadWhenTheTurnReadNothing() async {
        // A follow-up the model answered from rows an earlier turn read.
        let collector = AskCollector<FakeRow>()
        await collector.record(rows: FakeRow.six)
        await collector.beginTurn()
        #expect(await collector.groundingRows.count == 6)
    }

    @Test func toolCallsAreCounted() async {
        let collector = AskCollector<FakeRow>()
        await collector.noteToolCall(.searching(scope: "records"))
        await collector.noteToolCall(.searching(scope: nil))
        #expect(await collector.toolCallCount == 2)
    }

    @Test func theObserverHearsEachToolCall() async {
        let collector = AskCollector<FakeRow>()
        let seen = Mutex<[AskCollectorEvent]>([])
        collector.setObserver { event in seen.withLock { $0.append(event) } }
        await collector.noteToolCall(.searching(scope: "records"))
        #expect(seen.withLock { $0 } == [.tool(.searching(scope: "records"))])
    }

    @Test func idleFiresWhenTheLastToolReturnsNotAfterEach() async {
        let collector = AskCollector<FakeRow>()
        let seen = Mutex<[AskCollectorEvent]>([])
        collector.setObserver { event in seen.withLock { $0.append(event) } }
        await collector.noteToolCall(.searching(scope: "a"))
        await collector.noteToolCall(.searching(scope: "b"))
        await collector.noteToolFinished()
        #expect(!seen.withLock { $0 }.contains(.toolsIdle))
        await collector.noteToolFinished()
        #expect(seen.withLock { $0 }.contains(.toolsIdle))
    }

    @Test func clearingTheObserverStopsTheReports() async {
        let collector = AskCollector<FakeRow>()
        let seen = Mutex(0)
        collector.setObserver { _ in seen.withLock { $0 += 1 } }
        collector.setObserver(nil)
        await collector.noteToolCall(.searching(scope: nil))
        #expect(seen.withLock { $0 } == 0)
    }

    @Test func beginTurnResetsToolsInFlight() async {
        // A turn abandoned mid-tool must not leave the next turn's idle event
        // waiting on a call that will never return.
        let collector = AskCollector<FakeRow>()
        await collector.noteToolCall(.searching(scope: nil))
        await collector.beginTurn()
        let seen = Mutex<[AskCollectorEvent]>([])
        collector.setObserver { event in seen.withLock { $0.append(event) } }
        await collector.noteToolCall(.searching(scope: nil))
        await collector.noteToolFinished()
        #expect(seen.withLock { $0 }.contains(.toolsIdle))
    }
}

/// A payload two tools build together, read and recorded in one actor turn
/// (`mergePayload(as:_:)`).
///
/// The obvious shape, reading `turnPayload` in one call and recording in the
/// next, lets two tools interleave and the later record drop the other's
/// half: two summary tools running at once lost one's breakdown in 16 of 50
/// runs that way.
@Suite(.timeLimit(.minutes(1))) struct AskPayloadMergeTests {

    /// `nonisolated`, as a host's envelope has to be in a package with
    /// MainActor default isolation: `mergePayload` decodes it on the collector.
    nonisolated struct Bars: Codable, Equatable, Sendable {
        var groups: [String]
    }

    /// Another tool's envelope, which `mergePayload(as: Bars.self)` cannot
    /// read.
    nonisolated struct YearSpan: Codable, Equatable, Sendable {
        let oldest: Int
    }

    /// What a `merge` closure throws when it gives up halfway. Built inside
    /// the closure, which runs on the collector, so it cannot take the suite's
    /// isolation.
    nonisolated struct Refusal: Error {}

    private func bars(in collector: AskCollector<FakeRow>) async -> Bars? {
        guard let data = await collector.turnPayload else { return nil }
        return try? JSONDecoder().decode(Bars.self, from: data)
    }

    @Test func manyToolsMergingAtOnceLoseNothing() async {
        let collector = AskCollector<FakeRow>()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    await collector.mergePayload(as: Bars.self) { bars in
                        bars = Bars(groups: (bars?.groups ?? []) + ["group \(index)"])
                    }
                }
            }
        }
        let merged = await bars(in: collector)?.groups ?? []
        #expect(merged.count == 64, "every merge kept every merge before it")
        #expect(Set(merged).count == 64)
    }

    @Test func aMergeKeepsWhatAnotherToolRecorded() async throws {
        let collector = AskCollector<FakeRow>()
        await collector.record(payload: try JSONEncoder().encode(Bars(groups: ["decades"])))
        #expect(await collector.mergePayload(as: Bars.self) { $0?.groups.append("genres") })
        #expect(await bars(in: collector)?.groups == ["decades", "genres"])
    }

    @Test func aMergeOnATurnWithNoPayloadStartsFromNothing() async {
        let collector = AskCollector<FakeRow>()
        let kept = await collector.mergePayload(as: Bars.self) { bars in
            bars = Bars(groups: [bars == nil ? "from nothing" : "from something"])
        }
        #expect(kept)
        #expect(await bars(in: collector)?.groups == ["from nothing"])
    }

    @Test func aPayloadOfAnotherShapeIsRefusedNotReplaced() async throws {
        // `mergePayload` promises to keep what another tool put there, and it
        // cannot keep what it cannot read. Replacing it would be the lost half
        // again, by another route: decoding a payload of another shape as
        // nothing, and writing over it.
        let collector = AskCollector<FakeRow>()
        let span = try JSONEncoder().encode(YearSpan(oldest: 1959))
        await collector.record(payload: span)
        let ran = await collector.mergePayload(as: Bars.self) { bars in
            bars = Bars(groups: ["genres"])
        }
        #expect(!ran)
        #expect(await collector.turnPayload == span, "the other envelope is exactly as it was")
    }

    @Test func anOversizeResultIsRefusedAndTheEarlierPayloadStands() async throws {
        let collector = AskCollector<FakeRow>()
        let small = try JSONEncoder().encode(Bars(groups: ["decades"]))
        await collector.record(payload: small)
        let oversize = String(repeating: "x", count: AskCollector<FakeRow>.maxPayloadBytes)
        let kept = await collector.mergePayload(as: Bars.self) { bars in
            bars?.groups.append(oversize)
        }
        #expect(!kept)
        #expect(await collector.turnPayload == small, "refused whole, like an oversize record")
    }

    @Test func aMergeThatThrowsRecordsNothing() async throws {
        let collector = AskCollector<FakeRow>()
        let small = try JSONEncoder().encode(Bars(groups: ["decades"]))
        await collector.record(payload: small)
        await #expect(throws: Refusal.self) {
            try await collector.mergePayload(as: Bars.self) { bars in
                bars?.groups.append("half")
                throw Refusal()
            }
        }
        #expect(await collector.turnPayload == small, "the half-made merge never reached the payload")
    }

    @Test func leavingNothingClearsThePayload() async throws {
        let collector = AskCollector<FakeRow>()
        await collector.record(payload: try JSONEncoder().encode(Bars(groups: ["decades"])))
        #expect(await collector.mergePayload(as: Bars.self) { $0 = nil })
        #expect(await collector.turnPayload == nil)
    }

    @Test func aMergedPayloadDoesNotOutliveItsTurn() async {
        let collector = AskCollector<FakeRow>()
        await collector.mergePayload(as: Bars.self) { $0 = Bars(groups: ["decades"]) }
        await collector.beginTurn()
        let kept = await collector.mergePayload(as: Bars.self) { bars in
            bars = Bars(groups: [bars == nil ? "a new turn" : "the last turn's"])
        }
        #expect(kept)
        #expect(await bars(in: collector)?.groups == ["a new turn"])
    }
}

@Suite(.timeLimit(.minutes(1))) struct AskActivityRelayTests {

    @Test func reportsReachTheTurnsSink() async {
        let relay = AskActivityRelay()
        let seen = Mutex<[AskActivity]>([])
        await relay.begin { activity in seen.withLock { $0.append(activity) } }
        await relay.report(.searching(scope: "records"))
        #expect(seen.withLock { $0 } == [.searching(scope: "records")])
    }

    @Test func aFinishedTurnCannotWriteIntoTheNextOnesRow() async {
        // `end()` is awaited rather than fired into an unstructured `Task`,
        // which would let a slow last report land in the next turn's wait row.
        let relay = AskActivityRelay()
        let seen = Mutex(0)
        await relay.begin { _ in seen.withLock { $0 += 1 } }
        await relay.end()
        await relay.report(.searching(scope: nil))
        #expect(seen.withLock { $0 } == 0)
    }

    @Test func aTurnWithNobodyWatchingDropsItsReports() async {
        let relay = AskActivityRelay()
        await relay.begin(nil)
        await relay.report(.reading(shown: 3, total: 9, scope: nil))
        // No sink, no crash. The engine always points the relay at its turn's
        // listener; nil is for a host's test that listens to nothing.
    }
}

#endif
