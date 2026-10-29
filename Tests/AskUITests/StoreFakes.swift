#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import AskUI

// MARK: - Rows

nonisolated struct UIRow: AskRow {
    let id: String
    let displayTitle: String

    init(_ title: String) {
        id = title
        displayTitle = title
    }
}

extension UIRow {
    static let three = [UIRow("Kind of Blue"), UIRow("Rumours"), UIRow("Abbey Road")]
}

// MARK: - The asker

/// An engine stand-in that emits whatever the test scripted.
///
/// The store's whole job is turning a stream of `AskTurnEvent`s into a thread,
/// so a scripted stream is not a stand-in for the engine here — it is the exact
/// input the store is specified against.
nonisolated final class ScriptedAsker: AskAnswering, @unchecked Sendable {
    typealias Row = UIRow

    /// One turn's worth: the events, then optionally a throw.
    struct Script: Sendable {
        var events: [AskTurnEvent<UIRow>] = []
        var error: (any Error)?
        /// Wait, without finishing, after the events run out — a turn in flight
        /// for the test to stop.
        var hangs = false
    }

    private let queued = Mutex<[Script]>([])
    private let fallback = Mutex(Script())
    let questions = Mutex<[(String, AskTurnMode)]>([])
    let stops = Mutex(0)
    let resets = Mutex(0)
    let prewarms = Mutex(0)
    /// `stop`, `reset`, `resume` and `prewarm`, in the order they reached the
    /// engine — a warm built before the reset that takes it is no warm.
    let lifecycle = Mutex<[String]>([])
    let refreshes = Mutex(0)
    let resumedTails = Mutex<[[AskThreadTail]]>([])
    let feedbacks = Mutex<[(feedback: AskFeedback, isLatestTurn: Bool)]>([])

    init(_ script: Script = Script()) {
        fallback.withLock { $0 = script }
    }

    func script(_ script: Script) { fallback.withLock { $0 = script } }
    func scripts(_ list: [Script]) { queued.withLock { $0 = list } }

    /// The labels of the photos each question was sent with, in order.
    let imageLabels = Mutex<[[String]]>([])
    /// The scope each question was asked in, in order — nil for none.
    let scopes = Mutex<[String?]>([])

    func ask(_ question: String, mode: AskTurnMode) -> AsyncThrowingStream<AskTurnEvent<UIRow>, any Error> {
        ask(question, mode: mode, images: [], scope: nil)
    }

    func ask(
        _ question: String,
        mode: AskTurnMode,
        images: [AskImageAttachment]
    ) -> AsyncThrowingStream<AskTurnEvent<UIRow>, any Error> {
        ask(question, mode: mode, images: images, scope: nil)
    }

    func ask(
        _ question: String,
        mode: AskTurnMode,
        images: [AskImageAttachment],
        scope: String?
    ) -> AsyncThrowingStream<AskTurnEvent<UIRow>, any Error> {
        scopes.withLock { $0.append(scope) }
        imageLabels.withLock { $0.append(images.map(\.label)) }
        questions.withLock { $0.append((question, mode)) }
        let script = queued.withLock { $0.isEmpty ? nil : $0.removeFirst() } ?? fallback.withLock { $0 }
        // Paced where stops and resets cancel, so a turn is still streaming
        // when one sent before it reaches the engine lands, as a model's turn
        // would be: unpaced, it ends inside the hop, with nothing to cancel.
        let paced = cancelsTheTurnInFlight.withLock { $0 }
        return AsyncThrowingStream { continuation in
            let turn = UUID()
            let task = Task {
                defer { _ = self.inFlight.withLock { $0.removeValue(forKey: turn) } }
                for event in script.events {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                    if paced {
                        try? await Task.sleep(for: .milliseconds(1))
                    } else {
                        await Task.yield()
                    }
                }
                if script.hangs {
                    try? await Task.sleep(for: .seconds(600))
                    continuation.finish()
                    return
                }
                if Task.isCancelled { return }
                if let error = script.error {
                    continuation.finish(throwing: error)
                } else {
                    // A turn that answered leaves a conversation to follow up
                    // against, and a real engine says so before its stream
                    // ends. `followUps` waits on it, so the fake has to keep it
                    // honest or every follow-up test measures the wrong thing.
                    if self.answersKeepAConversation.withLock({ $0 }) {
                        self.keepsConversation.withLock { $0 = true }
                    }
                    continuation.finish()
                }
            }
            inFlight.withLock { $0[turn] = InFlightTurn(task: task, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A turn the fake is streaming, for `stop()` and `reset()` to cancel
    /// when `cancelsTheTurnInFlight` is set.
    private struct InFlightTurn: Sendable {
        let task: Task<Void, Never>
        let continuation: AsyncThrowingStream<AskTurnEvent<UIRow>, any Error>.Continuation
    }

    private let inFlight = Mutex<[UUID: InFlightTurn]>([:])

    /// Whether `stop()` and `reset()` cancel the turn in flight, as
    /// `AskEngine`'s do: its stream ends by throwing `CancellationError`,
    /// which the store reads as a stop from the engine's side. Off by
    /// default, where the two only count, so a test that doesn't model the
    /// engine's cancellation isn't moved by it.
    let cancelsTheTurnInFlight = Mutex(false)

    /// Where `AskEngine`'s `stop()` and `reset()` hop to the engine's actor,
    /// and the main actor runs on meanwhile: a question asked there can reach
    /// the engine first, and be the turn the call then cancels. A fake that
    /// ran its body inline would never let that happen.
    private func hopToTheEngine() async {
        guard cancelsTheTurnInFlight.withLock({ $0 }) else { return }
        for _ in 0..<10 { await Task.yield() }
    }

    private func cancelTheTurnInFlight() {
        guard cancelsTheTurnInFlight.withLock({ $0 }) else { return }
        let turns = inFlight.withLock { turns in
            defer { turns = [:] }
            return Array(turns.values)
        }
        for turn in turns {
            turn.continuation.finish(throwing: CancellationError())
            turn.task.cancel()
        }
    }

    /// The mirror the screen reads. A test drives `.cannotServe` and the quota
    /// banner by applying a snapshot to it, the same way a seam does.
    ///
    /// **One per asker, never one per process.** A `static let` here would be
    /// a shared mutable mirror, and Swift Testing runs tests in parallel, so
    /// two tests applying different snapshots would race: a failure a serial
    /// run never shows. Built lazily because `AskModelStatus` is `@MainActor`
    /// and this initialiser is not.
    private let statusBox = Mutex<AskModelStatus?>(nil)

    @MainActor var status: AskModelStatus {
        if let existing = statusBox.withLock({ $0 }) { return existing }
        let fresh = AskModelStatus()
        statusBox.withLock { $0 = fresh }
        return fresh
    }

    func stop() async {
        await hopToTheEngine()
        if parksStop.withLock({ $0 }) {
            await withCheckedContinuation { parked in
                parkedStop.withLock { $0 = parked }
            }
        }
        stops.withLock { $0 += 1 }
        lifecycle.withLock { $0.append("stop") }
        cancelTheTurnInFlight()
    }

    func reset() async {
        await hopToTheEngine()
        resets.withLock { $0 += 1 }
        lifecycle.withLock { $0.append("reset") }
        if parksReset.withLock({ $0 }) {
            await withCheckedContinuation { parked in
                parkedReset.withLock { $0 = parked }
            }
        }
        // After the park, as `AskEngine.reset()` cancels whatever is in
        // flight when it runs, not when it was called.
        cancelTheTurnInFlight()
        keepsConversation.withLock { $0 = false }
    }

    /// Whether the fake keeps a conversation, as `AskEngine` would: true once
    /// a turn has answered or a tail has been resumed, false after a reset.
    let keepsConversation = Mutex(false)
    /// Whether a turn that answers keeps a conversation, for a test of an
    /// engine that answers without one.
    let answersKeepAConversation = Mutex(true)

    var hasKeptConversation: Bool {
        get async {
            // Once: the read as the parked turn's stream ends.
            if parksKeptConversationRead.withLock({ parks in defer { parks = false }; return parks }) {
                await withCheckedContinuation { parked in
                    parkedKeptConversationRead.withLock { $0 = parked }
                }
            }
            return keepsConversation.withLock { $0 }
        }
    }

    /// Holds the next read of `hasKeptConversation` until
    /// `releaseKeptConversationRead()`: the hop to the engine a turn makes as
    /// its stream ends, for a test to act in.
    let parksKeptConversationRead = Mutex(false)
    private let parkedKeptConversationRead = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// Returns once a read is parked, or once `yieldUntil` gives up.
    func keptConversationReadIsParked() async {
        await yieldUntil { parkedKeptConversationRead.withLock { $0 != nil } }
    }

    /// Let a parked read finish.
    func releaseKeptConversationRead() {
        parkedKeptConversationRead.withLock { parked in
            parked?.resume()
            parked = nil
        }
    }

    /// Holds `stop()` until `releaseStop()`: Stop's word still on its way to
    /// the engine, for a test to act in.
    let parksStop = Mutex(false)
    private let parkedStop = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// Returns once a stop is parked, or once `yieldUntil` gives up.
    func stopIsParked() async {
        await yieldUntil { parkedStop.withLock { $0 != nil } }
    }

    /// Let a parked stop finish, and park no more.
    func releaseStop() {
        parksStop.withLock { $0 = false }
        parkedStop.withLock { parked in
            parked?.resume()
            parked = nil
        }
    }

    /// Holds `reset()` until `releaseReset()`: the store mid-way through
    /// swapping one chat for another, for a test to act in.
    let parksReset = Mutex(false)
    private let parkedReset = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// Returns once a parked reset is waiting, or once `yieldUntil` gives up.
    func resetIsParked() async {
        await yieldUntil { parkedReset.withLock { $0 != nil } }
    }

    /// Let a parked reset finish.
    func releaseReset() {
        parkedReset.withLock { parked in
            parked?.resume()
            parked = nil
        }
    }

    func prewarm() async {
        prewarms.withLock { $0 += 1 }
        lifecycle.withLock { $0.append("prewarm") }
    }

    /// How many times the store let a warm go. Counted apart from
    /// `lifecycle`, which tests compare whole.
    let forgets = Mutex(0)

    func forgetWarmIfEmpty() async {
        forgets.withLock { $0 += 1 }
    }

    func refreshStatus() async {
        refreshes.withLock { $0 += 1 }
        if parksRefresh.withLock({ $0 }) {
            await withCheckedContinuation { parked in
                parkedRefresh.withLock { $0 = parked }
            }
        }
        if let snapshot = refreshSnapshot.withLock({ $0 }) {
            await MainActor.run { status.apply(snapshot) }
        }
    }

    /// What `refreshStatus()` publishes to the mirror, as a seam does, or nil
    /// to publish nothing, as an engine with no seam of its own does.
    let refreshSnapshot = Mutex<AskModelStatus.Snapshot?>(nil)
    /// Holds `refreshStatus()` until `releaseRefresh()`: a Private Cloud
    /// Compute probe that takes its time, for a test to look at the screen
    /// meanwhile.
    let parksRefresh = Mutex(false)
    private let parkedRefresh = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// Returns once a parked refresh is waiting, or once `yieldUntil` gives up.
    func refreshIsParked() async {
        await yieldUntil { parkedRefresh.withLock { $0 != nil } }
    }

    /// Let a parked refresh finish.
    func releaseRefresh() {
        parkedRefresh.withLock { parked in
            parked?.resume()
            parked = nil
        }
    }

    func resume(from tail: [AskThreadTail]) async {
        resumedTails.withLock { $0.append(tail) }
        lifecycle.withLock { $0.append("resume") }
        if !tail.isEmpty { keepsConversation.withLock { $0 = true } }
    }

    func recordFeedback(_ feedback: AskFeedback, isLatestTurn: Bool) async -> Data? {
        feedbacks.withLock { $0.append((feedback, isLatestTurn)) }
        return isLatestTurn ? Data("attachment".utf8) : nil
    }
}

// MARK: - Domain

/// The domain the store's tests run on. Nothing here reaches a model: the
/// store asks it for the brand, the overview, the starters, the persistence
/// and the first-screen policy, and for what the tests vary: which answers can
/// be rerolled, the referent, whether it takes photos, and carrying out a
/// proposal.
nonisolated struct UIDomain: AskDomain {
    typealias Row = UIRow
    typealias SearchArguments = UISearchArguments

    var rows: [UIRow] = UIRow.three
    var persistenceMode: AskPersistence = .perLaunch
    var rerollKinds: Set<AskQuestionKind> = [AskQuestionKind.pick]
    /// Titles `referent(from:)` adds beyond the tiles, as a domain that reads
    /// "tiles, else what the prose named" would.
    var extraReferents: [String] = []
    var starterTexts: [String] = ["What do I own?", "Anything from 1970?", "Which are on vinyl?"]
    /// The ids the starters take, in order, as a host's slugs: empty for
    /// starters whose id is their text.
    var starterIDs: [String] = []
    /// What the nothing-to-ask screen says, or nil for a brand with no words
    /// for it.
    var nothingToAskCopy: String? = "nothing"

    var brand: AskBrand {
        AskBrand(
            title: "Ask Test", appDirectory: "AskKitUITests",
            logSubsystem: "AskKit.uitests", help: "help",
            firstScreenHeadline: "headline", firstScreenSentence: "sentence",
            nothingToAskCopy: nothingToAskCopy, disclosureSentence: "disclosure",
            scopeCaveat: "caveat"
        )
    }

    var persistence: AskPersistence { persistenceMode }

    /// What `overview()` does besides answering: where it ran, and whether it
    /// waits for the test.
    let overviewHook = OverviewHook()
    /// The domain's turn deadline, which also bounds the store's read of the
    /// overview (`AskConversationStore.refresh()`): the hook's, so a test can
    /// shorten it once a first read has landed at the default.
    var turnDeadline: Duration { overviewHook.deadline.withLock { $0 } }

    var acceptsPhotos = true
    var acceptsPhotoAttachments: Bool { acceptsPhotos }

    func overview() async -> AskOverview {
        await overviewHook.enter()
        return AskOverview(scopes: [.init(id: "records", name: "Records", count: rows.count)], total: rows.count)
    }

    func makeTools(_ context: AskToolContext<UIRow>) -> [any Tool] { [] }
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "Answer." }
    var promptPrefix: String { "PREFIX\n" }
    func promptLines(question: String, overview: AskOverview) async -> [String] { [] }
    var searchPlanInstructions: String { "Choose." }
    func search(_ arguments: UISearchArguments, context: AskToolContext<UIRow>) async throws -> String { "" }

    func starters(overview: AskOverview, window: Int) -> [AskStarter] {
        starterTexts.prefix(window).enumerated().map { index, text in
            AskStarter(id: starterIDs.indices.contains(index) ? starterIDs[index] : nil, text: text)
        }
    }

    func referent(from answer: AskAnswer<UIRow>) -> [String] { answer.tiles.map(\.displayTitle) + extraReferents }

    var rerollableKinds: Set<AskQuestionKind> { rerollKinds }

    /// Questions whose picks the domain says are superlatives.
    var nonRerollableQuestions: Set<String> = []

    func isRerollable(_ answer: AskAnswer<UIRow>, question: String) -> Bool {
        guard !nonRerollableQuestions.contains(question), let kind = answer.questionKind else { return false }
        return rerollKinds.contains(kind)
    }

    /// The line `perform` returns, unless `performError` is set.
    var performLine: String? = "Marked The Peregrine as lent."
    var performError: (any Error)?
    /// Every proposal `perform` was handed.
    let performed = PerformLog()

    func perform(_ proposal: AskProposal) async throws -> String? {
        await performed.record(proposal)
        if let performError { throw performError }
        return performLine
    }
}

/// What a domain's `overview()` does besides answering. A class, for the
/// reason `PerformLog` is one.
nonisolated final class OverviewHook: Sendable {
    /// The domain's turn deadline (`UIDomain.turnDeadline`).
    let deadline = Mutex<Duration>(.seconds(45))
    /// Whether each read ran on the main thread, in order.
    let ranOnTheMainThread = Mutex<[Bool]>([])
    /// Whether a read waits until `release()`: a host's overview that counts
    /// its library over the network, or never returns.
    let parks = Mutex(false)
    private let parked = Mutex<[CheckedContinuation<Void, Never>]>([])

    func enter() async {
        ranOnTheMainThread.withLock { $0.append(pthread_main_np() != 0) }
        guard parks.withLock({ $0 }) else { return }
        await withCheckedContinuation { continuation in
            parked.withLock { $0.append(continuation) }
        }
    }

    /// Returns once a read is parked, or once `yieldUntil` gives up.
    func isParked() async {
        await yieldUntil { parked.withLock { !$0.isEmpty } }
    }

    /// Let every parked read finish, and park no more.
    func release() {
        parks.withLock { $0 = false }
        let waiting = parked.withLock { parked in
            defer { parked = [] }
            return parked
        }
        for continuation in waiting { continuation.resume() }
    }
}

/// The proposals a domain was asked to carry out. A class, because `Mutex` is
/// non-Copyable and the domain is a struct.
nonisolated final class PerformLog: Sendable {
    private let log = Mutex<[AskProposal]>([])
    /// Whether `perform` waits, once it has recorded the proposal, until
    /// `release()`: a host's perform that takes its time, such as a network
    /// call, for a test to change the chat while it runs.
    let parks = Mutex(false)
    private let parked = Mutex<[CheckedContinuation<Void, Never>]>([])
    /// Whether each perform ran on the main thread, in order.
    let ranOnTheMainThread = Mutex<[Bool]>([])
    /// The thread file to read as each perform begins, or nil for none.
    let watchedThread = Mutex<URL?>(nil)
    /// What the watched thread's newest turn held for its proposal as each
    /// perform began: the yes, if it was saved first.
    let outcomesOnDiskAtEntry = Mutex<[AskProposalOutcome?]>([])

    func record(_ proposal: AskProposal) async {
        ranOnTheMainThread.withLock { $0.append(pthread_main_np() != 0) }
        if let url = watchedThread.withLock({ $0 }) {
            let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: url).load().entries.last?.proposalOutcome
            outcomesOnDiskAtEntry.withLock { $0.append(onDisk) }
        }
        log.withLock { $0.append(proposal) }
        guard parks.withLock({ $0 }) else { return }
        await withCheckedContinuation { continuation in
            parked.withLock { $0.append(continuation) }
        }
    }

    var proposals: [AskProposal] { log.withLock { $0 } }

    /// Returns once a perform is parked, or once `yieldUntil` gives up.
    func isParked() async {
        await yieldUntil { parked.withLock { !$0.isEmpty } }
    }

    /// Let every parked perform finish, and park no more.
    func release() {
        parks.withLock { $0 = false }
        let waiting = parked.withLock { parked in
            defer { parked = [] }
            return parked
        }
        for continuation in waiting { continuation.resume() }
    }
}

@Generable
nonisolated struct UISearchArguments: Sendable {
    @Guide(description: "What to search for.")
    var query: String
}

/// An engine that reads no photos and no scopes: only the seven members
/// `AskAnswering` requires, so photos, scopes and everything else take the
/// protocol's defaults.
nonisolated final class WordsOnlyAsker: AskAnswering, @unchecked Sendable {
    typealias Row = UIRow

    private let inner = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(AskAnswer<UIRow>(text: "Words."))]))

    func ask(_ question: String, mode: AskTurnMode) -> AsyncThrowingStream<AskTurnEvent<UIRow>, any Error> {
        inner.ask(question, mode: mode)
    }

    func stop() async {}
    func reset() async {}
    func prewarm() async {}
    func refreshStatus() async {}
    @MainActor var status: AskModelStatus { inner.status }
    var hasKeptConversation: Bool {
        get async { await inner.hasKeptConversation }
    }
}

