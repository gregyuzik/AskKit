#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing
@testable import AskUI

/// The bank a host draws its tiles in, and the columns it lays pictures out on.
@MainActor
@Suite("A bank of tiles", .timeLimit(.minutes(1)))
struct AskTileGridTests {
    private struct Tile: Identifiable {
        let id: Int
    }

    /// The one- and two-up layouts narrow for a portrait bank, and nothing
    /// else moves: not the grid case, whose minimum chooses the column count,
    /// and not a bank wider than square.
    @Test(arguments: [
        (1, 1, 150, 160),
        (2, 1, 130, 140),
        (3, 1, 76, 100),
        (1, 2.0 / 3.0, 100, 160 * 2.0 / 3.0),
        (2, 0.5, 65, 70),
        (5, 0.5, 76, 100),
        (1, 1.5, 150, 160)
    ] as [(Int, CGFloat, CGFloat, CGFloat)])
    func aPortraitBankNarrowsOnlyItsWideLayouts(count: Int, tallestAspect: CGFloat, minimum: CGFloat, maximum: CGFloat) {
        let columns = AskLayout.tileColumns(for: count, tallestAspect: tallestAspect)
        #expect(abs(columns.minimum - minimum) < 1e-9)
        #expect(abs(columns.maximum - maximum) < 1e-9)
    }

    /// **An aspect a host can pass never makes a column of nothing.** Zero or
    /// less, or a tile taller than twice its width, narrows as a 1:2 tile
    /// does, and an aspect that isn't a finite number lays out as square.
    @Test(arguments: [
        (1, 0, 75, 80),
        (1, -2, 75, 80),
        (2, 0.25, 65, 70),
        (1, .nan, 150, 160),
        (2, .infinity, 130, 140),
        (2, -.infinity, 130, 140)
    ] as [(Int, CGFloat, CGFloat, CGFloat)])
    func anAspectNoTileCouldHaveStillLaysOut(count: Int, tallestAspect: CGFloat, minimum: CGFloat, maximum: CGFloat) {
        let columns = AskLayout.tileColumns(for: count, tallestAspect: tallestAspect)
        #expect(abs(columns.minimum - minimum) < 1e-9)
        #expect(abs(columns.maximum - maximum) < 1e-9)
        #expect(columns.fit(in: 366).width > 0)
    }

    /// AskKit's default tiles carry titles, and at the accessibility sizes a
    /// title gets a column it can wrap in: one across a phone, two across the
    /// reading width, and all the lines it needs (`AskDefaultTileText`).
    @Test func theDefaultTilesWidenAndWrapAtTheAccessibilitySizes() {
        let resting = AskDefaultTileText.columns(isAccessibilitySize: false)
        #expect(resting == .adaptive(minimum: 132, maximum: 200, spacing: 10))
        #expect(AskDefaultTileText.lineLimit(isAccessibilitySize: false) == 2)

        let large = AskDefaultTileText.columns(isAccessibilitySize: true)
        #expect(large.fit(in: 366).count == 1)
        #expect(large.fit(in: 366).width == 366)
        #expect(large.fit(in: AskLayout.readingWidth).count == 2)
        #expect(AskDefaultTileText.lineLimit(isAccessibilitySize: true) == nil)
    }

    /// The columns a `LazyVGrid` of one adaptive item chose for the banks
    /// below, measured at widths from 120 to 680 pt, since the bank isn't a
    /// `LazyVGrid` and has to agree with one.
    /// The count comes from the minimum, each column is its share capped at
    /// the maximum, and a width under the minimum is one column that wide.
    @Test(arguments: [
        // AskKit's grid case: four across on a phone.
        (76, 100, 8, 120, 1, 100),
        (76, 100, 8, 300, 3, 284.0 / 3),
        (76, 100, 8, 366, 4, 85.5),
        (76, 100, 8, 500, 6, 460.0 / 6),
        (76, 100, 8, 680, 8, 78),
        // The solo and pair cases, capped, with the slack left at the end.
        (150, 160, 8, 120, 1, 120),
        (150, 160, 8, 366, 2, 160),
        (130, 140, 8, 120, 1, 120),
        (130, 140, 8, 366, 2, 140),
        // A host's captioned icons.
        (96, 128, 10, 120, 1, 120),
        (96, 128, 10, 300, 2, 128),
        (96, 128, 10, 366, 3, 346.0 / 3),
        (96, 128, 10, 500, 4, 117.5),
        (96, 128, 10, 680, 6, 105),
        // The demo's title cards.
        (132, 200, 10, 300, 2, 145),
        (132, 200, 10, 366, 2, 178),
        (132, 200, 10, 500, 3, 160),
        (132, 200, 10, 680, 4, 162.5)
    ] as [(CGFloat, CGFloat, CGFloat, CGFloat, Int, CGFloat)])
    func theColumnsAreTheOnesALazyGridChose(
        minimum: CGFloat, maximum: CGFloat, spacing: CGFloat, width: CGFloat, count: Int, columnWidth: CGFloat
    ) {
        let fit = AskTileColumns.adaptive(minimum: minimum, maximum: maximum, spacing: spacing).fit(in: width)
        #expect(fit.count == count)
        #expect(abs(fit.width - columnWidth) < 1e-9)
    }

