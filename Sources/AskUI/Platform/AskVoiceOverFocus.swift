#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// Where `AskScreen` sends VoiceOver's focus after a tap that takes away the
/// element that had it: New Chat takes the thread, and Edit & Resend puts the
/// reader back in the composer from a menu that closes.
///
/// **A request the element takes as it can, not a focus set from the
/// screen.** The element is often not on screen yet when the reader taps (the
/// first screen comes in as the thread goes), and a focus set on an element
/// that isn't in the accessibility tree goes nowhere. So the screen leaves the
/// request in its state, and the element it names takes it once it is there
/// and clears it, from a task as `AskThinkingRow` takes the wait row's focus.
/// Not watched under VoiceOver: no simulator runs it.
nonisolated enum AskVoiceOverTarget: Equatable {
    /// The first screen's headline, after New Chat, or the composer's field
    /// where the first screen draws none: the two that can't serve and the
    /// one with nothing to ask about have no headline, and a window too short
    /// for the ready screen's while it makes room lets it go
    /// (`AskFirstScreen.keepsMarkAndHeadline`).
    case headline
    /// The composer's field, after Edit & Resend or a tap on the face in a
    /// host's slot.
    case field
}

extension EnvironmentValues {
    /// The screen's request for VoiceOver's focus (`AskVoiceOverTarget`),
    /// handed to the first screen and to the composer. Nil outside
    /// `AskScreen`, and on the composer while it rests in a host's slot,
    /// hidden from VoiceOver, until it comes up.
    @Entry var askVoiceOverTarget: Binding<AskVoiceOverTarget?>?
}

#endif
