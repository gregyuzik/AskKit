#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

extension View {
    /// The host's spectrum as a glass rod round this capsule's rim
    /// (`AskGlassRod`), and nothing without a spectrum.
    ///
    /// **Drawn over the capsule and under what sits on it.** Apply it to the
    /// capsule's content before the surface it sits on, its glass or its
    /// wash: the rod is a background of the content, so the glass or wash
    /// goes under it and the text, the placeholder and the circles over it.
    ///
    /// **There whenever its capsule is in sight**, at rest and while a turn
    /// is in flight alike, so it marks where to type. It goes out while the
    /// capsule is covered: the composer resting in a host's slot, where the
    /// face stands in for it, and the face under the screen's composer raised
    /// over it, so only the rod on screen draws.
    ///
    /// **Still at rest; drifting while a turn is in flight** (house rule 4):
    /// the colors drift and shimmer along the rod while the store's clock
    /// runs, which it does while `isThinking`, and the drift fades in and out
    /// on the animation the stage's change runs in, with no animation of its
    /// own.
    ///
    /// - Parameters:
    ///   - spectrum: The host's spectrum, or nil for none.
    ///   - clock: The store's `rodClock`, which every rod on screen reads.
    ///   - facing: Which side of the rod its glow falls: both, mostly outward,
    ///     on the composer; inward on the face in a host's slot.
    ///   - corner: The radius of the capsule's corners, the glass's, or nil
    ///     for a capsule's, half its height.
    ///   - headroom: How far over the capsule's top the glow may reach,
    ///     where something sits that close above it, or nil for its full
    ///     reach.
    ///   - covered: Whether the capsule is out of sight.
    func askGlassRod(
        _ spectrum: AskSpectrum?,
        clock: AskGlassRodClock,
        facing: AskGlassRod.Facing,
        corner: CGFloat? = nil,
        headroom: CGFloat? = nil,
        covered: Bool
    ) -> some View {
        background {
            if let spectrum {
                AskGlassRod(
                    spectrum: spectrum, clock: clock, isCovered: covered, facing: facing,
                    corner: corner, headroom: headroom
                )
            }
        }
    }
}

