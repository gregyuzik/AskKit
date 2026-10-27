#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// The banner over the first screen when the chat saved last time couldn't be
/// read, so an empty screen where the reader's chat used to be says why.
///
/// It says the chat was kept and comes back if it can be read later, which is
/// true either way, short of Delete All Chats. It doesn't say where the chat
/// comes back, because that differs. Bytes this build can't decode, or a
/// thread none of whose turns decode, are set aside whole, and a later launch
/// that can read them files them with the earlier chats. A thread that
/// couldn't be read at all, such as on a locked device, stays where it is,
/// never deleted, until New Chat sets it aside to be filed the same way. Read
/// again before that, as protected data comes back, as the screen does or on
/// a relaunch, it comes back as the chat on screen, above anything asked
/// meanwhile.
struct AskUnreadableThreadBanner: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(.secondary)
                // Combined below into one element, so an unhidden glyph would
                // prepend its name to the sentence VoiceOver reads.
                .accessibilityHidden(true)
            Text(
                "Your last chat couldn't be opened. It's been kept, and will come back if it can be read later.",
                bundle: #bundle,
                comment: "Banner over the empty Ask screen when the chat saved on the device could not be read on this launch."
            )
            .font(.footnote)
            // Text to read on glass: 4.5:1 (`AskGlassForeground`).
            .foregroundStyle(AskGlassForeground(minimum: AskGlassForeground.text))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .askGlass(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

#endif