/// One opaque pixel, for the paths that need a `CGImage` and never look at it.
func onePixel() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alpha: .premultipliedLast)
    )
    context?.setFillColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1)
    context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard let image = context?.makeImage() else { preconditionFailure("a one-pixel bitmap always makes an image") }
    return image
}

// MARK: - Convenience

extension AskAnswer where Row == UIRow {
    static func of(
        _ text: String,
        tiles: [UIRow] = [],
        followUps: [String] = [],
        truncated: Bool = false,
        kind: AskQuestionKind? = nil
    ) -> AskAnswer<UIRow> {
        AskAnswer(
            text: text, matches: tiles, tiles: tiles, followUps: followUps,
            questionKind: kind, isTruncated: truncated
        )
    }
}

/// The one folder this test process writes into, removed as the process exits.
///
/// **One folder, not the temporary directory's top level,** so a run leaves
/// nothing behind. A store a test builds writes its thread, the chats it files
/// and its feedback wherever `temporaryLocation` points, and most tests don't
/// remove what it wrote. Removed at exit rather than after each test, because
/// a store writes from tasks of its own, and a write can land after the test
/// that started it has returned.
nonisolated enum TestScratch {
    static let root: URL = {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AskKitUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        // Made up front: a test that writes a file of its own at a location
        // from here would otherwise find no folder to write it in.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TestScratch.root) }
        return root
    }()
}