/// The Glass Rod, the spectrum's light on the composer: its rim becomes a
/// clear glass tube with the spectrum's colors lit inside it, there whenever
/// the composer is, so the place to type stands out.
///
/// **A ray cast into a tube.** Each point across the rod casts a ray into a
/// circle in cross-section, about 6 pt across (5 on the Mac), and bends it as
/// glass would, once for each of red, green and blue, so the glowing core
/// along the tube's middle splits into a faint prism fringe at its sides. The
/// glass turns to a mirror toward its silhouette (Fresnel), a light at the upper
/// left puts a highlight on the upper side, and a soft glow falls just past
/// the tube. In light mode a faint dark line at the silhouette draws the
/// tube on white, as a clear tube shows there. The colors are
/// `spectrum.colors`, handed to the shader as a color array. Light past white
/// is clipped a channel at a time, which whitens the core as a hot light
/// does, but only for what sRGB holds of a color: what a Display P3 color
/// reaches past sRGB goes back on after, so it stays a P3 color
/// (`aDisplayP3ColorKeepsItsGamutInTheCore`).
///
/// **By length round the rim, from the trailing end, out and back**: the
/// first color sits at the trailing end, where the send circle is, the last
/// at the leading end, and the colors between run both ways round the rim to
/// it, at one pace on the straights and round the corners. Run round as a
/// cycle instead, the last color met the first beside the send circle, and
/// aurora's coral and cyan, across the color wheel from each other, mixed to
/// a grey stretch of rod there. In a right-to-left layout the trailing end is
/// on the left. ARCHITECTURE.md's rejected designs say why not by angle.
///
/// **Still at rest; drifting while a turn is in flight.** At rest the colors
/// hold where three slow waves along the rim put them, and nothing draws a
/// frame: the fill renders when it appears and again only when the layout
/// changes. While a turn is in flight the colors drift round the rod, a
/// twentieth of the way round a second, and the waves shimmer through their
/// colors and brightness. That drift is the only difference: the same rod,
/// at the same brightness, at rest and in flight. It fades in and out on the
/// stage's animation (`AskGlassRodFill`): at the turn's end the drifting
/// colors fade back to the resting ones, rather than the clock running back
/// through every color it drifted past.
///
/// **Over the capsule's edge, under what sits on it.** The rod is centred on
/// the glass's outline, above the glass, so its highlight stays sharp, and
/// under the text, the placeholder and the circles, which it stays clear of:
/// its inner side reaches about 3.6 pt inside the capsule, and the circles
/// sit 7 pt in (4 pt on the Mac, where the rod is thinner), at four lines as
/// at one, since the capsule's corners keep their radius as it grows and
/// the rod follows them (`corner`). Its glow reaches about 20 pt past the
/// capsule, except over its top where something sits closer, the photo
/// waiting for the next question (`headroom`). It is a fill,
/// never glass or a `Material` (AskGlass.swift says why), so Reduce
/// Transparency leaves it as it is. On the face in a host's slot, which the
/// slot's own glass holds, the rod sits just inside the face's edge, over
/// its wash, with its glow falling inward and nothing past the face.
///
/// **Arithmetic, not blur.** AskGlassRod.metal works out each point's
/// distance from the capsule and its place round the rim, and the light from
/// those: one pass over the capsule and the glow's reach, with no blur, no
/// mask and no offscreen layer. A point the glow has faded from and the tube
/// doesn't cross, most of a tall composer's middle, returns before any of
/// the color work.
///
/// **Twenty frames a second while a turn is in flight**, and none at rest,
/// while the capsule is covered or under Reduce Motion. Measured with Time
/// Profiler over 10 s on an iPhone 18 Pro simulator (iOS 27.2), against the
/// same screen under Increase Contrast, which draws no rod: at rest the demo
/// took 0.01% of a core or less and committed no more than twice either way,
/// since nothing draws. With a turn held in flight (the demo's
/// `-askHoldTurn`), three runs each, the demo took 7.0% to 10.6% against
/// 5.8% to 9.5%, 1.2 points more on average, and the simulator's render
/// server, backboardd, 12.8% to 15.1% against 7.9% to 9.1%, 5.8 more, for
/// about 20 commits a second more. The Mac was busy (load averages of 7 to
/// 15), which raises both sides, and a simulator's render server encodes
/// every Metal pass for the Mac's GPU, which a device trace would show.
///
/// **Nothing under Increase Contrast** (`AskSpectrumLook`). Under Reduce
/// Motion the rod stays and its colors hold still, in flight as at rest
/// (house rule 8).
struct AskGlassRod: View {
    let spectrum: AskSpectrum
    let clock: AskGlassRodClock
    let isCovered: Bool
    let facing: Facing
    var corner: CGFloat?
    var headroom: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.displayScale) private var displayScale

    /// Where the rod sits on the capsule, and which side its glow falls.
    nonisolated enum Facing: Equatable {
        /// On the composer's glass: the rod centred on the glass's outline,
        /// its glow falling on both sides, mostly outside.
        case outward
        /// On the face in a host's slot, inside the slot's glass: the rod
        /// just inside the face's edge, its glow falling inward, and nothing
        /// past the face.
        case inward

        /// The tube's radius.
        var radius: CGFloat {
            switch self {
            case .outward: AskGlassRodShape.radius
            case .inward: AskGlassRodShape.faceRadius
            }
        }

        /// From the composer's capsule out to the rod's centre line; less
        /// than zero is inside it. Facing out, 0.4 pt inside the outline, so
        /// the tube straddles the glass's edge; facing in, far enough in that
        /// the whole tube is inside the face.
        var outset: CGFloat {
            switch self {
            case .outward: -0.4
            case .inward: -(radius + 0.4)
            }
        }

        /// How far past the composer's capsule the fill reaches.
        var reach: CGFloat {
            switch self {
            case .outward: outset + radius + AskGlassRodShape.glowReach
            case .inward: 0
            }
        }

        /// The shader's sign for the side the glow falls toward.
        var sign: Float {
            switch self {
            case .outward: 1
            case .inward: -1
            }
        }
    }

    var body: some View {
        // Lit where the send circle and the caret wear the spectrum, and out
        // where they wear the accent instead (`AskSpectrumLook`), so the
        // three never disagree. The accent itself plays no part in the rod.
        if let lit = AskSpectrumLook.of(accent: .clear, spectrum: spectrum, contrast: contrast).glow {
            let motion = AskGlassRodMotion.of(isThinking: clock.runs, isCovered: isCovered, reduceMotion: reduceMotion)
            AskGlassRodFill(
                colors: lit.colors,
                on: motion.isDrawn ? 1 : 0,
                drift: motion.drifts ? 1 : 0,
                ticks: motion.ticks,
                facing: facing,
                corner: corner,
                headroom: headroom,
                mirror: layoutDirection == .rightToLeft ? -1 : 1,
                dark: colorScheme == .dark ? 1 : 0,
                scale: Float(displayScale),
                clock: clock
            )
            .allowsHitTesting(false)
            // **No element, rather than a hidden one**, as the composer's
            // placeholder has it. Hidden by name, the light came back under
            // `AskScreen`'s `.accessibilityHidden(composerRests)`, false
            // whenever the composer is up: Apple's audit read it as an element
            // with no description, the capsule's size, on the demo's first
            // screen (iPhone 18 Pro simulator, iOS 27.2).
            .accessibilityRepresentation { EmptyView() }
        }
    }
}

