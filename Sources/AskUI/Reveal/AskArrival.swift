#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// How the rest of an answer arrives: the tiles it chose, the line saying what
/// it read, the cards and buttons under it, and the follow-ups, **each the way
/// its words do.**
///
/// The reveal draws every stretch of prose up out of a blur
/// (`AskRevealRenderer`). Each other piece under an answer comes up out of the
/// same blur, one short step behind the piece before it in reading order, in
/// waves: the tiles, then the lines and cards beneath them, then the follow-ups
/// when the stream ends. Inserted whole, a piece would read as a pop beside ink
/// still being drawn in. A picture that lands later than the piece it sits in, such
/// as a photo still decoding, crosses its placeholder on the same blur through
/// `AskPictureArrival`.
///
/// **Drawn, never laid out.** Opacity, blur and scale, none of which moves a
/// frame. The answer's layout still lands whole in one frame, on the Stage's
/// change, so the follow carries one growth rather than chasing a cascade, and
/// a piece answers a tap from the moment it is there. Nothing is held back:
/// the first piece starts in the frame the answer lands, and the stagger stops
/// growing at `lastStep`, so a grid of twenty is in as soon as a grid of seven.
///
/// **Once, for an answer that ends while the reader watches.** Only the turn
/// that ended most recently brings its pieces in. A thread read back from
/// disk, a chat opened from history and every turn above the newest draw
/// theirs at rest, as a restored turn's prose does, and so does a piece built
/// more than `liveWindow` after its answer ended.
///
/// Reduce Motion keeps the fade, as the reveal does, and drops the blur, the
/// scale and the stagger.
nonisolated public enum AskArrival {
    /// What a piece is, which decides how it comes up.
    public enum Kind: Sendable {
        /// Words: the evidence line, a note, a chip's question. Out of a blur
        /// on the reveal's own curve, and nothing else: words don't grow.
        case line
        /// An object: a tile, a card, a button. The same, growing from a
        /// little smaller.
        case piece
    }

    /// Between one piece and the next. Shorter than a chunk's shortest sweep
    /// (`AskArrivals.stagger`, 80 ms): a wave is a longer thing than a chunk,
    /// and the last of its pieces has to land with the answer.
    static let stagger: TimeInterval = 0.05

    /// Where a count of steps stops growing: 300 ms, still part of the answer
    /// that just landed rather than something late. A wave's base and a
    /// piece's place within the wave are each capped by it on their own, so
    /// the whole cascade reaches 600 ms and no further.
    static let lastStep = 6

    /// How much smaller a piece starts. Felt rather than seen.
    static let scale: CGFloat = 0.94

    /// How far out of focus a piece starts. A line about as far as the reveal
    /// takes body text; a piece further, since that little blur on a photo
    /// doesn't show.
    static func blur(for kind: Kind) -> CGFloat {
        switch kind {
        case .line: 3
        case .piece: 8
        }
    }

    /// What a count of `step` steps is worth, capped at `lastStep`.
    static func delay(forStep step: Int) -> TimeInterval {
        Double(min(max(step, 0), lastStep)) * stagger
    }

    /// When a piece starts, after its answer lands: its wave's `base` (the
    /// steps the row spent above the wave) plus its own place within the wave.
    ///
    /// **Each part is capped before they are added, because capping the sum
    /// collapses the wave.** The follow-ups' base is the deepest a row sets,
    /// and with a basis line above them it already stands at `lastStep`. Under
    /// a capped sum, every chip would ask for the delay the first one already
    /// has, and a bank of four would come in on one frame under prose that had
    /// drawn itself in properly. The cap keeps a long wave landing with its
    /// answer; it doesn't take away a deep wave's own reading order.
    static func delay(base: Int, forStep step: Int) -> TimeInterval {
        delay(forStep: base) + delay(forStep: step)
    }

    /// How long after its answer ends a piece built for it still arrives. Well
    /// past the cascade (no piece starts after 600 ms, and no curve takes
    /// longer than 400) and well short of scrolling a thread away and back.
    ///
    /// The thread is a lazy stack, and a row it rebuilds when the reader
    /// scrolls back to it starts its pieces' state afresh. Marked only by which
    /// turn ended, the newest answer would arrive all over again every time it
    /// came back on screen.
    static let liveWindow: TimeInterval = 2

    /// Whether a piece built at `now` arrives, for an answer that ended at
    /// `endedAt`: never for one that has not ended, nor one that ended too long
    /// ago for this to be its ending.
    static func isLive(endedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let endedAt else { return false }
        return now - endedAt < liveWindow
    }

    /// The curve a piece comes up on. `base` is its wave's, and defaults to
    /// none for a piece that stands outside the cascade, such as a picture
    /// crossing its own placeholder.
    static func animation(for kind: Kind, base: Int = 0, step: Int, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeOut(duration: AskArrivals.fade) }
        let curve: Animation = switch kind {
        // The reveal's own fade, so a line reads as more of the prose.
        case .line: .easeOut(duration: AskArrivals.settle)
        // Long enough for the scale to reach full size rather than snap, and no bounce:
        // overshoot on glass refracting what is behind it reads as a wobble.
        case .piece: .smooth(duration: 0.4)
        }
        return curve.delay(delay(base: base, forStep: step))
    }
}

