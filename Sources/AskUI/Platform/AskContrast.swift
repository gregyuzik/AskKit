#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

extension View {
    /// Deemphasized text that stays readable: a step below `.primary`, and clear
    /// of Apple's accessibility audit on its ground.
    ///
    /// **`.secondary` isn't enough on a light ground.** iOS draws it as
    /// #3C3C43 at 60%: 3.44:1 on white and 3.30:1 on grouped #F2F2F7, under
    /// the 4.5:1 WCAG bar for text this size. The Mac's is black at 50%,
    /// 3.98:1 on its white window. The audit's contrast check, run on the
    /// first screen alone, reads the sentences on it as failing at 50%,
    /// nearly passing at 60% and 68% and passing at 76%, which is the strength
    /// iOS's hue gets instead: 5.31:1 on white, the Mac's window included,
    /// and 4.98:1 on #F2F2F7, still a step below `.primary`. `.tertiary` is
    /// 1.73:1.
    ///
    /// **A dark ground keeps `.secondary`, because the audit passes it.** iOS's
    /// #EBEBF5 at 60% is about #8D8D93 on black, 6.36:1, and the same check
    /// reads every line of the first screen drawn in it as passing, though
    /// APCA's lightness contrast puts it at Lc 41, under the Lc 62 of the light
    /// `.secondary` that only nearly passes: on dark the audit agrees with
    /// WCAG's ratio, and APCA doesn't. It is 5.27:1 even on #2C2C2E. The
    /// Mac's white at 55% is 5.91:1 on its #1E1E1E window; that leg isn't
    /// UI-tested. visionOS keeps `.secondary` too: its text sits on glass,
    /// where `.secondary` is vibrant and a fixed color wouldn't be.
    ///
    /// **Measured on a call of its own.** With `.dynamicType` and another check
    /// in the same call, the audit fails the disclosure line in both appearances at every
    /// strength, #3C3C43 at 100% on white and #EBEBF5 at 100% on black
    /// included, and fails "Try asking" in light the same way: verdicts that
    /// don't follow the color. The demo's suite audits contrast apart from the
    /// other checks for that reason (`testTheScreenPassesApplesAccessibilityAudit`).
    ///
    /// Increase Contrast takes it the rest of the way to `.primary`. Two steps
    /// rather than one, because `.primary` everywhere would flatten the
    /// hierarchy the screen is built on for readers who didn't ask for that.
    ///
    /// For *text* on an opaque ground. A hairline or a decorative glyph has no
    /// contrast bar to meet, and text on glass stays hierarchical, for its
    /// vibrancy, which a fixed color would lose (`AskGlassForeground`).
    public func askDeemphasizedText() -> some View {
        modifier(AskDeemphasizedText())
    }
}

/// Text or a glyph on glass: `.secondary` where it clears the contrast its
/// size needs over the glass, and `.primary` where it doesn't.
///
/// **Hierarchical either way, never a fixed color.** Content on glass draws
/// vibrant, and glass follows what is under it and the reader's transparency
/// setting, where a fixed color would stay put; `askDeemphasizedText`'s boosted
/// gray is for opaque grounds. So the choice is the one between the two
/// hierarchical levels.
///
/// **The ground is estimated, not measured**: the glass's base, white in light
/// mode and #2C2C2E in dark, with its tint laid over it as a flat blend
/// (`AskContrast.ground(isLight:tint:)`). Liquid Glass isn't a flat blend, and
/// glass over dark content can darken, so this is a bar to clear, not a
/// reading: the demo's `testTheEmptyComposerPassesTheContrastAudit` is where
/// Apple's own audit reads the real thing. What the estimate says: iOS's
/// `.secondary` is 3.44:1 on white, under 4.5:1 for text before any tint, and
/// on the composer's capsule, the system blue (#0088FF) at half strength,
/// 2.66:1, under 3:1 for a glyph as well. In dark mode it clears both on untinted
/// glass (5.27:1) and on a dark accent's tint, and falls short on a light
/// one. Increase Contrast takes it to `.primary` always. visionOS keeps
/// `.secondary`, as `askDeemphasizedText` does: its glass isn't Liquid Glass,
/// and its tint is a far fainter fill (`AskGlass.visionTintOpacity`).
nonisolated struct AskGlassForeground: ShapeStyle {
    /// The bar for text a reader has to read.
    static let text = 4.5
    /// The bar for a glyph that says what a control does.
    static let glyph = 3.0

    /// The glass's tint as the glass wears it, opacity included, or nil for
    /// untinted glass.
    let tint: Color?
    /// The contrast `.secondary` has to clear to stay.
    let minimum: Double

    init(tint: Color? = nil, minimum: Double) {
        self.tint = tint
        self.minimum = minimum
    }

    func resolve(in environment: EnvironmentValues) -> HierarchicalShapeStyle {
        if environment.colorSchemeContrast == .increased { return .primary }
        #if os(visionOS)
        return .secondary
        #else
        let worn = tint.map { AskContrast.Tint($0.resolve(in: environment)) }
        let clears = AskContrast.secondaryClears(minimum, isLight: environment.colorScheme == .light, tint: worn)
        return clears ? .secondary : .primary
        #endif
    }
}

