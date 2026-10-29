import Foundation
import os

/// Where a reader's feedback attachments wait for someone to send them.
///
/// `LanguageModelSession.logFeedbackAttachment` hands back the transcript Apple
/// asks for with a model-quality report, and sends it nowhere by itself. A
/// transcript is the reader's own questions about their own data, so it leaves
/// the device only by an explicit share, from the diagnostics row of
/// `AskPrivateCloudCard`. Until then it stays on the device as the thread
/// does (`AskStoredFile`): excluded from backup, and under complete file
/// protection except on a Mac, in `feedback/`, which is made the same way.
/// Only the newest `maxKept` are kept, and they go when the chat they came
/// from leaves the screen: New Chat, Delete All Chats, or an earlier chat
/// opened in its place.
///
/// **A host only makes one, to hand to `AskConversationStore`,** as it does
/// the thread's (`AskThreadStore`). The initializer, to keep them somewhere of
/// its own (`directory:`), and `maxKept` are all that is public; keeping,
/// listing and removing them are AskKit's own (`package`). The conversation
/// store keeps one per verdict and removes them with their chat, and the
/// diagnostics row lists and shares them.
///
/// Behind no platform gate, like `AskThreadStore`: Foundation alone.
public actor AskFeedbackAttachments {
    private let logger: Logger

    /// How many are kept. The newest win: an attachment is worth sending while
    /// the build it describes is the one under test.
    public static var maxKept: Int { 10 }

    private let directory: URL?
    /// The names of the attachments kept since a removal of every one of
    /// them that couldn't list the folder, which the retry of that removal
    /// spares: they are the next chat's. Nil while no such removal is owed.
    private var keptSince: Set<String>?

    /// The attachments kept under the host's folder, or in `directory` when
    /// one is given.
    ///
    /// - Parameters:
    ///   - appDirectory: the folder under `Application Support`
    ///     (`AskBrand.appDirectory`). The attachments go in `feedback/` inside it.
    ///   - directory: an explicit folder, for tests. Overrides `appDirectory`.
    ///   - logSubsystem: the subsystem the attachments log under
    ///     (`AskBrand.logSubsystem`). Nil logs under the app's bundle identifier.
    public init(appDirectory: String, directory: URL? = nil, logSubsystem: String? = nil) {
        logger = Logger(subsystem: AskBrand.subsystem(logSubsystem), category: "feedback")
        self.directory = directory ?? Self.defaultDirectory(appDirectory: appDirectory)
        if directory == nil, !AskBrand.isOneFolder(appDirectory) {
            logger.fault("""
                \(appDirectory.debugDescription, privacy: .public) is not one folder under Application Support, \
                so no feedback attachment is kept
                """)
        }
    }

    /// `Application Support/<appDirectory>/feedback/`, or nil for a name that
    /// isn't one folder (`AskBrand.appDirectory`).
    static func defaultDirectory(appDirectory: String) -> URL? {
        AskBrand.appFolder(appDirectory)?.appending(path: "feedback", directoryHint: .isDirectory)
    }

    /// Keep one attachment, dropping the oldest past `maxKept`. Its name
    /// carries `date` and `sentiment`, and `urls()` reads the age back from
    /// it. Returns where it went, or nil when it couldn't be written.
    @discardableResult
    package func save(_ data: Data, sentiment: AskFeedback.Sentiment, at date: Date = .now) -> URL? {
        guard let directory else { return nil }
        let url = directory.appending(path: Self.unusedName(in: directory, at: date, sentiment: sentiment))
        // Before the write: a refused backup exclusion fails it with the
        // file on disk, which is this chat's as much as one that took.
        keptSince?.insert(url.lastPathComponent)
        do {
            try AskStoredFile.write(data, to: url, ownFolder: true, logger: logger)
        } catch {
            logger.error("a feedback attachment could not be written: \(AskStoredFile.tag(for: error), privacy: .public)")
            return nil
        }
        prune()
        return url
    }

    /// The next name in `directory`: `feedback-<seconds>-<sentiment>.json`,
    /// seconds since 1970, and for a later verdict in the same second
    /// `feedback-<seconds>.2-<sentiment>.json`, `.3` and on.
    ///
    /// One count per second whatever the verdict, so a thumbs-down after a
    /// thumbs-up in the same second is the later of the two, and a name
    /// already taken is never reused: it would cost the attachment written
    /// there, since the atomic write replaces it.
    private static func unusedName(in directory: URL, at date: Date, sentiment: AskFeedback.Sentiment) -> String {
        let seconds = Int(date.timeIntervalSince1970)
        let names = AskStoredFile.names(in: directory) ?? []
        var sequence = names.compactMap(stamp(of:)).filter { $0.seconds == seconds }.map(\.sequence).max().map { $0 + 1 } ?? 1
        func name() -> String {
            sequence == 1
                ? "feedback-\(seconds)-\(sentiment.rawValue).json"
                : "feedback-\(seconds).\(sequence)-\(sentiment.rawValue).json"
        }
        while FileManager.default.fileExists(atPath: directory.appending(path: name()).path(percentEncoded: false)) {
            sequence += 1
        }
        return name()
    }

    /// When an attachment was kept, from its name: the second, and its place
    /// among those kept in that second, 1 for the first, which has no number.
    /// Nil for a name of another shape.
    ///
    /// Read as numbers rather than compared as text: as text `.10-` sorts
    /// before `.9-`, and in one second a "negative" before a "positive"
    /// whichever came first.
    private static func stamp(of name: String) -> (seconds: Int, sequence: Int)? {
        guard name.hasPrefix("feedback-"), name.hasSuffix(".json") else { return nil }
        let stamp = name.dropFirst("feedback-".count).prefix { $0 != "-" }
        let parts = stamp.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let seconds = Int(first) else { return nil }
        guard parts.count == 2 else { return (seconds, 1) }
        guard let sequence = Int(parts[1]) else { return nil }
        return (seconds, sequence)
    }

    /// Whether the attachment named `name` was kept after the one named
    /// `other`. A name with no stamp counts as the oldest, so the prune takes
    /// it first, and two with one stamp, which this build never writes, go by
    /// name.
    private static func isNewer(_ name: String, than other: String) -> Bool {
        switch (stamp(of: name), stamp(of: other)) {
        case let (stamp?, otherStamp?):
            if stamp.seconds != otherStamp.seconds { return stamp.seconds > otherStamp.seconds }
            if stamp.sequence != otherStamp.sequence { return stamp.sequence > otherStamp.sequence }
            return name > other
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return name > other
        }
    }

    /// Every attachment kept, newest first. None where the folder won't
    /// list.
    package func urls() -> [URL] {
        guard let directory, let names = attachmentNames() else { return [] }
        return names.sorted(by: Self.isNewer).map { directory.appending(path: $0) }
    }

    /// The names of every attachment kept, or nil where the folder won't
    /// list (`AskStoredFile.names(in:)`).
    private func attachmentNames() -> [String]? {
        guard let directory else { return [] }
        return AskStoredFile.names(in: directory)?.filter { $0.hasPrefix("feedback-") && $0.hasSuffix(".json") }
    }

    /// Remove every attachment kept, and say whether all are gone: a
    /// transcript of a chat no longer on screen shouldn't outlive it. On false
    /// a transcript is still on the device, and a caller tries again.
    @discardableResult
    func removeAll() -> Bool {
        removeEvery().isEmpty
    }

    /// Remove every attachment kept, and those named in `owed`, as the store
    /// does when a chat leaves the screen, and hand back the names of those
    /// that wouldn't go, for `remove(named:)` to try again. `owed` is what an
    /// earlier chat's removal left.
    ///
    /// **Names, so a retry removes these and nothing else.** An attachment
    /// kept after, by a verdict in the chat that came next, is that chat's,
    /// and goes with it.
    ///
    /// **A folder that won't list owes them all.** It names no attachment,
    /// and read as empty, every transcript would stay while the removal said
    /// they had gone. So what is handed back holds `everyAttachment`, which
    /// the retry turns into the names the folder lists by then, less those
    /// kept since.
    package func removeEvery(also owed: Set<String> = []) -> Set<String> {
        guard let names = attachmentNames() else {
            keptSince = []
            logger.error("the feedback folder could not be listed, so every attachment in it is still owed")
            return remove(named: owed.subtracting([Self.everyAttachment])).union([Self.everyAttachment])
        }
        // Every one is listed, so an earlier removal's `everyAttachment` is
        // settled here.
        keptSince = nil
        return remove(named: Set(names).union(owed.subtracting([Self.everyAttachment])))
    }

    /// Remove the attachments with these names, and hand back the names of
    /// those still there. One already gone counts as removed, and a name that
    /// isn't an attachment's is left alone and dropped, but for
    /// `everyAttachment`, which stays owed while the folder won't list.
    package func remove(named names: Set<String>) -> Set<String> {
        guard let directory else { return [] }
        var names = names
        var left: Set<String> = []
        if names.remove(Self.everyAttachment) != nil {
            if let listed = attachmentNames() {
                names.formUnion(Set(listed).subtracting(keptSince ?? []))
                keptSince = nil
            } else {
                left.insert(Self.everyAttachment)
            }
        }
        for name in names where name.hasPrefix("feedback-") && name.hasSuffix(".json") && !name.contains("/") {
            do {
                try FileManager.default.removeItem(at: directory.appending(path: name))
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Gone already.
            } catch {
                logger.error("a feedback attachment could not be removed: \(AskStoredFile.tag(for: error), privacy: .public)")
                left.insert(name)
            }
        }
        return left
    }

    /// Stands, among the names a removal owes, for every attachment that was
    /// in the folder when a folder that wouldn't list kept the removal from
    /// naming them (`removeEvery(also:)`). No attachment is named it: each
    /// starts with `feedback-`.
    static var everyAttachment: String { "*" }

    private func prune() {
        for stale in urls().dropFirst(Self.maxKept) {
            do {
                try FileManager.default.removeItem(at: stale)
            } catch {
                logger.error("an old feedback attachment could not be removed: \(AskStoredFile.tag(for: error), privacy: .public)")
            }
        }
    }
}
