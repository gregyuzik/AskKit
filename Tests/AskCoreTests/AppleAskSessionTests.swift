import Foundation
import Testing

@testable import AskCore

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels
import Synchronization

/// Whether this process is a simulator's on a Mac that is itself a virtual
/// machine (`kern.hv_vmm_present`, which a simulator reads from its Mac).
nonisolated private let onAVirtualizedSimulator: Bool = {
    #if targetEnvironment(simulator)
    var present: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    #else
    return false
    #endif
}()

/// What `AppleAskSession` says a response cost, over a real
/// `LanguageModelSession` driven by a scripted model.
///
/// No Apple model runs: SDK 27's `LanguageModel` protocol takes a provider, and
/// this one answers every request with the same reply and whatever counts the
/// test scripts for it. So the arithmetic is pinned, not a model — and
/// `usage()` is the newest response's counts, never the SDK's own
/// `session.usage`, which is a running total.
///
/// Not on a simulator inside a virtual machine, as on a CI runner: there each
/// stream through `LanguageModelSession` holds for about 35 seconds, and the
/// main actor with it, so every test running beside it overshoots its deadline.
/// The same tests run under `swift test` on a virtual Mac, and on a simulator
/// on a real one.
@Suite(
    .timeLimit(.minutes(1)),
    .disabled(if: onAVirtualizedSimulator, "FoundationModels stalls a scripted stream on a virtualized simulator")
)
struct AppleAskSessionTests {

    private func makeSession(_ responses: [ScriptedResponse?]) -> AppleAskSession {
        let model = ScriptedModel(responses: responses)
        return AppleAskSession(
            session: LanguageModelSession(model: model, instructions: "Answer."),
            contextSize: 4096
        ) { instructions in
            LanguageModelSession(model: model, instructions: instructions)
        }
    }

    private func drain(_ session: AppleAskSession, _ prompt: String) async throws {
        for try await _ in session.stream(
            prompt: prompt, temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: true
        ) {}
    }

    @Test func callsMadeAtOnceAreCountedOneByOne() async {
        // One transcript entry holds every call the model made at once.
        let model = ScriptedModel(responses: [])
        let call = { (id: String) in
            Transcript.ToolCall(id: id, toolName: "search", arguments: GeneratedContent(properties: ["query": "vinyl"]))
        }
        let transcript = Transcript(entries: [
            .toolCalls(Transcript.ToolCalls([call("a"), call("b")])),
            .toolCalls(Transcript.ToolCalls([call("c")]))
        ])
        let session = AppleAskSession(
            session: LanguageModelSession(model: model, transcript: transcript),
            contextSize: 4096
        ) { instructions in
            LanguageModelSession(model: model, instructions: instructions)
        }
        #expect(await session.toolCallCount() == 3)
    }

    @Test func aSessionThatHasAnsweredNothingHasNoReading() async {
        let session = makeSession([ScriptedResponse(input: 100, output: 5)])
        #expect(await session.usage() == nil)
    }

