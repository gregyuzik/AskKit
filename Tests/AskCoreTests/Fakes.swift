#if canImport(FoundationModels) && !os(tvOS)

import CoreGraphics
import Foundation
import FoundationModels
import Synchronization

@_spi(AskKitInternal) @testable import AskCore

// MARK: - Rows

nonisolated struct FakeRow: AskRow {
    let id: String
    let displayTitle: String

    init(_ title: String) {
        id = title
        displayTitle = title
    }

    init(id: String, displayTitle: String) {
        self.id = id
        self.displayTitle = displayTitle
    }
}

extension FakeRow {
    /// Six rows, deliberately including a punctuation trap and a two-letter
    /// title, because those are the two cases tile resolution gets wrong.
    static let six = [
        FakeRow("Kind of Blue"),
        FakeRow("...And Justice For All"),
        FakeRow("Abbey Road"),
        FakeRow("Rumours"),
        FakeRow("Go"),
        FakeRow("The Dark Side of the Moon")
    ]
}

// MARK: - The collector bridge

/// A real tool records rows into the collector the engine built. The fake seam
/// never sees that collector — only `AskDomain.makeTools` does — so the domain
/// publishes it here and the fake session records through it at the moment a
/// generation starts, which is where a tool call really happens.
nonisolated final class CollectorBridge: @unchecked Sendable {
    let collector = Mutex<AskCollector<FakeRow>?>(nil)
    /// The relay the domain's tools were handed — the same object for a
    /// session's life, which is the whole point of it.
    let relay = Mutex<AskActivityRelay?>(nil)
    let rows = Mutex<[FakeRow]>(FakeRow.six)

    func publish(_ collector: AskCollector<FakeRow>, relay: AskActivityRelay) {
        self.collector.withLock { $0 = collector }
        self.relay.withLock { $0 = relay }
    }

    /// Called at the start of each scripted generation, for scripts that say a
    /// tool was called.
    func recordAToolCall(reporting activity: AskActivity = .searching(scope: "records")) async {
        guard let collector = collector.withLock({ $0 }) else { return }
        await collector.noteToolCall(activity)
        await collector.record(rows: rows.withLock { $0 })
        await collector.noteToolFinished()
    }

    /// What a tool also knew this turn, recorded where a real tool records it.
    func recordPayload(_ payload: Data) async {
        guard let collector = collector.withLock({ $0 }) else { return }
        await collector.record(encodedPayload: payload)
    }

    /// A narration the collector knows nothing about, reported with no tool
    /// of its own open — the reason the relay exists.
    func reportThroughRelay(_ activity: AskActivity) async {
        guard let relay = relay.withLock({ $0 }) else { return }
        await relay.report(activity)
    }

    /// The same narration made from *inside* the tool, before it reports
    /// finished — the ordering `AskToolContext` warns against, kept here so the
    /// engine's side of that warning is pinned rather than described.
    func reportThroughRelayMidTool(_ activity: AskActivity) async {
        guard let collector = collector.withLock({ $0 }),
              let relay = relay.withLock({ $0 }) else { return }
        await collector.noteToolCall(.searching(scope: "records"))
        await collector.record(rows: rows.withLock { $0 })
        await relay.report(activity)
        await collector.noteToolFinished()
    }
}

// MARK: - Holds and hooks

/// A place a fake can stop until the test lets it go. Armed, every call that
/// reaches it waits there; armed once, only the first does. Released, every
/// waiter goes on, and later calls pass straight through.
///
/// A checked continuation rather than a sleep, so a waiter can't notice
/// cancellation: it is the stand-in for a call that hangs on the network,
/// which is exactly the kind of call that doesn't.
nonisolated final class TestHold: Sendable {
    private struct State {
        var armed = false
        var once = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        var cancellations = 0
    }

    private let state = Mutex(State())

    /// How many waiters' tasks were cancelled while they waited here, which
    /// is all a waiter that can't notice cancellation lets anyone see of it.
    var cancellations: Int { state.withLock { $0.cancellations } }

    func arm(once: Bool = false) {
        state.withLock {
            $0.armed = true
            $0.once = once
        }
    }

    /// How many calls are waiting here.
    var waiters: Int { state.withLock { $0.waiting.count } }

    func release() {
        let waiting = state.withLock { state in
            state.armed = false
            defer { state.waiting = [] }
            return state.waiting
        }
        for waiter in waiting { waiter.resume() }
    }

    /// Wait here while armed, or go straight on.
    func pass() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                let goes = state.withLock { state -> Bool in
                    guard state.armed else { return true }
                    if state.once { state.armed = false }
                    state.waiting.append(waiter)
                    return false
                }
                if goes { waiter.resume() }
            }
        } onCancel: {
            state.withLock { $0.cancellations += 1 }
        }
    }

    /// Returns once a call is waiting here, or once `yieldUntil` gives up.
    func isReached() async {
        await yieldUntil { waiters > 0 }
    }
}

