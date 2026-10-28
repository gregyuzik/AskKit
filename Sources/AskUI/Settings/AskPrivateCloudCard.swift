#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import SwiftUI

/// What a settings surface has to say about Private Cloud Compute.
///
/// **Derived from the mirror, never probed here.** A settings card that asked
/// the system for itself would be a second reader of an availability that
/// `AskModelSeam` already owns, and the two would disagree in the one place a
/// reader goes to find out which is right.
///
/// A value rather than a chain of `if`s inside the view, so tests that build
/// no view can pin the mapping: this is the surface that tells a reader why
/// their answers are coming from the smaller model, and getting it wrong is
/// silent.
nonisolated public enum AskPrivateCloudState: Sendable, Equatable {
    /// The tier is up and has turns left.
    case serving
    /// Up, and near the day's limit. Shown, never acted on.
    case approachingLimit
    /// Up, and out of turns until the reset.
    case limitReached
    /// The host declared no entitlement (`AskPrivateCloudCompute`) or this
    /// build doesn't carry it, the demo app's ordinary state, or this is a
    /// development build parked off Private Cloud Compute
    /// (`AskDevelopmentPark`): a test host or `swift test` runner, a Debug
    /// build, a simulator, or a development-signed binary.
    case notEntitled
    /// The hardware cannot run it.
    case deviceNotEligible
    /// It needs a network the device does not have.
    case offline
    /// It is up and cannot write the app's language.
    case languageNotSupported
    /// Anything else, including a reason newer than this build.
    case unavailable

    /// The state, from the three fields the mirror publishes.
    ///
    /// Quota outranks unavailability: a tier at its limit is *up*, and telling
    /// the reader it is unavailable would send them looking for a setting that
    /// wouldn't help.
    ///
    /// - Parameters:
    ///   - quotaReached: Whether the day's quota is spent.
    ///   - quotaApproaching: Whether it is nearly spent.
    ///   - unavailability: Why Private Cloud Compute can't serve, or nil
    ///     while it can.
    /// - Returns: The state the card shows.
    public static func of(
        quotaReached: Bool,
        quotaApproaching: Bool,
        unavailability: AskUnavailability?
    ) -> AskPrivateCloudState {
        if quotaReached { return .limitReached }
        switch unavailability {
        case .notEntitled: return .notEntitled
        case .deviceNotEligible: return .deviceNotEligible
        case .offline: return .offline
        case .languageNotSupported: return .languageNotSupported
        case .appleIntelligenceOff, .modelNotReady, .systemNotReady, .unknown: return .unavailable
        case nil: return quotaApproaching ? .approachingLimit : .serving
        }
    }

    /// The state for `status`, from its quota and the reason Private Cloud
    /// Compute can't serve. On the main actor, where the mirror is read.
    ///
    /// A mirror its seam hasn't published to yet reads `.serving` here, since
    /// it names no reason; the card shows no state until it has
    /// (`shown(for:)`).
    ///
    /// - Parameter status: The mirror the engine's seam publishes.
    /// - Returns: The state the card shows.
    @MainActor
    public static func of(_ status: AskModelStatus) -> AskPrivateCloudState {
        of(
            quotaReached: status.quotaReached,
            quotaApproaching: status.quotaApproaching,
            unavailability: status.privateCloudUnavailability
        )
    }

    /// The state the card shows for `status`, or nil until its seam has
    /// published to it (`AskModelStatus.hasHeardFromSeam`).
    ///
    /// **Nil, not `.serving`.** A mirror nobody has published to names no
    /// reason, and no reason is what a serving tier looks like: a settings
    /// screen opened before the Ask screen would say Private Cloud Compute is
    /// available, with a green dot, on a build that has no entitlement or is
    /// parked off the tier.
    @MainActor
    static func shown(for status: AskModelStatus) -> AskPrivateCloudState? {
        status.hasHeardFromSeam ? of(status) : nil
    }

    /// Whether the tier can take a question right now: `.serving` or
    /// `.approachingLimit`.
    public var isServing: Bool {
        self == .serving || self == .approachingLimit
    }

    /// The sentence the card shows for this state.
    ///
    /// - Parameter resetDate: When the quota comes back. Read by
    ///   `.limitReached` alone, and ignored elsewhere. Its time for a reset
    ///   later today, its day and time for one on a later day, and nothing
    ///   for one already past.
    /// - Returns: The sentence, localized.
    public func message(resetDate: Date? = nil) -> String {
        switch self {
        case .serving:
            return String(localized: "Private Cloud Compute is available.", bundle: #bundle,
                          comment: "Settings line: Apple's Private Cloud Compute can answer questions right now.")
        case .approachingLimit:
            return String(localized: "Private Cloud Compute is near today's limit.", bundle: #bundle,
                          comment: "Settings line: the daily Private Cloud Compute quota is nearly spent. Nothing changes until it is.")
        case .limitReached:
            // The quota banner's line, word for word: AskCore's sentence, the
            // one the thread shows when a turn fails on the quota, and when it
            // resets by the day it falls on. Two copies drift.
            return AskQuotaBanner.line(resetDate: resetDate)
        case .notEntitled:
            return String(localized: "Private Cloud Compute isn't enabled in this build.", bundle: #bundle,
                          comment: "Settings line: the running app does not carry the Private Cloud Compute entitlement, so answers come from the on-device model.")
        case .deviceNotEligible:
            return String(localized: "Private Cloud Compute isn't available on this device.", bundle: #bundle,
                          comment: "Settings line: the hardware cannot use Private Cloud Compute.")
        case .offline:
            return String(localized: "Private Cloud Compute needs a network connection.", bundle: #bundle,
                          comment: "Settings line: Private Cloud Compute cannot be reached because the device is offline.")
        case .languageNotSupported:
            // AskCore's line, already written for exactly this: the tier is on
            // and simply cannot write this language.
            return AskError.unavailableMessage(.languageNotSupported)
        case .unavailable:
            return String(localized: "Private Cloud Compute isn't available right now.", bundle: #bundle,
                          comment: "Settings line: Private Cloud Compute cannot serve for a reason the app cannot name — not yet ready, or newer than this build.")
        }
    }
}