    @Test func theReadingIsTheNewestResponsesNotTheSessionsTotal() async throws {
        // Each request's input is the whole transcript so far, so the SDK's
        // running total reads 600 here, for a thread the third request sent
        // as 300. Set against the window by `shouldRollOver`, that total would
        // roll a conversation over long before its window filled.
        let session = makeSession([
            ScriptedResponse(input: 100, cached: 10, output: 5),
            ScriptedResponse(input: 200, cached: 90, output: 6),
            ScriptedResponse(input: 300, cached: 190, output: 7)
        ])
        for prompt in ["one", "two", "three"] {
            try await drain(session, prompt)
        }
        #expect(await session.usage() == AskUsage(
            inputTokens: 300, cachedTokens: 190, outputTokens: 7, reasoningTokens: 0
        ))
    }

    @Test func aRefinePassIsTheNewestResponse() async throws {
        // `refine` answers on the turn's own session, so the next question is
        // sent everything it added.
        let session = makeSession([
            ScriptedResponse(input: 100, output: 5),
            ScriptedResponse(input: 180, output: 9)
        ])
        try await drain(session, "one")
        _ = try await session.respond(
            AskReply.self, images: [], prompt: "Refine.", temperature: 0, reasoningLevel: nil
        )
        #expect(await session.usage()?.inputTokens == 180)
        #expect(await session.usage()?.outputTokens == 9)
    }

    @Test func aResponseThatNeverReportsItsInputLeavesTheLastReading() async throws {
        // Without the provider's counts the SDK has only counted the text: an
        // input of zero, which `shouldRollOver` would read as an empty window.
        let session = makeSession([ScriptedResponse(input: 100, output: 5), nil])
        try await drain(session, "one")
        try await drain(session, "two")
        #expect(await session.usage() == AskUsage(
            inputTokens: 100, cachedTokens: 0, outputTokens: 5, reasoningTokens: 0
        ))
    }

    // MARK: - Response caps

    private func makeCappedSession(
        answerCap: Int?, planCap: Int?, recorder: OptionsRecorder
    ) -> AppleAskSession {
        let model = ScriptedModel(responses: [ScriptedResponse(input: 100, output: 5)], recorder: recorder)
        return AppleAskSession(
            session: LanguageModelSession(model: model, instructions: "Answer."),
            contextSize: 8192,
            answerCap: answerCap,
            planCap: planCap
        ) { instructions in
            LanguageModelSession(model: model, instructions: instructions)
        }
    }

    @Test func aCappedSessionSendsItsCapWithEveryAnswer() async throws {
        let recorder = OptionsRecorder()
        let session = makeCappedSession(answerCap: 1_024, planCap: 256, recorder: recorder)
        try await drain(session, "one")
        _ = try await session.respond(
            AskReply.self, images: [], prompt: "Refine.", temperature: 0, reasoningLevel: nil
        )
        #expect(recorder.caps == [1_024, 1_024])
    }

    @Test func thePlannerTakesItsOwnCap() async throws {
        let recorder = OptionsRecorder()
        let session = makeCappedSession(answerCap: 1_024, planCap: 256, recorder: recorder)
        _ = try await session.plan(AskReply.self, instructions: "Plan.", prompt: "one")
        #expect(recorder.caps == [256])
    }

    // MARK: - Prewarm

    /// A domain with no prefix of its own warms the model and caches no
    /// prompt, rather than sending an empty prompt as one.
    @Test func aWarmWithNoPrefixSendsNoPrompt() async throws {
        let prewarms = PrewarmRecorder()
        let model = ScriptedModel(responses: [], prewarms: prewarms)
        let session = AppleAskSession(
            session: LanguageModelSession(model: model, instructions: "Answer."),
            contextSize: 4096
        ) { instructions in
            LanguageModelSession(model: model, instructions: instructions)
        }
        await session.prewarm(promptPrefix: "")
        await yieldUntil { prewarms.transcripts.count == 1 }
        await session.prewarm(promptPrefix: "Rows:")
        await yieldUntil { prewarms.transcripts.count == 2 }
        let transcripts = prewarms.transcripts
        try #require(transcripts.count == 2)
        #expect(Self.prompts(in: transcripts[0]).isEmpty)
        #expect(Self.prompts(in: transcripts[1]).count == 1)
    }

    private static func prompts(in transcript: Transcript) -> [Transcript.Prompt] {
        transcript.compactMap { entry in
            if case .prompt(let prompt) = entry { prompt } else { nil }
        }
    }

    @Test func anUncappedSessionLeavesTheModelItsWindow() async throws {
        // Private Cloud Compute's sessions are built without caps: its 32K
        // budgets are its own.
        let recorder = OptionsRecorder()
        let session = makeCappedSession(answerCap: nil, planCap: nil, recorder: recorder)
        try await drain(session, "one")
        _ = try await session.plan(AskReply.self, instructions: "Plan.", prompt: "one")
        #expect(recorder.caps == [nil, nil])
    }

    // MARK: - Reply shapes

    /// **A domain that names no shape still asks for `AskReply`**: the stream
    /// with no shape and the full shape send its schema, as every stream did
    /// before there were shapes. The prose shape sends `AskProseReply`'s, and
    /// its snapshots carry its two fields and nothing else.
    @Test func eachShapeAsksForItsOwnSchema() async throws {
        let schemas = SchemaRecorder()
        let model = ScriptedModel(responses: [], schemas: schemas)
        let session = AppleAskSession(
            session: LanguageModelSession(model: model, instructions: "Answer."),
            contextSize: 4096
        ) { instructions in
            LanguageModelSession(model: model, instructions: instructions)
        }
        try await drain(session, "one")
        var full: AskReplySnapshot?
        for try await snapshot in session.stream(
            prompt: "two", images: [], temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: false, shape: .full
        ) {
            full = snapshot
        }
        var prose: AskReplySnapshot?
        for try await snapshot in session.stream(
            prompt: "three", images: [], temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: false, shape: .prose
        ) {
            prose = snapshot
        }
        let reply = try SchemaRecorder.json(AskReply.generationSchema)
        let proseReply = try SchemaRecorder.json(AskProseReply.generationSchema)
        #expect(schemas.recorded == [reply, reply, proseReply])
        #expect(full?.questionKind == "lookup")
        #expect(full?.tiles == [])
        #expect(prose == AskReplySnapshot(answer: "Scripted.", followUps: ["Which is older?", "What else?"]))
    }

    // MARK: - The generation gate waits for the generation

    /// A session whose every request fails at once, and whose failure hook
    /// holds the task that runs the generation at `unwinding`: a generation
    /// still running after its reader let it go.
    private func makeUnwindingSession(_ unwinding: GateTestHold) -> AppleAskSession {
        let model = FailingModel()
        return AppleAskSession(
            session: LanguageModelSession(model: model, instructions: "Answer."),
            contextSize: 4096,
            noteFailure: { _ in await unwinding.hold() },
            makePlanner: { instructions in LanguageModelSession(model: model, instructions: instructions) }
        )
    }

    private func spin(_ what: String, until condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<4_000 {
            if await condition() { return }
            await Task.yield()
            try await Task.sleep(for: .microseconds(500))
        }
        Issue.record("timed out waiting for \(what)")
    }

    /// A turn stopped mid-stream: the engine's loop ends the moment its task
    /// is cancelled, and the task running `streamResponse` goes on. The next
    /// on-device generation waits for that task, not for the loop.
    @Test func aStoppedStreamHoldsTheGenerationGateUntilItsGenerationReturns() async throws {
        let gate = AskGenerationGate()
        let seam = AppleModelSeam(status: AskModelStatus(), privateCloudCompute: .undeclared, gate: gate)
        let unwinding = GateTestHold()
        let session = makeUnwindingSession(unwinding)
        let readerStopped = Mutex(false)
        let turn = Task {
            try await seam.withGeneration(onDevice: true) {
                for try await _ in session.stream(
                    prompt: "one", temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: true
                ) {}
                readerStopped.withLock { $0 = true }
            }
        }
        try await spin("the generation to fail") { unwinding.hasArrived }
        // Whether the generation had returned when the next one went in.
        let entered = Mutex<[Bool]>([])
        let next = Task {
            try await seam.withGeneration(onDevice: true) { entered.withLock { $0.append(unwinding.hasLeft) } }
        }
        try await spin("the next generation to queue") { await gate.queueDepth == 1 }
        turn.cancel()
        try await spin("the stopped turn's reader to stop") { readerStopped.withLock { $0 } }
        // Room for a release that must not happen.
        try await Task.sleep(for: .milliseconds(200))
        #expect(entered.withLock { $0 }.isEmpty)
        unwinding.release()
        try await next.value
        _ = await turn.result
        #expect(entered.withLock { $0 } == [true])
    }

    /// The refine pass's streams go through `AskGatedSession`, whose own task
    /// holds the generation gate: a pass abandoned at the turn's deadline
    /// holds it until the generation underneath has returned.
    @Test func anAbandonedRefinePassHoldsTheGenerationGateUntilItsGenerationReturns() async throws {
        let gate = AskGenerationGate()
        let seam = AppleModelSeam(status: AskModelStatus(), privateCloudCompute: .undeclared, gate: gate)
        let unwinding = GateTestHold()
        let pass = AskGatedSession(base: makeUnwindingSession(unwinding), seam: seam, onDevice: true) {}
        let reader = Task {
            for try await _ in pass.stream(
                prompt: "Refine.", temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: false
            ) {}
        }
        try await spin("the pass's generation to fail") { unwinding.hasArrived }
        let entered = Mutex<[Bool]>([])
        let next = Task {
            try await seam.withGeneration(onDevice: true) { entered.withLock { $0.append(unwinding.hasLeft) } }
        }
        try await spin("the next generation to queue") { await gate.queueDepth == 1 }
        reader.cancel()
        _ = await reader.result
        try await Task.sleep(for: .milliseconds(200))
        #expect(entered.withLock { $0 }.isEmpty)
        unwinding.release()
        try await next.value
        #expect(entered.withLock { $0 } == [true])
    }

    /// Private Cloud Compute contends for none of the on-device runtime, so a
    /// stopped generation there holds nothing, and its caller returns at once.
    @Test func aStoppedPrivateCloudStreamWaitsForNothing() async throws {
        let seam = AppleModelSeam(
            status: AskModelStatus(), privateCloudCompute: .undeclared, gate: AskGenerationGate()
        )
        let unwinding = GateTestHold()
        let session = makeUnwindingSession(unwinding)
        let turn = Task {
            try await seam.withGeneration(onDevice: false) {
                for try await _ in session.stream(
                    prompt: "one", temperature: 0, reasoningLevel: nil, includeSchemaInPrompt: true
                ) {}
            }
        }
        try await spin("the generation to fail") { unwinding.hasArrived }
        turn.cancel()
        _ = await turn.result
        #expect(!unwinding.hasLeft)
        unwinding.release()
    }
}

