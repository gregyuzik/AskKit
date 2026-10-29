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
/// **The row tapped is the row opened.** Every row is one button, the open
/// chat's disabled and heard as selected, and a row is the same row for as
/// long as it lists the same chat (`AskChatsPaneRows.Identity`). So opening an
/// earlier chat keeps the element VoiceOver activated where it was, and
/// VoiceOver hears which chat is opening (`AskChatOpening`).
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
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        List {
            ForEach(AskChatsPaneRows.rows(current: current, history: history)) { row in
                self.row(row)
                    .listRowBackground(mark(isOpen: row.isOpen))
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
                    // A glyph alone, so it carries the help tag every
                    // glyph-only button does. The tag shows only on the Mac,
                    // and the pane only beside iPhone Duo's fold, so it waits
                    // for a Mac that lists the chats in a pane.
                    .askHelp(AskDeleteAllChatsButton.title)
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

    /// Every row is the same button. An earlier chat opens on a tap, and goes
    /// on a swipe, from its context menu or by VoiceOver's action. The open
    /// chat's button is disabled, with no delete of its own: New Chat is how a
    /// chat on screen ends, and a tap on what is already open has nothing to
    /// do.
    ///
    /// **One element, whichever chat is open.** A row that became something
    /// other than a button as its chat opened would take away the element
    /// VoiceOver had just activated, and its focus would go wherever the
    /// system put it. So nothing here branches on whether the row is open: the
    /// same button takes the open chat's state through its modifiers, and the
    /// delete is left out of their contents rather than off the row. The row
    /// keeps its identity through the open too (`AskChatsPaneRows.Identity`).
    private func row(_ row: AskChatsPaneRows.Row) -> some View {
        let summary = row.summary
        return Button {
            AskChatOpening.announce(summary)
            onOpen(summary)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AskChatRowLabel(summary: summary, isOpen: row.isOpen)
                // **A mark that isn't a color, where the reader asks for
                // one.** The wash behind the row is about 1.2:1 on the pane
                // (`mark(isOpen:)`), so it says nothing to a reader who can't
                // tell the hue apart. The title's weight says it to everyone
                // else, and a check, the mark a list puts by its choice, says
                // it under Differentiate Without Color and under Bold Text,
                // where every title is heavy already (`showsCheck`).
                // VoiceOver hears `.isSelected` instead.
                if row.isOpen, Self.showsCheck(
                    differentiatesWithoutColor: differentiatesWithoutColor,
                    boldText: legibilityWeight == .bold
                ) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
        }
        // A row of the list, not a link in it, and the open chat's row drawn
        // as it is though it's disabled (`AskChatRowButtonStyle`).
        .buttonStyle(AskChatRowButtonStyle())
        .disabled(row.isOpen)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if row.offersDelete { AskChatDeleteButton { onDelete(summary) } }
        }
        .contextMenu {
            if row.offersDelete { AskChatDeleteButton { onDelete(summary) } }
        }
        // A swipe and a long press aren't gestures every reader can make.
        .accessibilityActions {
            if row.offersDelete {
                Button { onDelete(summary) } label: { AskChatDeleteButton.title }
            }
        }
        .accessibilityAddTraits(row.isOpen ? .isSelected : [])
        .accessibilityIdentifier(row.identifier)
    }

    /// Whether the open chat's row carries a check beside its title: where
    /// the reader asks for a mark that isn't a color, and where Bold Text has
    /// made every title as heavy as the open chat's, so its weight no longer
    /// tells it apart.
    static func showsCheck(differentiatesWithoutColor: Bool, boldText: Bool) -> Bool {
        differentiatesWithoutColor || boldText
    }

    /// The radius of the open chat's wash, and of a row's light.
    static let markCorner: CGFloat = 14

    /// What marks the open chat for the eye: a wash of the screen's accent
    /// behind its row, inset from the pane's edges and from the hinge, with
    /// the title's weight and, under Differentiate Without Color or Bold Text,
    /// a check (`row(_:)`). A wash, as on the composer's face: the row is
    /// content, and glass is for what floats over it.
    @ViewBuilder
    private func mark(isOpen: Bool) -> some View {
        if isOpen {
            RoundedRectangle(cornerRadius: Self.markCorner, style: .continuous)
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
///
/// **A style of its own, so it says outright what a bare button says**: it
/// lights under the reader's eyes and the pointer, in a circle round the
/// target (`askHoverEffect(in:)`), and wears a ring round the glyph under
/// Button Shapes (`AskBareButtonShape`). The Mac's help tag is the button's
/// (`header`), since the words are the button's and not the style's.
private struct AskQuietIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityShowBorders) private var showsBorders

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            // Round the glyph rather than the target, as the thumbs under an
            // answer are: a capsule, so a glyph taller than it is wide stays
            // inside.
            .padding(AskBareButtonShape.ringInset)
            .askButtonShapeRing(.capsule, showsBorders: showsBorders)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .askHoverEffect(in: .circle)
            .opacity(configuration.isPressed ? 0.4 : 1)
    }
}

