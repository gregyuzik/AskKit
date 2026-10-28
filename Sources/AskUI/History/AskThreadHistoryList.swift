#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The reader's chats as the list in the sheet the toolbar's button opens
/// (`AskThreadHistorySheet`): the one on screen, and the ones New Chat put
/// away. The pane beside iPhone Duo's fold lists them its own way
/// (`AskChatsPane`), out of the same rows, so a chat reads the same in both.
///
/// A plain list, because a chat is found by what it asked: its first
/// question, with when it was last asked beneath. The chat on screen leads and
/// has no delete of its own: New Chat is how a chat on screen ends. An earlier
/// chat opens on a tap, and goes on a swipe, from its context menu or by
/// VoiceOver's action. VoiceOver hears which chat is opening
/// (`AskChatOpening`), since the sheet closes on the tap and takes the row
/// with it.
///
/// Content, not chrome: the rows are the list's own, and the only glass is
/// what the system puts on the bar above it.
struct AskThreadHistoryList: View {
    let current: AskThreadSummary?
    let history: [AskThreadSummary]
    /// What the reader is searching for, or nothing.
    var query = ""
    let onOpen: (AskThreadSummary) -> Void
    let onDelete: (AskThreadSummary) -> Void

    /// What the list of chats is called: the sheet's title, and the title of
    /// the pane beside the fold. One key for both.
    static var title: Text {
        Text("Chats", bundle: #bundle, comment: "Title of the list of the reader's Ask chats.")
    }

    var body: some View {
        List {
            if let current, matches(current) {
                Section {
                    AskChatRowLabel(summary: current)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AskAccessibility.historyCurrent)
                } header: {
                    Text("Current chat", bundle: #bundle, comment: "Heading above the chat on screen, at the top of the list of Ask chats.")
                }
            }
            if !earlier.isEmpty {
                Section {
                    ForEach(earlier) { summary in
                        Button {
                            onOpen(summary)
                        } label: {
                            AskChatRowLabel(summary: summary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { AskChatDeleteButton { onDelete(summary) } }
                        .contextMenu { AskChatDeleteButton { onDelete(summary) } }
                        // A swipe and a long press aren't gestures every
                        // reader can make.
                        .accessibilityAction(named: AskChatDeleteButton.title) { onDelete(summary) }
                        .accessibilityIdentifier(AskAccessibility.historyRow)
                    }
                } header: {
                    Text("Earlier chats", bundle: #bundle, comment: "The reader's earlier Ask chats: the toolbar button that lists them, and the heading above them in that list.")
                }
            }
        }
        .accessibilityIdentifier(AskAccessibility.historyList)
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if current == nil, history.isEmpty {
            AskNoChatsView()
        } else if !query.isEmpty, earlier.isEmpty, current.map(matches) != true {
            ContentUnavailableView.search(text: query)
        }
    }

    private var earlier: [AskThreadSummary] {
        query.isEmpty ? history : history.filter(matches)
    }

    private func matches(_ summary: AskThreadSummary) -> Bool {
        query.isEmpty || summary.title.localizedStandardContains(query)
    }
}

/// A chat as a row: its first question, and when it was last asked, which
/// stays true while the row is on screen (`lastAsked(_:)`).
struct AskChatRowLabel: View {
    let summary: AskThreadSummary
    /// Whether this is the chat on screen in the pane beside the fold, whose
    /// title takes a heavier weight (`AskChatsPane`).
    var isOpen = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The reader's own words: verbatim, never looked up as a key.
            Text(verbatim: summary.title)
                .fontWeight(isOpen ? .semibold : nil)
                .foregroundStyle(.primary)
                .lineLimit(Self.titleLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
            // **Read against the moment it is drawn**, and drawn again as it
            // changes. A date formatted relative to now once stays as it was
            // until something rebuilds the row, and the pane beside iPhone
            // Duo's fold is on screen for as long as the chat beside it is:
            // "30 minutes ago" all afternoon. `.currentDate` with a discrete
            // style is one SwiftUI keeps live.
            Text(.currentDate, format: Self.lastAsked(summary.updatedAt))
                .font(.subheadline)
                .askDeemphasizedText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// When a chat was last asked, relative to the moment it is read:
    /// "2 minutes ago", "yesterday", "last week".
    ///
    /// **To the minute, never the second.** With seconds, the row of a chat
    /// just asked counts them for its first minute, redrawn every half
    /// second beside the answer the reader is reading. So it reads "this
    /// minute" until it reads "1 minute ago", and changes at most once a
    /// minute after.
    static func lastAsked(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> Date.AnchoredRelativeFormatStyle {
        Date.AnchoredRelativeFormatStyle(
            anchor: date,
            allowedFields: [.year, .month, .week, .day, .hour, .minute],
            presentation: .named,
            locale: locale
        )
    }

    /// Two lines of a title, or all of them at the accessibility sizes, as
    /// the default tiles' titles (`AskDefaultTileText`): at the largest size
    /// two lines hold a few words, too few to tell two chats apart.
    static func titleLineLimit(isAccessibilitySize: Bool) -> Int? {
        isAccessibilitySize ? nil : 2
    }
}

/// Deletes one earlier chat: an earlier row's swipe action and its menu item.
struct AskChatDeleteButton: View {
    let action: () -> Void

    /// One spelling, for the button and the row's VoiceOver action.
    static var title: Text {
        Text("Delete", bundle: #bundle, comment: "Swipe action and menu item that deletes one of the reader's earlier Ask chats.")
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Self.title
            } icon: {
                Image(systemName: "trash")
            }
        }
        .accessibilityIdentifier(AskAccessibility.historyDelete)
    }
}

/// What VoiceOver hears as the reader opens an earlier chat, from the pane
/// beside the fold or the sheet: which chat.
///
/// **An announcement, not the focus.** Moving VoiceOver's focus to the opened
/// chat's last question would say which chat it is by putting the reader in
/// it, but it would take a reader browsing the pane out of the list, and the
/// focus is the screen's to give (`AskVoiceOverTarget`), where nothing asks
/// for the thread's rows yet. Said here, it is the same line from both: in
/// the pane the reader's place stays on the row they tapped, and from the
/// sheet, whose row goes with it, the line is heard as the focus goes back to
/// the History button.
///
/// **"Opening", not "opened"**, because it is said on the tap. An open can be
/// declined, when the chat on screen can't be filed or the earlier one won't
/// read, and the sheet is gone before it would know.
nonisolated enum AskChatOpening {
    /// The line for opening `summary`, its title in the reader's own words.
    static func line(for summary: AskThreadSummary) -> String {
        String(
            localized: "Opening “\(summary.title)”",
            bundle: #bundle,
            comment: "Spoken by VoiceOver as the reader opens one of their earlier Ask chats from the list of chats. The placeholder is the chat's title: the first question the reader asked in it, in their own words."
        )
    }

    /// Posts the line at high priority, which only an `AttributedString`
    /// carries. At default priority VoiceOver can speak over it what takes
    /// the focus next, the History button as the sheet goes, as it speaks a
    /// refocused button over a terminal announcement (`AskScreen`).
    @MainActor static func announce(_ summary: AskThreadSummary) {
        var spoken = AttributedString(line(for: summary))
        spoken.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(spoken).post()
    }
}

/// What a list of chats shows while there are none.
struct AskNoChatsView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No earlier chats", bundle: #bundle, comment: "Shown in the list of Ask chats when there are none to go back to.")
            } icon: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
        } description: {
            Text("A chat moves here when a new one starts.", bundle: #bundle, comment: "Under 'No earlier chats': explains that New Chat puts the chat on screen into this list.")
        }
    }
}

/// Delete All Chats, and the dialog that asks first, attached to the button
/// rather than to the list, so the dialog is anchored to what was tapped.
/// Nothing goes until the dialog's own button is pressed.
///
/// **It takes every chat, the one on screen with it**, and the dialog says so.
/// The chat on screen is the first row of the list, so leaving it behind would
/// answer "delete all" with a list that still holds a chat. It isn't filed on
/// the way out, as New Chat files it.
struct AskDeleteAllChatsButton: View {
    /// What the dialog's button does: deletes every chat, and closes the sheet
    /// where there is one, since nothing is left in it to look at.
    let onConfirm: () -> Void

    @State private var confirms = false

    var body: some View {
        Button(role: .destructive) {
            confirms = true
        } label: {
            Label {
                title
            } icon: {
                Image(systemName: "trash")
            }
        }
        .accessibilityIdentifier(AskAccessibility.historyDeleteAll)
        .confirmationDialog(
            Text("Delete all chats?", bundle: #bundle, comment: "Title of the dialog that asks before every Ask chat is deleted, the one on screen included."),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                onConfirm()
            } label: {
                title
            }
            .accessibilityIdentifier(AskAccessibility.historyDeleteAllConfirm)
        } message: {
            Text("Every chat will be deleted, including the current one. This can't be undone.", bundle: #bundle, comment: "Under 'Delete all chats?': says that the chat on screen is deleted too, and that the deletion is final.")
        }
    }

    /// One key for the button and the dialog's, which say the same thing.
    private var title: Text {
        Text("Delete All Chats", bundle: #bundle, comment: "Button that deletes every Ask chat, the one on screen included: in the bar of the list of chats, and again in the dialog that asks first.")
    }
}

#endif
