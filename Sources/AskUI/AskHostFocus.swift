public import Foundation

/// A host's request for the composer that a screen took
/// (`AskConversationStore.claimComposerFocus(_:)`), and when: what lets the
/// screen hand it to the window the reader has moved to
/// (`AskHostFocusHandOver`).
nonisolated struct AskHostFocusTake: Equatable {
    let request: UUID
    let at: ContinuousClock.Instant
}

/// When a screen hands a host's request for the composer on to another
/// window's screen.
///
/// **Because the window the reader taps comes to the front after the tap's
/// action has run.** A host's request goes to the screen whose window appears
/// active (`AskScreen.windowAppearsActive`), and a tap on a button in the
/// window that isn't runs its action first. ARCHITECTURE.md, "A host's request
/// for the composer", has the timing, measured on two windows of the demo.
/// UIKit's own `activeAppearance` on each window changed when SwiftUI's did,
/// so reading it live rather than through SwiftUI tells nothing sooner. Each
/// scene's key window reads `isKeyWindow` true, so that tells nothing at all.
///
/// So a screen that took a host's request hands it on if its window stops
/// appearing active within `window` of the take with its field still
/// focused: it asks again through the store
/// (`AskConversationStore.repostComposerFocus()`), the screen in the window
/// now in front takes it, and this one lets its focus go once another screen
/// has. With no other window to come to the front, as with one window going
/// to the background, nobody takes the request until this window is back in
/// front and takes it again, and the field never lets its focus go.
///
/// On the Mac, a click makes its window key before its action runs, so this
/// is dormant there, short of a reader who moves to another window within the
/// second.
nonisolated enum AskHostFocusHandOver {
    /// How long after the take a window losing its active appearance still
    /// hands the request on: twice the 470 ms the iPad simulator took, short
    /// enough that a reader who stays put and later moves to another window
    /// keeps the field where they left it.
    static let window: Duration = .seconds(1)

    /// Whether a screen whose window has just stopped appearing active hands
    /// the request it took on: one taken within `window`, while its field
    /// still has the focus that request gave it.
    static func handsOver(_ take: AskHostFocusTake?, now: ContinuousClock.Instant, fieldIsFocused: Bool) -> Bool {
        guard let take, fieldIsFocused else { return false }
        return take.at.duration(to: now) < window
    }
}
