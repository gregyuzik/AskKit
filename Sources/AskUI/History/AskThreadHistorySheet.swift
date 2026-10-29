#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import SwiftUI

/// The reader's chats in a sheet, from the toolbar's button: the list
/// (`AskThreadHistoryList`), a search field, and Delete All Chats in the bar.
///
/// An earlier chat opens behind the sheet as it closes, and VoiceOver hears
/// which (`AskChatOpening`): the row it activated goes with the sheet, and the
/// focus goes back to the History button, which says nothing of the chat.
/// Delete All Chats closes the sheet too, since nothing is left in it to look
/// at.
struct AskThreadHistorySheet: View {
    let current: AskThreadSummary?
    let history: [AskThreadSummary]
    let onOpen: (AskThreadSummary) -> Void
    let onDelete: (AskThreadSummary) -> Void
    /// Deletes every chat: the earlier ones and the one on screen.
    let onDeleteAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            AskThreadHistoryList(
                current: current,
                history: history,
                query: query,
                onOpen: { summary in
                    dismiss()
                    AskChatOpening.announce(summary)
                    onOpen(summary)
                },
                onDelete: onDelete
            )
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
    }
}

#endif
