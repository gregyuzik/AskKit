#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import SwiftUI

/// The reader's own question, trailing.
///
/// **Content-sized, never full-width.** A `Spacer(minLength: 48)` before it
/// keeps a short question short, so the thread reads as an exchange rather than
/// as two columns of blocks.
///
/// **The turn's long-press menu lives here and nowhere else.** Its actions
/// (Copy, Copy answer, Edit & Resend, Ask again) hang off the thing that is
/// unambiguously the reader's: their question. The answer's prose has no menu
/// of its own, and on iOS a long press on it reaches neither a menu nor a
/// selection (`AskAnswerProse`), so "Copy answer" here is how a reader takes an
/// answer's words. VoiceOver reaches the same four as the bubble's actions,
/// and Copy answer as an action of the prose's as well.
///
/// **A photo the question went with sits above it**, trailing like the words:
/// the pixels while this process has them, the host's thumbnail for a thread
/// read back from disk (`AskDomain.photoThumbnail(for:)`), a glyph where there
/// is neither. The frame is the same in each case, so a thumbnail that arrives
/// late moves nothing under it.
struct AskQuestionBubble: View {
    private let question: String
    private let accent: Color
    /// Set only on a turn a chip could have just become, so the tapped chip
    /// travels here rather than vanishing while this appears. `AskChipMorph`
    /// carries why it is keyed on the question's own text.
    private let morph: Namespace.ID?
    private let photo: AskQuestionPhoto?
    private let photoImage: CGImage?
    private let photoThumbnail: (@Sendable (AskQuestionPhoto) async -> CGImage?)?
    private let onCopy: () -> Void
    private let onCopyAnswer: (() -> Void)?
    private let onEdit: () -> Void
    private let onAskAgain: () -> Void

