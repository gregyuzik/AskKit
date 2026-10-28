#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels
import Testing

@testable import AskCore

/// Raw SDK error to `AskError`.
///
/// Every payload type in SDK 27 has a public initialiser, so every arm here is
/// a constructed error, not a mock: `contextSizeExceeded` really is
/// `LanguageModelError`, with no real session made to throw it.
@Suite(.timeLimit(.minutes(1))) struct AskTriageTests {

    private struct SomethingElse: Error {}

    // MARK: - The distinctions that cost something to get wrong

    @Test func anOverflowIsContentNotTransport() {
        // Cooling the tier over this would punish it for the transcript's
        // size, and hand the turn to a window four times smaller.
        let error = LanguageModelError.contextSizeExceeded(
            .init(contextSize: 8192, tokenCount: 9001, debugDescription: "over")
        )
        #expect(AskTriage.askError(from: error, tier: .privateCloud) == .contextTooLarge)
        #expect(AskTriage.askError(from: error, tier: .onDevice) == .contextTooLarge)
        // And it is not an outage, so the turn fails where it stands rather than
        // handing down to a window four times smaller.
        #expect(!askIsTierOutage(.contextTooLarge))
    }

    @Test func concurrentRequestsIsOurBugNotTheReaders() {
        // It means the engine let two generations onto one session. The reader
        // gets the could-not-answer line, never a word about concurrency.
        let error = LanguageModelSession.Error.concurrentRequests
        #expect(AskTriage.askError(from: error, tier: .onDevice) == .couldNotAnswer)
    }

    @Test func theInstantMinusOneIsThePrivateCloudContextGate() {
        // What a process outside Private Cloud Compute's context gate gets,
        // in milliseconds. Never raw text.
        let gate = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        #expect(AskTriage.isPrivateCloudContextGate(gate))
        #expect(AskTriage.askError(from: gate, tier: .privateCloud) == .privateCloudUnreachable)
        // Some other -1 is not it.
        #expect(!AskTriage.isPrivateCloudContextGate(NSError(domain: "com.example", code: -1)))
        // Nor is a different code in the right domain.
        #expect(!AskTriage.isPrivateCloudContextGate(
            NSError(domain: "FoundationModels.LanguageModelError", code: 42)
        ))
    }

    // MARK: - Verdicts on the question

    @Test func aGuardrailVerdictIsFinal() {
        let guardrail = LanguageModelError.guardrailViolation(.init(debugDescription: "blocked"))
        let refusal = LanguageModelError.refusal(
            .init(explanation: "no", debugDescription: "refused")
        )
        #expect(AskTriage.askError(from: guardrail, tier: .privateCloud) == .refused)
        #expect(AskTriage.askError(from: refusal, tier: .onDevice) == .refused)
        #expect(!AskError.refused.isRetryable)
        #expect(!askIsTierOutage(.refused))
    }

    @Test func anUnsupportedLanguageIsAnUnavailability() {
        let error = LanguageModelError.unsupportedLanguageOrLocale(
            .init(languageCode: .hebrew, debugDescription: "he")
        )
        #expect(
            AskTriage.askError(from: error, tier: .privateCloud)
                == .modelUnavailable(.languageNotSupported)
        )
    }

    @Test func aTimeoutIsRetryable() {
        let error = LanguageModelError.timeout(.init(debugDescription: "slow"))
        let ask = AskTriage.askError(from: error, tier: .onDevice)
        #expect(ask == .couldNotAnswer)
        #expect(ask.isRetryable)
    }

    /// On Private Cloud Compute a timeout is the tier not answering, as a
    /// timed-out connection to it is (`NSURLErrorTimedOut`): an outage the
    /// turn is handed down from and the tier cooled for, so a tier that
    /// keeps timing out doesn't fail every turn while the on-device model
    /// could answer (house rule 1).
    @Test func aTimeoutOnPrivateCloudComputeIsAnOutage() {
        let error = LanguageModelError.timeout(.init(debugDescription: "slow"))
        let ask = AskTriage.askError(from: error, tier: .privateCloud)
        #expect(ask == .privateCloudUnreachable)
        #expect(ask == AskTriage.askError(from: URLError(.timedOut), tier: .privateCloud))
        #expect(askIsTierOutage(ask))
        #expect(ask.isRetryable)
    }

    // MARK: - Private Cloud Compute's own family

    @Test func networkFailureAndServiceUnavailableBothCoolTheCloud() {
        let network = PrivateCloudComputeLanguageModel.Error.networkFailure(
            .init(debugDescription: "no route")
        )
        let unavailable = PrivateCloudComputeLanguageModel.Error.serviceUnavailable(
            .init(debugDescription: "down")
        )
        #expect(AskTriage.askError(from: network, tier: .privateCloud) == .privateCloudUnreachable)
        #expect(AskTriage.askError(from: unavailable, tier: .privateCloud) == .privateCloudUnreachable)
        // And both hand the turn down.
        #expect(askIsTierOutage(.privateCloudUnreachable))
    }

    @Test func quotaCarriesItsResetDateThrough() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let error = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: reset, debugDescription: "spent")
        )
        #expect(AskTriage.askError(from: error, tier: .privateCloud) == .quotaReached(resetDate: reset))
    }

    @Test func aSpentQuotaSaysWhenItComesBack() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let spent = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: reset, debugDescription: "spent")
        )
        #expect(AskTriage.retryAfter(from: spent) == AskRetryAfter(date: reset, isQuota: true))
        // No date is still a quota: the seam falls back to the reset date the
        // model's quota usage reports.
        let undated = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: nil, debugDescription: "spent")
        )
        #expect(AskTriage.retryAfter(from: undated) == AskRetryAfter(date: nil, isQuota: true))
    }

    @Test func aRateLimitSaysWhenItLiftsOnlyWhenItKnows() {
        let reset = Date(timeIntervalSince1970: 1_800_000_060)
        let dated = LanguageModelError.rateLimited(.init(resetDate: reset, debugDescription: "slow down"))
        #expect(AskTriage.retryAfter(from: dated) == AskRetryAfter(date: reset, isQuota: false))
        // Without a date it is an ordinary outage, and the minute's cooldown
        // is what the seam applies.
        let undated = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "slow down"))
        #expect(AskTriage.retryAfter(from: undated) == nil)
    }

    @Test func nothingElseCarriesARetryDate() {
        #expect(AskTriage.retryAfter(from: PrivateCloudComputeLanguageModel.Error.networkFailure(
            .init(debugDescription: "no route")
        )) == nil)
        #expect(AskTriage.retryAfter(from: AskError.privateCloudUnreachable) == nil)
        #expect(AskTriage.retryAfter(from: SomethingElse()) == nil)
    }

    @Test func rateLimitedIsAnOutageOnTheCloudAndAFaultOnTheDevice() {
        // The tier saying "not now" — the one below is unaffected, so on Private
        // Cloud Compute it hands down. On device there is nothing below.
        let error = LanguageModelError.rateLimited(
            .init(resetDate: nil, debugDescription: "slow down")
        )
        #expect(AskTriage.askError(from: error, tier: .privateCloud) == .privateCloudUnreachable)
        #expect(AskTriage.askError(from: error, tier: .onDevice) == .model(tag: "rateLimited"))
    }

    // MARK: - Transport and the fall-through

    @Test func urlLevelOfflineIsRecognised() {
        for code in [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorTimedOut,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff
        ] {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            #expect(AskTriage.isOffline(error))
            #expect(AskTriage.askError(from: error, tier: .privateCloud) == .privateCloudUnreachable)
        }
        // A URL error that is not a connectivity one, and a non-URL domain.
        #expect(!AskTriage.isOffline(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)))
        #expect(!AskTriage.isOffline(NSError(domain: NSCocoaErrorDomain, code: -1009)))
    }

    /// A raw DNS failure on Private Cloud Compute is the tier unreachable,
    /// handed down and cooled, not an unclassified fault, typed or bridged.
    @Test func aHostThatCantBeFoundIsOffline() {
        #expect(AskTriage.askError(from: URLError(.cannotFindHost), tier: .privateCloud) == .privateCloudUnreachable)
        #expect(AskTriage.askError(from: URLError(.dnsLookupFailed), tier: .onDevice) == .model(tag: "offline"))
    }

    /// A struct that bridges to an `NSError` with a code of its own is tagged
    /// by its domain and code, so the log says which failure it was.
    @Test func aBridgedStructErrorKeepsItsDomainAndCode() {
        #expect(AskTriage.tag(for: URLError(.badServerResponse)) == "NSURLErrorDomain#\(NSURLErrorBadServerResponse)")
        #expect(AskTriage.tag(for: CocoaError(.fileReadNoSuchFile)) == "NSCocoaErrorDomain#\(CocoaError.fileReadNoSuchFile.rawValue)")
        #expect(
            AskTriage.askError(from: URLError(.badServerResponse), tier: .onDevice)
                == .model(tag: "NSURLErrorDomain#\(NSURLErrorBadServerResponse)")
        )
    }

    @Test func anythingElseKeepsItsTypeNameAndNothingElse() {
        let ask = AskTriage.askError(from: SomethingElse(), tier: .onDevice)
        #expect(ask == .model(tag: "SomethingElse"))
    }

    // MARK: - The tag never leaks a message

    @Test func theTagIsATypeNameNotTheSdksProse() {
        // The SDK's message can quote model output, so it must never travel with
        // the error. Everything the log gets is the shape of the failure.
        let wordy = NSError(
            domain: "Test", code: -7,
            userInfo: [NSLocalizedDescriptionKey: "The model said something about the reader's data"]
        )
        let tag = AskTriage.tag(for: wordy)
        #expect(tag == "Test#-7")
        #expect(!tag.contains("reader"))
        #expect(tag.count <= 60)

        let payloaded = LanguageModelError.guardrailViolation(
            .init(debugDescription: "a long explanation of exactly what was blocked")
        )
        #expect(AskTriage.tag(for: payloaded) == "guardrailViolation")
        #expect(!AskTriage.tag(for: payloaded).contains("blocked"))
    }

    @Test func aCaseWithNoPayloadIsTaggedByItsName() {
        // Such a case has no child for reflection to label. Read as its type,
        // `concurrentRequests` logged as "Error", and two of AskKit's own
        // failures as the same "AskError".
        #expect(AskTriage.tag(for: LanguageModelSession.Error.concurrentRequests) == "concurrentRequests")
        #expect(
            AskTriage.tag(for: LanguageModelSession.Error.transcriptMutationWhileResponding)
                == "transcriptMutationWhileResponding"
        )
        #expect(AskTriage.tag(for: AskError.couldNotAnswer) == "couldNotAnswer")
        #expect(AskTriage.tag(for: AskError.ungrounded) == "ungrounded")
        #expect(
            AskTriage.askError(from: LanguageModelSession.Error.transcriptMutationWhileResponding, tier: .onDevice)
                == .model(tag: "transcriptMutationWhileResponding")
        )
    }

    @Test func aCaseThatDescribesItselfIsNeverDescribed() {
        // The SDK's own errors describe themselves in prose, which is why the
        // tag is read by reflection. A case with no payload of a type that
        // describes itself is read as its domain and code, never its words.
        let tag = AskTriage.tag(for: TriageWordyError.blocked)
        #expect(!tag.contains("reader"))
        #expect(tag == "\((TriageWordyError.blocked as NSError).domain)#1")
        #expect(tag.count <= 60)
    }

    @Test func aCaseWithAPayloadIsTaggedByItsNameAlone() {
        #expect(AskTriage.tag(for: AskError.model(tag: "the reader's words")) == "model")
        #expect(AskTriage.tag(for: AskError.quotaReached(resetDate: nil)) == "quotaReached")
        #expect(AskTriage.tag(for: TriageWordyError.quoted("the reader's words")) == "quoted")
    }

    @Test func aToolsFailureIsTaggedWithWhatTheToolThrew() {
        // A domain tool that fails every turn logged only "ToolCallError".
        let wordy = NSError(
            domain: "Shelf", code: 7, userInfo: [NSLocalizedDescriptionKey: "the reader's own notes"]
        )
        let failed = LanguageModelSession.ToolCallError(tool: TriageShelfTool(), underlyingError: wordy)
        #expect(AskTriage.tag(for: failed) == "ToolCallError(Shelf#7)")
        #expect(AskTriage.askError(from: failed, tier: .onDevice) == .model(tag: "ToolCallError(Shelf#7)"))
        let plain = LanguageModelSession.ToolCallError(
            tool: TriageShelfTool(), underlyingError: AskError.couldNotAnswer
        )
        #expect(AskTriage.tag(for: plain) == "ToolCallError(couldNotAnswer)")
        // A long tag inside is cut short, and the parenthesis still closes.
        let long = LanguageModelSession.ToolCallError(
            tool: TriageShelfTool(), underlyingError: NSError(domain: String(repeating: "d", count: 80), code: 1)
        )
        let tag = AskTriage.tag(for: long)
        #expect(tag.count == 60)
        #expect(tag.hasPrefix("ToolCallError(") && tag.hasSuffix(")"))
    }

    /// An error that is already an `AskError` reads as itself, and so does
    /// one a tool threw: the domain chose it, as the engine passes on one
    /// the domain's search throws. A host triaging its own sessions' errors
    /// gets what the engine would have shown.
    @Test func anAskErrorReadsAsItselfThrownByATool() {
        #expect(AskTriage.askError(from: AskError.refused, tier: .onDevice) == .refused)
        #expect(AskTriage.askError(from: AskError.quotaReached(resetDate: nil), tier: .privateCloud) == .quotaReached(resetDate: nil))
        let thrown = LanguageModelSession.ToolCallError(tool: TriageShelfTool(), underlyingError: AskError.photosNotSupported)
        #expect(AskTriage.askError(from: thrown, tier: .privateCloud) == .photosNotSupported)
        // Anything else a tool threw is still the tool's failure, never the
        // tier's: a host's network error inside one doesn't cool Private
        // Cloud Compute.
        let offline = LanguageModelSession.ToolCallError(tool: TriageShelfTool(), underlyingError: URLError(.notConnectedToInternet))
        #expect(AskTriage.askError(from: offline, tier: .privateCloud) == .model(tag: "ToolCallError(NSURLErrorDomain#-1009)"))
    }

    /// A cancellation, bare or inside a tool's failure, is a stop.
    @Test func aCancellationReadsAsAStop() {
        #expect(AskTriage.askError(from: CancellationError(), tier: .privateCloud) == .stopped)
        let cancelled = LanguageModelSession.ToolCallError(tool: TriageShelfTool(), underlyingError: CancellationError())
        #expect(AskTriage.askError(from: cancelled, tier: .onDevice) == .stopped)
    }

    // MARK: - The context gate and offline, wherever they sit

    @Test func theContextGateOnDeviceIsAFaultNotAnOutage() {
        // Private Cloud Compute's context gate says nothing about the
        // on-device model, so on that tier it is an ordinary fault, typed or
        // bare: both branches ask `readsAsContextGate`. A typed
        // `LanguageModelError` can't be built to reach it, since one bridges
        // to its case's index and never to −1.
        let gate = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        #expect(AskTriage.readsAsContextGate(gate, on: .privateCloud))
        #expect(!AskTriage.readsAsContextGate(gate, on: .onDevice))
        #expect(
            AskTriage.askError(from: gate, tier: .onDevice) == .model(tag: "FoundationModels.LanguageModelError#-1")
        )
    }

    @Test func theContextGateIsFoundAmongSeveralUnderlyingErrors() {
        let manager = NSError(domain: "ModelManagerError", code: 1001)
        let wrapper = NSError(domain: "Wrapper", code: 3, userInfo: [
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "Other", code: 2), manager]
        ])
        #expect(AskTriage.isPrivateCloudContextGate(wrapper))
        #expect(AskTriage.askError(from: wrapper, tier: .privateCloud) == .privateCloudUnreachable)
        // Under one key, nested under the other.
        let deeper = NSError(domain: "Outer", code: 1, userInfo: [NSUnderlyingErrorKey: wrapper])
        #expect(AskTriage.isPrivateCloudContextGate(deeper))
    }

    @Test func offlineIsFoundUnderAWrapper() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let wrapped = NSError(domain: "Transport", code: 9, userInfo: [NSUnderlyingErrorKey: offline])
        #expect(AskTriage.isOffline(wrapped))
        #expect(AskTriage.askError(from: wrapped, tier: .privateCloud) == .privateCloudUnreachable)
        #expect(AskTriage.askError(from: wrapped, tier: .onDevice) == .model(tag: "offline"))
        let among = NSError(domain: "Transport", code: 9, userInfo: [
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "Other", code: 2), offline]
        ])
        #expect(AskTriage.isOffline(among))
    }

    @Test func theWalkDownTheUnderlyingErrorsStops() {
        // Bounded, in depth and in how many it reads: a chain deeper than the
        // walk goes reads as not found.
        var chain = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        var deepGate = NSError(domain: "ModelManagerError", code: 1001)
        for depth in 0..<8 {
            chain = NSError(domain: "Layer", code: depth, userInfo: [NSUnderlyingErrorKey: chain])
            deepGate = NSError(domain: "Layer", code: depth, userInfo: [NSUnderlyingErrorKey: deepGate])
        }
        #expect(!AskTriage.isOffline(chain))
        #expect(!AskTriage.isPrivateCloudContextGate(deepGate))
        let wide = NSError(domain: "Wide", code: 0, userInfo: [
            NSMultipleUnderlyingErrorsKey: (0..<100).map { NSError(domain: "Other", code: $0) }
                + [NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)]
        ])
        #expect(!AskTriage.isOffline(wide))
    }

    @Test func everyTagIsShownToNobody() throws {
        // Whatever the tag says, the line the reader sees is the neutral one.
        let error = AskError.model(tag: "SomethingInternal")
        let line = try #require(error.errorDescription)
        #expect(!line.contains("SomethingInternal"))
        #expect(line == AskError.couldNotAnswer.errorDescription)
    }
    @Test func downloadingAssetsReadStillDownloadingNotCouldNotAnswer() {
        // SDK 27's replacement for the obsoleted
        // `GenerationError.assetsUnavailable`, and one of the four families
        // triage is exhaustive over. Falling through, it would read "Couldn't
        // answer that just now" in a state that has its own copy.
        let raw = SystemLanguageModel.Error.assetsUnavailable(
            .init(debugDescription: "assets are still downloading")
        )
        #expect(AskTriage.askError(from: raw, tier: .onDevice) == .modelUnavailable(.modelNotReady))
        // And the tag is read by reflection, never from the SDK's prose — the
        // payload above is exactly the kind of string that must not surface.
        #expect(AskTriage.tag(for: raw) == "assetsUnavailable")
    }

}

/// An error that describes itself in words a log must never carry, with a
/// case that has a payload and one that doesn't.
nonisolated enum TriageWordyError: Error, CustomStringConvertible {
    case quoted(String)
    case blocked

    var description: String { "what the reader wrote" }
}

/// The smallest tool a `ToolCallError` can name.
nonisolated struct TriageShelfTool: Tool {
    let name = "shelf"
    let description = "Reads the shelf."

    @concurrent func call(arguments: FakeSearchArguments) async throws -> String { "" }
}

#endif