// MARK: - A model that fails

/// Fails every request at once.
nonisolated private struct FailingModel: LanguageModel {
    typealias Executor = FailingExecutor

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .toolCalling])
    }

    var executorConfiguration: FailingExecutor.Configuration { .init() }
}

nonisolated private final class FailingExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {}
    typealias Model = FailingModel

    struct Failure: Error {}

    init(configuration: Configuration) throws {}

    func prewarm(model: FailingModel, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: FailingModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        throw Failure()
    }
}

// MARK: - A scripted model

/// Every transcript a prewarm handed the model, in order.
nonisolated final class PrewarmRecorder: Sendable {
    private let state = Mutex<[Transcript]>([])
    var transcripts: [Transcript] { state.withLock { $0 } }
    func record(_ transcript: Transcript) { state.withLock { $0.append(transcript) } }
}

/// Every request's response schema, as sorted JSON, in order: nil for a
/// request that asked for none.
nonisolated final class SchemaRecorder: Sendable {
    private let state = Mutex<[Data?]>([])
    var recorded: [Data?] { state.withLock { $0 } }
    func record(_ schema: GenerationSchema?) {
        let json = schema.flatMap { try? Self.json($0) }
        state.withLock { $0.append(json) }
    }

    static func json(_ schema: GenerationSchema) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(schema)
    }
}

