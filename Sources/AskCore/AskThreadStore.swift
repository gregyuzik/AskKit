public import Foundation
import os

/// One turn of the thread as it is kept on disk.
///
/// **Every field added after the first release must be `decodeIfPresent`.**
/// The synthesized decoder throws on an absent key, and an entry that throws
/// is left out of the thread (`AskThreadStore.load()` counts it, and keeps the
/// file whole for a build that reads it): every reader would lose sight of
/// that turn on the first launch after an update, and no later build that
/// needs the key would bring it back. That is why the decoder below is
/// hand-written rather than left to the compiler.
nonisolated public struct AskThreadEntry<Row: AskRow>: Codable, Sendable, Equatable {
    /// The question as the reader asked it.
    public let question: String
    /// The prose as far as it got, kept even when the turn failed, so a
    /// failure renders *beneath* what was already said rather than wiping it.
    public let text: String
    /// The answer: a finished one, or a truncated one that the deadline or a
    /// stop left. Nil for a turn that failed.
    public let answer: AskAnswer<Row>?
    /// The failure line as it read when the turn was written.
    ///
    /// Kept as the fallback for an entry with no `failure` to decode, and for
    /// one whose case this build doesn't know. `failure` is what the line is
    /// rendered from whenever it decodes.
    public let failureMessage: String?
    /// The typed failure, so the line can be rendered again in the reader's
    /// current language rather than replayed in the one they had.
    public let failure: AskError?
    /// Whether the failure offered Try Again when the turn was written. A
    /// build that decodes `failure` asks the case instead
    /// (`AskError.isRetryable`).
    public let failureIsRetryable: Bool
    /// Whether the reader stopped the turn: with its words kept as a
    /// truncated answer, or before it had any (`AskError.stopped`). False for
    /// a stop the reader didn't ask for.
    public let stopped: Bool
    /// The tier that answered. Nil for an answer the domain gave without a
    /// model, for a turn that ended before a tier was chosen, and for a tier
    /// this build has no case for.
    public let tier: AskTier?
    /// When the question was asked, for the date line above the thread's
    /// first turn and above the first turn of each later day. Nil for an entry
    /// that carries no date, which a restored turn then dates to when it was
    /// read.
    public let askedAt: Date?
    /// The turn started a fresh session with a recap
    /// (`AskTurnEvent.summarized`), so AskUI draws the "Earlier in this chat
    /// is summarized" hairline above it.
    public let summarizedBefore: Bool
    /// The reader's thumbs on this answer, so a thread read back shows the
    /// verdict it was given rather than asking again.
    public private(set) var feedback: AskFeedback.Sentiment?
    /// What the reader did with the answer's proposal, so a thread read back
    /// shows the card as they left it rather than asking again: `.performing`
    /// from the reader's yes until the app says what came of it. Read back as
    /// `.performing` too when an outcome was written that this build can't
    /// decode (`init(from:)`).
    public private(set) var proposalOutcome: AskProposalOutcome?
    /// The photo the question was asked with: what it shows and where the
    /// host keeps it, never its pixels.
    public let photo: AskQuestionPhoto?
    /// Whether the model that answered was sent the photo, so a thread read
    /// back still says when an answer read only the words.
    public let answerSawPhoto: Bool

    /// An entry with each field as given. AskUI writes one for each finished
    /// turn (`AskTurn.entry`).
    public init(
        question: String,
        text: String,
        answer: AskAnswer<Row>?,
        failureMessage: String? = nil,
        failure: AskError? = nil,
        failureIsRetryable: Bool = false,
        stopped: Bool = false,
        tier: AskTier? = nil,
        askedAt: Date? = nil,
        summarizedBefore: Bool = false,
        feedback: AskFeedback.Sentiment? = nil,
        proposalOutcome: AskProposalOutcome? = nil,
        photo: AskQuestionPhoto? = nil,
        answerSawPhoto: Bool = false
    ) {
        self.question = question
        self.text = text
        self.answer = answer
        self.failureMessage = failureMessage
        self.failure = failure
        self.failureIsRetryable = failureIsRetryable
        self.stopped = stopped
        self.tier = tier
        self.askedAt = askedAt
        self.summarizedBefore = summarizedBefore
        self.feedback = feedback
        self.proposalOutcome = proposalOutcome
        self.photo = photo
        self.answerSawPhoto = answerSawPhoto
    }

    /// Decodes an entry field by field. Every field but the question has a
    /// default, so a thread written before a field existed still decodes, and
    /// a failure, a tier, a verdict or a photo that a newer build wrote
    /// differently costs only itself. A proposal's outcome is the exception,
    /// which reads as one nothing has answered yet.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decode(String.self, forKey: .question)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        answer = try container.decodeIfPresent(AskAnswer<Row>.self, forKey: .answer)
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        // `try?` and not `try`: a case written by a newer build is a stale
        // line, which `failureMessage` still holds, never a lost turn.
        failure = try? container.decodeIfPresent(AskError.self, forKey: .failure)
        failureIsRetryable = try container.decodeIfPresent(Bool.self, forKey: .failureIsRetryable) ?? false
        stopped = try container.decodeIfPresent(Bool.self, forKey: .stopped) ?? false
        // `try?`, as for `failure`: a tier a newer build answered on costs the
        // caption and the turn's place in a recap, never the turn.
        tier = try? container.decodeIfPresent(AskTier.self, forKey: .tier)
        askedAt = try container.decodeIfPresent(Date.self, forKey: .askedAt)
        summarizedBefore = try container.decodeIfPresent(Bool.self, forKey: .summarizedBefore) ?? false
        // `try?`, as for `failure`: a verdict a newer build wrote is a lost
        // thumb, never a lost turn.
        feedback = try? container.decodeIfPresent(AskFeedback.Sentiment.self, forKey: .feedback)
        // An outcome this build can't decode never loses the turn either, and
        // never reads as none: on the newest turn, none offers the card's
        // action again, and what a newer build wrote there, or a damaged
        // field held, may say it ran. Read as a perform nothing has answered,
        // the card takes no tap (`AskProposalPhase.outcomeUnknown`), so the
        // action is never done twice. Absent or null is still none.
        do {
            proposalOutcome = try container.decodeIfPresent(AskProposalOutcome.self, forKey: .proposalOutcome)
        } catch {
            proposalOutcome = .performing
        }
        // And again: a photo a newer build described differently costs the
        // thumbnail and the line under the question, never the turn.
        photo = try? container.decodeIfPresent(AskQuestionPhoto.self, forKey: .photo)
        answerSawPhoto = try container.decodeIfPresent(Bool.self, forKey: .answerSawPhoto) ?? false
    }
}

