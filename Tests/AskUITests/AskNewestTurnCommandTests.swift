#if os(macOS)

import AskCore
import Foundation
import Synchronization
import Testing

@testable import AskUI

/// What the menu bar's Copy, Copy answer, Edit & Resend and Ask again act on:
/// the newest turn of the focused window's thread, looked up as an item runs
/// (`AskNewestTurn`), and enabled by flags read from the thread's shape
/// (`AskNewestTurnCommand`). The pasteboard and the composer's focus are the
/// screen's own (`AskScreen.copy`, `editAndResend`), which these don't reach;
/// they pin what is handed to them.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskNewestTurnCommandTests {
    /// The screen builds a new value on every pass of its body, with new
    /// closures each time. Handed to the same actions object, it compares
    /// equal, and a call runs the closures handed in last.
    @Test func aNewPassWithTheSameFlagsIsNoChange() {
        let actions = AskNewestTurnActions()
        var ran: [String] = []
        let first = AskNewestTurnCommand(hasTurn: true, hasAnswerText: true, actions: actions.holding(
            copy: { ran.append("first copy") }, copyAnswer: {}, edit: {}, askAgain: {}
        ))
        let second = AskNewestTurnCommand(hasTurn: true, hasAnswerText: true, actions: actions.holding(
            copy: { ran.append("copy") },
            copyAnswer: { ran.append("copy answer") },
            edit: { ran.append("edit") },
            askAgain: { ran.append("ask again") }
        ))
        #expect(first == second)
        first.copy()
        first.copyAnswer()
        first.edit()
        first.askAgain()
        #expect(ran == ["copy", "copy answer", "edit", "ask again"])
    }

    /// A flag turning is a change, and so is another screen's object.
    @Test func aFlagOrAnotherScreenIsAChange() {
        let actions = AskNewestTurnActions()
        let offering = AskNewestTurnCommand(hasTurn: true, hasAnswerText: true, actions: actions)
        #expect(offering != AskNewestTurnCommand(hasTurn: false, hasAnswerText: true, actions: actions))
        #expect(offering != AskNewestTurnCommand(hasTurn: true, hasAnswerText: false, actions: actions))
        #expect(offering != AskNewestTurnCommand(hasTurn: true, hasAnswerText: true, actions: AskNewestTurnActions()))
    }

    /// **An empty thread offers nothing, and reaches nothing.** With no turn,
    /// every item is disabled, and an item run anyway copies nothing and asks
    /// nothing.
    @Test func anEmptyThreadOffersAndReachesNothing() {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        let command = AskNewestTurnCommand(store: store, actions: AskNewestTurnActions())

        #expect(!command.hasTurn)
        #expect(!command.hasAnswerText)
        #expect(AskNewestTurn.turn(in: store) == nil)
        #expect(AskNewestTurn.question(in: store) == nil)
        #expect(AskNewestTurn.answer(in: store) == nil)
        AskNewestTurn.askAgain(in: store)
        #expect(asker.questions.withLock { $0.isEmpty })
        #expect(!store.isThinking)
    }

    /// **The newest turn, not the first.** With two answered turns, Copy takes
    /// the second question, Copy answer the second answer as the reader reads
    /// it, Edit & Resend puts the second question in the composer, and Ask
    /// again asks it over as a follow-up, as the bubble's menu does.
    @Test func eachItemReachesTheNewestTurn() async throws {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.partial("You own **three** records.")]),
            .init(events: [.partial("The newest is **Abbey Road**.")]),
            .init(events: [.partial("Again.")])
        ])
        let store = makeStore(asker: asker)
        store.ask("How many records do I own?")
        await settle(store)
        store.ask("Which is the newest?")
        await settle(store)

        let command = AskNewestTurnCommand(store: store, actions: AskNewestTurnActions())
        #expect(command.hasTurn)
        #expect(command.hasAnswerText)
        #expect(AskNewestTurn.question(in: store) == "Which is the newest?")
        #expect(AskNewestTurn.answer(in: store) == "The newest is Abbey Road.")

        let newest = try #require(AskNewestTurn.turn(in: store))
        #expect(newest.id == store.lastTurnID)
        store.edit(newest)
        #expect(store.draft == "Which is the newest?")

        AskNewestTurn.askAgain(in: store)
        await settle(store)
        let asked = asker.questions.withLock { $0.map(\.0) }
        #expect(asked == ["How many records do I own?", "Which is the newest?", "Which is the newest?"])
        #expect(asker.questions.withLock { $0.last?.1 } == .followUp)
        #expect(store.turns.count == 3)
    }

    /// **Copy answer waits for words**, as the bubble's menu does: a turn that
    /// failed before it wrote any has a question to copy, edit and ask again,
    /// and no answer.
    @Test func aTurnWithNoWordsOffersNoCopyAnswer() async {
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud)], error: AskError.privateCloudUnreachable))
        let store = makeStore(asker: asker)
        store.ask("What do I own?")
        await settle(store)

        let command = AskNewestTurnCommand(store: store, actions: AskNewestTurnActions())
        #expect(command.hasTurn)
        #expect(!command.hasAnswerText)
        #expect(AskNewestTurn.question(in: store) == "What do I own?")
        #expect(AskNewestTurn.answer(in: store) == nil)
    }

    /// **Words keep the value as it was.** The flags come from the thread's
    /// shape, so a finished answer and the same thread a turn later compare
    /// equal while nothing they say has changed: the menu isn't rebuilt for
    /// a word.
    @Test func moreWordsOnTheNewestTurnAreNoChange() async {
        let asker = ScriptedAsker(.init(events: [.partial("You own"), .partial("You own three records.")]))
        let store = makeStore(asker: asker)
        let actions = AskNewestTurnActions()
        store.ask("How many records do I own?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        let early = AskNewestTurnCommand(store: store, actions: actions)
        await settle(store)
        let late = AskNewestTurnCommand(store: store, actions: actions)

        #expect(early.hasAnswerText)
        #expect(early == late)
    }
}

#endif