/// The Settings → Ask card: where answers come from, and what to do when Apple
/// has an option to offer.
///
/// **No toggle.** Private Cloud Compute serves every turn it can and the
/// on-device model serves the rest. That is house rule 1, and a switch here
/// would be a second, contradictory answer to a question the engine decides
/// on every turn. The card reports, and the navigation bar over the thread
/// says which tier is answering.
///
/// Made from the store, and not generic over its domain: it lives in an app's
/// settings, a long way from the Ask screen, and takes from the store only
/// what it shows and does: the one mirror the seam publishes, the route to a
/// higher limit, and the feedback attachments the store's thumbs kept, read
/// through the store, so the card lists them wherever the store keeps them.
///
/// From the top, it shows:
/// - a dot and a sentence for the state (`AskPrivateCloudState`), once the
///   mirror has heard from its seam (`AskPrivateCloudState.shown(for:)`);
/// - "Show options", once the day's quota is spent, where Apple offers a way
///   to ask for more;
/// - a line on where answers come from;
/// - with diagnostics on, a row that runs the host's evaluation, where the
///   host passed `onRunEval`;
/// - with diagnostics on, a row that shares the feedback attachments the
///   thumbs under answers kept, where there are any.
public struct AskPrivateCloudCard: View {
    private let status: AskModelStatus
    private let showsDiagnostics: Bool
    /// What "Show options" does: the store's route to a higher limit.
    private let onShowOptions: @Sendable () async -> Void
    private let onRunEval: (@Sendable () async -> String)?
    /// The store's own list of the feedback attachments, read through the
    /// attachments it was handed, so a store given another folder lists its
    /// own.
    private let listFeedback: @Sendable () async -> [URL]
    /// The store's count of changes to its attachments
    /// (`AskConversationStore.feedbackRevision`), read in the body so the
    /// list is read again when New Chat removes them or a verdict adds one.
    private let feedbackRevision: @MainActor () -> Int