/// The thread array, decoded one entry at a time.
///
/// At file scope because a generic function can't nest a type, and it has to
/// be generic over `Row` to decode an entry at all.
nonisolated private struct AskSalvagedThread<Row: AskRow>: Decodable {
    var entries: [AskThreadEntry<Row>] = []
    var dropped = 0

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            do {
                entries.append(try container.decode(AskThreadEntry<Row>.self))
            } catch {
                // A throwing `decode` leaves the element unconsumed, so
                // without this the loop never advances. `AskSkippedEntry`
                // decodes anything and keeps nothing.
                _ = try? container.decode(AskSkippedEntry.self)
                dropped += 1
            }
        }
    }
}

/// Consumes one element of any shape, so a failed entry can be stepped over.
nonisolated private struct AskSkippedEntry: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

nonisolated extension AskThreadEntry {
    /// `base` with every turn of `extra` that it lacks put back where `extra`
    /// had it, after the turn it followed there, and every turn in the order
    /// it was asked.
    ///
    /// How a thread's original goes back into its chat once a build reads it
    /// whole: `base` is the chat as written since, without the turns the build
    /// before couldn't read. How AskUI joins a thread read back with a filing
    /// of its chat, `base` being the thread, and opens the filing of the chat
    /// on screen, `base` being the screen's. Either copy may be the older,
    /// since a save that failed leaves the one on disk behind the filing New
    /// Chat made. So:
    ///
    /// - Where both hold a turn, `base`'s copy is kept, with what only
    ///   `extra`'s settled (`settled(with:)`): a proposal's outcome lost to
    ///   the older would offer its action again.
    /// - A failed turn only one copy holds goes where the other holds a later
    ///   turn asking the same question: that is a turn Try Again replaced
    ///   (`isReplaced(by:)`). Put back, it would be the newest turn, or sit
    ///   above the one asked again, with Try Again on it again.
    /// - The turns are in the order they were asked where both have a date;
    ///   an undated turn keeps the place its copy gave it.
    package static func merging(_ extra: [Self], into base: [Self]) -> [Self] {
        var merged = base.map { (entry: $0, inBoth: false) }
        var previous: Int?
        for turn in extra {
            if let held = merged.firstIndex(where: { $0.entry.isSameTurn(as: turn) }) {
                merged[held] = (merged[held].entry.settled(with: turn), true)
                previous = held
                continue
            }
            let index = previous.map { $0 + 1 } ?? 0
            merged.insert((turn, false), at: index)
            previous = index
        }
        // Only one copy holds the turn, so the other copy is the one that
        // can hold what replaced it: a turn the base lacks came from `extra`.
        let kept = merged.filter { turn in
            turn.inBoth || !turn.entry.isReplaced(by: base.contains { $0.isSameTurn(as: turn.entry) } ? extra : base)
        }
        return inTheOrderAsked(kept.map(\.entry))
    }

    /// Whether this is a failed turn that Try Again replaced, as `turns`
    /// show: they ask its question again, later. A failure carries nothing
    /// the reader would lose; the turn asked again carries the answer.
    private func isReplaced(by turns: [Self]) -> Bool {
        guard answer == nil, failure != nil || failureMessage != nil, let askedAt else { return false }
        return turns.contains { other in
            other.question == question && other.askedAt.map { $0 > askedAt } == true
        }
    }

    /// The turns in the order they were asked where they carry a date, each
    /// undated turn left where it is.
    private static func inTheOrderAsked(_ turns: [Self]) -> [Self] {
        let dated = turns.indices.filter { turns[$0].askedAt != nil }
        let ordered = dated.sorted { lhs, rhs in
            // The order they came in breaks a tie.
            guard let left = turns[lhs].askedAt, let right = turns[rhs].askedAt, left != right else { return lhs < rhs }
            return left < right
        }
        var result = turns
        for (slot, source) in zip(dated, ordered) {
            result[slot] = turns[source]
        }
        return result
    }

    /// This copy of a turn with what `other`'s settled that this one hadn't:
    /// a proposal's outcome further on, or a verdict where this one has none.
    /// Two verdicts that differ keep this one's. Everything else is this
    /// copy's: a copy, so a field added later is kept too.
    private func settled(with other: Self) -> Self {
        var settled = self
        if Self.progress(of: other.proposalOutcome) > Self.progress(of: proposalOutcome) {
            settled.proposalOutcome = other.proposalOutcome
        }
        if feedback == nil { settled.feedback = other.feedback }
        return settled
    }

    /// How far on a proposal's outcome is. A failure is offered again, so
    /// every other outcome is further. A perform nothing has answered yet is
    /// further than a failure too: the failure can be the attempt before the
    /// reader confirmed again, and offered again on it, the action could be
    /// done twice. So of two copies, one that says a perform is out wins over
    /// a failure, and gives way only to what came of it.
    private static func progress(of outcome: AskProposalOutcome?) -> Int {
        switch outcome {
        case nil: 0
        case .failed: 1
        case .performing: 2
        case .confirmed, .handedOff, .declined: 3
        }
    }

    /// `entries` with what came of the proposal made on the turn asked
    /// `question` at `askedAt` in place of the `.performing` it was written
    /// with, or nil where none of them is that turn waiting on its perform.
    ///
    /// How a perform that returns once its turn has left the screen writes
    /// its outcome into the copy of the chat that holds the turn now: replaced
    /// outright rather than joined (`merging`), since a failure is further
    /// back than a perform that is out, and this one is the perform's own
    /// answer.
    package static func settlingProposal(
        asked question: String, at askedAt: Date, with outcome: AskProposalOutcome, in entries: [Self]
    ) -> [Self]? {
        guard let index = entries.firstIndex(where: {
            $0.question == question && $0.askedAt == askedAt && $0.proposalOutcome == .performing
        }) else { return nil }
        var settled = entries
        settled[index].proposalOutcome = outcome
        return settled
    }

    /// A turn is known by its question and when it was asked, to the fraction
    /// of a second, as `AskThreadSummary.isSameChat` knows one. A turn with no
    /// date has only its words to go by.
    private func isSameTurn(as other: Self) -> Bool {
        guard question == other.question else { return false }
        guard askedAt != nil || other.askedAt != nil else { return text == other.text }
        return askedAt == other.askedAt
    }
}