/// A fresh, private scratch location per call — Swift Testing runs tests in
/// parallel, and two stores sharing a file race.
func temporaryLocation(_ prefix: String) -> URL {
    TestScratch.root.appending(path: "\(prefix)-\(UUID().uuidString)")
}

@MainActor
func makeStore(
    domain: UIDomain = UIDomain(),
    asker: ScriptedAsker,
    threadURL: URL? = nil,
    archiveDirectory: URL? = nil,
    attachmentsDirectory: URL? = nil,
    clock: @escaping @Sendable () -> TimeInterval = { 0 }
) -> AskConversationStore<UIDomain> {
    AskConversationStore(
        domain: domain,
        engine: asker,
        thread: AskThreadStore<UIRow>(
            appDirectory: domain.brand.appDirectory,
            url: threadURL ?? temporaryLocation("askkit-ui").appendingPathExtension("json")
        ),
        // Never the real one: a default archive is Application Support, and a
        // test filing chats there leaves them for the next run to list.
        archive: AskThreadArchive<UIRow>(
            appDirectory: domain.brand.appDirectory,
            directory: archiveDirectory ?? temporaryLocation("askkit-ui-archive")
        ),
        feedbackAttachments: AskFeedbackAttachments(
            appDirectory: domain.brand.appDirectory,
            directory: attachmentsDirectory ?? temporaryLocation("askkit-ui-feedback")
        ),
        clock: clock
    )
}

