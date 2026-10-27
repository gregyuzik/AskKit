#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// The rows of the pane beside iPhone Duo's fold: every chat newest first,
/// the one on screen in its place among them.
@Suite(.timeLimit(.minutes(1))) struct AskChatsPaneRowsTests {

    private func chat(_ title: String, minutesAgo: Double, id: UUID = UUID()) -> AskThreadSummary {
        let asked = Date(timeIntervalSinceReferenceDate: 800_000_000 - minutesAgo * 60)
        return AskThreadSummary(id: id, title: title, startedAt: asked, updatedAt: asked, turnCount: 1)
    }

    private func titles(current: AskThreadSummary?, history: [AskThreadSummary]) -> [String] {
        AskChatsPaneRows.ordered(current: current, history: history).map(\.title)
    }

    /// Before the first turn of a new chat ends there is no chat on screen to
    /// list, and the earlier ones are as the archive has them.
    @Test func withNoChatOnScreenTheEarlierOnesAreTheList() {
        let history = [chat("records", minutesAgo: 5), chat("books", minutesAgo: 9)]
        #expect(titles(current: nil, history: history) == ["records", "books"])
        #expect(titles(current: nil, history: []).isEmpty)
    }

    /// The chat just asked is the newest, so it leads.
    @Test func theChatJustAskedLeads() {
        let history = [chat("records", minutesAgo: 5), chat("books", minutesAgo: 9)]
        #expect(titles(current: chat("tools", minutesAgo: 0), history: history) == ["tools", "records", "books"])
    }

    /// An earlier chat opened and not yet asked anything stays where it was:
    /// the mark moves to it, and no row moves.
    @Test func anEarlierChatOpenedKeepsItsPlace() {
        let history = [chat("tools", minutesAgo: 1), chat("records", minutesAgo: 5)]
        #expect(titles(current: chat("books", minutesAgo: 9), history: history) == ["tools", "records", "books"])
        let between = [chat("tools", minutesAgo: 1), chat("books", minutesAgo: 9)]
        #expect(titles(current: chat("records", minutesAgo: 5), history: between) == ["tools", "records", "books"])
    }

    /// One row a chat: a filing that left the chat on screen in the archive
    /// too lists it once, as the chat on screen.
    @Test func aChatListedTwiceIsListedOnce() {
        let id = UUID()
        let filed = chat("books", minutesAgo: 9, id: id)
        let onScreen = chat("books", minutesAgo: 2, id: id)
        let rows = AskChatsPaneRows.ordered(current: onScreen, history: [chat("records", minutesAgo: 5), filed])
        #expect(rows.map(\.title) == ["books", "records"])
        #expect(rows.first == onScreen)
    }
}

#endif