/// A glyph drawn on a fill of the host's accent: white, or black on an accent
/// too light to hold white at 3:1 (`AskContrast.prefersBlack(on:minimum:)`).
///
/// **The accent is the host's, so white can't be taken for granted.** The
/// system blue holds a white arrow at 3.52:1 and keeps it. A yellow or a mint
/// accent would leave it at 1.41:1 on #FFD60A and 1.51:1 on #63E6E2, where
/// black is over 13:1 on either.
nonisolated struct AskOnAccent: ShapeStyle {
    let accent: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        AskContrast.prefersBlack(on: AskContrast.RGB(accent.resolve(in: environment)), minimum: AskGlassForeground.glyph) ? .black : .white
    }
}

/// A system button style's label on a fill of the host's accent, such as
/// `.borderedProminent` tinted with it: the style's own white where white
/// holds 4.5:1 on the accent, and black, the label and a spinner in it, where
/// white falls under that and black does better
/// (`AskContrast.prefersBlack(on:minimum:)`). Disabled, it is the style's
/// whatever the accent, so the style's disabled look stands.
///
/// **Text's 4.5:1, not a glyph's 3:1.** The label is words to read, at the
/// style's own size and weight: AskKit sets neither on it, and 3:1 is the bar
/// for large or bold text. Apple's audit holds it to more than 3:1 as well: it
/// reads white on the system blue, 3.52:1, as "nearly passed", short of its
/// bar, where 3:1 would pass it. So the label is black on the system blue,
/// 5.97:1 on #0088FF and 6.49:1 on dark mode's #0091FF, where white is 3.52:1
/// and 3.23:1; black on #007AFF, 5.23:1 to white's 4.02:1, and on the system
/// red (#FF383C), 5.88:1 to 3.57:1; and white on a dark accent such as navy.
/// Either way it holds 4.5:1 on every accent: white and black are both about
/// 4.58:1 where they cross, so one of the two always clears it.
///
/// **On the label, not the button**: the style draws its label white whatever
/// the tint, and a style set outside the label is the style's to ignore. The
/// button wears the same `accent` as its tint, so the fill under the words is
/// the color they were judged on.
///
/// **visionOS keeps the style's own label.** Its prominent button is a
/// `.bordered` platter with no fill of the accent (`askGlassButton`), so no
/// accent sits under the words to judge them on, and black there would be
/// black on a dark platter.
///
/// Text on a fill of the accent over the screen, such as the question bubble,
/// is `AskOnFill`, held to the same 4.5:1 on the fill as it is worn, opacity
/// and the screen under it included.
struct AskOnAccentLabel: ViewModifier {
    let accent: Color

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        if environment.isEnabled, Self.isBlack(on: AskContrast.RGB(accent.resolve(in: environment))) {
            content
                .foregroundStyle(.black)
                .tint(.black)
        } else {
            content
        }
    }

    /// Whether the words on `accent` are black rather than the style's white:
    /// where white falls under text's 4.5:1 on it and black does better.
    /// Never on visionOS, where no fill of the accent sits under them.
    nonisolated static func isBlack(on accent: AskContrast.RGB) -> Bool {
        #if os(visionOS)
        false
        #else
        AskContrast.prefersBlack(on: accent, minimum: AskGlassForeground.text)
        #endif
    }
}

