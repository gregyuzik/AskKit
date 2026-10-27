import Foundation
import Testing

@testable import AskCore

/// Where the thread, the earlier chats and the feedback attachments are kept.
///
/// These paths are a contract with every install already on disk: a thread one
/// build saved has to be where the next build looks. The expectations are
/// joined as plain strings rather than with `URL`'s own calls
/// (`appending(path:)`, or the soft-deprecated `appendingPathComponent`), so a
/// pin can't pass by agreeing with the code it pins.
@Suite(.timeLimit(.minutes(1))) struct AskPersistedLocationTests {

    nonisolated private struct Row: AskRow {
        let id: String
        let displayTitle: String

        init(_ title: String) {
            id = title
            displayTitle = title
        }
    }

    /// `Application Support`, as a path with no trailing slash.
    private func supportPath() throws -> String {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        return trimmed(support.path(percentEncoded: false))
    }

    /// A folder's URL may end in a slash and a file's never does, so folders
    /// are compared without one: where the files land is the contract, not
    /// how the URL spells its last component.
    private func trimmed(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func scratchDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "askkit-locations-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func chat(_ question: String) -> [AskThreadEntry<Row>] {
        [AskThreadEntry(
            question: question,
            text: "Answered.",
            answer: AskAnswer(text: "Answered.", matches: [Row("Rumours")]),
            tier: .privateCloud,
            askedAt: Date(timeIntervalSince1970: 1_000_000)
        )]
    }

    @Test func theThreadIsAskThreadJSONInTheAppsFolder() throws {
        let url = try #require(AskThreadStore<Row>.defaultURL(appDirectory: "AskKitDemo"))
        #expect(url.isFileURL)
        #expect(url.path(percentEncoded: false) == "\(try supportPath())/AskKitDemo/ask-thread.json")
    }

    /// A folder name with a space is percent-encoded in the URL, and has to
    /// come back as written in the path.
    @Test func aFolderNameIsKeptAsWritten() throws {
        let url = try #require(AskThreadStore<Row>.defaultURL(appDirectory: "Ask Kit"))
        #expect(url.path(percentEncoded: false) == "\(try supportPath())/Ask Kit/ask-thread.json")
    }

    /// A name that isn't one folder under Application Support would put the
    /// thread, the earlier chats and the feedback in Application Support
    /// itself or outside it, beside other apps' files, and Delete All Chats
    /// would delete whatever `threads/` it found there.
    @Test func aFolderNameThatIsNotOneFolderLocatesNothing() {
        for name in ["", ".", "..", "../Elsewhere", "Ask/..", "Ask/Kit", "/", "Ask\u{0}"] {
            #expect(AskThreadStore<Row>.defaultURL(appDirectory: name) == nil, "\(name.debugDescription)")
            #expect(AskThreadArchive<Row>.defaultDirectory(appDirectory: name) == nil, "\(name.debugDescription)")
            #expect(AskFeedbackAttachments.defaultDirectory(appDirectory: name) == nil, "\(name.debugDescription)")
        }
    }

    /// Built from such a name, each keeps nothing anywhere: no write lands,
    /// no read finds anything, and Delete All Chats deletes nothing.
    @Test func storesOverAFolderNameThatIsNotOneFolderReadAndWriteNothing() async {
        #expect(!AskBrand.isOneFolder(".."))
        let thread = AskThreadStore<Row>(appDirectory: "..")
        #expect(thread.fileURL == nil)
        #expect(await thread.save(chat("Which records do I own?")) == false)
        guard case .empty = await thread.load() else {
            Issue.record("a store with no folder read something")
            return
        }
        let archive = AskThreadArchive<Row>(appDirectory: "")
        #expect(await archive.archive(chat("Which records do I own?")) == nil)
        #expect(await archive.summaries().isEmpty)
        #expect(await archive.removeAll())
        let attachments = AskFeedbackAttachments(appDirectory: "Ask/..")
        #expect(await attachments.save(Data("{}".utf8), sentiment: .positive) == nil)
        #expect(await attachments.urls().isEmpty)
    }

    @Test func aDottedFolderNameIsOneFolder() throws {
        let url = try #require(AskThreadStore<Row>.defaultURL(appDirectory: "com.example.Ask"))
        #expect(url.path(percentEncoded: false) == "\(try supportPath())/com.example.Ask/ask-thread.json")
    }

    @Test func theEarlierChatsAreInThreadsBesideIt() throws {
        let directory = try #require(AskThreadArchive<Row>.defaultDirectory(appDirectory: "AskKitDemo"))
        #expect(trimmed(directory.path(percentEncoded: false)) == "\(try supportPath())/AskKitDemo/threads")
    }

    @Test func theFeedbackAttachmentsAreInFeedbackBesideIt() throws {
        let directory = try #require(AskFeedbackAttachments.defaultDirectory(appDirectory: "AskKitDemo"))
        #expect(trimmed(directory.path(percentEncoded: false)) == "\(try supportPath())/AskKitDemo/feedback")
    }

    @Test func aFiledChatIsNamedForItsIDBesideIndexJSON() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = AskThreadArchive<Row>(appDirectory: "unused", directory: directory)

        let summary = try #require(await archive.archive(chat("Which records do I own?")))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names.sorted() == ["\(summary.id.uuidString).json", "index.json"].sorted())
    }

    @Test func anAttachmentIsNamedForItsSecondAndItsVerdict() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachments = AskFeedbackAttachments(appDirectory: "unused", directory: directory)

        let url = try #require(await attachments.save(
            Data("{}".utf8), sentiment: .negative, at: Date(timeIntervalSince1970: 1_750_000_000)
        ))

        let expected = "\(trimmed(directory.path(percentEncoded: false)))/feedback-1750000000-negative.json"
        #expect(url.path(percentEncoded: false) == expected)
        #expect(await attachments.urls().map { $0.path(percentEncoded: false) } == [expected])
    }

    /// The second in a second takes the next number, whatever its verdict.
    @Test func aLaterAttachmentInTheSameSecondIsNumbered() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attachments = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let second = Date(timeIntervalSince1970: 1_750_000_000)
        await attachments.save(Data("{}".utf8), sentiment: .negative, at: second)

        let url = try #require(await attachments.save(Data("{}".utf8), sentiment: .positive, at: second))
        #expect(url.lastPathComponent == "feedback-1750000000.2-positive.json")
    }

    /// A thread set aside, by New Chat or as one this build can make nothing
    /// of, lies beside the thread's place, where a later launch looks for it
    /// (`AskThreadStore.recoverSetAside`).
    @Test func aThreadSetAsideIsNamedForTheThreadAndAnID() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let thread = URL(filePath: "\(trimmed(directory.path(percentEncoded: false)))/ask-thread.json")
        try Data("not a thread".utf8).write(to: thread)

        #expect(await AskThreadStore<Row>(appDirectory: "unused", url: thread).setAsideIfNotAThread())

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(names.count == 1)
        let aside = try #require(names.first)
        #expect(aside.hasPrefix("ask-thread-unreadable-"))
        #expect(aside.hasSuffix(".json"))
        #expect(UUID(uuidString: String(aside.dropFirst("ask-thread-unreadable-".count).dropLast(".json".count))) != nil)
    }

    /// A thread this build reads only in part keeps its original beside it,
    /// where a later launch looks for it.
    @Test func aThreadReadInPartKeepsItsOriginalBesideIt() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let thread = URL(filePath: "\(trimmed(directory.path(percentEncoded: false)))/ask-thread.json")
        try Data(#"[{"question":"kept"},{"question":1}]"#.utf8).write(to: thread)

        _ = await AskThreadStore<Row>(appDirectory: "unused", url: thread).load()

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let originals = names.filter { $0 != "ask-thread.json" }
        #expect(originals.count == 1)
        let original = try #require(originals.first)
        #expect(original.hasPrefix("ask-thread-original-"))
        #expect(original.hasSuffix(".json"))
        #expect(UUID(uuidString: String(original.dropFirst("ask-thread-original-".count).dropLast(".json".count))) != nil)
    }
}
