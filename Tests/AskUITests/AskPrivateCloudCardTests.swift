#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// The settings card is the one surface that tells a reader *why* their answers
/// stopped coming from Private Cloud Compute. Every branch of that mapping is
/// invisible on the machine that writes it — an unentitled simulator build shows
/// one state and one state only — so it is pinned here rather than by looking at
/// it.
@Suite(.timeLimit(.minutes(1))) struct AskPrivateCloudCardTests {

    @Test func aSpentQuotaOutranksEveryOtherReason() {
        // The tier is UP and out of turns. Reading it as "unavailable" would
        // send the reader looking for a setting that would not help.
        let state = AskPrivateCloudState.of(
            quotaReached: true, quotaApproaching: true, unavailability: .offline
        )
        #expect(state == .limitReached)
        #expect(!state.isServing)
    }

    @Test func anApproachingQuotaStillServes() {
        let state = AskPrivateCloudState.of(
            quotaReached: false, quotaApproaching: true, unavailability: nil
        )
        #expect(state == .approachingLimit)
        #expect(state.isServing)
    }

    @Test func everyReasonHasItsOwnLine() {
        let mapping: [(AskUnavailability?, AskPrivateCloudState)] = [
            (nil, .serving),
            (.notEntitled, .notEntitled),
            (.deviceNotEligible, .deviceNotEligible),
            (.offline, .offline),
            (.languageNotSupported, .languageNotSupported),
            (.systemNotReady, .unavailable),
            (.modelNotReady, .unavailable),
            (.appleIntelligenceOff, .unavailable),
            (.unknown, .unavailable)
        ]
        for (reason, expected) in mapping {
            let state = AskPrivateCloudState.of(
                quotaReached: false, quotaApproaching: false, unavailability: reason
            )
            #expect(state == expected, "\(String(describing: reason)) mapped to \(state)")
        }
    }

    /// Every `AskUnavailability` reaches a state, including one added after this
    /// build — the enum is `CaseIterable` precisely so a new case cannot slip
    /// through as a blank line.
    @Test func noReasonFallsThroughToNothing() {
        for reason in AskUnavailability.allCases {
            let state = AskPrivateCloudState.of(
                quotaReached: false, quotaApproaching: false, unavailability: reason
            )
            #expect(!state.isServing)
            #expect(!state.message().isEmpty)
        }
    }

    /// A wall time in the reader's own calendar and time zone, in the middle
    /// of June and away from any clock change, so the same wall times are the
    /// same days wherever the test runs (`AskDateLineTests`).
    private func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)))
    }

    @Test func aResetLaterTodayReadsAsItsTime() throws {
        let now = try date(day: 10, hour: 14)
        let reset = try date(day: 10, hour: 17)
        let reached = AskPrivateCloudState.limitReached.message(resetDate: nil)
        let line = AskQuotaBanner.line(resetDate: reset, now: now)
        #expect(!reached.isEmpty)
        #expect(line.hasPrefix(reached))
        #expect(line.contains(reset.formatted(date: .omitted, time: .shortened)))
        #expect(!line.contains(reset.formatted(.dateTime.weekday(.wide))))
    }

    /// **A reset on a later day names the day**, tomorrow's and one days
    /// off alike: a time alone is read as its next coming.
    @Test func aResetOnALaterDayNamesItsDay() throws {
        let now = try date(day: 10, hour: 23)
        let reached = AskPrivateCloudState.limitReached.message(resetDate: nil)
        for reset in [try date(day: 11, hour: 5), try date(day: 14, hour: 9, minute: 30)] {
            let line = AskQuotaBanner.line(resetDate: reset, now: now)
            #expect(line.hasPrefix(reached))
            #expect(line.count > reached.count)
            #expect(line.contains(reset.formatted(.dateTime.weekday(.wide))), "\(line)")
        }
    }

    /// **A reset already past says nothing about when.** A stale date read
    /// as a bare time says that time tomorrow, which nothing has said.
    @Test func aResetAlreadyPastLeavesTheLimitSentenceAlone() throws {
        let now = try date(day: 10, hour: 14)
        let reached = AskPrivateCloudState.limitReached.message(resetDate: nil)
        for reset in [try date(day: 10, hour: 9), try date(day: 9, hour: 17), now] {
            #expect(AskQuotaBanner.line(resetDate: reset, now: now) == reached)
        }
        #expect(AskQuotaBanner.line(resetDate: nil, now: now) == reached)
    }

    /// The card and the banner say the same of a spent quota: one line, the
    /// banner's, and not two copies that drift.
    @Test func theCardAtTheLimitSaysWhatTheBannerSays() {
        for offset: TimeInterval in [-3_600, 60, 3_600, 86_400 * 3] {
            let reset = Date.now.addingTimeInterval(offset)
            #expect(AskPrivateCloudState.limitReached.message(resetDate: reset) == AskQuotaBanner.line(resetDate: reset))
        }
        #expect(AskPrivateCloudState.limitReached.message(resetDate: nil) == AskQuotaBanner.line(resetDate: nil))
    }

    /// The limit sentence comes from AskCore, so the thread and the settings
    /// card cannot disagree about what a spent quota says.
    @Test func theLimitSentenceIsTheOneAskCoreOwns() {
        #expect(
            AskPrivateCloudState.limitReached.message(resetDate: nil)
                == AskError.quotaReached(resetDate: nil).errorDescription
        )
    }

    /// A mirror its seam hasn't published to names no reason, which is what
    /// a serving tier looks like. The card says nothing until it knows, so a
    /// settings screen opened before the Ask screen never claims Private
    /// Cloud Compute on a build that has none.
    @MainActor
    @Test func theCardMakesNoClaimUntilTheMirrorHasHeardFromItsSeam() {
        let status = AskModelStatus()
        #expect(!status.hasHeardFromSeam)
        #expect(AskPrivateCloudState.of(status) == nil)

        status.apply(.init(nextTier: .onDevice, privateCloudUnavailability: .notEntitled))
        #expect(AskPrivateCloudState.of(status) == .notEntitled)
        status.apply(.init(nextTier: .privateCloud))
        #expect(AskPrivateCloudState.of(status) == .serving)
    }

    /// Once it has heard, the mirror reads as its three fields do: the one
    /// public accessor and the mapping can't disagree.
    @MainActor
    @Test func aMirrorThatHasHeardReadsAsItsFields() {
        let status = AskModelStatus()
        status.apply(.init(nextTier: .onDevice, privateCloudUnavailability: .offline))
        #expect(AskPrivateCloudState.of(status) == .of(quotaReached: false, quotaApproaching: false, unavailability: .offline))
    }

    /// The diagnostics rows' *code* compiles in Release, and only whether they
    /// show is decided at run time. A TestFlight build is a Release build, and
    /// a signed build on a device is the only place Private Cloud Compute can
    /// actually be measured, so the rows have to be reachable there.
    @Test func theDiagnosticsRowsAreDecidedAtRunTime() {
        #expect(AskDiagnostics.isEnabled == (AskDiagnostics.isDebugBuild || AskDiagnostics.isTestFlight))
        // `swift test` is a Debug build, so the rows are on here, which is the
        // point: whether they show is read, not compiled away.
        #expect(AskDiagnostics.isDebugBuild)
    }

    /// A card the host left to itself follows `AskDiagnostics.isEnabled`,
    /// read as it draws, so the rows come when StoreKit says this is a
    /// TestFlight build; one the host decided keeps the host's word.
    @Test func aCardLeftToItselfFollowsTheSwitch() {
        #expect(AskPrivateCloudCard.showsDiagnostics(nil) == AskDiagnostics.isEnabled)
        #expect(AskPrivateCloudCard.showsDiagnostics(true))
        #expect(!AskPrivateCloudCard.showsDiagnostics(false))
    }
}