/// Something a test runs inside a fake's synchronous callback.
nonisolated final class TestHook: Sendable {
    private let body = Mutex<(@Sendable () -> Void)?>(nil)

    func set(_ newBody: (@Sendable () -> Void)?) {
        body.withLock { $0 = newBody }
    }

    func run() {
        body.withLock { $0 }?()
    }
}

// MARK: - Session

/// A session that emits whatever the test scripted, and records what it was
/// asked.
nonisolated final class FakeSession: AskSession, @unchecked Sendable {
    struct Script: Sendable {
        var snapshots: [AskReplySnapshot] = []
        /// Thrown instead of emitting, or after the snapshots run out.
        var error: (any Error)?
        /// Never finishes — for testing the deadline.
        var hangs = false
        /// Waits this long before its first snapshot: a generation that takes
        /// its time, for a deadline one turn's generations share.
        var delay: Duration?
        /// Emits every snapshot and THEN never finishes: the ceiling arriving
        /// on a turn that has already written prose, which is the only way
        /// truncation happens.
        var hangsAfterSnapshots = false
        /// Emits every snapshot, then waits for `releaseGeneration()` before it
        /// finishes, whatever was cancelled meanwhile: a generation that can't
        /// notice cancellation, which is the kind a turn has to stop from its
        /// own side.
        var holdsAfterSnapshots = false
        /// Tool calls the transcript will report after this generation.
        var toolCallsAfter = 0
        /// What the scripted tool call tells the collector it is doing. Not
        /// always a search: a host's tool may report `.custom` for every call.
        var toolActivity: AskActivity = .searching(scope: "records")
        /// Reported through the relay at generation start — a tool the
        /// collector never hears about.
        var relayReports: [AskActivity] = []
        /// Reported through the relay from *inside* an open collector tool, the
        /// shape `AskToolContext` warns against. Replaces the plain scripted
        /// tool call, so `toolCallsAfter` still drives grounding.
        var relayReportsMidTool: [AskActivity] = []
        /// Recorded into the collector at generation start, the way a tool
        /// records a turn's payload.
        var payload: Data?
        /// Recorded into the collector at generation start, the way a
        /// proposing tool records what the turn offers to do.
        var proposal: AskProposal?
        var usage: AskUsage?
        var contextSize: Int?
        /// Holds the next read of the transcript's tool-call count, the one the
        /// engine makes as it judges the first snapshot, until the test
        /// releases `countRead`: a snapshot loop caught between two hops when
        /// the deadline gives up on it.
        var holdsCountReadMidStream = false
    }

    private let state = Mutex(Script())
    /// Consumed one per generation, ahead of `state` — for the turns that need
    /// a different script the second time round (a rollover, a retry).
    private let queued = Mutex<[Script]>([])
    let prompts = Mutex<[String]>([])
    let schemaFlags = Mutex<[Bool]>([])
    let reasoningLevels = Mutex<[AskReasoningLevel?]>([])
    let temperatures = Mutex<[Double]>([])
    let feedbackRequests = Mutex<[AskFeedback.Sentiment]>([])
    let planCalls = Mutex(0)
    let prewarmCalls = Mutex<[String]>([])
    /// Generations let go before they finished: the turn that asked for one
    /// was stopped.
    let generationsCancelled = Mutex(0)
    private let heldGeneration = Mutex<CheckedContinuation<Void, Never>?>(nil)
    /// Where a scripted tool call records its rows.
    let bridge: CollectorBridge
    /// The transcript's tool-call count, which grows when a generation runs —
    /// as a real session's does, so a turn's `before` read is honestly zero.
    private let observedCalls = Mutex(0)

    init(bridge: CollectorBridge = CollectorBridge(), _ script: Script = Script()) {
        self.bridge = bridge
        state.withLock { $0 = script }
    }

    func script(_ script: Script) {
        state.withLock { $0 = script }
    }

    /// Scripts consumed in order, one per generation; `state` answers once they
    /// run out.
    func scripts(_ list: [Script]) {
        queued.withLock { $0 = list }
    }

    var toolCalls: Int { state.withLock { $0.toolCallsAfter } }

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt, images: [], temperature: temperature,
            reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    /// The labels of the photos each generation was sent, in order — empty for
    /// a generation sent none.
    let imageLabels = Mutex<[[String]]>([])
    /// The reply shape each generation asked for, in order. A generation that
    /// came in by a stream with no shape, as `AskSession`'s default sends one,
    /// adds nothing here.
    let shapes = Mutex<[AskReplyShape]>([])

    /// The scripted generation in the shape asked for. A prose reply has no
    /// kind and no tiles, as `AppleAskSession`'s doesn't, so each snapshot
    /// goes out without them, whatever the script wrote.
    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        shapes.withLock { $0.append(shape) }
        let full = stream(
            prompt: prompt, images: images, temperature: temperature,
            reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
        )
        guard shape == .prose else { return full }
        let (prose, continuation) = AsyncThrowingStream<AskReplySnapshot, any Error>.makeStream()
        let task = Task {
            do {
                for try await snapshot in full {
                    continuation.yield(AskReplySnapshot(answer: snapshot.answer, followUps: snapshot.followUps))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return prose
    }

    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        imageLabels.withLock { $0.append(images.map(\.label)) }
        prompts.withLock { $0.append(prompt) }
        schemaFlags.withLock { $0.append(includeSchemaInPrompt) }
        reasoningLevels.withLock { $0.append(reasoningLevel) }
        temperatures.withLock { $0.append(temperature) }
        let script = queued.withLock { $0.isEmpty ? nil : $0.removeFirst() } ?? state.withLock { $0 }
        observedCalls.withLock { $0 += script.toolCallsAfter }
        return AsyncThrowingStream { [bridge] continuation in
            let task = Task {
                if let payload = script.payload { await bridge.recordPayload(payload) }
                if let proposal = script.proposal, let collector = bridge.collector.withLock({ $0 }) {
                    await collector.record(proposal: proposal)
                }
                // The rows land where a real tool would put them: after the
                // turn's `beginTurn`, before the first snapshot.
                if script.toolCallsAfter > 0 {
                    if script.relayReportsMidTool.isEmpty {
                        await bridge.recordAToolCall(reporting: script.toolActivity)
                    } else {
                        for activity in script.relayReportsMidTool {
                            await bridge.reportThroughRelayMidTool(activity)
                        }
                    }
                }
                for activity in script.relayReports { await bridge.reportThroughRelay(activity) }
                if let delay = script.delay { try? await Task.sleep(for: delay) }
                // Before the first snapshot is out, so the read it holds is
                // the one the engine makes as it judges that snapshot.
                if script.holdsCountReadMidStream { self.countRead.arm(once: true) }
                if script.hangs {
                    // Long enough that any test deadline wins first.
                    try? await Task.sleep(for: .seconds(600))
                    continuation.finish()
                    return
                }
                for snapshot in script.snapshots {
                    if Task.isCancelled { break }
                    continuation.yield(snapshot)
                    await Task.yield()
                }
                if script.holdsAfterSnapshots {
                    await withCheckedContinuation { held in
                        self.heldGeneration.withLock { $0 = held }
                    }
                }
                if script.hangsAfterSnapshots {
                    try? await Task.sleep(for: .seconds(600))
                    continuation.finish()
                    return
                }
                if let error = script.error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { self.generationsCancelled.withLock { $0 += 1 } }
                task.cancel()
            }
        }
    }

    /// Returns once a held generation is waiting, or once `yieldUntil` gives
    /// up.
    func generationIsHeld() async {
        await yieldUntil { heldGeneration.withLock { $0 != nil } }
    }

    /// Let a held generation finish.
    func releaseGeneration() {
        heldGeneration.withLock { held in
            held?.resume()
            held = nil
        }
    }

    /// What the refinement pass was shown, so a test can assert it reached
    /// THIS session rather than a new one.
    let respondCalls = Mutex<[(labels: [String], prompt: String)]>([])

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        respondCalls.withLock { $0.append((images.map(\.label), prompt)) }
        throw AskError.couldNotAnswer
    }

    /// What each grounded retry's planner was asked, in order.
    let planPrompts = Mutex<[String]>([])
    /// How long the planner takes to choose, for a test that needs it slow.
    let planDelay = Mutex<Duration?>(nil)
    /// Thrown by the planner, raw, the way a session's failure arrives.
    let planError = Mutex<(any Error)?>(nil)

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        planCalls.withLock { $0 += 1 }
        planPrompts.withLock { $0.append(prompt) }
        if let delay = planDelay.withLock({ $0 }) { try await Task.sleep(for: delay) }
        if let error = planError.withLock({ $0 }) { throw error }
        // A rowless domain's planner has nothing to choose, and chooses it.
        if let nothing = AskNoSearchArguments() as? Arguments { return nothing }
        guard let arguments = FakeSearchArguments(query: "planned") as? Arguments else {
            throw AskError.couldNotAnswer
        }
        return arguments
    }

    /// Where a script's `holdsCountReadMidStream` stops a transcript read.
    let countRead = TestHold()

    func toolCallCount() async -> Int {
        await countRead.pass()
        return observedCalls.withLock { $0 }
    }
    /// Where `usage()` and `contextSize()` can be made to wait, as a host's
    /// session that never answers them would.
    let usageHold = TestHold()
    let contextSizeHold = TestHold()

    func usage() async -> AskUsage? {
        await usageHold.pass()
        return state.withLock { $0.usage }
    }
    func contextSize() async -> Int? {
        await contextSizeHold.pass()
        return state.withLock { $0.contextSize }
    }
    func tokenCount(for text: String) async -> Int? { nil }
    /// Holds `prewarm` until `releasePrewarm()`, so a test can ask a question
    /// while a warm is still being made.
    let holdsPrewarm = Mutex(false)
    private let heldPrewarm = Mutex<CheckedContinuation<Void, Never>?>(nil)

    func prewarm(promptPrefix: String) async {
        prewarmCalls.withLock { $0.append(promptPrefix) }
        guard holdsPrewarm.withLock({ $0 }) else { return }
        await withCheckedContinuation { continuation in
            heldPrewarm.withLock { $0 = continuation }
        }
    }

    /// Returns once a held prewarm is waiting, or once `yieldUntil` gives up.
    func prewarmIsHeld() async {
        await yieldUntil { heldPrewarm.withLock { $0 != nil } }
    }

    func releasePrewarm() {
        heldPrewarm.withLock { held in
            held?.resume()
            held = nil
        }
    }

    func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data? {
        feedbackRequests.withLock { $0.append(sentiment) }
        return Data("attachment-\(sentiment.rawValue)".utf8)
    }
}

