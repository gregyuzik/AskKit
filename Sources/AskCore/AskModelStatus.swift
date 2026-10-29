import Foundation
import Observation

/// Whether one tier can serve, and why not when it can't.
///
/// Every turn reads all of these from **one** snapshot, so the tier that is
/// chosen, the fallback that stands behind it and the reason the reader is
/// told can't disagree with each other, as two reads of the system in the
/// middle of a failure could.
nonisolated public struct AskTierState: Sendable, Equatable {
    /// The tier this state is for.
    public let tier: AskTier
    /// The model itself reports it can serve.
    public let isAvailable: Bool
    /// It can write in the app's language.
    public let speaksLanguage: Bool
    /// The daily quota is spent: Private Cloud Compute only.
    public let quotaReached: Bool
    /// A failure cooled this tier (a transport failure, or a rate limit until
    /// the reset it named), and the cooldown hasn't lifted.
    public let isCooled: Bool
    /// Why not, when `isAvailable` is false.
    public let unavailability: AskUnavailability?

    /// A tier's state with each field as given. A seam builds one per tier
    /// for `AskModelSeam.tierStates()`.
    public init(
        tier: AskTier,
        isAvailable: Bool,
        speaksLanguage: Bool,
        quotaReached: Bool = false,
        isCooled: Bool = false,
        unavailability: AskUnavailability? = nil
    ) {
        self.tier = tier
        self.isAvailable = isAvailable
        self.speaksLanguage = speaksLanguage
        self.quotaReached = quotaReached
        self.isCooled = isCooled
        self.unavailability = unavailability
    }

    /// Whether this tier can serve a turn starting now: available, speaking
    /// the app's language, with quota left and not cooling down.
    ///
    /// **An approaching quota never demotes anything.** Only a reached one
    /// excludes Private Cloud Compute at a turn's start, and a limit hit
    /// mid-turn is an outage the turn is handed down from.
    ///
    /// A tier held off only by a cooldown or a spent quota isn't servable,
    /// and still takes a turn that nothing servable can (`askHeldTier(from:)`):
    /// a cooled one is asked, and a spent one fails it at once as its quota.
    public var isServable: Bool {
        isAvailable && speaksLanguage && !quotaReached && !isCooled
    }
}

/// The tiers that can serve a turn starting now, in preference order.
///
/// A list, not one tier: `AskContinuation.shouldContinue` asks whether the
/// tier holding a kept session is still the *first* servable one, and a kept
/// on-device conversation must be dropped the moment Private Cloud Compute is
/// back, with a recap, on the better model. `first` is what a turn runs on;
/// the next is what an outage hands the turn down to. With none, a turn goes
/// to the held tier, if there is one (`askHeldTier(from:)`).
nonisolated func askServableTiers(from states: [AskTierState]) -> [AskTier] {
    states.filter(\.isServable).map(\.tier)
}

/// Why nothing can serve, from the same snapshot the tier choice read.
///
/// **Language outranks availability.** A tier that is up and doesn't speak
/// the app's language is the one case where "turn on Apple Intelligence" is
/// not merely unhelpful but wrong: it is already on. Hebrew is such a case,
/// and it is why this test comes first.
///
/// Otherwise the on-device tier's reason is the honest one. It is the tier
/// every eligible device has, and it answers with the distinction that
/// matters (off, ineligible, still downloading), where Private Cloud Compute
/// can be out for reasons of its own that say nothing about whether Ask could
/// work at all.
///
/// **Never asked while Private Cloud Compute is only held.** A tier held off
/// by a cooldown or a spent quota takes the turn (`askHeldTier(from:)`), and
/// the mirror names it: its reason would tell the reader to wait for a
/// download, or that nothing can be done, with no Try Again.
nonisolated func askUnavailability(from states: [AskTierState]) -> AskUnavailability {
    if states.contains(where: { $0.isAvailable && !$0.speaksLanguage }) { return .languageNotSupported }
    let tier = states.first { $0.tier == .onDevice } ?? states.first
    return tier?.unavailability ?? .unknown
}

