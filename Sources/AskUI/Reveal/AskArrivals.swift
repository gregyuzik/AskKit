import AskCore
public import Foundation

/// One stretch of answer text that arrived together: how many characters of the
/// drawn (markdown-parsed) text it spans, and when it landed.
///
/// **Offsets are into the parsed text on purpose.** The rendered runs live
/// there, where the asterisks are gone, so an offset into the raw markdown would
/// land the fade on the wrong words the moment the model bolds a name.
nonisolated struct AskRevealChunk: Equatable, Sendable {
    var length: Int
    var arrival: TimeInterval

    init(length: Int, arrival: TimeInterval) {
        self.length = length
        self.arrival = arrival
    }

    /// Ink that finished drawing before a later snapshot merged it
    /// (`AskArrivals.chunks`): the stretch keeps its length, so every offset
    /// after it stays put, and loses its arrival.
    ///
    /// **Minus infinity, so no clock brings it back.** Its age is infinite,
    /// which every rule already reads as long since drawn (`isRevealing` never
    /// counts it, and `timeUntilSettled` waits on nothing for it), whatever the
    /// clock does next, a jump backwards included, and however long a later
    /// merge makes it. `AskReveal.text` leaves it unstamped, which the renderer
    /// draws whole, as it drew every run of it the moment its own sweep ended.
    static func settled(length: Int) -> AskRevealChunk {
        AskRevealChunk(length: length, arrival: -.infinity)
    }

    /// Merged ink that no clock reaches.
    var isSettled: Bool { arrival == -.infinity }
}

