#if os(iOS) || os(macOS) || os(visionOS)

import Testing

@testable import AskUI

/// The words on a fill of the host's accent: the nothing-to-ask button's on
/// the first screen and the confirmation card's Confirm
/// (`AskOnAccentLabel`). White, as the system's prominent buttons draw them,
/// where white holds text's 4.5:1 on the accent, and black where it doesn't
/// and black does better. WCAG 2's arithmetic on the accent itself, which a
/// prominent button fills flat.
@Suite(.timeLimit(.minutes(1))) struct AskOnAccentLabelTests {
    private let systemBlue = AskContrast.RGB(red: 0, green: 136 / 255, blue: 1)
    private let darkSystemBlue = AskContrast.RGB(red: 0, green: 145 / 255, blue: 1)
    private let classicBlue = AskContrast.RGB(red: 0, green: 122 / 255, blue: 1)
    private let systemRed = AskContrast.RGB(red: 1, green: 56 / 255, blue: 60 / 255)
    private let navy = AskContrast.RGB(red: 26 / 255, green: 35 / 255, blue: 126 / 255)
    private let yellow = AskContrast.RGB(red: 1, green: 214 / 255, blue: 10 / 255)
    private let mint = AskContrast.RGB(red: 99 / 255, green: 230 / 255, blue: 226 / 255)

    private func gray(_ step: Int) -> AskContrast.RGB {
        let value = Double(step) / 255
        return AskContrast.RGB(red: value, green: value, blue: value)
    }

    #if !os(visionOS)
    /// **Words on the accent are held to text's 4.5:1, not a glyph's 3:1.**
    /// White is 3.52:1 on the system blue, 3.23:1 on its dark #0091FF, 4.02:1
    /// on #007AFF and 3.57:1 on the system red, all under the bar, where black
    /// is 5.97:1, 6.49:1, 5.23:1 and 5.88:1: each label is black. Navy keeps
    /// white, and the light accents take black as a glyph on them does.
    @Test func wordsOnTheAccentAreBlackWhereWhiteFallsUnderFourPointFiveToOne() {
        #expect(abs(AskContrast.ratio(.white, systemBlue) - 3.52) < 0.01)
        #expect(abs(AskContrast.ratio(.black, systemBlue) - 5.97) < 0.01)
        #expect(abs(AskContrast.ratio(.white, darkSystemBlue) - 3.23) < 0.01)
        #expect(abs(AskContrast.ratio(.black, darkSystemBlue) - 6.49) < 0.01)
        #expect(abs(AskContrast.ratio(.white, classicBlue) - 4.02) < 0.01)
        #expect(abs(AskContrast.ratio(.black, classicBlue) - 5.23) < 0.01)
        #expect(abs(AskContrast.ratio(.white, systemRed) - 3.57) < 0.01)
        #expect(abs(AskContrast.ratio(.black, systemRed) - 5.88) < 0.01)

        for accent in [systemBlue, darkSystemBlue, classicBlue, systemRed, yellow, mint, .white] {
            #expect(AskOnAccentLabel.isBlack(on: accent), "\(accent)")
        }
        for accent in [navy, .black] {
            #expect(!AskOnAccentLabel.isBlack(on: accent), "\(accent)")
        }
        // A glyph on the system blue keeps white: only words moved.
        #expect(!AskContrast.prefersBlack(on: systemBlue, minimum: AskGlassForeground.glyph))
    }

    /// **The label turns black at white's 4.5:1**, between the grays #767676,
    /// where white is 4.54:1, and #777777, where it is 4.48:1. On every gray
    /// the label is white exactly where white holds the bar, and holds the bar
    /// itself: white and black cross at about 4.58:1, so one of them always
    /// clears 4.5:1.
    @Test func theLabelTurnsBlackAtWhiteFourPointFiveToOneAndAlwaysHoldsIt() {
        let bar = AskGlassForeground.text
        #expect(abs(AskContrast.ratio(.white, gray(118)) - 4.54) < 0.01)
        #expect(abs(AskContrast.ratio(.white, gray(119)) - 4.48) < 0.01)
        #expect(!AskOnAccentLabel.isBlack(on: gray(118)))
        #expect(AskOnAccentLabel.isBlack(on: gray(119)))

        for step in 0...255 {
            let accent = gray(step)
            let label: AskContrast.RGB = AskOnAccentLabel.isBlack(on: accent) ? .black : .white
            #expect(AskContrast.ratio(label, accent) >= bar, "gray \(step)")
            #expect((label == .white) == (AskContrast.ratio(.white, accent) >= bar), "gray \(step)")
        }
    }

    /// The same on every hue: across a coarse sweep of sRGB, whichever of
    /// white and black the label takes holds 4.5:1 on the accent.
    @Test func theLabelHoldsFourPointFiveToOneOnEveryAccent() {
        let steps = stride(from: 0, through: 255, by: 15).map { Double($0) / 255 }
        for red in steps {
            for green in steps {
                for blue in steps {
                    let accent = AskContrast.RGB(red: red, green: green, blue: blue)
                    let label: AskContrast.RGB = AskOnAccentLabel.isBlack(on: accent) ? .black : .white
                    #expect(AskContrast.ratio(label, accent) >= AskGlassForeground.text, "\(accent)")
                }
            }
        }
    }
    #endif

    /// **visionOS keeps the style's own label.** Its prominent button is a
    /// bordered platter with no fill of the accent, so nothing is judged on
    /// the accent there, a light one included. Everywhere else a light accent
    /// fills the button, and the words on it are black.
    @Test func theLabelIsJudgedOnTheAccentOnlyWhereTheAccentFillsTheButton() {
        for accent in [yellow, mint, systemBlue] {
            #if os(visionOS)
            #expect(!AskOnAccentLabel.isBlack(on: accent), "\(accent)")
            #else
            #expect(AskOnAccentLabel.isBlack(on: accent), "\(accent)")
            #endif
        }
    }
}

#endif
