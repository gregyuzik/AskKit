public import Foundation
import Synchronization

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
    /// the deadline or its token cap cut it once its follow-ups had begun, and
    /// a stopped one keeps none. A deterministic answer's, and a refine
    /// pass's, are the domain's. Whoever chose them, the engine hands out at
    /// most `maxTiles`.
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
    public let questionKind: AskQuestionKind?
    /// The answer ended part-way: the turn's deadline cut the stream, the
    /// model's reply reached its token cap (`AskReplySnapshot.reachedTokenCap`),
    /// which the SDK ends as though it had finished, or the reader stopped a
    /// turn that had already written something (`AskThreadEntry.stopped`
    /// tells a stop from the other two). `text` is as far as it got, kept by
    /// the rule a finished answer is kept by: grounded, unless the domain's
    /// policy keeps answers nothing grounded
    /// (`AskGroundingPolicy.notRequired`). The model chooses its tiles after
    /// its prose and writes its follow-ups after them, so a deadline or a cap
    /// that cut it once the follow-ups had begun keeps the finished tile list,
    /// with its basis line; cut sooner, or stopped by the reader, it has no
    /// tiles.
    public let isTruncated: Bool
    /// The domain's factual sentence about why the answer chose what it shows
    /// (`AskDomain.basis(for:)`), never sentiment, never a percentage. Asked
    /// only of an answer that shows tiles and isn't a count, a total or a
    /// yes-or-no; nil for no line.
    public let basis: String?
    /// What a tool also knew about this turn: the data a card under the
    /// answer draws from, recorded through `AskCollector.record(payload:)`,
    /// or given to the initializer of an answer the domain builds itself,
    /// which encode it as JSON, and read back with `payload(as:)`. Persisted
    /// with the thread.
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

    /// An answer with each field as given and no payload. The engine builds
    /// one per turn; a domain builds one for a deterministic answer
    /// (`AskDomain.deterministicAnswer(for:)`) or a refine pass.
    public init(
        text: String,
        matches: [Row] = [],
        tiles: [Row] = [],
        followUps: [String] = [],
        questionKind: AskQuestionKind? = nil,
        isTruncated: Bool = false,
        basis: String? = nil,
        proposal: AskProposal? = nil,
        grounding: AskGrounding? = nil
    ) {
        self.init(
            text: text, matches: matches, tiles: tiles, followUps: followUps, questionKind: questionKind,
            isTruncated: isTruncated, basis: basis, encodedPayload: nil, proposal: proposal, grounding: grounding
        )
    }

    /// An answer with each field as given, carrying `payload`, which AskKit
    /// encodes as JSON for `payload(as:)` to read back, as it encodes what a
    /// tool records (`AskCollector.record(payload:)`): the value itself, such
    /// as the years a pick spans, never its encoding.
    ///
    /// **Throws, rather than building an answer missing its card.** A value
    /// that doesn't encode, such as a `Double` that is infinite or NaN, or a
    /// `Data`, which is a payload already encoded, throws the encoder's
    /// `EncodingError`: a mistake in the domain's type, which a card left out
    /// without a word would hide. Thrown from
    /// `AskDomain.deterministicAnswer(for:)`, it fails the turn, and from a
    /// refine pass it keeps the first answer; the log names it either way.
    public init(
        text: String,
        matches: [Row] = [],
        tiles: [Row] = [],
        followUps: [String] = [],
        questionKind: AskQuestionKind? = nil,
        isTruncated: Bool = false,
        basis: String? = nil,
        payload: some Encodable & Sendable,
        proposal: AskProposal? = nil,
        grounding: AskGrounding? = nil
    ) throws {
        self.init(
            text: text, matches: matches, tiles: tiles, followUps: followUps, questionKind: questionKind,
            isTruncated: isTruncated, basis: basis, encodedPayload: try AskPayloadCoding.encode(payload),
            proposal: proposal, grounding: grounding
        )
    }

    /// An answer whose payload is already JSON, or nil for none: what the
    /// engine builds from a turn's collector, and what a test scripts.
    ///
    /// **Not public**, so a domain can't hand in bytes in an encoding of its
    /// own, which `payload(as:)` would read as nil.
    init(
        text: String,
        matches: [Row] = [],
        tiles: [Row] = [],
        followUps: [String] = [],
        questionKind: AskQuestionKind? = nil,
        isTruncated: Bool = false,
        basis: String? = nil,
        encodedPayload payload: Data?,
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
        let droppedRows = AskDroppedRows.key.flatMap { decoder.userInfo[$0] as? AskDroppedRows }
        matches = Self.salvagedRows(in: container, forKey: .matches, counting: droppedRows)
        tiles = Self.salvagedRows(in: container, forKey: .tiles, counting: droppedRows)
        followUps = try container.decodeIfPresent([String].self, forKey: .followUps) ?? []
        questionKind = try container.decodeIfPresent(AskQuestionKind.self, forKey: .questionKind)
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
    /// The rows left out are added to `droppedRows`, for the read to log.
    private static func salvagedRows<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>, forKey key: Key, counting droppedRows: AskDroppedRows?
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
        // A JSON list knows its length, so a list cut short by a row that
        // couldn't be skipped counts the rows after it too.
        if let droppedRows, let count = list.count, count > rows.count {
            droppedRows.add(count - rows.count)
        }
        return rows
    }

    // MARK: - Payload, basis, proposal and grounding

    /// The payload as the domain's own type, decoded from the JSON AskKit
    /// encoded it as, or nil when there is none or it no longer decodes. A
    /// card that can't be drawn is left out; it is never a failed answer.
    public func payload<Value: Decodable>(as type: Value.Type) -> Value? {
        guard let payload else { return nil }
        return AskPayloadCoding.decode(type, from: payload)
    }

    /// This answer with a different basis line.
    public func replacing(basis newBasis: String?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: newBasis, encodedPayload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer carrying `payload` in place of whatever it carried,
    /// encoded as JSON as the initializer encodes one. Throws the encoder's
    /// `EncodingError` for a value that doesn't encode, as the initializer
    /// does, and for a `Data`.
    public func replacing(payload newPayload: some Encodable & Sendable) throws -> AskAnswer<Row> {
        replacing(encodedPayload: try AskPayloadCoding.encode(newPayload))
    }

    /// This answer with a payload already JSON, or none: the engine's, which
    /// keeps the first answer's payload under a refined one that has none.
    func replacing(encodedPayload newPayload: Data?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: newPayload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with a different proposal.
    public func replacing(proposal newProposal: AskProposal?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: payload,
            proposal: newProposal, grounding: grounding
        )
    }

    /// This answer with a different record of what grounded it: a refine
    /// pass's, to say its own answer rests on something else.
    public func replacing(grounding newGrounding: AskGrounding?) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: payload,
            proposal: proposal, grounding: newGrounding
        )
    }

    /// This answer with different follow-ups: the engine's, once it has
    /// cleaned a refine pass's.
    func replacing(followUps newFollowUps: [String]) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: tiles, followUps: newFollowUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with different tiles.
    func replacing(tiles newTiles: [Row]) -> AskAnswer<Row> {
        AskAnswer(
            text: text, matches: matches, tiles: newTiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: payload,
            proposal: proposal, grounding: grounding
        )
    }

    /// This answer with only the rows `isKept` keeps, in `matches` and
    /// `tiles` alike, and how many went, counted per list as a read counts
    /// the rows that no longer decode (`salvagedRows`): how a write leaves out
    /// a row that won't encode (`AskThreadStore.encodeEntries(_:logger:)`).
    func keepingRows(where isKept: (Row) -> Bool) -> (answer: AskAnswer<Row>, dropped: Int) {
        let keptMatches = matches.filter(isKept)
        let keptTiles = tiles.filter(isKept)
        let dropped = matches.count - keptMatches.count + tiles.count - keptTiles.count
        guard dropped > 0 else { return (self, 0) }
        let answer = AskAnswer(
            text: text, matches: keptMatches, tiles: keptTiles, followUps: followUps,
            questionKind: questionKind, isTruncated: isTruncated, basis: basis, encodedPayload: payload,
            proposal: proposal, grounding: grounding
        )
        return (answer, dropped)
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

    /// The fewest characters a title cut short keeps for a name or a mention
    /// ending in the cut's ellipsis to count as that title.
    ///
    /// A tool clamps the titles it shows (`AskPrompt.clamp(_:_:)`), and the
    /// model names a row whose title the clamp cut as it was shown: its first
    /// characters, then an ellipsis (`AskPrompt.cutMark`), which the model may
    /// retype as three periods. So a name or a mention that ends in one names
    /// the row whose title, as shown or as stored (`needles(for:)`), opens
    /// with what comes before it and goes on past it.
    ///
    /// Shorter than this, what comes before an ellipsis can be the model
    /// trailing off after a word or three, and a word can open a title: "You
    /// could play…" opens Playing the Angel, and a tile named "The B…" opens
    /// every band whose name starts so. `wholeWordBelow`, the floor for a
    /// title inside other text, lets both through. A clamp's cut is as long as
    /// the tool's limit, 60 characters at `AskPrompt.shortClamp`, so only a
    /// tool that clamps titles to fewer than this shows the model a cut that
    /// names no row.
    static var cutTitleFloor: Int { 16 }

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
        let cuts = cutMarks(inPlain: haystack)
        let named: [(row: Row, places: [Place])] = rows.compactMap { row in
            let places = places(of: row.displayTitle, inPlain: haystack, cuts: cuts)
            return places.isEmpty ? nil : (row, places)
        }
        // A title inside a longer one the prose names is that one's mention:
        // "Aliens" does not also name Alien, nor "Dune Messiah" Dune, nor a
        // title cut short ("Dune: The Machine Crusade and the Butlerian…") the
        // Dune it opens with. The shorter title counts only where the prose
        // names it outside every longer title it names: at a place no other
        // row's place holds (`Place.holds(_:)`). Only the rows already named
        // are compared, so the cost is the few titles an answer names, never
        // every row read.
        var kept: [(row: Row, at: String.Index)] = []
        for (index, entry) in named.enumerated() {
            let own = entry.places.first { place in
                !named.indices.contains { other in
                    other != index && named[other].places.contains { $0.holds(place) }
                }
            }
            if let own { kept.append((entry.row, own.range.lowerBound)) }
        }
        return kept.sorted { $0.at < $1.at }.map { $0.row }
    }

    /// Where the prose, its punctuation made plain, names a title, and
    /// whether it names it cut short.
    private struct Place {
        let range: Range<String.Index>
        let isCut: Bool

        /// Whether this place, another row's, is where `place` is named: it
        /// takes in `place` and runs further, or is the same place with the
        /// title whole where `place` is cut. A title that ends in an ellipsis
        /// is that title, not the start of a longer one.
        func holds(_ place: Place) -> Bool {
            guard range.lowerBound <= place.range.lowerBound, place.range.upperBound <= range.upperBound else { return false }
            return range != place.range || (place.isCut && !isCut)
        }
    }

    /// Every place the prose, its punctuation made plain, names a title, in
    /// order: whole in any of its forms (`needles(for:)`), or cut short
    /// before one of the prose's ellipses (`cutMentions(of:at:inPlain:)`).
    private static func places(of title: String, inPlain haystack: String, cuts: [CutMark]) -> [Place] {
        let forms = needles(for: title)
        var places: [Place] = []
        for form in forms {
            places += mentions(of: form, inPlain: haystack).map { Place(range: $0, isCut: false) }
            if !cuts.isEmpty {
                places += cutMentions(of: form, at: cuts, inPlain: haystack).map { Place(range: $0, isCut: true) }
            }
        }
        return places.sorted { $0.range.lowerBound < $1.range.lowerBound }
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
    /// `turn` and then in `thread`, then a title cut short, and only then a
    /// near one, each in the same order. A near match is for a model that
    /// paraphrased; when the title it wrote is a row, that row is the one it
    /// meant, so "Aliens" is never Alien for having been read first, nor
    /// "Dune" Dune Messiah. A title that resolves to nothing is dropped: a
    /// tile must be a row the thread actually read.
    ///
    /// **A title cut short, after an exact one and before a near one.** A
    /// name that ends in an ellipsis, as the clamp ends a title it cut, names
    /// the row whose title opens with what comes before it and goes on past
    /// it (`cutTitleFloor`), in `turn` and then in `thread`. Before a near
    /// match, since the row whose title is the cut's text alone, without its
    /// ellipsis, was shown to the model whole and is a near match to every
    /// cut of a longer one; after an exact one, so a title that itself ends
    /// in an ellipsis is still that title. Titles that open with the same
    /// characters were shown cut there alike, so a cut name is the first of
    /// them read, this turn's before the thread's.
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
            let cut = cutTitle(in: name)
            func firstCut(in rows: [Row]) -> Row? {
                guard let cut else { return nil }
                return rows.first { !seen.contains($0.id) && needles(for: $0.displayTitle).contains { opens($0, with: cut) } }
            }
            func nearest(in rows: [Row]) -> Row? {
                var best: (row: Row, overlap: Int)?
                for row in rows where !seen.contains(row.id) {
                    guard let overlap = nearOverlap(row.displayTitle, name: name), overlap > (best?.overlap ?? 0) else { continue }
                    best = (row, overlap)
                }
                return best?.row
            }
            let hit = firstExact(in: turn) ?? firstExact(in: thread)
                ?? firstCut(in: turn) ?? firstCut(in: thread)
                ?? nearest(in: turn) ?? nearest(in: thread)
            guard let hit else { continue }
            seen.insert(hit.id)
            picked.append(hit)
        }
        return picked
    }

    /// The same title once both are trimmed and their punctuation is made
    /// plain (`plainPunctuation`), and blind to case and diacritics, with the
    /// title read as stored or as a tool's clamp showed it (`needles(for:)`).
    /// The exact half of tile resolution, and what `AskEval` counts as a
    /// title the turn read.
    static func titleEquals(_ title: String, name: String) -> Bool {
        let name = needle(for: name)
        return needles(for: title).contains { equals($0, name) }
    }

    /// How much of the model's `name` a row titled `title` shares as a near
    /// match, or nil for none: equal by `titleEquals`, or one inside the
    /// other when the shorter side is long enough not to be a stray word, and
    /// the length of that shorter side. The title is read in each of its
    /// forms (`needles(for:)`), and the nearest of them counts.
    static func nearOverlap(_ title: String, name: String) -> Int? {
        let name = needle(for: name)
        guard !name.isEmpty else { return nil }
        let overlaps = needles(for: title).compactMap { title -> Int? in
            let shorter = min(title.count, name.count)
            if equals(title, name) { return shorter }
            guard shorter >= wholeWordBelow else { return nil }
            let inside = firstMention(of: title, inPlain: name) != nil || firstMention(of: name, inPlain: title) != nil
            return inside ? shorter : nil
        }
        return overlaps.max()
    }

    /// Where `title` is named in `text`, if it is: case- and
    /// diacritic-insensitive, over both strings with their typographic
    /// punctuation made plain, so a title stored with three periods or a
    /// straight apostrophe is found in prose the model wrote with an ellipsis
    /// or a curly one, and with the title read as stored or as a tool's
    /// clamp showed it (`needles(for:)`), whole or cut short before an
    /// ellipsis (`cutTitleFloor`): the first place it is named. The range
    /// indexes the text with its punctuation made plain (`plainPunctuation`),
    /// not the original; callers use it only to order mentions, never to
    /// slice the original.
    static func mention(of title: String, in text: String) -> Range<String.Index>? {
        let haystack = plainPunctuation(text)
        return places(of: title, inPlain: haystack, cuts: cutMarks(inPlain: haystack)).first?.range
    }

    /// The first place a needle is named in prose whose punctuation is
    /// already plain.
    private static func firstMention(of needle: String, inPlain haystack: String) -> Range<String.Index>? {
        var places = mentions(of: needle, inPlain: haystack).makeIterator()
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

    /// Where an ellipsis stands in prose whose punctuation is plain: the
    /// ellipsis, and where the text before it ends, short of any spaces
    /// between them, as the clamp leaves one when it cuts after a space.
    private struct CutMark {
        let end: String.Index
        let mark: Range<String.Index>
    }

    /// The clamp's ellipsis (`AskPrompt.cutMark`) as matching reads it, its
    /// punctuation made plain: three periods.
    private static var plainCutMark: String { plainPunctuation(String(AskPrompt.cutMark)) }

    /// Every ellipsis in the prose, in order. None in most answers, which
    /// then cost the mention scan nothing more.
    private static func cutMarks(inPlain haystack: String) -> [CutMark] {
        var marks: [CutMark] = []
        var start = haystack.startIndex
        while let mark = haystack.range(of: plainCutMark, options: .literal, range: start..<haystack.endIndex) {
            var end = mark.lowerBound
            while end > haystack.startIndex, haystack[haystack.index(before: end)].isWhitespace,
                  !haystack[haystack.index(before: end)].isNewline {
                end = haystack.index(before: end)
            }
            marks.append(CutMark(end: end, mark: mark))
            start = mark.upperBound
        }
        return marks
    }

    /// Where the prose names a title cut short, one of the title's forms
    /// `needle`: before an ellipsis, the text from a word's start that opens
    /// the title and stops short of its end, `cutTitleFloor` characters or
    /// more, counting any spaces before the ellipsis as a name's cut counts
    /// them (`cutTitle(in:)`). The place runs to the ellipsis's end, from the
    /// earliest start each ellipsis allows.
    private static func cutMentions(of needle: String, at cuts: [CutMark], inPlain haystack: String) -> [Range<String.Index>] {
        guard needle.count > cutTitleFloor else { return [] }
        let head = String(needle.prefix(cutTitleFloor))
        return cuts.compactMap { cut in
            // A cut opens the title, so it can't run far past the title's
            // length: twice that, for the case-blind comparison's leeway.
            let reach = haystack.index(cut.end, offsetBy: -2 * needle.count, limitedBy: haystack.startIndex)
                ?? haystack.startIndex
            var earliest: String.Index?
            // To the ellipsis, not to `end`: a cut just past a space keeps
            // it, so the title's opening can run into the spaces.
            var searchEnd = cut.mark.lowerBound
            while reach < searchEnd, let found = haystack.range(
                of: head, options: [.backwards, .caseInsensitive, .diacriticInsensitive],
                range: reach..<searchEnd, locale: .current
            ) {
                let before = found.lowerBound == haystack.startIndex ? nil : haystack[haystack.index(before: found.lowerBound)]
                if !continuesAWord(before), opens(needle, with: haystack[found.lowerBound..<cut.end]) {
                    earliest = found.lowerBound
                }
                searchEnd = haystack.index(before: found.upperBound)
            }
            return earliest.map { $0..<cut.mark.upperBound }
        }
    }

    /// What comes before the ellipsis a name ends in, without the spaces
    /// before it, when it is long enough to be a title cut short
    /// (`cutTitleFloor`), or nil. Counted with those spaces, as the clamp's
    /// limit counts a cut that falls just past one.
    private static func cutTitle(in name: String) -> Substring? {
        let name = needle(for: name)
        guard name.hasSuffix(plainCutMark) else { return nil }
        var kept = name.dropLast(plainCutMark.count)
        guard kept.count >= cutTitleFloor else { return nil }
        while let last = kept.last, last.isWhitespace { kept.removeLast() }
        return kept
    }

    /// Whether `cut` opens the title form `needle` and stops short of its
    /// end, blind to case and diacritics.
    private static func opens(_ needle: String, with cut: some StringProtocol) -> Bool {
        guard let range = needle.range(
            of: cut, options: [.anchored, .caseInsensitive, .diacriticInsensitive], locale: .current
        ) else { return false }
        return range.upperBound < needle.endIndex
    }

    /// The same text to the comparison every match makes: blind to case and
    /// diacritics.
    private static func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == .orderedSame
    }

    /// The model's name for a row as the matching reads it: trimmed,
    /// punctuation made plain.
    private static func needle(for name: String) -> String {
        plainPunctuation(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A row's title in each form the model may name it by, as the matching
    /// reads them (`needle(for:)`): as a tool's clamp showed it, which is how
    /// the model saw it in tool output, a recap or a referent
    /// (`AskPrompt.shownWhole(_:)`: brackets swapped, tabs and line breaks
    /// made spaces, invisible and control characters dropped, straight
    /// quotes turned to double primes); and as stored, which the model can
    /// know from elsewhere in the turn, such as the question. One form where
    /// the two agree, and none that is empty.
    ///
    /// Read once a title, not once a call (`AskTitleForms`): the mention scan
    /// reads every row the thread has read on every streamed snapshot of a
    /// follow-up, and the clamp's reading is several passes over each title.
    private static func needles(for title: String) -> [String] {
        AskTitleForms.forms(of: title) { title in
            let stored = needle(for: title)
            let shown = needle(for: AskPrompt.shownWhole(title))
            return [shown, stored].reduce(into: []) { forms, form in
                if !form.isEmpty, !forms.contains(form) { forms.append(form) }
            }
        }
    }

    /// The typographic variants a model writes and a catalog stores
    /// interchangeably, replaced with their plain forms. Applied to both sides
    /// of a mention, so which form either side used stops mattering.
    ///
    /// The double prime (`″`) is a straight double quote as the model reads
    /// one: `AskPrompt.sanitizeForFence`, which every fenced path runs, swaps
    /// each for it, so an answer that copies `7″` still names the row titled
    /// `7"`.
    static func plainPunctuation(_ text: String) -> String {
        var out = text
        for (fancy, plain) in [("…", "..."), ("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""), ("″", "\""), ("—", "-"), ("–", "-")] {
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

/// Counts the rows a read leaves out of their answers (`AskAnswer`'s
/// `salvagedRows`), handed to the decoder in its `userInfo` by a read that
/// logs them (`AskThreadStore.decodeEntries(from:)`).
///
/// A row a host's type has evolved past costs its answer that row and never
/// the turn, so nothing else would say it went: a migration gone wrong would
/// take every saved tile, and the next save would write the answers back
/// without them.
nonisolated final class AskDroppedRows: Sendable {
    /// Where a decoder's `userInfo` holds one. Optional only because
    /// `CodingUserInfoKey`'s initializer is.
    static let key = CodingUserInfoKey(rawValue: "AskKit.droppedRows")

    private let count = Mutex(0)

    /// How many rows were left out.
    var total: Int { count.withLock { $0 } }

    func add(_ rows: Int) {
        count.withLock { $0 += rows }
    }
}

/// The forms of the titles read lately, as tile and mention matching read
/// them (`AskAnswer`'s `needles(for:)`), so each title is read once rather
/// than on every streamed snapshot that is scanned for it. What a title's
/// forms are depends on the title alone.
///
/// Emptied whole once it holds `capacity` titles: four times
/// `AskCollector.maxThreadRows` (200), the most a scan reads at once, so a
/// thread's rows stay in it while a long-lived process can't grow it without
/// bound. A number rather than that constant: this file builds on every
/// platform, and `AskCollector` only where Foundation Models runs.
nonisolated enum AskTitleForms {
    static var capacity: Int { 800 }

    private static let known = Mutex<[String: [String]]>([:])

    /// `title`'s forms, made by `make` the first time it is asked for.
    static func forms(of title: String, making make: (String) -> [String]) -> [String] {
        if let forms = known.withLock({ $0[title] }) { return forms }
        let forms = make(title)
        known.withLock { known in
            if known.count >= capacity { known.removeAll(keepingCapacity: true) }
            known[title] = forms
        }
        return forms
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
        0x20000...0x3347F // CJK Unified Ideographs Extensions B to J, and the Compatibility Supplement among them
    ]
}
