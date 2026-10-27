#if os(iOS) || os(macOS) || os(visionOS)

import Testing

@testable import AskUI

/// The composer's field under a hardware keyboard: what return does.
@Suite(.timeLimit(.minutes(1))) struct AskComposerTests {
    /// Plain return sends a question, and shift-return keeps its newline
    /// whatever else is going on.
    @Test func returnSendsAndShiftReturnKeepsItsNewline() {
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: false) == .send)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "", isThinking: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: true) == .newline)
    }

    /// **Taken, not let through.** Let through, a return the composer can't
    /// send would type a newline: into an empty field that is a draft of one
    /// blank line, which the store reads as a question begun and warms a
    /// session for, and under a turn in flight a line break the reader never
    /// meant to type.
    @Test func returnWithNothingToSendTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: false) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: " \n ", isThinking: false) == .nothing)
    }

    @Test func returnWhileATurnIsInFlightTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: true) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: true) == .nothing)
    }
}

#if os(macOS)
/// What the composer hands the menu bar: a value that changes only when Send
/// or Stop turns on or off, so `AskCommands` isn't rebuilt on every keystroke.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskComposerCommandTests {
    /// The composer builds a new value on every pass of its body, with new
    /// closures each time. Handed to the same actions object, it compares
    /// equal, and a call runs the closures handed in last.
    @Test func aNewPassWithTheSameFlagsIsNoChange() {
        let actions = AskComposerActions()
        var sent = ""
        let first = AskComposerCommand(sends: true, stops: false, actions: actions.holding(send: { sent = "first" }, stop: {}))
        let second = AskComposerCommand(sends: true, stops: false, actions: actions.holding(send: { sent = "second" }, stop: {}))
        #expect(first == second)
        first.send()
        #expect(sent == "second")
    }

    /// A flag turning is a change, and so is another composer's object.
    @Test func aFlagOrAnotherComposerIsAChange() {
        let actions = AskComposerActions()
        let sending = AskComposerCommand(sends: true, stops: false, actions: actions)
        #expect(sending != AskComposerCommand(sends: false, stops: false, actions: actions))
        #expect(sending != AskComposerCommand(sends: true, stops: true, actions: actions))
        #expect(sending != AskComposerCommand(sends: true, stops: false, actions: AskComposerActions()))
    }
}
#endif

#endif
