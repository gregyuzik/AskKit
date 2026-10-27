import Foundation
import Testing

@testable import AskUI

/// The arrival chunks behind the answer's drawing-in: offsets into the parsed
/// prose, one chunk per snapshot that grew it until it has finished drawing,
/// nothing held back.
@Suite(.timeLimit(.minutes(1))) struct AskArrivalsTests {
    private func parsed(_ text: String) -> AttributedString { AskArrivals.parse(text) }

    @Test func eachSnapshotsNewTextBecomesOneChunk() {
        let first = parsed("Yes")
        let one = AskArrivals.chunks([], from: AttributedString(), to: first, at: 1)
        #expect(one == [AskRevealChunk(length: 3, arrival: 1)])

        // The next snapshot a fraction of a second on, as a stream sends it:
        // the first chunk is still drying, so it keeps its own stamp.
        let second = parsed("Yes — eight green pieces")
        let two = AskArrivals.chunks(one, from: first, to: second, at: 1.2)
        #expect(two == [
            AskRevealChunk(length: 3, arrival: 1),
            AskRevealChunk(length: second.characters.count - 3, arrival: 1.2)
        ])
        // Every character belongs to exactly one chunk, or the fade lands on
        // the wrong words.
        #expect(two.map(\.length).reduce(0, +) == second.characters.count)
    }

    @Test func aSnapshotThatRewritesEarlierTextReStampsTheChangedTail() {
        // "**Olive" is unclosed markdown and parses literally; the closing
        // asterisks in the next snapshot strip both pairs, so the parsed text
        // diverges at its first character.
        let open = parsed("**Olive")
        let chunks = AskArrivals.chunks([], from: AttributedString(), to: open, at: 1)
        let closed = parsed("**Olive** tee")
        #expect(String(closed.characters) == "Olive tee")

        let next = AskArrivals.chunks(chunks, from: open, to: closed, at: 2)
        #expect(next == [AskRevealChunk(length: closed.characters.count, arrival: 2)])
    }

    @Test func aTailOnlyRewriteKeepsTheSharedPrefixesStamps() {
        let before = parsed("Try the navy blazer with")
        let one = AskArrivals.chunks([], from: AttributedString(), to: before, at: 1)
        let after = parsed("Try the navy blazer and the grey trousers")
        let two = AskArrivals.chunks(one, from: before, to: after, at: 1.2)

        let common = "Try the navy blazer ".count
        #expect(two.count == 2)
        #expect(two[0] == AskRevealChunk(length: common, arrival: 1))
        #expect(two[1] == AskRevealChunk(length: after.characters.count - common, arrival: 1.2))
    }

    @Test func aSnapshotThatOnlyRestyledAddsNothing() {
        // The frame a title turns bold: the characters are identical, so
        // nothing re-fades.
        let text = parsed("The Abbey Road sleeve")
        let one = AskArrivals.chunks([], from: AttributedString(), to: text, at: 1)
        let again = AskArrivals.chunks(one, from: text, to: text, at: 1.2)
        #expect(again == one)
        // Nor long after, by when the ink it would have re-faded has merged.
        let later = AskArrivals.chunks(one, from: text, to: text, at: 9)
        #expect(later == [.settled(length: text.characters.count)])
    }

    // MARK: - Merging what has settled

    /// **Merging changes nothing a rule can see.** The same stream fed through
    /// `chunks` and kept unmerged beside it, at a device tier's cadence (seven
    /// characters every 35 ms), at a cloud tier's, and at one snapshot a
    /// second, must say the same about how much text there is, whether any of
    /// it is still fading and how long until it has all settled, at every
    /// frame from a tick behind the snapshot to long after it. And it must
    /// carry one settled stretch in front and only the chunks still inside
    /// `mergeAge`, where the unmerged list carries a chunk a snapshot for the
    /// whole turn.
    @Test(arguments: [(7, 0.035), (96, 0.18), (5, 1.0)] as [(Int, TimeInterval)])
    func mergingKeepsEveryAnswerTheUnmergedListGave(step: Int, cadence: TimeInterval) {
        let answer = String(
            repeating: "You own several olive pieces that would work here, and the navy blazer goes over any of them. ",
            count: 16
        )
        var drawn = AttributedString()
        var merged: [AskRevealChunk] = []
        var unmerged: [AskRevealChunk] = []
        var now = 1000.0
        var end = answer.startIndex
        while end < answer.endIndex {
            end = answer.index(end, offsetBy: step, limitedBy: answer.endIndex) ?? answer.endIndex
            let next = parsed(String(answer[..<end]))
            now += cadence
            merged = AskArrivals.chunks(merged, from: drawn, to: next, at: now)
            unmerged.append(AskRevealChunk(length: next.characters.count - drawn.characters.count, arrival: now))
            drawn = next

            #expect(merged == AskArrivals.merged(unmerged, at: now))
            #expect(merged.map(\.length).reduce(0, +) == drawn.characters.count)
            #expect(merged.dropFirst().allSatisfy { !$0.isSettled }, "one settled stretch, and only in front")
            #expect(merged.allSatisfy { $0.isSettled || now - $0.arrival < AskArrivals.mergeAge })
            for frame in [now - 1.0 / 60, now, now + 0.1, now + 0.5, now + 5] {
                #expect(AskArrivals.isRevealing(merged, at: frame) == AskArrivals.isRevealing(unmerged, at: frame))
                #expect(abs(
                    AskArrivals.timeUntilSettled(merged, at: frame)
                        - AskArrivals.timeUntilSettled(unmerged, at: frame)
                ) < 1e-9)
            }
        }
        #expect(merged.first?.isSettled == true)
        #expect(merged.count <= Int((AskArrivals.mergeAge / cadence).rounded(.up)) + 1)
    }

    /// **A long chunk still drawing holds back a short one behind it**, though
    /// the short one's own sweep ended first. Only leading chunks merge, so the
    /// settled stretch stays one piece in front of everything still stamped.
    @Test func aShortChunkThatSettlesFirstWaitsBehindALongOneStillDrawing() {
        let long = AskRevealChunk(length: 160, arrival: 100)
        let short = AskRevealChunk(length: 3, arrival: 100.1)
        let chunks = [long, short]

        let between = 100.1 + AskArrivals.settle(forLength: 3) + 0.01
        #expect(between < 100 + AskArrivals.settle(forLength: 160), "the short one done, the long one not")
        #expect(AskArrivals.merged(chunks, at: between) == chunks)
        #expect(AskArrivals.isRevealing(chunks, at: between))

        #expect(AskArrivals.merged(chunks, at: 100 + AskArrivals.mergeAge + 0.01) == [.settled(length: 160), short])
        #expect(AskArrivals.merged(chunks, at: 100.1 + AskArrivals.mergeAge + 0.01) == [.settled(length: 163)])
    }

    /// A clock that went backwards between snapshots leaves a finished chunk
    /// behind one still drawing, and it waits for the merge that reaches it
    /// rather than splitting the settled stretch in two.
    @Test func aChunkStampedEarlierThanTheOneAheadOfItWaitsForTheMergeThatReachesIt() {
        let ahead = AskRevealChunk(length: 3, arrival: 5)
        let behind = AskRevealChunk(length: 160, arrival: 1)
        #expect(AskArrivals.merged([ahead, behind], at: 5.5) == [ahead, behind])
        #expect(AskArrivals.merged([ahead, behind], at: 5 + AskArrivals.mergeAge + 0.01) == [.settled(length: 163)])
    }

    /// **A rewrite reaching back into the merged stretch**, an asterisk pair
    /// closing or the tidy pass at the end of a turn, keeps what it didn't
    /// change settled and stamps the changed tail anew, as it keeps the stamps
    /// of an unchanged prefix.
    @Test func aRewriteIntoTheMergedStretchKeepsWhatItDidNotChangeSettled() {
        let first = parsed("Try the navy blazer with")
        let one = AskArrivals.chunks([], from: AttributedString(), to: first, at: 1)
        let grown = parsed("Try the navy blazer with the olive")
        let two = AskArrivals.chunks(one, from: first, to: grown, at: 2)
        #expect(two == [
            .settled(length: first.characters.count),
            AskRevealChunk(length: " the olive".count, arrival: 2)
        ])

        let rewritten = parsed("Try the navy blazer and the grey trousers")
        let three = AskArrivals.chunks(two, from: grown, to: rewritten, at: 2.1)
        let common = "Try the navy blazer ".count
        #expect(three == [
            .settled(length: common),
            AskRevealChunk(length: rewritten.characters.count - common, arrival: 2.1)
        ])

        // One that diverges at the first character leaves nothing to keep.
        let open = parsed("**Olive")
        let closed = parsed("**Olive** tee")
        let reopened = AskArrivals.chunks([.settled(length: open.characters.count)], from: open, to: closed, at: 3)
        #expect(reopened == [AskRevealChunk(length: closed.characters.count, arrival: 3)])
    }

    /// Merged ink is long since drawn to every rule whatever the clock says, a
    /// jump backwards included; what is still drying behind it answers for
    /// itself; and a stretch already merged is left as it is.
    @Test func settledInkNeverRevealsAndWaitsOnNothing() {
        let settled = AskRevealChunk.settled(length: 500)
        #expect(settled.isSettled)
        #expect(!AskArrivals.isRevealing([settled], at: 0))
        #expect(!AskArrivals.isRevealing([settled], at: -1e12))
        #expect(AskArrivals.timeUntilSettled([settled], at: -1e12) == 0)

        let live = AskRevealChunk(length: 3, arrival: 100)
        #expect(AskArrivals.isRevealing([settled, live], at: 100.1))
        #expect(abs(AskArrivals.timeUntilSettled([settled, live], at: 100) - AskArrivals.settle(forLength: 3)) < 1e-9)

        #expect(AskArrivals.merged([settled, live], at: 100.1) == [settled, live])
        #expect(AskArrivals.merged([settled], at: 1e12) == [settled])
    }

    @Test func inlineMarkdownRendersAndStructureDoesNot() {
        #expect(String(parsed("a **bold** name").characters) == "a bold name")
        #expect(String(parsed("- one\n- two").characters) == "- one\n- two")
        // A string the parser rejects survives as it came.
        #expect(String(parsed("50% of [things").characters) == "50% of [things")
    }

    @Test func revealingStopsOnceEveryChunkHasSettled() {
        let chunks = [AskRevealChunk(length: 4, arrival: 100)]
        #expect(AskArrivals.isRevealing(chunks, at: 100.1))
        #expect(!AskArrivals.isRevealing(chunks, at: 100 + AskArrivals.settle + 0.01))
        #expect(!AskArrivals.isRevealing([], at: 0))
        // Each chunk against its own sweep: a cloud-sized one is still drawing
        // where a device-sized one that landed with it has finished.
        let long = [AskRevealChunk(length: 160, arrival: 100)]
        #expect(AskArrivals.isRevealing(long, at: 100 + AskArrivals.settle + 0.01))
        #expect(!AskArrivals.isRevealing(long, at: 100 + AskArrivals.settle(forLength: 160) + 0.01))
    }

    /// **A chunk sweeps for as long as it is long.** A device tier's few
    /// characters keep the measured 80 ms minimum (`AskArrivals.stagger`); a
    /// cloud tier's whole sentence gets the span that makes it read in order
    /// instead of landing as a block, and past a paragraph the span stops
    /// growing.
    @Test(arguments: [
        (0, 0.08), (4, 0.08), (16, 0.08), (24, 0.12),
        (60, 0.3), (100, 0.5), (162, 0.5), (4000, 0.5), (-5, 0.08)
    ] as [(Int, TimeInterval)])
    func aChunksSweepGrowsWithItAndThenStops(length: Int, span: TimeInterval) {
        #expect(abs(AskArrivals.stagger(forLength: length) - span) < 1e-9)
        #expect(abs(AskArrivals.settle(forLength: length) - (AskArrivals.fade + span)) < 1e-9)
    }

    /// **The bound that keeps this drawing rather than pacing.** The same
    /// question answered on device streamed 162 characters over 819 ms of prose
    /// span, so a cloud chunk of that size has its tail fully drawn before the
    /// device tier would have written it — the reader never waits on ink for
    /// text a slower tier would have shown them later anyway.
    /// `AskArrivals.staggerPerCharacter` carries the measurement.
    @Test func aCloudChunkIsDrawnNoLaterThanTheDeviceTierWouldHaveWrittenIt() {
        #expect(AskArrivals.settle(forLength: 162) <= 0.819)
    }

    /// What the store waits out before it drops the stamps
    /// (`forgetChunksOnceSettled`): the longest sweep still running, not a
    /// constant, or a cloud-sized chunk is painted opaque part-way through its
    /// own drawing-in.
    @Test func theWaitBeforeStampsAreDroppedIsTheLongestSweepLeft() {
        let long = AskRevealChunk(length: 160, arrival: 100)
        let short = AskRevealChunk(length: 3, arrival: 100)
        #expect(
            abs(AskArrivals.timeUntilSettled([short, long], at: 100)
                - AskArrivals.settle(forLength: 160)) < 1e-9
        )
        // A chunk that landed long ago asks for nothing, and neither does a
        // turn with no chunks left.
        #expect(AskArrivals.timeUntilSettled([long], at: 200) == 0)
        #expect(AskArrivals.timeUntilSettled([], at: 0) == 0)
    }

    /// House rule 3: the model writes both halves of a markdown link, so a
    /// rendered one is a tap target whose destination the reader cannot see.
    /// Every route into the reveal — streaming and restore-from-disk — comes
    /// through `parse`, so the strip belongs there and nowhere else.
    @Test func aLinkInModelProseIsStrippedOfItsDestination() {
        let attributed = AskArrivals.parse("See [your bank](https://elsewhere.example/) now")

        #expect(attributed.runs.allSatisfy { $0.link == nil },
                "a destination the reader cannot see must not survive the parse")
        // The label stays: stripping the destination must not eat the prose.
        #expect(String(attributed.characters) == "See your bank now")
    }

    @Test func aBareURLIsNotAutoLinkedAndAnImageURLIsDropped() {
        // No injection needed — the model copying a URL out of a row title is
        // enough for the parser to make it tappable.
        let bare = AskArrivals.parse("Found it at https://elsewhere.example/path")
        #expect(bare.runs.allSatisfy { $0.link == nil })

        // An image reference fetches on sight rather than on a tap.
        let image = AskArrivals.parse("Here ![alt](https://elsewhere.example/pixel.png)")
        #expect(image.runs.allSatisfy { $0.imageURL == nil })
        #expect(image.runs.allSatisfy { $0.link == nil })
    }

    @Test func strippingLinksLeavesTheInlineMarkdownThatMattersAlone() {
        // The strip must not be a blanket attribute wipe: bold and italic are
        // what the parse is *for*.
        let attributed = AskArrivals.parse("**Olive** and *green*")
        #expect(String(attributed.characters) == "Olive and green")
        #expect(attributed.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(attributed.runs.contains { $0.inlinePresentationIntent == .emphasized })
    }

    /// The text of every run the parse made bold, joined.
    private func bolded(_ attributed: AttributedString) -> String {
        attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(attributed[$0.range].characters) }
            .joined()
    }

    @Test func aBoldTitleInItsOwnBracketsRendersInChineseAndJapanese() {
        // CommonMark won't close `**` after a closing bracket with a letter
        // straight after it, nor open one after a letter with a bracket
        // straight after. Chinese and Japanese write the next word on with no
        // space, so a title bolded in its own brackets, as the answer guide
        // asks, would show its asterisks.
        let chinese = parsed("**《三体》**是刘慈欣写的。")
        #expect(String(chinese.characters) == "《三体》是刘慈欣写的。")
        #expect(bolded(chinese) == "《三体》")
        let japanese = parsed("おすすめは**「雪国」**です。")
        #expect(String(japanese.characters) == "おすすめは「雪国」です。")
        #expect(bolded(japanese) == "「雪国」")
        let quoted = parsed("我推荐**“三体”**和**《雪国》**。")
        #expect(String(quoted.characters) == "我推荐“三体”和《雪国》。")
        #expect(bolded(quoted) == "“三体”《雪国》")
    }

    @Test func boldThatCommonMarkAlreadyRendersIsLeftAsItIs() {
        let plain = parsed("推荐**三体**和*雪国*。")
        #expect(String(plain.characters) == "推荐三体和雪国。")
        #expect(bolded(plain) == "三体")
        #expect(plain.runs.contains { $0.inlinePresentationIntent == .emphasized })
    }

    @Test func asterisksLeftInSpacedProseStayAsTheyCame() {
        // Only a pair CommonMark refused for the next word's script is bolded
        // here. In spaced prose its verdict stands.
        #expect(String(parsed("**\"Rumours\"**is").characters) == "**\"Rumours\"**is")
        // And a lone pair still waiting for its partner is left alone.
        #expect(String(parsed("**《三体》是").characters) == "**《三体》是")
    }

    @Test func aBoldMarkTheParseSwallowsLeavesNoTraceOfTheOther() {
        // A taken-over pair whose closer lands in a link's destination loses
        // it with the link; its opener, left in the link's words, is dropped
        // rather than drawn as a private-use box.
        let attributed = parsed("[是**《三体](http://x。**)")
        #expect(String(attributed.characters) == "是《三体")
        #expect(!String(attributed.characters).unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) })
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
/// When each piece under an answer starts to come up (`AskArrival`): a step
/// behind the piece before it, and never later than the last step however many
/// pieces there are, so a long grid still lands with its answer. A wave's base
/// and a piece's place within it are capped separately: the cap bounds the
/// cascade, and doesn't flatten a wave that starts deep.
@Suite(.timeLimit(.minutes(1))) struct AskArrivalTests {
    @Test(arguments: [(0, 0.0), (1, 0.05), (6, 0.3), (7, 0.3), (40, 0.3), (-1, 0.0)])
    func aPieceStartsAStepBehindTheOneBeforeIt(step: Int, delay: TimeInterval) {
        #expect(abs(AskArrival.delay(forStep: step) - delay) < 1e-9)
    }

    /// A piece built as its answer ends arrives, and so does one built while
    /// the cascade is still running. One built long after — a row the thread
    /// rebuilt on a scroll back — is the same answer read again, and one with no
    /// ending behind it belongs to a turn that is not the newest to end.
    @Test(arguments: [
        (Optional(1000.0), 1000.0, true),
        (Optional(1000.0), 1000.7, true),
        (Optional(1000.0), 1000 + AskArrival.liveWindow, false),
        (Optional(1000.0), 1300.0, false),
        (nil, 1000.0, false)
    ] as [(TimeInterval?, TimeInterval, Bool)])
    func aPieceArrivesOnlyNearItsEnding(endedAt: TimeInterval?, now: TimeInterval, arrives: Bool) {
        #expect(AskArrival.isLive(endedAt: endedAt, now: now) == arrives)
    }

    /// **Capping the sum would collapse a deep wave.** The follow-up bank's
    /// base is `evidenceStep + 4`, which with a basis line above it is exactly
    /// `lastStep`: under a capped sum every chip would get the delay the first
    /// one has, and a bank of four would come in on one frame and read as a
    /// pop. Each part is capped on its own, so a bank keeps its reading order
    /// wherever the row put it.
    @Test func aWaveThatStartsAtTheCapStillStaggersItsOwnPieces() {
        let deep = AskArrival.delay(base: AskArrival.lastStep, forStep: 0)
        let next = AskArrival.delay(base: AskArrival.lastStep, forStep: 1)
        #expect(next > deep, "two pieces of one bank must not share a delay")
        #expect(abs(next - deep - AskArrival.stagger) < 1e-9)
        // A row that overspends its budget starts no later than one that spends
        // it exactly: the base is still bounded, just on its own.
        #expect(abs(AskArrival.delay(base: AskArrival.lastStep + 5, forStep: 0) - deep) < 1e-9)
        // And the base is what the wave adds: the first piece of a deep wave
        // comes in behind the first piece of a wave at the start.
        #expect(deep > AskArrival.delay(base: 0, forStep: 0))
    }

    /// The window outlasts the longest cascade: the deepest wave's last piece
    /// and the slower of the two curves.
    @Test func theWindowOutlastsTheCascade() {
        #expect(AskArrival.delay(base: .max, forStep: .max) + 0.4 < AskArrival.liveWindow)
    }
}
#endif

#if os(macOS)
import AppKit
import SwiftUI

/// The half of the reveal no value test can reach: that a stamp set on the text
/// actually survives into `Text.Layout`, where `AskRevealRenderer.draw` reads it
/// back.
///
/// It matters because the failure is SILENT and looks like success. If the
/// attribute were dropped, `run[AskArrivalStamp.self]` would be nil for every
/// run, `progress` would be 1, and each glyph would be drawn at full opacity:
/// a finished answer looks exactly right, and the drawing-in is simply gone.
/// So the assertion is that a freshly arrived chunk renders FAINTER than the
/// same chunk once its fade is over.
///
/// **It guards the one route that carries a stamp,** `Text.customAttribute`
/// on each piece, joined (`AskReveal.text`). Why not an
/// `AttributedStringKey`: ARCHITECTURE.md, Rejected designs.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskRevealRenderTests {

    /// One rendered frame's ink, as mean luminance per horizontal band, 0…1.
    /// Black text on white, so a faded run reads LIGHTER — closer to 1 — than a
    /// settled one. One band unless a test needs to see left from right.
    ///
    /// `down` reads the bands top to bottom instead of left to right, which is
    /// how a chunk wrapping several lines is told from one that fits on one.
    private func bands(
        _ text: Text,
        now: TimeInterval,
        renderer make: (TimeInterval) -> AskRevealRenderer = { AskRevealRenderer(now: $0, blurs: false, staggers: false, caret: nil) },
        count: Int = 1,
        height: CGFloat = 40,
        down: Bool = false
    ) -> [Double]? {
        let host = text
            .font(.body)
            .foregroundStyle(.black)
            .textRenderer(make(now))
            .frame(width: 400, height: height, alignment: .leading)
            .background(.white)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        var totals = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        let width = bitmap.pixelsWide
        let tall = bitmap.pixelsHigh
        for y in 0..<tall {
            for x in 0..<width {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                let band = down
                    ? min(count - 1, y * count / tall)
                    : min(count - 1, x * count / width)
                totals[band] += Double(colour.brightnessComponent)
                counts[band] += 1
            }
        }
        guard counts.allSatisfy({ $0 > 0 }) else { return nil }
        return zip(totals, counts).map { $0 / Double($1) }
    }

    private func ink(_ text: Text, now: TimeInterval) -> Double? {
        bands(text, now: now)?.first
    }

    private let prose = "Yes — eight green pieces"

    @Test func theStampReachesTheLayout() throws {
        let arrival: TimeInterval = 1000
        let chunks = [AskRevealChunk(length: prose.count, arrival: arrival)]
        let attributed = AskArrivals.parse(prose)

        // Barely arrived: `progress` ≈ 0, so the run is drawn near-invisible and
        // the frame is almost all background.
        let fresh = try #require(ink(AskReveal.text(attributed, chunks: chunks), now: arrival + 0.01))
        // Well past the fade: full opacity, so the glyphs darken it.
        let settled = try #require(ink(AskReveal.text(attributed, chunks: chunks), now: arrival + 5))

        #expect(
            fresh > settled,
            "a just-arrived chunk must render lighter than a settled one — if these match the stamp never reached Text.Layout and the reveal is dead"
        )
        // A real difference, not a rounding one.
        #expect(fresh - settled > 0.01, "the difference must be visible")
    }

    @Test func aChunksLengthIsHowMuchOfTheProseItHoldsBack() throws {
        // The off-by-one: `chunks` is arithmetic over character counts, and if
        // the slicing is a character wrong the fade lands on the wrong words.
        // Asserted as a monotone relationship rather than against pixel
        // columns: how much of the prose a just-arrived chunk SPANS is exactly
        // how much ink is held back, so a longer arriving chunk must leave a
        // lighter frame.
        let now: TimeInterval = 1000
        let long = "Yes — eight green pieces, mostly tees"
        let attributed = AskArrivals.parse(long)
        let total = attributed.characters.count

        func inkWithArriving(_ length: Int) throws -> Double {
            var chunks: [AskRevealChunk] = []
            if total > length { chunks.append(AskRevealChunk(length: total - length, arrival: now - 5)) }
            chunks.append(AskRevealChunk(length: length, arrival: now))
            return try #require(ink(AskReveal.text(attributed, chunks: chunks), now: now))
        }

        let little = try inkWithArriving(4)
        let half = try inkWithArriving(total / 2)
        let all = try inkWithArriving(total)

        #expect(little < half, "more arriving text must mean more of it held back")
        #expect(half < all)
        #expect(all - little > 0.02)
    }

    @Test func aTurnWithNoChunksRendersOpaqueWhateverTheClockSays() throws {
        // What a turn restored from disk has: no stamps, so no clock can hold
        // it faint, and an answer can't be left frozen part-way drawn.
        let attributed = AskArrivals.parse(prose)
        let cold = try #require(ink(AskReveal.text(attributed, chunks: []), now: 0))
        let warm = try #require(ink(AskReveal.text(attributed, chunks: []), now: 10_000))
        #expect(cold == warm)

        // And it matches a settled stamped render — fully drawn either way.
        let chunks = [AskRevealChunk(length: prose.count, arrival: 1)]
        let settled = try #require(ink(AskReveal.text(attributed, chunks: chunks), now: 100))
        #expect(abs(cold - settled) < 0.001)
    }

    @Test func theCaretDrawsInkOfItsOwn() throws {
        // The streaming caret is the only thing the renderer adds rather than
        // dims, so it is the one part a luminance read can see directly.
        let attributed = AskArrivals.parse(prose)
        func inkWithCaret(_ caret: AskCaret?) -> Double? {
            bands(
                AskReveal.text(attributed, chunks: []),
                now: 0,
                renderer: { AskRevealRenderer(now: $0, blurs: false, staggers: false, caret: caret) }
            )?.first
        }
        let without = try #require(inkWithCaret(nil))
        let with = try #require(inkWithCaret(.color(.black)))
        #expect(with < without, "the caret must put ink on the frame")
    }

    /// The darkest pixel of each column of one rendered frame, 0…1, laid out
    /// in `direction`, the caret drawn or not. Dark by luma, not by HSB
    /// brightness, which reads a saturated blue as bright as white, so a
    /// spectrum's caret would leave no mark.
    private func columns(_ prose: String, caret: AskCaret?, direction: LayoutDirection) -> [Double]? {
        let host = AskReveal.text(AskArrivals.parse(prose), chunks: [])
            .font(.body)
            .foregroundStyle(.black)
            .textRenderer(AskRevealRenderer(now: 0, blurs: false, staggers: false, caret: caret))
            .frame(width: 400, height: 40, alignment: .leading)
            .background(.white)
            .environment(\.layoutDirection, direction)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        func luma(_ color: NSColor?) -> Double {
            guard let rgb = color?.usingColorSpace(.sRGB) else { return 1 }
            return 0.2126 * Double(rgb.redComponent) + 0.7152 * Double(rgb.greenComponent)
                + 0.0722 * Double(rgb.blueComponent)
        }
        return (0..<bitmap.pixelsWide).map { x in
            (0..<bitmap.pixelsHigh).reduce(1.0) { darkest, y in
                min(darkest, luma(bitmap.colorAt(x: x, y: y)))
            }
        }
    }

    /// Where the caret put ink, and where the words are, as column ranges.
    private func caretAndWords(
        _ prose: String,
        direction: LayoutDirection,
        drawnIn drawing: AskCaret = .color(.black)
    ) throws -> (caret: [Int], words: ClosedRange<Int>) {
        let without = try #require(columns(prose, caret: nil, direction: direction))
        let with = try #require(columns(prose, caret: drawing, direction: direction))
        let inked = without.indices.filter { without[$0] < 0.5 }
        let first = try #require(inked.first)
        let last = try #require(inked.last)
        let words = first...last
        let caret = with.indices.filter { with[$0] < without[$0] - 0.2 }
        return (caret, words)
    }

    @Test func theCaretFollowsTheLastGlyphLeftToRight() throws {
        let (caret, words) = try caretAndWords(prose, direction: .leftToRight)
        #expect(!caret.isEmpty)
        #expect(caret.allSatisfy { $0 > words.upperBound }, "caret \(caret) against words \(words)")
    }

    /// A spectrum's caret, its gradient over a soft glow, puts ink after the
    /// last glyph as the accent's dot does, and its glow stays off the words.
    @Test func aSpectrumsCaretFollowsTheLastGlyph() throws {
        let (caret, words) = try caretAndWords(prose, direction: .leftToRight, drawnIn: AskSpectrumLook.spectrum(.aurora).caret)
        #expect(!caret.isEmpty)
        #expect(caret.allSatisfy { $0 > words.upperBound }, "caret \(caret) against words \(words)")
    }

    @Test func theCaretFollowsTheLastGlyphRightToLeft() throws {
        // Hebrew reads right to left, so its last glyph in reading order is
        // its leftmost, and the caret goes past it there, never on the words.
        let (caret, words) = try caretAndWords("כן — שמונה חלקים ירוקים", direction: .rightToLeft)
        #expect(!caret.isEmpty)
        #expect(caret.allSatisfy { $0 < words.lowerBound }, "caret \(caret) against words \(words)")
    }

    @Test func theStaggerRunsWithinAChunkNotAcrossTheLine() throws {
        // A chunk is one run, so a delay taken from the run's position on the
        // LINE gives the whole chunk one delay — no stagger at all. The delay
        // has to come from the glyph's position inside its own run.
        //
        // Measured against the flat fade rather than across the frame: a band
        // split is mostly blank paper and reads the words' own positions. With
        // the stagger on, every glyph but the first is BEHIND where the flat
        // fade puts it, so at a moment inside the sweep — 120 ms for this
        // chunk's length — the staggered frame carries less ink, and once both
        // have settled they are identical.
        let arrival: TimeInterval = 1000
        let attributed = AskArrivals.parse(prose)
        let chunks = [AskRevealChunk(length: prose.count, arrival: arrival)]
        let text = AskReveal.text(attributed, chunks: chunks)
        func staggered(at now: TimeInterval) -> Double? {
            bands(
                text, now: now,
                renderer: { AskRevealRenderer(now: $0, blurs: false, staggers: true, caret: nil) }
            )?.first
        }

        let lagging = try #require(staggered(at: arrival + 0.06))
        let flat = try #require(ink(text, now: arrival + 0.06))
        #expect(
            lagging > flat,
            "inside the stagger span the tail must still be held back — if these match the whole chunk shares one delay and there is no stagger"
        )

        // Past fade + stagger, both are the finished answer.
        let staggeredDone = try #require(staggered(at: arrival + 5))
        let flatDone = try #require(ink(text, now: arrival + 5))
        #expect(abs(staggeredDone - flatDone) < 0.001, "the stagger must not survive the settle")
    }

    /// A sentence landing in one snapshot, which is what a cloud tier does.
    private let sentence = "You own several olive pieces that would work here, and the navy blazer goes over any of them."

    private func sweeping(_ text: Text, at now: TimeInterval, bands count: Int = 1, down: Bool = false) -> [Double]? {
        bands(
            text, now: now,
            renderer: { AskRevealRenderer(now: $0, blurs: false, staggers: true, caret: nil) },
            count: count, height: 80, down: down
        )
    }

    /// **The pop, as a render.** At the moment a device-sized growth of a few
    /// characters has finished crossing its words, a sentence landing whole must
    /// still be crossing its own, and be finished by its own settle and not a
    /// frame later. With one sweep for every length, 92 characters would be
    /// drawn in the 330 ms four are, which is a paragraph appearing at once.
    @Test func aCloudSizedChunkIsStillDrawingWhereADeviceSizedOneHasFinished() throws {
        let arrival: TimeInterval = 1000
        let attributed = AskArrivals.parse(sentence)
        let length = attributed.characters.count
        let text = AskReveal.text(attributed, chunks: [AskRevealChunk(length: length, arrival: arrival)])

        let done = try #require(sweeping(text, at: arrival + 5)?.first)
        let atTheShortSettle = try #require(sweeping(text, at: arrival + AskArrivals.settle + 0.01)?.first)
        #expect(
            atTheShortSettle > done,
            "a sentence that arrived whole must still be drawing where a four-character growth has finished — if these match the sweep is a constant again and the answer pops"
        )
        #expect(atTheShortSettle - done > 0.001, "the difference must be visible")

        let atItsOwn = try #require(sweeping(text, at: arrival + AskArrivals.settle(forLength: length) + 0.01)?.first)
        #expect(abs(atItsOwn - done) < 0.001, "and it must be finished by its own settle, not held past it")
    }

    /// **One sweep across the chunk, not one per line.** A chunk is one
    /// `customAttribute` and a line is one run, so a delay counted inside the
    /// run restarts on every line the chunk wraps to — the lines rippling in
    /// parallel, which is the block the sweep exists to break, and the longer
    /// the sweep the more plainly it shows.
    ///
    /// Each band against its own settled ink, because the two lines hold
    /// different amounts of text and a raw luminance read compares the words'
    /// own positions rather than the sweep.
    @Test func aChunkThatWrapsSweepsOnAcrossItsLinesRatherThanRestarting() throws {
        let arrival: TimeInterval = 1000
        let attributed = AskArrivals.parse(sentence)
        let text = AskReveal.text(
            attributed,
            chunks: [AskRevealChunk(length: attributed.characters.count, arrival: arrival)]
        )
        let midSweep = try #require(sweeping(text, at: arrival + 0.3, bands: 2, down: true))
        let settled = try #require(sweeping(text, at: arrival + 5, bands: 2, down: true))
        #expect(settled.count == 2 && midSweep.count == 2)

        let heldBack = zip(midSweep, settled).map { $0 - $1 }
        #expect(heldBack[0] > 0.001, "the first line must still be drawing at all")
        #expect(
            heldBack[1] > heldBack[0],
            "the second line must be further behind than the first — if they match the sweep restarts per line and a wrapped chunk still lands as a block"
        )
    }

    /// The ink of each half of the prose's own width, left and right, in one
    /// frame of a chunk that arrived at `arrival`, swept and laid out in
    /// `direction`: dark by luma, summed down each column. The halves split
    /// the columns `inked` names, which a settled frame gives, so they are the
    /// words' halves and not the paper's.
    private func halves(
        _ prose: String,
        direction: LayoutDirection,
        arrival: TimeInterval,
        at now: TimeInterval,
        inked: ClosedRange<Int>? = nil
    ) -> (left: Double, right: Double, inked: ClosedRange<Int>)? {
        let attributed = AskArrivals.parse(prose)
        let host = AskReveal.text(attributed, chunks: [AskRevealChunk(length: attributed.characters.count, arrival: arrival)])
            .font(.body)
            .foregroundStyle(.black)
            .textRenderer(AskRevealRenderer(now: now, blurs: false, staggers: true, caret: nil))
            .frame(width: 600, height: 40, alignment: .leading)
            .background(.white)
            .environment(\.layoutDirection, direction)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let columns = (0..<bitmap.pixelsWide).map { x in
            (0..<bitmap.pixelsHigh).reduce(0.0) { total, y in
                guard let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return total }
                let luma = 0.2126 * Double(rgb.redComponent) + 0.7152 * Double(rgb.greenComponent)
                    + 0.0722 * Double(rgb.blueComponent)
                return total + (1 - luma)
            }
        }
        let range: ClosedRange<Int>
        if let inked {
            range = inked
        } else {
            let dark = columns.indices.filter { columns[$0] > 0.5 }
            guard let first = dark.first, let last = dark.last, last > first else { return nil }
            range = first...last
        }
        let middle = (range.lowerBound + range.upperBound) / 2
        let left = columns[range.lowerBound..<middle].reduce(0, +)
        let right = columns[middle...range.upperBound].reduce(0, +)
        return (left, right, range)
    }

    /// How far behind its settled ink each half of the prose is, mid-sweep.
    private func heldBack(_ prose: String, direction: LayoutDirection) throws -> (left: Double, right: Double) {
        let arrival: TimeInterval = 1000
        let settled = try #require(halves(prose, direction: direction, arrival: arrival, at: arrival + 5))
        let span = AskArrivals.stagger(forLength: AskArrivals.parse(prose).characters.count)
        let mid = try #require(
            halves(prose, direction: direction, arrival: arrival, at: arrival + span / 2, inked: settled.inked)
        )
        return (settled.left - mid.left, settled.right - mid.right)
    }

    /// **A right-to-left chunk sweeps in from its right**, where Hebrew starts,
    /// so mid-sweep its left half, read last, is further behind than its right.
    /// Swept in the layout's order, a right-to-left run's slices run left to
    /// right, and the sentence inked in from its end.
    @Test func aRightToLeftChunkSweepsInFromItsRight() throws {
        let behind = try heldBack("יש לך כמה פריטים ירוקים שיתאימו כאן והבלייזר הכחול", direction: .rightToLeft)
        #expect(behind.right > 0, "the reading's start must still be drawing at all")
        #expect(
            behind.left > behind.right,
            "the left half, read last, must be further behind — if not, the sweep runs against the reading in Hebrew (\(behind))"
        )
    }

    /// And a left-to-right one from its left: the same measure, the other way.
    @Test func aLeftToRightChunkSweepsInFromItsLeft() throws {
        let behind = try heldBack("You own several olive pieces that would work here", direction: .leftToRight)
        #expect(behind.left > 0)
        #expect(behind.right > behind.left, "\(behind)")
    }

    @Test func aRealStreamsWorthOfChunksStillReveals() throws {
        // The join nests one `Text` interpolation per chunk, and a Private Cloud
        // Compute answer arrives in dozens of snapshots — so the shape that has
        // to hold is thirty deep, not the two the other tests build. If nesting
        // ever costs the stamp, this is where it shows.
        let long = String(repeating: "one two three ", count: 8).trimmingCharacters(in: .whitespaces)
        let attributed = AskArrivals.parse(long)
        let total = attributed.characters.count
        let pieces = 30
        let each = total / pieces

        var chunks: [AskRevealChunk] = []
        var used = 0
        for index in 0..<(pieces - 1) {
            chunks.append(AskRevealChunk(length: each, arrival: 1000 - Double(pieces - index)))
            used += each
        }
        // The last chunk lands now; everything before it settled seconds ago.
        chunks.append(AskRevealChunk(length: total - used, arrival: 1000))
        #expect(chunks.count == pieces)

        let text = AskReveal.text(attributed, chunks: chunks)
        let arriving = try #require(ink(text, now: 1000.01))
        let done = try #require(ink(text, now: 1005))
        #expect(arriving > done, "at thirty chunks deep the last one must still fade in")
        #expect(arriving - done > 0.001)
    }

    /// Every pixel of one frame, for telling two renders apart exactly where
    /// `bands` compares means.
    ///
    /// **Drawn straight into this bitmap, not read back from `cgImage`.** Read
    /// back, the same view could draw a fading run one level in 255 lighter or
    /// darker depending on what the process had rendered before it: the
    /// merging test below failed in its suite on 11 runs of 31 and on none of
    /// 8 alone, every time on the same 663 bytes of one frame. Drawn through
    /// `render(rasterizationScale:renderer:)` it passed 12 of 12, and it still
    /// fails 3 of 3 when `mergeAge` loses its beat. That failure is at most 2
    /// levels, which is why the comparison stays exact rather than allowing 1.
    private func pixels(_ text: Text, renderer: AskRevealRenderer) -> [UInt8]? {
        let host = text
            .font(.body)
            .foregroundStyle(.black)
            .textRenderer(renderer)
            .frame(width: 400, height: 160, alignment: .topLeading)
            .background(.white)
        let image = ImageRenderer(content: host)
        let (width, height) = (800, 320)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(alpha: .premultipliedLast)
            ) else { return false }
            context.scaleBy(x: 2, y: 2)
            image.render(rasterizationScale: 2) { _, draw in draw(context) }
            return true
        }
        return drawn ? bytes : nil
    }

    /// **Merging is invisible.** Merging a long answer's finished chunks into
    /// one unstamped stretch must leave every pixel of every frame where the
    /// unmerged chunks put it, swept and blurred and under Reduce Motion's flat
    /// fade, from a frame drawn a tick behind the snapshot that merged to one
    /// long after the last sweep.
    ///
    /// The stream is the shape that tests it: a device tier's seven characters
    /// every 35 ms, then a cloud tier's sentence long enough to take the longest
    /// sweep, a short growth behind it that settles first, and a last growth
    /// landing the moment the sentence merges. That is the edge of the longest
    /// sweep, and the frame a tick behind it is where `mergeAge`'s beat earns
    /// its keep.
    @Test func mergingTheFinishedInkChangesNoPixelOfAnyFrame() throws {
        let device = "Yes, you own eight green pieces: the olive field jacket, two sage tees, a forest knit, "
            + "the mint oxford, a pair of moss chinos you added in the spring, and two wool scarves "
            + "in bottle green that you have not worn since you bought them. "
        let cloud = "The navy blazer goes over any of them, and the olive jacket is the one to reach for first on a cool evening."
        #expect(cloud.count >= 100, "long enough to sweep for the longest there is")

        var snapshots: [(text: String, at: TimeInterval)] = []
        var now = 1000.0
        var end = device.startIndex
        while end < device.endIndex {
            end = device.index(end, offsetBy: 7, limitedBy: device.endIndex) ?? device.endIndex
            now += 0.035
            snapshots.append((String(device[..<end]), now))
        }
        let landed = now + 0.035
        snapshots.append((device + cloud, landed))
        snapshots.append((device + cloud + " So", landed + 0.1))
        snapshots.append((device + cloud + " So, yes.", landed + AskArrivals.mergeAge + 0.001))

        var drawn = AttributedString()
        var merged: [AskRevealChunk] = []
        var unmerged: [AskRevealChunk] = []
        var states: [(drawn: AttributedString, merged: [AskRevealChunk], unmerged: [AskRevealChunk], at: TimeInterval)] = []
        for snapshot in snapshots {
            let next = AskArrivals.parse(snapshot.text)
            merged = AskArrivals.chunks(merged, from: drawn, to: next, at: snapshot.at)
            unmerged.append(AskRevealChunk(length: next.characters.count - drawn.characters.count, arrival: snapshot.at))
            drawn = next
            states.append((drawn, merged, unmerged, snapshot.at))
        }
        // The short growth behind the sentence, and the last one, which lands
        // as the sentence merges and the short one doesn't.
        let behind = states[states.count - 2]
        let last = states[states.count - 1]
        #expect(behind.merged.first?.isSettled == true && behind.merged.count < behind.unmerged.count)
        #expect(last.merged.count == 3 && last.merged[0].isSettled && !last.merged[1].isSettled)

        let modes = [
            (blurs: true, staggers: true),
            (blurs: false, staggers: false)
        ]
        for state in [behind, last] {
            let mergedText = AskReveal.text(state.drawn, chunks: state.merged)
            let unmergedText = AskReveal.text(state.drawn, chunks: state.unmerged)
            for mode in modes {
                func frame(_ text: Text, at moment: TimeInterval) throws -> [UInt8] {
                    try #require(pixels(text, renderer: AskRevealRenderer(
                        now: moment, blurs: mode.blurs, staggers: mode.staggers
                    )))
                }
                for offset in [-1.0 / 60, 0, 0.05, 0.2, 0.4, 0.8, 3] {
                    let drawnMerged = try frame(mergedText, at: state.at + offset)
                    let drawnUnmerged = try frame(unmergedText, at: state.at + offset)
                    #expect(
                        drawnMerged == drawnUnmerged,
                        "merged and unmerged must draw the same frame \(offset)s after the snapshot, \(mode)"
                    )
                }
                // And the frames are moving, so matching them says something.
                let early = try frame(unmergedText, at: state.at + 0.05)
                let late = try frame(unmergedText, at: state.at + 3)
                #expect(early != late)
            }
        }
    }
}