/// The reveal's arithmetic, with no layout in sight: every rule the fade obeys
/// is a pure function here, so the shape is testable without building a
/// `Text.Layout`.
///
/// Three ideas: chunks counted in parsed characters, which survive a markdown
/// rewrite mid-stream; a comparison of character views, so a snapshot that only
/// restyles doesn't fade in again; and a sweep across each chunk.
nonisolated enum AskArrivals {
    /// How long a chunk takes to reach full opacity.
    static let fade: TimeInterval = 0.25

    /// The least a chunk's last character waits behind its first, a measured
    /// value: what an on-device growth of a few characters gets.
    static let stagger: TimeInterval = 0.08

    /// What each character of a chunk adds to the sweep, past the minimum.
    ///
    /// **This is what keeps a long chunk from popping in.** One sweep time for
    /// every length is right for the on-device tier, which writes a few
    /// characters a snapshot, and wrong for Private Cloud Compute, which can
    /// land a whole sentence in one: 160 characters swept across 80 ms is a
    /// paragraph appearing at once. Nothing is held back either way; what
    /// changes is how long the ink takes to cross the words already laid out.
    ///
    /// **The rate is a measurement, not a taste, and it is the ceiling on this
    /// being drawing rather than pacing.** Answered on device, one question
    /// streamed 162 characters over 819 ms of prose (the `[stream]` log line's
    /// `proseSpan=819ms chars=162`): 5 ms a character. So a Private Cloud
    /// Compute chunk swept at this rate has its last character fully drawn no
    /// later than the same answer would have reached it had the on-device tier
    /// written it, and the reader never waits on ink for text a slower tier would have
    /// shown them later anyway. That is the line house rule 4 draws, and why
    /// this isn't a pacing buffer (`AskRevealRenderer`).
    static let staggerPerCharacter: TimeInterval = 0.005

    /// Where the sweep stops growing. A hundred characters, past which a chunk
    /// is a paragraph and reading it takes longer than drawing it either way.
    static let longestStagger: TimeInterval = 0.5

    /// How long a chunk of `length` characters takes to sweep, first character
    /// to last.
    static func stagger(forLength length: Int) -> TimeInterval {
        min(longestStagger, max(stagger, Double(max(0, length)) * staggerPerCharacter))
    }

    /// Past this the shortest chunk is fully drawn. A line under an answer
    /// arrives on a curve this long too (`AskArrival.animation`).
    static var settle: TimeInterval { fade + stagger }

    /// Past this a chunk of `length` characters is fully drawn and its stamp
    /// says nothing.
    static func settle(forLength length: Int) -> TimeInterval {
        fade + stagger(forLength: length)
    }

    /// How old a chunk is when `chunks` merges it: past the fade after the
    /// longest sweep there is, so no chunk of any length is still drawing, and
    /// a beat past that.
    ///
    /// **Not each chunk's own `settle(forLength:)`, on purpose.** The renderer
    /// measures a chunk's sweep in glyphs (`drawSweeping` counts the slices of
    /// the runs that carry its stamp), while `length` counts characters, and
    /// the two counts part in languages AskKit ships: a Thai character can
    /// draw as a base glyph and the glyphs of its marks, and an Arabic
    /// ligature draws two characters as one glyph. A chunk that draws more
    /// glyphs than it has characters, as Thai can, sweeps for longer than its
    /// length says, and merging on the length would cut the end of that sweep
    /// short, which is the pop in reverse. The ceiling holds whatever the
    /// shaping does, and all it costs is a chunk kept a few hundred
    /// milliseconds longer than it had to be.
    ///
    /// **The beat is for a frame drawn behind the clock.** A snapshot is
    /// stamped with the store's clock as it lands, and the `TimelineView` the
    /// new chunks reach can draw them first with the date of a tick it took
    /// before that. Merged on the ceiling alone, the end of a longest sweep
    /// would be drawn whole on a frame that still had it a sliver short of
    /// full. Fifty milliseconds is three frames at 60 Hz and about one more
    /// chunk carried.
    static var mergeAge: TimeInterval { fade + longestStagger + 0.05 }

    /// Take a snapshot of the prose into chunks.
    ///
    /// The new text is whatever follows the longest common prefix with what was
    /// drawn before: usually a suffix, but an asterisk pair that closes across
    /// snapshots rewrites earlier characters too, and then everything from the
    /// first changed character on counts as newly arrived. `AskPrompt.partialText` makes that rare
    /// rather than impossible: it drops a dangling emphasis marker so successive
    /// snapshots are prefix-monotone, and the tidy pass at the end of a turn
    /// still restructures.
    ///
    /// **What has finished drawing merges, so the list carries only the ink
    /// still drying.** Unmerged, the list would grow by a chunk a snapshot for
    /// the whole turn (a 1,584-character answer in 317 snapshots ended at 285
    /// chunks), and every one of them is a slice `AskReveal.text` cuts, a
    /// `Text` it joins and a stamped run the renderer walks twice a frame, at
    /// 120 Hz on a ProMotion screen, for the whole of the stream. Merged, it is
    /// one settled stretch and the chunks that landed in the last `mergeAge`. A
    /// rewrite that reaches back into the settled stretch keeps what it didn't
    /// change settled, as it keeps the stamps of what it didn't change; what
    /// it changed arrives anew.
    static func chunks(
        _ previous: [AskRevealChunk],
        from old: AttributedString,
        to new: AttributedString,
        at now: TimeInterval
    ) -> [AskRevealChunk] {
        let common = commonPrefixLength(old.characters, new.characters)
        var kept: [AskRevealChunk] = []
        var covered = 0
        for chunk in previous {
            if covered + chunk.length <= common {
                kept.append(chunk)
                covered += chunk.length
            } else {
                let partial = common - covered
                if partial > 0 {
                    kept.append(AskRevealChunk(length: partial, arrival: chunk.arrival))
                    covered += partial
                }
                break
            }
        }
        kept = merged(kept, at: now)
        let remaining = new.characters.count - covered
        if remaining > 0 { kept.append(AskRevealChunk(length: remaining, arrival: now)) }
        return kept
    }

    /// The leading chunks that have finished drawing at `now`, merged into one
    /// settled stretch in front of the rest.
    ///
    /// **Leading only.** Arrivals only grow along the list, so what has
    /// finished is a prefix of it, unless the clock went backwards, and then a
    /// finished chunk after an unfinished one simply waits for the merge that
    /// reaches it. Stopping at the first chunk still drawing is what keeps the
    /// settled stretch one piece that the renderer draws whole.
    static func merged(_ chunks: [AskRevealChunk], at now: TimeInterval) -> [AskRevealChunk] {
        var end = 0
        var length = 0
        while end < chunks.count, chunks[end].isSettled || now - chunks[end].arrival >= mergeAge {
            length += chunks[end].length
            end += 1
        }
        // Nothing has finished, or what has is already the one settled stretch.
        guard end > 0, !(end == 1 && chunks[0].isSettled) else { return chunks }
        let rest = chunks[end...]
        return length > 0 ? [.settled(length: length)] + rest : Array(rest)
    }

    static func commonPrefixLength(
        _ lhs: AttributedString.CharacterView,
        _ rhs: AttributedString.CharacterView
    ) -> Int {
        var count = 0
        var left = lhs.startIndex
        var right = rhs.startIndex
        while left < lhs.endIndex, right < rhs.endIndex, lhs[left] == rhs[right] {
            count += 1
            lhs.formIndex(after: &left)
            rhs.formIndex(after: &right)
        }
        return count
    }

    /// The answer as attributed text: the inline markdown the model reaches for
    /// (a bolded title, the odd italic) rendered rather than shown as
    /// asterisks, line breaks kept, and nothing that would restructure the prose
    /// (a "- " list stays a list of dashes). A string the parser rejects is
    /// shown as it came. The reading is AskCore's (`AskMarkdown.parse`), the
    /// one a follow-up is made plain text with, so a chip says what the prose
    /// would have drawn.
    ///
    /// Every link the parse produced is then stripped. House rule 3 makes tool
    /// output untrusted data, and this is the render step it names: the model
    /// writes the label *and* the destination, so `[your bank](http://elsewhere)`
    /// arrives as a tap target inside trusted app chrome with the destination
    /// hidden behind the label. It doesn't take an injection to reach: a bare
    /// URL the model copies out of a row title is auto-linked by the same
    /// parser. Nothing in AskUI installs an `openURL` handler to vet the
    /// destination, and a restored thread is parsed again from its stored text,
    /// so the tap target would outlive the turn.
    ///
    /// `.imageURL` goes with it: same author, same trust, and it would fetch on
    /// sight rather than on a tap.
    ///
    /// Stripping here rather than at each call site is deliberate: this is the
    /// one door. The live streaming path and `AskTurn`'s restore-from-disk path
    /// both come through it.
    ///
    /// **Bold against Chinese and Japanese punctuation is bolded here.**
    /// CommonMark refuses `**《三体》**是…` and `おすすめは**「雪国」**です`, so the
    /// parse takes such a pair out of the parser's hands
    /// (`AskMarkdown.unspacedBold(in:)`), and it is bolded once the rest has
    /// parsed.
    static func parse(_ text: String) -> AttributedString {
        let reading = AskMarkdown.parse(text)
        var parsed = reading.parsed
        // Collect first, then mutate: `runs` is invalidated by a write through
        // the string it was taken from.
        for range in Array(parsed.runs.map(\.range)) {
            parsed[range].link = nil
            parsed[range].imageURL = nil
        }
        if reading.takenOver { boldBetweenMarks(&parsed) }
        return parsed
    }

    /// Bold every stretch between `AskMarkdown.boldOpens` and `boldCloses`,
    /// keeping any emphasis the parser gave it, and drop the marks.
    ///
    /// One pass finds the marks; the writes then run from the end, each
    /// index taken afresh, since a write through the string can move every
    /// index taken before it. This runs on every snapshot of a taken-over
    /// answer, so nothing here walks the string once per character.
    private static func boldBetweenMarks(_ parsed: inout AttributedString) {
        // The pairs, and any mark without its partner, which the parse could
        // only leave by swallowing one, say into a link's hidden destination:
        // that one is dropped rather than drawn.
        var pairs: [(opens: Int, closes: Int)] = []
        var strays: [Int] = []
        var opened: Int?
        for (offset, character) in parsed.characters.enumerated() {
            if character == AskMarkdown.boldOpens {
                if let earlier = opened { strays.append(earlier) }
                opened = offset
            } else if character == AskMarkdown.boldCloses {
                if let opens = opened { pairs.append((opens, offset)) } else { strays.append(offset) }
                opened = nil
            }
        }
        if let opened { strays.append(opened) }
        guard !pairs.isEmpty || !strays.isEmpty else { return }

        func index(_ offset: Int) -> AttributedString.Index {
            parsed.characters.index(parsed.characters.startIndex, offsetBy: offset)
        }
        // A stray is never inside a pair, so the edits sort by where they
        // start and run from the last.
        enum Edit { case bold(opens: Int, closes: Int), drop(Int) }
        let edits = (pairs.map { Edit.bold(opens: $0.opens, closes: $0.closes) } + strays.map { Edit.drop($0) })
            .sorted { lhs, rhs in
                func start(_ edit: Edit) -> Int {
                    switch edit {
                    case .bold(let opens, _): opens
                    case .drop(let offset): offset
                    }
                }
                return start(lhs) > start(rhs)
            }
        for edit in edits {
            switch edit {
            case .drop(let offset):
                parsed.removeSubrange(index(offset)..<index(offset + 1))
            case .bold(let opens, let closes):
                let inner = index(opens + 1)..<index(closes)
                let intents = parsed[inner].runs.map { run in
                    (
                        start: parsed.characters.distance(from: parsed.startIndex, to: run.range.lowerBound),
                        end: parsed.characters.distance(from: parsed.startIndex, to: run.range.upperBound),
                        intent: run.inlinePresentationIntent ?? []
                    )
                }
                for run in intents {
                    parsed[index(run.start)..<index(run.end)].inlinePresentationIntent =
                        run.intent.union(.stronglyEmphasized)
                }
                parsed.removeSubrange(index(closes)..<index(closes + 1))
                parsed.removeSubrange(index(opens)..<index(opens + 1))
            }
        }
    }

    /// Whether any chunk is still fading at `now`. Each chunk is measured
    /// against its own sweep, since a long one is still drawing when a short
    /// one that landed with it has finished.
    static func isRevealing(_ chunks: [AskRevealChunk], at now: TimeInterval) -> Bool {
        chunks.contains { now - $0.arrival < settle(forLength: $0.length) }
    }

    /// How long from `now` until the last of these chunks has finished drawing,
    /// and zero once none of them is.
    ///
    /// What the store waits out before it drops the stamps
    /// (`forgetChunksOnceSettled`): clearing them paints every run opaque, so a
    /// fixed wait shorter than the longest sweep would snap a long chunk to
    /// full part-way through the very drawing-in this file exists to give it.
    static func timeUntilSettled(_ chunks: [AskRevealChunk], at now: TimeInterval) -> TimeInterval {
        chunks.reduce(0) { longest, chunk in
            max(longest, chunk.arrival + settle(forLength: chunk.length) - now)
        }
    }
}
