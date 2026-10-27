#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// A bank of result tiles under an answer (the pictures it stood on), laid out
/// in AskKit's columns and brought in a tile at a time, the way the answer's
/// words arrive.
///
/// **The bank is AskKit's; only the tile is the host's.** `AskScreen` hands
/// its `tiles` builder the rows and gets one view back, so the screen can't
/// bring the tiles in one by one from outside: a grid of twenty is a single
/// view to it. So the builder returns this grid, and draws only the tile
/// inside it, with the tile's gesture and its zoom source.
///
/// **The entrance lands outside everything the tile draws**, its
/// `matchedTransitionSource` included, so a zoom grows out of the tile's
/// laid-out frame: the order `askArrival` asks for, kept by construction.
///
/// **The tiles are built with the answer, not as they scroll in**, and each is
/// offered its row's height and set at the top of the row (`AskTileGridLayout`
/// says why the bank isn't a `LazyVGrid`). A tile should keep its height while
/// its picture loads, as a framed `AskPictureArrival` does, so nothing under
/// the bank moves when the picture lands.
///
/// **Each tile is handed a zoom source id of its own**: this bank's, then the
/// item's. The item's id alone isn't unique in the thread: ask the same thing
/// twice and one item has a tile under both answers, and a zoom keyed on the
/// item would have two sources under one id to grow out of, not necessarily
/// the one under the reader's finger. Tagging the tile stays the host's, since
/// only the host knows whether it zooms at all (`AskItemOpenAction`).
///
/// The arrangement for pictures is
/// `AskLayout.tileColumns(for:tallestAspect:spacing:)`. A bank that isn't
/// pictures passes columns of its own: captioned icons or title cards want
/// widths their words can live in.
public struct AskTileGrid<Item: Identifiable, Tile: View>: View {
    private let items: [Item]
    private let columns: AskTileColumns
    private let spacing: CGFloat
    private let firstStep: Int
    private let tile: (_ item: Item, _ zoomSourceID: String) -> Tile

    /// This bank's half of every tile's zoom source id. State, so it holds for
    /// as long as the bank is on screen, which is every moment a pushed detail
    /// can zoom back into its tile.
    @State private var zoomScope = UUID()

    /// A bank of pictures, in AskKit's arrangement.
    ///
    /// - Parameters:
    ///   - items: What the tiles are drawn from, one tile each, in reading
    ///     order.
    ///   - tallestAspect: Width over height of the bank's narrowest tile, for
    ///     tiles shaped like their object rather than square
    ///     (`AskLayout.tileColumns(for:tallestAspect:spacing:)`).
    ///   - spacing: Between rows, and between columns.
    ///   - firstStep: The step the first tile arrives on, for a bank drawn
    ///     after other pieces of its wave (`askArrival`).
    ///   - tile: The host's tile for an item, handed the id to tag it with as
    ///     a zoom's source where the host zooms.
    public init(
        _ items: [Item],
        tallestAspect: CGFloat = 1,
        spacing: CGFloat = 8,
        firstStep: Int = 0,
        @ViewBuilder tile: @escaping (_ item: Item, _ zoomSourceID: String) -> Tile
    ) {
        self.init(
            items,
            columns: AskLayout.tileColumns(for: items.count, tallestAspect: tallestAspect, spacing: spacing),
            spacing: spacing,
            firstStep: firstStep,
            tile: tile
        )
    }

    /// A bank in columns of its own. `spacing` is between rows; the columns
    /// carry the space between themselves. The other parameters are as in
    /// `init(_:tallestAspect:spacing:firstStep:tile:)`.
    public init(
        _ items: [Item],
        columns: AskTileColumns,
        spacing: CGFloat = 8,
        firstStep: Int = 0,
        @ViewBuilder tile: @escaping (_ item: Item, _ zoomSourceID: String) -> Tile
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.firstStep = firstStep
        self.tile = tile
    }

    public var body: some View {
        AskTileGridLayout(columns: columns, rowSpacing: spacing) {
            ForEach(items.enumerated(), id: \.element.id) { index, item in
                tile(item, "\(zoomScope.uuidString)/\(item.id)")
                    .askArrival(firstStep + index)
            }
        }
        // One element holding the tiles. A layout is no element of its own, and
        // an identifier on a view that is none reaches its children instead:
        // every tile would answer to `ask.results`, and a query for the bank's
        // tiles would find a tile with none inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AskAccessibility.results)
    }
}

#endif
