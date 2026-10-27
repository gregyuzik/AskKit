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
    ///   `.limitReached` alone, and ignored elsewhere.
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
            // The same words the thread shows when a turn fails on the quota,
            // from AskCore's catalog. Two copies of one sentence drift.
            let reached = AskError.quotaReached(resetDate: resetDate).errorDescription ?? ""
            guard let resetDate else { return reached }
            let resets = String(
                localized: "It resets at \(resetDate.formatted(date: .omitted, time: .shortened)).",
                bundle: #bundle,
                comment: "Follows the Private Cloud Compute limit line: the time of day the daily limit comes back. The placeholder is a time alone, such as 5:00 PM."
            )
            // With no space after a full-width full stop (`AskSentences`).
            return AskSentences.joined(reached, resets)
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
/// would be a second, contradictory answer to a question the engine has
/// already settled. The card reports, and the navigation bar over the thread
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

    @State private var evalReport: String?
    /// The evaluation the button asked for, while it runs: the identity of its
    /// `.task(id:)`, so it ends with the card. Nil while none runs.
    @State private var evalRun: UUID?
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
    /// **The evaluation ends with the card.** It runs in the row's
    /// `.task(id:)`, which is cancelled as the card goes, so leaving Settings
    /// stops a run that would otherwise go on generating, spending Private
    /// Cloud Compute's quota where that serves, for a report nothing would
    /// show, and coming back couldn't start a second beside it.
    @ViewBuilder
    private func evalRow(_ run: @escaping @Sendable () async -> String) -> some View {
        let isRunningEval = evalRun != nil
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Button {
                evalRun = UUID()
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
            if let evalReport {
                ShareLink(item: evalReport) {
                    Text(verbatim: "Share results")
                }
                .accessibilityIdentifier(AskAccessibility.privateCloudShareResults)
                Text(verbatim: evalReport)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .task(id: evalRun) {
            // Also run as the row appears, with nothing asked for.
            guard evalRun != nil else { return }
            let report = await run()
            // A run the card's going cancelled reports to nothing.
            guard !Task.isCancelled else { return }
            evalReport = report
            evalRun = nil
        }
    }
}

#endif
