#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// When the screen's navigation bar may minimize as the reader scrolls down,
/// and what keeps it open.
@Suite(.timeLimit(.minutes(1))) struct AskNavigationBarMinimizationTests {
    /// On the thread, with nothing over it, the bar minimizes as the reader
    /// scrolls down.
    @Test func theBarMinimizesOnTheThread() {
        #expect(AskNavigationBarMinimization.minimizes(showsDoneItem: false, itemIsPushed: false, threadScrollsItself: false))
    }

    /// Done is one of the bar's items, and a minimized bar hides its items.
    @Test func doneKeepsTheBarOpen() {
        #expect(!AskNavigationBarMinimization.minimizes(showsDoneItem: true, itemIsPushed: false, threadScrollsItself: false))
    }

    /// A page pushed while the bar is minimized hangs the app, so the bar is
    /// open from the update that pushes until the page is popped, with Done
    /// showing or not.
    @Test func aPushedItemKeepsTheBarOpen() {
        #expect(!AskNavigationBarMinimization.minimizes(showsDoneItem: false, itemIsPushed: true, threadScrollsItself: false))
        #expect(!AskNavigationBarMinimization.minimizes(showsDoneItem: true, itemIsPushed: true, threadScrollsItself: false))
    }

    /// The screen's own scroll of the thread, a chat opened or the follow,
    /// never minimizes the bar: only the reader's does.
    @Test func theScreensOwnScrollKeepsTheBarOpen() {
        #expect(!AskNavigationBarMinimization.minimizes(showsDoneItem: false, itemIsPushed: false, threadScrollsItself: true))
        #expect(!AskNavigationBarMinimization.minimizes(showsDoneItem: true, itemIsPushed: true, threadScrollsItself: true))
    }

    /// A host that never says it pushes keeps a bar that minimizes.
    @Test func nothingIsPushedUntilTheHostSaysSo() {
        #expect(!EnvironmentValues().askItemIsPushed)
    }
}

#endif