/// What a read of the thread found.
///
/// Three cases rather than an array, because "no thread" and "a thread that
/// couldn't be read" call for opposite behavior, and an array can't tell them
/// apart. Read as an empty array, a failed read would look exactly like a
/// fresh install, and the next finished turn would write a one-turn thread
/// over the reader's whole conversation. The return type makes that
/// unrepresentable.
nonisolated public enum AskThreadRead<Row: AskRow>: Sendable {
    /// Entries that decoded. `dropped` counts the ones beside them that
    /// didn't: a host can evolve a `Row` past what is on disk, and showing
    /// the turns that still decode beats showing none.
    ///
    /// Never every turn dropped: that thread is `.unreadable`. And for the
    /// current thread, never a drop without the file kept whole first
    /// (`AskThreadStore.load()`), so writing these entries back costs the
    /// reader nothing.
    case thread([AskThreadEntry<Row>], dropped: Int)
    /// No file. A fresh install, or New Chat.
    case empty
    /// A file that is there and couldn't be read: its bytes aren't a thread
    /// this build can decode, none of its turns decode, or they couldn't be
    /// read at all (a locked device). Nothing may be written over it.
    case unreadable

    /// The entries, or none, for a test that only wants to read what was
    /// written. Package, not public: read as an empty array, a failed read
    /// looks like a fresh install, and a save after it would write a
    /// one-turn thread over the reader's whole conversation, the very
    /// confusion the three cases exist to prevent.
    package var entries: [AskThreadEntry<Row>] {
        if case .thread(let entries, _) = self { return entries }
        return []
    }
}

