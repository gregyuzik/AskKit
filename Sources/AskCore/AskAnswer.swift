import Foundation

/// One answer: the prose, the rows behind it, the rows to show, what kind of
/// question it was, and what grounded it.
///
/// `matches` are the rows behind the answer, and `tiles` the ones the model
/// chose to stand under it: every match for a which or what question, the
/// pick for a recommendation, nothing for a count.
nonisolated public struct AskAnswer<Row: AskRow>: Sendable, Equatable, Codable {
    /// The answer's prose. A model's finished answer is tidied, with headings
    /// and bullets flattened to prose; a truncated one's is as far as the
    /// stream got.
    public let text: String
    /// The rows behind the answer, each once, in the order they were read:
    /// the rows this turn's tools read, or, for a follow-up that read none,
    /// every row read on this session, up to `AskCollector.maxThreadRows`
    /// (`AskCollector.groundingRows`). A turn the reader stopped keeps the
    /// rows it had read by then.
    public let matches: [Row]
    /// The rows shown as tiles. For a model's answer: the ones the model
    /// named, in its order; every match this turn read, in reading order,
    /// when it said the answer is all of them; or, when none of its names
    /// resolve to a row, the rows the prose names. Empty for a count, a total
    /// or a yes-or-no. A truncated answer keeps the model's choice only when
    /// the deadline cut it once its follow-ups had begun, and a stopped one
    /// keeps none. A deterministic answer's, and a refine pass's, are the
    /// domain's. Whoever chose them, the engine hands out at most `maxTiles`.
    public let tiles: [Row]
    /// Up to two questions offered as the next thing to ask, cleaned to plain
    /// text (`cleanedFollowUps(_:)`), except a deterministic answer's, which
    /// are the domain's with only their duplicates dropped. Empty for a
    /// truncated answer.
    public let followUps: [String]
    /// What kind of question this was, normalized to the domain's vocabulary
    /// (`AskDomain.questionKinds`), or nil when there is none, as for a
    /// truncated answer. It decides "no tiles for a count"
    /// (`AskQuestionKind.showNoTiles`): a list of English cues would decide
    /// nothing in the other 24 languages (house rule 7).
    public let questionKind: String?
    /// The answer ended part-way: the turn's deadline cut the stream, or the
    /// reader stopped a turn that had already written something
    /// (`AskThreadEntry.stopped` tells the two apart). `text` is as far as it
    /// got, kept by the rule a finished answer is kept by: grounded, unless
    /// the domain's policy keeps answers nothing grounded
    /// (`AskGroundingPolicy.notRequired`). The model chooses its tiles after
    /// its prose and writes its follow-ups after them, so a deadline that cut
    /// it once the follow-ups had begun keeps the finished tile list, with its
    /// basis line; cut sooner, or stopped by the reader, it has no tiles.
    public let isTruncated: Bool
    /// The domain's factual sentence about why the answer chose what it shows
    /// (`AskDomain.basis(for:)`), never sentiment, never a percentage. Asked
    /// only of an answer that shows tiles and isn't a count, a total or a
    /// yes-or-no; nil for no line.
    public let basis: String?
    /// What a tool also knew about this turn: the data a card under the
    /// answer draws from, recorded through `AskCollector.record(payload:)` and
    /// read back with `payload(as:)`. Persisted with the thread.
    public let payload: Data?
    /// What the answer offers to do, which happens only if the reader confirms
    /// it on the card under the answer. Recorded by a tool through
    /// `AskCollector.record(proposal:)`. Persisted with the thread.
    public let proposal: AskProposal?
    /// What grounded the answer, as the turn's stats log it: a tool call, the
    /// app's search, the thread's rows on a follow-up, or nothing
    /// (`AskGrounding.nothing`), which the engine writes only under a policy
    /// that keeps such answers (`AskGroundingPolicy.notRequired`). The engine
    /// writes it on every answer a model wrote, a truncated one included.
    ///
    /// Nil when nobody judged it: a turn the reader stopped, which the store
    /// keeps from the prose on screen, and one read from a thread written
    /// before answers recorded it. An answer the domain gave without a model
    /// (`AskDomain.deterministicAnswer(for:)`) carries what the domain set,
    /// usually nil; the engine passes it on as it is, so one that sets it is
    /// attributed as a model's answer with that grounding would be. A refine
    /// pass's answer that leaves it nil keeps the first answer's. Persisted
    /// with the thread.
    public let grounding: AskGrounding?

    /// An answer with each field as given. The engine builds one per turn; a
    /// domain builds one for a deterministic answer
    /// (`AskDomain.deterministicAnswer(for:)`) or a refine pass.
    public init(
        text: String,
        matches: [Row] = [],
        tiles: [Row] = [],
        followUps: [String] = [],
        questionKind: String? = nil,
        isTruncated: Bool = false,
        basis: String? = nil,
        payload: Data? = nil,
        proposal: AskProposal? = nil,
        grounding: AskGrounding? = nil
    ) {
        self.text = text
        self.matches = matches
        self.tiles = tiles
        self.followUps = followUps
        self.questionKind = questionKind
        self.isTruncated = isTruncated
        self.basis = basis
        self.payload = payload
        self.proposal = proposal
        self.grounding = grounding
    }

    /// Hand-written so a thread saved before a field existed still decodes.
    ///
    /// The synthesized initializer throws on a missing key, and a throw here
    /// drops the whole entry the answer belongs to (`AskThreadStore.load()`
    /// counts it): every reader would lose that turn on the first launch
    /// after an update. Every field added here after the first release must
    /// be `decodeIfPresent`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        matches = Self.salvagedRows(in: container, forKey: .matches)
        tiles = Self.salvagedRows(in: container, forKey: .tiles)
        followUps = try container.decodeIfPresent([String].self, forKey: .followUps) ?? []
        questionKind = try container.decodeIfPresent(String.self, forKey: .questionKind)
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        basis = try container.decodeIfPresent(String.self, forKey: .basis)
        payload = try container.decodeIfPresent(Data.self, forKey: .payload)
        // `try?`, not `try`: a proposal a newer build wrote costs the card,
        // never the answer.
        proposal = try? container.decodeIfPresent(AskProposal.self, forKey: .proposal)
        // `try?` for the same reason: a grounding a newer build named costs
        // the record of it, never the answer.
        grounding = try? container.decodeIfPresent(AskGrounding.self, forKey: .grounding)
    }

    /// A list of rows decoded one row at a time, keeping those that still
    /// decode: a host that adds a field to its row type makes every row saved
    /// before it fail, and one such row costs the answer that row, never the
    /// turn. A list that is missing, null or not a list at all is no rows.
    private static func salvagedRows<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>, forKey key: Key
    ) -> [Row] {
        guard var list = try? container.nestedUnkeyedContainer(forKey: key) else { return [] }
        var rows: [Row] = []
        while !list.isAtEnd {
            if let row = try? list.decode(Row.self) {
                rows.append(row)
            } else if (try? list.decode(AskSkippedRow.self)) == nil {
                // A failed decode leaves the list where it was, which is why
                // the skip exists; one that can't even skip would spin here.
                break
            }
        }
        return rows
    }

    // MARK: - Payload, basis, proposal and grounding

    /// The payload as the domain's own type, or nil when there is none or it
    /// no longer decodes. A card that can't be drawn is left out; it is never
    /// a failed answer.
    public func payload<Value: Decodable>(as type: Value.Type) -> Value? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(type, from: payload)
    }

    /// This answer with a different basis line.
    public func replacing(basis newBasis: String?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: newBasis, payload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with a different payload.
    public func replacing(payload newPayload: Data?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, payload: newPayload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with a different proposal.
    public func replacing(proposal newProposal: AskProposal?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, payload: payload,
            proposal: newProposal, grounding: grounding
        )
    }

    /// This answer with a different record of what grounded it: a refine
    /// pass's, to say its own answer rests on something else.
    public func replacing(grounding newGrounding: AskGrounding?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, payload: payload,
            proposal: proposal, grounding: newGrounding
        )
    }

    /// This answer with different follow-ups: the engine's, once it has
    /// cleaned a refine pass's.
    func replacing(followUps newFollowUps: [String]) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: newFollowUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, payload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with different tiles.
    func replacing(tiles newTiles: [Row]) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: newTiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, payload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with no more than `maxTiles` tiles, the first ones kept:
    /// what the engine hands out for every answer, the domain's own included,
    /// since AskUI lays a bank out whole on the strength of that bound.
    func cappingTiles() -> AskAnswer<Row> {
        tiles.count > Self.maxTiles ? replacing(tiles: Array(tiles.prefix(Self.maxTiles))) : self
    }

    // MARK: - Follow-ups

    /// Two chips at most, as `AskReply.followUps`' guide asks for.
    public static var maxFollowUps: Int { 2 }
    /// Longer than this is not a question, it is an answer.
    public static var maxFollowUpLength: Int { 80 }

    /// The follow-ups as the thread may show them: plain text, trimmed, one
    /// line, with a word in it, short enough to be a question, de-duplicated,
    /// and capped at two.
    ///
    /// **Plain text, because a chip draws its text as it is and a tap asks
    /// it.** The model carries the bold the answer guide asks of the prose into
    /// its follow-ups, and a chip would show the asterisks and send them back.
    /// So each loses a leading heading or list marker as the prose does, then
    /// its inline Markdown, read as the screen reads the prose's: emphasis
    /// and code lose their
    /// marks and a link keeps only its label, while `snake_case` and `5 * 3`,
    /// which aren't Markdown, stay. The length, the line, the word and the
    /// duplicates are judged on the plain text, so `**Dune**?` and `Dune?` are
    /// one chip, and markup alone (`****`) is none.
    ///
    /// They are model output that becomes a prompt when tapped, so they go back
    /// in through `ask` and are fenced by `AskPrompt` like any other question.
    /// This is the length-and-shape guard, not the injection one, but a chip
    /// sends what the reader saw on it: what draws nothing goes, as from an
    /// `AskLink`'s question (tag characters, the other invisible format
    /// characters and bidi controls, keeping the joiners and variation
    /// selectors where text puts them, and the recommended subdivision
    /// flags), from the text as written and again from the plain text, since
    /// an entity such as `&#x202E;` reads as the invisible it names.
    ///
    /// The engine cleans every model answer's follow-ups, a domain's `refine`
    /// pass's included. A deterministic answer's are the domain's, and lose
    /// only their duplicates. A domain that builds an
    /// answer from model output of its own, as a `refine` pass does, cleans
    /// the follow-ups the engine's way with this: to tell whether a revision's
    /// survive before it chooses between them and the first answer's.
    public static func cleanedFollowUps(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var picked: [String] = []
        for candidate in raw {
            // Made visible before the Markdown is read, so a marker behind
            // an invisible still reads as one, and again after: the parse
            // turns an entity into the character it names, and `&#x202E;`
            // names an invisible one.
            let plain = AskPrompt.droppingInvisibles(
                AskMarkdown.plainText(AskPrompt.tidy(AskPrompt.droppingInvisibles(candidate)))
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Without a letter or a digit it asks nothing: what is left of a
            // chip that was only markup, or only punctuation.
            guard plain.contains(where: { $0.isLetter || $0.isNumber }),
                  plain.count <= maxFollowUpLength else { continue }
            // A chip is one line: anything with a newline in it is the model
            // writing a paragraph into a field meant for a question.
            guard !plain.contains(where: \.isNewline) else { continue }
            guard seen.insert(plain.lowercased()).inserted else { continue }
            picked.append(plain)
            if picked.count == maxFollowUps { break }
        }
        return picked
    }

    /// A domain's own follow-ups, as given but for the empty and the
    /// repeated: a chip's text is its id in the chip row, so two the same
    /// would collide there. Compared trimmed and blind to case, as
    /// `cleanedFollowUps(_:)` compares its plain text. Nothing else is cut or
    /// made plain: the domain wrote these, not a model.
    static func dedupedFollowUps(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    // MARK: - Tiles

    /// The most tiles an answer shows. With the model asking for every match,
    /// a turn that read Private Cloud Compute's default 40 rows
    /// (`AskDomain.rowLimit(for:)`) would otherwise put a wall of tiles under
    /// a one-line answer. The engine cuts every answer's tiles to it, a
    /// deterministic answer's and a refine pass's included.
    public static var maxTiles: Int { 24 }

    /// A title shorter than this is only a mention as a whole word: "It" is
    /// inside "with", "Go" inside "Gloomhaven". Longer titles are unlikely
    /// enough inside other words that a plain substring is the better trade:
    /// the answer may inflect them, or make them possessive.
    ///
    /// A word ends where the next letter belongs to a script that sets words
    /// apart with spaces. Chinese, Japanese, Thai, Lao, Khmer and Burmese
    /// write the next word straight on, and Korean, which spaces its words,
    /// writes a particle straight onto one ("토지를"), so beside a letter of
    /// any of them a short title is a word, and 三体 is named in "三体是…" as
    /// "Go" is in "play Go tonight".
    public static var wholeWordBelow: Int { 4 }

    /// The rows in `matches` whose title the prose names, in the order it
    /// names them.
    public var mentioned: [Row] {
        Self.mentioned(in: text, among: matches)
    }

    static func mentioned(in text: String, among rows: [Row]) -> [Row] {
        // The prose's punctuation is made plain once, not once per row. The
        // engine asks this of every streamed snapshot of a follow-up until one
        // names a row, against up to `AskCollector.maxThreadRows` rows, so once
        // per row would rework the whole answer two hundred times a snapshot.
        let haystack = plainPunctuation(text)
        let named = rows.compactMap { row -> (row: Row, needle: String, at: Range<String.Index>)? in
            let needle = Self.needle(for: row.displayTitle)
            var places = mentions(of: needle, inPlain: haystack).makeIterator()
            guard let first = places.next() else { return nil }
            return (row, needle, first)
        }
        // A title inside a longer one the prose names is that one's mention:
        // "Aliens" does not also name Alien, nor "Dune Messiah" Dune. The
        // shorter title counts only where the prose names it outside every
        // longer title it names. Only the rows already named are compared, so
        // the cost is the few titles an answer names, never every row read.
        let kept = named.compactMap { entry -> (row: Row, at: String.Index)? in
            let longer = named.filter {
                $0.needle.count > entry.needle.count
                    && $0.needle.range(
                        of: entry.needle, options: [.caseInsensitive, .diacriticInsensitive], locale: .current
                    ) != nil
            }
            guard !longer.isEmpty else { return (entry.row, entry.at.lowerBound) }
            let theirs = longer.flatMap { mentions(of: $0.needle, inPlain: haystack) }
            let own = mentions(of: entry.needle, inPlain: haystack).first { place in
                !theirs.contains { $0.lowerBound <= place.lowerBound && place.upperBound <= $0.upperBound }
            }
            return own.map { (entry.row, $0.lowerBound) }
        }
        return kept.sorted { $0.at < $1.at }.map(\.row)
    }

    /// The tiles a turn shows, from what the model returned.
    ///
    /// When the model said the answer *is* the set it found
    /// (`showsEveryMatch`), every row the turn read, in reading order, up to
    /// `maxTiles`: a which, what or do-I-have question answered with pictures,
    /// and a decision a small model gets right where a list of nine exact
    /// titles is one it shortens. Otherwise the rows its `names` resolve to, in
    /// its order, or, when none of them resolve but its prose names rows,
    /// those rows.
    ///
    /// **Never every row read, by default.** The rows a turn read are its
    /// grounding, not its answer, and an answer that chose to show nothing
    /// shows nothing.
    ///
    /// This turn's rows are `turnMatches`, or `matches` when that is empty,
    /// and they are what `showsEveryMatch` and the prose draw on. Resolution
    /// walks them first and `matches` second, so given earlier turns' rows as
    /// `matches`, a follow-up can show a row an earlier turn read without the
    /// whole thread's history standing under every answer. The engine passes
    /// the rows its session has read (`AskCollector.rows`) as `matches` and
    /// this turn's (`AskCollector.turnRows`) as `turnMatches`.
    ///
    /// A turn that read nothing, such as a follow-up answered from the
    /// thread, found no set to show whole: the engine passes it
    /// `showsEveryMatch` false whatever the model said, so its tiles are the
    /// titles it named, else the rows its prose names, and never every row
    /// the thread has read.
    ///
    /// Public for a domain's refine pass (`AskDomain.refine`), which builds its
    /// own answer from what the model returned and resolves its tiles the way
    /// the engine resolves the first pass's.
    ///
    /// - Parameters:
    ///   - names: The titles the model chose, in its order.
    ///   - showsEveryMatch: Whether the model said the answer is the whole set
    ///     the turn found.
    ///   - text: The answer's prose, whose mentions stand in when no title
    ///     resolves.
    ///   - matches: The rows to resolve against after this turn's own.
    ///   - turnMatches: This turn's rows, or none to read `matches` as them.
    /// - Returns: At most `maxTiles` rows, each one a row given here.
    public static func tiles(
        named names: [String],
        showsEveryMatch: Bool = false,
        text: String,
        matches: [Row],
        turnMatches: [Row] = []
    ) -> [Row] {
        let turn = turnMatches.isEmpty ? matches : turnMatches
        if showsEveryMatch, !turn.isEmpty { return Array(turn.prefix(maxTiles)) }
        let resolved = resolve(names, in: turn, then: matches)
        guard resolved.isEmpty else { return Array(resolved.prefix(maxTiles)) }
        return Array(mentioned(in: text, among: turn).prefix(maxTiles))
    }

    /// Resolve the model's tile titles to rows: an exact title first, in
    /// `turn` and then in `thread`, and only then a near one, in the same
    /// order. A near match is for a model that paraphrased; when the title it
    /// wrote is a row, that row is the one it meant, so "Aliens" is never
    /// Alien for having been read first, nor "Dune" Dune Messiah. A title that
    /// resolves to nothing is dropped: a tile must be a row the thread
    /// actually read.
    ///
    /// **The nearest near match, not the first.** Of the rows a paraphrase
    /// matches, the one sharing the most of it wins: the length of whichever
    /// of the two titles sits inside the other, and reading order only between
    /// equals. So "Blue Oxford" is Blue Oxford Shirt, which holds all of it,
    /// and not Blue, read first, which holds four letters of it.
    static func resolve(_ names: [String], in turn: [Row], then thread: [Row]) -> [Row] {
        var picked: [Row] = []
        var seen = Set<Row.ID>()
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            func firstExact(in rows: [Row]) -> Row? {
                rows.first { !seen.contains($0.id) && titleEquals($0.displayTitle, name: name) }
            }
            func nearest(in rows: [Row]) -> Row? {
                var best: (row: Row, overlap: Int)?
                for row in rows where !seen.contains(row.id) && titleMatches(row.displayTitle, name: name) {
                    let overlap = min(row.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).count, name.count)
                    if overlap > (best?.overlap ?? 0) { best = (row, overlap) }
                }
                return best?.row
            }
            let hit = firstExact(in: turn) ?? firstExact(in: thread) ?? nearest(in: turn) ?? nearest(in: thread)
            guard let hit else { continue }
            seen.insert(hit.id)
            picked.append(hit)
        }
        return picked
    }

    /// The same title once both are trimmed and their punctuation is made
    /// plain (`plainPunctuation`), and blind to case and diacritics. The
    /// exact half of tile resolution, and what `AskEval` counts as a title the
    /// turn read.
    static func titleEquals(_ title: String, name: String) -> Bool {
        let title = needle(for: title)
        guard !title.isEmpty else { return false }
        return title.compare(
            needle(for: name), options: [.caseInsensitive, .diacriticInsensitive], locale: .current
        ) == .orderedSame
    }

    /// Equal by `titleEquals`, or one inside the other when the shorter side
    /// is long enough not to be a stray word.
    static func titleMatches(_ title: String, name: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        if titleEquals(title, name: name) { return true }
        guard min(title.count, name.count) >= wholeWordBelow else { return false }
        return mention(of: title, in: name) != nil || mention(of: name, in: title) != nil
    }

    /// Where `title` is named in `text`, if it is: case- and
    /// diacritic-insensitive, over both strings with their typographic
    /// punctuation made plain, so a title stored with three periods or a
    /// straight apostrophe is found in prose the model wrote with an ellipsis
    /// or a curly one. The range indexes the text with its punctuation made
    /// plain (`plainPunctuation`), not the original; callers use it only to
    /// order mentions, never to slice the original.
    static func mention(of title: String, in text: String) -> Range<String.Index>? {
        mention(of: title, inPlain: plainPunctuation(text))
    }

    /// `mention(of:in:)` over prose whose punctuation the caller has already
    /// made plain, so a scan of many titles through one text does that work
    /// once.
    private static func mention(of title: String, inPlain haystack: String) -> Range<String.Index>? {
        var places = mentions(of: needle(for: title), inPlain: haystack).makeIterator()
        return places.next()
    }

    /// Every place a title is named in prose, both with their punctuation
    /// made plain, in order and lazily, so a caller that wants only the first
    /// scans no further. A title shorter than `wholeWordBelow` counts only as
    /// a whole word.
    private static func mentions(
        of needle: String, inPlain haystack: String
    ) -> UnfoldSequence<Range<String.Index>, String.Index> {
        sequence(state: haystack.startIndex) { start in
            guard !needle.isEmpty else { return nil }
            while start < haystack.endIndex, let range = haystack.range(
                of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                range: start..<haystack.endIndex, locale: .current
            ) {
                start = range.upperBound
                if needle.count >= wholeWordBelow || isWholeWord(range, in: haystack) { return range }
            }
            return nil
        }
    }

    /// A title as the mention scan looks for it: trimmed, punctuation made
    /// plain.
    private static func needle(for title: String) -> String {
        plainPunctuation(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The typographic variants a model writes and a catalog stores
    /// interchangeably, replaced with their plain forms. Applied to both sides
    /// of a mention, so which form either side used stops mattering.
    static func plainPunctuation(_ text: String) -> String {
        var out = text
        for (fancy, plain) in [("…", "..."), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""), ("—", "-"), ("–", "-")] {
            out = out.replacingOccurrences(of: fancy, with: plain)
        }
        return out
    }

    /// Whether the text on both sides of `range` ends a word there: no
    /// letter, or a letter of a script that writes its words without spaces
    /// (`wholeWordBelow`).
    private static func isWholeWord(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        return !continuesAWord(before) && !continuesAWord(after)
    }

    private static func continuesAWord(_ neighbour: Character?) -> Bool {
        guard let neighbour, neighbour.isLetter else { return false }
        return !AskScripts.writesWordsWithoutSpaces(neighbour)
    }
}

