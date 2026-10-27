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
/// VoiceOver's action.
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

/// A chat as a row: its first question, and when it was last asked.
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
            Text(summary.updatedAt, format: .relative(presentation: .named))
                .font(.subheadline)
                .askDeemphasizedText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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
