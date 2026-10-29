public import Foundation
import os

/// One earlier chat, as the history list shows it.
///
/// **Every field added after the first release must be `decodeIfPresent`**, for
/// the reason `AskThreadEntry` gives. A summary that throws takes the index
/// with it, and the archive rebuilds the index from the chat files, which
/// costs a read, never a chat.
nonisolated public struct AskThreadSummary: Codable, Sendable, Equatable, Identifiable {
    /// What tells the chat apart in the history list. For an earlier chat, it
    /// names the chat's file in the archive, `threads/<id>.json`.
    public let id: UUID
    /// The chat's first question: what a reader remembers a chat by.
    public let title: String
    /// When that first question was asked. With the title, what makes two
    /// filings of one chat the same chat.
    public let startedAt: Date?
    /// When the chat's newest question was asked. The list is newest first by
    /// it.
    public let updatedAt: Date
    /// How many turns the chat holds. A filed chat keeps at most
    /// `AskThreadStore.maxPersistedTurns`.
    public let turnCount: Int

    /// A summary with each field as given.
    public init(id: UUID, title: String, startedAt: Date?, updatedAt: Date, turnCount: Int) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.turnCount = turnCount
    }

    /// Decodes a summary field by field: every field but the id has a
    /// default, so an index written before a field existed still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        turnCount = try container.decodeIfPresent(Int.self, forKey: .turnCount) ?? 0
    }

    /// The summary a chat's own entries give.
    package static func of<Row: AskRow>(_ entries: [AskThreadEntry<Row>], id: UUID, fallbackDate: Date) -> AskThreadSummary? {
        guard let first = entries.first else { return nil }
        return AskThreadSummary(
            id: id,
            title: first.question,
            startedAt: first.askedAt,
            updatedAt: entries.last?.askedAt ?? fallbackDate,
            turnCount: entries.count
        )
    }

    /// Whether these entries are the chat this summary names, filed again:
    /// they still hold the turn it opened with, or the turn it ended on.
    ///
    /// The second is how a chat past `AskThreadStore.maxPersistedTurns` is
    /// known. Each filing keeps only its newest turns, so the turn it opened
    /// with is trimmed away as it grows, while the turn the last filing ended
    /// on is still there. A turn's date is to the fraction of a second, so no
    /// other chat holds it.
    ///
    /// Never for a chat with no date on its first question. Two chats can open
    /// with the same starter, and filing them as one chat would overwrite one
    /// with the other.
    package func isSameChat<Row: AskRow>(as entries: [AskThreadEntry<Row>]) -> Bool {
        guard let startedAt else { return false }
        return entries.contains { entry in
            guard let askedAt = entry.askedAt else { return false }
            return (askedAt == startedAt && entry.question == title) || askedAt == updatedAt
        }
    }
}

/// `threads/index.json`.
nonisolated struct AskThreadIndex: Codable, Sendable, Equatable {
    /// Newest first.
    var threads: [AskThreadSummary]
    /// Chats deleted whose files didn't go, so a read leaves them off the
    /// list rather than listing their files again (`AskThreadArchive`'s
    /// `pendingDeletions`).
    var deleted: [UUID]

    init(threads: [AskThreadSummary] = [], deleted: [UUID] = []) {
        self.threads = threads
        self.deleted = deleted
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = try container.decodeIfPresent([AskThreadSummary].self, forKey: .threads) ?? []
        deleted = try container.decodeIfPresent([UUID].self, forKey: .deleted) ?? []
    }

    /// The deletions an index carries, from bytes that don't decode as a
    /// whole one, such as a later build's with a summary this build can't
    /// read: none where they don't decode either.
    static func deletions(in data: Data) -> [UUID] {
        (try? JSONDecoder().decode(Deletions.self, from: data))?.deleted ?? []
    }

    nonisolated private struct Deletions: Decodable {
        let deleted: [UUID]?
    }
}

