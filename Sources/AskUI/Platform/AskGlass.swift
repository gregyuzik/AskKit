#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

// MARK: - Why AskUI doesn't call SwiftUI's glass API directly
//
// **Liquid Glass doesn't exist on visionOS, none of it.** Not the modifier,
// not the container, not the button styles, and not even the `Glass` type, so
// a shared file can't so much as name it (measured against the visionOS 27
// SDK):
//
//     error: 'glassEffect(_:in:)' is unavailable in visionOS
//     error: 'GlassEffectContainer' is unavailable in visionOS
//     error: 'glassEffectID(_:in:)' is unavailable in visionOS
//     error: 'glass' / 'glassProminent' is unavailable in visionOS
//     error: 'Glass' is unavailable in visionOS
//
// visionOS shares the design language and has its own spelling for it,
// `.glassBackgroundEffect()`, which puts the content on real glass in space
// rather than compositing a material into a 2-D surface. The two aren't the
// same idea, so this is a vocabulary AskUI speaks and each platform answers in
// its own words, not a rename.
//
// **Never glass inside glass.** Glass can't sample glass: a tinted capsule
// inside a glass bar reads as a smudge, and on visionOS it becomes one pane of
// glass floating a millimeter in front of another. Anything sitting on glass
// gets a fill, a tint or vibrancy instead. The composer's send button is a
// fill for exactly this reason.
//
// **And never a `Material` imitating glass.** On the 27 OSes readers can set
// glass transparency anywhere from ultra-clear to fully opaque, and real glass
// tracks that slider while a hand-rolled blur doesn't, so imitation glass looks
// wrong at both ends of a control the reader chose.

/// Stand-in for SwiftUI's `Glass`, which can't be named on visionOS.
///
/// Deliberately only the configurations Ask uses. A wider stand-in would be a
/// second API to keep in step for nobody's benefit.
nonisolated enum AskGlass: Sendable {
    /// Plain glass. Static surfaces.
    case regular
    /// Glass that responds to touch. Anything the reader can hit.
    case interactive
    /// Glass carrying a semantic hue at the system's tint strength.
    case tint(Color)
    /// Both: a tinted surface that is also pressable.
    case tintInteractive(Color)

    #if !os(visionOS)
    /// The SwiftUI value this stands for. visionOS never asks: it can't even
    /// name the return type.
    var resolved: Glass {
        switch self {
        case .regular: .regular
        case .interactive: .regular.interactive()
        case .tint(let color): .regular.tint(color)
        case .tintInteractive(let color): .regular.tint(color).interactive()
        }
    }
    #endif

    /// The semantic hue this configuration carries, if any.
    ///
    /// visionOS's `glassBackgroundEffect(in:)` takes no `Glass`, so a tint has
    /// nowhere to go and would be silently dropped, which matters here because
    /// the accent's tint is what marks the composer, and on visionOS the
    /// question bubble too, as the reader's. `askGlass` paints it there as a
    /// fill of its own instead, under the content and over the glass behind
    /// both: the window's, or out of a window the glass
    /// `glassBackgroundEffect(in:displayMode:)` puts there.
    var tintColor: Color? {
        switch self {
        case .regular, .interactive: nil
        case .tint(let color), .tintInteractive(let color): color
        }
    }

    /// How strongly a tint reads on visionOS glass.
    ///
    /// Low on purpose: there the tint is a fill of its own rather than being
    /// mixed into a material the way `Glass.tint` is elsewhere, so the same
    /// nominal color arrives far more saturated.
    static let visionTintOpacity: Double = 0.22
}

extension View {
    /// Lays glass into the given shape.
    ///
    /// The shape is an `InsettableShape` because visionOS's
    /// `glassBackgroundEffect(in:)` requires one: it insets the glass so its
    /// edge sits inside the content, which a plain `Shape` gives it no way to
    /// do.
    ///
    /// **On visionOS, glass only where nothing around it is glass already**
    /// (`.implicit`). Every Ask surface sits in a window, and a window is glass:
    /// at the default `.always`, each would be a second pane floating in front
    /// of the window's, the glass on glass this file rules out. So each surface
    /// takes what sits on glass takes instead, a fill: its tint, or a quiet
    /// fill that keeps its shape where it has none, and glass of its own only
    /// out of a window, in a volume. Not yet looked at on the visionOS
    /// simulator.
    @ViewBuilder
    func askGlass(_ glass: AskGlass = .regular, in shape: some InsettableShape) -> some View {
        #if os(visionOS)
        if let tint = glass.tintColor {
            background(tint.opacity(AskGlass.visionTintOpacity), in: shape)
                .glassBackgroundEffect(in: shape, displayMode: .implicit)
        } else {
            background(.fill.tertiary, in: shape)
                .glassBackgroundEffect(in: shape, displayMode: .implicit)
        }
        #else
        glassEffect(glass.resolved, in: shape)
        #endif
    }

    /// A button that reads as glass: `.glass` on iOS and macOS, and
    /// `.bordered` on visionOS, where the style doesn't exist and a bordered
    /// button already reads as glass.
    ///
    /// **Prominent is a fill of the tint everywhere but visionOS.**
    /// `.glassProminent` fills with the environment's tint, so a label drawn
    /// on it is judged on that color (`AskOnAccentLabel`) and the button is
    /// tinted with the color its label is judged on. visionOS's is the same
    /// `.bordered` platter, with no fill of the accent, and its label keeps
    /// the style's own color. Not yet looked at on the visionOS simulator.
    @ViewBuilder
    func askGlassButton(prominent: Bool = false) -> some View {
        #if os(visionOS)
        buttonStyle(.bordered)
        #else
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
        #endif
    }
}

#endif
