#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// The measures the Ask screen is laid out to: the reading width, how many
/// starters the first screen offers, and the columns of a bank of tiles.
nonisolated public enum AskLayout {
    /// The widest a line of answer prose is allowed to get, in points.
    ///
    /// **A phone can't show you this, and a 13-inch iPad can.** Unconstrained,
    /// the thread fills the window: on an iPad Pro in portrait that is a
    /// thousand points of body text on one line, about double a comfortable
    /// measure, and it reads as a wall. A Mac window goes wider still. The
    /// first screen's stacked column is capped too, at 460.
    ///
    /// The composer is capped with it. A send button a thousand points from
    /// the last word you read belongs to a different screen.
    public static let readingWidth: CGFloat = 680

    /// How many starter chips the first screen offers: 3 on iPhone and iPad,
    /// and 8 on the Mac and Apple Vision Pro. The store asks the domain for
    /// this many (the `window` of `AskDomain.starters(overview:window:)`).
    ///
    /// **Three is a phone's number.** The first screen is capped at 460 pt and
    /// centered, so three chips in a Mac window or on Apple Vision Pro are a
    /// short column adrift in an empty one, and the screen reads as unfinished
    /// rather than uncluttered: it is the first thing a reader sees. Eight
    /// fills the same column without widening anything or moving the
    /// composer, because `AskChipFlow` wraps: the bank grows downward into
    /// space that was already blank.
    ///
    /// **Platform, not size class.** `.regular` is every iPad as well, and an
    /// iPad isn't what is sparse here: its window is close enough to a phone's
    /// that three still reads as a considered offer.
    ///
    /// A ceiling, not a quota. A host whose domain has fewer questions to ask
    /// shows fewer, and no filler is invented to reach the number.
    public static var starterBank: Int {
        #if os(macOS) || os(visionOS)
        8
        #else
        3
        #endif
    }

    /// The columns a bank of tiles is laid out in, `AskTileGrid`'s unless a
    /// bank brings its own, sized by how many tiles there are, the way
    /// Messages lays out photos: one stands alone, two sit side by side a
    /// little smaller, and three or more fall into a grid, four across on a
    /// phone.
    ///
    /// **A bank of tiles is the same object in every host**, the pictures the
    /// answer stood on, so the arrangement is AskKit's and only the tile is
    /// the host's, which is the split `AskItemOpenAction` already draws.
    ///
    /// **Every layout is capped short of the width it could have.** A tile is
    /// what the sentence above it stood on, not the answer's hero. At 240 of
    /// a phone's 366 pt, a solo tile pushes the evidence line and the next
    /// question off the bottom. The maxima hold a solo tile at 160 and a pair
    /// at 140 on every phone, so the trailing slack is deliberate: the tiles
    /// align with the prose rather than stretch to meet the margin.
    ///
    /// **Those maxima bound height, so a portrait bank narrows.** What pushes
    /// the evidence line off the bottom is a vertical number, and a tile is
    /// only as tall as it is wide while it is square. A 2:3 tile at the solo
    /// 160 would stand 240 pt, the height the cap exists to stop, so the two
    /// wide layouts scale by `tallestAspect` (width over height of the bank's
    /// narrowest tile), holding the height and spending the difference on
    /// width. The narrowest, because every column is one width and a mixed
    /// pair is sized by its taller half. Nothing wider than square scales up,
    /// and the grid case never scales: its tiles are too small for their
    /// height to be at risk, and its minimum is what chooses the column count,
    /// so a phone would go from four across to five.
    ///
    /// The minima choose the count, and the maxima stop the chosen columns
    /// from growing into the leftover: at a phone's measure the grid case
    /// fits four, about 85 pt each. Pass `spacing` matching the grid's own.
    ///
    /// **Narrowed no further than for a tile twice as tall as it is wide.**
    /// Held to the cap's height, a taller tile is a sliver, and an aspect of
    /// zero or less, which a host can pass, would scale the columns to
    /// nothing: a bank of 0 pt columns draws nothing at all. An aspect that isn't a
    /// finite number counts as square.
    public static func tileColumns(for count: Int, tallestAspect: CGFloat = 1, spacing: CGFloat = 8) -> AskTileColumns {
        let scale = tallestAspect.isFinite ? min(1, max(narrowestAspect, tallestAspect)) : 1
        return switch count {
        case 1: .adaptive(minimum: 150 * scale, maximum: 160 * scale, spacing: spacing)
        case 2: .adaptive(minimum: 130 * scale, maximum: 140 * scale, spacing: spacing)
        default: .adaptive(minimum: 76, maximum: 100, spacing: spacing)
        }
    }

    /// The narrowest aspect `tileColumns(for:tallestAspect:spacing:)` narrows
    /// a bank for: a tile twice as tall as it is wide.
    static let narrowestAspect: CGFloat = 0.5
}

/// How a control's frame grows with the text: **by what its glyph grows, not
/// in proportion to it.** In proportion, the room the default size leaves
/// around a glyph is multiplied with the glyph, and at the largest text sizes
/// a pair of targets takes a phone's column: the thumbs (`AskFeedbackTarget`)
/// and the composer's circles (`AskComposerMetrics`) both did. Grown by the
/// glyph's own growth, the room stays what the default size gave it.
nonisolated enum AskGrowth {
    /// `base` at the default text size, grown by however much the glyph grew
    /// from `glyph` to `scaled`, and never less than `base`: under the default
    /// size the glyph shrinks and the frame doesn't.
    static func grown(_ base: CGFloat, glyph: CGFloat, scaled: CGFloat) -> CGFloat {
        max(base, base + (scaled - glyph))
    }

    /// The least a touch target is: 44 pt, and 60 on visionOS, where Apple
    /// asks for 60 pt around an element's center for eyes and hands to land
    /// on. The Mac has no touch, and each control there keeps a size of its
    /// own.
    static var touchTarget: CGFloat {
        #if os(visionOS)
        60
        #else
        44
        #endif
    }
}

/// Two localized sentences as one string, in a fixed order.
///
/// **A space between them, except after a full-width sentence end.** Japanese
/// and Chinese end a sentence with a full-width mark (。！？), which carries
/// its own space, and run the next sentence on without one: an ASCII space
/// after it is a stray gap mid-line. Every other script AskKit ships ends a
/// sentence with a mark that wants the space, or, in Thai, with the space
/// itself. One helper, so every place that joins two sentences joins them
/// the same way.
nonisolated enum AskSentences {
    /// The marks that end a sentence and carry their own space: the
    /// ideographic full stop, the full-width exclamation and question marks,
    /// the full-width full stop and the halfwidth ideographic one.
    private static let fullWidthEnds: Set<Character> = ["\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF0E}", "\u{FF61}"]

    /// `first` and `second` as one string, `first` first. An empty sentence
    /// adds nothing, and no space.
    static func joined(_ first: String, _ second: String) -> String {
        guard !first.isEmpty else { return second }
        guard !second.isEmpty else { return first }
        let carriesItsSpace = first.last.map(fullWidthEnds.contains) ?? false
        return carriesItsSpace ? first + second : first + " " + second
    }
}

extension View {
    /// Centers this in the available width, no wider than the reading measure
    /// (`AskLayout.readingWidth`).
    public func askReadingColumn() -> some View {
        frame(maxWidth: AskLayout.readingWidth)
            .frame(maxWidth: .infinity)
    }
}

#endif
