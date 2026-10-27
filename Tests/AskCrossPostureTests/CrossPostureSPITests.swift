@_spi(AskKitInternal) import AskCore
import Foundation
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
@_spi(AskKitInternal) import AskUI
import SwiftUI
#endif

#if canImport(FoundationModels) && !os(tvOS)
import Synchronization
#endif

/// The compile contract for AskCore's SPI (`AskKitInternal`): what a host's
/// own tests and live evals reach for, imported the way they import it and
/// called under this target's posture, which is none.
///
/// **A file of its own because SPI is seen per file.** `CrossPostureTests.swift`
/// imports AskCore plainly, so it proves the public API alone builds an app's
/// Ask; this file proves the SPI does not need the package's isolation either.
/// A consumer spells `@_spi(AskKitInternal) import AskCore` in every file that
/// calls one of these, and a plain import elsewhere in the same module does
/// not see them.
///
/// **Every SPI declaration keeps its `nonisolated` spelling**, and a line
/// here fails to compile when one loses it, as `CrossPostureTests` does for
/// the public API.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureSPITests {
    /// What a host's deep-link router clamps and its live eval builds, off any
    /// actor.
    @Test func thePromptsSPIIsUsableWithoutThePosture() {
        #expect(AskPrompt.clampQuestion("  how many?\n") == "how many?")
        #expect(AskPrompt.clampQuestion(String(repeating: "a", count: 600)).count == AskPrompt.maxQuestionLength)
        let prompt = AskPrompt.promptText(prefix: "Rows:\n", lines: ["One row.", ""], question: "how <many>?")
        #expect(prompt == "Rows:\nOne row.\n<user_request>how ‹many›?</user_request>")
    }
}

/// A row as a consumer without the posture declares one.
private struct CrossPostureSPIRow: AskRow {
    let id: String
    var displayTitle: String { id }
}

#if os(iOS) || os(macOS) || os(visionOS)
extension CrossPostureSPITests {
    /// What a host's preview or UI-test launch picks to see its Ask tab around
    /// a fold the device doesn't have: made and compared off any actor.
    @Test func aStandInFoldIsMadeAndComparedWithoutThePosture() {
        #expect(AskSimulatedFold.book() == AskSimulatedFold.book(bend: 0))
        #expect(AskSimulatedFold.book() != AskSimulatedFold.upright())
        #expect(AskSimulatedFold.book(bend: 24) != AskSimulatedFold.book())
    }

    /// And handed to the view the host builds, where a host builds views.
    @MainActor
    @Test func aHostHandsAStandInFoldToItsView() {
        _ = Color.clear.askSimulatedFold(.book())
        _ = Color.clear.askSimulatedFold(nil)
    }
}
#endif

#if canImport(FoundationModels) && !os(tvOS)
extension CrossPostureSPITests {
    /// What a host's tests of its own tools do: watch the collector's events
    /// while a tool runs, then start a fresh turn and run it again.
    @Test func aToolsTestWatchesTheCollectorWithoutThePosture() async {
        let collector = AskCollector<CrossPostureSPIRow>()
        let log = CrossPostureSPILog<AskCollectorEvent>()
        collector.setObserver { event in log.values.withLock { $0.append(event) } }
        defer { collector.setObserver(nil) }

        await collector.noteToolCall(.searching(scope: nil))
        await collector.record(rows: [CrossPostureSPIRow(id: "one")])
        await collector.noteToolFinished()
        #expect(log.values.withLock { $0 } == [.tool(.searching(scope: nil)), .toolsIdle])
        #expect(await collector.turnRows == [CrossPostureSPIRow(id: "one")])

        await collector.beginTurn()
        #expect(await collector.turnRows.isEmpty)
        #expect(await collector.rows == [CrossPostureSPIRow(id: "one")])
    }

    /// What a host's tests of its own tools do to hear a phrase a tool
    /// reports through the relay.
    @Test func aToolsTestListensToTheRelayWithoutThePosture() async {
        let relay = AskActivityRelay()
        let log = CrossPostureSPILog<AskActivity>()
        await relay.begin { activity in log.values.withLock { $0.append(activity) } }

        await relay.report(.reading(shown: 1, total: 2, scope: nil))
        #expect(log.values.withLock { $0 } == [.reading(shown: 1, total: 2, scope: nil)])
    }
}

/// What a test's listener heard, from whichever thread it was called on.
private final class CrossPostureSPILog<Value: Sendable>: Sendable {
    let values = Mutex<[Value]>([])
}
#endif
