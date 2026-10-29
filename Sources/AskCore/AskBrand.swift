import Foundation
import os
import Synchronization

/// The host's own copy and identity, which AskUI needs and the domain
/// supplies.
///
/// Every string here stays in the **host's** catalog, not AskKit's: it names
/// the app ("Ask My Library"), and a package catalog can't hold twenty-five
/// locales of every host's brand. AskKit owns only the neutral copy.
nonisolated public struct AskBrand: Sendable {
    /// The screen's title, such as "Ask My Library", which the host gives its
    /// navigation container: `AskScreen` sets no title of its own.
    public let title: String
    /// The folder under `Application Support` the thread, the earlier chats
    /// and the feedback attachments are kept in: a name no other app keeps
    /// files under there.
    ///
    /// **The app's name only inside a sandbox.** A sandboxed app's
    /// Application Support is in its own container, so its name serves. An
    /// unsandboxed Mac app's is the user's `~/Library/Application Support`,
    /// which every app the user runs shares: a folder named for the app can
    /// be another app's of the same name, whose files Delete All Chats would
    /// reach. There, take a name no other app would, such as the bundle
    /// identifier.
    ///
    /// **One folder.** A name that is empty, `.` or `..`, or holds a `/`,
    /// would reach Application Support itself or a folder outside it, where
    /// Delete All Chats would delete whatever `threads/` it found. Such a
    /// name is logged as a fault, and the thread, archive and attachments
    /// built from it read and write nothing.
    public let appDirectory: String
    /// The `os.Logger` subsystem AskKit's lines go to: the engine's, the
    /// store's, and those of the thread, archive and feedback files the store
    /// keeps. The seam the host builds takes it too, as `AppleModelSeam`'s
    /// `logSubsystem`.
    ///
    /// **No generation gate is built for it.** The process has one generation
    /// gate, `AskGenerationGate.shared`, and an `AppleModelSeam`'s generation
    /// it presumes wedged is logged under the seam's `logSubsystem`, so a seam
    /// built with this subsystem logs that line here already. A gate built to
    /// log under it would be a second gate, and on-device generations queued
    /// at the two could run at once, the overlap the gate exists to prevent.
    public let logSubsystem: String
    /// The placeholder shown while the draft is empty: in the screen's
    /// composer, and on the face in a host's slot.
    public let help: String
    /// The ready first screen's headline.
    public let firstScreenHeadline: String
    /// The ready first screen's sentence under the headline, saying what Ask
    /// is. It goes while the screen is making room.
    public let firstScreenSentence: String
    /// What the nothing-to-ask first screen says when the reader has nothing
    /// to ask about yet, or nil for a host that never shows that screen, one
    /// whose `AskFirstScreenPolicy.needsOwnedRows` is false.
    ///
    /// **No copy, no nothing-to-ask screen.** A host that needs owned rows
    /// and gives none gets the ready first screen for an empty overview, as
    /// one that doesn't need them does, and `AskEngine` logs the mismatch
    /// when it is built.
    public let nothingToAskCopy: String?
    /// The label of the nothing-to-ask screen's button, or nil for no button.
    /// The button shows only when the host also passes `AskScreen` an action
    /// for it.
    public let nothingToAskActionLabel: String?
    /// One sentence naming what leaves the device, shown last on the ready
    /// and can't-serve first screens.
    public let disclosureSentence: String
    /// One line saying what Ask reads and that it can be wrong, such as "Ask
    /// reads only what you own. It can't search the web, and it can be wrong."
    /// The ready first screen shows it under its sentence, and lets it go
    /// while making room.
    public let scopeCaveat: String

    /// A brand with each field as given: the host's copy, resolved against
    /// its own bundle.
    public init(
        title: String,
        appDirectory: String,
        logSubsystem: String,
        help: String,
        firstScreenHeadline: String,
        firstScreenSentence: String,
        nothingToAskCopy: String? = nil,
        nothingToAskActionLabel: String? = nil,
        disclosureSentence: String,
        scopeCaveat: String
    ) {
        self.title = title
        self.appDirectory = appDirectory
        self.logSubsystem = logSubsystem
        self.help = help
        self.firstScreenHeadline = firstScreenHeadline
        self.firstScreenSentence = firstScreenSentence
        self.nothingToAskCopy = nothingToAskCopy
        self.nothingToAskActionLabel = nothingToAskActionLabel
        self.disclosureSentence = disclosureSentence
        self.scopeCaveat = scopeCaveat
        if !Self.isOneFolder(appDirectory), Self.reportedFolders.withLock({ $0.insert(appDirectory).inserted }) {
            Logger(subsystem: logSubsystem, category: "brand").fault("""
                AskBrand.appDirectory \(appDirectory.debugDescription, privacy: .public) is not one folder under \
                Application Support, so no thread, earlier chat or feedback attachment is read or written
                """)
        }
    }

    /// The folder names a brand has reported as not one folder, so a domain
    /// that builds its brand on every read logs the mistake once.
    private static let reportedFolders = Mutex<Set<String>>([])
}

