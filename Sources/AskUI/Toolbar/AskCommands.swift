#if os(macOS)

import AskCore
import SwiftUI

/// New Chat, Send and Stop in the Mac menu bar.
///
/// A Mac app's File menu is where a new-anything belongs, and a toolbar
/// button alone leaves ⇧⌘N working only while the window has focus, and the
/// shortcut undiscoverable otherwise. AskUI ships the item rather than leaving
/// it to each host, so every host has the same item, in the same place, with
/// the same shortcut.
///
/// Attach it beside the scene:
///
/// ```swift
/// WindowGroup { AskScreen(store: store) }
///     .commands { AskCommands(store: store) }
/// ```
///
/// That is `AskCommands(isEnabled: store.hasTurns) { store.startOver() }`,
/// the spelling for a host whose New Chat does more than start over.
///
/// **`hasTurns`, not `!turns.isEmpty`.** This is read in the scene's body,
/// and `turns` changes with every streamed snapshot, so reading it there runs
/// the scene's body again for every word an answer writes. `hasTurns` changes
/// only when the thread goes from empty to not and back.
///
/// `.newItem` is the standard placement: it puts the item under File, above
/// the separator, where ⌘N's neighbors live. The shortcut matches
/// `AskNewChatButton` exactly, since a menu item and a toolbar button that
/// disagree about their key equivalent are worse than either alone.
///
/// **Send and Stop beside it**, with the composer's own ⌘Return and ⌘., so
/// the two shortcuts are in a menu where a reader can find them. They act on
/// the composer in the focused window, which hands them up as it draws
/// (`AskComposerCommand`), so neither init needs more than it takes. What it
/// hands up changes only when Send or Stop turns on or off: as the reader
/// types, on the first character and the last one deleted, and as a turn
/// starts and ends, so the menu's body runs then and not with every
/// keystroke. Send is enabled while that composer has a question and no turn
/// in flight, and Stop while a turn is in flight; with no Ask window focused,
/// both are disabled.
public struct AskCommands: Commands {
    private let isEnabled: Bool
    private let action: () -> Void

    /// The focused window's composer, if it has one.
    @FocusedValue(\.askComposer) private var composer

    /// Creates New Chat with an action of the host's own.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the item can be chosen. Pass `store.hasTurns`,
    ///     read in the scene's body, rather than anything read from `turns`.
    ///   - action: What choosing the item, or pressing ⇧⌘N, does.
    public init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    /// Creates New Chat for `store`: enabled while its thread has a turn, and
    /// starting the thread over when chosen.
    ///
    /// Build it in the scene's body, so the scene reads `hasTurns` and builds
    /// the item again when it changes.
    ///
    /// - Parameter store: The store whose thread the item starts over.
    public init<Domain: AskDomain>(store: AskConversationStore<Domain>) {
        self.init(isEnabled: store.hasTurns) { store.startOver() }
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                action()
            } label: {
                Text("New Chat", bundle: #bundle, comment: "Toolbar button, and the Mac menu item, shortcut ⇧⌘N, that ends the Ask conversation and starts an empty one.")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!isEnabled)
            Divider()
            Button {
                composer?.send()
            } label: {
                Text("Send", bundle: #bundle, comment: "VoiceOver label for the Ask composer's send button; and the Mac menu item, shortcut ⌘↩, that sends the question.")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(composer?.sends != true)
            Button {
                composer?.stop()
            } label: {
                AskComposerWords.stop
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(composer?.stops != true)
        }
    }
}

#endif