extension EnvironmentValues {
    /// When the answer the pieces drawn here belong to ended, on the store's
    /// clock. `AskThreadRow` sets it on the turn that ended most recently; on
    /// every other turn and everywhere outside a thread it is nil, so a grid
    /// drawn there is simply drawn.
    @Entry var askArrivalEnding: TimeInterval?

    /// The step a wave's pieces count from: how much of the answer's cascade
    /// the row has already spent above the wave. Capped on its own, so a wave
    /// set deeper than `lastStep` still staggers its own pieces from wherever
    /// the cap put it (`AskArrival.delay(base:forStep:)`).
    @Entry var askArrivalFirstStep = 0
}

extension View {
    /// Brings this piece of an answer in the way the answer's words arrive
    /// (`AskArrival`).
    ///
    /// `step` is the piece's place in reading order within its wave:
    /// `AskTileGrid` passes each tile's index, a footer counts its own pieces
    /// from zero, and the thread starts each wave after the pieces above it.
    /// `kind` decides how the piece comes up: `.line` for words, `.piece` for
    /// an object.
    ///
    /// Apply it outside a `matchedTransitionSource` and never inside, so a zoom
    /// grows out of the tile's laid-out frame rather than a transformed one.
    ///
    /// Outside the answer that has just ended, it draws the piece at rest.
    public func askArrival(_ step: Int = 0, as kind: AskArrival.Kind = .piece) -> some View {
        modifier(AskArrivalModifier(step: step, kind: kind))
    }
}

private struct AskArrivalModifier: ViewModifier {
    let step: Int
    let kind: AskArrival.Kind

    @Environment(\.askArrivalEnding) private var ending
    @Environment(\.askArrivalFirstStep) private var firstStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Read against the clock here, where the piece is first built: a piece
        // built too late to arrive has to be drawn at rest from its first
        // frame, or it is drawn hidden for that frame and then fades up anyway.
        AskArrivalBody(
            content: content,
            base: firstStep,
            step: step,
            kind: kind,
            arrives: AskArrival.isLive(endedAt: ending, now: Date.timeIntervalSinceReferenceDate),
            reduceMotion: reduceMotion
        )
    }
}

/// The piece itself, so whether it arrives can be decided in an `init`: a
/// `ViewModifier` has no way to read the environment before its state is made.
///
/// **That is the whole reason this type exists, and the thread's scroll is what
/// it saves.** Seeded here, a piece drawn at rest does no work at all: the task
/// finds its answer already given and returns. Started false and corrected by
/// the task, every piece of every turn the lazy stack builds (a scrolled-back
/// row's tiles, its evidence line, its footer) would write state and cost a
/// second body pass, to reach the value it was always going to have.
private struct AskArrivalBody<Content: View>: View {
    private let content: Content
    private let base: Int
    private let step: Int
    private let kind: AskArrival.Kind
    private let reduceMotion: Bool

    /// Whether the piece is drawn at full: by arriving, or by being drawn at
    /// rest in the first place. Seeded at build and flipped once.
    @State private var hasArrived: Bool

    init(content: Content, base: Int, step: Int, kind: AskArrival.Kind, arrives: Bool, reduceMotion: Bool) {
        self.content = content
        self.base = base
        self.step = step
        self.kind = kind
        self.reduceMotion = reduceMotion
        // Drawn at rest, and so at rest for good: a later ending must never
        // take a piece already on screen away to bring it back.
        _hasArrived = State(initialValue: !arrives)
    }

    var body: some View {
        let moves = !hasArrived && !reduceMotion
        // The same three modifiers whatever the state, at identity once the
        // piece is in: a modifier that came and went would change the piece's
        // identity, and take any state inside it, such as a decoded photo, with
        // it.
        content
            // Scoped to the three effects rather than `withAnimation`. The
            // screen's animation on `Stage` replaces the animation of every
            // transaction beneath it that the stage changes in, and the stage
            // changes again as the stream behind an answer ends, the same
            // moment its pieces start to arrive. An animation on the effects
            // themselves is nearer than that one, so it is the one they take.
            .animation(AskArrival.animation(for: kind, base: base, step: step, reduceMotion: reduceMotion)) { effects in
                effects
                    .blur(radius: moves ? AskArrival.blur(for: kind) : 0)
                    .scaleEffect(moves && kind == .piece ? AskArrival.scale : 1)
                    .opacity(hasArrived ? 1 : 0)
            }
            .task {
                guard !hasArrived else { return }
                // A turn late, so the frame that draws the piece hidden is
                // committed first. Flipped in the same update, the two
                // coalesce and the piece simply appears.
                await Task.yield()
                guard !Task.isCancelled else { return }
                hasArrived = true
            }
    }
}

#endif