/// Text on a fill of the host's accent laid on the content layer, such as the
/// question bubble: `.primary`, or the color opposite to it where `.primary`
/// falls under 4.5:1 on the fill and the opposite does better
/// (`AskContrast.prefersInverse(on:isLight:minimum:)`).
///
/// **The ground is the fill over the screen** (`AskContrast.screen(isLight:)`),
/// worked out flat, which a fill is, where glass's ground is an estimate. At
/// the bubble's 60%, the system blue holds white at 6.28:1 in dark mode, on
/// its #0091FF, and black at 9.83:1 in light, on #0088FF. A light accent
/// leaves white short in dark mode: 3.29:1 on yellow (#FFD60A), 3.47:1 on
/// mint (#63E6E2) and 3.85:1 on cyan (#64D2FF), where black is 6.38:1, 6.06:1
/// and 5.45:1, so the words there are black. In light mode black holds on every accent AskKit has been
/// measured with, 8.56:1 at the least, on indigo.
///
/// **A fixed color is right here, as it isn't on glass** (`AskGlassForeground`):
/// a fill isn't glass, and has no vibrancy for black or white to lose.
/// visionOS keeps `.primary`: there the bubble is its window's glass with a
/// faint fill of the accent (`AskGlass.visionTintOpacity`), and white holds.
nonisolated struct AskOnFill: ShapeStyle {
    /// The fill as it is worn, opacity included.
    let fill: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        #if os(visionOS)
        return .primary
        #else
        let isLight = environment.colorScheme == .light
        guard Self.isInverse(fill: AskContrast.Tint(fill.resolve(in: environment)), isLight: isLight) else { return .primary }
        return isLight ? .white : .black
        #endif
    }

    /// Whether text on `fill` over the screen is drawn opposite to `.primary`.
    static func isInverse(fill: AskContrast.Tint, isLight: Bool) -> Bool {
        let ground = AskContrast.over(fill.color, opacity: fill.opacity, AskContrast.screen(isLight: isLight))
        return AskContrast.prefersInverse(on: ground, isLight: isLight, minimum: AskGlassForeground.text)
    }
}

