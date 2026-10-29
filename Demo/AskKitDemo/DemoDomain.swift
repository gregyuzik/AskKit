import AskCore
import CoreGraphics
import Foundation
import FoundationModels

/// One thing the demo's imaginary reader owns.
///
/// Four kinds on purpose: a domain with one kind never exercises the argument
/// the model has to choose, and the tile grid, the starters and the evidence
/// line all read differently once "your books" and "your records" are different
/// answers to the same question.
nonisolated struct DemoRow: AskRow {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case book, record, tool, garment

        /// What a sentence calls a shelf of these — the scope name that reaches
        /// the wait row and the evidence line.
        var scope: String {
            switch self {
            case .book: "books"
            case .record: "records"
            case .tool: "tools"
            case .garment: "clothes"
            }
        }

        /// What the reader does with a shelf of these, for the search: the
        /// query's `@Guide` asks for "a use", so "read" has to find the books.
        var uses: String {
            switch self {
            case .book: "read"
            case .record: "listen music"
            case .tool: "woodworking"
            case .garment: "wear"
            }
        }
    }

    let id: String
    let title: String
    let kind: Kind
    let year: Int
    let note: String

    var displayTitle: String { title }
}

extension DemoRow {
    /// Thirty rows, written rather than generated, because the traps are in the
    /// specifics: a two-letter title and a leading-punctuation title are the two
    /// cases a plain substring match gets wrong, a duplicated word across two
    /// kinds is what a `kind` argument is for, and a pair of years in one
    /// decade is what a "which is oldest" question needs to have an answer at
    /// all.
    static let all: [DemoRow] = [
        DemoRow(id: "b1", title: "The Long Goodbye", kind: .book, year: 1953, note: "paperback, spine cracked"),
        DemoRow(id: "b2", title: "Go", kind: .book, year: 1958, note: "two-letter title, on purpose"),
        DemoRow(id: "b3", title: "...And Then There Were None", kind: .book, year: 1939, note: "leading punctuation, on purpose"),
        DemoRow(id: "b4", title: "The Dispossessed", kind: .book, year: 1974, note: "first edition"),
        DemoRow(id: "b5", title: "A Pattern Language", kind: .book, year: 1977, note: "borrowed, never returned"),
        DemoRow(id: "b6", title: "The Peregrine", kind: .book, year: 1967, note: "reread every autumn"),
        DemoRow(id: "b7", title: "Housekeeping", kind: .book, year: 1980, note: "gift"),
        DemoRow(id: "b8", title: "The Mezzanine", kind: .book, year: 1988, note: "footnotes all the way down"),
        DemoRow(id: "r1", title: "Kind of Blue", kind: .record, year: 1959, note: "original pressing"),
        DemoRow(id: "r2", title: "Rumours", kind: .record, year: 1977, note: "warped, still plays"),
        DemoRow(id: "r3", title: "The Dark Side of the Moon", kind: .record, year: 1973, note: "poster missing"),
        DemoRow(id: "r4", title: "Abbey Road", kind: .record, year: 1969, note: "second pressing"),
        DemoRow(id: "r5", title: "Blue", kind: .record, year: 1971, note: "sleeve repaired"),
        DemoRow(id: "r6", title: "Remain in Light", kind: .record, year: 1980, note: "bought twice by mistake"),
        DemoRow(id: "r7", title: "Spirit of Eden", kind: .record, year: 1988, note: "sealed"),
        DemoRow(id: "r8", title: "Music for Airports", kind: .record, year: 1978, note: "played at low volume"),
        DemoRow(id: "t1", title: "Block Plane", kind: .tool, year: 1954, note: "inherited, sharpened"),
        DemoRow(id: "t2", title: "Marking Gauge", kind: .tool, year: 1998, note: "beech, brass face"),
        DemoRow(id: "t3", title: "Dovetail Saw", kind: .tool, year: 2011, note: "rip filed"),
        DemoRow(id: "t4", title: "Bench Chisel Set", kind: .tool, year: 2004, note: "six of them, one lost"),
        DemoRow(id: "t5", title: "Cabinet Scraper", kind: .tool, year: 1979, note: "needs a burr"),
        DemoRow(id: "t6", title: "Try Square", kind: .tool, year: 1963, note: "true, checked"),
        DemoRow(id: "t7", title: "Card Scraper", kind: .tool, year: 2019, note: "the cheap one"),
        DemoRow(id: "g1", title: "Navy Blazer", kind: .garment, year: 2016, note: "wool, two buttons"),
        DemoRow(id: "g2", title: "Blue Oxford Shirt", kind: .garment, year: 2021, note: "collar fraying"),
        DemoRow(id: "g3", title: "Grey Flannel Trousers", kind: .garment, year: 2019, note: "hemmed twice"),
        DemoRow(id: "g4", title: "Brown Derby Shoes", kind: .garment, year: 2015, note: "resoled"),
        DemoRow(id: "g5", title: "Waxed Cotton Jacket", kind: .garment, year: 2018, note: "needs rewaxing"),
        DemoRow(id: "g6", title: "Fair Isle Vest", kind: .garment, year: 2022, note: "too warm for indoors"),
        DemoRow(id: "g7", title: "Linen Shirt", kind: .garment, year: 2023, note: "creases on sight")
    ]
}

