import Foundation
import os

/// How AskKit keeps a file of its own: the thread, a filing of an earlier chat
/// or its list, a feedback attachment. One place, so the three stores
/// (`AskThreadStore`, `AskThreadArchive`, `AskFeedbackAttachments`) write,
/// read, list and log alike.
///
/// Behind no platform gate, like the stores: Foundation alone.
nonisolated enum AskStoredFile {
    /// The most bytes a file is read or written at: 64 MiB.
    ///
    /// Far past what the caps let a thread reach: fifty turns
    /// (`AskThreadStore.maxPersistedTurns`), each with 200 rows
    /// (`AskCollector.maxThreadRows`) of 2 KB, a 16 KB payload and a 4 KB
    /// proposal's, come to about 21 MB. And far short of what would take the
    /// app down: a file is decoded whole in memory, the thread at every
    /// launch, so one grown past any bound would end the app as it opened,
    /// every time. A file past it reads as one this build can't read, never
    /// as no file, and nothing is written past it, so what is written reads
    /// back.
    static var maxBytes: Int { 64 << 20 }

    /// Whether this process runs on a Mac: natively, as a Mac Catalyst app,
    /// or as an iPhone or iPad app on a Mac. The last two are compiled for
    /// iOS, so only the running process can tell.
    static var runsOnAMac: Bool {
        #if os(macOS)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp
        #endif
    }

    /// The options every write takes here: `writingOptions(onAMac:)` for the
    /// device this process runs on.
    static var writingOptions: Data.WritingOptions {
        writingOptions(onAMac: runsOnAMac)
    }

    /// Atomic, and with complete file protection except on a Mac.
    ///
    /// **Complete protection** keeps a whole chat transcript unreadable on a
    /// device that is locked after being unlocked once. The default class,
    /// `CompleteUntilFirstUserAuthentication`, keeps it readable from the
    /// first unlock until reboot.
    ///
    /// **Never on a Mac**, where a file keeps the system's default class.
    /// macOS 27.2 fails every write under complete protection while the Mac
    /// is locked, sandboxed or not. Measured with it on a locked Mac, the
    /// signed, sandboxed demo's thread write failed (`NSCocoaErrorDomain` 513,
    /// POSIX 1) and the chat was gone at relaunch, and outside the sandbox
    /// `swift test` failed three of `AskStoredFileTests`' seven at their
    /// writes, which pass with the Mac unlocked. Without it, the same locked
    /// demo wrote its thread and read it back at relaunch, the file's class
    /// `NSFileProtectionCompleteUntilFirstUserAuthentication`. And a Mac has
    /// no moment to write again: the store tries a refused write again as
    /// protected data comes back on iOS and visionOS alone
    /// (`AskConversationStore`), so on a Mac every turn written while it was
    /// locked would be lost. An iPhone or iPad app on a Mac or a Catalyst
    /// build runs on the same Mac, so it takes the same posture, never a
    /// weaker one.
    static func writingOptions(onAMac: Bool) -> Data.WritingOptions {
        onAMac ? [.atomic] : [.atomic, .completeFileProtection]
    }

    /// Write `data` to `file`, atomically, under `writingOptions`, and
    /// excluded from backup, making its folder first.
    ///
    /// **Excluded or failed.** A file left in a backup isn't what the stores
    /// promise, so a refused exclusion fails the write rather than only being
    /// logged: the caller keeps its copies and writes again, and the write
    /// that takes marks the file. The file is on disk either way, since the
    /// atomic write has already put it there.
    ///
    /// The folder is made on every write, not once: made once and
    /// remembered, a folder removed while the app runs would fail every write
    /// for the rest of the process. `ownFolder` is one AskKit keeps to
    /// itself (`threads/`, `feedback/`), which, where this call makes it, is
    /// made under the files' protection and excluded from backup, so a file
    /// in it is covered from the moment it is there and not only once it is
    /// marked (`makeOwnFolder(_:logger:)`).
    ///
    /// Refused past `maxBytes`, with the code a read gives such a file:
    /// written, it would never read back.
    static func write(_ data: Data, to file: URL, ownFolder: Bool, logger: Logger) throws {
        guard data.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let folder = file.deletingLastPathComponent()
        if ownFolder {
            try makeOwnFolder(folder, logger: logger)
        } else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try data.write(to: file, options: writingOptions)
        try excludeFromBackup(file)
    }

    /// Make a folder AskKit keeps to itself, if it isn't there, under its
    /// files' protection and excluded from backup.
    ///
    /// **Only one this call makes.** A folder that is there already may be a
    /// host's (`AskThreadArchive`'s `directory:`), and keeps what the host
    /// gave it. Its parent, the app's folder, is made bare: the host keeps
    /// its own files there, and a protection class set on it would become
    /// theirs, so a host's write on a locked device would fail. A refused
    /// exclusion is logged and costs no write: every file in the folder is
    /// excluded on its own (`write(_:to:ownFolder:logger:)`).
    private static func makeOwnFolder(_ folder: URL, logger: Logger) throws {
        guard !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let attributes: [FileAttributeKey: Any] = runsOnAMac ? [:] : [.protectionKey: FileProtectionType.complete]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: attributes)
        do {
            try excludeFromBackup(folder)
        } catch {
            logger.error("a folder of AskKit's own could not be excluded from backup: \(tag(for: error), privacy: .public)")
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = url
        try marked.setResourceValues(values)
    }

    /// A file's bytes, read whole, or `CocoaError(.fileReadTooLarge)` for a
    /// file past `maxBytes`, refused before a byte of it is read. A missing
    /// file throws `fileReadNoSuchFile` (260), as `Data(contentsOf:)` does.
    static func contents(of file: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        if let size = (attributes[.size] as? NSNumber)?.intValue, size > maxBytes {
            throw CocoaError(.fileReadTooLarge)
        }
        return try Data(contentsOf: file)
    }

    /// The names in `folder`: none for a folder that isn't there, and nil for
    /// one that won't list.
    ///
    /// **Nil is not empty.** A folder that can't be listed names no file, and
    /// read as empty, a removal of every file in it would report them gone
    /// while each stayed.
    static func names(in folder: URL) -> [String]? {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            return nil
        }
    }

    /// A file error for the log: its domain and code, and the underlying
    /// error's, which for a file is the POSIX one (`NSCocoaErrorDomain#513
    /// (NSPOSIXErrorDomain#1)`), as `AskTriage.tag(for:)` tags a bridged
    /// error. Never its description, which is the OS's localized prose, in
    /// the reader's language, and can carry the file's path.
    static func tag(for error: any Error) -> String {
        let error = error as NSError
        let tag = "\(error.domain)#\(error.code)"
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return tag }
        return "\(tag) (\(underlying.domain)#\(underlying.code))"
    }
}
