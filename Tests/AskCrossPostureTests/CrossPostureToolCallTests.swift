#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import FoundationModels
import Testing

/// `AskToolContext.withToolCall(_:_:)` as a host without the posture calls it:
/// from a tool's plain `call`, which runs off every actor here, and from a
/// main-actor caller whose body touches state that isn't `Sendable`. Built
/// under this target's lack of settings, it fails to compile if the helper or
/// its body loses the isolation it spells.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureToolCallTests {
    @Test func aToolsCallKeepsItsBookkeepingThroughTheHelper() async throws {
        let context = toolCallContext()
        let tool = ToolCallSearch(context: context)
        #expect(try await tool.call(arguments: ToolCallArguments(query: "one")) == "one")
        #expect(await context.collector.rows == [ToolCallRow(id: "one")])
        #expect(await context.collector.toolCallCount == 1)

        // A throw still reaches the tool's caller, after the call is counted.
        await #expect(throws: ToolCallMiss.self) {
            try await tool.call(arguments: ToolCallArguments(query: ""))
        }
        #expect(await context.collector.toolCallCount == 2)
    }

    @MainActor
    @Test func aMainActorCallersBodyRunsThereWithItsOwnState() async {
        let context = toolCallContext()
        let tally = ToolCallTally()
        let isolation = await context.withToolCall(.custom("tallying")) { collector in
            tally.count += 1
            await collector.record(rows: [ToolCallRow(id: "tallied")])
            return (#isolation, report: .custom("tallied"))
        }
        #expect(isolation === MainActor.shared)
        #expect(tally.count == 1)
        #expect(await context.collector.turnRows == [ToolCallRow(id: "tallied")])
    }
}

private func toolCallContext() -> AskToolContext<ToolCallRow> {
    AskToolContext(
        collector: AskCollector(), relay: AskActivityRelay(),
        rowLimit: 12, tier: .onDevice, isConversation: true
    )
}

private struct ToolCallRow: AskRow {
    let id: String
    var displayTitle: String { id }
}

@Generable
private struct ToolCallArguments: Sendable {
    @Guide(description: "Words from the question")
    var query: String
}

private struct ToolCallMiss: Error {}

/// A plain class, so only a body that runs where its caller does can touch it.
private final class ToolCallTally {
    var count = 0
}

/// A tool as a host without the posture writes one: a plain `call`, with no
/// `@concurrent`, whose bookkeeping is the helper's.
private struct ToolCallSearch: Tool {
    let name = "search"
    let description = "Search the rows by words from the question."
    let context: AskToolContext<ToolCallRow>

    func call(arguments: ToolCallArguments) async throws -> String {
        try await context.withToolCall(.searching(scope: nil)) { collector in
            guard !arguments.query.isEmpty else { throw ToolCallMiss() }
            await collector.record(rows: [ToolCallRow(id: arguments.query)])
            return (arguments.query, report: .reading(shown: 1, total: 1, scope: nil))
        }
    }
}

#endif
