#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The spectrum look (`AskSpectrum`): its palette, what it falls back to, and
/// the glyph its send circle draws.
@Suite(.timeLimit(.minutes(1))) struct AskSpectrumTests {

    private static let environment = EnvironmentValues()

    private static func luminance(_ color: Color) -> Double {
        AskContrast.luminance(color.resolve(in: environment))
    }

    /// White's contrast on a stop: the worst a white glyph does where that
    /// stop sits under it.
    private static func white(on color: Color) -> Double {
        1.05 / (luminance(color) + 0.05)
    }

    private static let cyan = Color(.displayP3, red: 0.30, green: 0.86, blue: 1.0)
    private static let blue = Color(.displayP3, red: 0.24, green: 0.48, blue: 1.0)
    private static let violet = Color(.displayP3, red: 0.56, green: 0.36, blue: 1.0)
    private static let magenta = Color(.displayP3, red: 0.90, green: 0.32, blue: 0.86)
    private static let coral = Color(.displayP3, red: 1.0, green: 0.50, blue: 0.44)

    // MARK: - Luminance

    /// **A Display P3 color outside sRGB keeps its own luminance.** Cyan's
    /// encoded sRGB red is −0.29: clamped to 0 it reads 0.600, and from its
    /// linear channels 0.588, its luminance in P3's own terms.
    @Test func aDisplayP3ColorKeepsItsOwnLuminance() {
        #expect(abs(Self.luminance(Self.cyan) - 0.5876) < 0.002)
        #expect(abs(Self.luminance(Self.coral) - 0.3899) < 0.002)
        // In sRGB the linear read is the encoded one's.
        let systemBlue = AskContrast.RGB(red: 0, green: 136 / 255, blue: 1)
        let resolved = Color(red: 0, green: 136 / 255, blue: 1).resolve(in: Self.environment)
        #expect(abs(AskContrast.luminance(resolved) - AskContrast.luminance(systemBlue)) < 0.0005)
    }

    // MARK: - Aurora

    /// The demo icon's five, in order.
    @Test func auroraIsTheIconsFiveColors() {
        #expect(AskSpectrum.aurora.colors == [Self.cyan, Self.blue, Self.violet, Self.magenta, Self.coral])
    }

    /// **The send circle and the caret run from blue to violet**, the two
    /// stops white holds best on, and every point between holds at least what
    /// blue does: luminance never rises between two stops.
    @Test func aurorasSendCircleAndCaretRunFromBlueToViolet() {
        #expect(AskSpectrum.aurora.fill == [Self.blue, Self.violet])
    }

    @Test func whiteHoldsWithMarginOnAurorasFill() {
        for stop in AskSpectrum.aurora.fill {
            #expect(Self.white(on: stop) >= 3.8)
        }
        #expect(!AskContrast.prefersBlack(onStops: AskSpectrum.aurora.fill.map(Self.luminance), minimum: AskGlassForeground.glyph))
    }

    /// Why not all five: white is 1.65:1 on cyan and 2.39:1 on coral, and
    /// 3.05:1 on magenta, short of any margin.
    @Test func whiteFailsOnAurorasEnds() {
        #expect(Self.white(on: Self.cyan) < 1.7)
        #expect(Self.white(on: Self.coral) < 2.4)
        #expect(Self.white(on: Self.magenta) < 3.1)
    }

    // MARK: - Stops

    /// A spectrum the host builds fills its send circle with every stop.
    @Test func aHostsSpectrumFillsItsSendCircleWithEveryStop() {
        let spectrum = AskSpectrum([.red, .blue, .purple])
        #expect(spectrum.colors == [.red, .blue, .purple])
        #expect(spectrum.fill == [.red, .blue, .purple])
    }

    /// **At least two stops, always.** One color is a spectrum of that color
    /// alone, and none is the app's accent color.
    @Test func aSpectrumHasAtLeastTwoStops() {
        #expect(AskSpectrum([.orange]).colors == [.orange, .orange])
        #expect(AskSpectrum([.orange]).fill == [.orange, .orange])
        #expect(AskSpectrum([]).colors == [.accentColor, .accentColor])
    }

    @Test func spectraAreComparedByTheirColors() {
        #expect(AskSpectrum([.red, .blue]) == AskSpectrum([.red, .blue]))
        #expect(AskSpectrum([.red, .blue]) != AskSpectrum([.blue, .red]))
        #expect(Set([AskSpectrum([.red, .blue]), AskSpectrum([.red, .blue]), .aurora]).count == 2)
        // Aurora's send circle is its own, so the five built by hand are
        // another spectrum.
        #expect(AskSpectrum([Self.cyan, Self.blue, Self.violet, Self.magenta, Self.coral]) != .aurora)
    }

    // MARK: - The glyph

    /// White wherever it holds 3:1 on the lightest stop, as on the accent.
    @Test func theGlyphIsWhiteWhereWhiteHoldsOnEveryStop() {
        let glyph = AskGlassForeground.glyph
        #expect(!AskContrast.prefersBlack(onStops: [Self.blue, Self.violet].map(Self.luminance), minimum: glyph))
        #expect(!AskContrast.prefersBlack(onStops: [0, 0.05], minimum: glyph))
    }

    /// **One light stop turns it black**: the glyph can sit on any of them.
    /// Aurora's five built by hand put white at 1.65:1 on cyan, and black
    /// holds 5.31:1 even on violet, its darkest.
    @Test func oneLightStopTurnsTheGlyphBlack() {
        let glyph = AskGlassForeground.glyph
        let five = [Self.cyan, Self.blue, Self.violet, Self.magenta, Self.coral].map(Self.luminance)
        #expect(AskContrast.prefersBlack(onStops: five, minimum: glyph))
        // Yellow and mint, as on the accent.
        let yellow = AskContrast.luminance(AskContrast.RGB(red: 1, green: 204 / 255, blue: 0))
        let mint = AskContrast.luminance(AskContrast.RGB(red: 0, green: 199 / 255, blue: 190 / 255))
        #expect(AskContrast.prefersBlack(onStops: [yellow, mint], minimum: glyph))
    }

    /// And stays white where black does no better on the darkest stop.
    @Test func theGlyphStaysWhiteWhereBlackDoesNoBetter() {
        #expect(!AskContrast.prefersBlack(onStops: [0.888, 0], minimum: AskGlassForeground.glyph))
        #expect(!AskContrast.prefersBlack(onStops: [], minimum: AskGlassForeground.glyph))
    }

    // MARK: - What the send circle and caret wear

    /// **No spectrum is today's screen**: the accent, at any contrast.
    @Test func noSpectrumIsTheAccent() {
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .standard) == .accent(.blue))
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .increased) == .accent(.blue))
    }

    @Test func aSpectrumIsWornWhereTheHostSetsOne() {
        let look = AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .standard)
        #expect(look == .spectrum(.aurora))
    }

    /// Increase Contrast takes the spectrum away, back to the accent.
    @Test func increaseContrastTakesTheSpectrumBackToTheAccent() {
        let look = AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .increased)
        #expect(look == .accent(.blue))
    }

    /// The send circle's glyph: the accent's own with no spectrum, white on
    /// aurora, and black on a light spectrum.
    @Test func theSendGlyphFollowsWhatTheCircleWears() {
        let yellow = Color(red: 1, green: 204 / 255, blue: 0)
        #expect(
            AskSendGlyph(accent: yellow, spectrum: nil).resolve(in: Self.environment)
                == AskOnAccent(accent: yellow).resolve(in: Self.environment)
        )
        #expect(AskSendGlyph(accent: yellow, spectrum: nil).resolve(in: Self.environment) == .black)
        #expect(AskSendGlyph(accent: yellow, spectrum: .aurora).resolve(in: Self.environment) == .white)
        #expect(AskSendGlyph(accent: .blue, spectrum: AskSpectrum([yellow, .mint])).resolve(in: Self.environment) == .black)
    }

    /// The caret: the accent's flat dot with no spectrum, and the spectrum's
    /// fill where there is one.
    @Test func theCaretFollowsWhatTheCircleWears() {
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .standard).caret == .color(.blue))
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .standard).caret == .gradient([Self.blue, Self.violet]))
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .increased).caret == .color(.blue))
    }
}

#endif