@Generable
nonisolated struct FakeSearchArguments: Sendable {
    @Guide(description: "What to search for.")
    var query: String
}

/// A session that writes the words-only stream and leaves the photo stream to
/// `AskSession`'s default, as a session built outside AskKit may.
nonisolated struct WordsOnlySession: AskSession {
    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(AskReplySnapshot(
                answer: "Words.", questionKind: nil, showsEveryMatch: nil, tiles: nil, followUps: nil
            ))
            continuation.finish()
        }
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type, instructions: String, prompt: String
    ) async throws -> Arguments {
        throw AskError.couldNotAnswer
    }

    func toolCallCount() async -> Int { 0 }
    func usage() async -> AskUsage? { nil }
    func contextSize() async -> Int? { nil }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        throw AskError.couldNotAnswer
    }

    func prewarm(promptPrefix: String) async {}
}

/// A `FakeSession` behind a session written before reply shapes, as one
/// built outside AskKit may be: it passes on every member but the shaped
/// stream, so `AskSession`'s default answers that one, and the script's kind
/// and tiles reach the engine whatever shape it asked for.
nonisolated struct ShapelessSession: AskSession {
    let base: FakeSession

    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        base.stream(
            prompt: prompt, temperature: temperature,
            reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        base.stream(
            prompt: prompt, images: images, temperature: temperature,
            reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type, instructions: String, prompt: String
    ) async throws -> Arguments {
        try await base.plan(type, instructions: instructions, prompt: prompt)
    }

    func toolCallCount() async -> Int { await base.toolCallCount() }
    func usage() async -> AskUsage? { await base.usage() }
    func contextSize() async -> Int? { await base.contextSize() }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        try await base.respond(type, images: images, prompt: prompt, temperature: temperature, reasoningLevel: reasoningLevel)
    }

    func prewarm(promptPrefix: String) async { await base.prewarm(promptPrefix: promptPrefix) }
}