/// Private Cloud Compute's state, when the tier is up and speaks the app's
/// language and only a cooldown or a spent quota keeps it out: the tier a
/// turn goes to when nothing is servable. Nil when it is down anyway, doesn't
/// speak the language, or isn't held. Only this one test decides it: the
/// engine reads it for the turn, and `AppleModelSeam.snapshot(from:)` for the
/// mirror's next tier (`AskModelStatus.nextTier`), so the caption and the
/// first screen agree with what the next question does.
///
/// **A hold is the tier saying "not now", not "can't".** House rule 1: an
/// outage with nowhere to hand down is the turn's error, which Try Again
/// retries. So a turn after the hold fails, if it fails, as that outage did,
/// retryably, and not with the on-device tier's reason
/// (`askUnavailability(from:)`), which offers no Try Again. Nor does the
/// mirror name a reason, which would put up the can't-serve first screen
/// after New Chat, in the on-device tier's words, for a hold that lifts in a
/// minute or at the quota's reset.
///
/// - A **cooldown** is asked through: a network that went out may be back,
///   and a tier that is back answers. One still out fails the turn as
///   unreachable.
/// - A **spent quota** is asked nothing: until its reset every request could
///   only fail as the quota, and each would spend one. The turn fails at once
///   as `.quotaReached`, beside the banner that says when it resets, and a
///   spent quota that is cooled as well is the same.
nonisolated func askHeldTier(from states: [AskTierState]) -> AskTierState? {
    guard let cloud = states.first(where: { $0.tier == .privateCloud }),
          cloud.isAvailable, cloud.speaksLanguage, cloud.isCooled || cloud.quotaReached else { return nil }
    return cloud
}

/// Whether a triaged failure says the *tier* can't serve right now, as
/// against saying something about the question: the line the hand-down is
/// drawn on.
///
/// Out: an unreachable Private Cloud Compute and a spent quota are the tier
/// saying "not now", and the tier below is unaffected by both, so the turn is
/// handed down rather than failed.
///
/// Not out: a refusal (a smaller model reaches the same verdict), an overflow
/// (the fallback's window is four times smaller, so it overflows harder), an
/// ungrounded answer, a photo the session can't take (the tier below reads no
/// photos at all), and `model(tag:)`, which is unclassified by definition and
/// must not become a license to run every unknown failure again on a second
/// model.
nonisolated func askIsTierOutage(_ error: AskError) -> Bool {
    switch error {
    case .privateCloudUnreachable, .quotaReached: return true
    case .modelUnavailable, .couldNotAnswer, .ungrounded, .refused,
         .contextTooLarge, .photosNotSupported, .model, .stopped: return false
    }
}

/// What the screen reads about the tiers: the mirror, a main-actor copy of
/// the seam's state and of which tier serves next, refreshed after every
/// probe and every turn.
///
/// Behind no platform gate: it needs only Observation, so a host's shared
/// code can name it on tvOS and watchOS too. No AskKit seam publishes to it
/// there, since `AppleModelSeam` is built only where a model runs, so there
/// it stays as it began, unheard (`hasHeardFromSeam`), unless a seam of the
/// host's own calls `apply(_:)`.
@Observable
@MainActor
public final class AskModelStatus {
    /// The tier the next question will run on, or nil when none can serve.
    /// On an empty thread, the first screen then says why, and the composer
    /// is disabled unless the domain answers without a model
    /// (`AskFirstScreenPolicy.answersWithoutModel`).
    ///
    /// With nothing servable, a Private Cloud Compute held off only by a
    /// cooldown or a spent quota is still the next tier, since the next
    /// question goes to it (`askHeldTier(from:)`): an outage with nowhere to
    /// hand down is the turn's error, which Try Again retries (house rule 1),
    /// and a hold that lifts in a minute, or at the quota's reset, is no
    /// reason nothing can serve. A cooled tier is asked again. A spent one is
    /// asked nothing until its reset: the question fails at once as its
    /// quota, retryably, and `quotaReached` says the quota is spent beside it.
    public private(set) var nextTier: AskTier?
    /// Why, when `nextTier` is nil. Always nil while `nextTier` is set
    /// (`apply(_:)`).
    public private(set) var unavailability: AskUnavailability?
    /// Whether a seam has published to this mirror yet (`apply(_:)`).
    ///
    /// **Until it has, the mirror knows nothing, and reads as serving.** A
    /// new mirror has no tier and no reason, and a nil reason is what a tier
    /// serving looks like. So a reader of it that would say something about
    /// the tiers waits on this: the first screen, which would otherwise offer
    /// the ready screen's starters on a device that can't serve for the length
    /// of a Private Cloud Compute probe, and the settings card, which would
    /// say Private Cloud Compute is available on a build that has none.
    public private(set) var hasHeardFromSeam = false
    /// The daily Private Cloud Compute quota is close to spent. Shown, never
    /// acted on: an approaching quota demotes nothing.
    public private(set) var quotaApproaching = false
    /// The daily Private Cloud Compute quota is spent, or held until its
    /// reset after a failure said so. The screen shows a banner, and until the
    /// reset, questions go to the on-device model when it can serve, and fail
    /// at once as the quota, with `resetDate`, when it can't.
    public private(set) var quotaReached = false
    /// When the quota resets, when that is known.
    public private(set) var resetDate: Date?
    /// Why Private Cloud Compute itself can't serve, or nil while the tier is
    /// up: for a settings surface, which has to say something about the tier
    /// even when the tier below it is answering perfectly well.
    ///
    /// **Not the same question as `unavailability`,** which is only populated
    /// when *nothing* can serve. On-device answering because Private Cloud
    /// Compute is unentitled, offline or not yet ready is the ordinary case,
    /// and `unavailability` is nil throughout it.
    ///
    /// A spent quota isn't here: it has `quotaReached`, because a tier at its
    /// limit is up and simply out of turns for the day. A transport cooldown
    /// isn't here either: it lifts in a minute, and a settings card that named
    /// it would be stale before it was read.
    public private(set) var privateCloudUnavailability: AskUnavailability?
    /// Apple has a limit-increase route to offer. `showLimitIncrease()` on the
    /// seam opens it.
    public private(set) var hasLimitIncreaseSuggestion = false