/// What `AskThreadArchive.merge(_:filingIfNew:at:)` did.
nonisolated enum AskArchiveMerge: Equatable, Sendable {
    /// Filed, into the chat's earlier filing when it had one.
    case filed(AskThreadSummary)
    /// No filing is this chat, and none was made.
    case noSuchChat
    /// Not written: the chat's filing can't be read whole, or the write
    /// failed.
    case notFiled
}

/// The chats before this one.
///
/// `ask-thread.json` stays the current chat, which `AskThreadStore` reads and
/// writes on its own. The archive holds the rest, beside it:
/// `threads/<id>.json` per chat in the same format, and `threads/index.json`
/// naming them.
///
/// **A chat is known by its turns, not by an id anyone has to remember.**
/// Filing the same chat again (the same first question, asked at the same
/// moment, or for a chat too long to keep whole, the turn its last filing ended
/// on) replaces its earlier filing. So the store files the current chat on New
/// Chat without tracking where it came from, and there is no id beside the
/// current thread to drift out of step with it: every write that could be
/// interrupted leaves a duplicate at worst, and the next filing replaces it.
/// A filing this build can't read whole is the exception: replaced, it would
/// lose the turns that didn't decode, so the chat is filed beside it instead.
///
/// **The index is a convenience, the chat files are the record.** Every read of
/// the index adds the chat files it doesn't name, so a chat whose filing was
/// interrupted before the index was written, or one that couldn't be read when
/// a lost index was rebuilt, is listed as soon as it reads. The exception is a
/// chat deleted whose file wouldn't go: remembered as deleted, and its file
/// retried, so it doesn't come back.
///
/// Written the way the thread is (`AskStoredFile`): off the main actor,
/// atomically, under complete file protection except on a Mac, excluded from
/// backup, and never past `AskStoredFile.maxBytes`. `threads/`, which is the
/// archive's own, is made the same way.
///
/// **A host only makes one, to hand to `AskConversationStore`,** as it does
/// the thread's (`AskThreadStore`). The initializer, to file the chats
/// somewhere of its own (`directory:`), and `maxThreads` are all that is
/// public; filing, reading and deleting are AskKit's own (`package`).
/// Whether a filing may be replaced or removed turns on what is on screen and
/// in the thread, which only the conversation store knows, and even the list
/// isn't a bare read: each read tries again the deletions that haven't taken.
/// The list a host shows is the conversation store's `history`.
///
/// Behind no platform gate, like `AskThreadStore`: Foundation alone.
public actor AskThreadArchive<Row: AskRow> {
    private let logger: Logger

    /// How many earlier chats are kept. The oldest of the others go as a chat
    /// is filed, never the chat just filed.
    public static var maxThreads: Int { 50 }

    private static var indexName: String { "index.json" }

    private let directory: URL?
    /// Chat files the index doesn't name that would not read, logged once each
    /// rather than on every read of the list.
    private var unlistedFailures: Set<UUID> = []
    /// Chats deleted, by the reader or the cap, whose deletion hasn't fully
    /// taken: the file is still there, or the index on disk still names the
    /// chat. Every read leaves them off the list and tries their files again,
    /// and every index written carries them (`AskThreadIndex.deleted`), so a
    /// relaunch remembers them too when the index could be written.
    private var pendingDeletions: Set<UUID> = []
    /// The filing of turns that are on screen and kept nowhere else yet
    /// (`fileProvisionally(_:as:at:)`), until the chat on screen is filed
    /// over it (`fileTheChatOnScreen(_:at:sparing:)`) or it ends
    /// (`endProvisional(removing:)`). The cap doesn't count it and no other
    /// chat filed takes it for its own earlier filing, so it neither takes
    /// another chat's place nor stands in for one. In memory only: a
    /// relaunch finds an ordinary filing of those turns, the chat they were.
    private var provisional: UUID?

    /// An archive in `Application Support/<appDirectory>/threads/`.
    ///
    /// - Parameters:
    ///   - appDirectory: the folder under `Application Support`:
    ///     `AskBrand.appDirectory`. The archive is `threads/` inside it.
    ///   - directory: an explicit folder, for tests. Overrides `appDirectory`.
    ///   - logSubsystem: the subsystem the archive logs under:
    ///     `AskBrand.logSubsystem`. Nil logs under the app's bundle identifier.
    public init(appDirectory: String, directory: URL? = nil, logSubsystem: String? = nil) {
        logger = Logger(subsystem: AskBrand.subsystem(logSubsystem), category: "thread-archive")
        self.directory = directory ?? Self.defaultDirectory(appDirectory: appDirectory)
        if directory == nil, !AskBrand.isOneFolder(appDirectory) {
            logger.fault("""
                \(appDirectory.debugDescription, privacy: .public) is not one folder under Application Support, \
                so no earlier chat is filed, read or deleted
                """)
        }
    }

    /// The folder the chats are filed in, or nil for an archive that has none
    /// and files nothing.
    package nonisolated var folderURL: URL? { directory }

    /// `Application Support/<appDirectory>/threads/`, or nil for a name that
    /// isn't one folder (`AskBrand.appDirectory`): `removeAll()` deletes this
    /// folder once the archive's files in it are gone and nothing else is.
    static func defaultDirectory(appDirectory: String) -> URL? {
        AskBrand.appFolder(appDirectory)?.appending(path: "threads", directoryHint: .isDirectory)
    }

    // MARK: - Reading

    /// Every earlier chat, newest first.
    package func summaries() -> [AskThreadSummary] {
        readIndex().threads
    }

    /// One chat's entries, read the way the current thread is: entry by entry,
    /// keeping what parses. A chat deleted whose file is still there reads as
    /// gone.
    ///
    /// Unlike the thread's, a read in part keeps no original: the filing is
    /// the only copy of the turns that didn't decode. A caller that opens one
    /// (`dropped` above zero) must keep it filed rather than remove it; the
    /// filing of the chat it becomes then goes beside it, never over it
    /// (`archive(_:at:)`).
    package func entries(for id: UUID) -> AskThreadRead<Row> {
        guard !pendingDeletions.contains(id), let url = url(for: id) else { return .empty }
        let (read, failure, droppedRows) = contents(of: url)
        if let failure {
            logger.error("an earlier chat \(failure, privacy: .public)")
        }
        if droppedRows > 0 {
            // As the thread's read logs them (`AskThreadStore.load()`).
            logger.error("\(droppedRows, privacy: .public) row(s) in an earlier chat no longer decode, and are left out of their answers")
        }
        return read
    }

    /// A chat file's entries, why it could not be read when it could not, and
    /// how many rows its answers left out (`AskDroppedRows`).
    private func contents(of url: URL) -> (read: AskThreadRead<Row>, failure: String?, droppedRows: Int) {
        let data: Data
        do {
            data = try AskStoredFile.contents(of: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (.empty, nil, 0)
        } catch {
            return (.unreadable, "could not be read: \(AskStoredFile.tag(for: error))", 0)
        }
        do {
            let (entries, dropped, droppedRows) = try AskThreadStore<Row>.decodeEntries(from: data)
            guard !entries.isEmpty || dropped == 0 else {
                return (.unreadable, "has no turn this build can decode", 0)
            }
            return (.thread(entries, dropped: dropped), nil, droppedRows)
        } catch {
            return (.unreadable, "on disk is not a chat: \(AskStoredFile.tag(for: error))", 0)
        }
    }

    /// Whether a filing can be replaced without losing a turn: it is gone, or
    /// every turn in it decodes.
    private func readsWhole(_ id: UUID) -> Bool {
        guard let url = url(for: id) else { return false }
        switch contents(of: url).read {
        case .thread(_, let dropped): return dropped == 0
        case .empty: return true
        case .unreadable: return false
        }
    }

    // MARK: - Writing

    /// File a chat, replacing an earlier filing of the same one. Returns its
    /// summary, or nil when there was nothing to file or it could not be
    /// written.
    ///
    /// Capped like the thread, at `AskThreadStore.maxPersistedTurns`, oldest
    /// turns dropped.
    ///
    /// **Nil for turns there were means they are not filed**, and a caller
    /// must keep them where they are: not clear the thread they came from,
    /// and not save another chat over it. On the iOS family a write fails
    /// while the device is locked, as the thread's does
    /// (`AskThreadStore.save(_:)`). A summary means the chat file is written;
    /// the index may not be, and the next read lists the chat from its file.
    @discardableResult
    package func archive(_ entries: [AskThreadEntry<Row>], at now: Date = .now) -> AskThreadSummary? {
        archive(entries, at: now, sparing: nil)
    }

    /// File a chat beside one that is being opened in its place.
    ///
    /// `spared` is left out of the count the cap trims to: it leaves the list
    /// as soon as it is on screen, and trimming for it would take the oldest
    /// chat to make room for one that is about to go anyway. Until it goes the
    /// list holds one chat past the cap, so an open interrupted here leaves a
    /// chat in two places rather than in none.
    ///
    /// Never filed over `spared`, even when these entries are the same chat:
    /// the caller removes that filing once the chat it holds is on screen, so
    /// written over, it would take these entries with it, and the turns only
    /// it held would already be gone.
    @discardableResult
    func archive(_ entries: [AskThreadEntry<Row>], at now: Date, sparing spared: UUID?) -> AskThreadSummary? {
        guard !entries.isEmpty else { return nil }
        let index = readIndex()
        let earlier = index.threads.first {
            $0.id != spared && $0.id != provisional && $0.isSameChat(as: entries)
        }?.id
        // A filing this build can't read whole is never replaced: its turns
        // that didn't decode would go. This one is filed beside it.
        let id = earlier.flatMap { readsWhole($0) ? $0 : nil } ?? UUID()
        return file(entries, as: id, in: index, at: now, sparing: spared)
    }

    /// File the chat on screen, the turns filed provisionally among them,
    /// as `archive(_:at:sparing:)` files a chat, and say what was filed.
    ///
    /// **The provisional filing goes in the same write where it can.**
    /// Without an earlier filing of the chat, the chat is filed over the
    /// provisional one, under its ID: one file, and nothing listed twice.
    /// Over the chat's own earlier filing, the provisional one comes off the
    /// list in the write of the list that files the chat, and its file goes
    /// after; a process ending once the chat's file is written and before the
    /// list is leaves the provisional filing listed beside the chat, an
    /// ordinary one at the next launch, its turns in both. Removed in a write
    /// of its own after the chat was filed, it would leave that window open
    /// at every New Chat. Either way the filing is an ordinary one, which the
    /// cap counts. Not filed, the provisional filing stays as it was.
    @discardableResult
    package func fileTheChatOnScreen(_ entries: [AskThreadEntry<Row>], at now: Date, sparing spared: UUID?) -> AskThreadSummary? {
        guard !entries.isEmpty else { return nil }
        let index = readIndex()
        let held = provisional
        let earlier = index.threads.first {
            $0.id != spared && $0.id != held && $0.isSameChat(as: entries)
        }?.id
        // Neither is replaced unless this build reads it whole, as in
        // `archive(_:at:sparing:)`.
        let wholeHeld = held.flatMap { readsWhole($0) ? $0 : nil }
        let id = earlier.flatMap { readsWhole($0) ? $0 : nil } ?? wholeHeld ?? UUID()
        provisional = nil
        guard let summary = file(entries, as: id, in: index, at: now, sparing: spared, absorbing: wholeHeld == id ? nil : wholeHeld) else {
            provisional = held
            return nil
        }
        return summary
    }

    /// Put turns kept aside back into the filing of the chat they belong to,
    /// joined with it: every turn either holds but a failure Try Again
    /// replaced (`AskThreadEntry.merging`). Without a filing of that chat,
    /// they are filed as a chat of their own when `filingIfNew`, and left
    /// alone when not.
    ///
    /// How `AskThreadStore.recoverSetAside` puts a thread back: filed over its
    /// chat's filing instead, a thread kept aside would cost the turns asked
    /// since, or the filing would cost the turns only it holds. Never into a
    /// filing that doesn't read whole: joined with what decoded, the rest
    /// would be written over.
    func merge(_ entries: [AskThreadEntry<Row>], filingIfNew: Bool, at now: Date = .now) -> AskArchiveMerge {
        guard !entries.isEmpty else { return .notFiled }
        let index = readIndex()
        guard let earlier = index.threads.first(where: { $0.id != provisional && $0.isSameChat(as: entries) }) else {
            guard filingIfNew else { return .noSuchChat }
            return file(entries, as: UUID(), in: index, at: now, sparing: nil).map(AskArchiveMerge.filed) ?? .notFiled
        }
        guard let url = url(for: earlier.id) else { return .notFiled }
        let merged: [AskThreadEntry<Row>]
        switch contents(of: url).read {
        case .thread(let filed, let dropped) where dropped == 0:
            merged = AskThreadEntry.merging(entries, into: filed)
        case .empty:
            merged = entries
        default:
            return .notFiled
        }
        return file(merged, as: earlier.id, in: index, at: now, sparing: nil).map(AskArchiveMerge.filed) ?? .notFiled
    }

    /// File turns that are on screen and kept nowhere else yet, under `id`,
    /// written over what an earlier call filed there, and say what was filed:
    /// the turns a caller can't write where they belong, such as those asked
    /// beside a thread that couldn't be read.
    ///
    /// **Provisional.** The cap doesn't count it, so it trims no chat, which
    /// it would take for good: the turns go back where they belong once they
    /// can, and the filing with them (`endProvisional(removing:)`), or their
    /// chat is filed over it (`fileTheChatOnScreen(_:at:sparing:)`). Until
    /// then the list holds one chat past the cap. Filed under the caller's id,
    /// not found by its turns: a first turn asked again is asked at another
    /// moment, and would be a chat anew to `isSameChat`.
    @discardableResult
    package func fileProvisionally(_ entries: [AskThreadEntry<Row>], as id: UUID, at now: Date = .now) -> AskThreadSummary? {
        guard !entries.isEmpty else { return nil }
        provisional = id
        return file(entries, as: id, in: readIndex(), at: now, sparing: nil)
    }

    /// End the provisional filing, if any: removed when its turns are kept
    /// elsewhere now, and otherwise left as an ordinary filing, which the cap
    /// counts and a filing of the same chat replaces. Says whether a removal
    /// took (`remove(_:)`).
    @discardableResult
    package func endProvisional(removing: Bool) -> Bool {
        guard let id = provisional else { return true }
        provisional = nil
        return removing ? remove(id) : true
    }

    /// Write what came of a proposal into the filing that holds the turn it
    /// was made on, asked `question` at `askedAt`, in place of the
    /// `.performing` it was filed with (`AskThreadEntry.settlingProposal`),
    /// and say whether a filing took it.
    ///
    /// How a perform that outlasts its chat on screen, ended by New Chat or by
    /// an earlier chat opened in its place, still reaches the card: the chat
    /// read back says what came of it, and never offers the action again.
    /// Only the chat's file is written, since its title, dates and count are
    /// as they were, and only a filing every turn of which decodes: written
    /// back from what decoded, it would lose the rest.
    @discardableResult
    package func settleProposal(asked question: String, at askedAt: Date, with outcome: AskProposalOutcome) -> Bool {
        var settledAny = false
        // Every filing, not only those whose listed dates span the turn: a
        // list written before its chat's last filing names older dates, and a
        // yes left unsettled reads as an outcome nobody knows. One filing
        // holds the turn, but for a chat filed beside one that didn't read
        // whole.
        for summary in readIndex().threads where !pendingDeletions.contains(summary.id) {
            guard let url = url(for: summary.id), case .thread(let entries, dropped: 0) = contents(of: url).read,
                  let settled = AskThreadEntry.settlingProposal(asked: question, at: askedAt, with: outcome, in: entries)
            else { continue }
            do {
                try write(JSONEncoder().encode(settled), to: url)
                settledAny = true
            } catch {
                logger.error("a proposal's outcome could not be written to its chat: \(AskStoredFile.tag(for: error), privacy: .public)")
            }
        }
        return settledAny
    }

    /// Write a chat as `id` and list it, trimming the list to the cap.
    ///
    /// The cap takes the oldest of the other chats, never this one. A chat
    /// opened from the list and ended again is filed with the date of its
    /// last turn, which can be older than every other chat's, and trimmed as
    /// the oldest it would be deleted as it was filed while its summary told
    /// the caller it was kept. Neither `spared` nor the provisional filing
    /// counts, and filing the provisional one trims nothing.
    ///
    /// `absorbed` is a filing whose turns these entries hold: it leaves the
    /// list in the same write, named there as deleted until its file is gone
    /// (`AskThreadIndex.deleted`).
    private func file(
        _ entries: [AskThreadEntry<Row>], as id: UUID, in index: AskThreadIndex, at now: Date, sparing spared: UUID?,
        absorbing absorbed: UUID? = nil
    ) -> AskThreadSummary? {
        let kept = Array(entries.suffix(AskThreadStore<Row>.maxPersistedTurns))
        guard let url = url(for: id),
              let summary = AskThreadSummary.of(kept, id: id, fallbackDate: now) else { return nil }
        do {
            try write(JSONEncoder().encode(kept), to: url)
        } catch {
            logger.error("an earlier chat could not be written: \(AskStoredFile.tag(for: error), privacy: .public)")
            return nil
        }
        // Filed, so a removal of this id that hadn't taken is over. Left
        // remembered, the chat just written would read as deleted, and the
        // index would carry it as deleted for the next read to sweep away.
        pendingDeletions.remove(id)
        var index = index
        index.threads.removeAll { $0.id == id || $0.id == absorbed }
        if let absorbed { pendingDeletions.insert(absorbed) }
        index.threads.append(summary)
        index.threads.sort { $0.updatedAt > $1.updatedAt }
        let others = index.threads.filter { $0.id != spared && $0.id != provisional && $0.id != id }
        let trimmed = Set(others.dropFirst(id == provisional ? Self.maxThreads : Self.maxThreads - 1).map(\.id))
        for dropped in trimmed where !removeFile(for: dropped) {
            pendingDeletions.insert(dropped)
        }
        index.threads.removeAll { trimmed.contains($0.id) }
        let indexWritten = writeIndex(index)
        // An index that didn't take still names the chats the cap trimmed,
        // whose files are gone, and the next read would list them, opening
        // onto nothing. Remembered as deleted, they stay off the list until an
        // index that doesn't name them is written.
        if !indexWritten { pendingDeletions.formUnion(trimmed) }
        if let absorbed, removeFile(for: absorbed), indexWritten {
            pendingDeletions.remove(absorbed)
        }
        return summary
    }

    /// Forget one earlier chat, and say whether it is gone from the disk.
    ///
    /// False when its file wouldn't go or the index couldn't be written. The
    /// chat stays off the list either way: the archive remembers the
    /// deletion, in the index when it can be written, and tries the file
    /// again on every read. So a caller has nothing to undo.
    @discardableResult
    package func remove(_ id: UUID) -> Bool {
        let fileGone = removeFile(for: id)
        if !fileGone { pendingDeletions.insert(id) }
        let (index, named) = loadIndex()
        // Nothing to write when the index on disk is known not to name the
        // chat and its file is gone: no read will list it. An index there
        // that won't read may name it, and would list it once it reads.
        if fileGone, let named, !named.contains(id) { return true }
        var listed = index
        listed.threads.removeAll { $0.id == id }
        let indexWritten = writeIndex(listed)
        // An index on disk that still names the chat, or may, would list it
        // on the next read, file or no file.
        if !indexWritten && named?.contains(id) != false { pendingDeletions.insert(id) }
        return fileGone && indexWritten
    }

    /// Forget every earlier chat: the list's Delete All Chats. Says whether
    /// they are gone from the disk.
    ///
    /// Every chat file in the folder rather than each chat the index names,
    /// so a chat file an interrupted write left out of the index goes too,
    /// instead of waiting on disk for an index rebuild to list it again. Then
    /// the index, then the folder, but only once nothing else is in it.
    ///
    /// **Only the archive's own files.** The folder can be a host's
    /// (`directory:`), such as an App Group container that holds a widget's
    /// files too, and Delete All Chats is no licence to delete what else is
    /// there. The next filing makes the folder afresh if it went.
    ///
    /// On false, every chat left is remembered as deleted, as `remove(_:)`
    /// remembers one, and stays off the list. False too for a folder that
    /// won't list, which names no chat file: read as empty, the index would
    /// go and every chat be reported gone while their files stayed, to come
    /// back once the folder lists. The index stays, as the record of which
    /// chats were there.
    @discardableResult
    package func removeAll() -> Bool {
        guard let directory else { return true }
        guard let chatFiles = chatFileIDs(in: directory) else {
            logger.error("the chat folder could not be listed, so every chat is remembered as deleted")
            oweEveryChat(in: directory)
            return false
        }
        let stranded = chatFiles.filter { !removeFile(for: $0) }
        let indexGone: Bool
        do {
            try FileManager.default.removeItem(at: directory.appending(path: Self.indexName))
            indexGone = true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Nothing was ever filed, or the index went with an earlier try.
            indexGone = true
        } catch {
            logger.error("the chat index could not be deleted: \(AskStoredFile.tag(for: error), privacy: .public)")
            indexGone = false
        }
        guard stranded.isEmpty, indexGone else {
            oweEveryChat(in: directory)
            return false
        }
        removeFolderIfEmpty(directory)
        pendingDeletions = []
        provisional = nil
        return true
    }

    /// What Delete All Chats does where it couldn't delete every chat:
    /// remember each one it knows of as deleted, those the index names or
    /// lists and those whose files the folder lists, and write an index that
    /// lists none of them and carries them all.
    private func oweEveryChat(in directory: URL) {
        let (index, named) = loadIndex()
        pendingDeletions.formUnion(named ?? [])
        pendingDeletions.formUnion(index.threads.map(\.id))
        pendingDeletions.formUnion(chatFileIDs(in: directory) ?? [])
        writeIndex(AskThreadIndex())
        provisional = nil
    }

    /// Delete the folder when nothing is left in it: the archive's own files
    /// are gone, and a file of anyone else's keeps it.
    private func removeFolderIfEmpty(_ directory: URL) {
        guard AskStoredFile.names(in: directory)?.isEmpty == true else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone.
        } catch {
            logger.error("the empty chat folder could not be deleted: \(AskStoredFile.tag(for: error), privacy: .public)")
        }
    }

    // MARK: - Files

    private func url(for id: UUID) -> URL? {
        directory?.appending(path: "\(id.uuidString).json")
    }

    private func readIndex() -> AskThreadIndex {
        loadIndex().index
    }

    /// The list as a read gives it, and the chats the index on disk names:
    /// none where there is no index, and nil where there is one that won't
    /// read, which may name any chat.
    ///
    /// **An index that won't read is not no index.** No index (260) is a
    /// fresh install, or one lost between two writes. One that is there and
    /// won't read, locked, damaged, past the ceiling or written by a later
    /// build, is rebuilt from the chat files too, but taken for none it would
    /// close every deletion whose file is gone while it may still name the
    /// chat, and lose the deletions it carries.
    private func loadIndex() -> (index: AskThreadIndex, named: Set<UUID>?) {
        guard let directory else { return (AskThreadIndex(), []) }
        var index = AskThreadIndex()
        var named: Set<UUID>?
        do {
            let data = try AskStoredFile.contents(of: directory.appending(path: Self.indexName))
            do {
                index = try JSONDecoder().decode(AskThreadIndex.self, from: data)
                named = Set(index.threads.map(\.id))
            } catch {
                logger.error("the chat index on disk is not one, rebuilding it: \(AskStoredFile.tag(for: error), privacy: .public)")
                // Its deletions where they still decode: rebuilt without
                // them, a chat whose file wouldn't go would be listed again,
                // and the next index written would name it for good.
                pendingDeletions.formUnion(AskThreadIndex.deletions(in: data))
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // No index and no chats is a fresh install. No index beside chat
            // files is an index lost between two writes, and the chat files
            // list themselves below.
            named = []
        } catch {
            logger.error("the chat index could not be read, rebuilding it: \(AskStoredFile.tag(for: error), privacy: .public)")
        }
        // A deletion is done once its file is gone and no index on disk names
        // the chat, which an index that won't read may. Until then the chat
        // stays off the list, and its file is tried again.
        pendingDeletions.formUnion(index.deleted)
        for id in pendingDeletions where removeFile(for: id, logging: false) && named?.contains(id) == false {
            pendingDeletions.remove(id)
        }
        index.threads.removeAll { pendingDeletions.contains($0.id) }
        return (withUnlistedChats(index, in: directory), named)
    }

    /// The index with every chat file it doesn't name added, for each that
    /// reads. Not written back here: the next write does that. A file that
    /// won't read is left off, and read again next time, and so is a chat
    /// deleted whose file is still there.
    private func withUnlistedChats(_ index: AskThreadIndex, in directory: URL) -> AskThreadIndex {
        guard let names = AskStoredFile.names(in: directory) else { return index }
        let listed = Set(index.threads.map(\.id))
        var threads = index.threads
        for name in names where name.hasSuffix(".json") && name != Self.indexName {
            guard let id = UUID(uuidString: String(name.dropLast(".json".count))),
                  !listed.contains(id), !pendingDeletions.contains(id) else { continue }
            let file = directory.appending(path: name)
            let (read, failure, _) = contents(of: file)
            guard case .thread(let entries, _) = read else {
                if let failure, unlistedFailures.insert(id).inserted {
                    logger.error("an earlier chat the list doesn't name \(failure, privacy: .public)")
                }
                continue
            }
            unlistedFailures.remove(id)
            // A required-reason API: Resources/PrivacyInfo.xcprivacy declares
            // the file timestamp for C617.1, a file in the app's own container.
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let summary = AskThreadSummary.of(entries, id: id, fallbackDate: modified ?? .distantPast) {
                threads.append(summary)
            }
        }
        guard threads.count > index.threads.count else { return index }
        threads.sort { $0.updatedAt > $1.updatedAt }
        var rebuilt = index
        rebuilt.threads = threads
        return rebuilt
    }

    /// The chats whose files are in `directory`, listed or not, or nil for a
    /// folder that won't list (`AskStoredFile.names(in:)`).
    private func chatFileIDs(in directory: URL) -> [UUID]? {
        AskStoredFile.names(in: directory)?.compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            return UUID(uuidString: String(name.dropLast(".json".count)))
        }
    }

    /// Write the index, carrying every deletion that hasn't taken, and say
    /// whether it was written.
    @discardableResult
    private func writeIndex(_ index: AskThreadIndex) -> Bool {
        guard let directory else { return false }
        var index = index
        index.deleted = pendingDeletions.sorted { $0.uuidString < $1.uuidString }
        do {
            try write(JSONEncoder().encode(index), to: directory.appending(path: Self.indexName))
            return true
        } catch {
            logger.error("the chat index could not be written: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
    }

    /// Delete a chat's file, and say whether it is gone, which it is when it
    /// was never there. Logged only where the deletion is first asked for: the
    /// retry on every read would log the same failure each time.
    private func removeFile(for id: UUID, logging: Bool = true) -> Bool {
        guard let url = url(for: id) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone.
        } catch {
            if logging {
                logger.error("an earlier chat could not be deleted: \(AskStoredFile.tag(for: error), privacy: .public)")
            }
            return false
        }
        return true
    }

    /// Every file the archive writes, as the thread's are (`AskStoredFile`),
    /// in `threads/`, its own folder. Made on every write, so a folder
    /// removed while the app runs, or by Delete All Chats, costs no write
    /// after it.
    private func write(_ data: Data, to url: URL) throws {
        try AskStoredFile.write(data, to: url, ownFolder: true, logger: logger)
    }
}
