#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)

import Foundation
import FoundationModels
import Network
import os
import Synchronization

/// The `AskModelSeam` for Apple's two tiers, on Foundation Models: one
/// availability cache, one cooldown, one quota hold, one generation gate and
/// one mirror for the process.
///
/// A host that already routes its own model calls bridges its router to
/// `AskModelSeam` instead, so its other features and Ask keep sharing one
/// cooldown and one generation gate.
///
/// **This is the only place the Private Cloud Compute model is constructed**,
/// and no request leaves it unless the host declared the entitlement
/// (`AskPrivateCloudCompute`) and the running build doesn't prove it absent
/// (`AskProcessEntitlements`). An unentitled request is a fatal trap, while
/// constructing the model and reading its availability are safe, and
/// `availability` reads `.available` without the entitlement, so the
/// declaration and the build's own entitlements are the check, not the
/// availability probe.
///
/// **Nor from a development build** (`AskDevelopmentPark`): a test host, a
/// `swift test` runner, a Debug build, a simulator or a development-signed
/// binary reads the tier as `.notEntitled` and sends it nothing (no session,
/// no prewarm, no locale probe, no context-size read), unless the run opts
/// back in: `ASK_LIVE_PCC=1` in the environment, `-ASK_LIVE_PCC YES` as a
/// launch argument, or the host's `AskDevelopmentPark.setAppOptIn(_:)`. The
/// daily quota is the developer's own.
public actor AppleModelSeam: AskModelSeam {
    private let logger: Logger

    /// How long a transient probe answer is served from cache before the next
    /// ask re-probes. A terminal one is never re-probed. A locale probe or a
    /// context-window read that couldn't say is remembered as no answer for as
    /// long.
    nonisolated public static let reprobeInterval: TimeInterval = 60
    /// How long Private Cloud Compute sits out after a transport failure that
    /// did not say when to come back, so a burst of questions on a bad
    /// connection does not wait on it every time. A rate limit that names its
    /// reset is held until then instead.
    nonisolated public static let transportCooldown: TimeInterval = 60

    /// The mirror this seam publishes to.
    public nonisolated let status: AskModelStatus

    /// Whether the host declared the entitlement.
    private let privateCloudCompute: AskPrivateCloudCompute
    private var cachedModel: PrivateCloudComputeLanguageModel?
    /// Every time below is on `now`, a monotonic clock, so a wall clock set
    /// back can't stretch a hold or keep a probe answer past its interval.
    /// A date the tier gives is turned into an instant once, when it is
    /// noted (`holdEnd(until:wallNow:now:)`).
    private var probe: (at: ContinuousClock.Instant, available: Bool, terminal: Bool, reason: AskUnavailability?)?
    private var cooledUntil: ContinuousClock.Instant?
    /// The day's quota, spent: held until the reset the failure (or the
    /// model's quota usage) named, so no turn is spent learning it again.
    private var quotaHeldUntil: ContinuousClock.Instant?
    private var hasLoggedRefusal = false
    private var hasLoggedPark = false
    /// Private Cloud Compute's locale probe, by locale. See
    /// `speaksAppLanguage(_:locale:)`.
    private let localeProbes: AskSharedRead<String, Bool>
    /// Private Cloud Compute's context window. See `privateCloudWindow(of:)`.
    private let windowRead: AskSharedRead<AskTier, Int>
    /// Whether the on-device model writes a locale, by locale: a local read,
    /// so never more than kept, and kept only while it can't go stale
    /// (`onDeviceSpeaks(_:)`).
    private var onDeviceLocaleSupport: [String: Bool] = [:]
    /// The on-device model's availability when `onDeviceLocaleSupport` was
    /// read, or nil before the first read of it.
    private var onDeviceLocaleReadsUnder: SystemLanguageModel.Availability?
    /// The on-device model's availability, read off the seam's actor
    /// (`systemAvailability()`), unless a test scripts it.
    private let onDeviceAvailability: @Sendable () async -> SystemLanguageModel.Availability
    /// Whether the on-device model writes a locale, read off the seam's actor
    /// (`systemSupportsLocale(_:)`), unless a test scripts it.
    private let onDeviceSupportsLocale: @Sendable (Locale) async -> Bool
    /// The monotonic clock the seam's holds and probe are timed on.
    private let now: @Sendable () -> ContinuousClock.Instant
    /// The refreshes begun, and the newest whose reading the mirror took. A
    /// refresh reads the tiers over several awaits, so two that overlap can
    /// finish in either order, and the older one's reading must not land
    /// over the newer's (`refreshStatus()`). The second is read and written
    /// only on the main actor, beside the mirror.
    private var refreshesBegun: UInt64 = 0
    private let newestRefreshApplied = Mutex<UInt64>(0)
    private let gate: AskGenerationGate
    private let monitor = NetworkReachability()

    /// How long one of Private Cloud Compute's reads, the locale probe or the
    /// context window, may run before it is abandoned and read as no answer
    /// (`AskSharedRead`): each is a network call, made at the start of a turn,
    /// so a stalled network can't hold the turn that asked.
    nonisolated static let privateCloudReadBound: Duration = .seconds(3)

    /// The seams alive in the process. More than one is the misuse
    /// "One per process" in `AskModelSeam` warns of, which `init` logs once.
    /// An actor's statics take no default isolation.
    nonisolated private static let census = Mutex(AskSeamCensus())

    /// A seam publishing to `status`.
    ///
    /// - Parameters:
    ///   - status: the mirror the screen reads, which the seam refreshes.
    ///   - privateCloudCompute: whether the app holds
    ///     `com.apple.developer.private-cloud-compute`. Required, because a
    ///     request from a process without it is a fatal trap, and a shipped
    ///     build can't read its own entitlements: declare it only when the
    ///     app's entitlements file grants it. `.undeclared` keeps every
    ///     question on the device. `.declared` lets Private Cloud Compute
    ///     serve, except where the running build proves the entitlement
    ///     absent, which is logged once: on the Mac or in a simulator, which
    ///     read it exactly, or on a device whose provisioning profile doesn't
    ///     grant it. It doesn't serve in a development build either
    ///     (`AskDevelopmentPark`).
    ///   - gate: the generation gate on-device generations wait at. The
    ///     default, `AskGenerationGate.shared`, is the one the process's other
    ///     on-device generations should use too.
    ///   - logSubsystem: the subsystem the seam logs under: the domain's
    ///     `AskBrand.logSubsystem`, so its lines sit with the engine's. Nil
    ///     logs under the app's bundle identifier.
    public init(
        status: AskModelStatus,
        privateCloudCompute: AskPrivateCloudCompute,
        gate: AskGenerationGate = .shared,
        logSubsystem: String? = nil
    ) {
        self.init(
            status: status, privateCloudCompute: privateCloudCompute, gate: gate, logSubsystem: logSubsystem,
            onDeviceAvailability: { await Self.systemAvailability() },
            onDeviceSupportsLocale: { await Self.systemSupportsLocale($0) },
            now: { .now }
        )
    }

    /// A seam whose on-device reads and clock are given: the system's in the
    /// public initializer, a test's script here.
    init(
        status: AskModelStatus,
        privateCloudCompute: AskPrivateCloudCompute,
        gate: AskGenerationGate,
        logSubsystem: String?,
        onDeviceAvailability: @escaping @Sendable () async -> SystemLanguageModel.Availability,
        onDeviceSupportsLocale: @escaping @Sendable (Locale) async -> Bool,
        now: @escaping @Sendable () -> ContinuousClock.Instant
    ) {
        self.status = status
        self.privateCloudCompute = privateCloudCompute
        self.gate = gate
        self.onDeviceAvailability = onDeviceAvailability
        self.onDeviceSupportsLocale = onDeviceSupportsLocale
        self.now = now
        let logger = Logger(subsystem: AskBrand.subsystem(logSubsystem), category: "seam")
        self.logger = logger
        let memory = Duration.seconds(Self.reprobeInterval)
        localeProbes = AskSharedRead(
            label: "locale probe for privateCloud", bound: Self.privateCloudReadBound, failureMemory: memory,
            logger: logger
        )
        windowRead = AskSharedRead(
            label: "context size read for privateCloud", bound: Self.privateCloudReadBound, failureMemory: memory,
            logger: logger
        )
        if Self.census.withLock({ $0.arrive() }) {
            logger.fault("""
                a second AppleModelSeam is alive in this process — one seam per process: two run two \
                cooldowns and two generation gates against one on-device model
                """)
        }
    }

    deinit {
        Self.census.withLock { $0.leave() }
    }

    /// A seam with a new mirror, for a caller with none of its own yet.
    /// `init(status:privateCloudCompute:gate:logSubsystem:)` says what to
    /// declare.
    @MainActor
    public static func make(
        privateCloudCompute: AskPrivateCloudCompute,
        gate: AskGenerationGate = .shared,
        logSubsystem: String? = nil
    ) -> AppleModelSeam {
        AppleModelSeam(
            status: AskModelStatus(), privateCloudCompute: privateCloudCompute, gate: gate,
            logSubsystem: logSubsystem
        )
    }

    // MARK: - Tier states

    /// Private Cloud Compute's state, then the on-device model's.
    public func tierStates() async -> [AskTierState] {
        [await privateCloudState(), await onDeviceState()]
    }

    private func privateCloudState() async -> AskTierState {
        guard mayReachPrivateCloud() else {
            return AskTierState(tier: .privateCloud, isAvailable: false, speaksLanguage: true,
                                unavailability: .notEntitled)
        }
        guard monitor.isConnected else {
            return AskTierState(tier: .privateCloud, isAvailable: false, speaksLanguage: true,
                                unavailability: .offline)
        }
        let available = probeAvailability()
        var quotaReached = isQuotaHeld
        if available, let model = model() {
            quotaReached = quotaReached || model.quotaUsage.isLimitReached
        }
        return AskTierState(
            tier: .privateCloud,
            isAvailable: available,
            speaksLanguage: available ? Self.speaksLanguage(probed: await speaksAppLanguage(.privateCloud)) : true,
            quotaReached: quotaReached,
            isCooled: isHeld(cooledUntil),
            unavailability: available ? nil : (probe?.reason ?? .unknown)
        )
    }

    /// Whether anything may go to Private Cloud Compute: the host declared the
    /// entitlement, the build doesn't prove it absent
    /// (`AskProcessEntitlements.privateCloudComputeRefusal(_:reading:)`), and
    /// the process isn't parked. Every read and request of the tier asks this
    /// first.
    ///
    /// The entitlement is weighed before the park, so the reason logged is the
    /// one that would still hold in a shipped build.
    private func mayReachPrivateCloud() -> Bool {
        if let refusal = AskProcessEntitlements.privateCloudComputeRefusal(
            privateCloudCompute, reading: AskProcessEntitlements.privateCloudComputeReading
        ) {
            if !hasLoggedRefusal {
                hasLoggedRefusal = true
                logger.notice("private cloud not entitled: \(refusal, privacy: .public)")
            }
            return false
        }
        return !isParked()
    }

    /// `AskDevelopmentPark`, with its reason logged once per process — a
    /// developer wondering why Ask answers on the device finds it in the log.
    private func isParked() -> Bool {
        guard let reason = AskDevelopmentPark.reason else { return false }
        if !hasLoggedPark {
            hasLoggedPark = true
            logger.info("private cloud parked: \(reason, privacy: .public) — \(AskDevelopmentPark.optInKey, privacy: .public)=1 opts in")
        }
        return true
    }

    private var isQuotaHeld: Bool {
        isHeld(quotaHeldUntil)
    }

    /// Whether a hold lifting at `until` is still on.
    private func isHeld(_ until: ContinuousClock.Instant?) -> Bool {
        (until.map { $0 > now() }) ?? false
    }

    /// Whether Private Cloud Compute is cooling down, and whether its spent
    /// quota is held. Test-facing: the tier's state reads both only where the
    /// tier may be reached, which no test process may.
    var holds: (isCooled: Bool, isQuotaHeld: Bool) {
        (isHeld(cooledUntil), isQuotaHeld)
    }

    private func onDeviceState() async -> AskTierState {
        let locale = Self.appLocale
        let availability = await onDeviceAvailability()
        keepLocaleReads(under: availability)
        switch availability {
        case .available:
            return AskTierState(tier: .onDevice, isAvailable: true, speaksLanguage: await onDeviceSpeaks(locale))
        case .unavailable(let why):
            let reason = Self.reason(from: why)
            // Only a model that says it is not ready is asked about the
            // language: that is the reason iOS gives for a language it cannot
            // write. Asked about the app's language, which the answer would be
            // written in, and about the system's (`Locale.current`) where the
            // two differ, since the system, not the app, said not ready: the
            // model not writing either is the language, not a download.
            var speaks = true
            if reason == .modelNotReady {
                speaks = await onDeviceSpeaks(locale)
                if speaks, locale.identifier != Locale.current.identifier {
                    speaks = await onDeviceSpeaks(.current)
                }
            }
            return Self.unavailableOnDeviceState(reason, speaksAppLanguage: speaks)
        @unknown default:
            return AskTierState(tier: .onDevice, isAvailable: false, speaksLanguage: true,
                                unavailability: .unknown)
        }
    }

    /// The on-device model's availability, read off the seam's actor: the
    /// first read can load a manifest, and the seam's other callers needn't
    /// wait on it. `@concurrent` rather than a detached task, so the read keeps
    /// its caller's priority and cancellation.
    @concurrent nonisolated private static func systemAvailability() async -> SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    nonisolated static func reason(from why: SystemLanguageModel.Availability.UnavailableReason) -> AskUnavailability {
        switch why {
        case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
        case .deviceNotEligible: return .deviceNotEligible
        case .modelNotReady: return .modelNotReady
        @unknown default: return .unknown
        }
    }

    /// The on-device tier when the model says it is unavailable.
    ///
    /// **"Not ready" in a language the model doesn't write means the
    /// language.** On an iOS 27 simulator, the demo launched in Hebrew read
    /// not ready twice, six minutes apart, while English answered on the same
    /// simulator in between. Under a Hebrew locale, the Mac reports the model
    /// `.available` with `supportsLocale` false, which `askUnavailability`
    /// reads as `.languageNotSupported`. Taken at its word, iOS would have the
    /// screen tell a Hebrew reader that Apple Intelligence is still
    /// downloading, a download that never finishes.
    ///
    /// Only `.modelNotReady` is re-read. Apple Intelligence turned off, or a
    /// device that cannot run it, is the first thing to fix in any language.
    nonisolated static func unavailableOnDeviceState(
        _ reason: AskUnavailability, speaksAppLanguage: Bool
    ) -> AskTierState {
        guard reason == .modelNotReady, !speaksAppLanguage else {
            return AskTierState(tier: .onDevice, isAvailable: false, speaksLanguage: true,
                                unavailability: reason)
        }
        return AskTierState(tier: .onDevice, isAvailable: false, speaksLanguage: false,
                            unavailability: .languageNotSupported)
    }

    /// The one place `PrivateCloudComputeLanguageModel.availability` is read.
    ///
    /// `.available` and `.deviceNotEligible` are terminal: the answer won't
    /// change while the process runs. Everything else is re-probed after
    /// `reprobeInterval`.
    private func probeAvailability() -> Bool {
        if let probe, probe.terminal || now() - probe.at < .seconds(Self.reprobeInterval) {
            return probe.available
        }
        guard let model = model() else {
            probe = (now(), false, true, .notEntitled)
            return false
        }
        let available: Bool
        let terminal: Bool
        let reason: AskUnavailability?
        switch model.availability {
        case .available:
            (available, terminal, reason) = (true, true, nil)
        case .unavailable(let why):
            switch why {
            case .deviceNotEligible:
                (available, terminal, reason) = (false, true, .deviceNotEligible)
            case .systemNotReady:
                (available, terminal, reason) = (false, false, .systemNotReady)
            @unknown default:
                (available, terminal, reason) = (false, false, .unknown)
            }
        }
        probe = (now(), available, terminal, reason)
        // "available" for no reason, so a healthy process's one line doesn't
        // read as the `unknown` an unnamed reason logs.
        logger.info("private cloud availability: \(reason.map { String(describing: $0) } ?? "available", privacy: .public)")
        return available
    }

    /// The model, constructed once, and only where the host declared the
    /// entitlement, the build doesn't prove it absent and the process isn't
    /// parked for development (`mayReachPrivateCloud()`). Every Private Cloud
    /// Compute read and request goes through here, which is how a process
    /// that fails any of those checks sends it nothing.
    private func model() -> PrivateCloudComputeLanguageModel? {
        guard mayReachPrivateCloud() else { return nil }
        if let cachedModel { return cachedModel }
        let model = PrivateCloudComputeLanguageModel()
        cachedModel = model
        return model
    }

    /// Whether the tier can write in the app's language (`appLocale`): nil
    /// when Private Cloud Compute's probe threw, ran past its bound, or did
    /// either within the last `reprobeInterval`, and so could not say.
    ///
    /// **Private Cloud Compute's probe is a network call**, so it goes through
    /// `AskSharedRead`, keyed by locale: one probe at a time however many
    /// callers overlap, an answer kept for the process (it changes with the
    /// OS, not with the minute), and no probe running past
    /// `privateCloudReadBound`. Keyed on the locale because the parameter
    /// exists to make the non-English path testable, and a single key hands
    /// the second locale the first one's answer.
    ///
    /// **A probe that couldn't say is not an answer**: it is never kept, only
    /// remembered as no answer for `reprobeInterval`, as a transient
    /// availability probe is, and each caller reads "could not say" its own
    /// way. The tier's state keeps the tier (`speaksLanguage(probed:)`) — a
    /// network blip must neither take Private Cloud Compute out of
    /// `askServableTiers` nor tell the reader their language is unsupported,
    /// which no Try Again gets past. The answer language degrades to English
    /// (`answerLanguage(for:probed:)`) rather than spend a request that bounces
    /// `unsupportedLanguageOrLocale`, which reaches `.modelUnavailable` and
    /// does not hand down.
    ///
    /// **English is not asked about** (`skipsPrivateCloudLocaleProbe`): the
    /// probe is a network call made just to open Ask, once per process, and
    /// English is the one answer that has never been in doubt.
    private func speaksAppLanguage(_ tier: AskTier, locale: Locale = AppleModelSeam.appLocale) async -> Bool? {
        switch tier {
        case .privateCloud:
            if Self.skipsPrivateCloudLocaleProbe(locale) { return true }
            guard let model = model() else { return false }
            return await localeProbes.value(for: locale.identifier) {
                try await Self.supportsLocale(locale, on: model)
            }
        case .onDevice:
            return await onDeviceSpeaks(locale)
        }
    }

    /// Whether the on-device model writes `locale`: a local read, but off the
    /// seam's actor (`systemSupportsLocale(_:)`), kept while it can't go
    /// stale.
    ///
    /// **A "no" read while the model isn't available is read again.** A
    /// model still downloading its assets can say no to a language it will
    /// write once they are in, and kept, that no would read as
    /// `.languageNotSupported`, which no Try Again gets past, until the app
    /// relaunched. A "yes" is kept, and so is a "no" from a model that is
    /// available (the Mac under a Hebrew locale), until the model's
    /// availability changes (`keepLocaleReads(under:)`).
    private func onDeviceSpeaks(_ locale: Locale) async -> Bool {
        if let kept = onDeviceLocaleSupport[locale.identifier] { return kept }
        let readUnder = onDeviceLocaleReadsUnder
        let supported = await onDeviceSupportsLocale(locale)
        // Unless the availability changed while the read ran: then the read
        // belongs to neither.
        if onDeviceLocaleReadsUnder == readUnder, supported || readUnder == .available {
            onDeviceLocaleSupport[locale.identifier] = supported
        }
        return supported
    }

    /// Drop the locale reads kept when the on-device model's availability is
    /// no longer the one they were read under: a download that finished, or
    /// one that began, can change which languages the model writes.
    private func keepLocaleReads(under availability: SystemLanguageModel.Availability) {
        guard onDeviceLocaleReadsUnder != availability else { return }
        onDeviceLocaleReadsUnder = availability
        onDeviceLocaleSupport = [:]
    }

    /// Private Cloud Compute's locale probe, run off the seam's actor.
    @concurrent nonisolated private static func supportsLocale(
        _ locale: Locale, on model: PrivateCloudComputeLanguageModel
    ) async throws -> Bool {
        try await model.supportsLocale(locale)
    }

    /// The on-device model's locale read, off the seam's actor, where its
    /// availability read is too: the first read of the model's languages can
    /// load a manifest.
    @concurrent nonisolated private static func systemSupportsLocale(_ locale: Locale) async -> Bool {
        SystemLanguageModel.default.supportsLocale(locale)
    }

    /// The language the app runs in, as the locale the tiers are asked about
    /// and the answer is written in: the main bundle's first preferred
    /// localization, the language AskUI's text and the host's are in.
    ///
    /// **Not the system's.** An app that doesn't ship the system's language
    /// runs in another. Asked about the system's, a tier that couldn't write
    /// it would take Ask down, with a line in the app's language saying the
    /// language wasn't supported.
    nonisolated static var appLocale: Locale {
        appLocale(preferredLocalizations: Bundle.main.preferredLocalizations, current: .current)
    }

    /// `appLocale`, from the bundle's preferred localizations and the system's
    /// locale. The system's locale when it is in the app's language and
    /// script, since it is the more exact of the two: it carries the region a
    /// "pt" localization is read in. The system's too when the bundle names
    /// nothing, or only `Base`, which is no language.
    nonisolated static func appLocale(preferredLocalizations: [String], current: Locale) -> Locale {
        guard let tag = preferredLocalizations.first, tag != "Base" else { return current }
        let app = likelyLanguage(tag)
        let system = likelyLanguage(current.language.maximalIdentifier)
        if app.languageCode == system.languageCode, app.script == system.script { return current }
        return Locale(identifier: tag)
    }

    nonisolated static func skipsPrivateCloudLocaleProbe(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "en"
    }

    /// Whether a tier's state says it writes the app's language, from what its
    /// locale probe said — nil when the probe couldn't say. A probe that threw
    /// or stalled said nothing about the language, so it takes nothing out:
    /// the turn finds out whether the network is there, and an unreachable
    /// tier hands down or can be tried again, where "language not supported"
    /// can do neither.
    nonisolated static func speaksLanguage(probed: Bool?) -> Bool {
        probed ?? true
    }

    /// The English name of the language the app runs in (`appLocale`), when
    /// `tier`'s locale probe confirmed the tier writes it. Nil for English,
    /// which needs no probe, and nil when the probe said no or couldn't say,
    /// so the answer is written in English.
    public func answerLanguage(for tier: AskTier) async -> String? {
        await answerLanguage(for: tier, locale: Self.appLocale)
    }

    /// `answerLanguage(for:)` for a given locale.
    func answerLanguage(for tier: AskTier, locale: Locale) async -> String? {
        // English is asked for by asking for nothing, and needs no probe.
        guard let code = locale.language.languageCode?.identifier, code != "en" else { return nil }
        return Self.answerLanguage(for: locale, probed: await speaksAppLanguage(tier, locale: locale))
    }

    /// The answer language, given what the locale probe said: the language's
    /// name only when the probe confirmed the tier writes it. A probe that said
    /// no, or couldn't say, degrades the answer to English rather than spend a
    /// request that bounces `unsupportedLanguageOrLocale`.
    nonisolated static func answerLanguage(for locale: Locale, probed: Bool?) -> String? {
        probed == true ? languageName(for: locale) : nil
    }

    /// The English name of the locale's language, or nil for English — with
    /// whatever the language's name alone leaves open, and nothing else.
    ///
    /// The script, when it is not the one the language, or the language in
    /// that region, is usually written in: "Chinese" alone can come back
    /// Simplified to a reader of Traditional. The region, when it is not the
    /// one the language and script imply: Portuguese in Portugal, French in
    /// Canada. So French stays "French", Brazilian Portuguese "Portuguese" and
    /// Simplified Chinese "Chinese". Built from the locale's language rather
    /// than its identifier, which can also carry a calendar or a region
    /// override that no answer is written in.
    nonisolated static func languageName(for locale: Locale) -> String? {
        let language = likelyLanguage(locale.language.maximalIdentifier)
        guard let code = language.languageCode?.identifier, code != "en" else { return nil }
        var tag = code
        if let script = language.script?.identifier, let region = language.region?.identifier {
            if likelyLanguage(code).script?.identifier != script
                || likelyLanguage("\(code)-\(region)").script?.identifier != script {
                tag += "-\(script)"
            }
            if likelyLanguage("\(code)-\(script)").region?.identifier != region {
                tag += "-\(region)"
            }
        }
        let english = Locale(identifier: "en")
        return english.localizedString(forIdentifier: tag) ?? english.localizedString(forLanguageCode: code)
    }

    /// A language tag with the script and region it most likely means filled
    /// in: "zh" is Simplified Chinese in China, "zh-Hant" Traditional Chinese
    /// in Taiwan, "pt" Portuguese in Brazil.
    nonisolated private static func likelyLanguage(_ tag: String) -> Locale.Language {
        Locale.Language(identifier: Locale.Language(identifier: tag).maximalIdentifier)
    }

    // MARK: - Sessions

    /// A session on `tier`, wrapped in `AppleAskSession`, with a planner on the
    /// same model for the grounded retry. Nil when Private Cloud Compute may
    /// not be reached (undeclared, proved absent or parked) or the on-device
    /// model isn't available. On device, an answer is capped at 1,024 tokens
    /// and a plan at 256 (`AppleAskSession.onDeviceAnswerCap` and
    /// `onDevicePlanCap`); Private Cloud Compute's sessions have no cap.
    public func makeSession(
        tier: AskTier,
        tools: [any Tool],
        instructions: String
    ) async throws -> AskSessionBox? {
        // The planner factory is bound to the SAME model the session runs on.
        // Building it here rather than inside `AppleAskSession` is what keeps
        // this the only place the Private Cloud Compute model is constructed,
        // and stops a Private Cloud Compute turn's grounded retry from planning
        // on the on-device model, which is a different model answering half the
        // question and a generation the generation gate never saw.
        switch tier {
        case .privateCloud:
            guard let model = model() else { return nil }
            let window = await privateCloudWindow(of: model)
            let session = Self.revertingOnFailure(
                LanguageModelSession(model: model, tools: tools, instructions: instructions)
            )
            return AskSessionBox(
                session: AppleAskSession(
                    session: session,
                    contextSize: window,
                    noteFailure: { [weak self] error in await self?.noteFailure(error) },
                    makePlanner: { planInstructions in
                        Self.revertingOnFailure(LanguageModelSession(model: model, instructions: planInstructions))
                    }
                ),
                tier: tier
            )
        case .onDevice:
            return await Self.makeOnDeviceSession(tools: tools, instructions: instructions)
        }
    }

    /// An on-device session, built off the seam's actor like
    /// `onDeviceAvailability()`'s read: this reads the model's availability
    /// again before it builds.
    @concurrent nonisolated private static func makeOnDeviceSession(
        tools: [any Tool], instructions: String
    ) async -> AskSessionBox? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = revertingOnFailure(LanguageModelSession(
            model: SystemLanguageModel.default, tools: tools, instructions: instructions
        ))
        // Capped, where Private Cloud Compute's session is not: a runaway
        // answer in an 8,192-token window reaches the overflow that throws the
        // turn away (`AskContinuation.onDeviceAnswerCap`).
        return AskSessionBox(
            session: AppleAskSession(
                session: session,
                contextSize: SystemLanguageModel.default.contextSize,
                answerCap: AskContinuation.onDeviceAnswerCap,
                planCap: AskContinuation.onDevicePlanCap
            ) { planInstructions in
                revertingOnFailure(LanguageModelSession(model: SystemLanguageModel.default, instructions: planInstructions))
            },
            tier: .onDevice
        )
    }

    /// `session`, set to put its transcript back as it was before a request
    /// that fails. The framework's default is undocumented, so it is said
    /// here: the engine starts a fresh session after any failed turn anyway,
    /// and a transcript that never holds half a failed exchange is the one a
    /// host's own reuse of the session can trust.
    nonisolated static func revertingOnFailure(_ session: LanguageModelSession) -> LanguageModelSession {
        session.transcriptErrorHandlingPolicy = .revertTranscript
        return session
    }

    /// Private Cloud Compute's context window, read once for the process.
    ///
    /// **Here, and not per turn.** The window is a property of the model, not
    /// of the minute, so one read serves every session the process builds.
    /// Read per turn, it would be an `async throws` read awaited before each
    /// follow-up's first token.
    ///
    /// A network call, so it is shared, bounded and remembered as the locale
    /// probe is (`AskSharedRead`). A read that couldn't say is not an answer
    /// and is never kept: the session is built without a window, and its turn
    /// count is then the only budget, which is what `maxTurns` is for.
    private func privateCloudWindow(of model: PrivateCloudComputeLanguageModel) async -> Int? {
        await windowRead.value(for: .privateCloud) { try await Self.contextSize(of: model) }
    }

    /// Private Cloud Compute's context window, read off the seam's actor.
    @concurrent nonisolated private static func contextSize(
        of model: PrivateCloudComputeLanguageModel
    ) async throws -> Int {
        try await model.contextSize
    }

    // MARK: - Cooldown, generation gate, mirror

    /// Cools Private Cloud Compute for `transportCooldown`, never shortening a
    /// hold already running, and republishes the mirror now and again when the
    /// hold lifts. An on-device failure changes nothing: that tier has no
    /// transport to cool.
    public func noteTransportFailure(on tier: AskTier) async {
        guard tier == .privateCloud else { return }
        let now = now()
        // Never shorter than a hold already running: the engine reports a rate
        // limit here too, after the session has already held the tier until
        // the reset the limit named (`noteFailure(_:)`).
        cooledUntil = Self.extendedHold(cooledUntil, to: now + .seconds(Self.transportCooldown), now: now)
        let held = (cooledUntil ?? now) - now
        logger.notice("transport failure — cooling private cloud for \(held.components.seconds, privacy: .public)s")
        await refreshStatus()
        refreshWhenHoldLifts(at: cooledUntil)
    }

    /// A Private Cloud Compute failure that says when the tier can be tried
    /// again, reported by the sessions this seam built: the raw error, before
    /// the engine triages it into an `AskError` that has no room for a date.
    ///
    /// A spent quota holds the tier until the day's reset, from the error or
    /// else from the model's quota usage: the turn it failed hands down on its
    /// own, and every turn after it would otherwise try Private Cloud Compute
    /// first and learn it again. A rate limit that named its reset cools the
    /// tier until then rather than for the minute an unannounced fault gets.
    /// Neither ever shortens a hold already running, nor runs past
    /// `longestHold`.
    func noteFailure(_ error: any Error) async {
        guard let retry = AskTriage.retryAfter(from: error) else { return }
        let now = now()
        let wallNow = Date.now
        let lifts: ContinuousClock.Instant?
        if retry.isQuota {
            let reset = Self.quotaReset(fromError: retry.date, fromUsage: model()?.quotaUsage.resetDate)
            quotaHeldUntil = Self.extendedHold(
                quotaHeldUntil, to: Self.holdEnd(until: reset, wallNow: wallNow, now: now), now: now
            )
            lifts = quotaHeldUntil
            logger.notice("quota reached — holding private cloud until its reset")
        } else {
            cooledUntil = Self.extendedHold(
                cooledUntil, to: Self.holdEnd(until: retry.date, wallNow: wallNow, now: now), now: now
            )
            lifts = cooledUntil
            logger.notice("rate limited — cooling private cloud until the reset it named")
        }
        // The hold is set; the mirror's refresh goes beside the turn whose
        // stream is about to throw, since it can wait on Private Cloud
        // Compute's probes and the hand-down shouldn't. The engine chose the
        // fallback from the turn's first read of the tiers.
        Task { [weak self] in await self?.refreshStatus() }
        refreshWhenHoldLifts(at: lifts)
    }

    /// Republish the mirror when a hold lifts, so the tier caption comes back
    /// on its own rather than waiting for the next question.
    private func refreshWhenHoldLifts(at lifts: ContinuousClock.Instant?) {
        guard let lifts else { return }
        let wait = lifts - now()
        guard wait > .zero else { return }
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            await self?.refreshStatus()
        }
    }

    /// The later of a hold already running and a proposed one. A proposed end
    /// already past holds nothing; a running hold is never shortened.
    nonisolated static func extendedHold(
        _ current: ContinuousClock.Instant?, to proposed: ContinuousClock.Instant?, now: ContinuousClock.Instant
    ) -> ContinuousClock.Instant? {
        guard let proposed, proposed > now else { return current }
        guard let current, current > proposed else { return proposed }
        return current
    }

    /// The longest a hold runs, whatever date the tier gave: a day, the span
    /// of the daily quota a hold exists for. A date further off is a clock or
    /// a server gone wrong, and held to it, Private Cloud Compute would sit
    /// out the life of the process. Past it, a quota still spent is still
    /// excluded by the model's own quota usage.
    nonisolated static let longestHold: Duration = .seconds(24 * 60 * 60)

    /// When a hold to `date` lifts, on the monotonic clock: `date`'s distance
    /// from the wall clock now, counted from `now`, and no further than
    /// `longestHold`. Nil for no date, a date already past, and one that is
    /// no number.
    nonisolated static func holdEnd(
        until date: Date?, wallNow: Date, now: ContinuousClock.Instant
    ) -> ContinuousClock.Instant? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(wallNow)
        guard !seconds.isNaN, seconds > 0 else { return nil }
        // Compared as seconds before any `Duration` is made of them: one made
        // of an infinite or vast number traps.
        guard seconds < Double(longestHold.components.seconds) else { return now + longestHold }
        return now + .seconds(seconds)
    }

    /// The wall-clock date a hold lifts at, which the quota banner shows: the
    /// hold's distance on the monotonic clock, from the wall clock now.
    nonisolated static func wallDate(
        of instant: ContinuousClock.Instant, wallNow: Date, now: ContinuousClock.Instant
    ) -> Date {
        let left = instant - now
        return wallNow.addingTimeInterval(
            Double(left.components.seconds) + Double(left.components.attoseconds) * 1e-18
        )
    }

    /// When a spent quota comes back: the failure's own date, else the one the
    /// model's quota usage reports. Nil when neither says, and then the tier is
    /// held no longer than the quota usage keeps reporting the limit.
    nonisolated static func quotaReset(fromError: Date?, fromUsage: Date?) -> Date? {
        fromError ?? fromUsage
    }

    /// An on-device generation waits its turn at this seam's generation gate,
    /// first in, first out; a Private Cloud Compute one runs at once.
    public func withGeneration<T: Sendable>(
        onDevice: Bool,
        _ body: nonisolated(nonsending) @Sendable () async throws -> T
    ) async throws -> T {
        guard onDevice else { return try await body() }
        return try await AskGenerationGate.run(gate: gate) { try await body() }
    }

    /// Reads every tier's state and Private Cloud Compute's quota, and
    /// publishes them to `status`.
    ///
    /// **The newest reading wins, not the last to finish.** The read awaits
    /// the tiers' probes, so a refresh begun before a cooldown can finish
    /// after one begun since, and its reading would name a tier the cooldown
    /// had just excluded until the next refresh. So each refresh takes a
    /// number before it reads, and the mirror takes a reading only when no
    /// newer refresh's has landed: checked on the main actor, in the same
    /// step as the apply, since the two hops there can land in either order
    /// too.
    public func refreshStatus() async {
        refreshesBegun &+= 1
        let refresh = refreshesBegun
        let states = await tierStates()
        var snapshot = Self.snapshot(from: states)
        // `model()` is nil in a parked or unentitled process, so a development
        // build, and a host that declared no entitlement, reads no quota either.
        if let model = model() {
            let quota = model.quotaUsage
            let held = isQuotaHeld
            snapshot.quotaReached = quota.isLimitReached || held
            if !held, case .belowLimit(let info) = quota.status { snapshot.quotaApproaching = info.isApproachingLimit }
            let heldUntil = held ? quotaHeldUntil.map { Self.wallDate(of: $0, wallNow: .now, now: now()) } : nil
            snapshot.resetDate = quota.resetDate ?? heldUntil
            snapshot.hasLimitIncreaseSuggestion = quota.limitIncreaseSuggestion != nil
        }
        let published = snapshot
        let status = self.status
        await MainActor.run {
            let isNewest = newestRefreshApplied.withLock { newest in
                guard refresh > newest else { return false }
                newest = refresh
                return true
            }
            if isNewest { status.apply(published) }
        }
    }

    /// The tier states, as the mirror the settings card reads.
    ///
    /// Split out of `refreshStatus`, which needs a live seam, a live
    /// `SystemLanguageModel` and an entitled process, and made `nonisolated
    /// static` so tests can reach it: every value the settings card reads,
    /// except the quota's, is derived here. The quota half stays in
    /// `refreshStatus`, which reads the real model.
    nonisolated static func snapshot(from states: [AskTierState]) -> AskModelStatus.Snapshot {
        // With nothing servable, a held Private Cloud Compute is still next,
        // by the test the engine's turn reads (`askHeldTier(from:)`).
        let next = askServableTiers(from: states).first ?? askHeldTier(from: states)?.tier
        var snapshot = AskModelStatus.Snapshot(
            nextTier: next,
            unavailability: next == nil ? askUnavailability(from: states) : nil
        )
        // The Private Cloud Compute tier's own reason, which `unavailability`
        // throws away: that field speaks only when NOTHING can serve, and a
        // settings card has to say something about the tier while the one below
        // it answers happily. The language case is included because it is the
        // one way a tier reports itself available and still can't write.
        if let cloud = states.first(where: { $0.tier == .privateCloud }) {
            snapshot.privateCloudUnavailability = cloud.isAvailable
                ? (cloud.speaksLanguage ? nil : .languageNotSupported)
                : (cloud.unavailability ?? .unknown)
        }
        return snapshot
    }

    /// Shows Private Cloud Compute's limit-increase suggestion, when the quota
    /// offers one.
    public func showLimitIncrease() async {
        model()?.quotaUsage.limitIncreaseSuggestion?.show()
    }
}