// MARK: - The search behind both callers

/// The one lookup, shared by the tool the model calls and the search the app
/// runs on the model's behalf during a grounded retry.
///
/// **One function, two callers, by design.** `AskDomain.search` exists so the
/// grounded retry searches through the *same* code path the tool takes; two
/// implementations of "find the reader's things" is how the retry ends up
/// grounded in something the tool would never have returned.
nonisolated enum DemoSearch {
    /// Every row of `kind`, or of every kind, that has a word of the query in
    /// its title, its note or its shelf's names and uses.
    ///
    /// **Whole words, not substrings.** "own" is in "Brown" and "down", so a
    /// substring match answers "records I own" with ten things. A query word
    /// that names no thing (`stopWords`) matches nothing, and a query with no
    /// other word finds the whole shelf, which is what "the oldest thing I
    /// have" needs to read. One that names something no row has finds
    /// nothing, so "a typewriter" is a no.
    static func rows(query: String, kind: String?) -> [DemoRow] {
        let wanted = DemoRow.Kind(rawValue: (kind ?? "").lowercased())
        let terms = words(query).filter { $0.count > 1 && !stopWords.contains($0) }
        return DemoRow.all.filter { row in
            if let wanted, row.kind != wanted { return false }
            guard !terms.isEmpty else { return true }
            let haystack = words("\(row.title) \(row.note) \(row.kind.rawValue) \(row.kind.scope) \(row.kind.uses)")
            return terms.contains { term in haystack.contains { sameWord(term, $0) } }
        }
    }

    /// The words of a string as the search compares them: split wherever
    /// there is neither a letter nor a digit, so "...And" is "and", and
    /// compared as `localizedStandardContains` does, ignoring case, accents
    /// and width in the reader's locale.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current) }
    }

    /// The same word, or the same with an "s" on, so "record" finds the
    /// records and "shirts" the shirts.
    private static func sameWord(_ term: String, _ word: String) -> Bool {
        term == word || term + "s" == word || term == word + "s"
    }

    /// Words a query carries that say nothing about which thing: function
    /// words, owning, counting, ordering and time. English, because the rows
    /// are: like the plural rule above, this is retrieval over the demo's own
    /// English data, steering what the model reads before it answers, never
    /// a decision about the answer after it (house rule 7). A host's search
    /// runs over its own data in its own way.
    private static let stopWords: Set<String> = [
        "a", "about", "all", "an", "and", "any", "are", "at", "be", "best", "by", "called", "can", "could",
        "count", "did", "do", "does", "every", "everything", "favorite", "favourite", "first", "for", "from",
        "got", "has", "have", "how", "in", "is", "it", "item", "items", "last", "latest", "least", "many",
        "me", "mine", "most", "much", "my", "named", "newest", "now", "number", "of", "oldest", "on", "one",
        "or", "own", "owned", "should", "some", "something", "stuff", "that", "the", "these", "thing",
        "things", "this", "those", "titled", "to", "today", "tomorrow", "tonight", "total", "what",
        "which", "with", "would", "you", "your"
    ]

    /// What the model is shown: one line a row, its title and note through
    /// `AskPrompt.clamp`, which clamps each, swaps its angle brackets and
    /// redacts AskKit's fence tags, so no row can spell a tag to the model
    /// (house rule 3). The kind and the year are the demo's own values.
    ///
    /// **Bare lines, in no tag of the demo's own.** AskKit fences what it
    /// composes: the grounded retry puts this inside its own `<tool_result>`,
    /// sanitized, so a wrapper spelled with one of AskKit's tag names, such as
    /// `<rows>`, would reach the model as `[redacted]`.
    static func render(_ rows: [DemoRow], limit: Int) -> String {
        guard !rows.isEmpty else { return "No matches." }
        var lines = rows.prefix(limit).map { row in
            "\(AskPrompt.clamp(row.title, AskPrompt.shortClamp)) | \(row.kind.rawValue) | \(row.year) | "
                + AskPrompt.clamp(row.note, AskPrompt.shortClamp)
        }
        if rows.count > limit { lines.append("(+\(rows.count - limit) more not shown)") }
        return lines.joined(separator: "\n")
    }
}

