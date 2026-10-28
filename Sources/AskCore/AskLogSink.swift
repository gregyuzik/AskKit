import Foundation
import os

/// What the snapshot loop measured, gathered inside the streaming closure and
/// read once it returns.
///
/// Snapshots are cumulative, so growth is measured as the prose getting
/// longer, not as deltas: a snapshot that changed only the tiles counts as a
/// snapshot and not as growth.
nonisolated struct StreamMeasurements: Sendable {
    var snapshots = 0
    var growths = 0
    var characters = 0
    var firstWord: ContinuousClock.Instant?
    var lastWord: ContinuousClock.Instant?
}

/// How a generation came to be grounded, as `AskTurnStats` logs it and an
/// answer records it (`AskAnswer.grounding`).
///
/// Its raw values are the log's words and the thread file's, so they don't
/// change.
nonisolated public enum AskGrounding: String, Sendable, Equatable, CaseIterable, Codable {
    /// The model called a tool.
    case toolCall = "tool call"
    /// The app searched for the model: the grounded retry, in this turn or
    /// earlier in the conversation the turn continues.
    case appRetrieved = "app retrieved"
    /// A follow-up with no tool call of its own, grounded by what the thread
    /// has read, such as prose that names a row an earlier turn read.
    case followUp = "follow-up"
    /// Nothing grounded it. Its prose was kept only under a policy that keeps
    /// such answers (`AskGroundingPolicy.notRequired`), and discarded under
    /// any other.
    ///
    /// Not `none`, whose raw value it keeps for the log and the thread file:
    /// `AskAnswer.grounding` is optional, and `answer.grounding == .none`
    /// would compile as the test for no grounding recorded.
    case nothing = "none"
}

/// What one generation's prose cost and how it arrived. The engine hands it to
/// `AskLogSink.turn(_:)` as each answer's stream ends, whether the answer is
/// kept, truncated or discarded, and `AskOSLogSink` writes it as the
/// `[stream]` and `[usage]` lines. A turn the grounded retry asks again logs
/// two, the second `retried`. A stream that fails or is stopped logs none,
/// and neither do the grounded retry's planner or a refine pass.
nonisolated public struct AskTurnStats: Sendable, Equatable {
    /// The tier the generation ran on.
    public var tier: AskTier
    /// Every snapshot the stream delivered.
    public var snapshots = 0
    /// The snapshots that made the prose longer.
    public var growths = 0
    /// The length of the prose the generation ended with: the answer's, or a
    /// truncated answer's. Zero when its prose wasn't kept.
    public var characters = 0
    /// The tools the model called during the generation, by the collector's
    /// count or the session's transcript, whichever is higher.
    public var toolCalls = 0
    /// The rows behind the answer (`AskAnswer.matches`).
    public var rowsRead = 0
    /// Milliseconds from the turn's start to the first activity a tool
    /// reported, as its call started (`AskToolContext.withToolCall(_:_:)`
    /// with an activity) or through the relay, as it happened rather than
    /// when a snapshot noticed it. Nil when no tool reported one.
    public var msToFirstTool: Int?
    /// Milliseconds from the turn's start to the first snapshot that added
    /// prose. Nil when none did.
    public var msToFirstWord: Int?
    /// Milliseconds from the turn's start to the last snapshot that added
    /// prose. Nil when none did.
    public var msToLastWord: Int?
    /// Milliseconds from the turn's start to the generation's end.
    public var msTotal = 0
    /// The generation's last response, when the tier reports it
    /// (`AskSession.usage()`): its input tokens.
    public var inputTokens: Int?
    /// Its output tokens.
    public var outputTokens: Int?
    /// Its reasoning tokens.
    public var reasoningTokens: Int?
    /// Its input tokens read from the session's cache.
    public var cachedTokens: Int?
    /// How the generation was grounded.
    public var grounding: AskGrounding = .nothing
    /// The generation is the grounded retry's second ask.
    public var retried = false

    /// Stats for a generation on `tier`, every count at zero.
    public init(tier: AskTier) {
        self.tier = tier
    }

    /// The mean characters per growing snapshot (`characters` over
    /// `growths`): the number that says whether prose arrived in words or in
    /// paragraphs.
    public var meanDelta: Int { growths > 0 ? characters / growths : 0 }

    /// The `[stream]` line.
    public var streamLine: String {
        func at(_ ms: Int?) -> String { ms.map { "\($0)ms" } ?? "–" }
        let span: String
        if let first = msToFirstWord, let last = msToLastWord { span = "\(last - first)ms" } else { span = "–" }
        return "[stream] \(tier.rawValue) snapshots=\(snapshots) growths=\(growths) "
            + "firstWord=\(at(msToFirstWord)) proseSpan=\(span) chars=\(characters) "
            + "meanDelta=\(meanDelta) firstTool=\(at(msToFirstTool)) tools=\(toolCalls) "
            + "rows=\(rowsRead) grounding=\(grounding.rawValue)\(retried ? " retried" : "") "
            + "total=\(msTotal)ms"
    }

    /// The `[usage]` line, when the tier reported token counts.
    public var usageLine: String? {
        guard inputTokens != nil || outputTokens != nil else { return nil }
        func n(_ value: Int?) -> String { value.map(String.init) ?? "–" }
        return "[usage] \(tier.rawValue) input=\(n(inputTokens)) cached=\(n(cachedTokens)) "
            + "output=\(n(outputTokens)) reasoning=\(n(reasoningTokens))"
    }
}

