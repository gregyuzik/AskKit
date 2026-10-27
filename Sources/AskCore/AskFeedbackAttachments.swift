import Foundation
import os

/// Where a reader's feedback attachments wait for someone to send them.
///
/// `LanguageModelSession.logFeedbackAttachment` hands back the transcript Apple
/// asks for with a model-quality report, and sends it nowhere by itself. A
/// transcript is the reader's own questions about their own data, so it leaves
/// the device only by an explicit share, from the diagnostics row of
/// `AskPrivateCloudCard`. Until then it stays on the device as the thread
/// does: excluded from backup, and under complete file protection except on
/// macOS. Only the newest `maxKept` are kept, and they go when the chat they
/// came from leaves the screen: New Chat, Delete All Chats, or an earlier chat
/// opened in its place.
///
/// Behind no platform gate, like `AskThreadStore`: Foundation alone.
public actor AskFeedbackAttachments {
    private let logger: Logger

    /// How many are kept. The newest win: an attachment is worth sending while
    /// the build it describes is the one under test.
    public static var maxKept: Int { 10 }

    private let directory: URL?

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
    public func save(_ data: Data, sentiment: AskFeedback.Sentiment, at date: Date = .now) -> URL? {
        guard let directory else { return nil }
        let url = directory.appending(path: Self.unusedName(in: directory, at: date, sentiment: sentiment))
        // The thread store's reasoning, and its measurement: data protection
        // is an iOS-family feature, and on macOS the option fails the write.
        #if os(macOS)
        let options: Data.WritingOptions = [.atomic]
        #else
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #endif
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: options)
        } catch {
            logger.error("a feedback attachment could not be written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // Its own step, as in the thread store. The file is on disk whatever
        // happens here, so a failure is logged and the prune still runs: inside
        // the write's `do`, it would return nil before the prune.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = url
        do {
            try marked.setResourceValues(values)
        } catch {
            logger.error("a feedback attachment could not be excluded from backup: \(error.localizedDescription, privacy: .public)")
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
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
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

    /// Every attachment kept, newest first.
    public func urls() -> [URL] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        else { return [] }
        return names
            .filter { $0.hasPrefix("feedback-") && $0.hasSuffix(".json") }
            .sorted(by: Self.isNewer)
            .map { directory.appending(path: $0) }
    }

    /// Remove every attachment kept, and say whether all are gone: a
    /// transcript of a chat no longer on screen shouldn't outlive it. On false
    /// a transcript is still on the device, and a caller tries again.
    @discardableResult
    public func removeAll() -> Bool {
        removeEvery().isEmpty
    }

    /// Remove every attachment kept, and those named in `owed`, as the store
    /// does when a chat leaves the screen, and hand back the names of those
    /// that wouldn't go, for `remove(named:)` to try again. `owed` is what an
    /// earlier chat's removal left: a folder that can't be listed lists
    /// nothing, and its names would be forgotten.
    ///
    /// **Names, so a retry removes these and nothing else.** An attachment
    /// kept after, by a verdict in the chat that came next, is that chat's,
    /// and goes with it.
    package func removeEvery(also owed: Set<String> = []) -> Set<String> {
        remove(named: Set(urls().map(\.lastPathComponent)).union(owed))
    }

    /// Remove the attachments with these names, and hand back the names of
    /// those still there. One already gone counts as removed, and a name that
    /// isn't an attachment's is left alone and dropped.
    package func remove(named names: Set<String>) -> Set<String> {
        guard let directory else { return [] }
        var left: Set<String> = []
        for name in names where name.hasPrefix("feedback-") && name.hasSuffix(".json") && !name.contains("/") {
            do {
                try FileManager.default.removeItem(at: directory.appending(path: name))
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Gone already.
            } catch {
                logger.error("a feedback attachment could not be removed: \(error.localizedDescription, privacy: .public)")
                left.insert(name)
            }
        }
        return left
    }

    private func prune() {
        for stale in urls().dropFirst(Self.maxKept) {
            do {
                try FileManager.default.removeItem(at: stale)
            } catch {
                logger.error("an old feedback attachment could not be removed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
