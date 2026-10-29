public import Foundation

/// Why no tier can serve.
///
/// Read off the same availability snapshot the tier choice was made from,
/// never asked for a second time, so the reason the reader is told can't
/// disagree with the choice that was made.
///
/// **One case per reason, because the line differs.** "Turn Apple
/// Intelligence on" is wrong for a reader who has it on and whose language it
/// doesn't support yet, and for a device that will never run it.
///
/// Each tier reports its own reason (`AskTierState.unavailability`). When
/// nothing can serve, the reader is told the on-device tier's, unless a tier
/// that is up doesn't speak the app's language, which is then the reason. So `notEntitled` and `offline`, which `AppleModelSeam` reports only for
/// Private Cloud Compute, reach the reader through the settings card
/// (`AskModelStatus.privateCloudUnavailability`).
///
/// `Codable` by raw value, which is the case name. A failed turn on disk
/// holds one inside `AskError.modelUnavailable`, so a renamed case changes
/// what a written thread decodes as.
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskUnavailability: String, Sendable, Equatable, Codable, CaseIterable {
    /// The reader hasn't turned Apple Intelligence on.
    case appleIntelligenceOff
    /// The hardware can't run it, so there is nothing to turn on.
    case deviceNotEligible
    /// The model's assets are still downloading.
    case modelNotReady
    /// A tier is there but not ready to serve.
    case systemNotReady
    /// A tier is up and doesn't speak the app's language, such as Hebrew.
    case languageNotSupported
    /// Private Cloud Compute is off for this process: the host declared no
    /// entitlement (`AskPrivateCloudCompute`), the running build doesn't
    /// carry it, or the development park keeps a development build off it
    /// (`AskDevelopmentPark`).
    case notEntitled
    /// Private Cloud Compute needs a network the device doesn't have.
    case offline
    /// A reason newer than this build knows about: one the framework gave
    /// that this build has no case for, or one a later build wrote to a
    /// thread this build reads back (`init(from:)`).
    case unknown

    /// Decodes a reason this build has no case for as `unknown`, so a failed
    /// turn a later build wrote reads back as no tier serving, for a reason
    /// this build can't name, rather than failing to decode.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AskUnavailability(rawValue: raw) ?? .unknown
    }
}

