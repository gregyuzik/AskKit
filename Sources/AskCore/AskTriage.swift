#if canImport(FoundationModels) && !os(tvOS)

public import Foundation
import FoundationModels

/// Raw Foundation Models errors to `AskError`, in one place.
///
/// Pure and exhaustive over the four SDK 27 error families
/// (`PrivateCloudComputeLanguageModel.Error`, `SystemLanguageModel.Error`,
/// `LanguageModelSession.Error` and `LanguageModelError`), so it is
/// unit-testable by feeding it constructed errors.
///
/// The distinctions that cost something to get wrong:
///
/// - **`contextSizeExceeded` is CONTENT, never transport.** It says the
///   conversation outgrew the window, and cooling Private Cloud Compute for a
///   minute over it punishes the tier for the transcript's size. So it is never
///   an outage: the turn fails where it stands, or rolls the conversation over.
/// - **`concurrentRequests` is never shown as itself.** It means the engine let
///   two generations onto one session, a serialization bug in AskKit rather
///   than anything the reader did. It reads as `couldNotAnswer`, and is logged
///   at the level every other turn failure is.
/// - **An instant `LanguageModelError` with code −1 is Private Cloud Compute's
///   context gate**, not rate limiting: a process outside an app's context gets
///   it every time, within milliseconds. It reads as the tier not serving,
///   never as raw text.
/// - **A capability, a guide or content the model doesn't support is a
///   verdict, never a passing fault.** Read as `.model(tag:)`, it would offer a
///   Try Again that can only fail the same way. It is `.requestNotSupported`,
///   or `.photosNotSupported` where the photo is what the model can't take.
nonisolated public enum AskTriage {

    /// The `AskError` a raw failure reads as.
    ///
    /// An `AskError` reads as itself and a `CancellationError` as `.stopped`,
    /// and so do either of them a tool threw, inside the session's
    /// `ToolCallError`: anything else a tool threw is the tool's failure,
    /// `.model(tag:)`, whatever tier it ran on. A timeout is the tier's on
    /// Private Cloud Compute, and an outage there, as a rate limit is.
    ///
    /// - Parameters:
    ///   - error: the failure as the framework, a session or a tool threw it.
    ///     Read by its type, case, domain and code, never its description.
    ///   - tier: which tier raised it, so a Private Cloud Compute transport
    ///     fault can be told from an on-device one.
    public static func askError(from error: any Error, tier: AskTier) -> AskError {
        // AskKit's own: an `AskError` as it is, and a stop as one.
        if let ask = error as? AskError { return ask }
        if error is CancellationError { return .stopped }
        // What a tool threw is the tool's failure, tagged inside its wrapper
        // below, and never a tier's: a host's `URLError` in there is its own
        // network, not Private Cloud Compute's. Two things a tool throws say
        // more, and read as themselves: an `AskError` the domain chose, as
        // one its search throws is passed on, and a stop. `#if !os(watchOS)`
        // because the SDK marks `ToolCallError` unavailable there.
        #if !os(watchOS)
        if let toolCall = error as? LanguageModelSession.ToolCallError {
            if let ask = toolCall.underlyingError as? AskError { return ask }
            if toolCall.underlyingError is CancellationError { return .stopped }
        }
        #endif
        // Private Cloud Compute transport and quota.
        if let pcc = error as? PrivateCloudComputeLanguageModel.Error {
            switch pcc {
            case .quotaLimitReached(let info): return .quotaReached(resetDate: info.resetDate)
            case .networkFailure, .serviceUnavailable: return .privateCloudUnreachable
            @unknown default: return .model(tag: tag(for: pcc))
            }
        }
        // The on-device model's assets aren't there yet. It reads as
        // `.modelUnavailable(.modelNotReady)`, whose line says Apple
        // Intelligence is still downloading, rather than the generic
        // "Couldn't answer that just now".
        //
        // `#if !os(watchOS)` because this file's platform gate lets it build
        // for watchOS, where `SystemLanguageModel` is unavailable: an ungated
        // reference would break a host's watchOS build.
        #if !os(watchOS)
        if let assets = error as? SystemLanguageModel.Error {
            switch assets {
            case .assetsUnavailable: return .modelUnavailable(.modelNotReady)
            @unknown default: return .model(tag: tag(for: assets))
            }
        }
        #endif
        // A session-level fault. `concurrentRequests` is AskKit's own bug.
        if let session = error as? LanguageModelSession.Error {
            switch session {
            case .concurrentRequests: return .couldNotAnswer
            default: return .model(tag: tag(for: session))
            }
        }
        // Model-side verdicts.
        if let model = error as? LanguageModelError {
            switch model {
            case .guardrailViolation, .refusal:
                return .refused
            case .contextSizeExceeded:
                return .contextTooLarge
            case .unsupportedLanguageOrLocale:
                return .modelUnavailable(.languageNotSupported)
            case .unsupportedCapability(let info):
                // A verdict on the request, never a passing fault: the same
                // request fails the same way on that model every time. Read
                // from what the error names rather than from whether the turn
                // had a photo: a model that can't see says `vision`, and one
                // that can't reason, asked with a photo, isn't failing on it.
                return info.capability == .vision ? .photosNotSupported : .requestNotSupported
            case .unsupportedTranscriptContent(let info):
                // A photo is the only thing besides words AskKit puts in a
                // prompt, so a prompt carrying one among the entries the model
                // can't process, as a corrupt or unreadable picture is, reads
                // as the photo.
                return info.unsupportedContent.contains(where: carriesAPhoto) ? .photosNotSupported : .requestNotSupported
            case .unsupportedGenerationGuide:
                return .requestNotSupported
            case .rateLimited:
                // The tier saying "not now": the one below is unaffected.
                return tier == .privateCloud ? .privateCloudUnreachable : .model(tag: tag(for: model))
            case .timeout:
                // On Private Cloud Compute the tier not answering in time, as
                // a timed-out connection to it is (`isOffline`): an outage the
                // turn is handed down from, so a tier that keeps timing out
                // doesn't fail every turn while the on-device model could
                // answer. On device there is nothing below.
                return tier == .privateCloud ? .privateCloudUnreachable : .couldNotAnswer
            default:
                return readsAsContextGate(model, on: tier) ? .privateCloudUnreachable : .model(tag: tag(for: model))
            }
        }
        // Private Cloud Compute's context gate arrives as a bare `NSError`,
        // not as a `LanguageModelError` case, so it is checked here too. The
        // check in the branch above is for the day the SDK types it, and both
        // read it only on the tier it belongs to.
        if readsAsContextGate(error, on: tier) {
            return .privateCloudUnreachable
        }
        if isOffline(error) {
            return tier == .privateCloud ? .privateCloudUnreachable : .model(tag: "offline")
        }
        return .model(tag: tag(for: error))
    }

    /// When a failure says the tier can be tried again: a rate limit that
    /// named its reset, or the day's quota. Nil for a failure that is neither.
    ///
    /// **Read from the raw error, because `askError(from:tier:)` drops it.** A
    /// rate limit triages to `.privateCloudUnreachable`, which carries no date
    /// and is written to disk, so the date can't ride the `AskError`. The seam
    /// reads it here instead, from the sessions it built, and holds the tier
    /// until then rather than for the minute an unannounced fault gets.
    ///
    /// A quota with no date is still a quota: the seam falls back to the reset
    /// date the model's quota usage reports. A rate limit with no date is an
    /// ordinary outage.
    ///
    /// Public for a host that builds its own sessions: an `AppleAskSession`
    /// hands every raw failure to its `noteFailure`, and this is how that
    /// seam learns when to try the tier again.
    public static func retryAfter(from error: any Error) -> AskRetryAfter? {
        if let pcc = error as? PrivateCloudComputeLanguageModel.Error,
           case .quotaLimitReached(let info) = pcc {
            return .quotaReached(resetDate: info.resetDate)
        }
        if let model = error as? LanguageModelError,
           case .rateLimited(let info) = model,
           let date = info.resetDate {
            return .rateLimited(until: date)
        }
        return nil
    }

    /// Whether a transcript entry is a prompt with a picture in it: one of
    /// the attachments a photo question puts after its words
    /// (`AskSession.stream(prompt:images:…)`).
    static func carriesAPhoto(_ entry: Transcript.Entry) -> Bool {
        guard case .prompt(let prompt) = entry else { return false }
        return prompt.segments.contains { segment in
            guard case .attachment(let attachment) = segment, case .image = attachment.content else { return false }
            return true
        }
    }

    /// Whether the error is Private Cloud Compute's context gate on the tier
    /// it says something about. On device it is an ordinary fault: the gate
    /// stands in front of Private Cloud Compute, not the on-device model.
    static func readsAsContextGate(_ error: any Error, on tier: AskTier) -> Bool {
        tier == .privateCloud && isPrivateCloudContextGate(error)
    }

    /// Whether the error is Private Cloud Compute's context gate: the instant
    /// −1 a process outside an app's context gets, with `ModelManagerError
    /// 1001` underneath.
    ///
    /// It must never reach a reader as raw text: the string is implementation
    /// detail, and the honest reading is "this tier is not serving here".
    ///
    /// The domain and code are the whole test, walked down the underlying
    /// errors (`anyUnderlying(of:where:)`), which is where `ModelManagerError
    /// 1001` lives. Never a match on the error's description: that
    /// materializes the SDK's own prose, which for a guardrail violation can
    /// quote the reader's data (`tag(for:)` says more).
    static func isPrivateCloudContextGate(_ error: any Error) -> Bool {
        anyUnderlying(of: error) { nsError in
            (nsError.code == -1 && nsError.domain.contains("LanguageModel"))
                || (nsError.code == 1001 && nsError.domain.contains("ModelManager"))
        }
    }

    /// A raw transport-level offline still reads as offline, at the top or
    /// under whatever wrapped it: no connection, a lost one, a host that
    /// can't be found, reached or looked up, a secure connection that
    /// couldn't be made, a timeout, and data or roaming turned off.
    static func isOffline(_ error: any Error) -> Bool {
        anyUnderlying(of: error) { nsError in
            guard nsError.domain == NSURLErrorDomain else { return false }
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorTimedOut,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff:
                return true
            default:
                return false
            }
        }
    }

    /// How far down the underlying errors `anyUnderlying(of:where:)` looks:
    /// the error, then three levels under it.
    static let underlyingDepth = 4

    /// How many errors `anyUnderlying(of:where:)` reads in all, so an error
    /// carrying a long list of others costs no more than a few.
    static let underlyingReads = 16

    /// Whether the error, or one under it, matches: walked breadth first
    /// down both `NSUnderlyingErrorKey` and `NSMultipleUnderlyingErrorsKey`,
    /// to `underlyingDepth` levels and `underlyingReads` errors at most. The
    /// bounds are what end a chain that loops back on itself.
    static func anyUnderlying(of error: any Error, where matches: (NSError) -> Bool) -> Bool {
        var level: [NSError] = [error as NSError]
        var reads = 0
        for _ in 0..<underlyingDepth {
            var next: [NSError] = []
            for nsError in level {
                guard reads < underlyingReads else { return false }
                reads += 1
                if matches(nsError) { return true }
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    next.append(underlying)
                }
                if let several = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                    next.append(contentsOf: several)
                }
            }
            guard !next.isEmpty else { return false }
            level = next
        }
        return false
    }

    /// A bare type or case name for the log, never the SDK's message, which
    /// can carry model output. Log this, never the error itself.
    ///
    /// **Not `String(describing:)` on the error.** Every SDK 27 error family
    /// conforms to `CustomDebugStringConvertible`, so describing one returns
    /// the SDK's own prose, which for `guardrailViolation` is a sentence about
    /// what was blocked. Reflection reads the case name and can reach nothing
    /// else.
    ///
    /// A tool's failure (`LanguageModelSession.ToolCallError`) carries what
    /// the tool threw, tagged the same way, as `ToolCallError(<tag>)`. No tag
    /// runs past `tagLength` characters.
    public static func tag(for error: any Error) -> String {
        String(untrimmedTag(for: error).prefix(tagLength))
    }

    /// The most characters a tag runs to.
    static let tagLength = 60

    private static func untrimmedTag(for error: any Error) -> String {
        // The wrapper the session throws when a domain's tool fails, which
        // says nothing of the failure itself. What the tool threw is trimmed
        // to leave the wrapper whole. `#if !os(watchOS)` because the SDK
        // marks `ToolCallError` unavailable there.
        #if !os(watchOS)
        if let toolCall = error as? LanguageModelSession.ToolCallError {
            let wrapper = "ToolCallError"
            let inner = tag(for: toolCall.underlyingError).prefix(tagLength - wrapper.count - 2)
            return "\(wrapper)(\(inner))"
        }
        #endif
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            return mirror.children.first?.label ?? payloadlessCaseName(of: error)
        }
        // A bridged `NSError` has no case to read, and nor does a struct that
        // bridges to one with a code of its own, such as `URLError` or
        // `CocoaError`: their domain and code are the shape of the failure
        // and carry no message. The type's name alone would say which family,
        // and not which failure.
        if mirror.displayStyle == .class || error is any CustomNSError {
            let nsError = error as NSError
            return "\(nsError.domain)#\(nsError.code)"
        }
        return String(describing: type(of: error))
    }

    /// The name of a case with no payload, which reflection can't read: such a
    /// case has no child to label.
    ///
    /// For an enum that doesn't describe itself, `String(describing:)` is the
    /// case's name and nothing else, since there is no payload to print. One
    /// that does describe itself, as every SDK 27 error family does, would hand
    /// back its prose instead. So the SDK's payload-less cases are named here,
    /// and any other case of a type that describes itself reads as its domain
    /// and code, as a bridged `NSError` does.
    private static func payloadlessCaseName(of error: any Error) -> String {
        if let session = error as? LanguageModelSession.Error {
            switch session {
            case .concurrentRequests: return "concurrentRequests"
            case .transcriptMutationWhileResponding: return "transcriptMutationWhileResponding"
            @unknown default: break
            }
        }
        // Asked of `Any`: asked of `any Error`, every check reads as always
        // true, because any error bridges to an `NSError`, which describes
        // itself.
        let value: Any = error
        if value is any CustomStringConvertible || value is any CustomDebugStringConvertible
            || value is any TextOutputStreamable {
            let nsError = error as NSError
            return "\(nsError.domain)#\(nsError.code)"
        }
        return String(describing: error)
    }

}

/// When a tier said it can be tried again: `AskTriage.retryAfter(from:)`.
///
/// **One of two readings, each with what it carries.** A rate limit is one
/// only when it named its reset (without one it is an ordinary outage, and
/// no reading at all), so its date is never missing; only a quota's can be.
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskRetryAfter: Sendable, Equatable {
    /// A rate limit that named when it lifts.
    case rateLimited(until: Date)
    /// The day's quota, with its reset when the tier gave one. Without one,
    /// the seam falls back to the reset the model's quota usage reports.
    case quotaReached(resetDate: Date?)
}

#endif
