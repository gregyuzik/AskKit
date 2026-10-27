// README.md's Adopt section shows this file's code word for word, and
// scripts/check-readme-sample.py fails when its copy differs, so the two change
// together.
#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels

/// One book on the reader's shelf. Every type here is `nonisolated`, because
/// AskKit uses them off the main actor.
nonisolated struct Book: AskRow {
    let id: String
    let title: String
    let author: String

    var displayTitle: String { title }

    /// Stands in for the app's own store.
    static let shelf = [
        Book(id: "b1", title: "The Dispossessed", author: "Ursula K. Le Guin"),
        Book(id: "b2", title: "Housekeeping", author: "Marilynne Robinson"),
        Book(id: "b3", title: "A Pattern Language", author: "Christopher Alexander")
    ]
}

/// The search's arguments: the model fills them in, or the app for the grounded retry.
@Generable
nonisolated struct BookQuery: Sendable {
    @Guide(description: "Words from the question: a title or an author. Short and literal.")
    var words: String
}

/// The one lookup: the model's tool, and the grounded retry's search.
nonisolated struct SearchBooks: Tool {
    let name = "search_books"
    let description = "Search the reader's books by any words from the question. Call this before answering anything about what they own."

    let context: AskToolContext<Book>

    // `@concurrent`, or the lookup runs on its caller's actor.
    @concurrent func call(arguments: BookQuery) async throws -> String {
        // Notes the call, finishes it however the lookup ends, then reports what it read.
        await context.withToolCall(.searching(scope: nil)) { collector in
            let words = arguments.words.split(whereSeparator: { !$0.isLetter }).map(String.init)
            let found = Book.shelf.filter { book in
                // Ignores case and accents, so "garcia marquez" finds "García Márquez".
                let text = "\(book.title) \(book.author)"
                return words.contains { text.localizedStandardContains($0) }
            }
            let shown = Array(found.prefix(context.rowLimit))
            // An answer's tiles resolve only against recorded rows.
            await collector.record(rows: shown)
            return (Self.render(shown, of: found.count), report: .reading(shown: shown.count, total: found.count, scope: nil))
        }
    }

    // Every field clamped, so none can spell a tag to the model, and no fence of its own.
    private static func render(_ shown: [Book], of total: Int) -> String {
        guard !shown.isEmpty else { return "No matches." }
        var lines = shown.map { "\(AskPrompt.clamp($0.title, AskPrompt.shortClamp)) | \(AskPrompt.clamp($0.author, AskPrompt.shortClamp))" }
        if total > shown.count { lines.append("(+\(total - shown.count) more not shown)") }
        return lines.joined(separator: "\n")
    }
}

/// Everything about Ask that is this app's rather than AskKit's.
nonisolated struct LibraryDomain: AskDomain {
    typealias Row = Book
    typealias SearchArguments = BookQuery

    let brand = AskBrand(
        title: "Ask My Library",
        shortLabel: "Ask",
        appDirectory: "MyLibrary",
        logSubsystem: "com.example.mylibrary",
        help: "Ask about your books",
        firstScreenHeadline: "Ask about your books",
        firstScreenSentence: "Find, count and compare what is on your shelves.",
        nothingToAskCopy: "Add a book to start asking.",
        disclosureSentence: "Questions are answered on this device.",
        scopeCaveat: "Ask reads only your library. It can't search the web, and it can be wrong."
    )

    func overview() async -> AskOverview {
        let count = Book.shelf.count
        return AskOverview(scopes: [AskOverview.Scope(id: "books", name: "books", count: count)], total: count)
    }

    func makeTools(_ context: AskToolContext<Book>) -> [any Tool] {
        [SearchBooks(context: context)]
    }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        var text = """
            You answer questions about the books one person owns, and about nothing else.
            Call search_books before you answer, and name only titles it returned.
            """
        if let answerLanguage { text += "\nWrite the answer in \(answerLanguage)." }
        return text
    }

    func search(_ arguments: BookQuery, context: AskToolContext<Book>) async throws -> String {
        try await SearchBooks(context: context).call(arguments: arguments)
    }

    // Optional. Without it the first screen has its copy and the composer, and no chips.
    func starters(overview: AskOverview, window: Int) -> [AskStarter] {
        [AskStarter(text: "How many books do I own?"), AskStarter(text: "Which of my books is by Ursula K. Le Guin?")]
    }
}

