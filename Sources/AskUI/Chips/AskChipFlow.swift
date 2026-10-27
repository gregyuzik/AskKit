#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// Lays chips out from the leading edge, and starts a new line when the next
/// one wouldn't fit.
///
/// **A row of chips isn't a row.** A bank is a handful of whole questions,
/// and two of them side by side are already wider than a phone's column, so
/// laid out as one line they run off the trailing edge. Scrolling them
/// sideways isn't the answer: the cut lands mid-word with nothing saying
/// there is more, and on the first screen, where everything else is
/// centered, a row that stops hard at the padding edge reads as a layout bug
/// rather than as something to swipe.
///
/// A chip wider than the whole column is measured against the column and
/// wraps inside it, so every chip shows its whole question at every text
/// size. A chip held to one line looks right at the default size, and shows
/// the ellipsis this layout exists to remove as soon as the text grows: at
/// an accessibility size every starter is wider than a phone's column.
nonisolated struct AskChipFlow: Layout {
    /// Where a line that doesn't fill the width sits. The first screen
    /// centers its column, so its chips center with it. The follow-ups and a
    /// failure's coaching are read against the leading edge and stay there.
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// The line-breaking, held between the calls SwiftUI makes in one pass.
    ///
    /// **`sizeThatFits` and `placeSubviews` ask the same question.** Both go
    /// through `lines(in:subviews:cache:)`, and breaking the lines measures
    /// every chip, a text layout each at whatever Dynamic Type size is in
    /// force. Without the cache a bank would be measured twice per pass, and
    /// SwiftUI is free to ask for a size more than once. `AskTileGridLayout`
    /// holds its arrangement the same way.
    ///
    /// **What invalidates it.** The width and `spacing`, which are all the
    /// breaking reads, and `lineSpacing`, which stacks the lines. `alignment`
    /// isn't among them, since it moves a finished line rather than deciding
    /// what is on it. A change to the chips
    /// themselves goes through `updateCache`, which throws the lot away. That
    /// handles a bank swapped for another and a chip whose words changed in
    /// place alike, since the subviews are rebuilt either way.
    struct Cache {
        var width: CGFloat?
        var spacing: CGFloat?
        var lineSpacing: CGFloat?
        var lines: [Line]?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let lines = lines(in: proposal.width ?? .infinity, subviews: subviews, cache: &cache)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        // Claim the offered width so the alignment below has room to act in.
        // Handed back the widest line instead, a centered bank would be
        // centered by the parent as a block, with every line inside it flush
        // to the leading edge.
        //
        // **Only a finite offer, though.** `ProposedViewSize.infinity` has a
        // non-nil width of `.infinity`, so `??` doesn't catch it, and claiming
        // it hands the parent an infinite size: the non-finite geometry behind
        // a crash in a host app (`view origin is invalid: … inf`, an assertion
        // in `LayoutSubview.place` with no app frame in its stack). An
        // infinite proposal is a probe asking how big this could be, not a
        // container offering room. Answer it with the widest line, which is
        // the honest answer and a number a parent can lay out against.
        let offered = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let width = offered ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    /// **Don't mirror this for right-to-left by hand.** A custom `Layout`
    /// looks as if it must, since it places subviews at absolute points and
    /// `subviews` even offers a `layoutDirection` to branch on, but SwiftUI
    /// has already mirrored the space these points land in. Measured in the
    /// demo under `-AppleTextDirection YES`: laying out from `minX` puts the
    /// first chip on the right, correctly, while a hand-written
    /// `bounds.maxX - x - width` flipped it a second time and read left to
    /// right in Hebrew. `x` below is an offset from the leading edge, not from
    /// the left.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let lines = lines(in: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for line in lines {
            var x = leadingOffset(for: line, in: bounds.width)
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + x, y: y + (line.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    // MARK: - Measuring

    // Internal rather than private only because `Cache` holds them, and a
    // `Layout`'s cache type has to be as visible as the conformance.
    struct Item {
        var index: Int
        var size: CGSize
    }

    struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The lines for `width`, from the cache where it still holds.
    private func lines(in width: CGFloat, subviews: Subviews, cache: inout Cache) -> [Line] {
        if cache.width == width, cache.spacing == spacing, cache.lineSpacing == lineSpacing,
           let held = cache.lines {
            return held
        }
        let fresh = brokenLines(in: width, subviews: subviews)
        cache.width = width
        cache.spacing = spacing
        cache.lineSpacing = lineSpacing
        cache.lines = fresh
        return fresh
    }

    /// Breaks the chips into lines against `width`.
    ///
    /// Each chip is measured against the full width rather than against what is
    /// left of the current line: a chip asked for its size in a sliver would
    /// report the truncated width it could squeeze into, and then fit there.
    private func brokenLines(in width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !line.items.isEmpty, line.width + spacing + size.width > width {
                lines.append(line)
                line = Line()
            }
            line.width += line.items.isEmpty ? size.width : spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(Item(index: index, size: size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }

    /// How far in from the leading edge a line starts, so a `.trailing` line
    /// sits against the right in English and the left in Hebrew, which is
    /// what `HorizontalAlignment` means by it.
    private func leadingOffset(for line: Line, in width: CGFloat) -> CGFloat {
        switch alignment {
        case .center:
            return max(width - line.width, 0) / 2
        case .trailing:
            return max(width - line.width, 0)
        default:
            return 0
        }
    }
}

#endif
