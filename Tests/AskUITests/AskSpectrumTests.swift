#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
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

    // MARK: - The glass rod

    /// Where the composer's circles sit inside its capsule: its 2 pt of
    /// padding, and half of what the hit region adds round the circle.
    private static var circleInset: CGFloat {
        AskComposerMetrics.edge + (AskComposerMetrics.target - AskComposerMetrics.circle) / 2
    }

    /// **On the composer the rod is centred on the glass's outline**, its
    /// inner side clear of the circles and the field's first and last lines
    /// at one line and past it, and the fill reaches past it far enough for
    /// its glow to fade out.
    @Test func onTheComposerTheRodIsCentredOnTheOutline() {
        let facing = AskGlassRod.Facing.outward
        #expect(abs(facing.outset) < 1)
        // The tube's inner side, inside the capsule, at least a point short
        // of the circles: 3.6 pt in against 7 (2.8 against 4 on the Mac).
        #expect(facing.radius - facing.outset <= Self.circleInset - 1)
        let inner = facing.radius - facing.outset
        // **At any height**, as the text grows the circles and as the field
        // grows to four lines. The corners keep the radius the capsule has at
        // one line, centred where the circles are, at the bottom of the row,
        // so the circles keep their inset; a capsule four lines tall, 114 pt
        // with ends 57 pt round, put the send circle's rim 7 pt past its
        // edge, over the rod.
        for scaled in [AskComposerMetrics.widestGlyph, 1.5 * AskComposerMetrics.widestGlyph, 3 * AskComposerMetrics.widestGlyph] {
            let corner = AskComposerMetrics.corner(widestGlyph: scaled)
            let target = AskComposerMetrics.target(widestGlyph: scaled)
            let circle = AskComposerMetrics.circle(widestGlyph: scaled)
            // A capsule at one line, where the row is the target's height;
            // and each circle, centred in a target `edge` in from the bottom
            // and the side, centred on its corner's centre at any height.
            #expect(2 * corner == target + 2 * AskComposerMetrics.edge)
            #expect(corner - circle / 2 >= inner + 1)
        }
        // The first and last lines' first glyph, 18 pt in from the leading
        // edge with no button before the field and the field's inset below
        // the top, clear of the corner's arc and the rod along it.
        let corner = AskComposerMetrics.corner(widestGlyph: AskComposerMetrics.widestGlyph)
        let glyph = CGPoint(x: 18, y: AskComposerMetrics.edge + AskComposerMetrics.fieldInset)
        #expect(corner - hypot(corner - glyph.x, corner - glyph.y) >= inner + 1)
        #expect(facing.reach == facing.outset + facing.radius + AskGlassRodShape.glowReach)
        // A 5 pt falloff at half strength: about 1% where the fill ends.
        #expect(0.5 * exp(-Double(AskGlassRodShape.glowReach) / 5) < 0.02)
        #expect(facing.sign == 1)
    }

    /// **On the face in a host's slot the rod sits inside the face**, clear
    /// of its circles, which keep the composer's default metrics there, with
    /// nothing drawn past the face.
    @Test func onTheFaceTheRodSitsInside() {
        let facing = AskGlassRod.Facing.inward
        #expect(facing.outset + facing.radius <= 0)
        #expect(facing.radius - facing.outset <= 7 - 1)
        #expect(facing.reach == 0)
        #expect(facing.sign == -1)
    }

    /// **The rod is there at rest**, with no turn in flight, still: it marks
    /// where to type.
    @Test func theRodIsDrawnAtRest() {
        let motion = AskGlassRodMotion.of(isThinking: false, isCovered: false, reduceMotion: false)
        #expect(motion.isDrawn)
        #expect(!motion.drifts)
    }

    /// And while a turn is in flight, drifting.
    @Test func theRodIsDrawnInFlight() {
        let motion = AskGlassRodMotion.of(isThinking: true, isCovered: false, reduceMotion: false)
        #expect(motion.isDrawn)
        #expect(motion.drifts)
        #expect(motion.ticks)
    }

    /// **The colors drift only while a turn is in flight**, and never under
    /// Reduce Motion.
    @Test func theRodDriftsOnlyInFlight() {
        for isCovered in [false, true] {
            #expect(AskGlassRodMotion.of(isThinking: true, isCovered: isCovered, reduceMotion: false).drifts)
            #expect(!AskGlassRodMotion.of(isThinking: false, isCovered: isCovered, reduceMotion: false).drifts)
            #expect(!AskGlassRodMotion.of(isThinking: true, isCovered: isCovered, reduceMotion: true).drifts)
            #expect(!AskGlassRodMotion.of(isThinking: false, isCovered: isCovered, reduceMotion: true).drifts)
        }
    }

    /// **Nothing ticks at rest**: the rod renders when it appears and when
    /// the layout changes, and draws no frames on a clock.
    @Test func nothingTicksAtRest() {
        for reduceMotion in [false, true] {
            #expect(!AskGlassRodMotion.of(isThinking: false, isCovered: false, reduceMotion: reduceMotion).ticks)
        }
    }

    /// **Nothing ticks under Reduce Motion**, even in flight, where the rod
    /// stays, holding still.
    @Test func nothingTicksUnderReduceMotion() {
        let motion = AskGlassRodMotion.of(isThinking: true, isCovered: false, reduceMotion: true)
        #expect(motion.isDrawn)
        #expect(!motion.ticks)
    }

    /// **Only the rod on screen is drawn**: out while its capsule is covered,
    /// the composer resting in a host's slot or the face under the raised
    /// composer, so the two never both draw, and a covered one never ticks.
    @Test func theLightIsOutWhileItsCapsuleIsCovered() {
        for isThinking in [false, true] {
            let covered = AskGlassRodMotion.of(isThinking: isThinking, isCovered: true, reduceMotion: false)
            #expect(!covered.isDrawn)
            #expect(!covered.ticks)
            #expect(AskGlassRodMotion.of(isThinking: isThinking, isCovered: false, reduceMotion: false).isDrawn)
        }
    }

    /// The colors' clock runs from the send, and reads 0, the colors at
    /// rest, before any turn.
    @Test func theColorsDriftFromTheSend() {
        let sent = Date(timeIntervalSinceReferenceDate: 1000)
        let clock = AskGlassRodClock.resting.started(at: sent)
        #expect(clock == .drifting(since: sent))
        #expect(clock.runs)
        #expect(clock.time(at: sent + 3) == 3)
        #expect(clock.time(at: sent - 1) == 0)
        #expect(!AskGlassRodClock.resting.runs)
        #expect(AskGlassRodClock.resting.time(at: sent) == 0)
    }

    /// **At the turn's end the clock stops where it got to**, which the
    /// stage's animation fades back to the colors at rest from. **The next
    /// send starts it from 0**, the colors at rest, so the drift fades in
    /// from where they are.
    @Test func theClockStopsAtTheEndAndStartsAgainAtRest() {
        let sent = Date(timeIntervalSinceReferenceDate: 1000)
        let stopped = AskGlassRodClock.drifting(since: sent).stopped(at: sent + 8)
        #expect(stopped == .stopped(since: sent, until: sent + 8))
        #expect(!stopped.runs)
        #expect(stopped.time(at: sent + 20) == 8)
        let next = stopped.started(at: sent + 60)
        #expect(next == .drifting(since: sent + 60))
        #expect(next.time(at: sent + 60) == 0)
        // Stopping a clock that isn't drifting changes nothing.
        #expect(stopped.stopped(at: sent + 90) == stopped)
        #expect(AskGlassRodClock.resting.stopped(at: sent) == .resting)
    }

    /// **A send while the last turn's drift is still fading out carries the
    /// colors on from where they stopped**: started from 0 there, the colors
    /// the fade was carrying back to rest would jump to rest in a frame.
    @Test func aSendDuringTheFadeCarriesTheColorsOn() {
        let sent = Date(timeIntervalSinceReferenceDate: 1000)
        let stopped = AskGlassRodClock.drifting(since: sent).stopped(at: sent + 8)
        let soon = stopped.started(at: sent + 8.1)
        #expect(abs(soon.time(at: sent + 8.1) - 8) < 1e-9)
        #expect(abs(soon.time(at: sent + 9.1) - 9) < 1e-9)
        let late = stopped.started(at: sent + 8 + AskGlassRodClock.carry)
        #expect(late.time(at: sent + 8 + AskGlassRodClock.carry) == 0)
    }

    /// **The store keeps the one clock every rod reads**, run and stopped in
    /// the update `isThinking` changes in, so the composer's rod and the
    /// face's drift in step, and a rod that comes into sight mid-turn picks
    /// the drift up where it is.
    @Test @MainActor func theStoreRunsTheRodsClockWhileATurnIsInFlight() async {
        let store = makeStore(asker: ScriptedAsker(.init(events: [.tier(.onDevice)], hangs: true)))
        #expect(store.rodClock == .resting)
        store.ask("q")
        #expect(store.isThinking)
        guard case .drifting(let since) = store.rodClock else {
            Issue.record("not drifting: \(store.rodClock)")
            return
        }
        store.stop(byReader: true)
        #expect(!store.isThinking)
        guard case .stopped(let from, _) = store.rodClock else {
            Issue.record("not stopped: \(store.rodClock)")
            return
        }
        #expect(from == since)
    }

    /// **The compiled library is in AskUI's bundle, and holds the function the
    /// fill names.** A name that doesn't match draws nothing and throws
    /// nothing.
    @Test func theShaderLibraryHoldsTheGlassRod() throws {
        let url = try #require(AskGlassRodShape.bundle.url(forResource: "default", withExtension: "metallib"))
        let library = try Data(contentsOf: url)
        #expect(library.range(of: Data(AskGlassRodShape.functionName.utf8)) != nil)
    }

    /// **The rod runs out and back through the colors**: the first at the
    /// trailing end, where the send circle is, the last at the leading end,
    /// and only neighbours in the list mixed between. Run round as a cycle,
    /// aurora's coral met its cyan below the send circle and mixed to a grey,
    /// which the rod's light washed out to white. Read from the shader's own
    /// pixels, drawn at rest in dark mode on a 280 × 40 capsule.
    @Test @MainActor func theRodRunsOutAndBackThroughTheColors() throws {
        let rod = try RenderedRod(colors: AskSpectrum.aurora.colors)
        // The middle of the trailing end: cyan.
        let trailing = rod.color(atRim: 0)
        #expect(trailing.blue > trailing.red + 0.3 && trailing.green > trailing.red + 0.3)
        // The middle of the leading end: coral.
        let leading = rod.color(atRim: 0.5)
        #expect(leading.red > leading.blue + 0.15)
        // Below the send circle, where a cycle mixed coral and cyan: a color,
        // not a grey or a white.
        for s in [0.88, 0.9, 0.92, 0.94] {
            let below = rod.color(atRim: s)
            #expect(below.chroma > 0.3, "rim \(s): \(below)")
        }
    }

    /// **Past one line the rod follows the composer's corners**, which keep
    /// the radius they have at one line: lit along the arc of a corner, and
    /// dark where a capsule's end as tall as the composer would have run it.
    @Test @MainActor func theRodFollowsTheCornersOfAComposerPastOneLine() throws {
        let size = CGSize(width: 300, height: 114)
        let corner: CGFloat = 24
        let rod = try RenderedRod(colors: AskSpectrum.aurora.colors, capsule: size, corner: corner)
        let ring = corner + AskGlassRod.Facing.outward.outset
        let centre = CGPoint(x: size.width / 2 - corner, y: size.height / 2 - corner)
        let diagonal = 1 / 2.0.squareRoot()
        // On the top trailing corner's arc, and along the trailing side.
        let onTheArc = rod.color(at: CGPoint(x: centre.x + ring * diagonal, y: centre.y + ring * diagonal))
        #expect(onTheArc.alpha > 0.5, "\(onTheArc)")
        let onTheSide = rod.color(at: CGPoint(x: size.width / 2 + AskGlassRod.Facing.outward.outset, y: 0))
        #expect(onTheSide.alpha > 0.5, "\(onTheSide)")
        // A capsule's end, 57 pt round, would have run it here, 14 pt inside
        // these corners.
        let end = size.height / 2
        let capsuleRing = end + AskGlassRod.Facing.outward.outset
        let whereACapsuleRan = rod.color(at: CGPoint(
            x: size.width / 2 - end + capsuleRing * diagonal, y: capsuleRing * diagonal
        ))
        #expect(whereACapsuleRan.alpha < 0.2, "\(whereACapsuleRan)")
    }

    /// **On the face in a host's slot the rod is lit just inside the face's
    /// edge**, its glow falling inward, and nothing is drawn past the face.
    @Test @MainActor func onTheFaceTheRodIsLitInsideAndNothingPast() throws {
        let facing = AskGlassRod.Facing.inward
        let size = CGSize(width: 300, height: 44)
        let rod = try RenderedRod(colors: AskSpectrum.aurora.colors, capsule: size, facing: facing)
        let top = size.height / 2
        #expect(rod.color(at: CGPoint(x: 0, y: top + facing.outset)).alpha > 0.5)
        #expect(rod.color(at: CGPoint(x: size.width / 2 + facing.outset, y: 0)).alpha > 0.5)
        // Inward of the tube, some glow; past the face, in the fill's corner
        // beyond its round end, nothing.
        #expect(rod.color(at: CGPoint(x: 0, y: top + facing.outset - facing.radius - 2)).alpha > 0.05)
        #expect(rod.color(at: CGPoint(x: size.width / 2 - 2, y: top - 2)).alpha < 0.01)
    }

    /// **The glow stops short of a photo waiting over the composer**: gone
    /// by `headroom` over the capsule's top, and as it was everywhere else,
    /// the rod itself included.
    @Test @MainActor func theGlowStopsShortOfWhatSitsOverTheComposer() throws {
        let colors = AskSpectrum.aurora.colors
        let open = try RenderedRod(colors: colors)
        let held = try RenderedRod(colors: colors, headroom: 6)
        let top: CGFloat = 20
        let over = CGPoint(x: 0, y: top + 8)
        #expect(open.color(at: over).alpha > 0.1, "\(open.color(at: over))")
        #expect(held.color(at: over).alpha < 0.01, "\(held.color(at: over))")
        let under = CGPoint(x: 0, y: -top - 8)
        #expect(abs(held.color(at: under).alpha - open.color(at: under).alpha) < 0.01)
        let rod = CGPoint(x: 0, y: top + AskGlassRod.Facing.outward.outset)
        #expect(abs(held.color(at: rod).alpha - open.color(at: rod).alpha) < 0.01)
    }

    /// **A Display P3 color stays one in the rod's core**: the light past
    /// white is clipped a channel at a time only for what sRGB holds of the
    /// color, and what the color reaches past sRGB goes back on, so P3's
    /// green, below 0 in sRGB's red and blue and past 1 in its green, keeps
    /// all three. Clamped to 0 and 1 as a whole, it came back as sRGB's.
    @Test @MainActor func aDisplayP3ColorKeepsItsGamutInTheCore() throws {
        let green = Color(.displayP3, red: 0, green: 1, blue: 0)
        let rod = try RenderedRod(colors: [green, green], extended: true)
        let core = rod.color(at: CGPoint(x: 0, y: 20 + AskGlassRod.Facing.outward.outset))
        // P3's green in extended sRGB: (-0.51, 1.02, -0.31). Clamped, the
        // red came to about -0.12, from the glow's share under the rod.
        #expect(core.red < -0.3, "\(core)")
        #expect(core.blue < -0.15, "\(core)")
        #expect(core.green > 1.005, "\(core)")
    }

    // MARK: - What the send circle and caret wear

    /// **No spectrum is today's screen**: the accent, at any contrast.
    @Test func noSpectrumIsTheAccent() {
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .standard) == .accent(.blue))
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .increased) == .accent(.blue))
        #expect(AskSpectrumLook.of(accent: .blue, spectrum: nil, contrast: .standard).glow == nil)
    }

    @Test func aSpectrumIsWornWhereTheHostSetsOne() {
        let look = AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .standard)
        #expect(look == .spectrum(.aurora))
        #expect(look.glow == .aurora)
    }

    /// Increase Contrast takes the spectrum away: no glow, and the accent.
    @Test func increaseContrastTakesTheSpectrumBackToTheAccent() {
        let look = AskSpectrumLook.of(accent: .blue, spectrum: .aurora, contrast: .increased)
        #expect(look == .accent(.blue))
        #expect(look.glow == nil)
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

/// The rod's fill drawn at rest by `ImageRenderer`, for reading its pixels:
/// round a capsule 280 × 40 pt unless a test says otherwise, in a fill
/// reaching past it as far as the composer's does, at 2x, in dark mode, left
/// to right.
@MainActor private struct RenderedRod {
    struct RGBA: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        var chroma: Double { max(red, green, blue) - min(red, green, blue) }
        var description: String { String(format: "(%.2f, %.2f, %.2f, alpha %.2f)", red, green, blue, alpha) }
    }

    private static let scale: CGFloat = 2
    private let facing: AskGlassRod.Facing
    private let capsule: CGSize
    private let fill: CGSize
    private let pixels: [Float]
    private let width: Int

    /// - Parameters:
    ///   - extended: Drawn in extended linear sRGB, whose channels go below 0
    ///     and past 1, rather than the default, which clamps them.
    init(
        colors: [Color],
        capsule: CGSize = CGSize(width: 280, height: 40),
        facing: AskGlassRod.Facing = .outward,
        corner: CGFloat? = nil,
        headroom: CGFloat? = nil,
        extended: Bool = false
    ) throws {
        self.facing = facing
        self.capsule = capsule
        fill = CGSize(width: capsule.width + 2 * facing.reach, height: capsule.height + 2 * facing.reach)
        let shape = Rectangle()
            .fill(AskGlassRodShape.function(
                .boundingRect,
                .float(facing.reach),
                .float(facing.outset),
                .float(facing.radius),
                .float(corner ?? AskGlassRodShape.unbounded),
                .float(headroom ?? AskGlassRodShape.unbounded),
                .float(facing.sign),
                .float(1),
                .float(0),
                .float(0),
                .float(1),
                .float(1),
                .float(Float(Self.scale)),
                .colorArray(colors)
            ))
            .frame(width: fill.width, height: fill.height)
        let renderer = ImageRenderer(content: shape)
        renderer.scale = Self.scale
        if extended { renderer.colorMode = .extendedLinear }
        let image = try #require(renderer.cgImage)
        width = image.width
        // Read back as floats in extended sRGB, so a channel below 0 or past
        // 1 survives.
        var floats = [Float](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let context = try #require(CGContext(
            data: &floats, width: image.width, height: image.height, bitsPerComponent: 32,
            bytesPerRow: image.width * 16, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        pixels = floats
        // **The shader ran.** `ImageRenderer` draws a Metal fill only where
        // the process can reach a GPU; where it can't, every pixel is clear,
        // and the colors read back would fail for the wrong reason.
        let probe = color(at: CGPoint(x: 0, y: capsule.height / 2 + facing.outset))
        try #require(
            probe.alpha > 0.5,
            "ImageRenderer drew none of the rod (\(probe)): this process can't run a Metal shader fill, so its pixels can't be read"
        )
    }

    /// The color at `point`, in points from the capsule's centre, y up,
    /// unpremultiplied.
    func color(at point: CGPoint) -> RGBA {
        let x = Int(((fill.width / 2 + point.x) * Self.scale).rounded(.down))
        let y = Int(((fill.height / 2 - point.y) * Self.scale).rounded(.down))
        let i = (y * width + x) * 4
        let alpha = Double(pixels[i + 3])
        let over = max(alpha, 1e-3)
        return RGBA(
            red: Double(pixels[i]) / over, green: Double(pixels[i + 1]) / over,
            blue: Double(pixels[i + 2]) / over, alpha: alpha
        )
    }

    /// The color on the rod's centre line at `s` round the rim of a capsule,
    /// 0 at the middle of the trailing end and rising anticlockwise, as the
    /// shader's rim coordinate runs.
    func color(atRim s: Double) -> RGBA {
        let r = capsule.height / 2
        let a = capsule.width / 2 - r
        let ring = r + facing.outset
        let perimeter = 4 * a + 2 * .pi * r
        var length = s * perimeter
        // Centred, y up, along the rim by length: the right end's upper half,
        // the top, the left end, the bottom, the right end's lower half.
        let point: CGPoint
        let quarter = 0.5 * .pi * r
        if length < quarter {
            let angle = length / r
            point = CGPoint(x: a + ring * cos(angle), y: ring * sin(angle))
        } else if (length - quarter) < 2 * a {
            point = CGPoint(x: a - (length - quarter), y: ring)
        } else if (length - quarter - 2 * a) < 2 * quarter {
            let angle = 0.5 * .pi + (length - quarter - 2 * a) / r
            point = CGPoint(x: -a + ring * cos(angle), y: ring * sin(angle))
        } else if (length - 3 * quarter - 2 * a) < 2 * a {
            point = CGPoint(x: -a + (length - 3 * quarter - 2 * a), y: -ring)
        } else {
            length -= 3 * quarter + 4 * a
            let angle = 1.5 * .pi + length / r
            point = CGPoint(x: a + ring * cos(angle), y: ring * sin(angle))
        }
        return color(at: point)
    }
}

#endif
