#if os(iOS) || os(macOS) || os(visionOS)

import Testing

@testable import AskUI

/// When the screen's bar has the History item.
@Suite(.timeLimit(.minutes(1))) struct AskHistoryItemTests {
    /// A domain that keeps its chats has the item, typing or not, while its
    /// bars run along the top.
    @Test func aDomainThatKeepsItsChatsHasTheItem() {
        #expect(AskHistoryItem.shows(offersHistory: true, listsChats: false, isTyping: false, barsAreInStrip: false))
        #expect(AskHistoryItem.shows(offersHistory: true, listsChats: false, isTyping: true, barsAreInStrip: false))
    }

    /// A domain that forgets a chat with the process has nothing to list.
    @Test func aDomainThatKeepsNoChatsHasNoItem() {
        #expect(!AskHistoryItem.shows(offersHistory: false, listsChats: false, isTyping: false, barsAreInStrip: false))
        #expect(!AskHistoryItem.shows(offersHistory: false, listsChats: false, isTyping: false, barsAreInStrip: true))
    }

    /// Beside iPhone Duo's fold the chats are on screen, and the item would
    /// open a second copy of them.
    @Test func theChatsOnScreenTakeTheItemAway() {
        #expect(!AskHistoryItem.shows(offersHistory: true, listsChats: true, isTyping: false, barsAreInStrip: true))
        #expect(!AskHistoryItem.shows(offersHistory: true, listsChats: true, isTyping: false, barsAreInStrip: false))
    }

    /// In iPhone Duo's strip the keyboard's predictive bar covers the strip's
    /// last item, so the item goes while the reader types and is back when
    /// the keyboard is put away.
    @Test func typingTakesTheItemOutOfTheStripAndNowhereElse() {
        #expect(!AskHistoryItem.shows(offersHistory: true, listsChats: false, isTyping: true, barsAreInStrip: true))
        #expect(AskHistoryItem.shows(offersHistory: true, listsChats: false, isTyping: false, barsAreInStrip: true))
    }
}

#endif
