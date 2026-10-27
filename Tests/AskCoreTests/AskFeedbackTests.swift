#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Synchronization
import Testing

@testable import AskCore

/// A reader's thumbs: the line it logs, the attachments it keeps, and the
/// verdict the thread remembers.
@Suite(.timeLimit(.minutes(1))) struct AskFeedbackTests {

    private func verdict(_ sentiment: AskFeedback.Sentiment = .negative, truncated: Bool = false) -> AskFeedback {
        AskFeedback(
            sentiment: sentiment, tier: .privateCloud, questionKind: AskQuestionKind.pick,
            tilesShown: 1, rowsRead: 12, wasTruncated: truncated
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "askkit-feedback-\(UUID().uuidString)")
    }

    // MARK: - The log

    @Test func theLineIsTheTurnsShapeAndNeverItsWords() {
        #expect(verdict().line == "[feedback] negative tier=privateCloud kind=\(AskQuestionKind.pick) tiles=1 rows=12")
        #expect(verdict(.positive, truncated: true).line.hasSuffix("rows=12 truncated"))
    }

    @Test func aSinkThatWritesOnlyRoutingLinesStillHearsVerdicts() {
        let sink = RoutingOnlySink()
        sink.feedback(verdict())
        #expect(sink.lines.withLock { $0 } == [verdict().line])
    }

    // MARK: - Kept attachments

    @Test func attachmentsAreKeptNewestFirst() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        await store.save(Data("old".utf8), sentiment: .positive, at: start)
        await store.save(Data("new".utf8), sentiment: .negative, at: start.addingTimeInterval(60))

        let urls = await store.urls()
        #expect(urls.map(\.lastPathComponent) == [
            "feedback-1780000060-negative.json", "feedback-1780000000-positive.json"
        ])
        let newest = try #require(urls.first)
        #expect(try Data(contentsOf: newest) == Data("new".utf8))
    }

    @Test func onlyTheNewestAttachmentsAreKept() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        for index in 0..<(AskFeedbackAttachments.maxKept + 2) {
            await store.save(Data("\(index)".utf8), sentiment: .positive, at: start.addingTimeInterval(Double(index)))
        }
        let urls = await store.urls()
        #expect(urls.count == AskFeedbackAttachments.maxKept)
        #expect(urls.last?.lastPathComponent == "feedback-1780000002-positive.json")
    }

    @Test func twoVerdictsOfOneKindInOneSecondAreBothKeptTheLaterFirst() async throws {
        // Names are to the second, and the write is atomic: a second verdict
        // of the same kind within it must not take the first one's name, or
        // the write replaces the first.
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let second = Date(timeIntervalSince1970: 1_780_000_000)
        for (index, offset) in [0.0, 0.3, 0.6].enumerated() {
            await store.save(Data("\(index)".utf8), sentiment: .negative, at: second.addingTimeInterval(offset))
        }

        let kept = try await store.urls().map { try Data(contentsOf: $0) }
        #expect(kept == ["2", "1", "0"].map { Data($0.utf8) })
    }

    @Test func aTenthVerdictInOneSecondIsNewerThanTheNinth() async throws {
        // As plain strings `.10-` sorts before `.9-`, and the prune would keep
        // the wrong ten.
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let second = Date(timeIntervalSince1970: 1_780_000_000)
        for index in 0...AskFeedbackAttachments.maxKept {
            await store.save(Data("\(index)".utf8), sentiment: .negative, at: second.addingTimeInterval(Double(index) / 100))
        }

        let kept = try await store.urls().map { try Data(contentsOf: $0) }
        #expect(kept == (1...AskFeedbackAttachments.maxKept).reversed().map { Data("\($0)".utf8) })
    }

    @Test func aThumbsDownAfterAThumbsUpInOneSecondIsTheNewer() async throws {
        // Not by the verdict's name: "negative" sorts before "positive".
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let second = Date(timeIntervalSince1970: 1_780_000_000)
        await store.save(Data("up".utf8), sentiment: .positive, at: second)
        await store.save(Data("down".utf8), sentiment: .negative, at: second.addingTimeInterval(0.5))

        let kept = try await store.urls().map { try Data(contentsOf: $0) }
        #expect(kept == ["down", "up"].map { Data($0.utf8) })
    }

    @Test func namesAnEarlierBuildWroteStillSortByAge() async throws {
        // Each verdict numbered its own names then, unpadded.
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in [
            ("feedback-1779999999-positive.json", "earlier"),
            ("feedback-1780000000-negative.json", "1"),
            ("feedback-1780000000.9-negative.json", "9"),
            ("feedback-1780000000.10-negative.json", "10")
        ] {
            try Data(contents.utf8).write(to: directory.appending(path: name))
        }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let url = try #require(await store.save(Data("11".utf8), sentiment: .positive, at: Date(timeIntervalSince1970: 1_780_000_000)))
        #expect(url.lastPathComponent == "feedback-1780000000.11-positive.json")

        let kept = try await store.urls().map { try Data(contentsOf: $0) }
        #expect(kept == ["11", "10", "9", "1", "earlier"].map { Data($0.utf8) })
    }

    @Test func removingEveryAttachmentSaysWhetherTheyAreGone() async throws {
        let directory = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: directory)
        }
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        #expect(await store.removeAll())
        _ = try #require(await store.save(Data("{}".utf8), sentiment: .negative))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path(percentEncoded: false))

        #expect(await !store.removeAll())
        #expect(await store.urls().count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false))
        #expect(await store.removeAll())
        #expect(await store.urls().isEmpty)
    }

    @Test func aDirectoryWithNothingKeptListsNothing() async {
        let store = AskFeedbackAttachments(appDirectory: "unused", directory: temporaryDirectory())
        #expect(await store.urls().isEmpty)
    }

    // MARK: - The thread remembers

    @Test func aVerdictIsSavedWithItsTurn() async {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "askkit-verdict-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([
            AskThreadEntry(
                question: "q", text: "a",
                answer: AskAnswer(text: "a", matches: [FakeRow("Rumours")]),
                feedback: .positive
            )
        ])
        #expect(await store.load().entries.first?.feedback == .positive)
    }

    @Test func aTurnSavedBeforeVerdictsDecodesWithNone() throws {
        let entry = try JSONDecoder().decode(
            AskThreadEntry<FakeRow>.self, from: Data(#"{"question":"q","text":"a"}"#.utf8)
        )
        #expect(entry.feedback == nil)
    }

    @Test func aVerdictANewerBuildWroteCostsTheVerdictAndNotTheTurn() throws {
        let entry = try JSONDecoder().decode(
            AskThreadEntry<FakeRow>.self, from: Data(#"{"question":"q","text":"a","feedback":"meh"}"#.utf8)
        )
        #expect(entry.question == "q")
        #expect(entry.feedback == nil)
    }
}

/// A sink that implements `turn`, `routing` and `discard`, and leaves
/// `feedback(_:)` to its default, as a sink a host already bridges does.
nonisolated private final class RoutingOnlySink: AskLogSink, Sendable {
    let lines = Mutex<[String]>([])

    func turn(_ stats: AskTurnStats) {}
    func routing(_ line: String) { lines.withLock { $0.append(line) } }
    func discard(_ discard: AskDiscard) {}
}

#endif