nonisolated extension AskBrand {
    /// The subsystem a piece built without one logs under: the app's bundle
    /// identifier, or "AskKit" in a process that has none.
    package static func subsystem(_ given: String?) -> String {
        given ?? Bundle.main.bundleIdentifier ?? "AskKit"
    }

    /// Whether `appDirectory` names one folder: not empty, not `.` or `..`,
    /// and with no `/` or NUL in it.
    ///
    /// **The guard on every path AskKit keeps files at.** Checked where the
    /// thread, the archive and the attachments find their folder
    /// (`appFolder(_:)`), and not only as a brand is made: each of them takes
    /// the name as a string of its own, so a check in `init` alone would
    /// leave them open to one passed straight in.
    static func isOneFolder(_ appDirectory: String) -> Bool {
        !appDirectory.isEmpty && appDirectory != "." && appDirectory != ".."
            && !appDirectory.contains("/") && !appDirectory.contains("\u{0}")
    }

    /// `Application Support/<appDirectory>/`, the path only, or nil when
    /// there is no Application Support or the name isn't one folder. A store
    /// with no folder refuses every read and write: a misnamed folder costs
    /// the app its own chats, never another app's files.
    static func appFolder(_ appDirectory: String) -> URL? {
        guard isOneFolder(appDirectory), let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return support.appending(path: appDirectory, directoryHint: .isDirectory)
    }
}

/// What the reader has to ask about, as the domain counts it: the scopes and
/// their sizes. The starters (`AskDomain.starters(overview:window:)`) and the
/// domain's prompt lines are written from it, so a first screen names
/// something the reader really has, and an empty one shows the nothing-to-ask
/// first screen where the policy needs owned rows
/// (`AskFirstScreenPolicy.needsOwnedRows`) and the brand has words for it.
nonisolated public struct AskOverview: Sendable, Equatable {
    /// One scope the reader has things in: its display name and how many.
    nonisolated public struct Scope: Sendable, Equatable, Identifiable {
        /// The domain's own id for the scope.
        public let id: String
        /// The scope's name as the reader sees it, such as "records".
        public let name: String
        /// How many things the reader has in it.
        public let count: Int

        /// A scope with each field as given.
        public init(id: String, name: String, count: Int) {
            self.id = id
            self.name = name
            self.count = count
        }
    }

    /// The scopes, in the domain's order.
    public let scopes: [Scope]
    /// Everything the reader has, across scopes. Not derived from `scopes`:
    /// a host may count something the scope list doesn't break down.
    public let total: Int

    /// An overview with each field as given.
    public init(scopes: [Scope], total: Int) {
        self.scopes = scopes
        self.total = total
    }

    /// Nothing to ask about: no scopes, and a total of zero.
    public static let empty = AskOverview(scopes: [], total: 0)

    /// Whether there is nothing to ask about: a total of zero. With
    /// `AskFirstScreenPolicy.needsOwnedRows` and the brand's
    /// `nothingToAskCopy`, it shows the nothing-to-ask first screen.
    public var isEmpty: Bool { total == 0 }

    /// The scopes, largest first: the order a domain usually names them in.
    public var byCount: [Scope] { scopes.sorted { $0.count > $1.count } }
}

/// A tappable question the screen opens with, or offers after an answer.
nonisolated public struct AskStarter: Sendable, Equatable, Identifiable {
    /// What tells this starter from the others in a bank, and what the
    /// reader declines when they turn it down.
    public let id: String
    /// The question as the reader sees it on the chip, and in the thread once
    /// tapped.
    public let text: String

    /// A starter for `text`. A nil `id` takes the text as the id.
    public init(id: String? = nil, text: String) {
        self.id = id ?? text
        self.text = text
    }
}

/// Whether a thread survives the process.
nonisolated public enum AskPersistence: String, Sendable, Equatable {
    /// Written to `Application Support/<appDirectory>/ask-thread.json` after
    /// every turn and restored on launch: a chat is expected to still be
    /// there. New Chat files it with the earlier chats (`AskThreadArchive`).
    case thread
    /// Kept for the process only.
    case perLaunch
}