    init(
        question: String,
        accent: Color,
        morph: Namespace.ID? = nil,
        photo: AskQuestionPhoto? = nil,
        photoImage: CGImage? = nil,
        photoThumbnail: (@Sendable (AskQuestionPhoto) async -> CGImage?)? = nil,
        onCopy: @escaping () -> Void,
        onCopyAnswer: (() -> Void)? = nil,
        onEdit: @escaping () -> Void,
        onAskAgain: @escaping () -> Void
    ) {
        self.question = question
        self.accent = accent
        self.morph = morph
        self.photo = photo
        self.photoImage = photoImage
        self.photoThumbnail = photoThumbnail
        self.onCopy = onCopy
        self.onCopyAnswer = onCopyAnswer
        self.onEdit = onEdit
        self.onAskAgain = onAskAgain
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let photo {
                HStack {
                    Spacer(minLength: 48)
                    AskQuestionPhotoView(photo: photo, image: photoImage, thumbnail: photoThumbnail)
                }
            }
            bubble
        }
    }

    private var bubble: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 48)
            Text(question)
                .font(.body)
                // Selectable and menu-bearing. On iOS 27 `textSelection` is
                // system selection rather than a callout menu, so whether a
                // long press reaches the menu is the system's decision.
                // Measured on an iPhone 17 Pro simulator with SDK 27, it does.
                // The demo's `testTheQuestionBubblesContextMenuIsReachable`
                // keeps measuring it, because Copy, Copy answer, Edit & Resend
                // and Ask again reach a reader's touch through this menu and
                // nowhere else in AskUI; VoiceOver has them as actions too
                // (below).
                .textSelection(.enabled)
                // Black or white on the fill as contrast decides, not always
                // `.primary` (`AskOnFill`).
                .foregroundStyle(AskOnFill(fill: fill))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // **A fill of the accent, not glass.** A question is content,
                // and glass belongs to the navigation layer: as the thread
                // scrolled, every bubble passing under the navigation bar was
                // glass under glass, an accent-colored question ghosting in
                // the bar's own glass (ARCHITECTURE.md, Rejected designs, the
                // `.hard` top edge). visionOS has no Liquid Glass to keep off
                // content, and its `askGlass` is already a faint fill on the
                // window's glass, so it keeps that.
                #if os(visionOS)
                .askGlass(.tint(fill), in: .rect(cornerRadius: Self.corner))
                #else
                .background(fill, in: .rect(cornerRadius: Self.corner))
                // The lifted preview takes the bubble's corners rather than
                // the system's rounded rectangle round its words. A Mac menu
                // lifts no preview, and the kind doesn't exist there.
                #if !os(macOS)
                .contentShape(.contextMenuPreview, .rect(cornerRadius: Self.corner))
                #endif
                #endif
                .contextMenu {
                    Button {
                        onCopy()
                    } label: {
                        Label {
                            Self.copyTitle
                        } icon: {
                            Image(systemName: "document.on.document")
                        }
                    }
                    .accessibilityIdentifier(AskAccessibility.questionCopy)
                    // **Optional, and nil is a real state.** A turn with no
                    // prose yet (waiting for its first word, stopped before
                    // it, failed outright) has nothing to put on the
                    // clipboard, and an item that copies an empty string is
                    // worse than no item. On iOS a long press on the answer's
                    // own prose reaches no selection (`AskAnswerProse`), so
                    // without this item the one thing a reader most wants to
                    // keep would be the one thing they couldn't take.
                    if let onCopyAnswer {
                        Button {
                            onCopyAnswer()
                        } label: {
                            Label {
                                Self.copyAnswerTitle
                            } icon: {
                                Image(systemName: "document.on.clipboard")
                            }
                        }
                        .accessibilityIdentifier(AskAccessibility.questionCopyAnswer)
                    }
                    Button {
                        onEdit()
                    } label: {
                        Label {
                            Self.editTitle
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    .accessibilityIdentifier(AskAccessibility.questionEdit)
                    Button {
                        onAskAgain()
                    } label: {
                        Label {
                            Self.askAgainTitle
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityIdentifier(AskAccessibility.questionAskAgain)
                }
                // Menu-item icons are hidden by default on iPadOS 27 and in
                // macOS 27 context menus, so the items' symbols would vanish
                // on iPad and the Mac while the phone kept them. Opting back
                // in makes the code and what renders agree.
                .labelStyle(.titleAndIcon)
                // On the bubble itself and not on the `HStack`, so the geometry
                // that travels is the capsule's. The stack is full width with a
                // `Spacer` holding the bubble trailing, so matching it would
                // fly the chip to the leading edge and stretch it across the
                // column on the way.
                .askChipMorph(question, in: morph)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.yourQuestion)
        .accessibilityValue(question)
        // **Voice Control reaches a question by its own words.** By the label
        // alone, every bubble and the composer's field were "Your question",
        // and "Tap" or "Long press" with the words on screen matched nothing.
        // The question's opening words lead, so Voice Control shows them as
        // its name, then the whole question and "Your question".
        .accessibilityInputLabels(AskSpokenName.inputLabels(showing: question, named: Self.yourQuestion))
        // **A heading, so VoiceOver's headings rotor moves a turn at a time.**
        // Each turn starts with its question, and without it a long thread
        // could only be swiped through element by element.
        .accessibilityAddTraits(.isHeader)
        // **The menu's items as actions of their own.** The bubble is one
        // combined element, and a long press isn't a gesture every reader can
        // make, so the turn's actions are reached through VoiceOver's actions
        // too, as `AskChipRow`'s "Don't suggest this" is.
        .accessibilityActions {
            Button(action: onCopy) { Self.copyTitle }
            if let onCopyAnswer {
                Button(action: onCopyAnswer) { Self.copyAnswerTitle }
            }
            Button(action: onEdit) { Self.editTitle }
            Button(action: onAskAgain) { Self.askAgainTitle }
        }
        .accessibilityIdentifier(AskAccessibility.question)
    }

    /// How strongly the bubble wears the accent. The composer's capsule wears
    /// it at half, or less on a light accent in dark mode (`AskComposer`).
    static let fillOpacity = 0.6

    private static let corner: CGFloat = 20

    /// The bubble's fill: the accent at `fillOpacity`.
    private var fill: Color {
        accent.opacity(Self.fillOpacity)
    }

    private static var yourQuestion: Text {
        Text("Your question", bundle: #bundle, comment: "VoiceOver label for the reader's own question in the Ask thread.")
    }

    // One spelling of each item, for the menu and its VoiceOver action.

    private static var copyTitle: Text {
        Text("Copy", bundle: #bundle, comment: "Menu item that copies the reader's own Ask question to the clipboard.")
    }

    /// Also the prose's VoiceOver action (`AskAnswerProse`).
    static var copyAnswerTitle: Text {
        Text("Copy answer", bundle: #bundle, comment: "Menu item that copies the answer to the reader's Ask question to the clipboard.")
    }

    private static var editTitle: Text {
        Text("Edit & Resend", bundle: #bundle, comment: "Menu item that puts the reader's Ask question back in the composer to change and send again.")
    }

    private static var askAgainTitle: Text {
        Text("Ask again", bundle: #bundle, comment: "Menu item that asks the same Ask question over, for a different answer.")
    }
}

/// The photo above a question: content, so a clipped image and no glass.
///
/// Its own VoiceOver stop, beside the question's rather than combined with it,
/// read as an image by the host's words for it.
private struct AskQuestionPhotoView: View {
    let photo: AskQuestionPhoto
    let image: CGImage?
    let thumbnail: (@Sendable (AskQuestionPhoto) async -> CGImage?)?

    /// What the host drew for a photo this process has no pixels for.
    @State private var loaded: CGImage?
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 120

    var body: some View {
        // A photo read back with its thread lands after the bubble is drawn,
        // so it comes into focus rather than popping over the symbol.
        AskPictureArrival(image ?? loaded) { shown in
            Image(decorative: shown, scale: 1)
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.fill.tertiary)
        }
        // Capped, so the largest text sizes grow the photo without letting it
        // take the column from the question under it.
        .frame(width: min(side, 220), height: min(side, 220))
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(AskAccessibility.questionPhoto)
        .task(id: photo) {
            guard image == nil, loaded == nil, let thumbnail else { return }
            loaded = await thumbnail(photo)
        }
    }

    private var label: Text {
        photo.label.isEmpty
            ? Text("Photo attached", bundle: #bundle, comment: "Title on the chip above the Ask composer while a photo waits to go with the reader's next question. Also what VoiceOver calls a photo above a question when the app gave it no description.")
            : Text(verbatim: photo.label)
    }
}

#endif
