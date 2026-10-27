#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Testing

@testable import AskUI

/// What grows with the text, and by how much: a thumb's target, the
/// composer's circles, the photo chip and a chip's corners. Each was in
/// proportion to the text, and at the largest sizes each broke a phone's
/// column.
@Suite(.timeLimit(.minutes(1))) struct AskLargeTextTests {

    // MARK: The thumbs' target

    /// At the default size the target is what it always was.
    @Test func atTheDefaultSizeAThumbsTargetIsTheMinimum() {
        #expect(AskFeedbackTarget.side(glyph: AskFeedbackTarget.glyph) == AskFeedbackTarget.minimum)
    }

    /// A larger glyph takes its growth and no more: the room round it stays
    /// what the default size leaves. In proportion, the largest size's glyph
    /// of 38 pt had a target of 140, and the pair left the evidence line
    /// beside it a character's width.
    @Test func aLargerGlyphAddsItsGrowthToTheTarget() {
        let room = AskFeedbackTarget.minimum - AskFeedbackTarget.glyph
        #expect(AskFeedbackTarget.side(glyph: 38) == 38 + room)
        #expect(AskFeedbackTarget.side(glyph: 24) == 24 + room)
    }

    /// Under the default size the glyph shrinks and the target doesn't.
    @Test func aSmallerGlyphKeepsTheMinimumTarget() {
        #expect(AskFeedbackTarget.side(glyph: 11) == AskFeedbackTarget.minimum)
    }

    // MARK: The composer's circles

    /// At the default size the circle and its target are what they always
    /// were: 34 and 44 pt, and 28 and 32 on the Mac.
    @Test func atTheDefaultSizeTheComposersCirclesAreUnchanged() {
        let widest = AskComposerMetrics.widestGlyph
        #expect(AskComposerMetrics.circle(widestGlyph: widest) == AskComposerMetrics.circle)
        #expect(AskComposerMetrics.target(widestGlyph: widest) == AskComposerMetrics.target)
        #if os(macOS)
        #expect(AskComposerMetrics.circle == 28)
        #expect(AskComposerMetrics.target == 32)
        #else
        #expect(AskComposerMetrics.circle == 34)
        #endif
    }

    /// **The circles grow by what their widest glyph grows.** At the largest
    /// size the body font is 53 pt, and the chevron that puts the keyboard
    /// away grows from 26 pt wide to 81, so the circle is 89 and the target
    /// 99. In proportion the target was about 137, and with an accessory
    /// button beside the field the two left it a few characters a line.
    @Test func theComposersCirclesGrowByTheirGlyphNotInProportion() {
        let largest = AskComposerMetrics.widestGlyph * 53 / 17
        let growth = largest - AskComposerMetrics.widestGlyph
        #expect(AskComposerMetrics.circle(widestGlyph: largest) == AskComposerMetrics.circle + growth)
        #expect(AskComposerMetrics.target(widestGlyph: largest) == AskComposerMetrics.target + growth)
        #if os(iOS)
        // The fill still holds the 81 pt chevron, and the target is well
        // under the proportional 137.
        #expect(AskComposerMetrics.circle(widestGlyph: largest) >= 81)
        #expect(AskComposerMetrics.target(widestGlyph: largest) < 100)
        #endif
    }

    /// Under the default size the glyphs shrink and the circles don't: a
    /// touch target is never less than its minimum.
    @Test func theComposersCirclesNeverShrinkUnderTheirMinimum() {
        let smallest = AskComposerMetrics.widestGlyph * 14 / 17
        #expect(AskComposerMetrics.circle(widestGlyph: smallest) == AskComposerMetrics.circle)
        #expect(AskComposerMetrics.target(widestGlyph: smallest) == AskComposerMetrics.target)
    }

    // MARK: The photo chip

    /// The thumbnail grows by what a line of its title grows, and the remove
    /// button's target by what its glyph grows. In proportion they were 125
    /// and 137 pt at the largest size, beside a column of words about 66 pt
    /// wide.
    @Test func thePhotoChipGrowsByItsTextNotInProportion() {
        #expect(AskPhotoChipMetrics.thumbnail(titleSize: AskPhotoChipMetrics.titleSize) == AskPhotoChipMetrics.thumbnail)
        #expect(AskPhotoChipMetrics.target(removeGlyph: AskPhotoChipMetrics.removeGlyph) == AskPhotoChipMetrics.target)
        // `.subheadline` is 48 pt at the largest size, and `.title3` 55.
        #expect(AskPhotoChipMetrics.thumbnail(titleSize: 48) == AskPhotoChipMetrics.thumbnail + 33)
        #expect(AskPhotoChipMetrics.target(removeGlyph: 55) == AskPhotoChipMetrics.target + 35)
        #expect(AskPhotoChipMetrics.thumbnail(titleSize: 12) == AskPhotoChipMetrics.thumbnail)
        #expect(AskPhotoChipMetrics.target(removeGlyph: 17) == AskPhotoChipMetrics.target)
    }

    // MARK: visionOS

    /// visionOS gives every touch target 60 pt, which Apple asks for there,
    /// and grows the hit region rather than the glyph: the composer's circle
    /// is iOS's 34 pt.
    @Test func visionOSTargetsAreSixtyPoints() {
        #if os(visionOS)
        #expect(AskGrowth.touchTarget == 60)
        #expect(AskFeedbackTarget.minimum == 60)
        #expect(AskComposerMetrics.target == 60)
        #expect(AskComposerMetrics.circle == 34)
        #expect(AskPhotoChipMetrics.target == 60)
        #expect(AskChipOutline.minimumHeight == 60)
        #else
        #expect(AskGrowth.touchTarget == 44)
        #expect(AskChipOutline.minimumHeight == 44)
        #endif
        // A chip takes the platform's least, as every target the screen draws.
        #expect(AskChipOutline.minimumHeight == AskGrowth.touchTarget)
    }

    // MARK: History

    /// A chat's title takes two lines, and all it needs at the accessibility
    /// sizes, where two hold a few words.
    @Test func aChatsTitleWrapsInFullAtTheAccessibilitySizes() {
        #expect(AskChatRowLabel.titleLineLimit(isAccessibilitySize: false) == 2)
        #expect(AskChatRowLabel.titleLineLimit(isAccessibilitySize: true) == nil)
    }

    // MARK: A chip's corners

    /// While a line of words is shorter than the minimum height, a chip one
    /// line tall is that height, and its corners are half of it: a capsule.
    @Test func aChipsCornersAreHalfTheMinimumHeightWhileALineIsShorter() {
        #expect(AskChipOutline.radius(line: AskChipOutline.line) == AskChipOutline.minimumHeight / 2)
        #expect(AskChipOutline.radius(line: 43) == AskChipOutline.minimumHeight / 2)
    }

    /// Once a line is taller than the minimum height, the corners are half
    /// the line: still a capsule round one line, and never half of three.
    @Test func aChipsCornersAreHalfATallerLine() {
        #expect(AskChipOutline.radius(line: 60) == 30)
    }
}

#endif