// MARK: - Photos

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

func testPhoto(_ label: String = "Blue record sleeve") -> AskImageAttachment {
    AskImageAttachment(label: label, image: onePixel())
}

// MARK: - Seam

/// A seam whose tier states, session and failures are all scripted.
nonisolated final class FakeSeam: AskModelSeam, @unchecked Sendable {
    let status: AskModelStatus

    let bridge: CollectorBridge
    private let states = Mutex<[AskTierState]>([])
    private let sessions = Mutex<[AskTier: FakeSession]>([:])
    let transportFailures = Mutex<[AskTier]>([])
    let refreshes = Mutex(0)
    let generationsGated = Mutex(0)
    /// `makeSession` returns nil for these tiers.
    let refusesSession = Mutex<Set<AskTier>>([])
    /// `makeSession` answers a request for a key's tier with its session in
    /// a box bound to the value's: a host's router handing back another
    /// tier's session.
    let boxesAs = Mutex<[AskTier: AskTier]>([:])
    /// Whether `makeSession` hands back each tier's session behind a
    /// `ShapelessSession`, which leaves the shaped stream to `AskSession`'s
    /// default.
    let buildsShapelessSessions = Mutex(false)
    /// The instructions each session was built with — where the answer language
    /// shows up, since only the domain can phrase it.
    let instructionsSeen = Mutex<[String]>([])
    /// What `answerLanguage(for:)` reports.
    let language = Mutex<String?>(nil)
    /// A real generation gate for on-device generations, as `AppleModelSeam`
    /// has, for a test about what a turn leaves holding it. Nil passes every
    /// generation straight through.
    let gate: AskGenerationGate?
    /// Where `refreshStatus`, `tierStates` and `answerLanguage` can be made to
    /// hang, as Private Cloud Compute's probes can on a stalled network.
    let refreshHold = TestHold()
    let tierStatesHold = TestHold()
    let languageHold = TestHold()

    init(
        status: AskModelStatus,
        states: [AskTierState] = [],
        bridge: CollectorBridge = CollectorBridge(),
        gate: AskGenerationGate? = nil
    ) {
        self.status = status
        self.bridge = bridge
        self.gate = gate
        self.states.withLock { $0 = states }
    }

    func set(_ newStates: [AskTierState]) { states.withLock { $0 = newStates } }

    func session(for tier: AskTier) -> FakeSession {
        sessions.withLock { table in
            if let existing = table[tier] { return existing }
            let fresh = FakeSession(bridge: bridge)
            table[tier] = fresh
            return fresh
        }
    }

    func tierStates() async -> [AskTierState] {
        await tierStatesHold.pass()
        return states.withLock { $0 }
    }

    func makeSession(
        tier: AskTier,
        tools: [any Tool],
        instructions: String
    ) async throws -> AskSessionBox? {
        instructionsSeen.withLock { $0.append(instructions) }
        guard !refusesSession.withLock({ $0.contains(tier) }) else { return nil }
        let boxed = boxesAs.withLock { $0[tier] } ?? tier
        if buildsShapelessSessions.withLock({ $0 }) {
            return AskSessionBox(session: ShapelessSession(base: session(for: tier)), tier: boxed)
        }
        return AskSessionBox(session: session(for: tier), tier: boxed)
    }

    func answerLanguage(for tier: AskTier) async -> String? {
        await languageHold.pass()
        return language.withLock { $0 }
    }

    func noteTransportFailure(on tier: AskTier) async {
        transportFailures.withLock { $0.append(tier) }
    }

    func withGeneration<T: Sendable>(
        onDevice: Bool,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        if onDevice { generationsGated.withLock { $0 += 1 } }
        guard onDevice, let gate else { return try await body() }
        return try await AskGenerationGate.run(gate: gate) { try await body() }
    }

    func refreshStatus() async {
        refreshes.withLock { $0 += 1 }
        await refreshHold.pass()
    }

    func showLimitIncrease() async {}
}

