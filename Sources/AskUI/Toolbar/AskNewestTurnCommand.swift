#if os(macOS)

import AskCore
import Foundation
import SwiftUI

/// What the menu bar's Copy, Copy answer, Edit & Resend and Ask again act on
/// (`AskCommands`): the newest turn of the thread in the focused window, which
/// its `AskScreen` hands up with `focusedSceneValue`. The question bubble's
/// menu holds the same four for every turn (`AskQuestionBubble`), and a long
/// press or a right-click is the only way to it: in the menu bar, a reader
/// with only a keyboard reaches them too, the newest turn's being the one a
/// reader wants back most.
///
/// **Two flags and an object, and no closure**, as the composer's Send and
/// Stop are (`AskComposerCommand`): a value holding the screen's closures read
/// as changed on every pass of its body and ran `AskCommands`' body again each
/// time. The flags come from the thread's shape, never from `turns`, so the
/// value changes as a turn arrives or the thread empties, and as the newest
/// turn writes its first word, and not with every word after.
struct AskNewestTurnCommand: Equatable {
    /// Whether the thread has a turn: Copy, Edit & Resend and Ask again are
    /// enabled while it has.
    let hasTurn: Bool
    /// Whether the newest turn has words to copy: Copy answer is enabled
    /// while it has, as the bubble's menu offers it once the answer has words.
    let hasAnswerText: Bool
    let actions: AskNewestTurnActions

    init(hasTurn: Bool, hasAnswerText: Bool, actions: AskNewestTurnActions) {
        self.hasTurn = hasTurn
        self.hasAnswerText = hasAnswerText
        self.actions = actions
    }

    /// What `store`'s thread offers now, read from its shape: `hasTurns`, and
    /// the stage's `lastHasText`, never `turns`.
    init<Domain: AskDomain>(store: AskConversationStore<Domain>, actions: AskNewestTurnActions) {
        self.init(hasTurn: store.hasTurns, hasAnswerText: store.stage.lastHasText, actions: actions)
    }

    /// Copies the newest turn's question.
    func copy() {
        actions.copy()
    }

    /// Copies the newest turn's answer, as the reader reads it.
    func copyAnswer() {
        actions.copyAnswer()
    }

    /// Puts the newest turn's question back in the composer, and the reader
    /// with it.
    func edit() {
        actions.edit()
    }

    /// Asks the newest turn's question over.
    func askAgain() {
        actions.askAgain()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasTurn == rhs.hasTurn && lhs.hasAnswerText == rhs.hasAnswerText && lhs.actions === rhs.actions
    }
}

/// The screen's four actions on its newest turn as the menu bar calls them
/// (`AskNewestTurnCommand`): handed the screen's closures as each pass of its
/// body builds them, so a call runs what the screen would run now.
///
/// **Each looks the turn up as it runs** (`AskNewestTurn`), and none holds a
/// turn: a turn held from the pass that built the closure would copy an
/// answer's first words long after it finished, as a question bubble SwiftUI
/// skips would (`AskEquatableQuestionBubble`).
///
/// Not observable, and nothing reads it in a body: what it holds changing
/// redraws nothing.
final class AskNewestTurnActions {
    private var copies: () -> Void = {}
    private var copiesAnswer: () -> Void = {}
    private var edits: () -> Void = {}
    private var asksAgain: () -> Void = {}

    /// This, holding the four from here on.
    func holding(
        copy: @escaping () -> Void,
        copyAnswer: @escaping () -> Void,
        edit: @escaping () -> Void,
        askAgain: @escaping () -> Void
    ) -> AskNewestTurnActions {
        copies = copy
        copiesAnswer = copyAnswer
        edits = edit
        asksAgain = askAgain
        return self
    }

    func copy() {
        copies()
    }

    func copyAnswer() {
        copiesAnswer()
    }

    func edit() {
        edits()
    }

    func askAgain() {
        asksAgain()
    }
}

/// The newest turn of a store's thread, read when a menu item runs, apart
/// from the screen so what each item reaches can be tested
/// (`AskNewestTurnCommandTests`).
enum AskNewestTurn {
    /// The newest turn, or nil on an empty thread.
    static func turn<Domain: AskDomain>(in store: AskConversationStore<Domain>) -> AskTurn<Domain.Row>? {
        store.turns.last
    }

    /// The newest turn's question, as the bubble's Copy copies it.
    static func question<Domain: AskDomain>(in store: AskConversationStore<Domain>) -> String? {
        turn(in: store)?.question
    }

    /// The newest turn's answer as the reader reads it (`AskTurn.drawnText`),
    /// or nil while it has no words, as the bubble's Copy answer copies it.
    static func answer<Domain: AskDomain>(in store: AskConversationStore<Domain>) -> String? {
        guard let text = turn(in: store)?.drawnText, !text.isEmpty else { return nil }
        return text
    }

    /// Asks the newest turn's question over, as the bubble's Ask again does.
    /// Nothing on an empty thread.
    static func askAgain<Domain: AskDomain>(in store: AskConversationStore<Domain>) {
        guard let turn = turn(in: store) else { return }
        store.askAgain(turn)
    }
}

extension FocusedValues {
    /// The focused window's newest turn (`AskNewestTurnCommand`).
    @Entry var askNewestTurn: AskNewestTurnCommand?
}

#endif
