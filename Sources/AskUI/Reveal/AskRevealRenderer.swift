#if os(iOS) || os(macOS) || os(visionOS)

public import Foundation
public import SwiftUI

/// The instant a run of answer text arrived, on the reveal clock, stamped on
/// the piece of text that carries it so the renderer can fade it by run.
///
/// It reaches the layout through `Text.customAttribute`, the only route that
/// works (`AskReveal.text(_:chunks:)`).
nonisolated struct AskArrivalStamp: TextAttribute, Hashable, Sendable {
    let arrival: TimeInterval
}

/// How a streamed Ask answer draws in: every run of text fades up over a quarter
/// second from the instant its snapshot arrived, and nothing is ever held back.
/// A chunk is on screen, at partial opacity, the frame it lands, and fully drawn
/// a sweep and a fade later.
///
/// **Not a typewriter.** Text materializes exactly where and when it arrives:
/// if the tier sends a sentence in one snapshot the sentence fades in as one,
/// and if it sends it word by word, the words do. Why not a pacing buffer that
/// releases characters at a steady rate: ARCHITECTURE.md, Rejected designs.
///
/// **The sentence still reads in order, and that isn't pacing.** The glyphs
/// are all laid out in the frame the snapshot lands, and the ink crosses them
/// at the rate the on-device tier writes at. `AskArrivals.staggerPerCharacter`
/// carries the measurement, and why the bound keeps this drawing rather than
/// pacing. It matters on Private Cloud Compute, where one snapshot can carry a
/// sentence or more: 160 characters swept across 80 ms is a paragraph
/// appearing at once.
///
/// **Draw-only.** The renderer changes how glyphs are painted, never where they
/// sit, so no layout animation runs per token (house rule 4).
///
/// The clock behind `now` is `AskStreamingText`'s `TimelineView`, and what
/// stops it is the store clearing the turn's chunks, 0.05 s after the longest
/// sweep has settled (`forgetChunksOnceSettled`), not anything this renderer
/// does. A runaway `TimelineView` is the store's to fix, not this type's.
///
/// Under Reduce Motion the blur and the stagger go and the fade stays: a fade is
/// not motion, and the same information arrives without anything moving.
nonisolated struct AskRevealRenderer: TextRenderer {
    /// The frame's time on the reveal clock: seconds since the reference date,
    /// the same terms as each stamp.
    var now: TimeInterval
    /// A slight blur clearing as a chunk lands. Off under Reduce Motion.
    var blurs: Bool
    /// Spread a chunk's glyphs across the span its length earns
    /// (`AskArrivals.stagger(forLength:)`) so it reads in order rather than
    /// landing as a block. Off under Reduce Motion, which takes the flat fade.
    var staggers: Bool
    /// When set, a dot after the last glyph: the streaming caret, shown while
    /// the prose is being written and gone when it stops.
    var caret: AskCaret?

    init(
        now: TimeInterval,
        blurs: Bool = true,
        staggers: Bool = true,
        caret: AskCaret? = nil
    ) {
        self.now = now
        self.blurs = blurs
        self.staggers = staggers
        self.caret = caret
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if staggers {
            drawSweeping(layout, in: context)
        } else {
            drawFlat(layout, in: context)
        }
        // Sized and spaced from the last glyph's height, so the caret scales
        // with the text.
        guard let caret, let slice = Self.lastInReadingOrder(layout) else { return }
        let rect = slice.typographicBounds.rect
        let diameter = rect.height * 0.3
        let gap = diameter * 0.6
        // After the glyph as its run reads: to its right in English, to its
        // left in Hebrew or Arabic, where the prose ends at its left.
        let x = slice.run.layoutDirection == .rightToLeft ? rect.minX - gap - diameter : rect.maxX + gap
        let dot = CGRect(x: x, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        switch caret {
        case .color(let color):
            context.fill(Path(ellipseIn: dot), with: .color(color))
        case .gradient(let colors):
            // The send circle's gradient, corner to corner, over a soft glow
            // of itself: one blurred fill a frame, a dot's worth of pixels.
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: dot.minX, y: dot.minY),
                endPoint: CGPoint(x: dot.maxX, y: dot.maxY)
            )
            var glow = context
            glow.addFilter(.blur(radius: diameter * 0.6))
            glow.opacity = 0.8
            glow.fill(Path(ellipseIn: dot.insetBy(dx: -diameter * 0.4, dy: -diameter * 0.4)), with: shading)
            context.fill(Path(ellipseIn: dot), with: shading)
        }
    }

    /// The glyph the prose ends on: on the last line, the one that draws the
    /// last character. Read from the characters it draws, not from its place
    /// in the line, since a line that mixes directions holds its runs in an
    /// order that says nothing about which one the reading ends in.
    private static func lastInReadingOrder(_ layout: Text.Layout) -> Text.Layout.RunSlice? {
        guard let line = layout.last else { return nil }
        var last: (slice: Text.Layout.RunSlice, character: Text.Layout.CharacterIndex)?
        for run in line {
            for slice in run {
                guard let character = slice.characterIndices.max() else { continue }
                if last.map({ character > $0.character }) ?? true { last = (slice, character) }
            }
        }
        return last?.slice
    }

    /// Reduce Motion's reveal: each run at the opacity its age has earned, no
    /// sweep, so a run is settled a plain `fade` after it arrived.
    private func drawFlat(_ layout: Text.Layout, in context: GraphicsContext) {
        for line in layout {
            let height = line.typographicBounds.rect.height
            for run in line {
                guard let stamp = run[AskArrivalStamp.self] else {
                    context.draw(run)
                    continue
                }
                let age = now - stamp.arrival
                guard age < AskArrivals.fade else {
                    context.draw(run)
                    continue
                }
                painting(progress: age / AskArrivals.fade, height: height, from: context).draw(run)
            }
        }
    }

    /// Every chunk swept slice by slice, each one a little behind the last, so
    /// it reads in order instead of landing as a block.
    ///
    /// **Per slice, and across the chunk's whole share of the layout, not
    /// within one run.** A chunk is one `customAttribute`, so a delay computed
    /// from the run's position on the line gives a whole chunk one delay, which
    /// is no sweep at all. A delay counted within each run is right only for a
    /// chunk that fits on one line: a chunk wrapping four lines is four runs,
    /// and a delay counted from each run's own start restarts the sweep on
    /// every one of them, four lines rippling in parallel, which is the block
    /// again. So the chunk's length is counted first, across the layout, and a
    /// slice's delay comes from its place in the whole chunk.
    ///
    /// **A slice's place is that of the characters it draws, not its place in
    /// the layout.** A right-to-left run holds its slices left to right, the
    /// last character read first, and a line that mixes directions holds its
    /// runs in the order they are drawn, which says nothing of the order they
    /// are read in (`lastInReadingOrder` says the same for the caret). Counted
    /// in the layout's order, a Hebrew sentence inked in from its end. Counted
    /// by character, a chunk sweeps in reading order in every direction, and
    /// on to its next line, whose characters come after.
    ///
    /// Both passes are walked whatever the clock says; only a run still fading
    /// is sliced, and a settled one is drawn whole in one call.
    private func drawSweeping(_ layout: Text.Layout, in context: GraphicsContext) {
        var chunks: [AskArrivalStamp: AskSweptChunk] = [:]
        for line in layout {
            for run in line {
                guard let stamp = run[AskArrivalStamp.self] else { continue }
                chunks[stamp, default: AskSweptChunk()].add(run)
            }
        }
        var drawn: [AskArrivalStamp: Int] = [:]
        for line in layout {
            let height = line.typographicBounds.rect.height
            for run in line {
                guard let stamp = run[AskArrivalStamp.self] else {
                    context.draw(run)
                    continue
                }
                let chunk = chunks[stamp] ?? AskSweptChunk()
                let span = AskArrivals.stagger(forLength: max(chunk.length, run.count))
                let age = now - stamp.arrival
                // Settled (including everything on screen once the answer is
                // finished) draws whole, one call, no slicing.
                if age < AskArrivals.fade + span {
                    sweep(
                        run, age: age, after: drawn[stamp] ?? 0, of: chunk,
                        span: span, height: height, in: context
                    )
                } else {
                    context.draw(run)
                }
                drawn[stamp, default: 0] += run.count
            }
        }
    }

    /// One run of a chunk, each slice delayed by where its characters fall in
    /// the chunk's (`AskSweptChunk.place(of:)`). A slice that draws no
    /// character, which no text has been seen to make, falls back on its place
    /// in the layout, `after` slices of the chunk behind it.
    private func sweep(
        _ run: Text.Layout.Run,
        age: TimeInterval,
        after: Int,
        of chunk: AskSweptChunk,
        span: TimeInterval,
        height: CGFloat,
        in context: GraphicsContext
    ) {
        guard chunk.length > 1 else {
            painting(progress: age / AskArrivals.fade, height: height, from: context).draw(run)
            return
        }
        let last = Double(chunk.length - 1)
        for (index, slice) in run.enumerated() {
            let place = chunk.place(of: slice.characterIndices.min()) ?? Double(after + index) / last
            let delay = span * place
            let progress = (age - delay) / AskArrivals.fade
            painting(progress: progress, height: height, from: context).draw(slice)
        }
    }

    /// The context to paint one drawable through, at the opacity its progress
    /// has earned and blurred while it is still arriving. The blur starts at a
    /// tenth of the line's height, so it scales with the text.
    ///
    /// A context rather than a `draw` call because `GraphicsContext` has three
    /// unrelated `draw` overloads (line, run, slice) and no protocol over
    /// them, so a generic helper can't exist.
    ///
    /// **A blur per slice, and measured to stay one.** One blur layer per run,
    /// at its middle slice's radius, was tried on two long Private Cloud
    /// Compute sweeps: it changed 43,038 of the frame's 1,872,000 bytes by up
    /// to 113 levels, a different look, and saved nothing the CPU could see, a
    /// 1.86 ms frame against 1.89 (1.78 with no blur at all). Measured through
    /// ImageRenderer at scale 2 on an M4 Pro Mac. What it might save is the
    /// GPU's offscreen passes, which that can't measure, so the look stays
    /// until a device says otherwise.
    private func painting(
        progress: Double,
        height: CGFloat,
        from context: GraphicsContext
    ) -> GraphicsContext {
        let clamped = min(1, max(0, progress))
        guard clamped < 1 else { return context }
        var copy = context
        let eased = UnitCurve.easeOut.value(at: clamped)
        copy.opacity = eased
        if blurs { copy.addFilter(.blur(radius: (1 - eased) * height / 10)) }
        return copy
    }
}

