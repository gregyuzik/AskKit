#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import SwiftUI

/// A photo waiting in the composer for the question it will go with
/// (`AskConversationStore.attachPhoto`).
nonisolated public struct AskPendingPhoto: Sendable {
    /// What the thread keeps of it.
    public let photo: AskQuestionPhoto
    /// Its pixels, which go to the model with the question and never to disk.
    public let image: CGImage
}

/// The photo waiting in the composer: its thumbnail, what it is, and the way to
/// take it back out.
///
/// **Over the composer's capsule, not in it.** The field is the composer, and
/// a thumbnail inside the capsule leaves a question room for a word: the
/// budget that keeps `AskComposerAccessory` to one button.
///
/// **Glass of its own**, beside the capsule's and never on it: it floats over
/// the thread in the composer's band the way the "Jump to latest" pill does,
/// and the thumbnail and the button sit on it as content.
///
/// **It says when the photo won't be read** (the next question runs on the
/// device, which reads no photos) before the reader sends rather than after.
/// The thread says so again under the question once it is asked.
struct AskPhotoChip: View {
    let pending: AskPendingPhoto
    let isHeldBack: Bool
    let onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// A line of the title as the text scales it, which the thumbnail grows
    /// by (`AskPhotoChipMetrics`).
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = AskPhotoChipMetrics.titleSize
    /// The remove button's glyph as the text scales it, which its target
    /// grows by.
    @ScaledMetric(relativeTo: .title3) private var removeGlyph: CGFloat = AskPhotoChipMetrics.removeGlyph

    private var thumbnail: CGFloat { AskPhotoChipMetrics.thumbnail(titleSize: titleSize) }
    private var target: CGFloat { AskPhotoChipMetrics.target(removeGlyph: removeGlyph) }

    var body: some View {
        // **At the accessibility sizes the words take a line of their own**,
        // under the thumbnail and the button. Beside them, a column of what
        // was left of a phone's width broke "attached" mid-word in English.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        thumbnailImage
                        Spacer(minLength: 0)
                        removeButton
                    }
                    words
                }
            } else {
                HStack(spacing: 10) {
                    thumbnailImage
                    words
                    removeButton
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .askGlass(.regular, in: .rect(cornerRadius: 18))
    }

    private var thumbnailImage: some View {
        Image(decorative: pending.image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: thumbnail, height: thumbnail)
            .clipShape(.rect(cornerRadius: 8))
            // A photo keeps its colors under Smart Invert, as Photos keeps
            // its own: inverted, it shows the reader a negative of what they
            // picked.
            .accessibilityIgnoresInvertColors()
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Photo attached", bundle: #bundle, comment: "Title on the chip above the Ask composer while a photo waits to go with the reader's next question. Also what VoiceOver calls a photo above a question when the app gave it no description.")
                .font(.subheadline.weight(.semibold))
            if isHeldBack {
                Text("Photos need Private Cloud Compute", bundle: #bundle, comment: "Line on the chip above the Ask composer when the next question will be answered on this device, which reads no photos. Private Cloud Compute is Apple's product name and stays in English.")
                    .font(.caption)
                    // Text to read on glass: 4.5:1 (`AskGlassForeground`).
                    .foregroundStyle(AskGlassForeground(minimum: AskGlassForeground.text))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // **Which photo, in the host's words**, since the thumbnail is
        // decorative: "Photo attached" alone left a VoiceOver reader no way to
        // tell the right one would go. The question above it reads the same
        // words (`AskQuestionBubble`).
        .accessibilityValue(Text(verbatim: pending.photo.label))
        .accessibilityIdentifier(AskAccessibility.pendingPhoto)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                // **One color, the cross cut out of the disc**, so the cross
                // shows the chip's glass through it, and what draws it is the
                // disc against that glass: the pair `AskGlassForeground`
                // holds to a glyph's 3:1. Hierarchical, the cross and the
                // disc are two strengths of one color against each other, a
                // pair the estimate doesn't see, and in `.secondary` under
                // 3:1 apart.
                .symbolRenderingMode(.monochrome)
                .frame(width: target, height: target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // On the chip's own glass, which wears no tint.
        .foregroundStyle(AskGlassForeground(minimum: AskGlassForeground.glyph))
        .accessibilityLabel(
            Text("Remove photo", bundle: #bundle, comment: "VoiceOver label for the button on the chip above the Ask composer that takes the waiting photo back out.")
        )
        .accessibilityIdentifier(AskAccessibility.removePhoto)
    }
}

/// How big the photo chip's thumbnail and remove button are, apart from the
/// view so the arithmetic can be pinned (`AskLargeTextTests`).
///
/// **Grown by what the text grows, not in proportion to it** (`AskGrowth`),
/// as the composer's circles are. In proportion, the 40 pt thumbnail and the
/// 44 pt target were 125 and 137 at the largest text size, and left the words
/// beside them about 66 pt of a phone's width.
nonisolated enum AskPhotoChipMetrics {
    /// A line of `.subheadline`, the title's style, at the default size.
    static let titleSize: CGFloat = 15
    /// The thumbnail at the default size, and the least it is at any.
    static let thumbnail: CGFloat = 40
    /// The remove button's `.title3` glyph at the default size.
    static let removeGlyph: CGFloat = 20
    /// The remove button's target at the default size, and the least it is
    /// at any: a touch target, 60 pt on visionOS, and on the Mac 28 pt, the
    /// size of the composer's circle there, whose hit region is 32.
    #if os(macOS)
    static let target: CGFloat = 28
    #else
    static let target: CGFloat = AskGrowth.touchTarget
    #endif

    static func thumbnail(titleSize scaled: CGFloat) -> CGFloat {
        AskGrowth.grown(thumbnail, glyph: titleSize, scaled: scaled)
    }

    static func target(removeGlyph scaled: CGFloat) -> CGFloat {
        AskGrowth.grown(target, glyph: removeGlyph, scaled: scaled)
    }
}

#endif