/// Consumes one element of a list of any shape, so a row that no longer
/// decodes can be stepped over.
nonisolated private struct AskSkippedRow: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

/// Which writing systems set their words apart with spaces, for a scan that
/// has to know where a word ends: `AskAnswer`'s mentions, and the bold against
/// Chinese and Japanese punctuation (`AskMarkdown.unspacedBold(in:)`).
nonisolated enum AskScripts {
    /// Whether `character` belongs to a script that writes the next word
    /// straight on, with no space between: Han, Hiragana, Katakana, Thai, Lao,
    /// Khmer and Myanmar. And Hangul: Korean spaces its words, but writes a
    /// particle straight onto one, so a title ends a word where a Hangul
    /// letter follows it, as "토지" does in "토지를". Read from the first
    /// scalar's block, since the standard library names no script.
    static func writesWordsWithoutSpaces(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return unspacedBlocks.contains { $0.contains(scalar.value) }
    }

    private static let unspacedBlocks: [ClosedRange<UInt32>] = [
        0x0E00...0x0E7F, // Thai
        0x0E80...0x0EFF, // Lao
        0x1000...0x109F, // Myanmar
        0x1100...0x11FF, // Hangul Jamo
        0x1780...0x17FF, // Khmer
        0x19E0...0x19FF, // Khmer Symbols
        0x2E80...0x2FDF, // CJK and Kangxi Radicals
        0x3005...0x3007, // 々, 〆 and 〇, which Han text writes as letters
        0x3040...0x30FF, // Hiragana and Katakana
        0x3130...0x318F, // Hangul Compatibility Jamo
        0x31F0...0x31FF, // Katakana Phonetic Extensions
        0x3400...0x4DBF, // CJK Unified Ideographs Extension A
        0x4E00...0x9FFF, // CJK Unified Ideographs
        0xA960...0xA97F, // Hangul Jamo Extended-A
        0xA9E0...0xA9FF, // Myanmar Extended-B
        0xAA60...0xAA7F, // Myanmar Extended-A
        0xAC00...0xD7FF, // Hangul Syllables and Jamo Extended-B
        0xF900...0xFAFF, // CJK Compatibility Ideographs
        0xFF66...0xFF9F, // Halfwidth Katakana
        0xFFA0...0xFFDC, // Halfwidth Hangul
        0x1B000...0x1B16F, // Kana Supplement and Extended-A
        0x20000...0x3134F // CJK Unified Ideographs Extensions B to G
    ]
}
