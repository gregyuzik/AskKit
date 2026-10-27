#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// The columns a bank of tiles is laid out in: as many as fit at `minimum`
/// wide with `spacing` between them, each grown to share the width, and none
/// wider than `maximum`.
///
/// `GridItem.adaptive`'s arithmetic, as a type of its own because the bank
/// isn't a `LazyVGrid` (`AskTileGrid` lays it out), and `[GridItem]` can say
/// things (fixed columns, flexible ones, a mix of the two) that this layout
/// doesn't do. Measured against a `LazyVGrid` of one adaptive item at widths from 120
/// to 680 pt: the column count, the widths and the slack left at the trailing
/// edge agree.
nonisolated public struct AskTileColumns: Equatable, Sendable {
    /// The narrowest a column may be, which decides how many fit.
    public var minimum: CGFloat
    /// The widest a column grows, however much width is left over.
    public var maximum: CGFloat
    /// Between columns.
    public var spacing: CGFloat

    /// Columns at least `minimum` and at most `maximum` wide, with `spacing`
    /// between them.
    public init(minimum: CGFloat, maximum: CGFloat, spacing: CGFloat = 8) {
        self.minimum = minimum
        self.maximum = maximum
        self.spacing = spacing
    }

    /// As many columns as fit at `minimum`, none wider than `maximum`.
    public static func adaptive(minimum: CGFloat, maximum: CGFloat, spacing: CGFloat = 8) -> AskTileColumns {
        AskTileColumns(minimum: minimum, maximum: maximum, spacing: spacing)
    }

    /// How many columns `width` holds, and how wide each one is.
    ///
    /// The count comes from the minimum alone, never from how many tiles there
    /// are: seven tiles in a width that holds eight columns leave the eighth
    /// empty rather than growing into it. A width too narrow for one column at
    /// the minimum gets one column as wide as the width. An unbounded width
    /// holds every tile in one row at the maximum, which is the honest answer
    /// to a probe asking how wide the bank could be.
    public func fit(in width: CGFloat) -> (count: Int, width: CGFloat) {
        guard width.isFinite else { return (.max, maximum) }
        let pitch = minimum + spacing
        // A hair of tolerance, so a width that holds its last column exactly is
        // not lost to the division's rounding.
        let fitting = pitch > 0 ? ((width + spacing) / pitch + 1e-6).rounded(.down) : 1
        let count = max(1, Int(min(fitting, 10_000)))
        let share = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        return (count, max(0, min(maximum, share)))
    }
}

