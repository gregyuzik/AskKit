public import Foundation

/// Prompt hygiene, in one place: the fences the reader's words and tool output
/// are quoted inside, the sanitizer that stops either from closing a fence, and
/// the clamps that keep a tool result from eating the context window.
///
/// **The tag list and the sanitizer must not fall out of step.** That is the
/// failure that lets an answer close its own fence and start giving orders, so
/// they are one declaration read by both.
///
/// **Brackets are scalars, not Characters.** A combining mark or a variation
/// selector after `<` joins it in one `Character`, and so does a Prepend scalar
/// before it, so a comparison of Characters never sees the bracket while its
/// byte still reaches the model. The sanitizer and the bracket swap read
/// `unicodeScalars`, so text the host didn't write can't speak as the host
/// (house rule 3).
///
/// **What a tool uses.** The engine builds every prompt itself. What a tool
/// returns reaches the model as it stands, and its rows are the reader's own
/// data, so a tool puts each field through `clamp(_:_:)` with `shortClamp` or
/// `longClamp`, or, where its line breaks carry the layout the model reads,
/// through `sanitizeForFence(_:)`, then `neuteringTags(_:)`.
/// `sanitizeForFence(_:)` drops what a reader can't see and the control
/// characters, turns straight double quotes into double primes and redacts
/// AskKit's own fence tags, leaving every other bracket alone; `clamp` runs
/// it too, and `neuteringTags` doesn't.
nonisolated public enum AskPrompt {
    /// Longest question that reaches a model. Anything past this is a
    /// paste, not a question, and it costs context the tools need.
    ///
    /// SPI (`AskKitInternal`), with `clampQuestion(_:)`.
    @_spi(AskKitInternal) public static let maxQuestionLength = 500

    /// Every tag the prompt fences data in, and no other: the sanitizer
    /// redacts each of these in text it reads, so a tag nothing composes
    /// would only cost a host's tool the word.
    ///
    /// **Public so a tool can avoid them.** A tool returns its lines bare,
    /// with no fence of its own and none of these names: one it wrote would
    /// reach the model as `[redacted]`.
    public static let fenceTags: [String] = [
        "user_request", "rows", "previous_question", "previous_answer", "tool_result"
    ]

    /// Neuter anything that could close or open a fence from inside the
    /// reader's, a model's or a tool's text: each of AskKit's fence tags,
    /// opening or closing, becomes `[redacted]`, and every other bracket is
    /// left alone.
    ///
    /// **First, what a reader can't see goes, and the quote that would end
    /// the answer.** Before it reads for a tag, it drops what
    /// `droppingInvisibles(_:)` drops from the question: Unicode tag
    /// characters, which spell an order in ASCII and draw nothing; bidi
    /// controls, which draw text in another order than it is sent; a run of
    /// joiners and every other format character, keeping the joiners,
    /// selectors and subdivision flags real text spells. It drops every C0
    /// and C1 control too (`droppingControls(_:)`), but the tab and the line
    /// breaks, which are layout. And it turns each straight double quote into
    /// a double prime (`neuteringQuotes(_:)`; `clamp(_:_:)` says why). Every
    /// path that fences runs this, so each gets all three: the question's
    /// fence, the recaps, a photo's label, the grounded retry's rows, the
    /// clamp, and a tool's output that keeps its lines. A scalar that sat
    /// inside a tag goes before the tag is read: a control there ended the
    /// name, so `＜/ro␇ws＞` passed as another word.
    ///
    /// Case-insensitive, and tolerant of any whitespace inside the tag,
    /// newlines included, and of attributes: an XML-ish parser reading the
    /// prompt takes `</USER_REQUEST>`, `</user_request >`, `</user_request\n>`
    /// and `<user_request lang="en">` for the tags they spell, and any one of
    /// them is the failure the type's doc names: text closing its own fence
    /// and starting to give orders. A combining mark, a variation selector or
    /// a format character such as ZWJ beside the `<`, the slash or the name,
    /// or inside the name, is skipped the same way, since the letters around
    /// it still spell the tag.
    ///
    /// The fullwidth `＜` `＞`, the small `﹤` `﹥` and the negated `≮` `≯`
    /// open and close a tag as `<` and `>` do, and the fullwidth `／` spells
    /// its slash: NFKC maps the fullwidth and small forms to ASCII, and `≮`
    /// and `≯` decompose to `<` and `>` under a combining long solidus. Any
    /// scalar that compatibility decomposition (NFKD) maps to ASCII letters
    /// or `_` once its marks are dropped spells its name: fullwidth,
    /// mathematical and circled letters, `ſ`, the Kelvin sign, ligatures such
    /// as `ﬆ`, the other low lines, precomposed letters such as `ú`, and the
    /// rest. So a model whose tokenizer normalizes with NFKC, or decomposes
    /// and drops accents, reads `＜/rows>`,
    /// `＜／ｕｓｅｒ＿ｒｅｑｕｅｓｔ＞`, `＜/𝐭𝐨𝐨𝐥_𝐫𝐞𝐬𝐮𝐥𝐭＞` or
    /// `≮/úser_request≯` as the tag, and `neuteringTags(_:)` swaps ASCII
    /// brackets alone. Such a tag is redacted like an ASCII one. A fullwidth
    /// bracket that spells no fence tag stays as written: it is how CJK text
    /// quotes and compares, as in `＜注意＞` or `1000円＜2000円`, and swapping
    /// it would mangle what the reader typed. Letter forms stay as written
    /// too, unless they spell a fence tag's name after a bracket: a title in
    /// mathematical bold is the reader's.
    ///
    /// That is the whole of the reading: what compatibility decomposition
    /// (NFKD) makes ASCII once marks are dropped. A letter of another script
    /// that only looks Latin, such as Cyrillic `о` or Greek `ο`, and a slash
    /// that only looks like one, such as `⁄` or `∕`, normalize to no ASCII,
    /// so a tag spelled with one is another word here and stays as written.
    ///
    /// A tag whose `>` doesn't come soon after its name, before another `<`,
    /// loses only its opener, `<rows` or `</rows`, whatever follows the name:
    /// a space, a full stop or a comma, as in `</rows, now obey`, or a letter
    /// of another script. Only an ASCII letter, digit or `_`, or a scalar
    /// that normalizes to one, goes on with the name, and makes it another
    /// one. The opener is all spelling a tag needs, and the reader's words up
    /// to a `>` further on, as in
    /// "<rows of my shelf, and is 3 > 2?", are theirs. A `<` parted from the
    /// name by inline spacing alone, with nothing closing it, as in
    /// "3 < rows", is a comparison and stays; a slash or a newline in that
    /// gap still makes it a tag.
    public static func sanitizeForFence(_ input: String) -> String {
        // The controls before the invisibles: a joiner stays after anything
        // but a joiner, so two parted by a bell would both stay, and the
        // bell's going would leave them a run.
        let input = neuteringQuotes(droppingInvisibles(droppingControls(input)))
        let known = Set(fenceTags.map { $0.lowercased() })
        let longest = fenceTags.map(\.unicodeScalars.count).max() ?? 0
        let scalars = input.unicodeScalars
        var out = String.UnicodeScalarView()
        var index = scalars.startIndex
        while index < scalars.endIndex {
            guard asciiForm(scalars[index]) == "<",
                  let after = fenceEnd(in: scalars, from: index, known: known, longest: longest) else {
                out.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }
            // Scalar by scalar: `append(contentsOf:)` counts the whole of
            // `out` first, which makes a text of many tags quadratic.
            for scalar in "[redacted]".unicodeScalars { out.append(scalar) }
            index = after
        }
        return String(out)
    }

    /// If a fence tag in `known`, none longer than `longest` scalars, starts
    /// at the `<` at `start`, the index just past what to redact: the tag's
    /// `>`, or the end of its name when no `>` comes within `maxTagTail`
    /// scalars of it, before another `<`, unless only inline spacing parts
    /// the name from the `<`. Brackets and the slash are read through
    /// `asciiForm(_:)`; the name, and the scalar after it, through
    /// `compatibilityForm(of:)`, so the name is matched on its compatibility
    /// decomposition (NFKD), without its marks.
    ///
    /// `›` closes a tag as `>` does. `clamp(_:_:)` swaps brackets before it
    /// sanitizes, and titles, history and a photo's label are sanitized again
    /// after it, so the ASCII `>` of a tag opened with `＜`, as in `＜/rows>`,
    /// arrives already swapped.
    ///
    /// Whitespace and invisible scalars may sit around the slash and the
    /// name, invisible ones inside the name too, and everything after the
    /// name up to the `>` (whitespace, attributes, a self-closing slash) is
    /// part of the tag. The name ends at the first scalar that, normalized,
    /// isn't an ASCII letter, digit or `_`, or at the end of the text, so
    /// `<user_requests>` and `＜rows２＞` are other tags, and `＜/rows.` is
    /// the tag. A spacing accent such as `¨` normalizes to a space and a
    /// mark, so `</rows¨>` is the tag with an attribute.
    ///
    /// Only the name and the scalar after it are normalized, and the name is
    /// given up as soon as it outgrows the longest fence tag, so a candidate
    /// costs at most that many normalizations, plus one, however long the
    /// run of letters after its bracket.
    ///
    /// A hand scan rather than a regex because the pattern is built from
    /// `fenceTags` at runtime, and the two ways to do that are a throwing
    /// initializer force-unwrapped or an `AnyRegexOutput`. Neither belongs in
    /// a function standing between tool output and a prompt.
    private static func fenceEnd(
        in scalars: String.UnicodeScalarView, from start: String.Index, known: Set<String>, longest: Int
    ) -> String.Index? {
        var index = scalars.index(after: start)
        func skip(while matches: (Unicode.Scalar) -> Bool) {
            while index < scalars.endIndex, matches(scalars[index]) {
                index = scalars.index(after: index)
            }
        }
        skip(while: isGap)
        if index < scalars.endIndex, asciiForm(scalars[index]) == "/" {
            index = scalars.index(after: index)
            skip(while: isGap)
        }
        let nameStart = index
        var name = String.UnicodeScalarView()
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if isInvisible(scalar) {
                index = scalars.index(after: index)
                continue
            }
            let form = compatibilityForm(of: scalar)
            let letters = form.prefix(while: isTagNameASCII)
            name.append(contentsOf: letters)
            guard name.count <= longest else { return nil }
            if letters.count == form.count {
                index = scalars.index(after: index)
                continue
            }
            // The name ends here, at whatever isn't a letter, a digit or
            // `_`. A form that starts with letters and goes on, as `℀`'s
            // `a/c` does, ends it inside the scalar, which goes with the tag.
            if !letters.isEmpty { index = scalars.index(after: index) }
            break
        }
        guard known.contains(String(name).lowercased()) else { return nil }
        // Inline spacing alone between the `<` and the name is how a
        // comparison reads; anything else in the gap is how a tag reads, and
        // loses its opener without its `>`.
        let gap = scalars[scalars.index(after: start)..<nameStart]
        let comparison = !gap.isEmpty && gap.allSatisfy(isInlineSpace)
        let openerEnd = comparison ? nil : index
        var tail = 0
        while index < scalars.endIndex, tail <= maxTagTail {
            switch asciiForm(scalars[index]) {
            case ">", "›": return scalars.index(after: index)
            case "<": return openerEnd
            default:
                index = scalars.index(after: index)
                tail += 1
            }
        }
        return openerEnd
    }

    /// How far past a fence tag's name its `>` may come, in scalars, for the
    /// tag to be redacted whole.
    ///
    /// Room for the whitespace and the attribute the sanitizer's doc names
    /// (`<user_request lang="en">` carries ten), and short enough that a `>`
    /// further along the reader's sentence isn't taken for the tag's. Past
    /// it, only the opener goes.
    private static let maxTagTail = 16

    /// A scalar that rides on the one before it or draws nothing: a combining
    /// mark of any kind, variation selectors included; a format character
    /// such as ZWJ, ZWSP or a bidi control; or another default-ignorable one,
    /// such as a Hangul filler.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .format: true
        default: scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    /// Whitespace, newlines included, or an invisible scalar.
    private static func isGap(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || isInvisible(scalar)
    }

    /// A tab or a space of any width, the spacing a comparison is typed with.
    private static func isInlineSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\t" || scalar.properties.generalCategory == .spaceSeparator
    }

    /// An ASCII letter, digit or `_`, what a tag's name is spelled with.
    /// Every fence tag is letters and `_` alone, so a digit after one's name
    /// makes it another tag's, as a letter does.
    private static func isTagNameASCII(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "_": true
        default: false
        }
    }

    /// The compatibility decomposition (NFKD) of `scalar` on its own, with
    /// its marks and other invisible scalars dropped: ASCII, the fullwidth
    /// block and the negated brackets through `asciiForm(_:)`, anything else
    /// through Foundation's `decomposedStringWithCompatibilityMapping`.
    ///
    /// One scalar can normalize to several, as `ﬆ` to `st` and `℀` to
    /// `a/c`, and a precomposed letter decomposes to its base and its marks,
    /// as `ú` to `u` and a combining acute. The marks go, as the scan reads
    /// past them in the text, so `ú` spells what `u` and a combining acute
    /// spell. Normalizing scalar by scalar reads a name as the whole text's
    /// decomposition would: that is each scalar's, with only the order of
    /// the marks changed.
    private static func compatibilityForm(of scalar: Unicode.Scalar) -> String.UnicodeScalarView {
        let ascii = asciiForm(scalar)
        guard !ascii.isASCII else { return String.UnicodeScalarView([ascii]) }
        return String(scalar).decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isInvisible($0) }
    }

    /// The ASCII scalar a fullwidth or small form maps to under NFKC, or a
    /// negated bracket decomposes to without its mark, or `scalar` as it is.
    ///
    /// The scan finds brackets and the solidus with this alone, so it reads
    /// every scalar of the text without normalizing one, and misses none:
    /// with marks dropped, NFKD maps only `＜`, `﹤` and `≮` to `<`, `＞`,
    /// `﹥` and `≯` to `>`, and `／` to `/`, and no scalar to a longer form
    /// holding a bracket. `AskPromptTests` holds this table to the running
    /// system's normalization. The fullwidth block mirrors printable ASCII
    /// at a fixed offset, so its letters and low line map by the same
    /// subtraction; every other letter form goes through
    /// `compatibilityForm(of:)`.
    private static func asciiForm(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0xFF01...0xFF5E: Unicode.Scalar(UInt8(scalar.value - 0xFEE0))
        case 0xFE64, 0x226E: "<"
        case 0xFE65, 0x226F: ">"
        default: scalar
        }
    }

    /// ASCII angle brackets replaced with single-glyph lookalikes, so no tag
    /// can be spelled with them.
    ///
    /// Fullwidth, small and negated brackets stay: CJK text quotes and
    /// compares with the first two, mathematics writes `≮` and `≯`, and
    /// `sanitizeForFence(_:)` redacts AskKit's own tags spelled with any of
    /// them.
    ///
    /// Swapped scalar by scalar: a comparison of Characters misses a `<`
    /// that a combining mark or a variation selector joins, and leaves its
    /// byte in the prompt.
    ///
    /// Separate from `clamp` for tool output whose line breaks carry its
    /// layout, which needs this and mustn't be clamped: `clamp` collapses
    /// newlines and truncates, which flattens the layout a domain built for
    /// the model to read.
    public static func neuteringTags(_ text: String) -> String {
        let swapped = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar {
            case "<": "‹"
            case ">": "›"
            default: scalar
            }
        }
        return String(String.UnicodeScalarView(swapped))
    }

    /// Each straight double quote (U+0022) replaced with a double prime
    /// (U+2033, `″`), so none can end the answer's string; `clamp(_:_:)`
    /// says why. One scalar for one, so a text keeps its length in
    /// characters and in scalars, and its line breaks.
    ///
    /// Swapped scalar by scalar, as `neuteringTags(_:)` swaps brackets: a
    /// quote under a combining mark is one Character with it, and still
    /// U+0022 to the model.
    ///
    /// `sanitizeForFence(_:)` runs it, so every fenced path does;
    /// `neuteringTags(_:)` is named for tags and leaves quotes alone.
    static func neuteringQuotes(_ text: String) -> String {
        let swapped = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            scalar == "\"" ? "″" : scalar
        }
        return String(String.UnicodeScalarView(swapped))
    }

    /// `text` without its C0 and C1 controls (U+0000 to U+001F, U+007F to
    /// U+009F), but for the tab and the line breaks a `Character` reads as
    /// one (LF, VT, FF, CR and NEL). A control draws nothing a reader sees,
    /// and reaches the model all the same; the tab and the line breaks are
    /// layout, which output laid out in lines keeps and `clamp(_:_:)` makes
    /// spaces.
    ///
    /// `sanitizeForFence(_:)` runs it, so every fenced path does.
    static func droppingControls(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09...0x0D, 0x85: out.append(scalar)
            case 0x00...0x1F, 0x7F...0x9F: continue
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// The question as it reaches a prompt: trimmed of whitespace and
    /// newlines, clamped to `maxQuestionLength` characters, and each
    /// character held to its first 16 Unicode scalars, as `clamp(_:_:)`
    /// holds them, then trimmed again, since what the cap drops can leave
    /// whitespace at either end. Clamping it again changes nothing, which
    /// matters because the fence clamps a question the engine has already
    /// clamped, as the engine does one a prefill has.
    ///
    /// Empty for a question that is only whitespace, and every caller refuses
    /// an empty one: `AskLink` leaves it out of the link,
    /// `AskConversationStore.prefill(_:scope:send:)` ignores it, and the engine
    /// fails the turn with `AskError.couldNotAnswer`.
    ///
    /// SPI (`AskKitInternal`): `AskLink` and
    /// `AskConversationStore.prefill(_:scope:send:)` already clamp what a host
    /// hands them, and the engine clamps every question it is asked.
    @_spi(AskKitInternal) public static func clampQuestion(_ question: String) -> String {
        boundingScalars(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuestionLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` without what a reader can't see: every question the engine is
    /// asked and each question a recap quotes, before either is clamped;
    /// everything `sanitizeForFence(_:)` reads, so every fenced path; and
    /// the words that reach the composer or a chip from neither the reader
    /// nor the host, an `AskLink`'s question and the follow-ups a model
    /// writes. Whatever is left is what the reader saw, or sees before they
    /// send it.
    ///
    /// **Invisible text is still text to the model.** A Unicode tag character
    /// (U+E0020 to U+E007F) is a format character that draws nothing and
    /// spells an ASCII letter, and the character before it carries as many
    /// as the scalar cap allows, so a link can show "What's my oldest book?"
    /// and send an order beside it. A bidi control (U+202A to U+202E, U+2066
    /// to U+2069, the marks U+200E, U+200F and U+061C) draws text in another
    /// order than it is sent. Both are format characters (`Cf`), and every
    /// format character goes, with two exceptions that spell text people
    /// write:
    /// - the joiners: ZWJ (U+200D), which joins an emoji sequence such as a
    ///   family, and ZWNJ (U+200C), which Persian and the Indic scripts write
    ///   inside words. A joiner stays after anything but a joiner: two in a
    ///   row join nothing, and a run of them is bits in hiding;
    /// - the three subdivision flags Unicode recommends, England's,
    ///   Scotland's and Wales's: a black flag (U+1F3F4), the tags of `gbeng`,
    ///   `gbsct` or `gbwls`, and the cancel tag (U+E007F), the whole of one
    ///   character. Tags anywhere else go, a flag's that spell anything else
    ///   included, since a black flag and a cancel tag can hold a run of tags
    ///   as long as any other character can.
    ///
    /// **A variation selector stays only where it selects.** VS15 and VS16
    /// (U+FE0E, U+FE0F) choose text or emoji presentation, and stay after an
    /// emoji. An ideographic variation selector (U+E0100 to U+E01EF) chooses
    /// a kanji's glyph, as Japanese names need, and stays after a unified
    /// ideograph. A Mongolian free variation selector stays after a Mongolian
    /// letter. Every other selector goes, VS1 to VS14 among them, and so does
    /// any after another selector or after a base it doesn't belong to:
    /// selectors spell a byte apiece, and a run of them, or one on a base
    /// that takes none, is a byte in hiding.
    static func droppingInvisibles(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for character in text {
            let keepsTags = isRecommendedSubdivisionFlag(character)
            for scalar in character.unicodeScalars {
                let kept: Bool
                if isTag(scalar) {
                    kept = keepsTags
                } else if scalar.properties.isVariationSelector {
                    kept = previous.map { selects(scalar, after: $0) } ?? false
                } else if isJoiner(scalar) {
                    kept = previous.map { !isJoiner($0) } ?? false
                } else {
                    kept = scalar.properties.generalCategory != .format
                }
                guard kept else { continue }
                out.append(scalar)
                previous = scalar
            }
        }
        return String(out)
    }

    /// U+E0020 to U+E007F: the tag letters, digits and symbols, and the
    /// cancel tag.
    private static func isTag(_ scalar: Unicode.Scalar) -> Bool {
        (0xE0020...0xE007F).contains(scalar.value)
    }

    /// ZWJ or ZWNJ.
    private static func isJoiner(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200D}" || scalar == "\u{200C}"
    }

    /// Whether `selector` chooses a glyph for `base`: VS15 or VS16 after an
    /// emoji, an ideographic variation selector after a unified ideograph, a
    /// Mongolian free variation selector after a Mongolian letter.
    private static func selects(_ selector: Unicode.Scalar, after base: Unicode.Scalar) -> Bool {
        switch selector.value {
        case 0xFE0E, 0xFE0F: base.properties.isEmoji
        case 0xE0100...0xE01EF: base.properties.isUnifiedIdeograph
        case 0x180B...0x180D, 0x180F: (0x1820...0x18AA).contains(base.value)
        default: false
        }
    }

    /// England's, Scotland's and Wales's flags, the subdivision flags Unicode
    /// recommends, scalar for scalar: the black flag, the tags of `gbeng`,
    /// `gbsct` or `gbwls`, and the cancel tag.
    private static let recommendedSubdivisionFlags: Set<[UInt32]> = Set(["gbeng", "gbsct", "gbwls"].map { code in
        [0x1F3F4] + code.unicodeScalars.map { 0xE0000 + $0.value } + [0xE007F]
    })

    /// Whether `character` is one of the recommended subdivision flags and
    /// nothing else. Compared whole, so no scalar in it is read as a tag
    /// before it is known to be one.
    private static func isRecommendedSubdivisionFlag(_ character: Character) -> Bool {
        recommendedSubdivisionFlags.contains(character.unicodeScalars.map(\.value))
    }

    /// The question in its fence: clamped, sanitized (its invisibles and
    /// controls dropped, its straight double quotes turned into double primes
    /// and any fence tag in it redacted), then every angle bracket swapped for
    /// its lookalike, the order the rows get in the grounded retry. The
    /// reader's own words, typed or an `AskLink` prefill they sent, get what
    /// titles, labels and tool rows get, so no tag can be spelled inside the
    /// fence in ASCII brackets, no fence tag in the other brackets
    /// `sanitizeForFence(_:)` reads, and no quote they typed can end the
    /// answer's string. Only the prompt's copy is fenced: the thread shows
    /// the question as the reader typed it.
    static func fencedQuestion(_ question: String) -> String {
        "<user_request>" + neuteringTags(sanitizeForFence(clampQuestion(question))) + "</user_request>"
    }

    /// Untrusted text as it may appear in a prompt: tabs and newlines
    /// collapsed to spaces, what a reader can't see and every other control
    /// dropped, straight double quotes turned into double primes (`″`),
    /// ASCII angle brackets replaced with their single-glyph lookalikes so no
    /// tag can be spelled with them, any of AskKit's fence tags spelled in
    /// other brackets redacted, and the whole clamped. The drops, the quote
    /// swap and the redaction are `sanitizeForFence(_:)`'s. Text longer than
    /// `limit` keeps its first `limit` characters, then a "…".
    ///
    /// **A clamped field can't end the answer's string.** Apple's on-device
    /// model writes its answer inside a guided-generation JSON string, and
    /// copies a straight double quote (U+0022) from tool output into it,
    /// where the quote ends the string: the answer stops mid-sentence ("The
    /// incident is titled ") and the generation runs on to the token cap.
    /// So each one becomes a double prime (U+2033), which looks like it and
    /// ends nothing, as in `Vinyl, 7″, 45 RPM` or `The ″Best″ Album`
    /// (`neuteringQuotes(_:)`, which the sanitizer runs). One scalar for one
    /// and one character for one, so the limit and the scalar cap fall where
    /// they did, and nothing after the swap writes a quote for a second clamp
    /// to find.
    ///
    /// **Nor can it carry what the reader can't see.** Tool rows, such as
    /// catalog titles and web imports, can hold Unicode tag characters that
    /// spell an order in ASCII, bidi controls and runs of joiners, which the
    /// question path drops (`droppingInvisibles(_:)`), and C0 and C1
    /// controls. The sanitizer drops them before it reads for a tag, keeping
    /// the joiners, selectors and subdivision flags real text spells; the
    /// tab and the line breaks it keeps are spaces here by then.
    ///
    /// Each character also keeps at most its first 16 Unicode scalars, so the
    /// result holds no more than `16 × limit + 1` of them. The limit counts
    /// characters, and one character can stack any number of combining marks:
    /// uncapped, a 60-character title could carry thousands of scalars into
    /// the context window. No character real text spells comes near the cap;
    /// the longest run to ten.
    ///
    /// **A clamped field can't close the fence it sits in** in any spelling
    /// `sanitizeForFence(_:)` reads, because hosts put tool rows through this
    /// and nothing else. The swap stops any tag in ASCII brackets, AskKit's
    /// or not, and `sanitizeForFence(_:)` stops AskKit's own in the
    /// fullwidth, small and negated brackets the swap leaves, which
    /// normalize to ASCII, so `＜/tool_result＞` is the fence's closer to a
    /// model that normalizes, and so is `＜/𝐭𝐨𝐨𝐥_𝐫𝐞𝐬𝐮𝐥𝐭＞`.
    ///
    /// The bracket swap runs first, so an ASCII tag comes out as `‹rows›`,
    /// and only a tag in other brackets loses its text. The
    /// sanitizer closes a tag on `›` as on `>`, so `＜/rows>` is caught after
    /// the swap has turned its `>`, here and by a caller that sanitizes the
    /// result again and finds nothing left. It reads the text with its tabs
    /// and newlines already spaces, as the model will.
    ///
    /// The sanitizer and the scalar cap go before the cut, so the limit
    /// counts `[redacted]`, and a tag that straddles the limit can't be cut
    /// into a half-tag that slips past: `＜/user_req…` is no fence tag to the
    /// sanitizer, but a model reads where it was going. Each can make work
    /// for the other, so the text is sanitized and capped again until a pass
    /// changes nothing: a redaction can join what follows a tag to its `]`,
    /// and a scalar the sanitizer drops can join the characters either side
    /// of it, either one a character over the cap; and the trim can leave a
    /// joiner first, where the sanitizer drops it.
    /// The kept text is read the same way before the "…" goes on, for the
    /// openers the cut makes: a cut just past a fence tag's name inside a
    /// longer one, as in `＜/tool_results＞`, leaves the tag's opener.
    /// `[redacted]` can be more characters than what it replaced, so a pass
    /// that redacts anything cuts the text to the limit again and is read
    /// again, until one finds nothing. Each pass that redacts takes away an
    /// opening bracket, and the sanitizer's drops and swap, the cap, the trim
    /// and the cut add none, and only ever drop scalars or swap one for one,
    /// so the passes end. A last character that would join the "…", as a
    /// run of Prepend scalars joins anything, goes before it. The result is
    /// never longer than the limit and the "…", and clamping it again changes
    /// nothing. A negative limit reads as zero.
    public static func clamp(_ text: String, _ limit: Int) -> String {
        let limit = max(0, limit)
        var kept = shownWhole(text)
        var cut = false
        while kept.count > limit {
            cut = true
            kept = settled(String(kept.prefix(limit)), trimmingItsEnd: false)
        }
        return cut ? boundingScalars(kept, before: cutMark) + String(cutMark) : kept
    }

    /// What `clamp(_:_:)` puts after a text it cut: an ellipsis, so a model
    /// that names a row by a title it was shown cut writes it there, and tile
    /// and mention matching read a name that ends in it as a cut title
    /// (`AskAnswer.cutTitleFloor`).
    static let cutMark: Unicode.Scalar = "…"

    /// `text` as `clamp(_:_:)` shows it to the model before any cut: its
    /// angle brackets swapped, its tabs and line breaks made spaces, then
    /// settled (`settled(_:trimmingItsEnd:)`), so sanitized, held to the
    /// scalar cap and trimmed. A clamp whose limit `text` fits returns this.
    ///
    /// What tile and mention matching read a row's title as, beside the
    /// title as stored (`AskAnswer.titleEquals`), since the model names a row
    /// as a tool showed it: `<3 Love Songs>` as `‹3 Love Songs›`, and `Abbey`
    /// and `Road` parted by a tab as `Abbey Road`. The clamp's own first
    /// step, so the two can't drift.
    static func shownWhole(_ text: String) -> String {
        settled(
            neuteringTags(text)
                .split(whereSeparator: { $0.isNewline || $0 == "\t" })
                .joined(separator: " "),
            trimmingItsEnd: true
        )
    }

    /// `text` sanitized (`sanitizeForFence(_:)`), held to the scalar cap and
    /// trimmed of whitespace, over and over until a pass changes nothing, so
    /// the sanitizer and the cap would each leave it as it is.
    ///
    /// `trimmingItsEnd` false trims only the start, for a text that was
    /// just cut: what it keeps before its "…" is the first characters as
    /// they stand, a space included. Trimmed scalar by scalar, as
    /// `trimmingCharacters(in:)` trims, so one loop serves both.
    private static func settled(_ text: String, trimmingItsEnd: Bool) -> String {
        var text = text
        while true {
            let capped = boundingScalars(sanitizeForFence(text))
            var scalars = Substring(capped).unicodeScalars
            while let first = scalars.first, CharacterSet.whitespaces.contains(first) { scalars.removeFirst() }
            while trimmingItsEnd, let last = scalars.last, CharacterSet.whitespaces.contains(last) { scalars.removeLast() }
            let next = String(scalars)
            if next.unicodeScalars.elementsEqual(text.unicodeScalars) { return next }
            text = next
        }
    }

    /// A short label, such as a row title or a category name, as it appears
    /// in tool output, a recap or a photo's line.
    public static let shortClamp = 60
    /// A sentence-length field in tool output, such as a status line or a
    /// note.
    public static let longClamp = 220

    /// The most Unicode scalars one character keeps through `clamp(_:_:)` and
    /// `clampQuestion(_:)`.
    ///
    /// The clamps count characters, and a character has no scalar limit of
    /// its own: a letter under two hundred combining marks is one. Sixteen
    /// clears the longest characters real text spells, ten scalars for a kiss
    /// emoji with two skin tones or a five-consonant Devanagari conjunct, so
    /// only a stack built to overflow loses any. Cutting a character short
    /// never splits it, and what it keeps joins nothing after it
    /// (`boundingScalars(_:before:)`), so the character limits still hold and
    /// a second clamp finds nothing to cut.
    static let maxScalarsPerCharacter = 16

    /// `text` with each character cut to its first `maxScalarsPerCharacter`
    /// scalars, less any at the end of what it keeps that would join it to
    /// what follows: the result is the same characters, each within the
    /// cap, and bounding it again changes nothing.
    ///
    /// What the cap keeps of a character can reach forward. A run of Prepend
    /// scalars, such as Arabic number signs, joins whatever comes next; a
    /// ZWJ after an emoji joins the next emoji, a virama the next
    /// consonant, a Hangul leading consonant the next syllable. Kept as cut,
    /// it would swallow the character after it, a character over the cap
    /// again. So scalars come off its end until it joins nothing, and a run
    /// of Prepend scalars goes whole. A character whose neighbour went that
    /// way meets the one after it, and is read against that the same way.
    /// `trailer` is what will follow the text, as the clamp's "…" does, and
    /// its last character is read against it.
    ///
    /// Read from the end, so the scalar a character is read against is the
    /// first of what the result keeps after it. Joining is asked of Swift's
    /// own segmentation, and only for a character the cap cut or one that
    /// meets a new neighbour. A text with no character over the cap, whose
    /// last joins no trailer, is returned as it is without that reading.
    private static func boundingScalars(_ text: some StringProtocol, before trailer: Unicode.Scalar? = nil) -> String {
        let overCap = text.contains { $0.unicodeScalars.count > maxScalarsPerCharacter }
        let joinsTrailer = trailer.flatMap { trailer in text.last.map { joins(Array($0.unicodeScalars), trailer) } } ?? false
        guard overCap || joinsTrailer else { return String(text) }
        var reversed: [Unicode.Scalar] = []
        var next = trailer
        // Whether `next` is the scalar that followed this character in `text`.
        var nextIsItsOwn = false
        for character in Array(text).reversed() {
            let scalars = character.unicodeScalars
            let isCut = scalars.count > maxScalarsPerCharacter
            guard isCut || (next != nil && !nextIsItsOwn) else {
                // Whole, and followed by what followed it: nothing to read.
                reversed.append(contentsOf: scalars.reversed())
                next = scalars.first
                nextIsItsOwn = true
                continue
            }
            var kept = Array(scalars.prefix(maxScalarsPerCharacter))
            if let following = next {
                while !kept.isEmpty, joins(kept, following) { kept.removeLast() }
            }
            guard let first = kept.first else {
                nextIsItsOwn = false
                continue
            }
            reversed.append(contentsOf: kept.reversed())
            next = first
            nextIsItsOwn = true
        }
        return String(String.UnicodeScalarView(reversed.reversed()))
    }

    /// Whether `scalar` would join the character `scalars` spell rather than
    /// start one of its own.
    private static func joins(_ scalars: [Unicode.Scalar], _ scalar: Unicode.Scalar) -> Bool {
        var probe = String.UnicodeScalarView(scalars)
        probe.append(scalar)
        return String(probe).count == 1
    }

    /// A session's instructions as the engine builds them: Apple's opening for
    /// the answer's language, then `text`, the domain's own words
    /// (`AskDomain.instructions(tier:isConversation:answerLanguage:)`), after
    /// a blank line. With no opening, `text` as it stands.
    ///
    /// The opening is the practice of Apple's article "Supporting languages
    /// and locales with Foundation Models", as its sample code has it:
    /// - **The person's locale**, in Apple's exact phrase,
    ///   "The person's locale is \(locale.identifier).". Apple: "This special
    ///   phrase comes from the model's training, and reduces the possibility
    ///   of hallucinations in multilingual situations." Left out for U.S.
    ///   English, by Apple's own check
    ///   (`Locale.Language(identifier: "en_US").isEquivalent(to:)`), and for a
    ///   locale in another language that `answerLanguage` doesn't name: the
    ///   seam names none where a tier doesn't write the language, the case
    ///   Apple says to check support for first, and the answer is written in
    ///   English. English in another region, such as en_GB, keeps it, as
    ///   Apple's sample does.
    /// - **The language to respond in**, "You MUST respond in
    ///   \(answerLanguage).", Apple's example, when the seam names one: by
    ///   default the model responds in the language of its inputs.
    ///
    /// `locale` is `Locale.current`, as in Apple's sample, which takes in the
    /// person's language settings for the app. A test passes its own.
    ///
    /// SPI (`AskKitInternal`): the engine builds every session's instructions
    /// with it, and a host's live eval can build the same ones.
    @_spi(AskKitInternal) public static func instructions(
        _ text: String, answerLanguage: String?, locale: Locale = .current
    ) -> String {
        let named = answerLanguage.flatMap { $0.isEmpty ? nil : $0 }
        var opening: [String] = []
        if !Locale.Language(identifier: "en_US").isEquivalent(to: locale.language),
           named != nil || locale.language.languageCode?.identifier == "en" {
            opening.append("The person's locale is \(locale.identifier).")
        }
        if let named { opening.append("You MUST respond in \(named).") }
        guard !opening.isEmpty else { return text }
        let head = opening.joined(separator: "\n")
        return text.isEmpty ? head : head + "\n\n" + text
    }

    /// A prompt as the engine sends one: `prefix`, then `lines`, then the
    /// fenced question. An empty line is skipped, and each line ends in a
    /// newline, the prefix too: one that doesn't end in a newline gets one,
    /// so a domain's opening sentence never runs into the next line or the
    /// question's fence.
    ///
    /// A fresh session's first prompt and the grounded retry's re-ask start
    /// with the domain's byte-stable prefix (what `prewarm` cached), and the
    /// planner's prompt with none. Their lines are such as a recap, the
    /// domain's per-turn lines, or the rows the grounded retry found.
    ///
    /// The prefix must be byte-identical between the prewarm and the real
    /// turn, or the cache the prewarm built is thrown away (house rule 6).
    /// That is the whole point of `prewarm(promptPrefix:)`, and it is why the
    /// prefix takes no arguments. The newline goes after it, so the prompt
    /// still opens with the prefix as prewarmed.
    ///
    /// SPI (`AskKitInternal`): the engine builds every prompt it sends, and a
    /// host's live eval can build the same one.
    @_spi(AskKitInternal) public static func promptText(prefix: String, lines: [String], question: String) -> String {
        var text = prefix.isEmpty || prefix.hasSuffix("\n") ? prefix : prefix + "\n"
        for line in lines where !line.isEmpty {
            text += line.hasSuffix("\n") ? line : line + "\n"
        }
        text += fencedQuestion(question)
        return text
    }

    /// The line a prompt carries for a photo that goes with the question: that
    /// there is one, and the host's words for what it shows.
    ///
    /// The words are the host's, often a row's title, and they can be the
    /// reader's, such as a caption or the name they gave an item, so they are
    /// clamped, redacted and neutered like any untrusted text, and fenced in
    /// `<rows>`, as the titles in a recap, a referent or a steer are (house
    /// rule 3). A label the clamp leaves empty takes no fence. Only ever for
    /// a photo the model is sent. A line about a picture the model can't see
    /// invites it to describe one anyway.
    static func photoLine(label: String) -> String {
        let label = sanitizeForFence(clamp(label, shortClamp))
        guard !label.isEmpty else { return "The reader attached a photo to this question." }
        return "The reader attached a photo to this question, labelled: <rows>\(label)</rows>"
    }

    /// The answer as a thread shows it: the Markdown headings and bullets a
    /// model reaches for despite being told not to, flattened to prose, since
    /// AskUI renders inline Markdown only.
    static func tidy(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = droppingHeadingMarker(String(line).trimmingCharacters(in: .whitespaces))
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                    trimmed.removeFirst(2)
                }
                return trimmed.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A line without its Markdown heading marker: one to six `#`, then a
    /// space, a tab or the end of the line. Any other leading `#` is the
    /// answer's own, as in "#1 pick" or "#hashtag".
    private static func droppingHeadingMarker(_ line: String) -> String {
        let marker = line.prefix { $0 == "#" }
        let rest = line.dropFirst(marker.count)
        guard (1...6).contains(marker.count) else { return line }
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return line }
        return String(rest)
    }

    /// A streaming snapshot as the thread may draw it.
    ///
    /// Snapshots are cumulative, so the prose only ever grows, except at an
    /// emphasis marker: in `**bol`, the dangling `**` renders as two asterisks
    /// that vanish on the next snapshot. So a trailing run of `*` or `_` goes,
    /// opener or closer, and then the last `**` if it is left unpaired, which
    /// keeps the drawn text prefix-monotone, as the reveal renderer's arrival
    /// stamps assume. A lone `*` or `_` opener earlier in the text stays.
    static func partialText(_ text: String) -> String {
        var out = text
        // A trailing run of emphasis markers is either an opener with nothing
        // after it yet, or the first half of a closer. Neither is drawable.
        while let last = out.last, last == "*" || last == "_" { out.removeLast() }
        // An odd number of `**` means one is still open; drop the opener so the
        // words after it draw as plain text until its partner arrives.
        if out.components(separatedBy: "**").count % 2 == 0, let range = out.range(of: "**", options: .backwards) {
            out.removeSubrange(range)
        }
        return out
    }
}