/// Every request's `maximumResponseTokens`, in order.
nonisolated final class OptionsRecorder: Sendable {
    private let state = Mutex<[Int?]>([])
    var caps: [Int?] { state.withLock { $0 } }
    func record(_ cap: Int?) { state.withLock { $0.append(cap) } }
}

/// The counts one request reports: its input, the whole transcript it was
/// sent, and its output.
///
/// Sent after the text. When makes no difference here: with a provider, the SDK
/// hands the stream nothing until `respond` returns (measured on SDK 27), so a
/// scripted answer cannot be cut short partway.
nonisolated struct ScriptedResponse: Hashable, Sendable {
    var input: Int
    var cached = 0
    var output: Int
}

/// Answers request *n* of a session with `responses[n - 1]`; nil there, or a
/// request past the end, is the reply with no counts.
nonisolated struct ScriptedModel: LanguageModel {
    typealias Executor = ScriptedExecutor

    var responses: [ScriptedResponse?]
    /// Where each request's generation options are noted, when a test asks.
    var recorder: OptionsRecorder?
    /// Where each prewarm's transcript is noted, when a test asks.
    var prewarms: PrewarmRecorder?
    /// Where each request's response schema is noted, when a test asks.
    var schemas: SchemaRecorder?

    init(
        responses: [ScriptedResponse?],
        recorder: OptionsRecorder? = nil,
        prewarms: PrewarmRecorder? = nil,
        schemas: SchemaRecorder? = nil
    ) {
        self.responses = responses
        self.recorder = recorder
        self.prewarms = prewarms
        self.schemas = schemas
    }

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .toolCalling])
    }

    var executorConfiguration: ScriptedExecutor.Configuration { .init() }
}

nonisolated final class ScriptedExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {}
    typealias Model = ScriptedModel

    static let reply = #"{"answer":"Scripted.","questionKind":"lookup","showsEveryMatch":false,"tiles":[],"followUps":[]}"#
    /// The reply to a request for `AskProseReply`, whose schema allows no
    /// field it doesn't have.
    static let proseReply = #"{"answer":"Scripted.","followUps":["Which is older?","What else?"]}"#

    init(configuration: Configuration) throws {}

    func prewarm(model: ScriptedModel, transcript: Transcript) {
        model.prewarms?.record(transcript)
    }

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        model.recorder?.record(request.generationOptions.maximumResponseTokens)
        model.schemas?.record(request.schema)
        let reply = Self.asksForProse(request.schema) ? Self.proseReply : Self.reply
        // Which request this is, from the session's own transcript rather than
        // a counter: the suite runs in parallel.
        let index = request.transcript.reduce(into: -1) { index, entry in
            if case .prompt = entry { index += 1 }
        }
        await channel.send(.response(action: .appendText(String(reply.prefix(20)), tokenCount: 3)))
        await channel.send(.response(action: .appendText(String(reply.dropFirst(20)), tokenCount: 3)))
        guard model.responses.indices.contains(index), let response = model.responses[index] else { return }
        await channel.send(.response(action: .updateUsage(
            input: .init(totalTokenCount: response.input, cachedTokenCount: response.cached),
            output: .init(totalTokenCount: response.output, reasoningTokenCount: 0)
        )))
    }

    /// Whether `schema` is `AskProseReply`'s, by the title it carries.
    private static func asksForProse(_ schema: GenerationSchema?) -> Bool {
        guard let schema, let data = try? JSONEncoder().encode(schema),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["title"] as? String == "AskProseReply"
    }
}

#endif