/// A picture that is there when its view is built is drawn at rest in that
/// first frame: only the placeholder giving way moves. A render is exactly the
/// first frame, so a picture held back for an arrival it has no need of, faint
/// or still behind its placeholder, renders the wrong colour.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskPictureArrivalRenderTests {
    private let picture = Color(red: 1, green: 0, blue: 0)
    private let placeholder = Color(red: 0, green: 0, blue: 1)

    /// The rendered square's mean red and blue, 0…1, over white.
    private func mean(_ view: some View) -> (red: Double, blue: Double)? {
        let renderer = ImageRenderer(content: view.frame(width: 40, height: 40).background(.white))
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        var red = 0.0
        var blue = 0.0
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                red += Double(colour.redComponent)
                blue += Double(colour.blueComponent)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (red / Double(count), blue / Double(count))
    }

    @Test func aPictureThereWhenItIsBuiltIsDrawnAtRest() throws {
        let drawn = try #require(mean(AskPictureArrival(picture) { $0 } placeholder: { placeholder }))
        #expect(drawn.red > 0.9 && drawn.blue < 0.1)
    }

    @Test func noPictureYetDrawsItsPlaceholder() throws {
        let drawn = try #require(mean(AskPictureArrival(Color?.none) { $0 } placeholder: { placeholder }))
        #expect(drawn.blue > 0.9 && drawn.red < 0.1)
    }
}