    /// A mirror that reads as nothing known yet: no tier, no reason, no
    /// quota, and `hasHeardFromSeam` false. The seam it is handed to fills
    /// it.
    public init() {}

    /// What a seam publishes in one go (`apply(_:)`): every field of the
    /// mirror.
    nonisolated public struct Snapshot: Sendable, Equatable {
        /// `AskModelStatus.nextTier`.
        public var nextTier: AskTier?
        /// `AskModelStatus.unavailability`: why nothing can serve, for a
        /// snapshot with no `nextTier`. Ignored beside one (`apply(_:)`).
        public var unavailability: AskUnavailability?
        /// `AskModelStatus.quotaApproaching`.
        public var quotaApproaching = false
        /// `AskModelStatus.quotaReached`.
        public var quotaReached = false
        /// `AskModelStatus.resetDate`.
        public var resetDate: Date?
        /// `AskModelStatus.hasLimitIncreaseSuggestion`.
        public var hasLimitIncreaseSuggestion = false
        /// `AskModelStatus.privateCloudUnavailability`.
        public var privateCloudUnavailability: AskUnavailability?

        /// A snapshot with each field as given.
        public init(
            nextTier: AskTier? = nil,
            unavailability: AskUnavailability? = nil,
            quotaApproaching: Bool = false,
            quotaReached: Bool = false,
            resetDate: Date? = nil,
            hasLimitIncreaseSuggestion: Bool = false,
            privateCloudUnavailability: AskUnavailability? = nil
        ) {
            self.nextTier = nextTier
            self.unavailability = unavailability
            self.quotaApproaching = quotaApproaching
            self.quotaReached = quotaReached
            self.resetDate = resetDate
            self.hasLimitIncreaseSuggestion = hasLimitIncreaseSuggestion
            self.privateCloudUnavailability = privateCloudUnavailability
        }
    }

    /// Publish a seam's reading, every field at once, and with it that the
    /// mirror has heard from its seam (`hasHeardFromSeam`). `AppleModelSeam`
    /// calls it from `refreshStatus()`, and a seam of a host's own calls it
    /// the same way.
    ///
    /// **A tier to serve wins over a reason none can.** A snapshot with both
    /// says two contradictory things, and the mirror keeps `nextTier` and
    /// drops `unavailability`: the tier was read as servable, and a reason
    /// beside it would put the can't-serve screen over a tier that answers.
    public func apply(_ snapshot: Snapshot) {
        nextTier = snapshot.nextTier
        unavailability = snapshot.nextTier == nil ? snapshot.unavailability : nil
        quotaApproaching = snapshot.quotaApproaching
        quotaReached = snapshot.quotaReached
        resetDate = snapshot.resetDate
        hasLimitIncreaseSuggestion = snapshot.hasLimitIncreaseSuggestion
        privateCloudUnavailability = snapshot.privateCloudUnavailability
        hasHeardFromSeam = true
    }
}