/// What the rod does, from whether a turn is in flight, whether its capsule
/// is covered and Reduce Motion, apart from the view so it can be pinned.
nonisolated struct AskGlassRodMotion: Equatable {
    /// Whether the rod is drawn: whenever its capsule is in sight, at rest
    /// and in flight alike.
    let isDrawn: Bool
    /// Whether the colors drift: while a turn is in flight, except under
    /// Reduce Motion.
    let drifts: Bool
    /// Whether the rod draws frames on a clock: while it drifts and is
    /// drawn. At rest it renders when it appears and when the layout
    /// changes, and never on a clock.
    let ticks: Bool

    static func of(isThinking: Bool, isCovered: Bool, reduceMotion: Bool) -> Self {
        let drifts = isThinking && !reduceMotion
        return Self(isDrawn: !isCovered, drifts: drifts, ticks: drifts && !isCovered)
    }
}

/// The rod itself: the shader as a fill, on a rectangle that reaches past
/// the capsule by the glow's reach, `.boundingRect` telling the shader where
/// that is.
///
/// **`on` and `drift` are animatable**, so the transaction that covers the
/// capsule carries the rod out and back, and the stage's carries the drift
/// in and out, with no animation of the rod's own (house rule 4). Only the
/// drift runs on the clock, in a timeline paused whenever it isn't
/// drifting.
private struct AskGlassRodFill: View, Animatable {
    let colors: [Color]
    var on: Double
    var drift: Double
    let ticks: Bool
    let facing: AskGlassRod.Facing
    let corner: CGFloat?
    let headroom: CGFloat?
    let mirror: Float
    let dark: Float
    let scale: Float
    let clock: AskGlassRodClock

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(on, drift) }
        set {
            on = newValue.first
            drift = newValue.second
        }
    }

    var body: some View {
        if on > 0 {
            // Paused, so it draws no frames, at rest, while the capsule is
            // covered and under Reduce Motion; kept in the tree rather than
            // swapped for a plain fill, so the drift's fade at the end of a
            // turn animates the same fill.
            TimelineView(.animation(minimumInterval: AskGlassRodClock.frame, paused: !ticks)) { context in
                Rectangle()
                    .fill(AskGlassRodShape.function(
                        .boundingRect,
                        .float(facing.reach),
                        .float(facing.outset),
                        .float(facing.radius),
                        .float(corner ?? AskGlassRodShape.unbounded),
                        .float(headroom ?? AskGlassRodShape.unbounded),
                        .float(facing.sign),
                        .float(mirror),
                        .float(clock.time(at: context.date)),
                        .float(drift),
                        .float(on),
                        .float(dark),
                        .float(scale),
                        .colorArray(colors)
                    ))
            }
            .padding(-facing.reach)
        }
    }
}

