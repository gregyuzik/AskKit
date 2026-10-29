#if os(macOS)

import AppKit
import AskCore
import SwiftUI
import Testing

@testable import AskUI

/// The first screens around a fold across them, and either side of one from
/// top to bottom, read off a render, one point to a pixel.
///
/// A column 400 wide with what the bars leave 700 high: 300 above the fold,
/// a bend of 40, and 360 below. Lying flat the bend is none, and the same two
/// halves meet at 300.
///
/// **What the render can't show, and how each is pinned instead.** The
/// renderer draws text and the mark, a red square here, and leaves glass
/// blank: the starters' chips and the nothing-to-ask screen's button take
/// their room and draw nothing. So:
/// - a text is found by the rows that change when its words do;
/// - the chips by the rows that change with one starter in place of three,
///   which move "Try asking" and the disclosure around them;
/// - the button by the room it takes: in a lower half too short for it, the
///   column grows by exactly what the button is over.
///
/// Decided, not yet seen: nothing here has been looked at on an iPhone Duo.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenFoldTests {

    private let column = ProposedViewSize(width: 400, height: nil)
    private let bent = AskFoldSplit(above: 300, gap: 40, below: 360, isBent: true)
    private let flat = AskFoldSplit(above: 300, gap: 0, below: 360, isBent: false)

    private let three = [
        AskStarter(id: "books", text: "What books do I own?"),
        AskStarter(id: "oldest", text: "What's the oldest thing I have?"),
        AskStarter(id: "count", text: "How many things do I own in total?")
    ]

    // MARK: The screens

    /// What a test changes about a screen to find where it drew something.
    private struct Screen {
        var phase: AskStage.Phase
        var starters: [AskStarter] = []
        var answersWithoutModel = false
        var sentence: String? = "Nothing to ask about yet."
        var action: String?
        var disclosure = "Questions are answered on this device."
        var part = AskFirstScreenPart.whole
        var keyboardIsUp = false
    }

    private func cantServe(
        _ why: AskUnavailability = .deviceNotEligible, starters: [AskStarter] = [],
        answersWithoutModel: Bool = false
    ) -> Screen {
        Screen(phase: .cannotServe(why), starters: starters, answersWithoutModel: answersWithoutModel)
    }

    private func nothing(action: String? = nil) -> Screen {
        Screen(phase: .nothingToAskAbout, action: action)
    }

    /// The reason reworded, at the same length: one line either way. Not the
    /// Apple Intelligence off line, which says System Settings on a Mac and
    /// wraps to a second line there.
    private func reworded(_ screen: inout Screen) {
        screen.phase = .cannotServe(.languageNotSupported)
    }

    private func view(_ screen: Screen, split: AskFoldSplit?) -> some View {
        AskFirstScreen(
            phase: screen.phase,
            brand: AskBrand(
                title: "Ask the Tests", appDirectory: "AskKitTests",
                logSubsystem: "AskKit.uitests", help: "Ask about your things",
                firstScreenHeadline: "Ask about your things",
                firstScreenSentence: "Books, records, tools and clothes.",
                nothingToAskCopy: screen.sentence,
                disclosureSentence: screen.disclosure,
                scopeCaveat: "Ask reads only what you own, and it can be wrong."
            ),
            starters: screen.starters,
            answersWithoutModel: screen.answersWithoutModel,
            onStarter: { _ in },
            nothingToAskAction: screen.action.map { AskNothingToAskAction($0) {} },
            mark: { _ in Color(red: 1, green: 0, blue: 0) }
        )
        .environment(\.askFoldSplit, split)
        .environment(\.askFirstScreenPart, screen.part)
        .environment(\.askFirstScreenKeyboardIsUp, screen.keyboardIsUp)
        .environment(\.colorScheme, .light)
        .background(Color.white)
    }

    // MARK: The render

    /// A screen drawn on white, and what can be read off it by pixel row,
    /// counted from the top.
    private struct Render {
        let image: NSBitmapImageRep

        var height: Int { image.pixelsHigh }

        /// One row's pixels, and how many bytes of them there are, without
        /// the padding a row may end in.
        ///
        /// `unsafe` here and where a row is read: a pointer into `image`'s own
        /// bitmap, read for at most `rowLength` bytes while `image` holds it.
        private func pixels(row: Int) -> UnsafePointer<UInt8>? {
            unsafe image.bitmapData.map { unsafe UnsafePointer($0 + row * image.bytesPerRow) }
        }

        private var rowLength: Int { image.pixelsWide * image.bitsPerPixel / 8 }

        /// The rows with anything drawn on them. White is every byte full,
        /// whatever order the renderer keeps its channels in, and a text's
        /// faintest edge isn't counted.
        var inkRows: [Int] {
            let length = rowLength
            let white = [UInt8](repeating: 0xFF, count: length)
            return (0..<height).filter { row in
                guard let mine = unsafe pixels(row: row), unsafe memcmp(mine, white, length) != 0 else { return false }
                for offset in 0..<length where unsafe mine[offset] < 0xF0 { return true }
                return false
            }
        }

        /// The rows the mark is drawn on: red down the column's middle, whole
        /// or dimmed, where a text is grey.
        var markRows: [Int] {
            (0..<height).filter { row in
                guard let colour = image.colorAt(x: image.pixelsWide / 2, y: row)?.usingColorSpace(.sRGB) else {
                    return false
                }
                return colour.redComponent - colour.greenComponent > 0.25
            }
        }

        /// The rows that differ from `other`'s: where what the two screens
        /// don't share is drawn, and whatever it moved.
        ///
        /// By more than the renderer's own grain. The same screen drawn in
        /// two test runs came back one level of 255 apart along a few
        /// letters' edges, where a letter drawn or moved changes a pixel by
        /// a hundred or more.
        func rows(differingFrom other: Render) -> [Int] {
            guard height == other.height, image.pixelsWide == other.image.pixelsWide else {
                return Array(0..<max(height, other.height))
            }
            let length = rowLength
            return (0..<height).filter { row in
                guard let mine = unsafe pixels(row: row), let theirs = unsafe other.pixels(row: row) else { return true }
                guard unsafe memcmp(mine, theirs, length) != 0 else { return false }
                for offset in 0..<length where unsafe abs(Int(mine[offset]) - Int(theirs[offset])) > Self.grain {
                    return true
                }
                return false
            }
        }

        /// How far a pixel's channel may differ between two renders of one
        /// screen and still be the same pixel.
        private static let grain = 8

        /// Whether the two renders are the same picture.
        func matches(_ other: Render) -> Bool {
            height == other.height && rows(differingFrom: other).isEmpty
        }
    }

    /// Draws `screen` around `split`.
    ///
    /// It gives the main actor up first, since a render holds it from start
    /// to end. Before it did, and while this suite read its pixels a byte at
    /// a time through a closure, the suite held the main actor for 18 s on a
    /// loaded Mac, and the store's tests, which wait on it against a 15 s
    /// deadline, failed by the dozen with nothing wrong.
    private func render(_ screen: Screen, split: AskFoldSplit?) async throws -> Render {
        await Task.yield()
        let renderer = ImageRenderer(content: view(screen, split: split))
        renderer.scale = 1
        renderer.proposedSize = column
        let image = try #require(renderer.cgImage)
        #expect(image.width == 400)
        return Render(image: NSBitmapImageRep(cgImage: image))
    }

    /// The rows where `drawn`, a render of `screen` around `split`, differs
    /// from the same screen after `change`: what the change rewords, and
    /// whatever that moves.
    private func rows(
        of screen: Screen, drawn: Render, split: AskFoldSplit?, changedBy change: (inout Screen) -> Void
    ) async throws -> [Int] {
        var other = screen
        change(&other)
        return drawn.rows(differingFrom: try await render(other, split: split))
    }

    // MARK: Two halves across a fold

    /// (a) Can't serve with starters that work: the mark and the reason above
    /// the fold, "Try asking", the starters and the disclosure below, and
    /// nothing in the bend. Flat, the same two halves meet at the hinge.
    @Test func aScreenThatCantServeWithStartersPartsAtTheFold() async throws {
        let screen = cantServe(starters: three, answersWithoutModel: true)
        for split in [bent, flat] {
            let upperEnd = Int(split.above)
            let lowerStart = Int(split.above + split.gap)
            let drawn = try await render(screen, split: split)
            let ink = drawn.inkRows
            #expect(drawn.height == Int(split.whole))
            #expect(ink.allSatisfy { $0 < upperEnd || $0 >= lowerStart })

            // What only informs: the mark, and the reason under it.
            let mark = drawn.markRows
            #expect(mark.count == 56)
            #expect(mark.allSatisfy { $0 < upperEnd })
            let reason = try await rows(of: screen, drawn: drawn, split: split, changedBy: reworded)
            #expect(reason.allSatisfy { $0 < upperEnd })
            let reasonStart = try #require(reason.min())
            let markEnd = try #require(mark.max())
            #expect(reasonStart > markEnd)

            // Each half centered in its side, as the ready screen's are: the
            // mark as far under the top of what the bars leave as the
            // reason's last line is over the fold, give or take the room
            // under a line's letters.
            let lead = try #require(ink.first)
            let last = try #require(ink.last { $0 < upperEnd })
            #expect(lead > 40)
            #expect(abs(lead - (upperEnd - 1 - last)) <= 8)

            // What to ask: the disclosure, and the starters' room, which
            // moves "Try asking" and the disclosure and nothing above.
            let disclosure = try await rows(of: screen, drawn: drawn, split: split) {
                $0.disclosure = "Nothing leaves this device."
            }
            #expect(!disclosure.isEmpty)
            #expect(disclosure.allSatisfy { $0 >= lowerStart })
            let starters = try await rows(of: screen, drawn: drawn, split: split) { [three] in
                $0.starters = [three[0]]
            }
            #expect(!starters.isEmpty)
            #expect(starters.allSatisfy { $0 >= lowerStart })
            #expect(ink.contains { $0 >= lowerStart && !disclosure.contains($0) })
        }
    }

    // MARK: No halves, in a tabletop

    /// (b) Nothing to ask about, bent: the mark and the sentence above the
    /// bend, and the button in the lower half.
    ///
    /// The button draws nothing here, so two things stand in for it. Above
    /// the bend the screen is the same picture with the button as without,
    /// where one column puts the button under the sentence and lifts both.
    /// And in a lower half 8 pt high, too short for the button, the column
    /// is taller by what the button is over, where a button anywhere else
    /// would leave it the split's own height.
    ///
    /// With no button the lower half is empty, and the column still runs to
    /// the foot of what the bars leave, so nothing centers it across the bend.
    @Test func bentTheNothingToAskScreenPutsItsSentenceAboveAndItsButtonBelow() async throws {
        let plain = nothing()
        let withButton = nothing(action: "Add Your First Item")
        let drawn = try await render(withButton, split: bent)
        #expect(drawn.height == 700)
        #expect(!drawn.inkRows.isEmpty)
        #expect(drawn.inkRows.allSatisfy { $0 < 300 })
        #expect(drawn.markRows.count == 56)
        let sentence = try await rows(of: withButton, drawn: drawn, split: bent) {
            $0.sentence = "Add something to ask about."
        }
        #expect(!sentence.isEmpty)
        #expect(sentence.allSatisfy { $0 < 300 })

        // The button takes nothing of the upper half, and with none the
        // column is as tall and its lower half empty.
        let plainBent = try await render(plain, split: bent)
        #expect(plainBent.height == 700)
        #expect(drawn.matches(plainBent))
        // One column puts it under the sentence: 16 pt and its own height.
        let oneColumn = try await render(withButton, split: nil)
        let plainColumn = try await render(plain, split: nil)
        let button = oneColumn.height - plainColumn.height - 16
        #expect(button > 8)

        // Its room is the lower half's.
        let short = AskFoldSplit(above: 300, gap: 40, below: 8, isBent: true)
        let overgrown = try await render(withButton, split: short)
        let plainShort = try await render(plain, split: short)
        #expect(overgrown.height == 300 + 40 + button)
        #expect(plainShort.height == 300 + 40 + 8)
        #expect(overgrown.inkRows == drawn.inkRows)
    }

    /// (c) Can't serve with no starters, bent: the mark, the reason and the
    /// disclosure all above the bend, centered there, and nothing below. For
    /// a host that needs a model, and for one that answers without and has no
    /// starter left to offer.
    @Test func bentAScreenThatCantServeWithoutStartersKeepsToTheUpperHalf() async throws {
        for screen in [cantServe(starters: three), cantServe(answersWithoutModel: true)] {
            let drawn = try await render(screen, split: bent)
            let ink = drawn.inkRows
            #expect(drawn.height == 700)
            #expect(ink.allSatisfy { $0 < 300 })
            #expect(drawn.markRows.count == 56)
            let reason = try await rows(of: screen, drawn: drawn, split: bent, changedBy: reworded)
            let disclosure = try await rows(of: screen, drawn: drawn, split: bent) {
                $0.disclosure = "Nothing leaves this device."
            }
            #expect(!reason.isEmpty)
            #expect(!disclosure.isEmpty)
            #expect((reason + disclosure).allSatisfy { $0 < 300 })

            // Centered in the upper half, not at its top.
            let lead = try #require(ink.first)
            let last = try #require(ink.last)
            #expect(lead > 40)
            #expect(abs(lead - (299 - last)) <= 8)
        }
    }

    // MARK: No copy

    /// A host that draws the nothing-to-ask phase itself, from a brand with
    /// no copy for it, gets the mark and nothing under it: no blank line
    /// holding a sentence's room. (`AskStage` shows the ready screen in this
    /// phase's place, so a store never draws it.)
    @Test func theNothingToAskScreenWithNoCopyDrawsTheMarkAlone() async throws {
        var bare = nothing()
        bare.sentence = nil
        let drawn = try await render(bare, split: nil)
        #expect(drawn.markRows.count == 56)
        #expect(drawn.inkRows == drawn.markRows)

        // The control: with its sentence, the column draws below the mark.
        let worded = try await render(nothing(), split: nil)
        let markEnd = try #require(worded.markRows.max())
        #expect(worded.inkRows.contains { $0 > markEnd })
        #expect(drawn.height < worded.height)
    }

    // MARK: Nothing else moves

    /// (d) Lying flat, the screens with no halves are the one column they are
    /// with no fold at all: the same picture. A flat display has nothing to
    /// keep clear of. Nothing to ask about, with a button and without, and
    /// can't serve with no starters to keep, for a host that needs a model
    /// and for one that answers without.
    ///
    /// Nor does the keyboard's flag move anything of its own: these columns
    /// animate on it and lay nothing out by it, so with it up and no fold
    /// each is the picture it is with it down. `AskScreen` ends an
    /// arrangement while its keyboard is up by setting no split in the
    /// environment.
    @Test func lyingFlatOrTypingTheScreensWithNoHalvesAreTheColumnTheyAreWithNoFold() async throws {
        let screens = [
            nothing(),
            nothing(action: "Add Your First Item"),
            cantServe(starters: three),
            cantServe(answersWithoutModel: true)
        ]
        for screen in screens {
            let whole = try await render(screen, split: nil)
            #expect(whole.height < 300)
            let lyingFlat = try await render(screen, split: flat)
            #expect(lyingFlat.matches(whole))
            var typing = screen
            typing.keyboardIsUp = true
            let typed = try await render(typing, split: nil)
            #expect(typed.matches(whole))
        }
    }

    /// The keyboard's flag moves nothing of the screen that can't serve with
    /// its starters either, in one column or parted at a fold.
    @Test func theKeyboardsFlagMovesNothingOfAScreenWithTwoHalves() async throws {
        let screen = cantServe(starters: three, answersWithoutModel: true)
        var typing = screen
        typing.keyboardIsUp = true
        for split in [nil, bent] {
            let down = try await render(screen, split: split)
            let up = try await render(typing, split: split)
            #expect(up.matches(down))
        }
    }

    // MARK: Either side of a fold from top to bottom

    /// Beside the fold the screen that can't serve with starters is two
    /// views, as the ready one is: the mark and the reason for the leading
    /// pane, and the starters and the disclosure for the conversation's. A
    /// fold across says nothing to either.
    @Test func aScreenThatCantServeWithStartersDrawsOneHalfForEachPane() async throws {
        let whole = cantServe(starters: three, answersWithoutModel: true)
        var about = whole
        about.part = .about
        var ask = whole
        ask.part = .ask
        /// What to ask, changed: another disclosure and one starter of three.
        let asked: (inout Screen) -> Void = { [three] in
            $0.disclosure = "Nothing leaves this device."
            $0.starters = [three[0]]
        }

        let leading = try await render(about, split: nil)
        #expect(leading.markRows.count == 56)
        let leadingReason = try await rows(of: about, drawn: leading, split: nil, changedBy: reworded)
        let leadingAsk = try await rows(of: about, drawn: leading, split: nil, changedBy: asked)
        #expect(!leadingReason.isEmpty)
        #expect(leadingAsk.isEmpty)

        let trailing = try await render(ask, split: nil)
        #expect(trailing.markRows.isEmpty)
        let trailingReason = try await rows(of: ask, drawn: trailing, split: nil, changedBy: reworded)
        let trailingAsk = try await rows(of: ask, drawn: trailing, split: nil, changedBy: asked)
        #expect(trailingReason.isEmpty)
        #expect(!trailingAsk.isEmpty)

        // The two halves and the 16 pt between them are the one column.
        let column = try await render(whole, split: nil)
        #expect(leading.height + 16 + trailing.height == column.height)
        let leadingAcross = try await render(about, split: bent)
        let trailingAcross = try await render(ask, split: bent)
        #expect(leadingAcross.matches(leading))
        #expect(trailingAcross.matches(trailing))
    }
}

#endif