/// Prose the engine wrote and then refused to show, with why. Goes to the log
/// as a verbose payload, never to the screen.
nonisolated public struct AskDiscard: Sendable, Equatable {
    /// Why prose was written and then not shown.
    nonisolated public enum Reason: String, Sendable, Equatable, CaseIterable {
        /// The answer read nothing, under a policy that requires grounding,
        /// so it would have been invented (house rule 2).
        case ungrounded
        /// The generation ended with no prose.
        case empty
        /// The deadline cut the stream before anything the domain's policy
        /// keeps was written: no prose, or under a policy that requires
        /// grounding, none grounded.
        case deadlineWithNothingToKeep = "deadline with nothing to keep"
    }

    /// The tier that wrote the prose.
    public let tier: AskTier
    /// Why it wasn't shown.
    public let reason: Reason
    /// The prose as far as it got: model output about the reader's own data,
    /// which `AskOSLogSink` logs as private.
    public let text: String

    /// A discard with each field as given.
    public init(tier: AskTier, reason: Reason, text: String) {
        self.tier = tier
        self.reason = reason
        self.text = text
    }
}

/// A reader's thumbs on one answer, as the log keeps it: the shape of the
/// answer, never its words.
nonisolated public struct AskFeedback: Sendable, Equatable {
    /// Up or down. No neutral: a reader who has no verdict taps nothing.
    /// `Codable` by raw value, which is the case name: a thread on disk holds
    /// it (`AskThreadEntry.feedback`).
    nonisolated public enum Sentiment: String, Sendable, Equatable, Codable, CaseIterable {
        /// A thumbs-up.
        case positive
        /// A thumbs-down.
        case negative
    }

    /// The reader's verdict.
    public let sentiment: Sentiment
    /// The tier that wrote the answer, or nil for an answer the domain gave
    /// without a model.
    public let tier: AskTier?
    /// The answer's normalized kind (`AskAnswer.questionKind`), so a verdict
    /// can be read against the kind of question it was on.
    public let questionKind: String?
    /// How many tiles the answer showed.
    public let tilesShown: Int
    /// How many rows stood behind the answer (`AskAnswer.matches`).
    public let rowsRead: Int
    /// Whether the answer was truncated (`AskAnswer.isTruncated`).
    public let wasTruncated: Bool

    /// A verdict with each field as given. AskUI builds one from the answer
    /// the reader rated.
    public init(
        sentiment: Sentiment,
        tier: AskTier?,
        questionKind: String?,
        tilesShown: Int,
        rowsRead: Int,
        wasTruncated: Bool
    ) {
        self.sentiment = sentiment
        self.tier = tier
        self.questionKind = questionKind
        self.tilesShown = tilesShown
        self.rowsRead = rowsRead
        self.wasTruncated = wasTruncated
    }

    /// The `[feedback]` line.
    public var line: String {
        "[feedback] \(sentiment.rawValue) tier=\(tier?.rawValue ?? "–") kind=\(questionKind ?? "–") "
            + "tiles=\(tilesShown) rows=\(rowsRead)\(wasTruncated ? " truncated" : "")"
    }
}