/// What the shader takes that isn't the moment's: its function, and the
/// numbers the Swift side sizes the fill by.
nonisolated enum AskGlassRodShape {
    /// `askGlassRod` in AskGlassRod.metal, from AskUI's own bundle. SwiftPM
    /// and Xcode compile the file into the bundle's `default.metallib` for
    /// all five platforms, tvOS and watchOS included, where nothing loads it,
    /// so it takes no platform gate. A name that doesn't match draws nothing
    /// and throws nothing, so a test reads it from the library.
    static let functionName = "askGlassRod"
    static let bundle = Bundle.module
    static let function = ShaderFunction(library: .bundle(bundle), name: functionName)

    #if os(macOS)
    /// The tube's radius on the composer: on the Mac, whose circles sit 4 pt
    /// inside its 36 pt capsule, thinner, so it stays clear of them.
    static let radius: CGFloat = 2.4
    #else
    /// The tube's radius on the composer, whose circles sit 7 pt inside its
    /// capsule at every height.
    static let radius: CGFloat = 3.2
    #endif

    /// The tube's radius on the face in a host's slot, where it sits wholly
    /// inside the face, whose circles are 7 pt in at every size.
    static let faceRadius: CGFloat = 2.8

    /// How far past the tube the glow reaches before the fill ends: its
    /// falloff is 5 pt, so at 20 pt it is down to 1%, and the shader takes
    /// it the rest of the way to nothing over the last 40%.
    static let glowReach: CGFloat = 20

    /// A `corner` or `headroom` past anything the shader measures: a
    /// capsule's ends, or the glow's full reach. Finite, since the shader
    /// compiles with fast math, which assumes no infinities.
    static let unbounded: CGFloat = 10_000
}

/// The clock the colors drift by while a turn is in flight: the store's
/// (`AskConversationStore.rodClock`), so every rod on screen drifts in step.
///
/// **Set in the update the turn starts or ends in**, with `isThinking`, so a
/// rod never reads the last turn's clock for a frame: at the send the colors
/// drift from where they rest, and at the end they stop where they got to,
/// for the stage's animation to fade back to the colors at rest from.
///
/// **A send while that fade is still running picks the colors up where they
/// stopped** rather than at rest, so they carry on drifting as the drift
/// fades back in, rather than jump back to the start.
nonisolated enum AskGlassRodClock: Equatable {
    /// No turn yet: the colors at rest.
    case resting
    /// Drifting since `since`: the send, or earlier by where a turn that had
    /// only just ended stopped.
    case drifting(since: Date)
    /// Stopped where the last turn left the colors, which the stage's
    /// animation fades back to the colors at rest.
    case stopped(since: Date, until: Date)

    /// The longest a frame waits while the colors drift, when nothing moves
    /// faster than about 40 pt a second round the screen's bar, and that in
    /// broad washes of color.
    static let frame: TimeInterval = 1.0 / 20.0

    /// How soon after a turn's end a send carries the colors on from where
    /// they stopped: longer than the stage's animation (`AskStage.animation`,
    /// 0.28 s) takes to fade the drift out and settle.
    static let carry: TimeInterval = 0.5

    /// Whether the clock runs: while a turn is in flight.
    var runs: Bool {
        if case .drifting = self { true } else { false }
    }

    /// This clock started at `date`, as a turn begins: from 0, the colors at
    /// rest, or, within `carry` of the last turn's end, from where that turn
    /// stopped.
    func started(at date: Date) -> Self {
        if case .stopped(let since, let until) = self, date.timeIntervalSince(until) < Self.carry {
            return .drifting(since: date - until.timeIntervalSince(since))
        }
        return .drifting(since: date)
    }

    /// This clock stopped at `date`, if it was drifting.
    func stopped(at date: Date) -> Self {
        guard case .drifting(let since) = self else { return self }
        return .stopped(since: since, until: date)
    }

    /// Seconds on the clock at `date`: 0, where the colors rest, before any
    /// turn. The shader reads it only while the colors drift, so under Reduce
    /// Motion, where they never do, it goes unread.
    func time(at date: Date) -> Double {
        switch self {
        case .resting:
            0
        case .drifting(let since):
            max(0, date.timeIntervalSince(since))
        case .stopped(let since, let until):
            max(0, until.timeIntervalSince(since))
        }
    }
}

#endif
