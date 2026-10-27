#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Synchronization
import Testing

@_spi(AskKitInternal) @testable import AskCore

/// `AskToolContext.withToolCall(_:_:)`: the call noted, the finish however the
/// body ends, and the phrase it hands back reported only after that finish.
@Suite(.timeLimit(.minutes(1))) struct AskToolCallTests {

    /// What the wait row hears from either route, in one sequence, so the
    /// order between the collector's events and the relay's is what is checked.
    nonisolated enum Heard: Sendable, Equatable {
        case collector(AskCollectorEvent)
        case relay(AskActivity)
    }

    /// What was heard, in the order it arrived, from whichever executor it
    /// came on.
    nonisolated final class Log: Sendable {
        private let heard = Mutex<[Heard]>([])
        func append(_ event: Heard) { heard.withLock { $0.append(event) } }
        var all: [Heard] { heard.withLock { $0 } }
    }

    nonisolated struct Boom: Error, Equatable {}

    /// A context whose collector and relay both write into one log, as the
    /// engine points them at one turn's events.
    private func listening() async -> (AskToolContext<FakeRow>, Log) {
        let collector = AskCollector<FakeRow>()
        let relay = AskActivityRelay()
        let heard = Log()
        collector.setObserver { event in heard.append(.collector(event)) }
        await relay.begin { activity in heard.append(.relay(activity)) }
        let context = AskToolContext(
            collector: collector, relay: relay,
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        return (context, heard)
    }

    @Test func aNegativeRowLimitReadsAsNone() {
        // A tool shows `prefix(context.rowLimit)` of what it found, as the
        // README's does, and `prefix` traps on a negative length.
        let context = AskToolContext(
            collector: AskCollector<FakeRow>(), relay: AskActivityRelay(),
            rowLimit: -3, tier: .onDevice, isConversation: true
        )
        #expect(context.rowLimit == 0)
        #expect(FakeRow.six.prefix(context.rowLimit).isEmpty)
    }

    @Test func thePhraseIsReportedAfterTheFinish() async {
        // Reported while the call is open, the phrase would be cleared by the
        // idle signal one await later (`AskToolContext`).
        let (context, heard) = await listening()
        let reply = await context.withToolCall(.searching(scope: "records")) { collector in
            await collector.record(rows: FakeRow.six)
            return ("six rows", report: .reading(shown: 6, total: 9, scope: "records"))
        }
        #expect(reply == "six rows")
        #expect(heard.all == [
            .collector(.tool(.searching(scope: "records"))),
            .collector(.toolsIdle),
            .relay(.reading(shown: 6, total: 9, scope: "records"))
        ])
        #expect(await context.collector.toolCallCount == 1)
        #expect(await context.collector.turnRows == FakeRow.six)
    }

    @Test func aBodyThatThrowsStillFinishesTheCall() async {
        let (context, heard) = await listening()
        await #expect(throws: Boom.self) {
            try await context.withToolCall(.searching(scope: nil)) { collector -> (String, report: AskActivity?) in
                await collector.record(rows: [FakeRow("Rumours")])
                throw Boom()
            }
        }
        // Finished, so idle; nothing handed back, so nothing reported.
        #expect(heard.all == [.collector(.tool(.searching(scope: nil))), .collector(.toolsIdle)])
        #expect(await context.collector.turnRows == [FakeRow("Rumours")])

        // And the count is back at zero: the next call idles when it finishes.
        await context.withToolCall { _ in ((), report: nil) }
        #expect(heard.all.last == .collector(.toolsIdle))
        #expect(heard.all.count == 3)
    }

    @Test func aThrowFinishesOnlyItsOwnCall() async {
        // Another tool still open: the throwing call takes its own count back
        // and no more, so idle waits for the other, then fires.
        let (context, heard) = await listening()
        await context.collector.noteToolCall(.searching(scope: "books"))
        await #expect(throws: Boom.self) {
            try await context.withToolCall(.searching(scope: "records")) { _ -> (Int, report: AskActivity?) in
                throw Boom()
            }
        }
        #expect(!heard.all.contains(.collector(.toolsIdle)))
        await context.collector.noteToolFinished()
        #expect(heard.all == [
            .collector(.tool(.searching(scope: "books"))),
            .collector(.tool(.searching(scope: "records"))),
            .collector(.toolsIdle)
        ])
    }

    @Test func noPhraseHandedBackReportsNothing() async {
        let (context, heard) = await listening()
        let count = await context.withToolCall { collector in
            await collector.record(rows: FakeRow.six)
            return (await collector.turnRows.count, report: nil)
        }
        #expect(count == 6)
        // No activity given, so the call is counted without a phrase of its own.
        #expect(heard.all == [.collector(.toolsIdle)])
        #expect(await context.collector.toolCallCount == 1)
    }

    @Test func theBodyIsHandedTheContextsCollector() async {
        let (context, _) = await listening()
        let handed = await context.withToolCall { collector in (collector, report: nil) }
        #expect(handed === context.collector)
    }

    // MARK: Where the body runs

    @MainActor
    @Test func theBodyRunsOnAMainActorCallersActor() async {
        let (context, _) = await listening()
        let isolation = await context.withToolCall { _ in (#isolation, report: nil) }
        #expect(isolation === MainActor.shared)
    }

    @Test func theBodyRunsOnAnActorCallersActor() async {
        let (context, _) = await listening()
        let caller = ToolCallingActor()
        let isolation = await caller.isolationInsideACall(context)
        #expect(isolation === caller)
    }

    @Test func theBodyOfAConcurrentToolRunsOffEveryActor() async {
        // A tool's `@concurrent` call: the body stays off the main actor and
        // off the collector, rather than hopping to either for its work.
        let (context, _) = await listening()
        #expect(await isolationInsideAConcurrentCall(context) == nil)
    }
}

/// A caller with an actor of its own, for the body to run on.
private actor ToolCallingActor {
    func isolationInsideACall(_ context: AskToolContext<FakeRow>) async -> (any Actor)? {
        await context.withToolCall { _ in (#isolation, report: nil) }
    }
}

/// A caller shaped like a tool's `@concurrent` call.
@concurrent private func isolationInsideAConcurrentCall(_ context: AskToolContext<FakeRow>) async -> (any Actor)? {
    await context.withToolCall { _ in (#isolation, report: nil) }
}

#endif
