import Foundation
import Testing

@testable import AskCore

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels
import Synchronization

/// The snapshot the settings card reads, and the availability mapping beside it.
///
/// `refreshStatus` needs a live seam, a live `SystemLanguageModel` and an
/// entitled process, which no test has, so every value the card reads but the
/// quota is derived by the pure functions pinned here. Without them, the
/// card's tests would pin the drawing of values nothing pins the derivation
/// of.
@Suite(.timeLimit(.minutes(1))) struct AppleModelSeamTests {

    private func state(
        _ tier: AskTier, available: Bool, speaks: Bool = true,
        why: AskUnavailability? = nil, quota: Bool = false, cooled: Bool = false
    ) -> AskTierState {
        AskTierState(tier: tier, isAvailable: available, speaksLanguage: speaks,
                     quotaReached: quota, isCooled: cooled, unavailability: why)
    }

    @Test func theNextTierIsTheFirstThatCanServe() {
        let both = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: true), state(.onDevice, available: true)
        ])
        #expect(both.nextTier == .privateCloud)
        #expect(both.unavailability == nil)

        let handedDown = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: false, why: .offline), state(.onDevice, available: true)
        ])
        #expect(handedDown.nextTier == .onDevice)
        // Nothing to say at the top level: something IS serving.
        #expect(handedDown.unavailability == nil)
    }

    @Test func theTopLevelReasonSpeaksOnlyWhenNothingCanServe() {
        let none = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: false, why: .offline),
            state(.onDevice, available: false, why: .appleIntelligenceOff)
        ])
        #expect(none.nextTier == nil)
        #expect(none.unavailability != nil)
    }

    @Test func thePrivateCloudRowKeepsItsOwnReasonWhileTheTierBelowServes() {
        // The distinction the card exists to draw: `unavailability` is silent
        // whenever anything serves, so without this the settings row would say
        // nothing about Private Cloud Compute while on-device answered happily.
        let snapshot = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: false, why: .notEntitled),
            state(.onDevice, available: true)
        ])
        #expect(snapshot.nextTier == .onDevice)
        #expect(snapshot.unavailability == nil)
        #expect(snapshot.privateCloudUnavailability == .notEntitled)
    }

    @Test func anAvailableTierThatCannotWriteTheLanguageSaysSo() {
        // The one way a tier reports itself available and still cannot serve
        // the reader — Hebrew on Private Cloud Compute.
        let snapshot = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: true, speaks: false),
            state(.onDevice, available: true)
        ])
        #expect(snapshot.privateCloudUnavailability == .languageNotSupported)
    }

    @Test func anUnavailableTierWithNoStatedReasonIsUnknownRatherThanNil() {
        let snapshot = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: false), state(.onDevice, available: true)
        ])
        #expect(snapshot.privateCloudUnavailability == .unknown)
    }

    @Test func turnedOffAndIneligibleMapToReasonsTheReaderCanActOn() {
        // Two of `reason(from:)`'s three cases: Apple Intelligence turned off
        // and a device that can't run it each read as the reason the reader
        // can act on.
        #expect(AppleModelSeam.reason(from: .appleIntelligenceNotEnabled) == .appleIntelligenceOff)
        #expect(AppleModelSeam.reason(from: .deviceNotEligible) == .deviceNotEligible)
    }

    @Test func aModelNotReadyInALanguageItCannotWriteSaysItIsTheLanguage() {
        // iOS reports an app language the model does not write as "not ready".
        // Taken at its word, it would tell a Hebrew reader to wait for a
        // download that never finishes.
        let hebrew = AppleModelSeam.unavailableOnDeviceState(.modelNotReady, speaksAppLanguage: false)
        #expect(hebrew.unavailability == .languageNotSupported)
        #expect(!hebrew.isServable)
        #expect(askUnavailability(from: [hebrew]) == .languageNotSupported)
        // With Private Cloud Compute out too, the on-device reason is the one
        // the screen shows.
        #expect(askUnavailability(from: [
            state(.privateCloud, available: false, why: .offline), hebrew
        ]) == .languageNotSupported)

        let downloading = AppleModelSeam.unavailableOnDeviceState(.modelNotReady, speaksAppLanguage: true)
        #expect(downloading.unavailability == .modelNotReady)
    }

    @Test func turnedOffOrIneligibleOutranksTheLanguage() {
        for reason in [AskUnavailability.appleIntelligenceOff, .deviceNotEligible, .unknown] {
            let state = AppleModelSeam.unavailableOnDeviceState(reason, speaksAppLanguage: false)
            #expect(state.unavailability == reason)
        }
    }

    // MARK: - A tier out for a while

    @Test func aTierOutOnlyForAWhileStaysTheNextTierWhenNothingBelowServes() {
        // A cooldown or a spent quota with nowhere to hand down to is the
        // turn's error, which Try Again retries: the mirror names the tier,
        // so New Chat doesn't put up the can't-serve first screen in the
        // on-device tier's words.
        let device = state(.onDevice, available: false, why: .modelNotReady)
        for cloud in [
            state(.privateCloud, available: true, cooled: true),
            state(.privateCloud, available: true, quota: true),
            state(.privateCloud, available: true, quota: true, cooled: true)
        ] {
            let snapshot = AppleModelSeam.snapshot(from: [cloud, device])
            #expect(snapshot.nextTier == .privateCloud)
            #expect(snapshot.unavailability == nil)
            #expect(snapshot.privateCloudUnavailability == nil)
        }
        // While the device serves, it serves.
        let handedDown = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: true, cooled: true), state(.onDevice, available: true)
        ])
        #expect(handedDown.nextTier == .onDevice)
    }

    @Test func aHoldOnATierThatCannotServeAnywayNamesNothing() {
        let device = state(.onDevice, available: false, why: .appleIntelligenceOff)
        let down = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: false, why: .offline, cooled: true), device
        ])
        #expect(down.nextTier == nil)
        #expect(down.unavailability == .appleIntelligenceOff)
        let wrongLanguage = AppleModelSeam.snapshot(from: [
            state(.privateCloud, available: true, speaks: false, quota: true), device
        ])
        #expect(wrongLanguage.nextTier == nil)
        #expect(wrongLanguage.unavailability == .languageNotSupported)
    }

    // MARK: - Holding the tier until Apple says

    private let wallNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let start = ContinuousClock.now

    @Test func aHoldRunsToTheDateTheTierGave() {
        let reset = AppleModelSeam.holdEnd(until: wallNow.addingTimeInterval(3_600), wallNow: wallNow, now: start)
        #expect(reset == start + .seconds(3_600))
        #expect(AppleModelSeam.extendedHold(nil, to: reset, now: start) == reset)
        // And the quota banner's date is the one the tier gave.
        #expect(AppleModelSeam.wallDate(of: start + .seconds(3_600), wallNow: wallNow, now: start)
                == wallNow.addingTimeInterval(3_600))
    }

    @Test func aHoldNeverShortensOneAlreadyRunning() {
        // A rate limit that said an hour, followed by the engine's ordinary
        // one-minute transport cooldown for the same failure: the hour stands.
        let hour = start + .seconds(3_600)
        let minute = start + .seconds(60)
        #expect(AppleModelSeam.extendedHold(hour, to: minute, now: start) == hour)
        #expect(AppleModelSeam.extendedHold(minute, to: hour, now: start) == hour)
    }

    @Test func aDateAlreadyPastHoldsNothingNew() {
        #expect(AppleModelSeam.holdEnd(until: wallNow.addingTimeInterval(-10), wallNow: wallNow, now: start) == nil)
        #expect(AppleModelSeam.holdEnd(until: nil, wallNow: wallNow, now: start) == nil)
        let past = start - .seconds(10)
        #expect(AppleModelSeam.extendedHold(nil, to: past, now: start) == nil)
        #expect(AppleModelSeam.extendedHold(nil, to: nil, now: start) == nil)
        let running = start + .seconds(30)
        #expect(AppleModelSeam.extendedHold(running, to: past, now: start) == running)
    }

    @Test func aResetFarOffOrNoNumberHoldsNoLongerThanADay() {
        // A date a day off at most is the daily quota's; one further is a
        // clock or a server gone wrong, and an infinite one would trap the
        // moment it became a `Duration`.
        let day = start + AppleModelSeam.longestHold
        #expect(AppleModelSeam.longestHold == .seconds(86_400))
        #expect(AppleModelSeam.holdEnd(until: .distantFuture, wallNow: wallNow, now: start) == day)
        let infinite = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(AppleModelSeam.holdEnd(until: infinite, wallNow: wallNow, now: start) == day)
        let noNumber = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(AppleModelSeam.holdEnd(until: noNumber, wallNow: wallNow, now: start) == nil)
    }

    @Test func theQuotaHoldTakesTheErrorsDateFirstAndTheQuotaUsagesSecond() {
        let fromError = wallNow.addingTimeInterval(7_200)
        let fromUsage = wallNow.addingTimeInterval(9_000)
        #expect(AppleModelSeam.quotaReset(fromError: fromError, fromUsage: fromUsage) == fromError)
        #expect(AppleModelSeam.quotaReset(fromError: nil, fromUsage: fromUsage) == fromUsage)
        #expect(AppleModelSeam.quotaReset(fromError: nil, fromUsage: nil) == nil)
    }

    // MARK: - The locale probe

    @Test func aLocaleProbeThatThrewLeavesPrivateCloudComputeServing() {
        // A network blip or a cancelled refresh says nothing about the
        // language. Read as "no", it would hand every turn to the device or,
        // with no device tier, tell the reader their language is unsupported,
        // which no Try Again gets past.
        let cloud = state(.privateCloud, available: true, speaks: AppleModelSeam.speaksLanguage(probed: nil))
        let device = state(.onDevice, available: false, why: .appleIntelligenceOff)
        #expect(askServableTiers(from: [cloud, device]) == [.privateCloud])
        let snapshot = AppleModelSeam.snapshot(from: [cloud, device])
        #expect(snapshot.nextTier == .privateCloud)
        #expect(snapshot.unavailability == nil)
        #expect(snapshot.privateCloudUnavailability == nil)
        // A probe that answered still decides.
        #expect(AppleModelSeam.speaksLanguage(probed: true))
        #expect(!AppleModelSeam.speaksLanguage(probed: false))
    }

    @Test func anAnswerLanguageTheProbeCouldNotConfirmIsEnglish() {
        // The tier stays up, but a request naming a language the tier may not
        // write can bounce `unsupportedLanguageOrLocale`, which does not hand
        // down. English is the answer nothing bounces.
        let french = Locale(identifier: "fr_FR")
        #expect(AppleModelSeam.answerLanguage(for: french, probed: true) == "French")
        #expect(AppleModelSeam.answerLanguage(for: french, probed: false) == nil)
        #expect(AppleModelSeam.answerLanguage(for: french, probed: nil) == nil)
    }

    // MARK: - The answer language's name

    @Test func traditionalChineseIsAskedForByItsScript() throws {
        // "Chinese" alone can come back Simplified. Whether the locale names
        // the script or its region implies it, the name says Traditional.
        for identifier in ["zh-Hant", "zh_TW", "zh-Hant_TW"] {
            let name = try #require(AppleModelSeam.languageName(for: Locale(identifier: identifier)), "\(identifier)")
            #expect(name.hasPrefix("Chinese") && name.contains("Traditional"), "\(identifier): \(name)")
        }
        let hongKong = try #require(AppleModelSeam.languageName(for: Locale(identifier: "zh-Hant_HK")))
        #expect(hongKong.contains("Traditional") && hongKong.contains("Hong Kong"), "\(hongKong)")
    }

    @Test func aRegionalVariantIsAskedForByItsRegion() throws {
        let portugal = try #require(AppleModelSeam.languageName(for: Locale(identifier: "pt_PT")))
        #expect(portugal.hasPrefix("Portuguese") && portugal.contains("Portugal"), "\(portugal)")
        let canada = try #require(AppleModelSeam.languageName(for: Locale(identifier: "fr_CA")))
        #expect(canada.hasPrefix("French") && canada.contains("Canada"), "\(canada)")
    }

    @Test func aLanguagesUsualScriptAndRegionGoUnsaid() {
        // Simplified is what "Chinese" is written in and Brazil where
        // "Portuguese" is, so neither is named, as with any plain language.
        let names = [
            "zh-Hans": "Chinese", "zh-Hans_CN": "Chinese", "pt-BR": "Portuguese",
            "fr": "French", "fr_FR": "French", "he_IL": "Hebrew"
        ]
        for (identifier, name) in names {
            #expect(AppleModelSeam.languageName(for: Locale(identifier: identifier)) == name, "\(identifier)")
        }
    }

    @Test func theNameNeverCarriesTheLocalesSettings() {
        // An identifier can carry a calendar or a region override, and no
        // answer is written in either.
        #expect(AppleModelSeam.languageName(for: Locale(identifier: "ja_JP@calendar=japanese")) == "Japanese")
        #expect(AppleModelSeam.languageName(for: Locale(identifier: "de_DE@rg=chzzzz")) == "German")
    }

    @Test func englishIsAskedForByNamingNothing() {
        for identifier in ["en", "en_US", "en_GB", "en-AU@rg=nzzzzz"] {
            #expect(AppleModelSeam.languageName(for: Locale(identifier: identifier)) == nil, "\(identifier)")
        }
    }

    // MARK: - The app's language, not the system's

    @Test func theTiersAreAskedAboutTheLanguageTheAppRunsIn() {
        // An app that ships English alone runs in English on a French system,
        // and its UI says so. Asked about French, a tier that couldn't write
        // it took Ask down, with an English line saying the language wasn't
        // supported.
        let french = Locale(identifier: "fr_FR")
        let english = AppleModelSeam.appLocale(preferredLocalizations: ["en"], current: french)
        #expect(english.language.languageCode == .english)
        #expect(AppleModelSeam.skipsPrivateCloudLocaleProbe(english))
        #expect(AppleModelSeam.languageName(for: english) == nil)
        // And an app the reader runs in Hebrew on an English system is asked
        // about Hebrew.
        let hebrew = AppleModelSeam.appLocale(preferredLocalizations: ["he", "en"], current: Locale(identifier: "en_US"))
        #expect(AppleModelSeam.languageName(for: hebrew) == "Hebrew")
    }

    @Test func theSystemsLocaleIsKeptWhenItIsInTheAppsLanguage() {
        // It is the more exact of the two: a "pt" localization read in
        // Portugal is still asked for as Portugal's.
        let portugal = Locale(identifier: "pt_PT")
        let kept = AppleModelSeam.appLocale(preferredLocalizations: ["pt"], current: portugal)
        #expect(kept.identifier == portugal.identifier)
        let traditional = Locale(identifier: "zh_TW")
        #expect(AppleModelSeam.appLocale(preferredLocalizations: ["zh-Hant"], current: traditional).identifier
                == traditional.identifier)
        // Not when the script differs: an app in Simplified Chinese answers in
        // Simplified, whatever the system reads.
        let simplified = AppleModelSeam.appLocale(preferredLocalizations: ["zh-Hans"], current: traditional)
        #expect(AppleModelSeam.languageName(for: simplified) == "Chinese")
    }

    @Test func aBundleThatNamesNoLanguageLeavesTheSystems() {
        let french = Locale(identifier: "fr_FR")
        #expect(AppleModelSeam.appLocale(preferredLocalizations: [], current: french).identifier == "fr_FR")
        #expect(AppleModelSeam.appLocale(preferredLocalizations: ["Base"], current: french).identifier == "fr_FR")
    }

    // MARK: - One seam per process

    @Test func theSecondSeamAliveIsReportedOnce() {
        var census = AskSeamCensus()
        let first = census.arrive()
        let second = census.arrive()
        let third = census.arrive()
        #expect(!first && second && !third)
        census.leave()
        census.leave()
        #expect(census.alive == 1)
        // Reported once for the process: a later second seam is the same
        // misuse, already in the log.
        let later = census.arrive()
        #expect(!later)
    }

    @Test func seamsBuiltOneAfterAnotherAreNotReported() {
        var census = AskSeamCensus()
        let first = census.arrive()
        census.leave()
        let next = census.arrive()
        #expect(!first && !next)
        #expect(census.alive == 1)
    }

    // MARK: - A seam with a scripted on-device model and a clock

    /// A clock a test moves by hand.
    nonisolated private final class SeamClock: Sendable {
        private let instant = Mutex(ContinuousClock.now)
        var now: ContinuousClock.Instant { instant.withLock { $0 } }
        func advance(_ duration: Duration) { instant.withLock { $0 += duration } }
    }

    /// The on-device model as a test scripts it: its availability and
    /// whether it writes the language, each changed when the test says, and
    /// an availability read the test can hold.
    nonisolated private final class ScriptedOnDevice: Sendable {
        private struct State {
            var availability: SystemLanguageModel.Availability
            var writes: Bool
            var localeReads = 0
            var heldRead: GateTestHold?
        }
        private let state: Mutex<State>

        init(_ availability: SystemLanguageModel.Availability, writes: Bool) {
            state = Mutex(State(availability: availability, writes: writes))
        }

        func set(_ availability: SystemLanguageModel.Availability, writes: Bool) {
            state.withLock { $0.availability = availability; $0.writes = writes }
        }

        /// How many times the seam asked whether the model writes a locale.
        var localeReads: Int { state.withLock { $0.localeReads } }

        /// Hold the next availability read at `hold`, answering what the
        /// model said when the read began.
        func holdNextRead(at hold: GateTestHold) {
            state.withLock { $0.heldRead = hold }
        }

        func availability() async -> SystemLanguageModel.Availability {
            let (answer, hold) = state.withLock { state in
                defer { state.heldRead = nil }
                return (state.availability, state.heldRead)
            }
            await hold?.hold()
            return answer
        }

        func supportsLocale() -> Bool {
            state.withLock { state in
                state.localeReads += 1
                return state.writes
            }
        }
    }

    /// A seam on `device` and `clock`, with no Private Cloud Compute to
    /// reach.
    private func seam(
        _ device: ScriptedOnDevice, clock: SeamClock = SeamClock(), status: AskModelStatus = AskModelStatus()
    ) -> AppleModelSeam {
        AppleModelSeam(
            status: status, privateCloudCompute: .undeclared, gate: AskGenerationGate(), logSubsystem: nil,
            onDeviceAvailability: { await device.availability() },
            onDeviceSupportsLocale: { _ in device.supportsLocale() },
            now: { clock.now }
        )
    }

    private func onDevice(_ seam: AppleModelSeam) async throws -> AskTierState {
        try #require(await seam.tierStates().first { $0.tier == .onDevice })
    }

    // MARK: - The on-device model's languages

    @Test func aNoFromAModelThatIsNotReadyIsAskedAgain() async throws {
        // A model still downloading can say no to a language it will write
        // once its assets are in. Kept, that no read as "language not
        // supported", which no Try Again gets past, until a relaunch.
        let device = ScriptedOnDevice(.unavailable(.modelNotReady), writes: false)
        let seam = seam(device)
        #expect(try await onDevice(seam).unavailability == .languageNotSupported)
        device.set(.unavailable(.modelNotReady), writes: true)
        #expect(try await onDevice(seam).unavailability == .modelNotReady)
        device.set(.available, writes: true)
        #expect(try await onDevice(seam).isServable)
    }

    @Test func aLanguageReadIsKeptOnlyWhileTheModelsAvailabilityHolds() async throws {
        // An available model's no is its answer, as on the Mac under a Hebrew
        // locale, and is read once.
        let device = ScriptedOnDevice(.available, writes: false)
        let seam = seam(device)
        #expect(try await !onDevice(seam).speaksLanguage)
        #expect(try await !onDevice(seam).speaksLanguage)
        #expect(device.localeReads == 1)
        // Until the model's availability changes, as when it downloads the
        // assets of a language: then it is read again.
        device.set(.unavailable(.modelNotReady), writes: true)
        #expect(try await onDevice(seam).unavailability == .modelNotReady)
        device.set(.available, writes: true)
        #expect(try await onDevice(seam).isServable)
    }

    // MARK: - The holds' clock

    @Test func theHoldsAreTimedOnTheMonotonicClock() async {
        // The seam's own clock, moved by hand while the wall clock stands
        // still: a hold read off the wall clock would never lift here, and
        // one set back would hold the tier for as long again.
        let clock = SeamClock()
        let seam = seam(ScriptedOnDevice(.available, writes: true), clock: clock)
        await seam.noteTransportFailure(on: .privateCloud)
        #expect(await seam.holds.isCooled)
        clock.advance(.seconds(59))
        #expect(await seam.holds.isCooled)
        clock.advance(.seconds(2))
        #expect(await !seam.holds.isCooled)

        await seam.noteFailure(LanguageModelError.rateLimited(
            .init(resetDate: Date.now.addingTimeInterval(600), debugDescription: "slow down")
        ))
        clock.advance(.seconds(598))
        #expect(await seam.holds.isCooled)
        clock.advance(.seconds(3))
        #expect(await !seam.holds.isCooled)

        await seam.noteFailure(PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: Date.now.addingTimeInterval(3_600), debugDescription: "spent")
        ))
        clock.advance(.seconds(3_598))
        #expect(await seam.holds.isQuotaHeld)
        clock.advance(.seconds(3))
        #expect(await !seam.holds.isQuotaHeld)
    }

    @Test func aResetFarOffLiftsADayLater() async {
        let clock = SeamClock()
        let seam = seam(ScriptedOnDevice(.available, writes: true), clock: clock)
        await seam.noteFailure(LanguageModelError.rateLimited(.init(resetDate: .distantFuture, debugDescription: "")))
        await seam.noteFailure(PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: .distantFuture, debugDescription: "")
        ))
        clock.advance(AppleModelSeam.longestHold - .seconds(1))
        #expect(await seam.holds == (isCooled: true, isQuotaHeld: true))
        clock.advance(.seconds(2))
        #expect(await seam.holds == (isCooled: false, isQuotaHeld: false))
    }

    // MARK: - Refreshes that overlap

    @Test func anOlderRefreshThatFinishesLastLeavesTheNewerReading() async throws {
        // A refresh begun before the model went away, finishing after one
        // begun since: its reading would name a tier that can't serve.
        let device = ScriptedOnDevice(.available, writes: true)
        let status = AskModelStatus()
        let seam = seam(device, status: status)
        let held = GateTestHold()
        device.holdNextRead(at: held)
        let older = Task { await seam.refreshStatus() }
        for _ in 0..<4_000 where !held.hasArrived {
            try await Task.sleep(for: .microseconds(500))
        }
        try #require(held.hasArrived)
        device.set(.unavailable(.appleIntelligenceNotEnabled), writes: true)
        await seam.refreshStatus()
        #expect(status.nextTier == nil)
        #expect(status.unavailability == .appleIntelligenceOff)
        held.release()
        await older.value
        #expect(status.nextTier == nil)
        #expect(status.unavailability == .appleIntelligenceOff)
    }

    @Test func englishNeverAsksPrivateCloudComputeWhichLanguagesItWrites() {
        // The probe is a network call, made once per process just to open Ask,
        // and English is the one answer that has never been in doubt.
        for identifier in ["en", "en_US", "en_GB", "en_IN", "en-AU"] {
            #expect(AppleModelSeam.skipsPrivateCloudLocaleProbe(Locale(identifier: identifier)), "\(identifier)")
        }
        for identifier in ["he", "fr_FR", "zh-Hans", "ja"] {
            #expect(!AppleModelSeam.skipsPrivateCloudLocaleProbe(Locale(identifier: identifier)), "\(identifier)")
        }
    }

    // MARK: - Where a wedged generation is logged

    /// The line the generation gate writes for an on-device generation of a
    /// seam built under `logSubsystem` that never returns, at a gate whose
    /// own subsystem is another, once its 50 ms are up.
    private func wedgedGenerationLines(
        seamLogSubsystem logSubsystem: String?
    ) async throws -> [GateTestWedgeLines.Line] {
        let lines = GateTestWedgeLines()
        let device = ScriptedOnDevice(.available, writes: true)
        let seam = AppleModelSeam(
            status: AskModelStatus(), privateCloudCompute: .undeclared,
            gate: AskGenerationGate(logSubsystem: "com.example.gate", logWedge: lines.write),
            logSubsystem: logSubsystem, holderDeadline: .milliseconds(50),
            onDeviceAvailability: { await device.availability() },
            onDeviceSupportsLocale: { _ in device.supportsLocale() },
            now: { .now }
        )
        let hold = GateTestHold()
        let generation = Task { try await seam.withGeneration(onDevice: true) { await hold.hold() } }
        for _ in 0..<4_000 where lines.written.isEmpty {
            try await Task.sleep(for: .microseconds(500))
        }
        hold.release()
        try await generation.value
        return lines.written
    }

    @Test func aWedgedOnDeviceGenerationIsLoggedUnderTheSeamsSubsystem() async throws {
        // The brand's subsystem, at the process's one gate: a host has no
        // gate of its own to build, and needs none, to find the line beside
        // the seam's.
        let lines = try await wedgedGenerationLines(seamLogSubsystem: "com.example.brand")
        #expect(lines == [.init(subsystem: "com.example.brand", deadline: .milliseconds(50))])
    }

    @Test func aSeamWithNoSubsystemLogsItsWedgedGenerationWhereItsOtherLinesGo() async throws {
        let lines = try await wedgedGenerationLines(seamLogSubsystem: nil)
        #expect(lines == [.init(subsystem: AskBrand.subsystem(nil), deadline: .milliseconds(50))])
    }

    // MARK: - One gate per process

    /// Both ways a host builds the seam take no gate: its on-device
    /// generations wait at `AskGenerationGate.shared`, where the host's own
    /// do, whatever subsystem it logs under.
    @Test func aSeamAHostBuildsWaitsAtTheSharedGate() async {
        let built = AppleModelSeam(status: AskModelStatus(), privateCloudCompute: .undeclared)
        let made = AppleModelSeam.make(privateCloudCompute: .undeclared, logSubsystem: "com.example.brand")
        #expect(await built.gate === AskGenerationGate.shared)
        #expect(await made.gate === AskGenerationGate.shared)
    }
}

