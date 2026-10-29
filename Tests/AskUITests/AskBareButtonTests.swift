#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import SwiftUI
import Testing

@testable import AskUI

/// What AskKit's bare buttons say they are where the platform asks
/// (`AskBareButton.swift`): the words of the Mac's help tags, and the ring
/// Button Shapes draws round a glyph.
///
/// **Not the light.** The hover effect is visionOS's and the iPad pointer's,
/// drawn by the system, and nothing in a test process shows it; the help tag
/// is drawn by AppKit as the pointer rests. What a test can pin is the words
/// each tag shows and the ring a render draws.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskBareButtonTests {
    // MARK: The help tags' words

    /// **A help tag is its button's accessibility label, from AskUI's own
    /// catalog.** `Text` compares its bundle, so a tag looked up in the host's
    /// main bundle, which shows the English key in every language, isn't
    /// equal to one looked up in AskUI's (`#bundle`).
    @Test func theThumbsTagsAreTheirLabelsFromAskUIsCatalog() {
        #expect(AskFeedbackButtons.label(for: .positive) == Text("Helpful", bundle: .module))
        #expect(AskFeedbackButtons.label(for: .negative) == Text("Not helpful", bundle: .module))
        #expect(AskFeedbackButtons.label(for: .positive) != Text("Helpful", bundle: .main))
    }

    /// The send circle's tag says what a click on it does now, in the words
    /// VoiceOver reads for each state.
    @Test func theSendCirclesTagFollowsWhatItDoes() {
        #expect(AskComposer.buttonLabel(isThinking: false, dismissesKeyboard: false, hasQuestion: true) == Text("Send", bundle: .module))
        #expect(AskComposer.buttonLabel(isThinking: false, dismissesKeyboard: false, hasQuestion: false) == Text("Write a question", bundle: .module))
        #expect(AskComposer.buttonLabel(isThinking: true, dismissesKeyboard: false, hasQuestion: true) == Text("Cancel", bundle: .module))
        #expect(AskComposer.buttonLabel(isThinking: false, dismissesKeyboard: true, hasQuestion: false) == Text("Dismiss keyboard", bundle: .module))
        #expect(AskComposer.buttonLabel(isThinking: false, dismissesKeyboard: false, hasQuestion: true) != Text("Send", bundle: .main))
    }

    /// The photo chip's Remove, and the photo button, which is the accessory
    /// button whose words are AskKit's rather than the host's.
    @Test func theRemoveAndPhotoTagsAreFromAskUIsCatalog() {
        #expect(AskPhotoChip.removeLabel == Text("Remove photo", bundle: .module))
        #expect(AskComposerAccessory.photo {}.label == Text("Add a photo", bundle: .module))
        #expect(AskPhotoChip.removeLabel != Text("Remove photo", bundle: .main))
    }

    /// The chats pane's trash, a glyph alone, is tagged in the words its
    /// button and the dialog it opens say.
    @Test func theChatsPanesTrashTagIsDeleteAllChatsFromAskUIsCatalog() {
        #expect(AskDeleteAllChatsButton.title == Text("Delete All Chats", bundle: .module))
        #expect(AskDeleteAllChatsButton.title != Text("Delete All Chats", bundle: .main))
    }

    // MARK: Button Shapes

    /// **The ring is drawn only while Button Shapes is on**, round the frame
    /// it is given, and leaves the glyph's middle alone. Off, nothing at all
    /// is drawn: the ring is there, at no opacity, so the setting changing
    /// never changes the button's identity.
    @Test func theRingShowsOnlyUnderButtonShapes() throws {
        let on = try #require(render(ringed(showsBorders: true)))
        let off = try #require(render(ringed(showsBorders: false)))

        #expect(alpha(in: on, x: 20, y: 0) > 0.5, "the ring's top")
        #expect(alpha(in: on, x: 0, y: 20) > 0.5, "the ring's leading edge")
        #expect(alpha(in: on, x: 20, y: 20) == 0, "the middle, where the glyph is")
        for (x, y) in [(20, 0), (0, 20), (20, 20), (39, 20)] {
            #expect(alpha(in: off, x: x, y: y) == 0, "(\(x), \(y)) with Button Shapes off")
        }
    }

    /// Words are underlined while Button Shapes is on, and not otherwise:
    /// the evidence line's and the face's line's.
    @Test func wordsAreUnderlinedOnlyUnderButtonShapes() {
        #expect(AskBareButtonShape.underlines(showsBorders: true))
        #expect(!AskBareButtonShape.underlines(showsBorders: false))
        #expect(AskBareButtonShape.ringOpacity(showsBorders: true) == 1)
        #expect(AskBareButtonShape.ringOpacity(showsBorders: false) == 0)
    }

    private func ringed(showsBorders: Bool) -> some View {
        Color.clear
            .frame(width: 40, height: 40)
            .askButtonShapeRing(.circle, showsBorders: showsBorders)
            .foregroundStyle(.black)
    }

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 40, height: 40)
        return renderer.cgImage
    }

    /// The opacity of the pixel at `x`, `y`, from the top leading corner.
    private func alpha(in image: CGImage, x: Int, y: Int) -> Double {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            // `unsafe`: the context draws into `pixel`'s four bytes, and only inside this closure.
            guard let context = unsafe CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The image drawn so its pixel at (x, y) lands on the context's
            // one pixel: Core Graphics counts up from the bottom.
            context.draw(image, in: CGRect(
                x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height
            ))
            return true
        }
        return drawn ? Double(pixel[3]) / 255 : -1
    }
}

#endif
