import Foundation
import Testing

@testable import AskCore

/// The chats before this one, on disk.
@Suite(.timeLimit(.minutes(1))) struct AskThreadArchiveTests {

    nonisolated private struct Row: AskRow {
        let id: String
        let displayTitle: String

        init(_ title: String) {
            id = title
            displayTitle = title
        }
    }

    /// A fresh, private folder per test — Swift Testing runs them in parallel.
    private func makeArchive() -> (AskThreadArchive<Row>, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "askkit-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (AskThreadArchive<Row>(appDirectory: "unused", directory: directory), directory)
    }

    /// A chat of answered questions, a minute apart from `start` — or undated,
    /// the way a thread written before `askedAt` existed reads back.
    private func chat(
        _ questions: [String],
        from start: Date = Date(timeIntervalSince1970: 1_000_000),
        dated: Bool = true
    ) -> [AskThreadEntry<Row>] {
        questions.enumerated().map { index, question in
            AskThreadEntry(
                question: question,
                text: "Answered.",
                answer: AskAnswer(text: "Answered.", matches: [Row("Rumours")], tiles: [Row("Rumours")]),
                tier: .privateCloud,
                askedAt: dated ? start.addingTimeInterval(Double(index) * 60) : nil
            )
        }
    }

    @Test func aFiledChatIsListedAndReadsBack() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entries = chat(["Which records do I own?", "Any on vinyl?"])

        let summary = try #require(await archive.archive(entries))
        #expect(summary.title == "Which records do I own?")
        #expect(summary.startedAt == entries.first?.askedAt)
        #expect(summary.updatedAt == entries.last?.askedAt)
        #expect(summary.turnCount == 2)
        #expect(await archive.summaries() == [summary])

        guard case .thread(let read, let dropped) = await archive.entries(for: summary.id) else {
            Issue.record("the filed chat did not read back")
            return
        }
        #expect(read == entries)
        #expect(dropped == 0)
    }

    @Test func whatCameOfAProposalIsWrittenIntoTheFilingOfItsChat() async throws {
        // A perform that outlasted its chat on screen: the chat was filed with
        // the reader's yes, and reads back with what came of it.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        var entries = chat(["Which records do I own?", "Can I lend Rumours?", "And Abbey Road?"])
        entries[1] = AskThreadEntry(
            question: entries[1].question, text: entries[1].text, answer: entries[1].answer,
            tier: .privateCloud, askedAt: entries[1].askedAt, proposalOutcome: .performing
        )
        let other = try #require(await archive.archive(chat(["Anything from 1969?"], from: Date(timeIntervalSince1970: 3_000_000))))
        let summary = try #require(await archive.archive(entries))
        let askedAt = try #require(entries[1].askedAt)

        #expect(await archive.settleProposal(asked: "Can I lend Rumours?", at: askedAt, with: .confirmed("Lent.")))
        guard case .thread(let read, 0) = await archive.entries(for: summary.id) else {
            Issue.record("the filing reads back whole")
            return
        }
        #expect(read.map(\.proposalOutcome) == [nil, .confirmed("Lent."), nil])
        // The list is as it was, and so is every other chat.
        #expect(await archive.summaries().map(\.id) == [other.id, summary.id])
        // Settled, there is no perform left out to write over.
        #expect(await !archive.settleProposal(asked: "Can I lend Rumours?", at: askedAt, with: .failed(nil)))
        #expect(await !archive.settleProposal(asked: "Not asked", at: askedAt, with: .declined))
    }

    @Test func theChatAskedInLastIsListedFirst() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newer = try #require(await archive.archive(chat(["new"], from: Date(timeIntervalSince1970: 2_000_000))))
        let older = try #require(await archive.archive(chat(["old"], from: Date(timeIntervalSince1970: 1_000_000))))
        #expect(await archive.summaries().map(\.id) == [newer.id, older.id])
    }

    @Test func theSameChatFiledAgainReplacesItsEarlierFiling() async throws {
        // What New Chat does to a chat that was opened from the list and then
        // continued: the same opening, more turns.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try #require(await archive.archive(chat(["first"])))
        let again = try #require(await archive.archive(chat(["first", "second"])))
        #expect(again.id == first.id)
        let listed = await archive.summaries()
        #expect(listed.count == 1)
        #expect(listed.first?.turnCount == 2)
    }

    @Test func twoChatsOpeningWithOneStarterAreTwoChats() async {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        await archive.archive(chat(["What do I own?"], from: Date(timeIntervalSince1970: 1_000_000)))
        await archive.archive(chat(["What do I own?"], from: Date(timeIntervalSince1970: 2_000_000)))
        #expect(await archive.summaries().count == 2)
    }

    @Test func undatedChatsAreNeverTakenForOneAnother() async {
        // Nothing to tell them apart but the question, and taking two chats
        // that share one for the same chat would overwrite one of them.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        await archive.archive(chat(["What do I own?"], dated: false))
        await archive.archive(chat(["What do I own?", "Any on vinyl?"], dated: false))
        #expect(await archive.summaries().count == 2)
    }

    @Test func nothingToFileFilesNothing() async {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await archive.archive([]) == nil)
        #expect(await archive.summaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test func pastTheCapTheOldestChatsGoWithTheirFiles() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<(cap + 2) {
            let start = Date(timeIntervalSince1970: Double(1_000_000 + index * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(index)"], from: start))))
        }
        let listed = await archive.summaries()
        #expect(listed.count == cap)
        #expect(listed.first?.id == filed.last?.id)
        for dropped in filed.prefix(2) {
            guard case .empty = await archive.entries(for: dropped.id) else {
                Issue.record("a chat past the cap is still on disk")
                continue
            }
        }
    }

    @Test func filingAChatBesideOneBeingOpenedTakesNoOtherChatWithIt() async throws {
        // Opening an earlier chat files the one on screen, then takes the
        // opened one off the list. At the cap, a filing that counted the
        // opened chat would push the oldest chat out to make room for one
        // about to leave anyway.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<cap {
            let start = Date(timeIntervalSince1970: Double(1_000_000 + index * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(index)"], from: start))))
        }
        let opened = try #require(filed.last)
        let onScreen = chat(["on screen"], from: Date(timeIntervalSince1970: 9_000_000))

        _ = try #require(await archive.archive(onScreen, at: .now, sparing: opened.id))
        // Until the opened chat leaves, every chat is findable: an interrupted
        // open leaves a chat in two places, never in none.
        #expect(await archive.summaries().count == cap + 1)
        await archive.remove(opened.id)

        let listed = await archive.summaries()
        #expect(listed.count == cap)
        #expect(listed.contains { $0.id == filed[0].id })
        guard case .thread = await archive.entries(for: filed[0].id) else {
            Issue.record("the oldest chat left the disk to make room for nothing")
            return
        }
    }

    @Test func aChatFiledBesideItsOwnFilingBeingOpenedLeavesThatFilingAlone() async throws {
        // The chat on screen is the very chat being opened, as an interrupted
        // open leaves it: filed over the filing being opened, the turns only
        // that filing holds would go, and the filing would then be removed
        // with the turns asked since in it.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = try #require(await archive.archive(chat(["first"])))
        let onScreen = chat(["first", "second"])

        let filed = try #require(await archive.archive(onScreen, at: .now, sparing: opened.id))
        #expect(filed.id != opened.id)
        guard case .thread(let kept, _) = await archive.entries(for: opened.id) else {
            Issue.record("the filing being opened is gone")
            return
        }
        #expect(kept.map(\.question) == ["first"])
        #expect(Set(await archive.summaries().map(\.id)) == [opened.id, filed.id])
    }

    @Test func aChatFiledAsTheOldestOfTooManyIsKeptAndTheOldestOtherGoes() async throws {
        // An old chat opened from a full list and ended again is filed with
        // the date of its last turn, older than every other chat. Trimmed as
        // the oldest, it would be deleted as it was filed, and its summary
        // would tell the caller it was kept.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<cap {
            let start = Date(timeIntervalSince1970: Double(2_000_000 + index * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(index)"], from: start))))
        }

        let oldest = try #require(await archive.archive(chat(["oldest"], from: Date(timeIntervalSince1970: 1_000_000))))
        guard case .thread(let kept, _) = await archive.entries(for: oldest.id) else {
            Issue.record("the chat just filed was trimmed")
            return
        }
        #expect(kept.map(\.question) == ["oldest"])
        let listed = await archive.summaries()
        #expect(listed.count == cap)
        #expect(listed.contains { $0.id == oldest.id })
        #expect(!listed.contains { $0.id == filed[0].id })
    }

    @Test func aChatPastTheTurnCapFiledAgainReplacesItsEarlierFiling() async throws {
        // Past `maxPersistedTurns` the turns a chat opened with are trimmed
        // away as it grows: the thread keeps only its newest turns, so the chat
        // read back on a later launch no longer holds the turn its earlier
        // filing opened with. It is known by the turn that filing ended on.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let turns = AskThreadStore<Row>.maxPersistedTurns
        let whole = chat((0..<(turns + 9)).map { "q\($0)" })
        let first = try #require(await archive.archive(Array(whole.prefix(turns + 5))))
        let again = try #require(await archive.archive(Array(whole.dropFirst(8))))
        #expect(again.id == first.id)
        let listed = await archive.summaries()
        #expect(listed.count == 1)
        #expect(listed.first?.turnCount == turns)
    }

    @Test func aChatLeftFiledByAnInterruptedOpenIsOneChatWhenItIsFiledAgain() async throws {
        // An open interrupted after filing the chat on screen and before
        // taking the opened chat off the list leaves the opened chat in two
        // places. Continued past the turn cap, read back on a later launch
        // and filed again, it is still one chat.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let turns = AskThreadStore<Row>.maxPersistedTurns
        let whole = chat((0..<(turns + 2)).map { "q\($0)" })
        let opened = try #require(await archive.archive(Array(whole.prefix(turns))))
        let onScreen = try #require(await archive.archive(
            chat(["on screen"], from: Date(timeIntervalSince1970: 9_000_000)), at: .now, sparing: opened.id
        ))
        // The open stops here. The reader carries on with the opened chat.
        let continued = try #require(await archive.archive(Array(whole.dropFirst(2))))
        #expect(continued.id == opened.id)
        #expect(Set(await archive.summaries().map(\.id)) == [opened.id, onScreen.id])
    }

    @Test func aProvisionalFilingTakesNoChatsPlaceInAFullList() async throws {
        // Turns asked beside a thread that couldn't be read are filed as they
        // are asked, and go once they are written as the thread. Counted, the
        // first would push the oldest chat out of a full list for good.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<cap {
            let start = Date(timeIntervalSince1970: Double(1_000_000 + index * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(index)"], from: start))))
        }
        let held = UUID()
        let start = Date(timeIntervalSince1970: 9_000_000)

        #expect(await archive.fileProvisionally(chat(["held"], from: start), as: held)?.id == held)
        #expect(await archive.fileProvisionally(chat(["held", "again"], from: start), as: held)?.turnCount == 2)
        #expect(await archive.summaries().count == cap + 1)
        guard case .thread = await archive.entries(for: filed[0].id) else {
            Issue.record("a provisional filing trimmed the oldest chat")
            return
        }

        // Nor does another filing count it: the list keeps its cap of others.
        let next = try #require(await archive.archive(chat(["next"], from: Date(timeIntervalSince1970: 9_500_000))))
        let listed = await archive.summaries().map(\.id)
        #expect(listed.count == cap + 1)
        #expect(listed.contains(held) && listed.contains(next.id))
        #expect(!listed.contains(filed[0].id))
    }

    @Test func aProvisionalFilingIsNoChatsEarlierFiling() async throws {
        // A chat filed with the same opening is a chat in its own right, the
        // one the provisional turns are a copy of: filed over the copy, it
        // would go when the copy does.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = UUID()
        await archive.fileProvisionally(chat(["first"]), as: held)

        let filed = try #require(await archive.archive(chat(["first", "second"])))
        #expect(filed.id != held)
        #expect(Set(await archive.summaries().map(\.id)) == [held, filed.id])
    }

    @Test func endingAProvisionalFilingRemovesItOrLeavesAnOrdinaryOne() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = UUID()
        await archive.fileProvisionally(chat(["kept elsewhere"]), as: kept)
        #expect(await archive.endProvisional(removing: true))
        #expect(await archive.summaries().isEmpty)
        // Ended already: there is nothing to remove.
        #expect(await archive.endProvisional(removing: true))

        let left = UUID()
        await archive.fileProvisionally(chat(["kept nowhere else"]), as: left)
        await archive.endProvisional(removing: false)
        #expect(await archive.summaries().map(\.id) == [left])
        // An ordinary filing now, which the same chat filed again replaces.
        let again = try #require(await archive.archive(chat(["kept nowhere else", "and more"])))
        #expect(again.id == left)
        #expect(await archive.summaries().map(\.turnCount) == [2])
    }

    @Test func theChatOnScreenFiledTakesOverTheProvisionalFilingInOneWrite() async throws {
        // New Chat files the chat on screen, the turns filed provisionally
        // among them. Filed as a chat of its own and the provisional filing
        // removed after, a process that ended between the two would leave
        // those turns listed twice at the next launch.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = UUID()
        let start = Date(timeIntervalSince1970: 9_000_000)
        await archive.fileProvisionally(chat(["held"], from: start), as: held)

        let filed = try #require(await archive.fileTheChatOnScreen(chat(["held", "and more"], from: start), at: .now, sparing: nil))
        #expect(filed.id == held)
        // The process ends here.
        let relaunched = AskThreadArchive<Row>(appDirectory: "unused", directory: directory)
        #expect(await relaunched.summaries().map(\.id) == [held])
        #expect(await relaunched.summaries().map(\.turnCount) == [2])
    }

    @Test func theChatOnScreenFiledOverItsOwnFilingTakesTheProvisionalOneOffTheListInTheSameWrite() async throws {
        // The thread read again after turns were asked beside it, and the
        // chat it holds filed already: filed over that filing, the chat holds
        // the provisional turns, and the provisional filing goes in the same
        // write of the list.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thread = chat(["first"])
        let own = try #require(await archive.archive(thread))
        let held = UUID()
        let beside = chat(["asked beside"], from: Date(timeIntervalSince1970: 1_000_600))
        await archive.fileProvisionally(beside, as: held)

        let filed = try #require(await archive.fileTheChatOnScreen(thread + beside, at: .now, sparing: nil))
        #expect(filed.id == own.id)
        let relaunched = AskThreadArchive<Row>(appDirectory: "unused", directory: directory)
        #expect(await relaunched.summaries().map(\.id) == [own.id])
        guard case .empty = await relaunched.entries(for: held) else {
            Issue.record("the provisional filing is still on disk")
            return
        }
    }

    @Test func theChatOnScreenFiledOverTheProvisionalFilingCountsAgainstTheCap() async throws {
        // Ordinary once filed: a full list keeps its cap.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<cap {
            let start = Date(timeIntervalSince1970: Double(1_000_000 + index * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(index)"], from: start))))
        }
        let held = UUID()
        let start = Date(timeIntervalSince1970: 9_000_000)
        await archive.fileProvisionally(chat(["held"], from: start), as: held)

        _ = try #require(await archive.fileTheChatOnScreen(chat(["held", "and more"], from: start), at: .now, sparing: nil))
        let listed = await archive.summaries().map(\.id)
        #expect(listed.count == cap)
        #expect(listed.contains(held))
        #expect(!listed.contains(filed[0].id))
    }

    @Test func anotherChatFiledLeavesTheProvisionalFilingAlone() async throws {
        // A chat New Chat ended and couldn't file, filed later as the disk
        // allows, is no chat on screen.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = UUID()
        await archive.fileProvisionally(chat(["held"], from: Date(timeIntervalSince1970: 9_000_000)), as: held)

        let owed = try #require(await archive.archive(chat(["owed"])))
        #expect(owed.id != held)
        #expect(Set(await archive.summaries().map(\.id)) == [held, owed.id])
        let onScreen = try #require(await archive.fileTheChatOnScreen(
            chat(["held", "and more"], from: Date(timeIntervalSince1970: 9_000_000)), at: .now, sparing: nil
        ))
        #expect(onScreen.id == held)
    }

    @Test func aChatFileTheIndexDoesNotNameIsListed() async throws {
        // A filing interrupted after its chat was written and before the index
        // was: the chat files are the record, and the list reads them.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let listed = try #require(await archive.archive(chat(["listed"])))
        let orphan = UUID()
        let entries = chat(["unlisted"], from: Date(timeIntervalSince1970: 2_000_000))
        try JSONEncoder().encode(entries).write(to: directory.appending(path: "\(orphan.uuidString).json"))

        #expect(await archive.summaries().map(\.id) == [orphan, listed.id])
    }

    @Test func aChatThatCouldNotBeReadWhenTheListWasRebuiltComesBackOnceItReads() async throws {
        // A rebuilt index leaves out a chat it can't read, and the next write
        // must not make that for good.
        let (archive, directory) = makeArchive()
        var lockedFile: URL?
        defer {
            if let lockedFile {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedFile.path(percentEncoded: false))
            }
            try? FileManager.default.removeItem(at: directory)
        }
        let older = try #require(await archive.archive(chat(["old"], from: Date(timeIntervalSince1970: 1_000_000))))
        let locked = try #require(await archive.archive(chat(["locked"], from: Date(timeIntervalSince1970: 2_000_000))))
        let file = directory.appending(path: "\(locked.id.uuidString).json")
        lockedFile = file
        try Data("not an index".utf8).write(to: directory.appending(path: "index.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))

        #expect(await archive.summaries().map(\.id) == [older.id])
        let newer = try #require(await archive.archive(chat(["new"], from: Date(timeIntervalSince1970: 3_000_000))))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))

        #expect(await archive.summaries().map(\.id) == [newer.id, locked.id, older.id])
    }

    @Test func aRemovedChatIsGoneFromTheListAndTheDisk() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = try #require(await archive.archive(chat(["kept"])))
        let removed = try #require(await archive.archive(chat(["removed"], from: Date(timeIntervalSince1970: 2_000_000))))
        await archive.remove(removed.id)
        #expect(await archive.summaries().map(\.id) == [kept.id])
        guard case .empty = await archive.entries(for: removed.id) else {
            Issue.record("the removed chat is still on disk")
            return
        }
    }

    /// Delete All Chats: every chat leaves the list and the disk, an archive
    /// that never filed one has nothing to fail on, and the next New Chat
    /// files into it as before.
    @Test func removingEveryChatEmptiesTheListAndTheDisk() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        await archive.removeAll()

        let older = try #require(await archive.archive(chat(["older"])))
        let newer = try #require(await archive.archive(chat(["newer"], from: Date(timeIntervalSince1970: 2_000_000))))
        await archive.removeAll()
        #expect(await archive.summaries().isEmpty)
        for id in [older.id, newer.id] {
            guard case .empty = await archive.entries(for: id) else {
                Issue.record("a chat is still on disk after every chat was removed")
                continue
            }
        }

        _ = try #require(await archive.archive(chat(["after"])))
        #expect(await archive.summaries().map(\.title) == ["after"])
    }

    /// The folder can be a host's, such as an App Group container a widget
    /// reads: Delete All Chats takes the archive's own files and leaves
    /// everything else, and the folder with it.
    @Test func removingEveryChatLeavesWhatElseIsInTheFolder() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let filed = try #require(await archive.archive(chat(["filed"])))
        let widget = directory.appending(path: "widget.json")
        let notes = directory.appending(path: "notes.txt")
        try Data("{}".utf8).write(to: widget)
        try Data("mine".utf8).write(to: notes)

        #expect(await archive.removeAll())
        #expect(await archive.summaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file(for: filed.id, in: directory).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "index.json").path(percentEncoded: false)))
        #expect(try Data(contentsOf: widget) == Data("{}".utf8))
        #expect(try Data(contentsOf: notes) == Data("mine".utf8))

        // With nothing else in it, the folder goes too.
        try FileManager.default.removeItem(at: widget)
        try FileManager.default.removeItem(at: notes)
        _ = try #require(await archive.archive(chat(["again"])))
        #expect(await archive.removeAll())
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    // MARK: - Writes and deletions that fail

    private func setImmutable(_ immutable: Bool, _ url: URL) throws {
        try FileManager.default.setAttributes([.immutable: immutable], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// A chat filed under an id whose removal hadn't taken reads back, and
    /// isn't swept as deleted: the filing ends the removal.
    @Test func aChatFiledUnderAnIdWhoseRemovalDidNotTakeReadsBack() async throws {
        let (archive, directory) = makeArchive()
        let index = directory.appending(path: "index.json")
        defer {
            try? setImmutable(false, index)
            try? FileManager.default.removeItem(at: directory)
        }
        let removed = try #require(await archive.archive(chat(["removed"])))
        // The file goes and the index that names it won't be written: the
        // removal is remembered rather than taken.
        try setImmutable(true, index)
        #expect(await !archive.remove(removed.id))
        try setImmutable(false, index)

        let refiled = chat(["filed again"], from: Date(timeIntervalSince1970: 2_000_000))
        _ = try #require(await archive.fileProvisionally(refiled, as: removed.id))
        guard case .thread(let read, _) = await archive.entries(for: removed.id) else {
            Issue.record("the chat filed under the id reads as deleted")
            return
        }
        #expect(read == refiled)
        #expect(await archive.summaries().map(\.id).contains(removed.id))
        #expect(FileManager.default.fileExists(atPath: file(for: removed.id, in: directory).path(percentEncoded: false)))
    }

    /// The cap trims the oldest chat's file before the index is written; an
    /// index that won't be written still names it, and it must not be listed
    /// to open onto nothing.
    @Test func aChatTrimmedByTheCapStaysOffTheListWhenTheIndexWontWrite() async throws {
        let (archive, directory) = makeArchive()
        let index = directory.appending(path: "index.json")
        defer {
            try? setImmutable(false, index)
            try? FileManager.default.removeItem(at: directory)
        }
        let cap = AskThreadArchive<Row>.maxThreads
        var filed: [AskThreadSummary] = []
        for number in 0..<cap {
            let start = Date(timeIntervalSince1970: Double(1_000_000 + number * 3_600))
            filed.append(try #require(await archive.archive(chat(["q\(number)"], from: start))))
        }
        try setImmutable(true, index)
        let newest = try #require(await archive.archive(chat(["newest"], from: Date(timeIntervalSince1970: 9_000_000))))
        let listed = await archive.summaries().map(\.id)
        #expect(listed.count == cap)
        #expect(listed.first == newest.id)
        #expect(!listed.contains(filed[0].id))
    }

    private func setPermissions(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    private func file(for id: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    @Test func aFilingThatCannotBeWrittenReturnsNoSummary() async throws {
        // The caller's signal not to delete or overwrite the thread it filed.
        let (archive, directory) = makeArchive()
        defer {
            try? setPermissions(0o755, of: directory)
            try? FileManager.default.removeItem(at: directory)
        }
        _ = try #require(await archive.archive(chat(["first"])))
        try setPermissions(0o555, of: directory)
        #expect(await archive.archive(chat(["second"], from: Date(timeIntervalSince1970: 2_000_000))) == nil)
    }

    @Test func aChatThatWillNotDeleteStaysOffTheList() async throws {
        // The chat files are the record, so a file left behind would be
        // listed again by the next read: the chat the reader deleted, back.
        let (archive, directory) = makeArchive()
        defer {
            try? setPermissions(0o755, of: directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let kept = try #require(await archive.archive(chat(["kept"])))
        let removed = try #require(await archive.archive(chat(["removed"], from: Date(timeIntervalSince1970: 2_000_000))))
        try setPermissions(0o555, of: directory)

        #expect(await !archive.remove(removed.id))
        #expect(await archive.summaries().map(\.id) == [kept.id])
        guard case .empty = await archive.entries(for: removed.id) else {
            Issue.record("a chat the reader deleted still opens")
            return
        }
        // Retried on the next read that can.
        try setPermissions(0o755, of: directory)
        #expect(await archive.summaries().map(\.id) == [kept.id])
        #expect(!FileManager.default.fileExists(atPath: file(for: removed.id, in: directory).path(percentEncoded: false)))
    }

    @Test func aDeletionThatDidNotTakeIsRememberedByTheNextLaunch() async throws {
        // A file that won't go from a folder that still takes writes: the
        // index remembers the deletion.
        let (archive, directory) = makeArchive()
        let kept = try #require(await archive.archive(chat(["kept"])))
        let removed = try #require(await archive.archive(chat(["removed"], from: Date(timeIntervalSince1970: 2_000_000))))
        let lingering = file(for: removed.id, in: directory)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: lingering.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: lingering.path(percentEncoded: false))

        #expect(await !archive.remove(removed.id))
        let relaunched = AskThreadArchive<Row>(appDirectory: "unused", directory: directory)
        #expect(await relaunched.summaries().map(\.id) == [kept.id])

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: lingering.path(percentEncoded: false))
        #expect(await relaunched.summaries().map(\.id) == [kept.id])
        #expect(!FileManager.default.fileExists(atPath: lingering.path(percentEncoded: false)))
    }

    @Test func everyChatStaysDeletedWhenTheFolderWillNotGo() async throws {
        let (archive, directory) = makeArchive()
        defer {
            try? setPermissions(0o755, of: directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let older = try #require(await archive.archive(chat(["older"])))
        let newer = try #require(await archive.archive(chat(["newer"], from: Date(timeIntervalSince1970: 2_000_000))))
        try setPermissions(0o555, of: directory)

        #expect(await !archive.removeAll())
        #expect(await archive.summaries().isEmpty)
        try setPermissions(0o755, of: directory)
        #expect(await archive.summaries().isEmpty)
        for id in [older.id, newer.id] {
            #expect(!FileManager.default.fileExists(atPath: file(for: id, in: directory).path(percentEncoded: false)))
        }
        #expect(await archive.removeAll())

        _ = try #require(await archive.archive(chat(["after"], from: Date(timeIntervalSince1970: 3_000_000))))
        #expect(await archive.summaries().map(\.title) == ["after"])
    }

    @Test func removingSaysWhetherTheChatIsGone() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(await archive.removeAll())
        let filed = try #require(await archive.archive(chat(["filed"])))
        #expect(await archive.remove(filed.id))
        #expect(await archive.remove(UUID()))
        #expect(await archive.removeAll())
    }

    @Test func aFilingThisBuildCannotReadWholeIsNeverWrittenOver() async throws {
        // A turn in it that a later build wrote: replaced by this build's
        // filing of the same chat, it would be gone. Filed beside it instead.
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try #require(await archive.archive(chat(["first", "second"])))
        let filed = file(for: first.id, in: directory)
        var turns = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: filed)) as? [[String: Any]])
        turns[1]["question"] = 12_345
        let altered = try JSONSerialization.data(withJSONObject: turns)
        try altered.write(to: filed)

        let again = try #require(await archive.archive(chat(["first", "second", "third"])))
        #expect(again.id != first.id)
        #expect(try Data(contentsOf: filed) == altered)
        #expect(Set(await archive.summaries().map(\.id)) == [first.id, again.id])
    }

    @Test func anIndexThatWillNotDecodeIsRebuiltFromTheChats() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = try #require(await archive.archive(chat(["old"], from: Date(timeIntervalSince1970: 1_000_000))))
        let newer = try #require(await archive.archive(chat(["new"], from: Date(timeIntervalSince1970: 2_000_000))))
        try Data("not an index".utf8).write(to: directory.appending(path: "index.json"))

        let listed = await archive.summaries()
        #expect(listed.map(\.id) == [newer.id, older.id])
        #expect(listed.map(\.title) == ["new", "old"])
    }

    @Test func aSummaryWrittenBeforeItsFieldsExistedStillDecodes() throws {
        let id = UUID()
        let data = Data(#"{"id":"\#(id.uuidString)"}"#.utf8)
        let summary = try JSONDecoder().decode(AskThreadSummary.self, from: data)
        #expect(summary.id == id)
        #expect(summary.title.isEmpty)
        #expect(summary.startedAt == nil)
        #expect(summary.turnCount == 0)
    }
}