/// The send circle's fill (`AskSendFill`), rendered.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskSendFillRenderTests {
    /// **The accent's circle is the accent, top to bottom**, so its glyph is
    /// drawn on what it was judged against (`AskOnAccent`). `Color.gradient`
    /// drew the top lighter, where white on the system blue is short of the
    /// 3.52:1 it was judged at.
    @Test func theAccentsCircleIsFlat() throws {
        let host = Rectangle()
            .fill(AskSendFill(accent: Color(red: 0, green: 136 / 255, blue: 1), spectrum: nil))
            .frame(width: 10, height: 100)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let top = try #require(bitmap.colorAt(x: 5, y: 1)?.usingColorSpace(.sRGB))
        let bottom = try #require(bitmap.colorAt(x: 5, y: 98)?.usingColorSpace(.sRGB))
        #expect(abs(top.redComponent - bottom.redComponent) < 0.01, "\(top) against \(bottom)")
        #expect(abs(top.greenComponent - bottom.greenComponent) < 0.01, "\(top) against \(bottom)")
    }
}

/// The wait row's shimmer (`ShimmerSweep`): which way its band runs, and how
/// strong it is.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskShimmerTests {
    /// The column, 0…1 across, where the band at `phase` is strongest, laid
    /// out in `direction`: the reddest column of a red band over white.
    private func peak(at phase: Double, direction: LayoutDirection) -> Double? {
        let host = ShimmerSweep.band(at: phase, color: Color(red: 1, green: 0, blue: 0))
            .frame(width: 200, height: 10)
            .background(.white)
            .environment(\.layoutDirection, direction)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let redness = (0..<bitmap.pixelsWide).map { x -> Double in
            guard let rgb = bitmap.colorAt(x: x, y: 5)?.usingColorSpace(.sRGB) else { return 0 }
            return Double(rgb.redComponent) - Double(rgb.greenComponent)
        }
        guard let column = redness.indices.max(by: { redness[$0] < redness[$1] }) else { return nil }
        return Double(column) / Double(bitmap.pixelsWide)
    }

    /// **The band runs in reading direction**: from the left in English and
    /// from the right in Hebrew, since a gradient from `.leading` to
    /// `.trailing` is mirrored right to left.
    @Test func theBandRunsInReadingDirection() throws {
        let leftToRight = try #require(peak(at: 0.25, direction: .leftToRight))
        let rightToLeft = try #require(peak(at: 0.25, direction: .rightToLeft))
        #expect(abs(leftToRight - 0.25) < 0.05, "\(leftToRight)")
        #expect(abs(rightToLeft - 0.75) < 0.05, "\(rightToLeft)")
    }

    /// **In light mode the band keeps the line at 4.5:1**, a faint sheen of the
    /// accent; in dark mode it is the full 0.55, which takes the line further
    /// from the dark ground.
    @Test func theBandKeepsTheLinesContrastInLightMode() {
        let systemBlue = AskContrast.RGB(red: 0, green: 136 / 255, blue: 1)
        let yellow = AskContrast.RGB(red: 1, green: 214 / 255, blue: 10 / 255)
        #expect(ShimmerSweep.strength(for: systemBlue, isLight: true) == 0.09)
        #expect(ShimmerSweep.strength(for: yellow, isLight: true) == 0.05)
        #expect(ShimmerSweep.strength(for: systemBlue, isLight: false) == ShimmerSweep.darkStrength)
        let gray = AskContrast.deemphasizedLight
        let line = AskContrast.over(gray.color, opacity: gray.opacity, .white)
        for accent in [systemBlue, yellow, .white, .black] {
            let strength = ShimmerSweep.strength(for: accent, isLight: true)
            let lit = AskContrast.RGB(
                red: min(1, line.red + strength * accent.red),
                green: min(1, line.green + strength * accent.green),
                blue: min(1, line.blue + strength * accent.blue)
            )
            #expect(AskContrast.ratio(lit, .white) >= AskGlassForeground.text, "\(accent)")
        }
    }
}
#endif