// MARK: - Domain

/// What a fake domain's `instructions` was asked for, in order.
nonisolated final class InstructionsLog: @unchecked Sendable {
    private let calls = Mutex<[(tier: AskTier, isConversation: Bool)]>([])

    func record(tier: AskTier, isConversation: Bool) {
        calls.withLock { $0.append((tier, isConversation)) }
    }

    var recorded: [(tier: AskTier, isConversation: Bool)] { calls.withLock { $0 } }
}

/// Whether each of a fake domain's searches ran inside a conversation, in
/// order.
nonisolated final class SearchLog: @unchecked Sendable {
    private let flags = Mutex<[Bool]>([])

    func record(isConversation: Bool) {
        flags.withLock { $0.append(isConversation) }
    }

    var isConversation: [Bool] { flags.withLock { $0 } }
}

/// Which sessions a fake domain's `refine` was handed, in order.
nonisolated final class SessionIdentityLog: @unchecked Sendable {
    private let ids = Mutex<[ObjectIdentifier]>([])

    func record(_ session: any AskSession) {
        // The engine hands `refine` the turn's session behind the generation
        // gate. The identity that matters is the session underneath.
        let underneath = (session as? AskGatedSession)?.base ?? session
        ids.withLock { $0.append(ObjectIdentifier(underneath as AnyObject)) }
    }

    var recorded: [ObjectIdentifier] { ids.withLock { $0 } }
}