    /// Rows as tall as their tallest tile, a row's spacing apart, each tile's
    /// cell its row's full height from the top: a bank of captioned icons at
    /// 300 pt, frame for frame what the lazy grid gave tiles that fill their
    /// cells.
    @Test func eachRowIsAsTallAsItsTallestTile() {
        let heights: [CGFloat] = [40, 64, 52, 40, 64]
        let arrangement = AskTileArrangement(
            count: heights.count, in: 300, columns: .adaptive(minimum: 96, maximum: 128, spacing: 10), rowSpacing: 14
        ) { index, _ in heights[index] }
        #expect(arrangement.frames == [
            CGRect(x: 0, y: 0, width: 128, height: 64),
            CGRect(x: 138, y: 0, width: 128, height: 64),
            CGRect(x: 0, y: 78, width: 128, height: 52),
            CGRect(x: 138, y: 78, width: 128, height: 52),
            CGRect(x: 0, y: 144, width: 128, height: 64)
        ])
        #expect(arrangement.width == 266)
        #expect(arrangement.height == 208)
    }

    /// A tile is measured at its column's width, never at the whole bank's:
    /// a caption that wraps in a column has to be asked about the column.
    @Test func aTileIsMeasuredAtItsColumnsWidth() {
        var asked: Set<CGFloat> = []
        _ = AskTileArrangement(count: 7, in: 366, columns: .adaptive(minimum: 76, maximum: 100), rowSpacing: 8) { _, width in
            asked.insert(width)
            return 50
        }
        #expect(asked == [85.5])
    }

    /// No tiles is no bank. An unbounded width — a probe asking how wide the
    /// bank could be — is every tile in one row at the maximum.
    @Test func anEmptyBankAndAnUnboundedOne() {
        let columns = AskTileColumns.adaptive(minimum: 76, maximum: 100)
        let empty = AskTileArrangement(count: 0, in: 366, columns: columns, rowSpacing: 8) { _, _ in 50 }
        #expect(empty.frames.isEmpty)
        #expect(empty.width == 0)
        #expect(empty.height == 0)

        let unbounded = AskTileArrangement(count: 3, in: .infinity, columns: columns, rowSpacing: 8) { _, _ in 50 }
        #expect(unbounded.frames.map(\.minX) == [0, 108, 216])
        #expect(unbounded.width == 316)
        #expect(unbounded.height == 50)
    }

    /// A tile that answers with a height it cannot have is given none, so the
    /// bank never hands `place` a non-finite frame.
    @Test func aNonFiniteHeightIsNoHeight() {
        let arrangement = AskTileArrangement(
            count: 2, in: 366, columns: .adaptive(minimum: 150, maximum: 160), rowSpacing: 8
        ) { index, _ in index == 0 ? .infinity : 40 }
        #expect(arrangement.frames.map(\.height) == [40, 40])
        #expect(arrangement.height == 40)
    }

    /// Both ways a host spells a bank, AskKit's pictures and columns of its
    /// own, as the compiler sees them. The annotations are the assertions, as
    /// in `AskScreenViewBuildersTests`: dropping an `init` or reordering its
    /// labels stops compiling here rather than in a host's build.
    @Test func bothSpellingsOfABank() {
        let tiles = [Tile(id: 1), Tile(id: 2)]
        let pictures: AskTileGrid<Tile, Text> = AskTileGrid(tiles, tallestAspect: 2.0 / 3.0, firstStep: 2) { tile, zoomSourceID in
            Text(verbatim: "\(tile.id) \(zoomSourceID)")
        }
        let captioned: AskTileGrid<Tile, Text> = AskTileGrid(
            tiles,
            columns: .adaptive(minimum: 96, maximum: 128, spacing: 10),
            spacing: 14
        ) { tile, _ in
            Text(verbatim: "\(tile.id)")
        }
        _ = pictures.body
        _ = captioned.body
    }
}

#endif