/// How long `settle`, `eventually` and `yieldUntil` wait before giving up.
///
/// **Long, because only a failing test ever waits it out.** All three return the
/// moment their condition holds, so the deadline costs a passing run nothing.
/// Two seconds is too short: on a machine shared with a simulator, an
/// on-device model run and another build, at a load average of 170, the fake
/// engine's turn went unscheduled that long, and twenty store assertions
/// failed with nothing wrong. No test waits for one of these to run out on
/// purpose.
nonisolated let storeWaitDeadline: Double = 15

/// Wait for the store's in-flight turn to settle, or give up.
///
/// Every wait here also stops when the test is cancelled, which is what the
/// suites' time limit does to a test that runs past it. A cancelled
/// `Task.sleep` returns at once, so a loop that doesn't look spins hot to its
/// deadline.
@MainActor
func settle(_ store: AskConversationStore<UIDomain>, within seconds: Double = storeWaitDeadline) async {
    let deadline = ContinuousClock().now + .seconds(seconds)
    while store.isThinking, !Task.isCancelled, ContinuousClock().now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Wait for what a store does in a task of its own — the engine's reset and
/// warm as a chat ends — up to a deadline. The caller still asserts: this only
/// stops waiting.
@MainActor
func eventually(within seconds: Double = storeWaitDeadline, _ condition: () -> Bool) async {
    let deadline = ContinuousClock().now + .seconds(seconds)
    while !condition(), !Task.isCancelled, ContinuousClock().now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Yield until a turn reaches the point a test acts at — its first words,
/// its tier — or give up.
///
/// **Yielding, not sleeping like `eventually`,** because the test acts the
/// moment the condition holds: a turn stopped mid-stream has to be stopped
/// while it is mid-stream. **Bounded and cancellable,** because a bare
/// `while … { await Task.yield() }` whose condition never comes true hangs the
/// run: the suite's time limit cancels the test, and a loop that never looks
/// at cancellation spins on past it, the process with it.
nonisolated func yieldUntil(within seconds: Double = storeWaitDeadline, _ condition: () -> Bool) async {
    let deadline = ContinuousClock().now + .seconds(seconds)
    while !condition(), !Task.isCancelled, ContinuousClock().now < deadline {
        await Task.yield()
    }
}

#endif