/// Where the engine's telemetry goes: `AskOSLogSink` by default, or a sink
/// that bridges a host's own activity log.
///
/// Every method is defaulted, so a sink bridges only the lines it wants. A
/// sink that writes none of them hears nothing, and the engine runs the same
/// with or without it.
nonisolated public protocol AskLogSink: Sendable {
    /// One answer stream's shape and cost, as it ends (`AskTurnStats` says
    /// which streams). Dropped by default.
    func turn(_ stats: AskTurnStats)
    /// Why a turn ran where it did: the line that answers "why did my
    /// question run on device?" Dropped by default.
    func routing(_ line: String)
    /// Prose that was written and not shown. Dropped by default: the prose is
    /// model output about the reader's own data, and a sink keeps it only by
    /// writing this.
    func discard(_ discard: AskDiscard)
    /// A reader's verdict on an answer. Defaulted to a `routing` line, so a
    /// sink a host already bridges hears it with no change.
    func feedback(_ feedback: AskFeedback)
}

nonisolated extension AskLogSink {
    /// Drops the stats.
    public func turn(_ stats: AskTurnStats) {}

    /// Drops the line.
    public func routing(_ line: String) {}

    /// Drops the discard, and with it the prose.
    public func discard(_ discard: AskDiscard) {}

    /// Writes the verdict as a `routing` line (`AskFeedback.line`).
    public func feedback(_ feedback: AskFeedback) {
        routing(feedback.line)
    }
}

/// The default sink: `os.Logger` under the domain's subsystem.
nonisolated public struct AskOSLogSink: AskLogSink {
    private let logger: Logger

    /// A sink that logs under `subsystem` and `category`. The engine builds
    /// one under the brand's `AskBrand.logSubsystem` when the host passes no
    /// sink of its own.
    public init(subsystem: String, category: String = "ask") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    /// Logs the `[stream]` line, and the `[usage]` line when there is one, at
    /// info level.
    public func turn(_ stats: AskTurnStats) {
        logger.info("\(stats.streamLine, privacy: .public)")
        if let usage = stats.usageLine {
            logger.info("\(usage, privacy: .public)")
        }
    }

    /// Logs the line under `[routing]`, at `routingLevel`.
    public func routing(_ line: String) {
        logger.log(level: Self.routingLevel, "[routing] \(line, privacy: .public)")
    }

    /// Notice, which the log store keeps: the routing lines say why a turn ran
    /// where it did and why one failed, by its tag, and they are wanted after
    /// the fact. At info level they were kept in memory only, and Console
    /// hides them.
    static var routingLevel: OSLogType { .default }

    /// Logs a mistake in the domain an engine was built with under
    /// `[domain]`, at `domainMistakeLevel`. The line is logged once, as the
    /// engine is built (`AskEngine.init(domain:seam:log:)`).
    func domainMistake(_ line: String) {
        logger.log(level: Self.domainMistakeLevel, "[domain] \(line, privacy: .public)")
    }

    /// Fault, which the log store keeps and Console and Xcode set apart: a
    /// domain mistake is a bug in the host's code whose cost is otherwise
    /// silent.
    static var domainMistakeLevel: OSLogType { .fault }

    /// Logs the `[feedback]` line as public: it is the answer's shape (a
    /// verdict, a tier, a kind from a fixed vocabulary, two counts and whether
    /// the answer was cut short) and carries none of its words.
    public func feedback(_ feedback: AskFeedback) {
        logger.notice("\(feedback.line, privacy: .public)")
    }

    /// Logs the reason as public and the prose as private, under `[discard]`.
    public func discard(_ discard: AskDiscard) {
        // The reason is public; the prose isn't: it is model output about the
        // reader's own data.
        logger.notice("[discard] \(discard.tier.rawValue, privacy: .public) \(discard.reason.rawValue, privacy: .public): \(discard.text, privacy: .private)")
    }
}
