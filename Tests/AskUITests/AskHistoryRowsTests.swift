#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// A chat's row in the list of chats, the pane's and the sheet's: when it was
/// last asked, kept true while the row is on screen, and what VoiceOver hears
/// as the reader opens it.
@Suite(.timeLimit(.minutes(1))) struct AskHistoryRowsTests {

    private let asked = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    // MARK: - When it was last asked

    /// Read against the moment it is drawn, not the moment the row was built.
    @Test func theDateReadsAgainstTheMomentItIsDrawn() {
        let style = AskChatRowLabel.lastAsked(asked, locale: english)
        #expect(style.format(asked.addingTimeInterval(3 * 60)) == "3 minutes ago")
        #expect(style.format(asked.addingTimeInterval(2 * 60 * 60)) == "2 hours ago")
    }

    /// **Drawn again as it changes.** SwiftUI keeps a `.currentDate` text
    /// live only for a discrete style, which says when its words next
    /// change: a row on screen half an hour reads "30 minutes ago", not what
    /// it read as it appeared.
    @Test func theDateSaysWhenItNextChanges() throws {
        let style = AskChatRowLabel.lastAsked(asked, locale: english)
        let now = asked.addingTimeInterval(90)
        let next = try #require(style.discreteInput(after: now))
        #expect(next > now)
        #expect(next <= now.addingTimeInterval(60))
        #expect(style.format(next) != style.format(now))
    }

    /// To the minute: a chat just asked reads "this minute", and its row
    /// isn't redrawn each second to count them.
    @Test func theDateNeverCountsSeconds() throws {
        let style = AskChatRowLabel.lastAsked(asked, locale: english)
        let tenSeconds = asked.addingTimeInterval(10)
        #expect(style.format(tenSeconds) == style.format(asked.addingTimeInterval(20)))
        let next = try #require(style.discreteInput(after: tenSeconds))
        #expect(next.timeIntervalSince(tenSeconds) > 1)
    }

    // MARK: - Which chat opens

    /// VoiceOver hears the chat by its title, the reader's own words, as
    /// they wrote them: a title that looks like a format is still the title.
    @Test func theOpeningLineNamesTheChatInTheReadersWords() {
        let books = AskThreadSummary(id: UUID(), title: "Which books did I lend out?", startedAt: asked, updatedAt: asked, turnCount: 1)
        #expect(AskChatOpening.line(for: books) == "Opening “Which books did I lend out?”")
        let percent = AskThreadSummary(id: UUID(), title: "100% %@ cotton", startedAt: asked, updatedAt: asked, turnCount: 1)
        #expect(AskChatOpening.line(for: percent) == "Opening “100% %@ cotton”")
    }
}

#endif