/// Whether the device has a network at all.
///
/// Inside the seam rather than a seam requirement: an app's own reachability
/// monitor is one more thing every adopter would have to supply, and
/// `.networkFailure` cooling the tier is the backstop when this is wrong.
nonisolated final class NetworkReachability: Sendable {
    private let monitor = NWPathMonitor()
    /// A `Mutex`, so the class is checked `Sendable` rather than `@unchecked`.
    private let connected = Mutex(true)

    init() {
        // `[weak self]` rather than a captured `connected`: a `Mutex` is
        // non-copyable, so it can only be borrowed, and a closure can't borrow
        // a stored property for its lifetime.
        monitor.pathUpdateHandler = { [weak self] path in
            self?.connected.withLock { $0 = path.status == .satisfied }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    deinit { monitor.cancel() }

    /// Defaults to true before the first path update: a false negative here
    /// would send a perfectly good question to the smaller model.
    var isConnected: Bool {
        connected.withLock { $0 }
    }
}

/// `AskSession` over a real `LanguageModelSession`.
///
/// One request at a time on the session, which the engine's own
/// serialization keeps true. Plain `Sendable`: on SDK 27 `LanguageModelSession`
/// is `Sendable`, and every stored property here is a `let` of a `Sendable`
/// type.
///
/// Public for a host whose own model router builds its sessions: its
/// `AskModelSeam.makeSession` wraps each one in this and keeps the streaming,
/// the photo prompt, the planner, the usage reading and the feedback
/// attachment `AppleModelSeam` uses.
nonisolated public final class AppleAskSession: AskSession, Sendable {
    private let session: LanguageModelSession
    /// The model's context window, read by the seam when it built this
    /// session — see `contextSize()`.
    private let window: Int?
    /// Builds a tool-free planner on the model this session runs on. Supplied by
    /// the seam, which owns model construction and the entitlement check.
    private let makePlanner: @Sendable (String) -> LanguageModelSession
    /// Hands every raw failure back to the seam that built this session, before
    /// the engine triages it: a spent quota's reset and a rate limit's are on
    /// the SDK's error and nowhere else. Nil for an on-device session.
    private let noteFailure: (@Sendable (any Error) async -> Void)?
    /// The most tokens one answer — a streamed turn or a refine pass — may run
    /// to, or nil for the model's whole window. The on-device session's is
    /// `AskContinuation.onDeviceAnswerCap`; Private Cloud Compute's is nil.
    private let answerCap: Int?
    /// The same for the planner's reply (`AskContinuation.onDevicePlanCap`).
    private let planCap: Int?
    /// The newest response's token counts — see `usage()`.
    private let newestUsage = Mutex<AskUsage?>(nil)

    /// The on-device answer cap `AppleModelSeam` gives its sessions, in
    /// tokens: a guard against a runaway answer in the device's small window,
    /// which the engine's rollover allows for.
    public static let onDeviceAnswerCap = AskContinuation.onDeviceAnswerCap

    /// The on-device planner cap `AppleModelSeam` gives its sessions, in
    /// tokens: a plan is a handful of search arguments.
    public static let onDevicePlanCap = AskContinuation.onDevicePlanCap

    /// A session the engine can run turns on.
    ///
    /// - Parameters:
    ///   - session: the session the turns stream on, built with the tools and
    ///     instructions the seam's `makeSession` was handed.
    ///   - contextSize: the model's context window, read when the session was
    ///     built. Nil leaves the domain's turn count as the only budget.
    ///   - answerCap: the most tokens one answer may run to, or nil for the
    ///     model's whole window. An on-device session takes
    ///     `onDeviceAnswerCap`.
    ///   - planCap: the same for the grounded retry's planner. An on-device
    ///     session takes `onDevicePlanCap`.
    ///   - noteFailure: hears every raw failure before the engine triages it,
    ///     which drops a quota's or a rate limit's reset date
    ///     (`AskTriage.retryAfter(from:)` reads it).
    ///   - makePlanner: a session with no tools, on the same model, with the
    ///     instructions it is handed: the grounded retry plans its search on
    ///     it.
    public init(
        session: LanguageModelSession,
        contextSize: Int?,
        answerCap: Int? = nil,
        planCap: Int? = nil,
        noteFailure: (@Sendable (any Error) async -> Void)? = nil,
        makePlanner: @escaping @Sendable (String) -> LanguageModelSession
    ) {
        self.session = session
        self.window = contextSize
        self.answerCap = answerCap
        self.planCap = planCap
        self.noteFailure = noteFailure
        self.makePlanner = makePlanner
    }

    /// One generation of `AskReply`, with no photos.
    public func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt,
            images: [],
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt
        )
    }

    /// One generation of `AskReply`, with `images` after the prompt's words:
    /// the shaped stream below, in the full shape.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        stream(
            prompt: prompt,
            images: images,
            temperature: temperature,
            reasoningLevel: reasoningLevel,
            includeSchemaInPrompt: includeSchemaInPrompt,
            shape: .full
        )
    }

    /// One generation of the reply `shape` names, `AskReply` or
    /// `AskProseReply`, with `images` after the prompt's words, capped at
    /// `answerCap` tokens. The snapshots update `usage()` as they arrive, and
    /// a failure goes to `noteFailure` before the stream throws it. Letting
    /// the stream go cancels the generation. Read inside
    /// `AskGenerationGate.run`, the generation gate moves on only once the
    /// generation has returned, not when the reader lets go.
    public func stream(
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        shape: AskReplyShape
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        switch shape {
        case .full:
            generate(
                AskReply.self, prompt: prompt, images: images, temperature: temperature,
                reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
            ) { reply in
                AskReplySnapshot(
                    answer: reply.answer,
                    questionKind: reply.questionKind,
                    showsEveryMatch: reply.showsEveryMatch,
                    tiles: reply.tiles,
                    followUps: reply.followUps
                )
            }
        case .prose:
            generate(
                AskProseReply.self, prompt: prompt, images: images, temperature: temperature,
                reasoningLevel: reasoningLevel, includeSchemaInPrompt: includeSchemaInPrompt
            ) { reply in
                AskReplySnapshot(answer: reply.answer, followUps: reply.followUps)
            }
        }
    }

    /// One streamed generation of `type`, each snapshot of it turned into an
    /// `AskReplySnapshot` by `snapshot`.
    private func generate<Reply: Generable>(
        _ type: Reply.Type,
        prompt: String,
        images: [AskImageAttachment],
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool,
        snapshot: @escaping @Sendable (Reply.PartiallyGenerated) -> AskReplySnapshot
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        // The generation gate's holder this stream is read under, if any:
        // read here, in the reader's task, where the holder bound it.
        let producers = AskGenerationProducers.current
        return AsyncThrowingStream { continuation in
            let task = Task { [session, answerCap, self] in
                do {
                    let options = GenerationOptions(temperature: temperature, maximumResponseTokens: answerCap)
                    let context = ContextOptions(
                        includeSchemaInPrompt: includeSchemaInPrompt,
                        reasoningLevel: Self.level(reasoningLevel)
                    )
                    // A question with no photo goes as a plain string, so
                    // what a warm session cached is what arrives. One with a
                    // photo puts the words first, for the same cache
                    // (`AskSession` says so).
                    let stream: LanguageModelSession.ResponseStream<Reply>
                    if images.isEmpty {
                        stream = session.streamResponse(
                            to: prompt,
                            generating: type,
                            options: options,
                            contextOptions: context
                        )
                    } else {
                        stream = session.streamResponse(
                            to: Prompt {
                                prompt
                                for attachment in images {
                                    Attachment(attachment.image).label(attachment.label)
                                }
                            },
                            generating: type,
                            options: options,
                            contextOptions: context
                        )
                    }
                    for try await partial in stream {
                        // Every snapshot, not only the last: on the device each
                        // one already carries the request's whole input and the
                        // output so far, so a stream the deadline abandons still
                        // leaves its size behind.
                        self.noteUsage(partial.usage)
                        continuation.yield(snapshot(partial.content))
                    }
                    continuation.finish()
                } catch {
                    // Before the throw, so the tier is held before the next
                    // read of the tiers can find it servable.
                    await self.noteFailure?(error)
                    continuation.finish(throwing: error)
                }
            }
            // Letting the stream go only cancels this task, and the reader's
            // loop ends at once while `streamResponse` is still unwinding. So
            // the holder waits for the task itself before the generation gate
            // lets the next generation in (`AskGenerationProducers`).
            producers?.adopt(task)
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func level(_ level: AskReasoningLevel?) -> ContextOptions.ReasoningLevel? {
        switch level {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        case nil: nil
        }
    }

    /// The grounded retry's plan: one response of `type` from a new session
    /// with no tools, on this session's model, capped at `planCap` tokens.
    public func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        // A session of its own, with NO tools, so the model's only possible
        // reply is the search arguments. On the tier's own model, since the
        // answer it plans for is the one that model will write.
        let planner = makePlanner(instructions)
        do {
            return try await planner.respond(
                to: prompt, generating: type, options: GenerationOptions(maximumResponseTokens: planCap)
            ).content
        } catch {
            await noteFailure?(error)
            throw error
        }
    }

    /// One response of `type` on this session, with `images` ahead of the
    /// prompt, capped at `answerCap` tokens. Its usage becomes `usage()`'s
    /// reading.
    public func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        let response: LanguageModelSession.Response<Content>
        do {
            response = try await session.respond(
                to: Prompt {
                    for attachment in images {
                        Attachment(attachment.image).label(attachment.label)
                    }
                    prompt
                },
                generating: type,
                options: GenerationOptions(temperature: temperature, maximumResponseTokens: answerCap),
                contextOptions: ContextOptions(reasoningLevel: Self.level(reasoningLevel))
            )
        } catch {
            await noteFailure?(error)
            throw error
        }
        // The refine pass is a response on THIS session, and the newest one:
        // what the next turn's request starts from includes it.
        noteUsage(response.usage)
        return response.content
    }

    /// The tool calls in the session's transcript, across all its turns. One
    /// transcript entry holds every call the model made at once, so this counts
    /// the calls in each entry, not the entries.
    public func toolCallCount() async -> Int {
        session.transcript.reduce(into: 0) { count, entry in
            if case .toolCalls(let calls) = entry { count += calls.count }
        }
    }

    /// The newest response's counts, never the session's.
    ///
    /// **`session.usage` is a running total**: every request's input, added
    /// up, and each request's input is the whole transcript so far, so the
    /// total counts the thread once per turn. Measured on the on-device model,
    /// four short turns read 70, 160, 270 and 400 input tokens while
    /// `tokenCount(for:)` put the transcript at 72, 92, 112 and 132. Set
    /// against the window, the running total would roll a conversation over,
    /// onto a cold cache and a recap, long before the window filled, and each
    /// turn's `[usage]` line would report it as that turn's cost.
    ///
    /// A response's own usage is what the next request starts from: its input
    /// was the transcript, its output is the newest entry. Nil until this
    /// session has answered anything.
    public func usage() async -> AskUsage? {
        newestUsage.withLock { $0 }
    }

    /// Keep a response's counts, unless it has not reported its input yet.
    ///
    /// **The input, not the total.** The SDK counts output as the text
    /// arrives, so a provider that sends the request's size only once it has
    /// finished streams snapshots with an output count and an input of zero
    /// (measured with a scripted provider), and a reading of zero input is an
    /// empty window to the rollover check. Until the input arrives, the last
    /// response's reading stands.
    private func noteUsage(_ usage: LanguageModelSession.Usage) {
        guard usage.input.totalTokenCount > 0 else { return }
        newestUsage.withLock { $0 = Self.askUsage(from: usage) }
    }

    nonisolated static func askUsage(from usage: LanguageModelSession.Usage) -> AskUsage {
        AskUsage(
            inputTokens: usage.input.totalTokenCount,
            cachedTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount,
            reasoningTokens: usage.output.reasoningTokenCount
        )
    }

    /// The window the seam read when it built this session: 8,192 tokens on
    /// device and 32,768 on Private Cloud Compute in the 27 releases, read
    /// rather than hardcoded because both move with the OS.
    public func contextSize() async -> Int? {
        window
    }

    /// An empty prefix warms the model with nothing cached ahead of the
    /// question, rather than caching an empty prompt.
    public func prewarm(promptPrefix: String) async {
        await Self.prewarm(session, promptPrefix: promptPrefix)
    }

    /// The warm itself, off the caller's actor: under
    /// `NonisolatedNonsendingByDefault` `prewarm` runs on the engine's.
    /// `@concurrent` rather than a detached task, so it keeps its caller's
    /// priority and cancellation.
    @concurrent nonisolated private static func prewarm(_ session: LanguageModelSession, promptPrefix: String) async {
        session.prewarm(promptPrefix: promptPrefix.isEmpty ? nil : Prompt(promptPrefix))
    }

    /// `logFeedbackAttachment` records the verdict against this session's
    /// transcript and hands back the attachment a Feedback Assistant report
    /// takes.
    public func feedbackAttachment(sentiment: AskFeedback.Sentiment) async -> Data? {
        let verdict: LanguageModelFeedback.Sentiment = switch sentiment {
        case .positive: .positive
        case .negative: .negative
        }
        return session.logFeedbackAttachment(sentiment: verdict)
    }
}