/// A fake domain's `turnDeadline` while it is set: read at each question, so
/// one question can run out of time and the next have the whole of its own.
nonisolated final class DeadlineOverride: Sendable {
    private let value = Mutex<Duration?>(nil)

    func set(_ deadline: Duration?) {
        value.withLock { $0 = deadline }
    }

    var deadline: Duration? { value.withLock { $0 } }
}

/// How many times a fake domain's hook ran.
nonisolated final class CallCount: @unchecked Sendable {
    private let count = Mutex(0)

    func record() {
        count.withLock { $0 += 1 }
    }

    var recorded: Int { count.withLock { $0 } }
}

/// Six rows, one tool that records what it was asked for, and nothing clever.
nonisolated struct FakeDomain: AskDomain {
    typealias Row = FakeRow
    typealias SearchArguments = FakeSearchArguments

    /// Rows the tool hands back. The tool records into the collector, so a test
    /// that wants a grounded turn scripts the session's `toolCallsAfter` too.
    var rows: [FakeRow] = FakeRow.six
    var kinds: [AskQuestionKind] = AskQuestionKind.default
    var deadline: Duration = .seconds(45)
    /// Outranks `deadline` while set. A class, for `instructionsFor`'s reason.
    let deadlineOverride = DeadlineOverride()
    var deterministic: AskAnswer<FakeRow>?
    /// Where `deterministicAnswer(for:)` can be made to wait, as `overviewHold`
    /// makes `overview()` wait.
    let deterministicHold = TestHold()
    var refinement: AskAnswer<FakeRow>?
    var refinementThrows = false
    /// How long `refine` takes before it answers.
    var refinementDelay: Duration?
    /// Whether `refine` asks the model again, on the session it was handed,
    /// the way a pass that looks at photos of the rows it named does, rather
    /// than only reordering what it has.
    var refineAsksTheModel = false
    /// Identity of every session `refine` was handed — so a test can say
    /// it got the one the turn streamed on and not a fresh one. A class,
    /// because `Mutex` is non-Copyable and this domain is a struct.
    let refinedOn = SessionIdentityLog()
    var maxTurnsOverride: Int?
    /// Rows the app's own search returns during a grounded retry.
    var searchRows: [FakeRow] = FakeRow.six
    /// Thrown by the app's own search, raw, the way a domain's error arrives.
    var searchError: (any Error)?
    /// What `basis(for:)` says, when anything.
    var basisText: String?
    /// The kinds offering "Another pick": none, as the framework's default
    /// offers, unless a test lists some.
    var rerollKinds: Set<AskQuestionKind> = []
    /// Where `makeTools` publishes the collector the engine built.
    var bridge = CollectorBridge()
    /// The line each scope is asked with; a scope missing here gets none, as
    /// the framework's default gives none.
    var scopeLines: [String: String] = [:]
    /// The protocol's default, `.retrieval`, unless a test sets another. A
    /// test about the default itself uses a domain that names none.
    var grounding: AskGroundingPolicy = .retrieval
    /// The protocol's default, `.full`, unless a test sets another; as with
    /// `grounding`, a test about the default uses a domain that names none.
    var replyShape: AskReplyShape = .full

    var brand: AskBrand {
        AskBrand(
            title: "Ask Fake", appDirectory: "AskKitTests",
            logSubsystem: "AskKit.tests", help: "help",
            firstScreenHeadline: "headline", firstScreenSentence: "sentence",
            nothingToAskCopy: "nothing", disclosureSentence: "disclosure",
            scopeCaveat: "caveat"
        )
    }

    var questionKinds: [AskQuestionKind] { kinds }
    var turnDeadline: Duration { deadlineOverride.deadline ?? deadline }

    func maxTurns(for tier: AskTier) -> Int {
        if let maxTurnsOverride { return maxTurnsOverride }
        return tier == .privateCloud ? 8 : 3
    }

    /// How often `overview()` and `promptLines` ran — so a test can say a
    /// follow-up never waits on the overview, and a grounded retry asks for
    /// its lines once. Classes, for `instructionsFor`'s reason.
    let overviewReads = CallCount()
    let promptLineReads = CallCount()
    /// Where `overview()` can be made to wait, for as long as the test likes:
    /// a host's hook that never returns and can't notice it was stopped.
    let overviewHold = TestHold()
    /// Where `promptLines(question:overview:)` can be made to wait, as
    /// `overviewHold` makes `overview()` wait.
    let promptLinesHold = TestHold()
    /// Run inside `referent(from:)`, which the engine calls on its own actor
    /// once a turn's answer is out.
    let referentHook = TestHook()

    func overview() async -> AskOverview {
        overviewReads.record()
        await overviewHold.pass()
        return AskOverview(scopes: [.init(id: "records", name: "Records", count: rows.count)], total: rows.count)
    }

    func makeTools(_ context: AskToolContext<FakeRow>) -> [any Tool] {
        bridge.publish(context.collector, relay: context.relay)
        return []
    }

    /// Records what it was told, so a test can say the sentences and the tool
    /// set were built from the same flag. A class, because `Mutex` is
    /// non-Copyable and this domain is a struct.
    let instructionsFor = InstructionsLog()

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        instructionsFor.record(tier: tier, isConversation: isConversation)
        return "Answer from the tools."
            + (isConversation ? " You may use every tool." : "")
            + (answerLanguage.map { " Answer in \($0)." } ?? "")
    }

    var promptPrefix: String { "PREFIX\n" }

    func promptLines(question: String, overview: AskOverview) async -> [String] {
        promptLineReads.record()
        await promptLinesHold.pass()
        return ["You have \(overview.total) records."]
    }

    func scopeLine(for scope: String) -> String? { scopeLines[scope] }

    var searchPlanInstructions: String { "Choose a query." }

    /// Records each search's `isConversation`. A class, for the reason
    /// `instructionsFor` is one.
    let searches = SearchLog()

    func search(_ arguments: FakeSearchArguments, context: AskToolContext<FakeRow>) async throws -> String {
        searches.record(isConversation: context.isConversation)
        if let searchError { throw searchError }
        await context.collector.noteToolCall(.searching(scope: "records"))
        await context.collector.record(rows: searchRows)
        await context.collector.noteToolFinished()
        return searchRows.map(\.displayTitle).joined(separator: "\n")
    }

    func starters(overview: AskOverview, window: Int) -> [AskStarter] {
        [AskStarter(text: "What do I own?")]
    }

    func referent(from answer: AskAnswer<FakeRow>) -> [String] {
        referentHook.run()
        return answer.tiles.isEmpty ? answer.mentioned.map(\.displayTitle) : answer.tiles.map(\.displayTitle)
    }

    func deterministicAnswer(for question: String) async -> AskAnswer<FakeRow>? {
        await deterministicHold.pass()
        return deterministic
    }

    func basis(for answer: AskAnswer<FakeRow>) -> String? { basisText }

    var rerollableKinds: Set<AskQuestionKind> { rerollKinds }

    func refine(
        _ answer: AskAnswer<FakeRow>,
        question: String,
        tier: AskTier,
        session: AskSessionBox
    ) async throws -> AskAnswer<FakeRow>? {
        refinedOn.record(session.session)
        if refineAsksTheModel {
            // What comes back is not the point, and the fake session answers
            // nothing: only that the pass asked, on the session it was handed.
            _ = try? await session.session.respond(
                AskReply.self, images: [], prompt: "Revise.", temperature: 0.4, reasoningLevel: nil
            )
        }
        if let refinementDelay { try await Task.sleep(for: refinementDelay) }
        if refinementThrows { throw AskError.couldNotAnswer }
        return refinement
    }
}

