#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The reader's chats as the pane beside iPhone Duo's fold
/// (`AskFoldArrangement`): on screen beside the conversation, where the sheet
/// (`AskThreadHistorySheet`) is a list called up over it.
///
/// **One list, newest first, the open chat marked in its place.** The sheet
/// leads with the chat on screen under a heading of its own, since it opens
/// over that chat and closes on a choice. Here both stay on screen, so the
/// open chat is a row among the others, marked the way a split view marks
/// what its other column shows, and opening an earlier chat moves the mark and
/// no row (`AskChatsPaneRows`).
///
/// **The conversation's own ground.** The list draws no background, so the
/// two panes are one surface with the hinge's hairline between them. A
/// grouped list's grey ground and white cards read as Settings beside a chat.
///
/// **Its title is its own**, since the bar is the host's, and on iPhone Duo's
/// inner display held like a book there is no bar along the top at all.
/// Delete All Chats sits beside it, as it sits in the sheet's bar, and asks
/// before it deletes.
///
/// No search field, which the sheet has: a field here would raise the
/// keyboard under a conversation whose own composer hasn't the focus, and the
/// screen's way out of the keyboard, Done, is keyed on that composer.
struct AskChatsPane: View {
    let current: AskThreadSummary?
    let history: [AskThreadSummary]
    /// The screen's accent, which marks the open chat.
    let accent: Color
    let onOpen: (AskThreadSummary) -> Void
    let onDelete: (AskThreadSummary) -> Void
    /// Deletes every chat: the earlier ones and the one on screen.
    let onDeleteAll: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiatesWithoutColor

    var body: some View {
        List {
            ForEach(AskChatsPaneRows.ordered(current: current, history: history)) { summary in
                row(summary)
                    .listRowBackground(mark(isOpen: summary.id == current?.id))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 28, bottom: 10, trailing: 28))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier(AskAccessibility.historyPane)
        .overlay { emptyState }
        .safeAreaBar(edge: .top) { header }
    }

    /// The pane's title, and Delete All Chats beside it while there is a chat
    /// to delete: the one on screen once a turn of it has ended, or any
    /// earlier one.
    private var header: some View {
        HStack {
            AskThreadHistoryList.title
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if current != nil || !history.isEmpty {
                AskDeleteAllChatsButton(onConfirm: onDeleteAll)
                    .labelStyle(.iconOnly)
                    .buttonStyle(AskQuietIconButtonStyle())
            }
        }
        // The title on the rows' edge, and the glyph centered on the edge
        // their text ends at.
        .padding(.leading, 28)
        .padding(.trailing, 6)
        .padding(.top, 4)
        // As tall with no button in it, so the first chat filed doesn't move
        // the title.
        .frame(minHeight: 48)
    }

    /// The open chat's row is no button: New Chat is how a chat on screen
    /// ends, and a tap on what is already open has nothing to do. An earlier
    /// chat opens on a tap, and goes on a swipe, from its context menu or by
    /// VoiceOver's action.
    @ViewBuilder
    private func row(_ summary: AskThreadSummary) -> some View {
        if summary.id == current?.id {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AskChatRowLabel(summary: summary, isOpen: true)
                // **A mark that isn't a color, where the reader asks for
                // one.** The wash behind the row is about 1.2:1 on the pane
                // (`mark(isOpen:)`), so it says nothing to a reader who can't
                // tell the hue apart. The title's weight says it to everyone,
                // and Differentiate Without Color adds the check a list puts
                // by its choice. VoiceOver hears `.isSelected` instead.
                if differentiatesWithoutColor {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier(AskAccessibility.historyCurrent)
        } else {
            Button {
                onOpen(summary)
            } label: {
                AskChatRowLabel(summary: summary)
            }
            // A row of the list, not a link in it: plain, so the title keeps
            // the text's color rather than the tint's.
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { AskChatDeleteButton { onDelete(summary) } }
            .contextMenu { AskChatDeleteButton { onDelete(summary) } }
            // A swipe and a long press aren't gestures every reader can make.
            .accessibilityAction(named: AskChatDeleteButton.title) { onDelete(summary) }
            .accessibilityIdentifier(AskAccessibility.historyRow)
        }
    }

    /// What marks the open chat for the eye: a wash of the screen's accent
    /// behind its row, inset from the pane's edges and from the hinge, with
    /// the title's weight and, under Differentiate Without Color, a check
    /// (`row(_:)`). A wash, as on the composer's face: the row is content,
    /// and glass is for what floats over it.
    @ViewBuilder
    private func mark(isOpen: Bool) -> some View {
        if isOpen {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.16))
                .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if current == nil, history.isEmpty {
            AskNoChatsView()
        }
    }
}

/// A glyph alone as a button, in the pane's title row: the text's quiet color,
/// since the dialog it opens is where a deletion is red, and a 44 pt target
/// around a glyph half that size.
private struct AskQuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.4 : 1)
    }
}

/// The rows of the pane beside the fold, apart from the view so the order can
/// be pinned (`AskChatsPaneRowsTests`).
nonisolated enum AskChatsPaneRows {
    /// Every chat, newest first by its latest question, the one on screen
    /// among them.
    ///
    /// **In its place, not on top.** Opening an earlier chat files the one on
    /// screen and puts the earlier one there, and neither is asked anything
    /// by that, so neither moves: the mark does. A chat goes to the top when
    /// the reader asks it something, which is when it is the newest.
    ///
    /// The archive lists a filed chat once, and the chat on screen isn't in
    /// it. Should a filing ever leave one behind under the same id, the chat
    /// on screen is the one listed.
    static func ordered(current: AskThreadSummary?, history: [AskThreadSummary]) -> [AskThreadSummary] {
        guard let current else { return history }
        let earlier = history.filter { $0.id != current.id }
        let index = earlier.firstIndex { $0.updatedAt <= current.updatedAt } ?? earlier.endIndex
        return Array(earlier[..<index]) + [current] + Array(earlier[index...])
    }
}

#endif
