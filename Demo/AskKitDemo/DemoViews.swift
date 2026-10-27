import AskCore
import AskUI
import SwiftUI

/// The mark — the one glyph a host puts in the wait row and on the first
/// screens: lit on the ready first screen and in the wait row, unlit on the
/// other two first screens.
///
/// A host's can be a glyph of its own, even one that moves. The demo's is its
/// Ask tab's, whose bubble its icon traces: SF Symbols'
/// `text.bubble.badge.sparkles`, lit in the tint as the tab draws it selected,
/// and unlit in one tertiary ink.
struct DemoMark: View {
    let isLit: Bool

    var body: some View {
        Image(systemName: "text.bubble.badge.sparkles.fill")
            .resizable()
            .scaledToFit()
            .padding(6)
            .foregroundStyle(isLit ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .accessibilityHidden(true)
    }
}

/// The rows an answer stood on, as the tiles under it.
///
/// A title card rather than a photo: the demo owns no images, and the grid's job
/// here is to exercise what the `tiles` builder draws into — its width, its
/// place below the prose, how it behaves at Dynamic Type XXL and in Hebrew —
/// rather than to look like a host's own grid of pictures.
///
/// Each card opens through `askItemOpener`, so the demo exercises the
/// environment value a host sets to open its rows — the grid asks, the host
/// answers. A host that wires nothing gets plain cards rather than a tap that
/// does nothing, which is the whole reason the value is optional.
struct DemoTiles: View {
    let rows: [DemoRow]

    @Environment(\.askItemOpener) private var open
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Deliberately NOT AskKit's picture arrangement (`AskLayout.tileColumns`).
    /// That policy sizes banks of *pictures*, one photo or piece of artwork to
    /// a tile, and its grid case lands near 85 pt, which is a square photo and
    /// not a two-line title over a caption. These cards carry text, so they
    /// keep a width text can live in — and at the accessibility sizes a wider
    /// one, one across a phone, where a title takes the lines it needs. Two
    /// lines of a 200 pt column held about twelve characters of a title at
    /// the largest size. AskKit's own default tiles do the same.
    private var columns: AskTileColumns {
        dynamicTypeSize.isAccessibilitySize
            ? .adaptive(minimum: 264, maximum: AskLayout.readingWidth, spacing: 10)
            : .adaptive(minimum: 132, maximum: 200, spacing: 10)
    }

    var body: some View {
        // The bank every host draws its tiles in, so the cards come in a step
        // behind each other the way a host's do. Nothing here zooms, so the
        // zoom source id goes unused.
        AskTileGrid(rows, columns: columns, spacing: 10) { row, _ in
            card(row)
        }
    }

    @ViewBuilder
    private func card(_ row: DemoRow) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            // The deemphasized gray: on the card's fill over white, 4.88:1 in
            // light where `.secondary` is 3.25:1 (`askDeemphasizedText`).
            Text(verbatim: "\(row.kind.scope) · \(year(of: row))")
                .font(.caption)
                .askDeemphasizedText()
                // The middle dot is for the eye. Read with punctuation on,
                // VoiceOver would say "middle dot" on every tile, so it hears
                // the two with a pause between, as AskKit's wait row does.
                .accessibilityLabel(Text(verbatim: "\(row.kind.scope), \(year(of: row))"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        // A fill, not glass: tiles are content, and content never gets glass.
        // Its own height, at the top of its row, beside a card with a title a
        // line longer — `AskTileGrid` sets it there.
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))

        if let open {
            Button { open(row.id) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// The year as a year, with no grouping separator.
    private func year(of row: DemoRow) -> String {
        row.year.formatted(.number.grouping(.never))
    }
}
