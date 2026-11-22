#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import SwiftUI

/// The reader's chats in a sheet, from the toolbar's button: the list
/// (`AskThreadHistoryList`), a search field, and Delete All Chats in the bar.
///
/// VoiceOver hears which earlier chat opens as it is tapped
/// (`AskChatOpening`), and the sheet closes once the chat is on screen behind
/// it: the row it activated goes with the sheet, and the focus goes back to
/// the History button, which says nothing of the chat. A chat that doesn't
/// open keeps the sheet up, and an alert over it says so (`AskChatRefusal`):
/// closed on the tap, it would leave the reader on the chat they meant to
/// leave, with nothing said. Delete All Chats closes the sheet too, since
/// nothing is left in it to look at.
struct AskThreadHistorySheet: View {
    let current: AskThreadSummary?
    let history: [AskThreadSummary]
    /// Opens a chat, and tells the sheet what came of it
    /// (`AskConversationStore.openThread(_:reporting:)`).
    let onOpen: (AskThreadSummary, @escaping @MainActor (AskChatOpenOutcome) -> Void) -> Void
    let onDelete: (AskThreadSummary) -> Void
    /// Deletes every chat: the earlier ones and the one on screen.
    let onDeleteAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var refusal = AskChatRefusal()

    var body: some View {
        NavigationStack {
            AskThreadHistoryList(
                current: current,
                history: history,
                query: query,
                onOpen: { summary in
                    AskChatOpening.announce(summary)
                    onOpen(summary) { outcome in
                        switch outcome {
                        case .opened: dismiss()
                        // What took its place says what came of it here when
                        // it came from here: another row, whose own word
                        // closes the sheet or says why not, or Delete All
                        // Chats, which closes it. New Chat from the menu, a
                        // host's own request or another window's leaves the
                        // sheet up, listing the chats as they are now.
                        case .gaveWay: break
                        case .refused: refusal.show(for: summary)
                        }
                    }
                },
                onDelete: onDelete
            )
            .askChatRefusalAlert($refusal)
            .searchable(text: $query, prompt: Text("Search chats", bundle: #bundle, comment: "Placeholder in the search field of the list of Ask chats."))
            .navigationTitle(AskThreadHistoryList.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier(AskAccessibility.historyClose)
                }
                // Only while there is a chat to delete: the one on screen once
                // a turn of it has ended, or any earlier one.
                if current != nil || !history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        AskDeleteAllChatsButton {
                            dismiss()
                            onDeleteAll()
                        }
                    }
                }
            }
        }
        #if os(macOS)
        // **A size of its own on the Mac**, where a sheet is as big as its
        // content asks: a list asks for no height, and the sheet opened 470 by
        // 158 points, its bars alone with no row between them (macOS 27.2,
        // 2026-10-31). Room for a few rows, which scroll in what they have.
        .frame(minWidth: 400, idealWidth: 480, minHeight: 300, idealHeight: 420)
        #endif
    }
}

#endif