/// A chunk's share of one frame's layout, read before any of it is drawn:
/// how many slices it has, for the length of its sweep, and the characters it
/// spans, for where each slice falls in it (`AskRevealRenderer.drawSweeping`).
nonisolated struct AskSweptChunk {
    /// The slices of every run the chunk has in the layout.
    private(set) var length = 0
    /// The first character the chunk draws and the last.
    private var characters: ClosedRange<Text.Layout.CharacterIndex>?

    /// Counts `run` into the chunk.
    mutating func add(_ run: Text.Layout.Run) {
        length += run.count
        guard let first = run.characterIndices.min(), let last = run.characterIndices.max() else { return }
        characters = characters.map { min($0.lowerBound, first)...max($0.upperBound, last) } ?? first...last
    }

    /// Where `character` falls in the chunk's characters, from 0 at the first
    /// to 1 at the last, or nil where there is none to place.
    func place(of character: Text.Layout.CharacterIndex?) -> Double? {
        guard let character, let characters else { return nil }
        let spread = characters.lowerBound.distance(to: characters.upperBound)
        guard spread > 0 else { return 0 }
        return Double(characters.lowerBound.distance(to: character)) / Double(spread)
    }
}

/// What the streaming caret is drawn in: one color, the accent's dot, or a
/// gradient of a host's spectrum with a soft glow (`AskSpectrumLook.caret`).
nonisolated enum AskCaret: Equatable, Sendable {
    case color(Color)
    case gradient([Color])
}

