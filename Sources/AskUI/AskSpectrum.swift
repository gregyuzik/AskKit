#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// A run of colors the Ask screen wears where a host asks for it: the spectrum
/// look, `AskScreen(store:spectrum:)`.
///
/// **Two things wear it, and nothing else.** The send circle is filled with
/// a gradient of it, top leading to bottom trailing, and the caret at the end
/// of an answer being written is drawn in the same gradient. The composer's
/// glass, the question bubbles, the wait row's shimmer and every tint keep
/// the accent. With no spectrum the send circle and the caret wear the
/// accent too.
///
/// The send circle wears it on whichever face is on screen: the composer in
/// the screen's bar, or its face in a host's tab bar slot
/// (`askComposerSlot`), for a host that rests the composer there.
///
/// **The send circle's glyph is white, or black where white falls under 3:1
/// on the lightest color the circle is filled with**, the rule the accent's
/// circle keeps (`AskOnAccent`). The glyph can sit on any part of the fill,
/// and no point between two stops is lighter than the lighter of them, so the
/// stops are where white is weakest.
///
/// **Accessibility.** Under Increase Contrast the send circle and the caret
/// go back to the accent. Under Reduce Motion the caret goes, as it does
/// without a spectrum.
///
/// **Isolation.** A value, built and compared on any actor.
nonisolated public struct AskSpectrum: Sendable, Hashable {
    /// The colors, in order, at least two: the send circle and the caret are
    /// filled with them, except for `aurora`'s.
    public let colors: [Color]
    /// What the send circle and the caret are filled with: `colors`, except
    /// for `aurora`, whose ends white can't hold a glyph on.
    let fill: [Color]

    /// Creates a spectrum of `colors`, in order.
    ///
    /// Give it two or more. With one, the spectrum is that color alone; with
    /// none, the app's accent color.
    ///
    /// Choose colors white holds 3:1 on for a white glyph in the send circle:
    /// where one stop is too light for white, the glyph is black over all of
    /// them.
    ///
    /// - Parameter colors: The colors, in the order the gradients run.
    public init(_ colors: [Color]) {
        let stops = Self.twoOrMore(colors)
        self.init(stops, fill: stops)
    }

    /// A spectrum whose send circle and caret are filled with `fill` rather
    /// than with all of `colors`.
    init(_ colors: [Color], fill: [Color]) {
        self.colors = Self.twoOrMore(colors)
        self.fill = Self.twoOrMore(fill)
    }

    /// At least two stops: a gradient needs two ends.
    private static func twoOrMore(_ colors: [Color]) -> [Color] {
        switch colors.count {
        case 0: [.accentColor, .accentColor]
        case 1: colors + colors
        default: colors
        }
    }

    /// The colors of the demo's icon, in Display P3: its glass plates shade
    /// through all five together, from the stack's bottom left corner to its
    /// top right. Cyan, blue, violet, magenta, coral.
    ///
    /// **The send circle and the caret run from blue to violet**, two of the
    /// five. White is 3.81:1 on the blue and 3.95:1 on the violet, and no
    /// point between them is lighter than the blue, so the glyph holds 3.81:1
    /// wherever it sits. The others would not hold it with room to spare:
    /// white is 1.65:1 on the cyan, 2.39:1 on the coral and 3.05:1 on the
    /// magenta, and a fill run on from the violet to the magenta comes to
    /// 3.40:1 under the corners of the widest glyph, the chevron that puts the
    /// keyboard away. WCAG 2's ratio, from each color's luminance in P3's own
    /// terms.
    public static let aurora = AskSpectrum(
        [cyan, blue, violet, magenta, coral],
        fill: [blue, violet]
    )

    private static let cyan = Color(.displayP3, red: 0.30, green: 0.86, blue: 1.0)
    private static let blue = Color(.displayP3, red: 0.24, green: 0.48, blue: 1.0)
    private static let violet = Color(.displayP3, red: 0.56, green: 0.36, blue: 1.0)
    private static let magenta = Color(.displayP3, red: 0.90, green: 0.32, blue: 0.86)
    private static let coral = Color(.displayP3, red: 1.0, green: 0.50, blue: 0.44)
}