/// WCAG 2's contrast arithmetic, and the grounds AskUI estimates it on, apart
/// from the views so it can be pinned (`AskAccessibilityTests`).
nonisolated enum AskContrast {
    /// A color in gamma-encoded sRGB, each channel 0 to 1.
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ resolved: Color.Resolved) {
            self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
        }

        static let white = RGB(red: 1, green: 1, blue: 1)
        static let black = RGB(red: 0, green: 0, blue: 0)
    }

    /// A tint as glass wears it: its color, and how strongly.
    struct Tint: Equatable {
        var color: RGB
        var opacity: Double

        init(_ color: RGB, opacity: Double) {
            self.color = color
            self.opacity = opacity
        }

        init(_ resolved: Color.Resolved) {
            self.init(RGB(resolved), opacity: Double(resolved.opacity))
        }
    }

    /// WCAG 2's relative luminance.
    static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            let clamped = min(1, max(0, channel))
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// WCAG 2's contrast ratio, from 1 to 21, in either order.
    static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `top` at `opacity` over `bottom`, blended channel by channel.
    static func over(_ top: RGB, opacity: Double, _ bottom: RGB) -> RGB {
        let alpha = min(1, max(0, opacity))
        return RGB(
            red: top.red * alpha + bottom.red * (1 - alpha),
            green: top.green * alpha + bottom.green * (1 - alpha),
            blue: top.blue * alpha + bottom.blue * (1 - alpha)
        )
    }

    /// The glass's base: white in light mode, and in dark mode #2C2C2E, the
    /// lightest dark ground `askDeemphasizedText` measures `.secondary` on.
    static func base(isLight: Bool) -> RGB {
        isLight ? .white : RGB(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    }

    /// The glass with its tint over the base, as a flat blend.
    static func ground(isLight: Bool, tint: Tint?) -> RGB {
        let base = base(isLight: isLight)
        guard let tint else { return base }
        return over(tint.color, opacity: tint.opacity, base)
    }

    /// `.secondary`'s hue and strength: iOS's #3C3C43 at 60% on light and
    /// #EBEBF5 at 60% on dark, and the Mac's black at 50% and white at 55%.
    static func secondary(isLight: Bool) -> (color: RGB, opacity: Double) {
        #if os(macOS)
        isLight ? (.black, 0.5) : (.white, 0.55)
        #else
        isLight
            ? (RGB(red: 60 / 255, green: 60 / 255, blue: 67 / 255), 0.6)
            : (RGB(red: 235 / 255, green: 235 / 255, blue: 245 / 255), 0.6)
        #endif
    }

    /// The gray `askDeemphasizedText` draws on a light ground: iOS's secondary
    /// label hue, #3C3C43, at 76% rather than `.secondary`'s 60%.
    static let deemphasizedLight = (color: RGB(red: 60 / 255, green: 60 / 255, blue: 67 / 255), opacity: 0.76)

    /// Whether `.secondary` clears `minimum` on glass wearing `tint`.
    static func secondaryClears(_ minimum: Double, isLight: Bool, tint: Tint?) -> Bool {
        let ground = ground(isLight: isLight, tint: tint)
        let secondary = secondary(isLight: isLight)
        return ratio(over(secondary.color, opacity: secondary.opacity, ground), ground) >= minimum
    }

    /// The screen a fill on the content layer sits on: white in light mode, and
    /// in dark mode #1E1E1E, the Mac's window and about an iOS screen raised in
    /// a sheet (#1C1C1E). An iPhone's own screen is black, where white text
    /// holds more than it does here, so this is the bar's worst case.
    static func screen(isLight: Bool) -> RGB {
        isLight ? .white : RGB(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    }

    /// `.primary` in `isLight`'s appearance, as the estimate reads it: black on
    /// light, white on dark. The Mac draws its label at 85%, a little under
    /// this, which the bar's margin covers.
    static func primary(isLight: Bool) -> RGB {
        isLight ? .black : .white
    }

    /// Whether text on `ground` is drawn in the color opposite to `.primary`:
    /// where `.primary` falls under `minimum` on it and the opposite does
    /// better. White in light mode on a dark fill, and black in dark mode on a
    /// light one, such as a yellow or a mint accent.
    static func prefersInverse(on ground: RGB, isLight: Bool, minimum: Double) -> Bool {
        let held = ratio(primary(isLight: isLight), ground)
        return held < minimum && ratio(primary(isLight: !isLight), ground) > held
    }

    /// The most of `tint`, up to `ceiling`, that glass can wear and keep
    /// `.primary` at `minimum` on it (`ground(isLight:tint:)`), in steps of a
    /// hundredth. `ceiling` itself where it already does, as every dark
    /// accent does in either appearance; less in dark mode for a light accent,
    /// whose tint lightens the glass under white text.
    static func tintStrength(_ tint: RGB, ceiling: Double, isLight: Bool, minimum: Double) -> Double {
        let words = primary(isLight: isLight)
        func holds(_ strength: Double) -> Bool {
            ratio(words, ground(isLight: isLight, tint: Tint(tint, opacity: strength))) >= minimum
        }
        var hundredths = Int((ceiling * 100).rounded(.down))
        while hundredths > 0, !holds(Double(hundredths) / 100) {
            hundredths -= 1
        }
        return Double(hundredths) / 100
    }

    /// Whether what is drawn on `accent` is black: where white falls under
    /// `minimum` on it and black does better.
    static func prefersBlack(on accent: RGB, minimum: Double) -> Bool {
        let white = ratio(.white, accent)
        return white < minimum && ratio(.black, accent) > white
    }
}

private struct AskDeemphasizedText: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private static let onLight = Color(
        red: AskContrast.deemphasizedLight.color.red,
        green: AskContrast.deemphasizedLight.color.green,
        blue: AskContrast.deemphasizedLight.color.blue
    ).opacity(AskContrast.deemphasizedLight.opacity)

    func body(content: Content) -> some View {
        content.foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        if contrast == .increased { return AnyShapeStyle(.primary) }
        #if os(visionOS)
        return AnyShapeStyle(.secondary)
        #else
        return scheme == .light ? AnyShapeStyle(Self.onLight) : AnyShapeStyle(.secondary)
        #endif
    }
}

#endif
