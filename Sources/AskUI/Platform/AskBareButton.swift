#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

// MARK: - What a bare button says it is
//
// A bare button is one that draws its label and nothing behind it: a glyph on
// glass, a line of caption text, a chip whose capsule is laid outside the
// button. Three things a system control does on its own have to be said for
// one of these, each where its platform asks for it:
//
// - **It lights under the reader's eyes and the iPad's pointer**
//   (`askHoverEffect(in:)`), in the shape the reader sees.
// - **On the Mac, a glyph alone shows a help tag** (`askHelp(_:)`), in the
//   words VoiceOver reads for it.
// - **Under Button Shapes, it shows a shape** (`AskBareButtonShape`): a ring
//   round a glyph, and an underline under words.

extension View {
    /// Lights the view as the reader looks at it on visionOS, or points at it
    /// on an iPad, in `shape`: the circle, capsule or outline the button draws,
    /// rather than the rectangle round its frame. Nothing on the Mac, where
    /// SwiftUI's hover effects don't exist.
    ///
    /// **Said outright, not left to the style.** Whether `.plain` lights its
    /// label on visionOS and under the pointer, and in what shape, isn't
    /// written down, and a button style of AskKit's own (`AskChatsPane`'s rows)
    /// lights nothing. So every bare button names its effect and the shape it
    /// lights in. `.contentShape(.hoverEffect, …)` shapes only the light: what
    /// starts it is the button's own hit region (`.interaction`).
    ///
    /// **Not while the button is disabled**, read from the environment, so a
    /// `.disabled` outside this modifier turns the light off with the button.
    ///
    /// Not yet looked at on the visionOS simulator or under an iPad's pointer.
    func askHoverEffect(in shape: some Shape) -> some View {
        modifier(AskHoverEffect(shape: shape))
    }

    /// The help tag a glyph-only button shows on the Mac as the pointer rests
    /// on it, in the words VoiceOver reads for it: its accessibility label, so
    /// a sighted reader with a pointer can find out what a glyph does without
    /// pressing it. Nothing elsewhere.
    ///
    /// **The Mac's alone, because `.help` is also the accessibility hint**, as
    /// SwiftUI documents it. On iOS and visionOS VoiceOver reads a hint after
    /// the label, so a help in the label's own words would read every button
    /// twice: "Send, button, Send". On the Mac the hint is the element's help,
    /// as an AppKit control's tooltip is. Only for a button whose label is a
    /// glyph: a line of words says what it does already, and the evidence
    /// line's hint, which `.help` would replace, says what its words don't.
    func askHelp(_ words: Text) -> some View {
        #if os(macOS)
        help(words)
        #else
        self
        #endif
    }
}

/// The light `askHoverEffect(in:)` puts on a bare button.
private struct AskHoverEffect<HoverShape: Shape>: ViewModifier {
    let shape: HoverShape

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight, isEnabled: isEnabled)
        #endif
    }
}

/// The shape a bare button shows while the reader has Button Shapes on
/// (`accessibilityShowBorders`, the setting's name since the 26.1 SDKs; the
/// older `accessibilityShowButtonShapes` is deprecated in its favor).
///
/// **A ring round a glyph, and an underline under words**, as the setting asks
/// of a button that shows no shape of its own. Buttons that already show one,
/// the send circle's fill, the chips' capsules, the jump pill's glass, the
/// photo chip's disc and the tiles' fill, wear nothing more.
///
/// **A ring rather than a fill**, so the ground under the glyph is the one its
/// color was chosen on: the glyph holds 3:1 on the composer's tint, or on the
/// thread (`AskGlassForeground`), and a fill laid under it would change what
/// it is read against. The ring is drawn in the glyph's own style, so on that
/// ground it holds the contrast the glyph does.
///
/// **Shown and hidden by its opacity, never by a conditional modifier.** The
/// setting can change while VoiceOver's focus is on the button, and a modifier
/// added or taken away gives the button a new identity, which takes the focus
/// with it.
nonisolated enum AskBareButtonShape {
    /// The ring's width.
    static let ringWidth: CGFloat = 1

    /// How far a ring sits outside a glyph that has no circle of its own to
    /// be drawn in, such as the thumbs under an answer: close enough that the
    /// two thumbs' rings stay apart inside the Mac's 28 pt targets.
    static let ringInset: CGFloat = 6

    /// How opaque the ring is: drawn while Button Shapes is on, and not
    /// otherwise.
    static func ringOpacity(showsBorders: Bool) -> Double {
        showsBorders ? 1 : 0
    }

    /// Whether words are underlined: while Button Shapes is on.
    static func underlines(showsBorders: Bool) -> Bool {
        showsBorders
    }
}

extension View {
    /// The ring a glyph-only button wears under Button Shapes, in `shape` and
    /// the frame this view has, in the foreground style the glyph is drawn in
    /// (`AskBareButtonShape`). Lays out nothing: the ring is drawn behind the
    /// glyph, in its frame.
    func askButtonShapeRing(_ shape: some InsettableShape, showsBorders: Bool) -> some View {
        background {
            shape
                .strokeBorder(lineWidth: AskBareButtonShape.ringWidth)
                .opacity(AskBareButtonShape.ringOpacity(showsBorders: showsBorders))
                .accessibilityHidden(true)
        }
    }
}

#endif