/// The thread on disk, so a conversation survives a relaunch the way a chat is
/// expected to.
///
/// Not the model's session: that lives and dies with the process, and a
/// question asked on a restored thread starts a fresh session with a recap.
/// Device-local and excluded from backup: a thread is a conversation about
/// the host's data, not a record of it. Written after a turn ends, never
/// mid-stream, so a crash mid-answer costs that answer and nothing before it.
/// Every file is written, read and listed through `AskStoredFile`: under
/// complete file protection except on a Mac, and never past
/// `AskStoredFile.maxBytes`.
///
/// **Writes happen off the main actor,** so encoding and writing the whole
/// thread never lands on the frame that ends a turn.
///
/// `ask-thread.json` is the current thread. The chats before it live beside it
/// in `threads/`, which is `AskThreadArchive`'s. Two kinds of file wait beside
/// it for a build that reads more than this one:
/// - a thread this build could make nothing of, set aside as
///   `ask-thread-unreadable-<id>.json`, until a launch that can read it files
///   it with the earlier chats;
/// - the original of a thread this build read only in part, kept as
///   `ask-thread-original-<id>.json`, until a launch that reads it whole puts
///   the turns this one couldn't back into their chat.
///
/// **A host only makes one, to hand to `AskConversationStore`.** The
/// initializer, to keep the thread somewhere of its own (`url:`), and
/// `maxPersistedTurns` are all that is public; what reads, writes and deletes
/// the files is AskKit's own (`package`). The rules that keep a reader's
/// turns, that a thread read in part or not at all is never written over and
/// that the only copy of a chat is never deleted, span this file and the
/// archive, and only the conversation store keeps them: called from anywhere
/// else, `clear()` alone could delete the one copy of a chat. Nor is a read a
/// bare read: `load()` keeps a thread read in part whole beside it first. A
/// host that takes AskCore alone keeps its thread its own way.
public actor AskThreadStore<Row: AskRow> {
    private let logger: Logger

    /// The path only. `init` isn't async and is called from the main actor,
    /// so it does string work alone, and every write makes the folder it
    /// needs, off the main actor.
    private let url: URL?

    /// How many turns are kept: the newest 50.
    ///
    /// Every entry embeds the rows behind its answer (`AskAnswer.matches`: up
    /// to `AskCollector.maxTurnRows`, or `maxThreadRows` for a follow-up that
    /// read none) and its tiles, so the file grows with turns times rows, and
    /// every write encodes all of it. Fifty turns is far past what a reader
    /// scrolls back through, and still bounds the write.
    public static var maxPersistedTurns: Int { 50 }

    /// A store for the thread at
    /// `Application Support/<appDirectory>/ask-thread.json`.
    ///
    /// - Parameters:
    ///   - appDirectory: the folder under `Application Support`:
    ///     `AskBrand.appDirectory`.
    ///   - url: an explicit file, for tests. Overrides `appDirectory`.
    ///   - logSubsystem: the subsystem the store logs under:
    ///     `AskBrand.logSubsystem`. Nil logs under the app's bundle identifier.
    public init(appDirectory: String, url: URL? = nil, logSubsystem: String? = nil) {
        logger = Logger(subsystem: AskBrand.subsystem(logSubsystem), category: "thread-store")
        self.url = url ?? Self.defaultURL(appDirectory: appDirectory)
        if url == nil, !AskBrand.isOneFolder(appDirectory) {
            logger.fault("""
                \(appDirectory.debugDescription, privacy: .public) is not one folder under Application Support, \
                so the Ask thread is neither read nor written
                """)
        } else if self.url == nil {
            logger.error("no Application Support directory for the Ask thread")
        }
    }

    /// The thread's file, or nil for a store that has none and reads and
    /// writes nothing. What tells two stores over one thread apart from two
    /// over their own.
    package nonisolated var fileURL: URL? { url }

    /// `Application Support/<appDirectory>/ask-thread.json`, the path only,
    /// or nil for a name that isn't one folder (`AskBrand.appDirectory`).
    /// The directory is made by a write, not here.
    static func defaultURL(appDirectory: String) -> URL? {
        AskBrand.appFolder(appDirectory)?.appending(path: "ask-thread.json")
    }

    /// The thread as last written.
    ///
    /// **Entry by entry, keeping what parses.** Decoded as one value, a
    /// single `Row` that a host had evolved past, which is the layer AskKit
    /// doesn't control, would throw the whole array, and the thread would be
    /// gone. The entry decoders (`AskThreadEntry`'s and `AskAnswer`'s) use
    /// `decodeIfPresent` for the same reason, and decoding the array whole
    /// would undo them one level up.
    ///
    /// **What didn't parse is never written over.** The caller writes back
    /// only the turns it was handed, so a thread read in part is first kept
    /// whole beside the thread, as its original, and a launch that reads all
    /// of it puts the rest back (`recoverSetAside`). If the original can't be
    /// kept, the read is `.unreadable` rather than a thread the next save
    /// would cut down. A thread none of whose turns parse is `.unreadable`
    /// too: read as no turns, it would look like a fresh install, and the
    /// next answer would write a one-turn thread over all of it.
    package func load() -> AskThreadRead<Row> {
        guard let url else { return .empty }
        let data: Data
        do {
            data = try AskStoredFile.contents(of: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // `fileReadNoSuchFile` (260), not `fileNoSuchFile` (4): reading
            // and removing report a missing file with different codes, and the
            // wrong one turns "no thread yet" into "unreadable", which locks
            // persistence off for every fresh install.
            return .empty
        } catch {
            // Not "no thread". Something is there and can't be read, or is
            // past the ceiling, and the caller must not write over it.
            logger.error("the Ask thread could not be read: \(AskStoredFile.tag(for: error), privacy: .public)")
            return .unreadable
        }
        let decoded: (entries: [AskThreadEntry<Row>], dropped: Int, droppedRows: Int)
        do {
            decoded = try Self.decodeEntries(from: data)
        } catch {
            logger.error("the Ask thread on disk is not a thread: \(AskStoredFile.tag(for: error), privacy: .public)")
            return .unreadable
        }
        let (entries, dropped, droppedRows) = decoded
        if droppedRows > 0 {
            // Each costs its answer that row and nothing else, so nothing on
            // screen says so, and the next save writes the answers without
            // them: the host's row type no longer reads what it wrote.
            logger.error("""
                \(droppedRows, privacy: .public) row(s) in the Ask thread on disk no longer decode, \
                and are left out of their answers
                """)
        }
        guard dropped > 0 else { return .thread(entries, dropped: 0) }
        guard !entries.isEmpty else {
            logger.error("none of the \(dropped, privacy: .public) Ask turn(s) on disk decode")
            return .unreadable
        }
        guard keepOriginal(data) else {
            logger.error("\(dropped, privacy: .public) Ask turn(s) on disk no longer decode, and the thread could not be kept whole")
            return .unreadable
        }
        logger.error("\(dropped, privacy: .public) Ask turn(s) on disk no longer decode; the thread is kept whole beside them")
        return .thread(entries, dropped: dropped)
    }

    /// Decode the array element by element, counting the turns that didn't
    /// decode and the rows left out of the answers that did
    /// (`AskDroppedRows`). Throws only when the top level isn't an array at
    /// all, when there is nothing to salvage.
    static func decodeEntries(from data: Data) throws -> (entries: [AskThreadEntry<Row>], dropped: Int, droppedRows: Int) {
        let droppedRows = AskDroppedRows()
        let decoder = JSONDecoder()
        if let key = AskDroppedRows.key { decoder.userInfo[key] = droppedRows }
        let salvaged = try decoder.decode(AskSalvagedThread<Row>.self, from: data)
        return (salvaged.entries, salvaged.dropped, droppedRows.total)
    }

    /// Write the thread, and say whether it is on disk. An empty thread
    /// removes the file, as `clear()` does.
    ///
    /// Capped at `maxPersistedTurns`, oldest dropped. Written as every file
    /// here is (`AskStoredFile.write(_:to:ownFolder:logger:)`): atomically,
    /// excluded from backup, and with complete file protection except on a
    /// Mac, so a whole chat transcript isn't readable on a device that is
    /// locked after being unlocked once. A thread past
    /// `AskStoredFile.maxBytes` isn't written: it would never read back.
    ///
    /// **False means these turns may not be on disk here.** A caller must then
    /// keep every other copy of them: not delete the chat it opened from the
    /// archive (`AskThreadArchive.remove(_:)`), and not write anything else
    /// over the chat they replace. On the iOS family the complete protection
    /// above fails every write while the device is locked, and nothing writes
    /// the thread again until the next turn ends, so a turn that ends after
    /// the lock is lost if the process dies first: a caller should save
    /// again once protected data is available
    /// (`UIApplication.protectedDataDidBecomeAvailableNotification`).
    @discardableResult
    package func save(_ entries: [AskThreadEntry<Row>]) -> Bool {
        guard let url else { return false }
        guard !entries.isEmpty else { return clear() }
        do {
            try write(JSONEncoder().encode(Array(entries.suffix(Self.maxPersistedTurns))), to: url)
            return true
        } catch {
            logger.error("the Ask thread could not be written: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
    }

    /// Every file this store writes, in the app's folder, which is the
    /// host's too, so it is made bare (`AskStoredFile`).
    private func write(_ data: Data, to file: URL) throws {
        try AskStoredFile.write(data, to: file, ownFolder: false, logger: logger)
    }

    /// Forget the thread on disk, as a chat ends: New Chat, for one. Says
    /// whether it is gone, which it is when there was none.
    ///
    /// A failure here isn't cosmetic: the screen reports the conversation
    /// gone, and until a save writes over it, a relaunch brings it back. On
    /// false, a caller that filed the chat first has lost nothing, and one
    /// deleting it at the reader's word should try again.
    @discardableResult
    package func clear() -> Bool {
        guard let url else { return true }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Already gone. New Chat on an empty thread.
        } catch {
            logger.error("the Ask thread could not be deleted: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - A thread that could not be read

    /// Move a thread whose bytes are not a thread out of the way, whole, and
    /// say whether it moved.
    ///
    /// Only one that was read and would not decode: bytes that aren't an
    /// array, or an array none of whose turns decode. And one past
    /// `AskStoredFile.maxBytes`, which no read takes. This build can make
    /// nothing of either, and the next answer needs its place. One that could
    /// not be read at all stays where it is, since a locked device makes a
    /// good thread unreadable for a while, and moving it would take it out of
    /// the reader's current chat for good. So does one read in part: it is a
    /// thread.
    package func setAsideIfNotAThread() -> Bool {
        guard let url else { return false }
        do {
            let data = try AskStoredFile.contents(of: url)
            if let decoded = try? Self.decodeEntries(from: data), !decoded.entries.isEmpty || decoded.dropped == 0 {
                return false
            }
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            // Past the ceiling: moved, whole, for a build that reads it.
        } catch {
            return false
        }
        return moveAside(url, unread: true)
    }

    /// Move the thread out of the way whatever it holds, and say whether it
    /// moved: the chat is ending, and a thread that could not be read is kept
    /// rather than deleted, since it was never shown to be worthless.
    package func setAside() -> Bool {
        guard let url else { return false }
        return moveAside(url, unread: false)
    }

    /// Put every file waiting beside the thread that now reads whole where it
    /// belongs, and say how many were.
    ///
    /// - A thread set aside goes to the earlier chats: a newer build may have
    ///   written it, or the device was locked when it was read. Into the
    ///   filing its chat already has, if one does, so neither copy's turns are
    ///   lost. Read only in part, what reads is filed and the file is kept
    ///   whole as an original, for a build that reads the rest.
    /// - An original goes back into its own chat: the thread, when the thread
    ///   is that chat, or else the earlier chat that is. When neither is, the
    ///   reader deleted that chat or the cap trimmed it, and the original goes
    ///   too rather than bring it back. Unless a turn in it has no date, which
    ///   leaves its chat unfindable: then it is filed as a chat of its own.
    ///
    /// Filed first and removed after, so an archive that cannot be written
    /// leaves the file for the next launch rather than losing it. One that
    /// still will not read whole stays too, and so does an original whose
    /// chat can't be read whole now: joined with what did read, the rest of
    /// that chat would be written over.
    ///
    /// **Before the thread is read**, since it may write the thread: called
    /// after, the turns put back would sit under a thread already on screen,
    /// and its next save would write over them.
    @discardableResult
    package func recoverSetAside(into archive: AskThreadArchive<Row>) async -> Int {
        var recovered = 0
        for file in setAsideFiles() {
            guard let data = try? AskStoredFile.contents(of: file),
                  case let (entries, dropped, _)? = try? Self.decodeEntries(from: data) else { continue }
            if entries.isEmpty {
                // Every turn dropped stays for a build that reads them. An
                // empty array holds nothing to keep.
                if dropped == 0 { remove(file) }
                continue
            }
            guard case .filed = await archive.merge(entries, filingIfNew: true) else { continue }
            recovered += 1
            if dropped == 0 {
                remove(file)
            } else {
                keepAsOriginal(file)
            }
        }
        for file in originalFiles() {
            guard let data = try? AskStoredFile.contents(of: file),
                  case let (entries, dropped, _)? = try? Self.decodeEntries(from: data), dropped == 0 else { continue }
            switch mergeIntoThread(entries) {
            case .merged:
                recovered += 1
                remove(file)
                continue
            case .notThisChat:
                break
            case .notWritten:
                continue
            }
            // A chat is found by its turns' dates (`AskThreadSummary.isSameChat`),
            // so with an undated turn among them, finding none proves nothing:
            // filed on its own, a chat may show twice, but nothing is lost.
            let isKnownByDate = entries.allSatisfy { $0.askedAt != nil }
            switch await archive.merge(entries, filingIfNew: !isKnownByDate) {
            case .filed:
                recovered += 1
                remove(file)
            case .noSuchChat:
                remove(file)
            case .notFiled:
                break
            }
        }
        if recovered > 0 {
            logger.notice("\(recovered, privacy: .public) Ask thread(s) kept aside now read, and were put back with their chats")
        }
        return recovered
    }

    /// What `mergeIntoThread` did.
    private enum ThreadMerge {
        case merged, notThisChat, notWritten
    }

    /// Put an original's turns back into the thread when the thread is the
    /// chat they came from. Before the thread is read, so the read finds them.
    private func mergeIntoThread(_ turns: [AskThreadEntry<Row>]) -> ThreadMerge {
        guard let url else { return .notThisChat }
        let data: Data
        do {
            data = try AskStoredFile.contents(of: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .notThisChat
        } catch {
            // Locked, say: it may be this chat, and the next launch can tell.
            return .notWritten
        }
        // A thread that doesn't read whole is left alone: written back with
        // these turns, it would lose its own that didn't decode.
        guard case let (thread, dropped, _)? = try? Self.decodeEntries(from: data), dropped == 0 else { return .notWritten }
        guard let summary = AskThreadSummary.of(thread, id: UUID(), fallbackDate: .distantPast),
              summary.isSameChat(as: turns) else { return .notThisChat }
        return save(AskThreadEntry.merging(turns, into: thread)) ? .merged : .notWritten
    }

    /// Forget every file waiting beside the thread, as Delete All Chats does,
    /// and hand back the names of those that wouldn't go, for
    /// `removeSetAside(named:)` to try again.
    ///
    /// **Names, so a retry deletes these and nothing else.** A file set aside
    /// after Delete All Chats, by a New Chat that couldn't file its chat, is
    /// the reader's chat waiting for the next launch to file it. A retry that
    /// removed every file beside the thread would delete it with the ones
    /// Delete All Chats was owed.
    ///
    /// **A folder that won't list owes them all.** It names no file, and read
    /// as empty, every file beside the thread would stay while Delete All
    /// Chats reported them gone, and nothing would try again. So what is
    /// handed back is `everyFileKeptAside`, which the retry turns into the
    /// names the folder lists by then, less those this store has kept beside
    /// the thread since (`keptAsideSince`).
    package func removeEverySetAside() -> Set<String> {
        guard let names = keptAsideNames() else {
            keptAsideSince = []
            logger.error("the Ask thread's folder could not be listed, so the files kept beside the thread are still owed")
            return [Self.everyFileKeptAside]
        }
        keptAsideSince = nil
        return removeSetAside(named: Set(names))
    }

    /// Forget the files waiting beside the thread with these names, and hand
    /// back the names of those still there. A file already gone counts as
    /// forgotten, and a name that isn't one of this thread's set-aside or
    /// original files is left alone and dropped, but for
    /// `everyFileKeptAside`, which stays owed while the folder won't list.
    package func removeSetAside(named names: Set<String>) -> Set<String> {
        guard let folder = url?.deletingLastPathComponent() else { return [] }
        var names = names
        var left: Set<String> = []
        if names.remove(Self.everyFileKeptAside) != nil {
            if let listed = keptAsideNames() {
                names.formUnion(Set(listed).subtracting(keptAsideSince ?? []))
                keptAsideSince = nil
            } else {
                left.insert(Self.everyFileKeptAside)
            }
        }
        let prefixes = [setAsidePrefix, originalPrefix].compactMap { $0 }
        for name in names where name.hasSuffix(".json") && !name.contains("/")
            && prefixes.contains(where: { name.hasPrefix($0) }) {
            if !remove(folder.appending(path: name)) { left.insert(name) }
        }
        return left
    }

    /// Stands, among the names a deletion owes, for every file that was
    /// beside the thread when a folder that wouldn't list kept Delete All
    /// Chats from naming them (`removeEverySetAside()`). No file is named
    /// it: each ends in `.json`.
    static var everyFileKeptAside: String { "*" }

    /// The names of the files this store has kept beside the thread since a
    /// Delete All Chats that couldn't list the folder, which the retry of that
    /// deletion spares: a chat New Chat set aside since is the reader's. Nil
    /// while no such deletion is owed. In memory only, as the debt is.
    private var keptAsideSince: Set<String>?

    /// `ask-thread-unreadable-`, from the thread's own name.
    private var setAsidePrefix: String? {
        url.map { $0.deletingPathExtension().lastPathComponent + "-unreadable-" }
    }

    /// `ask-thread-original-`, likewise.
    private var originalPrefix: String? {
        url.map { $0.deletingPathExtension().lastPathComponent + "-original-" }
    }

    /// Move the thread aside, and say whether it moved. `unread` is whether
    /// it is moved for being unreadable, which the log then says: a chat
    /// ending is set aside whether it reads or not.
    private func moveAside(_ url: URL, unread: Bool) -> Bool {
        guard let setAsidePrefix else { return false }
        let aside = url.deletingLastPathComponent().appending(path: "\(setAsidePrefix)\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            keptAsideSince?.insert(aside.lastPathComponent)
            if unread {
                logger.notice("the Ask thread could not be read, and was set aside")
            } else {
                logger.notice("the Ask thread was set aside, for a later launch to file")
            }
            return true
        } catch {
            logger.error("the Ask thread could not be set aside: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
    }

    /// Keep the thread's bytes beside it as an original, unless an original
    /// with the same bytes is there already: every launch that reads the
    /// thread in part, before anything is written, would otherwise add one.
    private func keepOriginal(_ data: Data) -> Bool {
        guard let url, let originalPrefix else { return false }
        if originalFiles().contains(where: { (try? AskStoredFile.contents(of: $0)) == data }) { return true }
        let original = url.deletingLastPathComponent().appending(path: "\(originalPrefix)\(UUID().uuidString).json")
        do {
            try write(data, to: original)
            keptAsideSince?.insert(original.lastPathComponent)
            return true
        } catch {
            logger.error("the Ask thread could not be kept whole: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
    }

    /// A thread set aside whose readable turns are filed now, kept for the
    /// rest. Left set aside if it won't move: the next launch files it again,
    /// into the same filing, and tries again.
    private func keepAsOriginal(_ file: URL) {
        guard let originalPrefix else { return }
        let original = file.deletingLastPathComponent().appending(path: "\(originalPrefix)\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: file, to: original)
            keptAsideSince?.insert(original.lastPathComponent)
        } catch {
            logger.error("an Ask thread set aside could not be kept as an original: \(AskStoredFile.tag(for: error), privacy: .public)")
        }
    }

    private func setAsideFiles() -> [URL] {
        files(withPrefix: setAsidePrefix)
    }

    private func originalFiles() -> [URL] {
        files(withPrefix: originalPrefix)
    }

    /// The files with `prefix` beside the thread, or none where the folder
    /// won't list: a read finds nothing to put back, and the next launch
    /// looks again.
    private func files(withPrefix prefix: String?) -> [URL] {
        guard let folder = url?.deletingLastPathComponent(), let prefix,
              let names = AskStoredFile.names(in: folder)
        else { return [] }
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    /// The names of every set-aside and original file, or nil where the
    /// folder won't list.
    private func keptAsideNames() -> [String]? {
        guard let folder = url?.deletingLastPathComponent() else { return [] }
        guard let names = AskStoredFile.names(in: folder) else { return nil }
        let prefixes = [setAsidePrefix, originalPrefix].compactMap { $0 }
        return names.filter { name in name.hasSuffix(".json") && prefixes.contains { name.hasPrefix($0) } }
    }

    @discardableResult
    private func remove(_ file: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: file)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return true
        } catch {
            logger.error("an Ask thread kept aside could not be deleted: \(AskStoredFile.tag(for: error), privacy: .public)")
            return false
        }
    }
}