/// What the send circle and the caret wear: the host's spectrum, or the
/// accent. Read once from the screen's options and the reader's contrast
/// setting, so the circle and the caret can't disagree.
nonisolated enum AskSpectrumLook: Equatable {
    case accent(Color)
    case spectrum(AskSpectrum)

    /// The spectrum where the host set one, and the accent under Increase
    /// Contrast, where a gradient behind a glyph is what the reader asked to
    /// be rid of.
    static func of(accent: Color, spectrum: AskSpectrum?, contrast: ColorSchemeContrast) -> Self {
        guard let spectrum, contrast != .increased else { return .accent(accent) }
        return .spectrum(spectrum)
    }

    /// The streaming caret: a dot of the accent, or of the spectrum's fill.
    var caret: AskCaret {
        switch self {
        case .accent(let accent): .color(accent)
        case .spectrum(let spectrum): .gradient(spectrum.fill)
        }
    }
}

/// The send circle's fill: the accent, or a linear gradient of the spectrum's
/// fill from the top leading corner to the bottom trailing one
/// (`AskSpectrumLook`).
///
/// **The accent flat, not its `gradient`**, since the glyph on it is judged
/// against the accent (`AskOnAccent`). `Color.gradient` lightens the top:
/// rendered, the system blue's top was the accent with about a fifth of white
/// in it, where white holds about 2.8:1 against the accent's 3.52:1. Judged
/// against that top, the system blue's glyph would turn black, unlike the
/// system's own prominent buttons; filled flat, the circle is what the glyph
/// is judged against. A spectrum's glyph is judged against its gradient's
/// lightest stop (`AskSendGlyph`).
nonisolated struct AskSendFill: ShapeStyle {
    let accent: Color
    let spectrum: AskSpectrum?

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        switch AskSpectrumLook.of(accent: accent, spectrum: spectrum, contrast: environment.colorSchemeContrast) {
        case .accent(let accent):
            AnyShapeStyle(accent)
        case .spectrum(let spectrum):
            AnyShapeStyle(LinearGradient(colors: spectrum.fill, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// The glyph on the send circle: on the accent, `AskOnAccent`'s; on a
/// spectrum, white, or black where white falls under 3:1 on the lightest stop
/// of its fill and black does better on the darkest
/// (`AskContrast.prefersBlack(onStops:minimum:)`).
nonisolated struct AskSendGlyph: ShapeStyle {
    let accent: Color
    let spectrum: AskSpectrum?

    func resolve(in environment: EnvironmentValues) -> Color {
        switch AskSpectrumLook.of(accent: accent, spectrum: spectrum, contrast: environment.colorSchemeContrast) {
        case .accent(let accent):
            return AskOnAccent(accent: accent).resolve(in: environment)
        case .spectrum(let spectrum):
            let stops = spectrum.fill.map { AskContrast.luminance($0.resolve(in: environment)) }
            return AskContrast.prefersBlack(onStops: stops, minimum: AskGlassForeground.glyph) ? .black : .white
        }
    }
}

nonisolated extension AskContrast {
    /// WCAG 2's relative luminance of a resolved color, from its linear
    /// channels and unclamped, so a Display P3 color outside sRGB keeps its
    /// own: the cyan of `AskSpectrum.aurora` is 0.588, where clamping its
    /// encoded sRGB channels (−0.29, 0.87, 1.02) reads 0.600.
    static func luminance(_ resolved: Color.Resolved) -> Double {
        let linear = 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
        return min(1, max(0, linear))
    }

    /// Whether a glyph on a gradient through stops of these luminances is
    /// black: where white falls under `minimum` on the lightest stop and black
    /// does better on the darkest, `prefersBlack(on:minimum:)` across a fill.
    ///
    /// **The stops bound the fill.** Each channel runs straight between two
    /// stops and luminance curves upward in each, so no point between two
    /// stops is lighter than the lighter of them: white's worst is at a stop,
    /// read exactly. Black's worst can dip a little between stops, which only
    /// makes black the less likely choice.
    static func prefersBlack(onStops luminances: [Double], minimum: Double) -> Bool {
        guard let lightest = luminances.max(), let darkest = luminances.min() else { return false }
        let white = 1.05 / (lightest + 0.05)
        let black = (darkest + 0.05) / 0.05
        return white < minimum && black > white
    }
}

#endif