/// `AskTileGrid`'s arrangement: tiles in `AskTileColumns`, in rows as tall as
/// their tallest tile, built with the rest of the answer rather than as they
/// scroll into view.
///
/// **Not a `LazyVGrid`, because a lazy grid builds a tile when it scrolls into
/// view, and the thread scrolls a settled answer's tiles in after everything
/// beneath them.** While an answer streams, the follow keeps the thread's foot
/// above the composer, so in a thread taller than the screen the bank lands
/// below the bottom edge with the lines and cards under it, and the follow
/// brings them up a moment later. Those pieces are built at once and start
/// their arrival off screen. A lazy grid would build its tiles only as they
/// scrolled in, so the evidence line and the card beneath a bank would already
/// have come up out of their blur while the bank above them was empty space,
/// and the tiles would arrive last, into the hole. A bank is at most
/// `AskAnswer.maxTiles` tiles, so laziness has nothing to save.
///
/// **Every tile is offered its row's height and set at the top of the row.** A
/// tile whose background should match its neighbors' takes the height by
/// filling it; one that doesn't keeps its own height at the top of the row,
/// where the eye runs along the row. `LazyVGrid` centers a tile that doesn't
/// fill, and each tile would carry a frame to undo that.
///
/// A tile is measured at its column's width with no height, as a lazy grid
/// measures its cells.
nonisolated struct AskTileGridLayout: Layout {
    var columns: AskTileColumns
    /// Between rows.
    var rowSpacing: CGFloat

    /// The last arrangement worked out, and the width it was worked out for.
    ///
    /// **Because measuring a tile isn't free and the layout asks twice.**
    /// `sizeThatFits` measures every tile in the bank to find its rows'
    /// heights, and the `placeSubviews` that follows it would measure them all
    /// over again for the same answer, and a tile here is the host's whole
    /// card, not a box. The thread lays a bank out every time the lazy stack
    /// builds its row, which on a long thread is every scroll.
    ///
    /// Thrown away in `updateCache`, which SwiftUI documents as running when
    /// the layout or its subviews change. It is keyed on the width and on this
    /// layout's own values as well, so a change of width, columns or row
    /// spacing never places a bank to an old arrangement, however SwiftUI
    /// times the update.
    ///
    /// What no key can see is a tile whose height changes with nothing else.
    /// The cache relies on a tile holding its height while its picture loads,
    /// which a framed `AskPictureArrival` does.
    struct Cache {
        var columns: AskTileColumns?
        var rowSpacing: CGFloat?
        var width: CGFloat?
        var arrangement: AskTileArrangement?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // Only a FINITE offer is claimed, for the reason `AskChipFlow` gives:
        // an infinite width is a probe, and claiming it hands the parent an
        // infinite size.
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let arrangement = arrangement(in: offered ?? .infinity, subviews: subviews, cache: &cache)
        return CGSize(width: offered ?? arrangement.width, height: arrangement.height)
    }

    /// Placed from `minX` and never mirrored by hand (`AskChipFlow` has the
    /// measurement): SwiftUI has already mirrored the space for a right-to-left
    /// layout, so the first tile lands on the right in Hebrew.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let arrangement = arrangement(in: bounds.width, subviews: subviews, cache: &cache)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(in width: CGFloat, subviews: Subviews, cache: inout Cache) -> AskTileArrangement {
        if cache.width == width, cache.columns == columns, cache.rowSpacing == rowSpacing,
           let held = cache.arrangement {
            return held
        }
        let fresh = AskTileArrangement(count: subviews.count, in: width, columns: columns, rowSpacing: rowSpacing) { index, cellWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
        }
        cache.columns = columns
        cache.rowSpacing = rowSpacing
        cache.width = width
        cache.arrangement = fresh
        return fresh
    }
}

/// Where each tile of a bank goes: the arithmetic apart from the views, so it
/// can be checked without laying anything out.
nonisolated struct AskTileArrangement: Equatable {
    /// Each tile's cell, from the bank's top leading corner: its column's
    /// width and its row's height.
    var frames: [CGRect]
    /// How far the columns in use reach.
    var width: CGFloat
    /// The rows' heights and the spacing between them.
    var height: CGFloat

    /// - Parameter height: A tile's height at a column width.
    init(
        count: Int,
        in width: CGFloat,
        columns: AskTileColumns,
        rowSpacing: CGFloat,
        height: (_ index: Int, _ cellWidth: CGFloat) -> CGFloat
    ) {
        let fit = columns.fit(in: width)
        let perRow = max(1, min(fit.count, count))
        var frames: [CGRect] = []
        var top: CGFloat = 0
        var start = 0
        while start < count {
            let end = min(start + perRow, count)
            // A tile that answers with a height it can't have gets none,
            // rather than handing `place` the non-finite geometry that trips
            // its assertion (`AskChipFlow`).
            let rowHeight = (start..<end).map { index in
                let measured = height(index, fit.width)
                return measured.isFinite ? max(0, measured) : 0
            }.max() ?? 0
            for index in start..<end {
                let leading = CGFloat(index - start) * (fit.width + columns.spacing)
                frames.append(CGRect(x: leading, y: top, width: fit.width, height: rowHeight))
            }
            top += rowHeight + rowSpacing
            start = end
        }
        self.frames = frames
        self.width = frames.map(\.maxX).max() ?? 0
        self.height = frames.isEmpty ? 0 : top - rowSpacing
    }
}

#endif