/// The evaluation row's run (`AskEvalRun`): one at a time, and over when the
/// card goes, never when the row does.
///
/// **A row's coming back never starts a run.** Tied to the row's appearance,
/// as a `.task(id:)` ties it, a row scrolled away and back, or under a page
/// pushed and popped, would start the evaluation over while it was still
/// asked for, and spend Private Cloud Compute's quota a second time.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskEvalRunTests {

    /// How many times a run's body began, and a latch it waits on.
    private actor Probe {
        private(set) var starts = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var open = false

        func begin() async {
            starts += 1
            guard !open else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            open = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    @Test func aRunAskedForWhileOneIsUnderWayIsThatRun() async {
        let probe = Probe()
        let run = AskEvalRun()
        let body: @Sendable () async -> String = {
            await probe.begin()
            return "report"
        }
        run.start(body)
        let task = run.task
        // What a row coming back would ask of a `.task(id:)`: the same run
        // again, while the first is still under way.
        run.start(body)
        run.start(body)
        #expect(run.isRunning)
        #expect(run.task == task)
        await probe.release()
        await task?.value
        #expect(await probe.starts == 1)
        #expect(run.report == "report")
        #expect(!run.isRunning)
    }

    @Test func aFinishedRunCanBeAskedForAgain() async {
        let probe = Probe()
        await probe.release()
        let run = AskEvalRun()
        run.start { await probe.begin(); return "first" }
        await run.task?.value
        #expect(run.report == "first")
        #expect(run.task == nil)
        run.start { await probe.begin(); return "second" }
        #expect(run.isRunning)
        await run.task?.value
        #expect(run.report == "second")
        #expect(await probe.starts == 2)
    }

    /// **The card's going cancels the run**, so leaving Settings stops an
    /// evaluation that would otherwise go on spending the quota for a report
    /// nothing shows.
    @Test func theRunEndsWithTheCard() async {
        let (cancelled, signal) = AsyncStream<Void>.makeStream()
        var run: AskEvalRun? = AskEvalRun()
        run?.start {
            await withTaskCancellationHandler {
                try? await Task.sleep(for: .seconds(120))
            } onCancel: {
                signal.yield()
            }
            return "never shown"
        }
        #expect(run?.isRunning == true)
        run = nil
        var heard = cancelled.makeAsyncIterator()
        #expect(await heard.next() != nil)
    }
}

#endif
