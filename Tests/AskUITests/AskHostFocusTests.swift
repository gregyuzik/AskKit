import Foundation
import Testing

@testable import AskUI

/// When a screen that took a host's request for the composer hands it on, as
/// its window loses the front to the window the reader tapped
/// (`AskHostFocusHandOver`).
@Suite(.timeLimit(.minutes(1))) struct AskHostFocusTests {
    private let request = UUID()
    private let taken = ContinuousClock.now

    /// The window the reader taps comes to the front after the tap's action
    /// has run, 470 ms after it on the iPad simulator, so a take that recent
    /// is handed on with its field still focused.
    @Test func aRequestTakenJustBeforeTheWindowLostTheFrontIsHandedOn() {
        let take = AskHostFocusTake(request: request, at: taken)
        #expect(AskHostFocusHandOver.handsOver(take, now: taken + .milliseconds(470), fieldIsFocused: true))
        #expect(AskHostFocusHandOver.handsOver(take, now: taken, fieldIsFocused: true))
    }

    /// A reader who stayed put and moves to another window later keeps the
    /// field where they left it.
    @Test func aRequestTakenEarlierStaysWhereItWasTaken() {
        let take = AskHostFocusTake(request: request, at: taken)
        #expect(!AskHostFocusHandOver.handsOver(take, now: taken + AskHostFocusHandOver.window, fieldIsFocused: true))
        #expect(!AskHostFocusHandOver.handsOver(take, now: taken + .seconds(5), fieldIsFocused: true))
    }

    /// Nothing to hand on once the field has let its focus go, or where this
    /// screen took no request, or has handed it on already.
    @Test func aFieldWithoutTheFocusOrAScreenThatTookNothingHandsNothingOn() {
        let take = AskHostFocusTake(request: request, at: taken)
        #expect(!AskHostFocusHandOver.handsOver(take, now: taken + .milliseconds(100), fieldIsFocused: false))
        #expect(!AskHostFocusHandOver.handsOver(nil, now: taken + .milliseconds(100), fieldIsFocused: true))
    }
}