/// What a search also knew beyond its rows: the years they span.
///
/// The demo's turn payload (`AskCollector.record(payload:)`), drawn under the
/// answer by `DemoSpanCard` — the shape a host's own card under an answer
/// takes. The model never reads it; the answer carries it out of the turn and
/// the thread keeps it.
nonisolated struct DemoYearSpan: Codable, Sendable, Equatable {
    let oldest: Int
    let newest: Int
    let count: Int

    init?(_ rows: [DemoRow]) {
        let years = rows.map(\.year)
        guard let oldest = years.min(), let newest = years.max() else { return nil }
        self.oldest = oldest
        self.newest = newest
        self.count = rows.count
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

/// The arguments, shared by the tool and the planner.
///
/// **One type, both places.** `AskDomain.SearchArguments` is described to the
/// planner as the arguments the tool would have been called with — if the two
/// drifted, the grounded retry would plan a search the tool cannot run.
@Generable
nonisolated struct DemoSearchArguments: Sendable {
    @Guide(description: "Words from the question — a title, a material, a colour, a use. Leave short and literal.")
    var query: String
    @Guide(description: "Narrow to one kind, when the question is clearly about one: \"book\", \"record\", \"tool\" or \"garment\". Omit for anything that spans kinds.")
    var kind: String?
}

/// `search_my_things` — the demo's whole toolbox.
nonisolated struct DemoSearchTool: Tool {
    let name = "search_my_things"
    let description = """
        Search the things this person owns — their books, records, woodworking tools and clothes — \
        by any words from the question. Call this before answering anything about what they have, \
        including counts and comparisons. Returns one line per match: title, kind, year, note.
        """

    typealias Arguments = DemoSearchArguments

    let context: AskToolContext<DemoRow>

    /// `@concurrent` because this target is main-actor by default, like
    /// AskKit: without it this body runs on the main actor while the reader is
    /// watching a wait row, the trap AGENTS.md names.
    @concurrent func call(arguments: DemoSearchArguments) async throws -> String {
        let scope = DemoRow.Kind(rawValue: (arguments.kind ?? "").lowercased())?.scope
        // The lookup runs inside the call, so the wait row says what is being
        // searched while it is. `withToolCall` finishes the call however the
        // body ends, and only then reports the phrase the body hands back, in
        // the order `AskToolContext` gives.
        return try await context.withToolCall(.searching(scope: scope)) { collector in
            let rows = DemoSearch.rows(query: arguments.query, kind: arguments.kind)
            // Only the rows the model is shown. An answer's tiles and the
            // count under it resolve against what is recorded, so a row past
            // the limit would be a tile the model never read.
            let shown = Array(rows.prefix(context.rowLimit))
            await collector.record(rows: shown)
            // What the search also knew, for the card under the answer. The
            // model never sees it; the answer carries it out of the turn.
            if let span = DemoYearSpan(rows) { try await collector.record(payload: span) }
            return (
                DemoSearch.render(rows, limit: context.rowLimit),
                report: .reading(shown: shown.count, total: rows.count, scope: scope)
            )
        }
    }
}

// MARK: - The domain

/// An app's worth of `AskDomain` with no app behind it.
///
/// It exists so AskUI can be driven in a simulator in seconds — the first
/// screen, the failures, the wait row, the reveal — without a real app's
/// library in the way. It is also a complete example of what a host writes.
///
/// Its copy is plain English literals rather than `String(localized:)`: the demo
/// carries no catalog, so a localized lookup would find nothing and show the
/// English anyway. AskUI's own strings, which are the ones that matter, come
/// from AskUI's catalog exactly as they do in every host.
nonisolated struct DemoDomain: AskDomain {
    typealias Row = DemoRow
    typealias SearchArguments = DemoSearchArguments

    /// `.perLaunch` under the reset launch argument, `.thread` otherwise — see
    /// `DemoLaunchArgument`, which both this target and the UI-test bundle
    /// compile so the string is written once.
    var persistence: AskPersistence {
        CommandLine.arguments.contains(DemoLaunchArgument.resetThread) ? .perLaunch : .thread
    }

    /// The default kinds and `superlative`. Without it a superlative arrives
    /// as a pick (`normalizedKind`), and "Another pick" would offer a second
    /// oldest thing (`rerollableKinds`).
    var questionKinds: [String] { AskQuestionKind.default + [AskQuestionKind.superlative] }

    /// The demo takes a photo, so the composer has its photo button to show
    /// (under `DemoLaunchArgument.photos`) and the thread what becomes of a
    /// photo. It reads none: with no Private Cloud Compute entitlement, the
    /// demo only ever answers on the device.
    var acceptsPhotoAttachments: Bool { true }

    /// A restored question's thumbnail: the sleeve drawn again, off the main
    /// actor, for the one photo the demo attaches.
    func photoThumbnail(for photo: AskQuestionPhoto) async -> CGImage? {
        guard photo.reference == DemoPhoto.reference else { return nil }
        return await DemoPhoto.drawn()
    }

    /// A fixed answer under `-askScriptedAnswer`, so the UI smoke suite can
    /// assert on tiles, a pick's basis line and "Another pick", and a
    /// proposal's card, rather than skipping when the model chooses none of
    /// them; and under `-askHoldTurn` one that never comes. Off by default:
    /// the demo's whole point is a real turn.
    var implementsDeterministicAnswer: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.scriptedAnswer) || Self.holdsTurns
    }

    /// `DemoLaunchArgument.holdTurn`: every turn waits, its wait row up, until
    /// Stop or this deadline.
    static var holdsTurns: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.holdTurn)
    }

    /// Ten minutes under `DemoLaunchArgument.holdTurn`, and the default 45 s
    /// otherwise.
    var turnDeadline: Duration {
        Self.holdsTurns ? .seconds(600) : .seconds(45)
    }

    /// Under `-askScriptedAnswer` or `-askHoldTurn` the demo answers every
    /// question itself, so it says so: on a Mac or simulator without Apple
    /// Intelligence, the first screen keeps its starters and a live composer
    /// under the reason, and the scripted paths run. Otherwise it is
    /// `.ownedLibrary`, the default.
    ///
    /// The same flags as `implementsDeterministicAnswer`, never others: the
    /// promise and the hook that keeps it can't disagree. Only a device that
    /// can't serve reads `answersWithoutModel`, so with Apple Intelligence on
    /// the demo behaves as it does without the flags.
    var firstScreenPolicy: AskFirstScreenPolicy {
        AskFirstScreenPolicy(answersWithoutModel: implementsDeterministicAnswer)
    }

    /// The English phrases matched here choose which fixture stands in for the
    /// model, before anything is generated. None decides what becomes of an
    /// answer (house rule 7): "Another pick" under the scripted pick comes
    /// from its kind, as it would under a turn the model wrote.
    func deterministicAnswer(for question: String) async -> AskAnswer<DemoRow>? {
        guard implementsDeterministicAnswer else { return nil }
        // Held until Stop, which cancels the wait, or the deadline, which
        // abandons it.
        if Self.holdsTurns {
            try? await Task.sleep(for: .seconds(3600))
            return nil
        }
        // An answer that offers to do something, for the smoke test of the
        // card: nothing is done until the reader confirms it.
        if question.localizedCaseInsensitiveContains("lend"),
           let book = DemoRow.all.first(where: { $0.id == "b6" }) {
            return AskAnswer(
                text: "\(book.displayTitle) is on your shelf — you reread it every autumn.",
                matches: [book],
                tiles: [book],
                questionKind: AskQuestionKind.lookup,
                // `try?` only because this answer can't throw: a string id
                // always encodes.
                proposal: try? AskProposal(
                    title: "Mark \(book.displayTitle) as lent",
                    detail: "It stays with your books, marked as out on loan.",
                    actionLabel: "Mark as lent",
                    systemImage: "book.closed",
                    payload: book.id
                )
            )
        }
        // A pick, for the smoke test of what sits under one: the basis line
        // and "Another pick". Not "the oldest" — a superlative has one right
        // answer, and another pick of it is a wrong one. A reroll asks the same
        // question and lands on the same book: what is scripted is the
        // mechanics, not the variety.
        if question.localizedCaseInsensitiveContains("read tonight"),
           let book = DemoRow.all.first(where: { $0.id == "b6" }) {
            let books = DemoRow.all.filter { $0.kind == .book }
            return AskAnswer(
                text: "Try \(book.displayTitle) tonight — you reread it every autumn.",
                matches: books,
                tiles: [book],
                questionKind: AskQuestionKind.pick,
                payload: DemoYearSpan(books)?.encoded
            )
        }
        let shown = Array(DemoRow.all.prefix(2))
        return AskAnswer(
            text: "You own \(DemoRow.all.count) things. Two of them are \(shown[0].displayTitle) "
                + "and \(shown[1].displayTitle).",
            matches: DemoRow.all,
            tiles: shown,
            // No follow-ups: a deterministic answer never establishes a kept
            // conversation, and `AskConversationStore.followUps` is empty
            // without one, so any listed here would be built and never shown.
            questionKind: AskQuestionKind.lookup,
            payload: DemoYearSpan(DemoRow.all)?.encoded
        )
    }

    /// Why these tiles, in the demo's plainest terms: which shelves, which
    /// years. The engine asks only of an answer that shows tiles and isn't a
    /// count, a total or a yes or no (`AskQuestionKind.showNoTiles`), so this
    /// never has to decide that for itself. The shelves are joined as the
    /// reader's locale joins a list, never with an English ", ".
    func basis(for answer: AskAnswer<DemoRow>) -> String? {
        let years = answer.tiles.map(\.year)
        guard let oldest = years.min(), let newest = years.max() else { return nil }
        let shelves = Set(answer.tiles.map(\.kind)).sorted { $0.rawValue < $1.rawValue }.map(\.scope)
        let span = oldest == newest ? "\(oldest)" : "\(oldest)–\(newest)"
        return "From your \(shelves.formatted(.list(type: .and))) · \(span)"
    }

    /// "Another pick" under a pick, a recommendation, and never under a
    /// superlative, which has one right answer.
    ///
    /// The kind the model returned decides it (house rule 7), through the
    /// default `isRerollable`, which the demo doesn't override: `questionKinds`
    /// lists `superlative`, so "what's the oldest thing I have" comes back as
    /// one and "what should I read tonight" as a pick, in any language. A host
    /// that can tell them apart from its tool's arguments, its rows or its
    /// payload as well overrides `isRerollable` to check.
    var rerollableKinds: Set<String> { [AskQuestionKind.pick] }

    /// The demo's one action, offered by its scripted answer about lending a
    /// book. There is no shelf behind it to change, so it keeps nothing and
    /// says what a host would have done.
    func perform(_ proposal: AskProposal) async throws -> String? {
        guard let id = proposal.payload(as: String.self),
              let row = DemoRow.all.first(where: { $0.id == id }) else {
            throw AskProposalFailure(line: "That isn't on the shelf any more.")
        }
        return "Marked \(row.displayTitle) as lent."
    }

    var brand: AskBrand {
        AskBrand(
            title: "Ask the Demo",
            appDirectory: "AskKitDemo",
            logSubsystem: "com.example.askkitdemo",
            help: "Ask about your things",
            firstScreenHeadline: "Ask about your things",
            firstScreenSentence: "Books, records, tools and clothes — thirty of them, made up for this demo.",
            nothingToAskCopy: "Nothing to ask about yet.",
            nothingToAskActionLabel: Self.offersFirstItem ? "Add Your First Item" : nil,
            disclosureSentence: "Questions are answered on this device.",
            scopeCaveat: "Ask reads only what you own — it can't search the web, and it can be wrong."
        )
    }

    /// `DemoLaunchArgument.emptyLibrary`: the overview reads as empty, so
    /// the first screen is the nothing-to-ask one.
    static var ownsNothing: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.emptyLibrary)
    }

    /// `DemoLaunchArgument.emptyLibrary` with `button` after it: the
    /// nothing-to-ask screen has its button. The brand's label and the
    /// screen's action (`ContentView`) both read this, since the button
    /// shows only with both.
    static var offersFirstItem: Bool {
        DemoLaunchArgument.value(after: DemoLaunchArgument.emptyLibrary) == "button"
    }

    func overview() async -> AskOverview {
        if Self.ownsNothing { return .empty }
        let counts = Dictionary(grouping: DemoRow.all, by: \.kind)
        return AskOverview(
            scopes: DemoRow.Kind.allCases.compactMap { kind in
                guard let rows = counts[kind], !rows.isEmpty else { return nil }
                return AskOverview.Scope(id: kind.rawValue, name: kind.scope, count: rows.count)
            },
            total: DemoRow.all.count
        )
    }

    func makeTools(_ context: AskToolContext<DemoRow>) -> [any Tool] {
        [DemoSearchTool(context: context)]
    }

    /// Three sentences, and a fourth with an answer language: short, as house
    /// rule 3 asks (`AskDomain.instructions(tier:isConversation:answerLanguage:)`
    /// has the measurement). Every category and activity mapping that would
    /// have gone here lives in the tool's `@Guide`s instead. `isConversation`
    /// is unused here: the demo registers one tool and registers it always,
    /// so there is nothing for a one-shot to narrow.
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        var text = """
            You answer questions about the things one person owns, and about nothing else.
            Call search_my_things before you answer, and name only titles it returned.
            Answer in two or three sentences of plain prose, with no headings and no lists.
            """
        if let answerLanguage { text += "\nWrite the answer in \(answerLanguage)." }
        return text
    }

    /// Byte-stable: no date, no counts, nothing that moves between the warm
    /// session and the turn that consumes it. A single changed byte throws away
    /// the KV cache `prewarm` paid for.
    var promptPrefix: String { "Answer a question about one person's own things.\n" }

    func promptLines(question: String, overview: AskOverview) async -> [String] {
        var lines = ["Now: \(Date.now.formatted(date: .abbreviated, time: .shortened))"]
        let owned = overview.byCount.map { "\($0.count) \($0.name)" }.joined(separator: ", ")
        lines.append("They own: \(owned).")
        return lines
    }

    var searchPlanInstructions: String {
        """
        Choose the search that would find what the question is about.
        Give a short literal query, and a kind only when the question is clearly about one.
        """
    }

    /// The tool's own call (`DemoSearchTool`), so the grounded retry records
    /// what the tool would have, and its wait row hears what it hears from
    /// the tool: the search, the finish, then what it read. One body, not a
    /// copy of it, so the two can't drift on what they record.
    func search(_ arguments: DemoSearchArguments, context: AskToolContext<DemoRow>) async throws -> String {
        try await DemoSearchTool(context: context).call(arguments: arguments)
    }

    /// Named from what the reader actually owns, largest shelf first — a
    /// starter that names an empty shelf is a question with no answer.
    func starters(overview: AskOverview, window: Int) -> [AskStarter] {
        let byScope = overview.byCount.prefix(window).map { scope in
            AskStarter(id: "own.\(scope.id)", text: "What \(scope.name) do I own?")
        }
        return byScope + [
            AskStarter(id: "oldest", text: "What's the oldest thing I have?"),
            AskStarter(id: "count", text: "How many things do I own in total?")
        ]
    }

    /// None of the wait row's words are the demo's own: every event keeps
    /// AskUI's default, which is translated into all 25 of AskKit's languages.
    /// The demo carries no catalog to translate a line of its own into, so an
    /// English one here would put English in the middle of a translated wait
    /// row. A host returns its line resolved against its own bundle, for the
    /// events it has better words for (`AskDomain.phrase(for:)`).
    func phrase(for activity: AskActivity) -> String? { nil }

    func referent(from answer: AskAnswer<DemoRow>) -> [String] {
        answer.tiles.isEmpty ? answer.mentioned.map(\.displayTitle) : answer.tiles.map(\.displayTitle)
    }
}

// MARK: - The eval

extension DemoDomain {
    /// What "Run Ask eval on this device" puts through the real engine.
    ///
    /// Shapes, never prose: whether the turn read anything, what kind of
    /// question it decided this was, whether it named something it never read.
    /// Five, because n ≥ 5 is what a prompt change has to beat.
    static let scenarios: [AskScenario] = [
        AskScenario(id: "which-records", question: "Which records do I own?",
                    expectedKinds: [AskQuestionKind.everyMatch],
                    expectedTitles: ["Kind of Blue", "Rumours"]),
        AskScenario(id: "count", question: "How many things do I own in total?",
                    expectsNoTiles: true),
        AskScenario(id: "oldest", question: "What's the oldest thing I have?",
                    expectedKinds: [AskQuestionKind.superlative],
                    expectedTitles: ["...And Then There Were None"]),
        AskScenario(id: "two-letter", question: "Do I own a book called Go?",
                    expectedTitles: ["Go"]),
        AskScenario(id: "ungrounded", question: "What's the capital of Portugal?")
    ]
}
