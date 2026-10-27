#if os(macOS)

import AppKit
import SwiftUI
import Testing

@testable import AskUI

/// How chips flow into lines, read off a render: fixed-size black chips on
/// white, one point to a pixel.
///
/// Three chips 100 wide and 20 high, with the flow's own gaps of 8 between
/// chips and between lines. Two and their gap make 208, so in 250 the third
/// starts a line of its own; all three make 316.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskChipFlowTests {

    private let column = ProposedViewSize(width: 250, height: nil)

    private func chips(alignment: HorizontalAlignment = .leading) -> some View {
        AskChipFlow(alignment: alignment) {
            ForEach(0..<3, id: \.self) { _ in
                Color.black.frame(width: 100, height: 20)
            }
        }
        .background(Color.white)
    }

    private func render(_ view: some View, proposing proposal: ProposedViewSize) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = proposal
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    /// The leftmost pixel of any chip on pixel row `y`, counted from the top,
    /// or nil for a row with none.
    private func leftmostChip(in image: NSBitmapImageRep, row y: Int) -> Int? {
        (0..<image.pixelsWide).first { x in
            guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return colour.redComponent < 0.5
        }
    }

    @Test func aChipThatDoesNotFitStartsANewLine() throws {
        let image = try #require(render(chips(), proposing: column))
        // The offered width, claimed so a short line has room to be aligned
        // in; two lines of 20 and the gap between them.
        #expect(image.pixelsWide == 250)
        #expect(image.pixelsHigh == 48)
        #expect(leftmostChip(in: image, row: 10) == 0)
        #expect(leftmostChip(in: image, row: 24) == nil)
        #expect(leftmostChip(in: image, row: 38) == 0)
    }

    @Test func anOfferWithNoFiniteWidthIsAnsweredWithTheWidestLine() throws {
        // `.infinity` is a probe, not room: claimed, it would hand the parent
        // an infinite width. It and no width at all both get one line of three.
        for proposal in [ProposedViewSize.infinity, .unspecified] {
            let image = try #require(render(chips(), proposing: proposal))
            #expect(image.pixelsWide == 316)
            #expect(image.pixelsHigh == 20)
        }
    }

    @Test func aShortLineSitsWhereTheAlignmentSays() throws {
        // In 250, the first line's 208 leaves 42 over and the second's 100
        // leaves 150.
        let expected: [(alignment: HorizontalAlignment, first: Int, second: Int)] = [
            (.leading, 0, 0), (.center, 21, 75), (.trailing, 42, 150)
        ]
        for (alignment, first, second) in expected {
            let image = try #require(render(chips(alignment: alignment), proposing: column))
            #expect(leftmostChip(in: image, row: 10) == first)
            #expect(leftmostChip(in: image, row: 38) == second)
        }
    }

    @Test func rightToLeftLinesStartAtTheRight() throws {
        // Leading is the right edge, and SwiftUI mirrors the flow's offsets
        // itself: the first line ends against the right, and the third chip
        // sits there alone.
        let image = try #require(render(chips().environment(\.layoutDirection, .rightToLeft), proposing: column))
        #expect(leftmostChip(in: image, row: 10) == 42)
        #expect(leftmostChip(in: image, row: 38) == 150)
    }
}

#endif