#endif

// Steps 2 to 4, where AskUI draws: iOS, macOS and visionOS. A block of its own,
// so its imports are a host file's: AskCore as well as AskUI, which doesn't
// re-export it.
#if canImport(FoundationModels) && (os(iOS) || os(macOS) || os(visionOS))

import AskCore
import AskUI
import SwiftUI

/// The one Ask, owned by the app and not by a view, so the thread outlives every view.
@MainActor
final class LibraryAsk {
    let store: AskConversationStore<LibraryDomain>

    init() {
        let domain = LibraryDomain()
        // `.declared` only if the entitlements file holds Private Cloud Compute's.
        let seam = AppleModelSeam.make(privateCloudCompute: .undeclared)
        let engine = AskEngine(domain: domain, seam: seam)
        store = AskConversationStore(domain: domain, engine: engine)
    }
}

/// The screen in a navigation stack, titled with the brand's title.
struct AskTab: View {
    let ask: LibraryAsk

    var body: some View {
        NavigationStack {
            AskScreen(store: ask.store)
                .navigationTitle(ask.store.brand.title)
        }
    }
}

#endif

#if canImport(FoundationModels) && !os(tvOS)

// MARK: - The test, which README.md doesn't show

import Testing

/// The README's domain, asked what the engine asks of it. Its wiring is compiled
/// here and not built: `AppleModelSeam.make` asks the system for its models,
/// which no test does.
@Suite(.timeLimit(.minutes(1))) struct ReadmeDomainTests {
    @MainActor
    @Test func theReadmesDomainAnswersWhatTheEngineAsksOfIt() async throws {
        let domain = LibraryDomain()
        let overview = await domain.overview()
        #expect(overview.total == 3)
        #expect(domain.starters(overview: overview, window: 3).count == 2)
        let instructions = domain.instructions(tier: .onDevice, isConversation: true, answerLanguage: "French")
        #expect(instructions.contains("search_books"))
        #expect(instructions.hasSuffix("Write the answer in French."))

        // The search the grounded retry runs, through the context the engine
        // builds for it: what it read lands in the collector, and what the
        // model is shown is clamped, with no fence of the tool's own.
        let collector = AskCollector<Book>()
        let context = AskToolContext(
            collector: collector, relay: AskActivityRelay(),
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        let reply = try await domain.search(BookQuery(words: "pattern"), context: context)
        #expect(reply == "A Pattern Language | Christopher Alexander")
        #expect(await collector.rows == [Book.shelf[2]])
        #expect(await collector.toolCallCount == 1)

        // A limit under the matches says so, and records only what it shows.
        // A miss says that.
        let capped = AskCollector<Book>()
        let cappedContext = AskToolContext(
            collector: capped, relay: AskActivityRelay(),
            rowLimit: 1, tier: .onDevice, isConversation: true
        )
        let some = try await domain.search(BookQuery(words: "the language ursula"), context: cappedContext)
        #expect(some == "The Dispossessed | Ursula K. Le Guin\n(+1 more not shown)")
        #expect(await capped.rows == [Book.shelf[0]])
        #expect(try await domain.search(BookQuery(words: "xyzzy"), context: cappedContext) == "No matches.")

        // The words match whatever their case and accents.
        #expect(try await domain.search(BookQuery(words: "GUÍN"), context: cappedContext) == "The Dispossessed | Ursula K. Le Guin")
    }
}

#endif
