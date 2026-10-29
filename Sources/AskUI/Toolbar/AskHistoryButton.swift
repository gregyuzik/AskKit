#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// The reader's earlier chats, beside New Chat: the way back to a chat New
/// Chat put away.
///
/// `AskScreen` offers it only on a domain that keeps its chats
/// (`AskConversationStore.offersHistory`). Monochrome for the reason
/// `AskNewChatButton` gives: without it, a `Label`'s icon renders black on
/// glass.
public struct AskHistoryButton: View {
    private let action: () -> Void

    /// Creates the button.
    ///
    /// - Parameter action: What a tap does. `AskScreen` loads the earlier
    ///   chats and presents a list of its own. A host's own list loads them
    ///   with `AskConversationStore.loadHistory()`, reads `history`, and opens
    ///   or deletes one with `openThread(_:)` or `deleteThread(_:)`.
    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
        }
        .symbolRenderingMode(.monochrome)
        // What Voice Control answers to: the label, and "History", what a
        // clock in a bar is called.
        .accessibilityInputLabels([
            title,
            Text("History", bundle: #bundle, comment: "Voice Control name for the toolbar button that lists the reader's earlier Ask chats, beside its label 'Earlier chats'.")
        ])
        .accessibilityIdentifier(AskAccessibility.history)
    }

    private var title: Text {
        Text("Earlier chats", bundle: #bundle, comment: "The reader's earlier Ask chats: the toolbar button that lists them, and the heading above them in that list.")
    }
}

/// Whether the screen's bar has the History item, decided apart from the
/// screen so the cases can be pinned (`AskHistoryItemTests`).
///
/// **Only on a domain that keeps its chats, and not while they are on screen**
/// in the pane beside iPhone Duo's fold: the button would open a second copy
/// of the list beside them.
///
/// **Not while the reader types with the bars in iPhone Duo's strip.** The
/// strip is laid out against the keyboard's frame, and the keyboard's
/// predictive bar stands above that frame, over the strip's foot. History is
/// the strip's last item, so on the closed Duo upright the predictive bar
/// covered its lower third: the strip began its items at y 418, and the
/// predictive bar began at about 374. The list is a way back, and a reader
/// mid-question has Done to put the keyboard away first. A bar along the top
/// is nowhere near the keyboard, and keeps the item.
nonisolated enum AskHistoryItem {
    static func shows(offersHistory: Bool, listsChats: Bool, isTyping: Bool, barsAreInStrip: Bool) -> Bool {
        guard offersHistory, !listsChats else { return false }
        return !(isTyping && barsAreInStrip)
    }
}

#endif