/// The seam's Private Cloud Compute reads, each a network call: the locale
/// probe and the context window, through `AskSharedRead`.
///
/// `swift test` is parked, so no seam here ever reaches the tier. The read is
/// a closure that counts how often it runs, which is the property worth
/// pinning: two overlapping `tierStates()` at launch sent the probe twice, and
/// a probe that threw was sent again by every caller after it.
@Suite(.timeLimit(.minutes(1))) struct AskSharedReadTests {

    /// A clock a test moves by hand.
    nonisolated private final class Clock: Sendable {
        private let instant = Mutex(ContinuousClock.now)
        var now: ContinuousClock.Instant { instant.withLock { $0 } }
        func advance(_ duration: Duration) { instant.withLock { $0 += duration } }
    }

    /// A read that counts its runs and holds each one until `open()`.
    nonisolated private final class Probe: Sendable {
        private struct State {
            var runs = 0
            var isOpen = false
            var held: [CheckedContinuation<Void, Never>] = []
        }
        private let state = Mutex(State())

        func held(_ answer: Bool) async -> Bool {
            await withCheckedContinuation { continuation in
                let isOpen = state.withLock { state in
                    state.runs += 1
                    if !state.isOpen { state.held.append(continuation) }
                    return state.isOpen
                }
                if isOpen { continuation.resume() }
            }
            return answer
        }

        func open() {
            let held = state.withLock { state in
                state.isOpen = true
                defer { state.held = [] }
                return state.held
            }
            for continuation in held { continuation.resume() }
        }

        var count: Int { state.withLock { $0.runs } }
    }

    nonisolated private struct Unreachable: Error {}

    private func reads(
        bound: Duration = .seconds(5), memory: Duration = .seconds(60), clock: Clock = Clock()
    ) -> AskSharedRead<String, Bool> {
        AskSharedRead(label: "test read", bound: bound, failureMemory: memory, now: { clock.now })
    }

    /// Spin until `condition` holds, or give up. Bounded, and it yields.
    private func spin(_ what: String, until condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<4_000 {
            if await condition() { return }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("timed out waiting for \(what)")
    }

    @Test func overlappingReadsShareOneRun() async throws {
        let reads = reads()
        let probe = Probe()
        let first = Task { await reads.value(for: "he") { await probe.held(true) } }
        try await spin("the first run") { probe.count == 1 }
        let others = (0..<4).map { _ in
            Task { await reads.value(for: "he") { await probe.held(true) } }
        }
        try await spin("every caller waiting") { await reads.waiting(for: "he") == 5 }
        #expect(probe.count == 1)
        probe.open()
        #expect(await first.value == true)
        for other in others { #expect(await other.value == true) }
        #expect(probe.count == 1)
    }

    @Test func anAnswerIsKeptForTheProcess() async {
        let clock = Clock()
        let reads = reads(clock: clock)
        let runs = Mutex(0)
        let read: @Sendable () async throws -> Bool = {
            runs.withLock { $0 += 1 }
            return false
        }
        #expect(await reads.value(for: "he", read: read) == false)
        clock.advance(.seconds(3_600))
        #expect(await reads.value(for: "he", read: read) == false)
        #expect(runs.withLock { $0 } == 1)
    }

    @Test func aReadThatThrewIsNoAnswerAndIsRememberedBriefly() async {
        // Each caller reads "could not say" its own way: the tier stays up and
        // the answer is written in English. Remembered for a minute, so the
        // next caller doesn't pay for the same failure again.
        let clock = Clock()
        let reads = reads(memory: .seconds(60), clock: clock)
        let runs = Mutex(0)
        let throwing: @Sendable () async throws -> Bool = {
            runs.withLock { $0 += 1 }
            throw Unreachable()
        }
        let answering: @Sendable () async throws -> Bool = {
            runs.withLock { $0 += 1 }
            return true
        }
        #expect(await reads.value(for: "he", read: throwing) == nil)
        clock.advance(.seconds(59))
        #expect(await reads.value(for: "he", read: answering) == nil)
        #expect(runs.withLock { $0 } == 1)
        // Never kept as an answer: once the minute is up, the tier is asked
        // again, and what it says then is kept.
        clock.advance(.seconds(2))
        #expect(await reads.value(for: "he", read: answering) == true)
        #expect(await reads.value(for: "he", read: throwing) == true)
        #expect(runs.withLock { $0 } == 2)
    }

    @Test func aStalledReadIsAbandonedAtItsBound() async {
        // A stalled network can't hold the turn that asked: the read gives up
        // at its bound, reads as no answer, and is remembered like a throw.
        let reads = reads(bound: .milliseconds(50))
        let runs = Mutex(0)
        let stalled: @Sendable () async throws -> Bool = {
            runs.withLock { $0 += 1 }
            try await Task.sleep(for: .seconds(30))
            return true
        }
        let started = ContinuousClock.now
        #expect(await reads.value(for: "he", read: stalled) == nil)
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(await reads.value(for: "he", read: stalled) == nil)
        #expect(runs.withLock { $0 } == 1)
    }

    @Test func aCancelledCallerStopsWaitingAndTheReadGoesOn() async throws {
        // A view torn down mid-refresh cancels its caller, not the read the
        // next caller is waiting on.
        let reads = reads()
        let probe = Probe()
        let cancelled = Task { await reads.value(for: "he") { await probe.held(true) } }
        try await spin("the first caller waiting") { await reads.waiting(for: "he") == 1 }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
        let next = Task { await reads.value(for: "he") { await probe.held(true) } }
        try await spin("the next caller waiting") { await reads.waiting(for: "he") == 1 }
        probe.open()
        #expect(await next.value == true)
        #expect(probe.count == 1)
    }

    @Test func eachKeyIsReadOnItsOwn() async {
        let reads = reads()
        let runs = Mutex<[String]>([])
        let hebrew: @Sendable () async throws -> Bool = {
            runs.withLock { $0.append("he") }
            return false
        }
        let french: @Sendable () async throws -> Bool = {
            runs.withLock { $0.append("fr") }
            return true
        }
        #expect(await reads.value(for: "he", read: hebrew) == false)
        #expect(await reads.value(for: "fr", read: french) == true)
        #expect(runs.withLock { $0 } == ["he", "fr"])
    }
}

#endif