    /// The evaluation the row runs, and its report: in the card's state, so
    /// it ends with the card and outlasts the row's coming and going
    /// (`AskEvalRun`).
    @State private var evalRun = AskEvalRun()
    @State private var feedbackAttachments: [URL] = []

    /// Creates the card for `store`: its mirror, its route to a higher limit
    /// (`showLimitIncrease()`), and the feedback attachments its thumbs kept,
    /// read through the store and again whenever it adds or removes one.
    ///
    /// - Parameters:
    ///   - store: The store whose mirror the card reads.
    ///   - showsDiagnostics: Whether the two developer rows can show, the
    ///     evaluation and the feedback attachments, whose copy is English
    ///     alone. Defaults to `AskDiagnostics.isEnabled`.
    ///   - onRunEval: Runs the host's evaluation and returns its report, such
    ///     as `AskEval`'s table. The row shows the report monospaced and
    ///     selectable, and offers to share it. Nil for no row.
    public init<Domain: AskDomain>(
        store: AskConversationStore<Domain>,
        showsDiagnostics: Bool = AskDiagnostics.isEnabled,
        onRunEval: (@Sendable () async -> String)? = nil
    ) {
        status = store.status
        self.showsDiagnostics = showsDiagnostics
        onShowOptions = { [store] in await store.showLimitIncrease() }
        self.onRunEval = onRunEval
        listFeedback = { [store] in await store.feedbackAttachmentURLs() }
        feedbackRevision = { [store] in store.feedbackRevision }
    }

