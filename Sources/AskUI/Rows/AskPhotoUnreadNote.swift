#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The line under a question asked with a photo when the answer read only its
/// words: the tier answering reads no photos, or the app answered without a
/// model (`AskTurn.answeredWithoutPhoto`).
///
/// **Under the question and trailing, with it.** It says something about what
/// the reader sent, the way Messages says a message wasn't delivered, so it
/// sits with the bubble rather than with the answer. It appears no later than
/// the answer does, so nothing under it moves when it arrives.
///
/// **One sentence for every cause.** After a hand-down the photo did reach
/// Private Cloud Compute, and the answer on screen still isn't the one that
/// saw it, so the line says what the answer read, never whether the photo was
/// sent.
struct AskPhotoUnreadNote: View {
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text("This answer read your words only.", bundle: #bundle, comment: "Note under a question the reader asked with a photo, when the answer came from a model that did not see the photo: the on-device model, which reads no photos, or the app answering on its own.")
                .font(.caption)
                .askDeemphasizedText()
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AskAccessibility.photoUnread)
    }
}

#endif
