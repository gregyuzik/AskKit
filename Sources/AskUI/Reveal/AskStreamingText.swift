#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// An answer's prose, drawn in as it arrives.
///
/// **The clock stops.** A `TimelineView` running while nothing is fading costs a
/// frame's work per frame forever, on every finished turn on the thread, so the
/// timeline is built only while the turn has chunks: while it streams, and
/// until the store drops them 0.05 s after the last sweep settles
/// (`forgetChunksOnceSettled`). Then the view hands back a plain `Text`, with
/// no renderer and no clock. A turn read from disk never has a clock at all.
/// While the turn streams, the clock also pauses whenever every chunk has
/// finished drawing in, as it does between snapshots, and between fades under
/// Reduce Motion, and runs again with the next chunk.
///
/// Under Reduce Motion the blur and the stagger go and the fade stays: a fade is
/// not motion, and holding text back until it is fully opaque would be slower
/// than showing it.
struct AskStreamingText: View {
    private let attributed: AttributedString
    private let chunks: [AskRevealChunk]
    private let showsCaret: Bool
    private let caret: AskCaret

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped once the last chunk has finished drawing in, so the body runs
    /// again and pauses the clock.
    @State private var settledTick = 0

    /// Whether a chunk is still drawing in. It reads `settledTick`, so the
    /// body runs again once the last one has settled.
    private var isDrawing: Bool {
        _ = settledTick
        return AskArrivals.isRevealing(chunks, at: Date.timeIntervalSinceReferenceDate)
    }

    init(
        _ attributed: AttributedString,
        chunks: [AskRevealChunk],
        showsCaret: Bool = false,
        caret: AskCaret = .color(.secondary)
    ) {
        self.attributed = attributed
        self.chunks = chunks
        self.showsCaret = showsCaret
        self.caret = caret
    }

    var body: some View {
        // Reduce Motion takes the caret with the blur and the stagger: a dot
        // chasing the last glyph for the whole turn is motion by any reading,
        // and the reduced reveal is a fade and nothing else.
        let caret = showsCaret && !reduceMotion ? self.caret : nil
        if chunks.isEmpty && caret == nil {
            // At rest: a plain `Text`, with no renderer and no clock. A
            // finished turn lands here once the store drops its chunks. A turn
            // in flight always has chunks, at least the merged stretch, so it
            // keeps the clock, under Reduce Motion too.
            Text(attributed)
        } else {
            // **The stamped text is built once, not once a frame.** It depends
            // on `attributed` and `chunks` and on nothing the clock carries:
            // only the renderer reads `now`. Built inside the closure, it would
            // be rebuilt at the display's rate for the whole of a stream, and
            // `AskReveal.text` isn't cheap to rebuild: it slices the
            // `AttributedString` once per chunk, allocates a `Text` per slice,
            // and joins them through a localized `"%@%@"` lookup.
            //
            // The store answers the case where a settled turn keeps a clock
            // forever: `forgetChunksOnceSettled`, and `settleTurnInFlight` for
            // a turn a new question overtook. This is the other half, the
            // slicing a turn does while it streams, which stopping the clock
            // afterwards never reaches. And since `AskArrivals.chunks` merges
            // what has finished drawing, what is sliced is one settled stretch
            // and the chunks still drying, not a chunk for every snapshot.
            //
            // Safe because a `Text` is a value and its stamps ride with it
            // rather than being resolved where it is built:
            // `AskRevealRenderTests.theStampReachesTheLayout` makes one exactly
            // this way, outside any timeline, and renders it at two different
            // `now`s, which is the shape below. A stamp lost on the way fails
            // silently (`AskReveal.text`), and that test exists to catch it.
            //
            // **At the display's rate, and measured to stay there.** A 60 Hz
            // cap (`.animation(minimumInterval: 1.0 / 60)`) would save under a
            // millisecond a frame: the renderer's own draw of a
            // 1,584-character answer mid-sweep is 0.73 ms merged (2.68 ms at
            // its 285 chunks unmerged), and of two long Private Cloud Compute
            // sweeps 1.3 ms, against 8.3 ms a frame at 120 Hz. Merging took the
            // whole ImageRenderer frame around that draw from 15.2 ms to 3.0.
            // Measured through ImageRenderer at scale 2 on an M4 Pro Mac, so
            // the GPU's share isn't in it; an Instruments run on a device is
            // where that would show.
            let stamped = AskReveal.text(attributed, chunks: chunks)
            // Paused once nothing is drawing in. A paused timeline still draws
            // its last frame, the caret included, and the task wakes the body
            // just after the last chunk settles, so that frame is a settled one.
            TimelineView(.animation(paused: !isDrawing)) { context in
                stamped
                    .textRenderer(
                        AskRevealRenderer(
                            now: context.date.timeIntervalSinceReferenceDate,
                            blurs: !reduceMotion,
                            staggers: !reduceMotion,
                            caret: caret
                        )
                    )
            }
            .task(id: chunks) {
                let remaining = AskArrivals.timeUntilSettled(chunks, at: Date.timeIntervalSinceReferenceDate)
                guard remaining > 0 else { return }
                try? await Task.sleep(for: .seconds(remaining + 0.05))
                guard !Task.isCancelled else { return }
                settledTick &+= 1
            }
        }
    }
}

#endif
