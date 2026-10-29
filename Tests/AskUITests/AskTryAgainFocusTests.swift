#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Whose wait row Try Again sends VoiceOver's focus to: the turn the store
/// asks the question again as (`AskWaitRowFocus.retrying(_:after:)`). Try
/// Again goes as that turn starts, with the failed turn that is no longer the
/// newest or no longer there, and the focus goes to the turn's wait row
/// rather than to wherever the system puts it. The focus itself isn't
/// reachable from a test: these pin the request against the turn the store
/// makes (`AskConversationStore.retry`).
@Suite(.timeLimit(.minutes(1))) struct AskTryAgainFocusTests {
    /// **Under prose the failed turn drew, the turn asked below it.** The
    /// failed turn keeps its prose and its place, and the question is asked
    /// again after it, so the request names the failed turn and not the one
    /// before it, whose turn never comes.
    @Test func underProseItKeptTheWaitRowBelowItTakesTheFocus() async throws {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .partial("You own three")], error: AskError.privateCloudUnreachable),
            .init(events: [.tier(.privateCloud)], hangs: true)
        ])
        let store = makeStore(asker: asker)
        store.ask("What do I own?", origin: .starter)
        await settle(store)
        let failed = try #require(store.pairedTurns.last)
        #expect(failed.turn.hasContent)
        #expect(failed.turn.offersRetry(isNewest: true, whileThinking: store.isThinking))

        let request = AskWaitRowFocus.retrying(failed.turn, after: failed.previous)
        store.retry(failed.turn)

        let asked = try #require(store.pairedTurns.last)
        #expect(asked.turn.id != failed.turn.id)
        #expect(asked.previous?.id == failed.turn.id, "the failed turn kept its place")
        #expect(asked.turn.showsWaitRow)
        #expect(AskWaitRowFocus.takes(request, firstTurn: false, after: asked.previous?.id))
        store.stop()
    }

    /// **In the place of a failed turn that drew nothing, the turn asked
    /// there.** The re-ask takes the failed turn's place, after the turn
    /// before it, which the request names.
    @Test func inThePlaceOfATurnThatDrewNothingTheWaitRowThereTakesTheFocus() async throws {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .answer(.of("Kind of Blue."))]),
            .init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer),
            .init(events: [.tier(.onDevice)], hangs: true)
        ])
        let store = makeStore(asker: asker)
        store.ask("What's the oldest?")
        await settle(store)
        store.ask("And the newest?")
        await settle(store)
        let failed = try #require(store.pairedTurns.last)
        let answered = try #require(failed.previous)
        #expect(!failed.turn.hasContent)
        #expect(failed.turn.offersRetry(isNewest: true, whileThinking: store.isThinking))

        let request = AskWaitRowFocus.retrying(failed.turn, after: failed.previous)
        store.retry(failed.turn)

        let asked = try #require(store.pairedTurns.last)
        #expect(store.turns.map(\.id) == [answered.id, asked.turn.id], "the re-ask took the failed turn's place")
        #expect(asked.previous?.id == answered.id)
        #expect(asked.turn.showsWaitRow)
        #expect(AskWaitRowFocus.takes(request, firstTurn: false, after: asked.previous?.id))
        store.stop()
    }

    /// The rule on its own: the failed turn where it drew prose, whatever
    /// came before it, and the turn before it where it drew nothing, which on
    /// the thread's first turn is nothing.
    @Test func theRequestNamesTheFailedTurnOnlyWhereItDrewProse() {
        let earlier = AskTurn<UIRow>(question: "What's the oldest?", origin: .typed)
        var drewNothing = AskTurn<UIRow>(question: "And the newest?", origin: .typed)
        drewNothing.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", isRetryable: true)
        var drewProse = AskTurn<UIRow>(question: "And the newest?", origin: .typed)
        drewProse.write("Going by what you own,", at: 0)
        drewProse.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", isRetryable: true)

        #expect(AskWaitRowFocus.retrying(drewNothing, after: earlier) == AskWaitRowFocus(after: earlier.id))
        #expect(AskWaitRowFocus.retrying(drewNothing, after: nil) == AskWaitRowFocus(after: nil))
        #expect(AskWaitRowFocus.retrying(drewProse, after: earlier) == AskWaitRowFocus(after: drewProse.id))
        #expect(AskWaitRowFocus.retrying(drewProse, after: nil) == AskWaitRowFocus(after: drewProse.id))
    }
}

#endif