// MARK: - Building the text

/// Builds the stamped `Text` that `AskRevealRenderer` draws.
nonisolated enum AskReveal {

    /// The answer as `Text`, each chunk stamped with its arrival.
    ///
    /// **`Text.customAttribute` on each piece, joined, is the only path that
    /// carries a stamp into `Text.Layout`.** Measured on SDK 27: a stamp set
    /// through an `AttributedStringKey` on one `AttributedString`, whether or
    /// not one type is both the key and the value, fails silently. Every run
    /// reaches the renderer unstamped, `progress` is always 1, the finished
    /// answer looks perfect and the drawing-in is simply gone.
    /// `AskRevealRenderTests.theStampReachesTheLayout` exists to catch that.
    /// Why not an `AttributedStringKey`: ARCHITECTURE.md, Rejected designs.
    ///
    /// The pieces are joined by string interpolation. Joined by `+` they work
    /// too, but `+` is deprecated, and interpolation is what the deprecation
    /// points to, so the build stays free of warnings.
    ///
    /// Built from the whole parsed string, sliced by chunk, never from per-chunk
    /// parses, since a `**` that opens in one snapshot and closes in the next
    /// can't be parsed across pieces. No chunks (a turn restored from disk)
    /// draws the whole text unstamped, which the renderer paints opaque.
    ///
    /// **A settled chunk is a piece with no stamp**, so the merged front of a
    /// long answer is one slice and one `Text` here, and runs the renderer
    /// draws whole without looking them up, which is what it did with each of
    /// them once its own sweep had ended.
    static func text(_ attributed: AttributedString, chunks: [AskRevealChunk]) -> Text {
        guard !chunks.isEmpty else { return Text(attributed) }
        let characters = attributed.characters
        var pieces: [Text] = []
        var start = characters.startIndex
        for chunk in chunks {
            let end = characters.index(start, offsetBy: chunk.length, limitedBy: characters.endIndex)
                ?? characters.endIndex
            let piece = Text(AttributedString(attributed[start..<end]))
            pieces.append(chunk.isSettled ? piece : piece.customAttribute(AskArrivalStamp(arrival: chunk.arrival)))
            start = end
        }
        if start < characters.endIndex {
            pieces.append(Text(AttributedString(attributed[start..<characters.endIndex])))
        }
        // Interpolation, not `+`: same composition, no deprecation. It still
        // goes through a `LocalizedStringKey`, though: `"%@%@"`, which the
        // extractor writes out as a real key and a lookup really does search
        // for. Without `bundle: #bundle` that search runs against the *host
        // app's* bundle, so a host carrying its own `%@%@` key would have its
        // translation substituted into the middle of an answer being drawn.
        // The catalog carries the key with `shouldTranslate: false`, so the
        // lookup resolves here and resolves to nothing.
        return pieces.reduce(Text(verbatim: "")) { total, piece in
            Text("\(total)\(piece)", bundle: #bundle)
        }
    }
}

#endif
