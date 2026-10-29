#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels
import Synchronization
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
#endif

/// How the engine runs a turn and where the screen says a question came from,
/// used as a host without the posture uses them: no `swiftSettings`, so
/// nonisolated by default (`CrossPostureTests` says why the target has none).
/// The modes, the origins, and an engine of a host's own told the mode, by the
/// store and through the protocol's defaults.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureTurnModeTests {

    /// The modes, compared and read off any actor, as a host's own engine
    /// reads the one it is asked in: every mode but a one-shot joins the
    /// thread.
    @Test func aTurnModeIsReadWithoutThePosture() {
        let modes: [AskTurnMode] = [.conversation, .reroll, .standalone]
        #expect(modes.map(\.joinsThread) == [true, true, false])
        #expect(AskTurnMode.reroll != .conversation)
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    /// Where a question came from, read off any actor off the turn a host's
    /// view builder is handed. A turn read back from disk keeps no origin,
    /// and reads as typed.
    @Test func anOriginIsReadOffTheTurnWithoutThePosture() {
        let turn = AskTurn<TurnModeRow>(question: "What else should I play?", origin: .reroll)
        #expect(turn.origin == .reroll && turn.origin != .followUp)
        #expect(AskTurn(entry: turn.entry).origin == .typed)
    }

    /// The defaulted `ask`s of an engine of a host's own, asked off any actor
    /// as the store asks them, pass the mode on to the one it writes.
    @Test func aHostsEngineHearsTheModeThroughTheDefaults() async throws {
        let status = await MainActor.run { AskModelStatus() }
        let engine = TurnModeEngine(status: status)
        for try await _ in engine.ask("What else?", mode: .reroll, images: []) {}
        for try await _ in engine.ask("How many?", mode: .standalone, images: [], scope: "albums") {}
        #expect(engine.modes.withLock { $0 } == [.reroll, .standalone])
    }

    /// A host's own button asking Another pick through the store: its engine
    /// runs the question as a reroll, not as a typed question.
    @MainActor
    @Test func aRerollAHostAsksTheStoreReachesItsEngineAsAReroll() async {
        let engine = TurnModeEngine(status: AskModelStatus())
        let store = AskConversationStore(domain: TurnModeDomain(), engine: engine)
        store.ask("What else should I play?", origin: .reroll)
        var hops = 0
        while engine.modes.withLock({ $0.isEmpty }), hops < 1_000 {
            await Task.yield()
            hops += 1
        }
        #expect(engine.modes.withLock { $0 } == [.reroll])
        #expect(store.turns.map(\.origin) == [.reroll])
        store.stop()
    }
    #endif
}

#if os(iOS) || os(macOS) || os(visionOS)
/// A host's row type, plain: nonisolated by this target's default.
private struct TurnModeRow: AskRow {
    let id: String
    var displayTitle: String { id }
}

/// A domain that keeps no thread on disk, so a question is asked at once.
private struct TurnModeDomain: AskDomain {
    let brand = AskBrand(
        title: "Ask the Crate", appDirectory: "AskKitCrossPostureTurnMode",
        logSubsystem: "askkit.crossposture", help: "Ask about the crate.",
        firstScreenHeadline: "Ask about the crate", firstScreenSentence: "Answers come from the model.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    var persistence: AskPersistence { .perLaunch }

    func makeTools(_ context: AskToolContext<TurnModeRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer briefly."
    }
}

/// An engine of a host's own that writes only what `AskAnswering` requires,
/// and keeps the mode it was asked in.
private final class TurnModeEngine: AskAnswering {
    let status: AskModelStatus
    let modes = Mutex<[AskTurnMode]>([])

    init(status: AskModelStatus) {
        self.status = status
    }

    func ask(_ question: String, mode: AskTurnMode) -> AsyncThrowingStream<AskTurnEvent<TurnModeRow>, any Error> {
        modes.withLock { $0.append(mode) }
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}
    func reset() async {}
    func prewarm() async {}
    func refreshStatus() async {}

    var hasKeptConversation: Bool { false }
}
#endif

#endif