    /// The state the card shows, or nil while the mirror knows nothing.
    private var state: AskPrivateCloudState? { .shown(for: status) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // No line at all until the mirror knows something, rather than a
            // claim it can't back (`AskPrivateCloudState.shown(for:)`).
            if let state {
                statusLine(state)
            }
            if status.quotaReached, status.hasLimitIncreaseSuggestion {
                Button {
                    Task { await onShowOptions() }
                } label: {
                    Text("Show options", bundle: #bundle, comment: "Button that opens Apple's route to request a higher Private Cloud Compute limit.")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                // The label is the tint, and the system blue on the style's
                // gray is under 4.5:1 in both appearances; `.primary` is what
                // the confirmation card's "Not now" wears on the same gray,
                // for the same reason, and the fill still marks it a button.
                .tint(.primary)
                .accessibilityIdentifier(AskAccessibility.privateCloudShowOptions)
            }
            explanation
            if showsDiagnostics, let onRunEval {
                evalRow(onRunEval)
            }
            if showsDiagnostics, !feedbackAttachments.isEmpty {
                feedbackRow
            }
        }
        .accessibilityElement(children: .contain)
        // Read once the card is up, off the main actor, in the attachments'
        // own actor, and again whenever the store adds or removes one. Only
        // where the row can show, so a card with diagnostics off never looks.
        .task(id: feedbackRevision()) {
            guard showsDiagnostics else { return }
            feedbackAttachments = await listFeedback()
        }
    }

    /// The attachments `logFeedbackAttachment` produced, for a Feedback
    /// Assistant report. Developer copy, shown only with diagnostics on, as
    /// the evaluation row is, and verbatim for the same reason.
    @ViewBuilder
    private var feedbackRow: some View {
        Divider()
        ShareLink(items: feedbackAttachments) {
            Text(verbatim: "Share feedback attachments (\(feedbackAttachments.count))")
        }
        .accessibilityIdentifier(AskAccessibility.privateCloudShareFeedback)
    }

    private func statusLine(_ state: AskPrivateCloudState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Self.dotColor(for: state))
                .frame(width: 8, height: 8)
                // The color is decoration: the sentence beside it already says
                // everything the dot encodes, and a spoken "green circle" adds
                // nothing but a word.
                .accessibilityHidden(true)
            Text(state.message(resetDate: status.resetDate))
                .font(.subheadline)
                .askDeemphasizedText()
        }
    }

    private static func dotColor(for state: AskPrivateCloudState) -> Color {
        switch state {
        case .serving: .green
        case .approachingLimit: .yellow
        case .limitReached: .orange
        case .notEntitled, .deviceNotEligible, .offline, .languageNotSupported, .unavailable: .gray
        }
    }

    /// The one sentence that says where answers come from, beside the glyph of
    /// the system they come from.
    private var explanation: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "apple.intelligence")
                .font(.caption)
                .accessibilityHidden(true)
            Text("Answers come from Apple's Private Cloud Compute whenever it can serve, and from the on-device model when it can't.", bundle: #bundle, comment: "Settings explanation under the Ask status line: which model answers a question, and when.")
                .font(.caption)
        }
        .askDeemphasizedText()
    }

    // MARK: - The evaluation row

    /// Runs the host's evaluation, such as `AskEval`'s scenarios through the
    /// real engine on whatever tier is serving, and hands the report out.
    ///
    /// Deliberately not a sheet: the report is a few hundred characters of
    /// Markdown, and a `ShareLink` that appears once there is something to
    /// share is one control instead of a presentation.
    ///
    /// **The evaluation ends with the card, and only with it.** It runs in a
    /// task the card's state holds (`AskEvalRun`), which the state's going
    /// cancels, so leaving Settings stops a run that would otherwise go on
    /// generating, spending Private Cloud Compute's quota where that serves,
    /// for a report nothing would show. The row's coming and going leaves it
    /// running: tied to the row's appearance, as a `.task(id:)` ties it, a row
    /// scrolled away and back, or under a page pushed and popped, would start
    /// it over while it was still asked for, and spend the quota again.
    @ViewBuilder
    private func evalRow(_ run: @escaping @Sendable () async -> String) -> some View {
        let isRunningEval = evalRun.isRunning
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Button {
                evalRun.start(run)
            } label: {
                HStack(spacing: 8) {
                    // Verbatim throughout this row: it is developer copy,
                    // shown only with diagnostics on, and "Ask eval" is a term
                    // of art. Translating it would be false precision in
                    // twenty-four locales.
                    Text(verbatim: "Run Ask eval on this device")
                    if isRunningEval { ProgressView().controlSize(.small) }
                }
            }
            .disabled(isRunningEval)
            .accessibilityIdentifier(AskAccessibility.privateCloudRunEval)
            if let evalReport = evalRun.report {
                ShareLink(item: evalReport) {
                    Text(verbatim: "Share results")
                }
                .accessibilityIdentifier(AskAccessibility.privateCloudShareResults)
                Text(verbatim: evalReport)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}

/// The evaluation `AskPrivateCloudCard`'s row runs, and the report it last
/// gave: one run at a time, and over when the card goes.
///
/// **An object in the card's state, so the run's life is the card's.** The
/// task is the object's, and the object's going, with the state that holds
/// it, cancels it. The task holds the object weakly, so a run under way never
/// keeps the card's state alive past the card.
@MainActor
@Observable
final class AskEvalRun {
    /// The report of the last run that finished, or nil before one has.
    private(set) var report: String?
    /// Whether a run is under way.
    private(set) var isRunning = false
    /// The run under way, or nil.
    @ObservationIgnored private(set) var task: Task<Void, Never>?

    /// Runs `body`, unless a run is already under way, which goes on as it
    /// was: one evaluation spends the quota once.
    ///
    /// - Parameter body: Runs the host's evaluation and returns its report.
    func start(_ body: @escaping @Sendable () async -> String) {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            let report = await body()
            // Gone with the card, the run reports to nothing.
            guard let self else { return }
            self.report = report
            isRunning = false
            task = nil
        }
    }

    deinit {
        task?.cancel()
    }
}

#endif
