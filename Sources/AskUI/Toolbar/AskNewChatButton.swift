#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// New Chat, in the toolbar where a chat app keeps it.
///
/// **`.symbolRenderingMode(.monochrome)` is load-bearing.** Without it a
/// `Label`'s icon renders black on glass: a toolbar button that disappears
/// against a light background and reads as a smudge against a dark one.
public struct AskNewChatButton: View {
    private let isEnabled: Bool
    private let action: () -> Void
    /// Bumped by this button's own action, so the haptic fires on the tap.
    @State private var taps = 0

    /// Creates the button, with ⇧⌘N as its shortcut, as `AskCommands` has.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the button can be tapped, such as while the
    ///     thread has a turn (`store.hasTurns`).
    ///   - action: What a tap does, such as starting the thread over.
    public init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Label {
                Text("New Chat", bundle: #bundle, comment: "Toolbar button, and the Mac menu item, shortcut ⇧⌘N, that ends the Ask conversation and starts an empty one.")
            } icon: {
                Image(systemName: "square.and.pencil")
            }
        }
        .symbolRenderingMode(.monochrome)
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(!isEnabled)
        // Triggered on the tap, not on `isEnabled`. Keyed to enablement, it
        // would fire on two events that aren't interactions with this button
        // at all: the reader asking their first question, and
        // `restoreIfNeeded()` repopulating the thread at launch.
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityIdentifier(AskAccessibility.newChat)
    }
}

#endif
