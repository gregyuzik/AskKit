import Foundation
import os
import Testing

@testable import AskCore

/// How the three stores keep their files (`AskStoredFile`), and the feedback
/// attachments' share of it.
@Suite(.timeLimit(.minutes(1))) struct AskStoredFileTests {

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "askkit-stored-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func setPermissions(_ mode: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Read from a URL of its own, so no value cached in another is read.
    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        let fresh = URL(filePath: url.path(percentEncoded: false))
        let excluded = try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        try #require(excluded != nil)
        return excluded == true
    }

    // MARK: - Protection

    /// An iPhone or iPad app on a Mac, and a Catalyst build, are compiled
    /// for iOS: chosen at compile time, they would write with the option the
    /// native macOS leg has always gone without.
    @Test func everyMacWritesWithoutCompleteProtectionAndEveryOtherDeviceWithIt() {
        #expect(AskStoredFile.writingOptions(onAMac: true) == [.atomic])
        #expect(AskStoredFile.writingOptions(onAMac: false) == [.atomic, .completeFileProtection])
        #expect(AskStoredFile.writingOptions == AskStoredFile.writingOptions(onAMac: AskStoredFile.runsOnAMac))
        #if os(macOS)
        #expect(AskStoredFile.runsOnAMac)
        #endif
    }

    // MARK: - The ceiling

    @Test func aWritePastTheCeilingIsRefusedAndWritesNothing() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "big.json")
        let logger = Logger(subsystem: "AskKitTests", category: "stored-file")

        #expect(throws: CocoaError.self) {
            try AskStoredFile.write(Data(count: AskStoredFile.maxBytes + 1), to: file, ownFolder: false, logger: logger)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        try AskStoredFile.write(Data("[]".utf8), to: file, ownFolder: false, logger: logger)
        #expect(try AskStoredFile.contents(of: file) == Data("[]".utf8))
    }

    @Test func aMissingFileReadsAsMissingAsDataWouldSay() throws {
        // The stores tell no file (a fresh install) from one that won't read
        // by this code alone.
        let missing = scratchDirectory().appending(path: "ask-thread.json")
        do {
            _ = try AskStoredFile.contents(of: missing)
            Issue.record("a missing file read")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoSuchFile)
        }
    }

    // MARK: - Listing

    @Test func aFolderThatIsntThereListsNothingAndOneThatWontListIsNil() throws {
        let directory = scratchDirectory()
        defer {
            try? setPermissions(0o755, of: directory)
            try? FileManager.default.removeItem(at: directory)
        }
        #expect(AskStoredFile.names(in: directory) == [])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appending(path: "a.json"))
        #expect(AskStoredFile.names(in: directory) == ["a.json"])
        try setPermissions(0o300, of: directory)
        #expect(AskStoredFile.names(in: directory) == nil)
    }

    // MARK: - The log

    /// The OS's description is localized prose, in the reader's language,
    /// and can carry the path. The tag is the domain and code, the
    /// underlying POSIX one's with it.
    @Test func aFileErrorIsLoggedAsItsDomainAndCode() throws {
        let directory = scratchDirectory()
        let file = directory.appending(path: "locked.json")
        defer {
            try? setPermissions(0o644, of: file)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: file)
        try setPermissions(0o000, of: file)

        do {
            _ = try AskStoredFile.contents(of: file)
            Issue.record("an unreadable file read")
        } catch {
            #expect(AskStoredFile.tag(for: error) == "NSCocoaErrorDomain#257 (NSPOSIXErrorDomain#13)")
        }
        #expect(AskStoredFile.tag(for: CocoaError(.fileReadTooLarge)) == "NSCocoaErrorDomain#263")
    }

    // MARK: - Feedback attachments

    @Test func removingEveryAttachmentFromAFolderThatWontListOwesThemAll() async throws {
        // A folder that won't list names no attachment. Read as empty, a
        // chat leaving the screen would report its transcripts gone while
        // they stayed. Owed whole, the retry lists them once it can, and
        // spares one a verdict in the next chat kept since.
        let directory = scratchDirectory()
        defer {
            try? setPermissions(0o755, of: directory)
            try? FileManager.default.removeItem(at: directory)
        }
        let attachments = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let owed = try #require(await attachments.save(Data("{}".utf8), sentiment: .negative, at: Date(timeIntervalSince1970: 1_000)))
        try setPermissions(0o300, of: directory)

        let left = await attachments.removeEvery()
        #expect(!left.isEmpty)
        #expect(await !attachments.removeAll())
        // Still owed while it won't list.
        #expect(await attachments.remove(named: left) == left)

        try setPermissions(0o755, of: directory)
        let since = try #require(await attachments.save(Data("{}".utf8), sentiment: .positive, at: Date(timeIntervalSince1970: 2_000)))
        #expect(await attachments.remove(named: left).isEmpty)
        #expect(await attachments.urls() == [since])
        #expect(!FileManager.default.fileExists(atPath: owed.path(percentEncoded: false)))
    }

    @Test func theFolderTheAttachmentsMakeIsExcludedFromBackupAndTheAppsIsNot() async throws {
        let app = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: app) }
        let directory = app.appending(path: "feedback", directoryHint: .isDirectory)
        let attachments = AskFeedbackAttachments(appDirectory: "unused", directory: directory)
        let saved = try #require(await attachments.save(Data("{}".utf8), sentiment: .positive))

        #expect(try isExcludedFromBackup(directory))
        #expect(try !isExcludedFromBackup(app))
        #expect(try isExcludedFromBackup(saved))
    }
}