/// A domain whose tools read no rows, written as a host without rows writes
/// one: it names neither associated type, and leaves `overview()` and
/// `search(_:context:)` to their defaults. It has no tools, so a turn grounds
/// only through a script's `toolCallsAfter`.
nonisolated struct RowlessDomain: AskDomain {
    var nothingToAskCopy: String?
    var firstScreenPolicy: AskFirstScreenPolicy = .openSubject
    var grounding: AskGroundingPolicy = .retrieval

    var brand: AskBrand {
        AskBrand(
            title: "Ask Rowless", appDirectory: "AskKitTests",
            logSubsystem: "AskKit.tests", help: "help",
            firstScreenHeadline: "headline", firstScreenSentence: "sentence",
            nothingToAskCopy: nothingToAskCopy, disclosureSentence: "disclosure",
            scopeCaveat: "caveat"
        )
    }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
}

// MARK: - Log sink

nonisolated final class FakeLogSink: AskLogSink, @unchecked Sendable {
    let turns = Mutex<[AskTurnStats]>([])
    let routings = Mutex<[String]>([])
    let discards = Mutex<[AskDiscard]>([])
    let feedbacks = Mutex<[AskFeedback]>([])

    func turn(_ stats: AskTurnStats) { turns.withLock { $0.append(stats) } }
    func routing(_ line: String) { routings.withLock { $0.append(line) } }
    func discard(_ discard: AskDiscard) { discards.withLock { $0.append(discard) } }
    func feedback(_ feedback: AskFeedback) { feedbacks.withLock { $0.append(feedback) } }
}