/// A chat's row as a button: its label as it is, faded only while pressed,
/// and lit under the reader's eyes and the pointer in the corners of the open
/// chat's wash (`AskChatsPane.mark(isOpen:)`), since a style of AskKit's own
/// lights nothing unless it says so (`askHoverEffect(in:)`). The open chat's
/// row is disabled, and isn't lit.
///
/// **Not the plain style**, which dims a disabled button's label, and the open
/// chat's row is disabled: dimmed, the chat on screen would read as the one
/// chat that can't be had. Rendered on the Mac, a disabled plain button's
/// black label on white went from 0.20 to 0.64 lightness, and this style's
/// stayed at 0.20.
private struct AskChatRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .askHoverEffect(in: .rect(cornerRadius: AskChatsPane.markCorner, style: .continuous))
            .opacity(configuration.isPressed ? 0.4 : 1)
    }
}

/// The rows of the pane beside the fold, apart from the view so the order and
/// each row's identity can be pinned (`AskChatsPaneRowsTests`).
nonisolated enum AskChatsPaneRows {
    /// A chat as the pane lists it.
    struct Row: Identifiable, Equatable {
        let summary: AskThreadSummary
        /// Whether this is the chat on screen.
        let isOpen: Bool
        /// What keeps the row the same row while the chat is filed or opened.
        let id: Identity

        /// Only an earlier chat can be deleted from its row: New Chat is how
        /// the chat on screen ends.
        var offersDelete: Bool { !isOpen }

        /// What a UI test finds the row by.
        var identifier: String {
            isOpen ? AskAccessibility.historyCurrent : AskAccessibility.historyRow
        }
    }

    /// What makes a row the same row from one reading of the chats to the
    /// next, and so the same element to VoiceOver.
    ///
    /// **The chat, not its id.** The chat on screen has the store's own id
    /// for as long as the store lives, whichever chat it is (`currentSummary`),
    /// and a chat filed again can take a new id. Keyed by id, the earlier chat
    /// a reader opens would leave the list, and the row of the chat on screen
    /// would move to its place with its title, so the element VoiceOver had
    /// activated would go. A chat's first question, and the moment it was
    /// asked, go with it through a filing and an open, and a question's date
    /// is to the fraction of a second, so no other chat has it.
    enum Identity: Hashable {
        /// A chat by when its first question was asked.
        case chat(Date)
        /// A chat with no date on its first question, which an index written
        /// before there were dates holds, or a second filing of one chat:
        /// by its id, so no two rows share an identity.
        case filing(UUID)
    }

    /// Every chat, newest first by its latest question, the one on screen
    /// among them (`ordered(current:history:)`), each with its identity. The
    /// chat on screen takes its chat's identity before any filing can.
    static func rows(current: AskThreadSummary?, history: [AskThreadSummary]) -> [Row] {
        var taken: Set<Identity> = []
        func identity(of summary: AskThreadSummary) -> Identity {
            if let startedAt = summary.startedAt, taken.insert(.chat(startedAt)).inserted {
                return .chat(startedAt)
            }
            taken.insert(.filing(summary.id))
            return .filing(summary.id)
        }
        let open = current.map { (id: $0.id, identity: identity(of: $0)) }
        return ordered(current: current, history: history).map { summary in
            if let open, summary.id == open.id {
                return Row(summary: summary, isOpen: true, id: open.identity)
            }
            return Row(summary: summary, isOpen: false, id: identity(of: summary))
        }
    }

    /// Every chat, newest first by its latest question, the one on screen
    /// among them.
    ///
    /// **In its place, not on top.** Opening an earlier chat files the one on
    /// screen and puts the earlier one there, and neither is asked anything
    /// by that, so neither moves: the mark does. A chat goes to the top when
    /// the reader asks it something, which is when it is the newest.
    ///
    /// **One row a chat.** The list leaves out the earlier chat on screen,
    /// but not at once: an open puts the chat on screen first and reads the
    /// list again once it is written, and a filing an interrupted write left
    /// behind stays listed until a read joins it. A filing of the chat on
    /// screen, under its id or as the same first question asked at the same
    /// moment, is left out, and the chat on screen is the one listed.
    static func ordered(current: AskThreadSummary?, history: [AskThreadSummary]) -> [AskThreadSummary] {
        guard let current else { return history }
        let earlier = history.filter { !isFiling($0, of: current) }
        let index = earlier.firstIndex { $0.updatedAt <= current.updatedAt } ?? earlier.endIndex
        return Array(earlier[..<index]) + [current] + Array(earlier[index...])
    }

    /// Whether `filing` is a filing of the chat on screen: its id, or its
    /// first question asked at the same moment.
    private static func isFiling(_ filing: AskThreadSummary, of current: AskThreadSummary) -> Bool {
        guard filing.id != current.id else { return true }
        guard let startedAt = filing.startedAt else { return false }
        return startedAt == current.startedAt && filing.title == current.title
    }
}

#endif
