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

    // MARK: - One element a row

    /// The chat on screen as the store gives it: under the store's own id,
    /// whichever chat it is (`AskConversationStore.currentSummary`).
    private let storeChatID = UUID()

    private func summary(_ title: String, id: UUID, startedAt: Date?, minutesAgo: Double) -> AskThreadSummary {
        let asked = Date(timeIntervalSinceReferenceDate: 800_000_000 - minutesAgo * 60)
        return AskThreadSummary(id: id, title: title, startedAt: startedAt, updatedAt: asked, turnCount: 2)
    }

    private func started(minutesAgo: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 - minutesAgo * 60 + 0.123)
    }

    /// **The row tapped is the row opened.** Opening an earlier chat puts it
    /// on screen under the store's id, takes its filing off the list and
    /// files the chat that was on screen under a new id. Keyed by id, the
    /// row the reader tapped went and another took its place; keyed by the
    /// chat, the same row is now the open one, so VoiceOver's element stays.
    @Test func theRowTappedIsTheRowOpened() throws {
        let toolsStarted = started(minutesAgo: 30)
        let booksStarted = started(minutesAgo: 60)
        let before = AskChatsPaneRows.rows(
            current: summary("tools", id: storeChatID, startedAt: toolsStarted, minutesAgo: 1),
            history: [summary("books", id: UUID(), startedAt: booksStarted, minutesAgo: 9)]
        )
        let after = AskChatsPaneRows.rows(
            current: summary("books", id: storeChatID, startedAt: booksStarted, minutesAgo: 9),
            history: [summary("tools", id: UUID(), startedAt: toolsStarted, minutesAgo: 1)]
        )
        let tapped = try #require(before.first { $0.summary.title == "books" })
        let opened = try #require(after.first { $0.isOpen })
        #expect(!tapped.isOpen)
        #expect(opened.summary.title == "books")
        #expect(opened.id == tapped.id)
        // The chat that was on screen keeps its row too, now an earlier one.
        let wasOpen = try #require(before.first { $0.isOpen })
        let filed = try #require(after.first { $0.summary.title == "tools" })
        #expect(filed.id == wasOpen.id)
        #expect(!filed.isOpen)
        // And neither moved.
        #expect(before.map(\.id) == after.map(\.id))
    }

    /// Between an open putting the chat on screen and the list being read
    /// again, the list still holds the chat's filing: one row, the open one,
    /// not the chat twice.
    @Test func theOpenedChatsFilingIsntListedBesideIt() {
        let booksStarted = started(minutesAgo: 60)
        let rows = AskChatsPaneRows.rows(
            current: summary("books", id: storeChatID, startedAt: booksStarted, minutesAgo: 9),
            history: [
                summary("records", id: UUID(), startedAt: started(minutesAgo: 20), minutesAgo: 5),
                summary("books", id: UUID(), startedAt: booksStarted, minutesAgo: 9)
            ]
        )
        #expect(rows.map(\.summary.title) == ["records", "books"])
        #expect(rows.map(\.isOpen) == [false, true])
    }

    /// Two filings of one chat, as a filing that won't read whole leaves the
    /// chat filed beside it, are two rows that a list can still tell apart.
    @Test func twoFilingsOfOneChatAreTwoRows() {
        let booksStarted = started(minutesAgo: 60)
        let rows = AskChatsPaneRows.rows(
            current: nil,
            history: [
                summary("books", id: UUID(), startedAt: booksStarted, minutesAgo: 9),
                summary("books", id: UUID(), startedAt: booksStarted, minutesAgo: 12)
            ]
        )
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)).count == 2)
    }

    /// A chat filed before there were dates on first questions is known by
    /// its id.
    @Test func aChatWithNoDateIsKnownByItsID() {
        let id = UUID()
        let rows = AskChatsPaneRows.rows(current: nil, history: [summary("books", id: id, startedAt: nil, minutesAgo: 9)])
        #expect(rows.map(\.id) == [.filing(id)])
    }

    /// The open chat's row is heard as selected, can't be deleted from its
    /// row, and is found as the current chat; an earlier chat's row as a row.
    @Test func onlyAnEarlierChatsRowOffersDelete() throws {
        let rows = AskChatsPaneRows.rows(
            current: summary("tools", id: storeChatID, startedAt: started(minutesAgo: 30), minutesAgo: 1),
            history: [summary("books", id: UUID(), startedAt: started(minutesAgo: 60), minutesAgo: 9)]
        )
        let open = try #require(rows.first)
        let earlier = try #require(rows.last)
        #expect(open.isOpen && !open.offersDelete)
        #expect(open.identifier == AskAccessibility.historyCurrent)
        #expect(!earlier.isOpen && earlier.offersDelete)
        #expect(earlier.identifier == AskAccessibility.historyRow)
    }

    // MARK: - The mark that isn't a color

    /// The title's weight marks the open chat for most readers. Under Bold
    /// Text every title is heavy, so the check says it there, as it does
    /// under Differentiate Without Color.
    @Test func theCheckShowsWhereTheWeightCantTellTheOpenChatApart() {
        #expect(!AskChatsPane.showsCheck(differentiatesWithoutColor: false, boldText: false))
        #expect(AskChatsPane.showsCheck(differentiatesWithoutColor: true, boldText: false))
        #expect(AskChatsPane.showsCheck(differentiatesWithoutColor: false, boldText: true))
        #expect(AskChatsPane.showsCheck(differentiatesWithoutColor: true, boldText: true))
    }
}

#endif