/// One of the seam's Private Cloud Compute reads, each a network call (the
/// locale probe, the context window): shared while it runs, kept once it
/// answers, bounded in time, and, when it couldn't say, remembered briefly as
/// no answer.
///
/// - **Shared.** A caller that finds the read running waits on that run
///   rather than sending another. The seam is an actor and every `await` lets
///   another caller in, so two `tierStates()` overlapping at launch would each
///   send the probe before either had kept its answer.
/// - **Kept.** An answer is kept for the process: it changes with the OS, not
///   with the minute.
/// - **Bounded.** A run past `bound` is abandoned (`AskDeadline`) and reads as
///   no answer, so a stalled network can't hold the turn that asked.
/// - **Remembered, never kept, when it couldn't say.** A run that threw or was
///   abandoned reads as no answer to every caller for `failureMemory`, the way
///   a transient availability probe is served from cache
///   (`AppleModelSeam.reprobeInterval`), and the first caller after that reads
///   again.
///
/// A caller that is cancelled stops waiting at once and reads no answer. The
/// run goes on for whoever else waits on it, and keeps what it learns.
actor AskSharedRead<Key: Hashable & Sendable, Value: Sendable> {
    private let label: String
    private let bound: Duration
    private let failureMemory: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let logger: Logger
    private var answers: [Key: Value] = [:]
    private var failedAt: [Key: ContinuousClock.Instant] = [:]
    private var running: [Key: Task<Value?, Never>] = [:]
    private var waiters: [Key: Int] = [:]

    /// - Parameters:
    ///   - label: what the read is, for the line logged when it couldn't say.
    ///   - bound: how long one run may take before it is abandoned.
    ///   - failureMemory: how long a run that couldn't say is remembered.
    ///   - now: the clock `failureMemory` is counted on.
    ///   - logger: where the line goes.
    init(
        label: String,
        bound: Duration,
        failureMemory: Duration,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
        logger: Logger = Logger(subsystem: AskBrand.subsystem(nil), category: "seam")
    ) {
        self.label = label
        self.bound = bound
        self.failureMemory = failureMemory
        self.now = now
        self.logger = logger
    }

    /// The answer for `key`: the one kept, or the one the run already going
    /// brings, or one `read` brings now. Nil when the run couldn't say, or one
    /// couldn't within `failureMemory`, or the caller was cancelled.
    func value(for key: Key, read: @escaping @Sendable () async throws -> Value) async -> Value? {
        if let answer = answers[key] { return answer }
        if let failed = failedAt[key], now() - failed < failureMemory { return nil }
        let run = running[key] ?? start(key, read)
        waiters[key, default: 0] += 1
        defer { waiters[key, default: 1] -= 1 }
        return await Self.wait(for: run, upTo: bound)
    }

    /// How many callers are waiting on `key`'s run. Test-facing: that the
    /// callers share one run is the property worth pinning, and it is
    /// otherwise invisible.
    func waiting(for key: Key) -> Int { waiters[key] ?? 0 }

    private func start(_ key: Key, _ read: @escaping @Sendable () async throws -> Value) -> Task<Value?, Never> {
        let bound = self.bound
        let run = Task {
            let value: Value?
            let failure: String?
            do {
                value = try await AskDeadline.run(bound) { try await read() }
                failure = value == nil ? "ran past \(bound.components.seconds)s" : nil
            } catch {
                // Its tag, never its message (`AskTriage.tag(for:)`).
                (value, failure) = (nil, AskTriage.tag(for: error))
            }
            record(key, value, failure: failure)
            return value
        }
        running[key] = run
        return run
    }

    private func record(_ key: Key, _ value: Value?, failure: String?) {
        running[key] = nil
        if let value {
            answers[key] = value
            failedAt[key] = nil
        } else {
            failedAt[key] = now()
            logger.notice("""
                \(self.label, privacy: .public) couldn't say (\(failure ?? "–", privacy: .public)) — \
                read as no answer for \(self.failureMemory.components.seconds, privacy: .public)s
                """)
        }
    }

    /// Waits on a run without tying the run to the caller: `AskDeadline`
    /// returns at once when the caller is cancelled, and abandons only the
    /// wait. The run is bounded on its own, so the wait's bound, twice the
    /// run's, is only a backstop.
    private static func wait(for run: Task<Value?, Never>, upTo bound: Duration) async -> Value? {
        (try? await AskDeadline.run(bound * 2) { await run.value }) ?? nil
    }
}

/// Who counts the `AppleModelSeam`s alive in the process, so the second one is
/// reported, once.
nonisolated struct AskSeamCensus: Sendable {
    private(set) var alive = 0
    private var hasReported = false

    /// A seam was built. True only for the first time a second one is alive.
    mutating func arrive() -> Bool {
        alive += 1
        guard alive > 1, !hasReported else { return false }
        hasReported = true
        return true
    }

    /// A seam was let go.
    mutating func leave() {
        alive = max(0, alive - 1)
    }
}

#endif
