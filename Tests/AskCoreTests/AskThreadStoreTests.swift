#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Testing

@testable import AskCore

@Suite(.timeLimit(.minutes(1))) struct AskThreadStoreTests {
    typealias Entry = AskThreadEntry<FakeRow>

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "askkit-thread-\(UUID().uuidString).json")
    }

    private func entry(_ question: String) -> Entry {
        Entry(
            question: question, text: "answer to \(question)",
            answer: AskAnswer(text: "answer to \(question)", matches: [FakeRow("Rumours")]),
            tier: .privateCloud, askedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    @Test func roundTripsAThread() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one"), entry("two")])
        let loaded = await store.load().entries
        #expect(loaded.count == 2)
        #expect(loaded.first?.question == "one")
        #expect(loaded.first?.tier == .privateCloud)
    }

    @Test func aCorruptFileReadsAsUnreadableAndNotAsAnEmptyThread() async {
        // The distinction this whole type exists for. "No thread" and "there is
        // a thread I could not read" want opposite behaviour from the caller,
        // and an array cannot tell them apart: read as empty, a failed read
        // would be written over by the next answer.
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("{not json".utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        guard case .unreadable = await store.load() else {
            Issue.record("a file that is there and does not parse is not an empty thread")
            return
        }
    }

    @Test func aMissingFileReadsAsEmpty() async {
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: temporaryURL())
        guard case .empty = await store.load() else {
            Issue.record("no file is an empty thread, not a failure")
            return
        }
    }

    @Test func oneUndecodableTurnCostsThatTurnAndNotTheThread() async throws {
        // A `Row` a host evolved past — the layer AskKit does not control.
        // Decoded as one value, the array would throw with that entry, and the
        // reader would lose every turn they had.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let json = """
        [{"question":"first","text":"a","failureIsRetryable":false,"stopped":false,"summarizedBefore":false},
         {"question":12345},
         {"question":"third","text":"c","failureIsRetryable":false,"stopped":false,"summarizedBefore":false}]
        """
        try Data(json.utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        guard case .thread(let entries, let dropped) = await store.load() else {
            Issue.record("a thread with one bad entry is still a thread")
            return
        }
        #expect(entries.map(\.question) == ["first", "third"])
        #expect(dropped == 1)
    }

    @Test func theThreadIsCappedSoTheFileCannotGrowWithoutBound() async {
        // Every entry embeds the rows behind its answer, up to
        // `maxTurnRows`, or `maxThreadRows` for a follow-up that read none, so
        // the turn count is the dimension left to cap.
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let cap = AskThreadStore<FakeRow>.maxPersistedTurns
        await store.save((0..<(cap + 10)).map { entry("q\($0)") })
        let loaded = await store.load().entries
        #expect(loaded.count == cap)
        // The OLDEST go: what the reader just asked has to survive.
        #expect(loaded.last?.question == "q\(cap + 9)")
    }

    @Test func savingAnEmptyThreadRemovesTheFile() async {
        let url = temporaryURL()
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one")])
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        await store.save([])
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func clearForgetsTheThread() async {
        let url = temporaryURL()
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one")])
        await store.clear()
        #expect(await store.load().entries.isEmpty)
    }

    @Test func decodesAThreadWrittenBeforeAnyOptionalFieldExisted() async throws {
        // The synthesized decoder throws on a missing key, and `load` drops an
        // entry that throws: every turn written before a field existed would be
        // dropped, and every reader's chat would empty on the first launch
        // after the update that added it.
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"[{"question":"what did I own?"}]"#
        try Data(json.utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let loaded = await store.load().entries
        #expect(loaded.count == 1)
        let entry = try #require(loaded.first)
        #expect(entry.question == "what did I own?")
        #expect(entry.text.isEmpty)
        #expect(entry.answer == nil)
        #expect(entry.failureMessage == nil)
        #expect(entry.failureIsRetryable == false)
        #expect(entry.stopped == false)
        #expect(entry.tier == nil)
        #expect(entry.askedAt == nil)
        #expect(entry.summarizedBefore == false)
        #expect(entry.photo == nil)
        #expect(entry.answerSawPhoto == false)
    }

    @Test func aFailedTurnKeepsItsPartialProse() async {
        // Nothing the thread has shown is taken back: a failure renders beneath
        // what was already said.
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let failed = Entry(
            question: "q", text: "as far as it got", answer: nil,
            failureMessage: "Couldn't answer that just now.", failureIsRetryable: true
        )
        await store.save([failed])
        let loaded = await store.load().entries
        #expect(loaded.first?.text == "as far as it got")
        #expect(loaded.first?.failureIsRetryable == true)
    }

    @Test func theSummarizedMarkerSurvivesTheRoundTrip() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([Entry(question: "q", text: "t", answer: nil, summarizedBefore: true)])
        #expect(await store.load().entries.first?.summarizedBefore == true)
    }

    @Test func aPhotoSurvivesTheRoundTripAsItsLabelAndReference() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let photo = AskQuestionPhoto(label: "Blue record sleeve", reference: "asset-1")
        await store.save([Entry(question: "q", text: "t", answer: nil, photo: photo, answerSawPhoto: true)])
        let loaded = await store.load().entries.first
        #expect(loaded?.photo == photo)
        #expect(loaded?.answerSawPhoto == true)
    }

    @Test func aTierThisBuildDoesNotKnowCostsTheCaptionAndNotTheTurn() throws {
        // A newer build may answer on a tier this one has no case for. The
        // turn is the reader's either way.
        let entry = try JSONDecoder().decode(
            Entry.self, from: Data(#"{"question":"q","text":"a","tier":"quantum"}"#.utf8)
        )
        #expect(entry.question == "q")
        #expect(entry.text == "a")
        #expect(entry.tier == nil)
    }

    @Test func aPhotoThisBuildCannotReadCostsThePhotoAndNotTheTurn() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"[{"question":"which record is this?","photo":{"label":12},"answerSawPhoto":true}]"#
        try Data(json.utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let entry = try #require(await store.load().entries.first)
        #expect(entry.question == "which record is this?")
        #expect(entry.photo == nil)
        #expect(entry.answerSawPhoto)
    }

    // MARK: - A thread that couldn't be read

    /// A private folder holding the thread, for the tests that look beside it:
    /// a thread set aside lands next to it.
    private func temporaryFolder() throws -> (folder: URL, thread: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "askkit-thread-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appending(path: "ask-thread.json"))
    }

    private func setAsideFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("ask-thread-unreadable-") && $0.hasSuffix(".json") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    private func originalFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("ask-thread-original-") && $0.hasSuffix(".json") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    private func archive(in folder: URL) -> AskThreadArchive<FakeRow> {
        AskThreadArchive<FakeRow>(appDirectory: "unused", directory: folder.appending(path: "threads", directoryHint: .isDirectory))
    }

    /// A turn asked at `seconds` past the reference date, the way `askedAt`
    /// is written.
    private func dated(_ question: String, _ seconds: Double) -> Entry {
        Entry(question: question, text: "answer to \(question)", answer: nil, askedAt: Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// Three turns, the second one written by a build this one can't read:
    /// its question isn't a string.
    private var partialThread: Data {
        Data("""
        [{"question":"first","text":"answer to first","askedAt":1000},
         {"question":12345,"askedAt":2000},
         {"question":"third","text":"answer to third","askedAt":3000}]
        """.utf8)
    }

    /// The three turns as a build that reads all of them would.
    private var wholeThread: [Entry] {
        [dated("first", 1000), dated("second", 2000), dated("third", 3000)]
    }

    private func setAside(_ data: Data, in folder: URL) throws -> URL {
        let file = folder.appending(path: "ask-thread-unreadable-\(UUID().uuidString).json")
        try data.write(to: file)
        return file
    }

    // MARK: - Turns that don't decode

    @Test func aThreadNoneOfWhoseTurnsDecodeIsUnreadableAndNeverEmpty() async throws {
        // Read as an empty thread, the next answer would write a one-turn
        // thread over every turn a later build could read.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data(#"[{"question":1},{"question":2}]"#.utf8)
        try bytes.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)

        guard case .unreadable = await store.load() else {
            Issue.record("a thread none of whose turns decode is not an empty thread")
            return
        }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(await store.setAsideIfNotAThread())
        #expect(try setAsideFiles(in: folder).map { try Data(contentsOf: $0) } == [bytes])
    }

    @Test func aThreadThatReadsInPartKeepsItsOriginalBesideIt() async throws {
        // What decoded is shown, and the next save writes only that. The
        // original, kept whole first, is what keeps the turn that didn't.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try partialThread.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)

        guard case .thread(let entries, let dropped) = await store.load() else {
            Issue.record("a thread with one turn this build can't read is still a thread")
            return
        }
        #expect(entries.map(\.question) == ["first", "third"])
        #expect(dropped == 1)
        #expect(try originalFiles(in: folder).map { try Data(contentsOf: $0) } == [partialThread])
        #expect(await !store.setAsideIfNotAThread())

        // Read again on a launch that wrote nothing: one original, not two.
        _ = await store.load()
        #expect(originalFiles(in: folder).count == 1)

        #expect(await store.save(entries + [dated("fourth", 4000)]))
        #expect(try originalFiles(in: folder).map { try Data(contentsOf: $0) } == [partialThread])
    }

    @Test func anOriginalThatStillReadsOnlyInPartStays() async throws {
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try partialThread.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        _ = await store.load()

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 0)
        #expect(await archive.summaries().isEmpty)
        #expect(try originalFiles(in: folder).map { try Data(contentsOf: $0) } == [partialThread])
    }

    @Test func anOriginalThatReadsWholeGoesBackIntoTheThread() async throws {
        // A later build reads the turn this one couldn't. The reader carried
        // on meanwhile, and keeps that too.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try partialThread.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let read = await store.load().entries
        #expect(await store.save(read + [dated("fourth", 4000)]))
        let original = try #require(originalFiles(in: folder).first)
        try JSONEncoder().encode(wholeThread).write(to: original)

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 1)
        #expect(await store.load().entries.map(\.question) == ["first", "second", "third", "fourth"])
        #expect(originalFiles(in: folder).isEmpty)
        #expect(await archive.summaries().isEmpty)
    }

    @Test func anOriginalWhoseChatWasFiledGoesBackIntoThatFiling() async throws {
        // New Chat filed what this build read. The filing is the chat now.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try partialThread.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let archive = archive(in: folder)
        let read = await store.load().entries
        let filed = try #require(await archive.archive(read + [dated("fourth", 4000)]))
        #expect(await store.clear())
        let original = try #require(originalFiles(in: folder).first)
        try JSONEncoder().encode(wholeThread).write(to: original)

        #expect(await store.recoverSetAside(into: archive) == 1)
        #expect(await archive.summaries().map(\.id) == [filed.id])
        #expect(await archive.entries(for: filed.id).entries.map(\.question) == ["first", "second", "third", "fourth"])
        #expect(originalFiles(in: folder).isEmpty)
    }

    @Test func anOriginalWhoseChatIsGoneGoesWithIt() async throws {
        // The reader deleted the chat it belongs to. Filed on its own, the
        // chat would come back.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try partialThread.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        let archive = archive(in: folder)
        let filed = try #require(await archive.archive(await store.load().entries))
        #expect(await store.clear())
        #expect(await archive.remove(filed.id))
        let original = try #require(originalFiles(in: folder).first)
        try JSONEncoder().encode(wholeThread).write(to: original)

        #expect(await store.recoverSetAside(into: archive) == 0)
        #expect(await archive.summaries().isEmpty)
        #expect(originalFiles(in: folder).isEmpty)
    }

    @Test func anUndatedOriginalWhoseChatCannotBeFoundIsFiledOnItsOwn() async throws {
        // Chats are found by date, so for a thread written before `askedAt`
        // existed, finding none doesn't mean the reader deleted it.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"[{"question":"first","text":"a"},{"question":2},{"question":"third","text":"c"}]"#.utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.load().entries.map(\.question) == ["first", "third"])
        #expect(await store.clear())
        let original = try #require(originalFiles(in: folder).first)
        let whole = ["first", "second", "third"].map { Entry(question: $0, text: "t", answer: nil) }
        try JSONEncoder().encode(whole).write(to: original)

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 1)
        #expect(await archive.summaries().map(\.turnCount) == [3])
        #expect(originalFiles(in: folder).isEmpty)
    }

    @Test func aThreadSetAsideNoneOfWhoseTurnsDecodeStaysSetAside() async throws {
        // Every turn dropping is a thread this build can't read, not an empty
        // one, and deleting it would lose what a later build could.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data(#"[{"question":1},{"question":2}]"#.utf8)
        let aside = try setAside(bytes, in: folder)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 0)
        #expect(await archive.summaries().isEmpty)
        #expect(try setAsideFiles(in: folder).map { try Data(contentsOf: $0) } == [bytes])
        #expect(setAsideFiles(in: folder) == [aside])
    }

    @Test func aThreadSetAsideThatReadsInPartIsFiledAsFarAsItReadsAndKeptWhole() async throws {
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try setAside(partialThread, in: folder)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 1)
        let filed = await archive.summaries()
        #expect(filed.map(\.title) == ["first"])
        #expect(filed.map(\.turnCount) == [2])
        #expect(setAsideFiles(in: folder).isEmpty)
        #expect(try originalFiles(in: folder).map { try Data(contentsOf: $0) } == [partialThread])
    }

    // MARK: - Writes that fail

    @Test func aSaveSaysWhetherTheThreadIsOnDisk() async throws {
        // A caller deletes or overwrites the other copy of these turns only
        // once they are on disk here.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notAFolder = folder.appending(path: "not-a-folder")
        try Data().write(to: notAFolder)
        let blocked = AskThreadStore<FakeRow>(appDirectory: "unused", url: notAFolder.appending(path: "ask-thread.json"))
        #expect(await !blocked.save([entry("one")]))

        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.save([entry("one")]))
        #expect(await store.load().entries.map(\.question) == ["one"])
    }

    @Test func aSaveAfterTheFolderIsRemovedMakesItAgain() async throws {
        // Made once and remembered, a folder removed while the app runs would
        // fail every save for the rest of the process.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.save([entry("one")]))
        try FileManager.default.removeItem(at: folder)

        #expect(await store.save([entry("two")]))
        #expect(await store.load().entries.map(\.question) == ["two"])
    }

    @Test func clearSaysWhetherTheThreadIsGone() async throws {
        let (folder, url) = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.clear())
        #expect(await store.save([entry("one")]))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))

        #expect(await !store.clear())
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        #expect(await store.clear())
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func removingTheThreadsSetAsideSaysWhetherTheyAreGone() async throws {
        let (folder, url) = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        _ = try setAside(Data("{not a thread".utf8), in: folder)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))

        #expect(await !store.removeEverySetAside().isEmpty)
        #expect(setAsideFiles(in: folder).count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        #expect(await store.removeEverySetAside().isEmpty)
        #expect(setAsideFiles(in: folder).isEmpty)
    }

    @Test func aRetryOfDeletingTheSetAsideRemovesOnlyWhatWasOwed() async throws {
        // Delete All Chats owes the files that wouldn't go by name. A file set
        // aside since, by a New Chat that couldn't file its chat, is the
        // reader's, and a retry leaves it.
        let (folder, url) = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        let owed = try setAside(Data("{not a thread".utf8), in: folder)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        let left = await store.removeEverySetAside()
        #expect(left == [owed.lastPathComponent])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        let since = try setAside(try JSONEncoder().encode([entry("Anything from 1969?")]), in: folder)
        let unrelated = folder.appending(path: "notes.json")
        try Data("{}".utf8).write(to: unrelated)

        #expect(await store.removeSetAside(named: left.union(["notes.json", "../ask-thread.json"])).isEmpty)
        #expect(setAsideFiles(in: folder) == [since], "the retry removed a file set aside after Delete All")
        #expect(FileManager.default.fileExists(atPath: unrelated.path(percentEncoded: false)))
        // A file already gone counts as forgotten.
        #expect(await store.removeSetAside(named: left).isEmpty)
    }

    @Test func aFileThatIsNotAThreadIsSetAsideWhole() async throws {
        // The next answer needs the thread's place, and this build can make
        // nothing of what is there. Moved, not deleted: a later build may.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let garbage = Data("{not a thread".utf8)
        try garbage.write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)

        #expect(await store.setAsideIfNotAThread())
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let aside = setAsideFiles(in: folder)
        #expect(aside.count == 1)
        #expect(try aside.first.map { try Data(contentsOf: $0) } == garbage)
        guard case .empty = await store.load() else {
            Issue.record("the place of a thread set aside is free for the next one")
            return
        }
    }

    @Test func aThreadThatCannotBeReadAtAllStaysWhereItIs() async throws {
        // A locked device makes a good thread unreadable for a while. Moved,
        // it would leave the reader's current chat for good.
        let (folder, url) = try temporaryFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one")])
        let written = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path(percentEncoded: false))

        guard case .unreadable = await store.load() else {
            Issue.record("a thread that can't be read is not an empty one")
            return
        }
        #expect(await !store.setAsideIfNotAThread())
        #expect(setAsideFiles(in: folder).isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
        #expect(try Data(contentsOf: url) == written)
    }

    @Test func aThreadThatReadsIsNeverSetAside() async throws {
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one")])
        #expect(await !store.setAsideIfNotAThread())
        #expect(await store.load().entries.map(\.question) == ["one"])
        #expect(setAsideFiles(in: folder).isEmpty)
    }

    @Test func endingAChatSetsAsideEvenAThreadThatCannotBeRead() async throws {
        // New Chat clears the thread's place either way. What couldn't be
        // read is kept rather than deleted, since it was never shown to be
        // worthless.
        let (folder, url) = try temporaryFolder()
        defer {
            for file in setAsideFiles(in: folder) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
            }
            try? FileManager.default.removeItem(at: folder)
        }
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        await store.save([entry("one")])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path(percentEncoded: false))

        #expect(await store.setAside())
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(setAsideFiles(in: folder).count == 1)
    }

    @Test func aThreadSetAsideThatReadsAgainIsFiledWithTheEarlierChats() async throws {
        // A newer build wrote it, say, or the device was locked when it was
        // read. Filed with the earlier chats, and gone from beside the thread.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{not a thread".utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.setAsideIfNotAThread())
        let aside = try #require(setAsideFiles(in: folder).first)
        try JSONEncoder().encode([entry("What do I own?")]).write(to: aside)

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 1)
        #expect(await archive.summaries().map(\.title) == ["What do I own?"])
        #expect(setAsideFiles(in: folder).isEmpty)
    }

    @Test func aThreadSetAsideThatStillWillNotReadStaysSetAside() async throws {
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{not a thread".utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.setAsideIfNotAThread())

        let archive = archive(in: folder)
        #expect(await store.recoverSetAside(into: archive) == 0)
        #expect(await archive.summaries().isEmpty)
        #expect(setAsideFiles(in: folder).count == 1)
    }

    @Test func aThreadSetAsideStaysUntilTheEarlierChatsHaveIt() async throws {
        // Filed first, removed after: an archive that can't be written to
        // leaves the thread where it was set aside, for the next launch.
        let (folder, url) = try temporaryFolder()
        let threads = folder.appending(path: "threads", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: threads.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        try Data("{not a thread".utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.setAsideIfNotAThread())
        let aside = try #require(setAsideFiles(in: folder).first)
        try JSONEncoder().encode([entry("What do I own?")]).write(to: aside)
        try FileManager.default.createDirectory(at: threads, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: threads.path(percentEncoded: false))

        #expect(await store.recoverSetAside(into: archive(in: folder)) == 0)
        #expect(setAsideFiles(in: folder) == [aside])
    }

    @Test func deletingEveryChatTakesTheThreadsSetAsideToo() async throws {
        // Delete All Chats means every chat, the ones this build couldn't
        // read included.
        let (folder, url) = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{not a thread".utf8).write(to: url)
        let store = AskThreadStore<FakeRow>(appDirectory: "unused", url: url)
        #expect(await store.setAsideIfNotAThread())
        // And the original of one this build read only in part.
        try partialThread.write(to: url)
        _ = await store.load()
        #expect(originalFiles(in: folder).count == 1)

        #expect(await store.removeEverySetAside().isEmpty)
        #expect(setAsideFiles(in: folder).isEmpty)
        #expect(originalFiles(in: folder).isEmpty)
    }

    @Test func aTurnBothCopiesHoldKeepsWhatEitherSettled() {
        // Either copy may be the older: a save that failed leaves the thread
        // behind the filing New Chat made, and the screen's copy goes on after
        // a filing. Kept whole, the older copy's card would offer its action
        // again.
        func copy(_ question: String, _ outcome: AskProposalOutcome?, _ feedback: AskFeedback.Sentiment?) -> Entry {
            Entry(
                question: question, text: "answer to \(question)",
                answer: AskAnswer(text: "answer to \(question)", matches: [FakeRow("Rumours")]),
                tier: .privateCloud, askedAt: Date(timeIntervalSince1970: 1_750_000_000),
                feedback: feedback, proposalOutcome: outcome
            )
        }
        let base = [
            copy("unsettled", nil, nil),
            copy("failed", .failed(nil), .negative),
            copy("done", .confirmed("Done."), .positive)
        ]
        let extra = [
            copy("unsettled", .declined, .positive),
            copy("failed", .handedOff(nil), .positive),
            copy("done", .failed("Couldn't."), nil)
        ]
        let merged = Entry.merging(extra, into: base)
        #expect(merged.map(\.question) == ["unsettled", "failed", "done"])
        #expect(merged.map(\.proposalOutcome) == [.declined, .handedOff(nil), .confirmed("Done.")])
        // Two verdicts that differ keep the base's: the other thumb replaces
        // a verdict, so neither is known to be the newer.
        #expect(merged.map(\.feedback) == [.positive, .negative, .positive])
        #expect(merged.map(\.text) == base.map(\.text))
    }

    @Test func aPerformStillOutOutranksAFailureAndGivesWayToWhatCameOfIt() {
        // The failure can be the attempt before the reader confirmed again:
        // kept over the perform that followed, the card would offer the
        // action again while it may have been done.
        func copy(_ question: String, _ outcome: AskProposalOutcome?) -> Entry {
            Entry(
                question: question, text: "answer to \(question)",
                answer: AskAnswer(text: "answer to \(question)", matches: [FakeRow("Rumours")]),
                tier: .privateCloud, askedAt: Date(timeIntervalSince1970: 1_750_000_000), proposalOutcome: outcome
            )
        }
        let base = [copy("unsettled", nil), copy("failed", .failed(nil)), copy("done", .performing), copy("declined", .performing)]
        let extra = [copy("unsettled", .performing), copy("failed", .performing), copy("done", .confirmed("Done.")), copy("declined", .declined)]
        #expect(Entry.merging(extra, into: base).map(\.proposalOutcome) == [.performing, .performing, .confirmed("Done."), .declined])
        // Whichever copy is the base.
        #expect(Entry.merging(base, into: extra).map(\.proposalOutcome) == [.performing, .performing, .confirmed("Done."), .declined])
    }

    @Test func whatCameOfAPerformReplacesTheYesItWasWrittenWith() throws {
        // Its own answer, so a failure takes the perform's place, though a
        // join would keep the perform over it.
        let asked = Date(timeIntervalSince1970: 1_750_000_000)
        let chat = [
            Entry(question: "Lend it?", text: "Sure.", answer: AskAnswer(text: "Sure."), askedAt: asked, proposalOutcome: .performing),
            answered("And the other?", at: 1_750_000_060)
        ]
        let settled = try #require(Entry.settlingProposal(asked: "Lend it?", at: asked, with: .failed(nil), in: chat))
        #expect(settled.map(\.proposalOutcome) == [.failed(nil), nil])
        #expect(settled.map(\.question) == chat.map(\.question))
        // Only the turn asked then, and only while its perform is out.
        #expect(Entry.settlingProposal(asked: "Lend it?", at: asked.addingTimeInterval(1), with: .declined, in: chat) == nil)
        #expect(Entry.settlingProposal(asked: "Lend it?", at: asked, with: .declined, in: settled) == nil)
    }

    private func answered(_ question: String, at seconds: TimeInterval?) -> Entry {
        Entry(
            question: question, text: "answer to \(question)",
            answer: AskAnswer(text: "answer to \(question)", matches: [FakeRow("Rumours")]),
            tier: .privateCloud, askedAt: seconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func failed(_ question: String, at seconds: TimeInterval) -> Entry {
        Entry(
            question: question, text: "", answer: nil, failureMessage: "Couldn't answer that.",
            failure: .couldNotAnswer, failureIsRetryable: true, tier: .privateCloud,
            askedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func aFailedTurnTryAgainReplacedStaysReplacedWhicheverCopyIsOlder() {
        // Try Again takes the failed turn off the chat and asks its question
        // again, so one copy can hold the failure and the other the turn
        // asked again. Put back, the failure would be the newest turn, or sit
        // above the turn that replaced it, with Try Again on it again.
        let older = [answered("first", at: 1_000_000), failed("again", at: 1_000_060)]
        let newer = [answered("first", at: 1_000_000), answered("again", at: 1_000_120)]
        #expect(Entry.merging(newer, into: older) == newer)
        #expect(Entry.merging(older, into: newer) == newer)
    }

    @Test func aFailureNoLaterTurnAskedAgainIsKept() {
        let base = [answered("first", at: 1_000_000), answered("later", at: 1_000_120)]
        let extra = [answered("first", at: 1_000_000), failed("failed", at: 1_000_060)]
        #expect(Entry.merging(extra, into: base).map(\.question) == ["first", "failed", "later"])
        // Nor is a failure both copies hold, whatever came after it.
        let both = [answered("first", at: 1_000_000), failed("again", at: 1_000_060)]
        let typedAgain = both + [answered("again", at: 1_000_120)]
        #expect(Entry.merging(typedAgain, into: both).map(\.question) == ["first", "again", "again"])
        #expect(Entry.merging(typedAgain, into: both).first { $0.question == "again" }?.failure == .couldNotAnswer)
    }

    @Test func mergedTurnsAreInTheOrderTheyWereAsked() {
        // Each copy's turns are in the order they were asked, and put back
        // after the turn they followed, the turns only one copy holds could
        // land after a later one.
        let base = [answered("q1", at: 1_000_000), answered("q3", at: 1_000_120)]
        let extra = [answered("q1", at: 1_000_000), answered("q2", at: 1_000_060), answered("q4", at: 1_000_180)]
        #expect(Entry.merging(extra, into: base).map(\.question) == ["q1", "q2", "q3", "q4"])
        // Undated turns keep the place their copy gave them.
        let undated = [answered("u1", at: nil), answered("d1", at: 1_000_000)]
        let more = [answered("u1", at: nil), answered("u2", at: nil)]
        #expect(Entry.merging(more, into: undated).map(\.question) == ["u1", "u2", "d1"])
    }

    @Test func theDefaultURLLandsUnderTheBrandsDirectory() {
        let url = AskThreadStore<FakeRow>.defaultURL(appDirectory: "AskKitTests")
        #expect(url?.lastPathComponent == "ask-thread.json")
        #expect(url?.deletingLastPathComponent().lastPathComponent == "AskKitTests")
    }
}

#endif