/// The typed failure Ask surfaces, so a model that can't serve reads
/// differently from a model that tried and couldn't answer, and a turn never
/// ends in a silent empty answer.
///
/// Raw SDK text never reaches the screen: `model(tag:)` carries a tag for
/// the log (`AskTriage.tag(for:)`) and shows the couldn't-answer line.
///
/// **`Codable`, and the case names are on disk.** A failed turn is written
/// with its case beside the line it showed (`AskThreadEntry.failure`), so a
/// thread read back renders the line again in the reader's current language,
/// and a reworded line reaches turns already written. A renamed case changes
/// what a written thread decodes as: `AskTurn.init(entry:)` falls back to the
/// stored line when the case doesn't decode, so the cost is a stale line
/// rather than a lost turn.
///
/// **Open** (`@nonexhaustive`): a later version may add a case, so a host's
/// `switch` over it takes `@unknown default`.
@nonexhaustive
nonisolated public enum AskError: LocalizedError, Equatable, Sendable, Codable {
    /// No tier can serve the question right now, for the reason given.
    case modelUnavailable(AskUnavailability)
    /// A tier was available and tried, but returned nothing usable or ran
    /// out of time: the turn's deadline passed, or the on-device model timed
    /// out. On Private Cloud Compute a timeout is an outage,
    /// `privateCloudUnreachable`. A question with nothing left in it once
    /// what the reader can't see is dropped and it is trimmed fails with this
    /// too, before any tier is asked.
    case couldNotAnswer
    /// The tier answered without reading anything, so whatever it said came
    /// from its own weights rather than the reader's own data. When every
    /// question is about one person's things, a confident invention is worse
    /// than no answer.
    ///
    /// Which answers surface it is the domain's grounding policy
    /// (`AskGroundingPolicy`). Under `.retrieval`, the default, a fresh
    /// session's answer that read nothing never surfaces it: the engine
    /// searches for the model instead (the grounded retry), and a
    /// conversation that retry grounded counts as grounded for the rest of
    /// its life. It surfaces for a follow-up on a kept conversation that
    /// called no tool and names no row the thread has read, and under
    /// `.toolCall` for a first answer that called no tool too, since that
    /// policy has no retry. Under `.notRequired` it never surfaces. The
    /// screen answers it with coaching. Retryable, because whether a model reaches
    /// for a tool it was offered is exactly the kind of thing another attempt
    /// changes.
    case ungrounded
    /// The model declined the question itself: a guardrail verdict. A fact
    /// about the question, so asking it again only refuses again.
    case refused
    /// Private Cloud Compute couldn't be reached: a network failure, the
    /// service unavailable, a rate limit, a timeout, or its context gate. The
    /// turn is handed down to the on-device model when that model can serve,
    /// so this is the turn's error only when it can't. Either way the engine
    /// tells the seam (`AskModelSeam.noteTransportFailure(on:)`), and
    /// `AppleModelSeam` cools the tier for 60 s, or until a later reset a rate
    /// limit named, so the next question goes to the on-device model when it
    /// can serve. When it can't, the next question, Try Again's included, asks
    /// Private Cloud Compute all the same, cooling or not.
    case privateCloudUnreachable
    /// The turn outgrew the model's window, even on a fresh session: a
    /// follow-up that overflows rolls over to one once before this is its
    /// error.
    case contextTooLarge
    /// The question carried a photo, and the session or engine answering it
    /// can't take one. It fails rather than answering as though it had seen
    /// the photo, and asking again with the photo fails the same way.
    ///
    /// A model that says it can't see (`LanguageModelError`'s
    /// `unsupportedCapability` for `vision`), or can't take a prompt that
    /// carries a picture (`unsupportedTranscriptContent`), fails with this
    /// too: the photo is what it couldn't take.
    case photosNotSupported
    /// The model answering can't take what the request asks of it: a
    /// capability it lacks, such as tool calling, guided generation or
    /// reasoning, a generation guide it doesn't support, or content in the
    /// prompt it can't process (`LanguageModelError`'s `unsupportedCapability`,
    /// `unsupportedGenerationGuide` and `unsupportedTranscriptContent`, a
    /// photo aside: `photosNotSupported`).
    ///
    /// A verdict on the request, which is the host's (its domain's schema and
    /// tools, and the options AskKit asks with) more than the reader's, so the
    /// same request fails the same way on that model every time: it offers no
    /// Try Again, and isn't handed down to the other tier
    /// (`askIsTierOutage`). The raw error's tag is in the routing log
    /// (`AskTriage.tag(for:)`), which says which of the three it was.
    case requestNotSupported
    /// The daily Private Cloud Compute quota is spent. `resetDate` is when it
    /// resets, when that is known. The turn is handed down to the on-device
    /// model when that model can serve, and this is the turn's error when it
    /// can't. Once the quota is known to be spent, a question with nothing
    /// below to serve it fails with this at once, asking Private Cloud Compute
    /// nothing and spending no request, with the reset date the mirror holds
    /// (`AskModelStatus.resetDate`). Retryable: Try Again asks once the quota
    /// has reset.
    case quotaReached(resetDate: Date?)
    /// An unclassified model failure, carrying a tag for the log
    /// (`AskTriage.tag(for:)`): the error's case name, its domain and code,
    /// or its type name, never its message. An on-device failure for want of
    /// a network carries "offline".
    case model(tag: String)
    /// The turn was stopped before it had written anything, by the reader or
    /// not. A turn stopped after its first words keeps them as a truncated
    /// answer instead (`AskAnswer.isTruncated`).
    ///
    /// Its line (`errorDescription`) is the couldn't-answer one, which is
    /// true of a stop nobody asked for, such as a host's or the engine's. A
    /// stop the reader asked for isn't that: AskUI says the reader stopped
    /// the answer instead, from `AskThreadEntry.stopped` on a turn read back
    /// too, and offers Try Again either way.
    case stopped

    /// Whether another attempt could plausibly succeed, which decides whether
    /// the thread offers **Try Again**.
    ///
    /// A refusal or an overflow is a verdict on the question, and a photo the
    /// session can't take, or a request the model can't, fails the same way
    /// again. No servable model is a state of the device that trying again at
    /// once doesn't change, and its line says why. Everything else (a timeout,
    /// an empty answer, a spent quota, an unreachable tier, a transient fault,
    /// a stop) can go differently next time.
    public var isRetryable: Bool {
        switch self {
        case .modelUnavailable, .refused, .contextTooLarge, .photosNotSupported, .requestNotSupported: return false
        case .couldNotAnswer, .ungrounded, .privateCloudUnreachable, .quotaReached, .model, .stopped: return true
        }
    }

    /// The line the thread shows. Copy that names the app stays in the host's
    /// catalog and reaches AskUI through `AskBrand`; these are the neutral
    /// lines AskCore owns.
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let why):
            return Self.unavailableMessage(why)
        case .couldNotAnswer, .model, .stopped:
            // One line for the three: from the reader's side these are the same
            // event, the app having nothing trustworthy to say.
            return String(localized: "Couldn't answer that just now. Please try again.", bundle: #bundle,
                          comment: "Shown when a model was available but the Ask turn timed out, failed, or produced no answer. Retryable, so Try Again is offered.")
        case .ungrounded, .refused:
            return String(localized: "Couldn't answer that question. Try asking it another way.", bundle: #bundle,
                          comment: "Shown when the model refused an Ask question, or answered without reading the reader's own data so the answer was discarded.")
        case .privateCloudUnreachable:
            return String(localized: "Couldn't reach Private Cloud Compute. Try again.", bundle: #bundle,
                          comment: "Shown when an Ask turn failed because Private Cloud Compute could not be reached. Retryable.")
        case .contextTooLarge:
            return String(localized: "This conversation got too long to carry on. Start a new chat and ask again.", bundle: #bundle,
                          comment: "Shown when an Ask conversation overflowed the model's context window. New Chat is the toolbar button that starts over.")
        case .photosNotSupported:
            return String(localized: "Couldn't read the photo. Ask again without it.", bundle: #bundle,
                          comment: "Shown when a question was asked with a photo and the model answering it can't take photos. Not retryable: asking again with the photo fails the same way, so the reader is told to ask without it.")
        case .requestNotSupported:
            return String(localized: "Couldn't answer that. The model doesn't support what this app asks of it.", bundle: #bundle,
                          comment: "Shown when the model answering can't take what the app's request asks of it: a feature, an output format or content the model doesn't support. Not the reader's doing, and not retryable: asking again fails the same way. \"The model\" is the Apple Intelligence model answering; \"this app\" is the app showing the line, unnamed.")
        case .quotaReached:
            return String(localized: "Private Cloud Compute has reached today's limit.", bundle: #bundle,
                          comment: "Shown when Private Cloud Compute's daily quota, the reader's iCloud account's, is spent. When it comes back is a sentence of its own after this one, on the quota banner and on the settings card, as a time or as a day and a time.")
        }
    }

    /// The line for a reason no tier can serve.
    public static func unavailableMessage(_ why: AskUnavailability) -> String {
        switch why {
        case .appleIntelligenceOff:
            return String(localized: "Apple Intelligence is turned off. Turn it on in Settings.", bundle: #bundle,
                          comment: "Shown when no model can answer because the reader has not turned Apple Intelligence on. The Mac variation names the Mac's app, System Settings, where the other says Settings.")
        case .deviceNotEligible:
            return String(localized: "This device can't run Apple Intelligence.", bundle: #bundle,
                          comment: "Shown when the hardware is not eligible for Apple Intelligence — there is nothing the reader can turn on. The Mac variation says \"this Mac\" where the other says \"this device\".")
        case .modelNotReady:
            return String(localized: "Apple Intelligence is still downloading. Ask again once it has finished.", bundle: #bundle,
                          comment: "Shown when the Apple Intelligence model assets are still downloading.")
        case .languageNotSupported:
            return String(localized: "Apple Intelligence doesn't support this language yet.", bundle: #bundle,
                          comment: "Shown when Apple Intelligence works but does not support the app's language, so no question can be answered. Hebrew is one such language.")
        case .notEntitled, .offline, .systemNotReady, .unknown:
            return String(localized: "Couldn't reach Apple Intelligence right now. Try again later.", bundle: #bundle,
                          comment: "Shown when no model can answer for a reason the app cannot name — a tier that is not ready, no network behind Private Cloud Compute, or a reason newer than this build.")
        }
    }
}