// MARK: - Convenience

extension AskTierState {
    static func serving(_ tier: AskTier) -> AskTierState {
        AskTierState(tier: tier, speaksLanguage: true)
    }

    static func down(_ tier: AskTier, _ why: AskUnavailability) -> AskTierState {
        AskTierState(tier: tier, speaksLanguage: true, unavailability: why)
    }
}

extension AskReplySnapshot {
    static func answering(
        _ text: String,
        kind: AskQuestionKind? = nil,
        tiles: [String]? = nil,
        showsEveryMatch: Bool? = nil,
        followUps: [String]? = nil
    ) -> AskReplySnapshot {
        AskReplySnapshot(
            answer: text, questionKind: kind?.rawValue, showsEveryMatch: showsEveryMatch,
            tiles: tiles, followUps: followUps
        )
    }
}

/// Drain a turn's events, keeping everything for assertion.
struct TurnRecording: Sendable {
    var events: [AskTurnEvent<FakeRow>] = []
    var error: (any Error)?

    var tiers: [AskTier] {
        events.compactMap { if case .tier(let tier) = $0 { return tier } else { return nil } }
    }
    var partials: [String] {
        events.compactMap { if case .partial(let text) = $0 { return text } else { return nil } }
    }
    var restarts: [AskTier] {
        events.compactMap { if case .restarted(let tier) = $0 { return tier } else { return nil } }
    }
    var activities: [AskActivity] {
        events.compactMap { if case .activity(let value) = $0 { return value } else { return nil } }
    }
    /// Everything the wait row was told, in order — the phrases *and* the
    /// clears. `activities` alone cannot see a phrase that was taken straight
    /// back, which is exactly the bug the ordering rule is about.
    var waitTrail: [AskTurnEvent<FakeRow>] {
        events.filter {
            switch $0 {
            case .activity, .activityEnded: return true
            default: return false
            }
        }
    }
    var rowsReadEvents: [[FakeRow]] {
        events.compactMap { if case .rowsRead(let rows) = $0 { return rows } else { return nil } }
    }
    var answer: AskAnswer<FakeRow>? {
        events.compactMap { if case .answer(let value) = $0 { return value } else { return nil } }.last
    }
    var summarizedCount: Int {
        events.filter { if case .summarized = $0 { return true } else { return false } }.count
    }
    /// What the stream said once it had given its first answer.
    var afterAnswer: [AskTurnEvent<FakeRow>] {
        guard let first = events.firstIndex(where: { if case .answer = $0 { return true } else { return false } })
        else { return [] }
        return Array(events[(first + 1)...])
    }
    var askError: AskError? { error as? AskError }
}

func record(_ stream: AsyncThrowingStream<AskTurnEvent<FakeRow>, any Error>) async -> TurnRecording {
    var recording = TurnRecording()
    do {
        for try await event in stream { recording.events.append(event) }
    } catch {
        recording.error = error
    }
    return recording
}

// MARK: - Waiting

/// How long `yieldUntil` waits before it gives up. Long, because only a failing
/// test ever waits it out.
nonisolated let testWaitDeadline: Duration = .seconds(15)

/// A clock a test moves by hand: the engine ages its warm session by it.
nonisolated final class TestClock: Sendable {
    private let instant = Mutex(ContinuousClock().now)

    var now: ContinuousClock.Instant { instant.withLock { $0 } }

    func advance(by duration: Duration) {
        instant.withLock { $0 = $0.advanced(by: duration) }
    }
}

/// Yield until `condition` holds — a generation has started, a warm is
/// being held — or give up. The caller still asserts: this only stops waiting.
///
/// **Yielding, not sleeping,** because the test acts the moment the condition
/// holds. **Bounded and cancellable,** because a bare
/// `while … { await Task.yield() }` whose condition never comes true hangs the
/// run: the suite's time limit cancels the test, and a loop that never looks
/// at cancellation spins on past it, the process with it.
nonisolated func yieldUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock().now + testWaitDeadline
    while !condition(), !Task.isCancelled, ContinuousClock().now < deadline {
        await Task.yield()
    }
}

#endif
