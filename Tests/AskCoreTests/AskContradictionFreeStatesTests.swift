import Foundation
import Testing

@testable import AskCore

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// Three shapes that once let a value contradict itself, and the readings each
/// contradiction was papered over with. None of them can be written any more,
/// which no test can show by compiling them; what these show is that every
/// value the new shapes can hold reads one way.
///
/// - A tier's state: down with no reason (`isAvailable: false,
///   unavailability: nil`), which read as `.unknown`, and up with one.
///   Availability is now read from `unavailability` alone.
/// - A retry-after reading: a rate limit with no date (`date: nil, isQuota:
///   false`), which no failure gives. A rate limit's date is now its own.
/// - An evaluation's outcome: `isUngrounded` beside a `failure` that was nil
///   or said something else. Whether a turn failed as ungrounded is now read
///   off its one failure value.
@Suite(.timeLimit(.minutes(1))) struct AskContradictionFreeStatesTests {

    // MARK: - A tier's state

    private let reasons: [AskUnavailability?] = [nil] + AskUnavailability.allCases.map(Optional.some)

    /// Whatever else a tier's state says, it is available exactly when it
    /// gives no reason it isn't.
    @Test func aTierIsAvailableExactlyWhenItGivesNoReason() {
        for reason in reasons {
            for flags in 0..<16 {
                let state = AskTierState(
                    tier: flags & 1 == 0 ? .privateCloud : .onDevice, speaksLanguage: flags & 2 != 0,
                    quotaReached: flags & 4 != 0, isCooled: flags & 8 != 0, unavailability: reason
                )
                #expect(state.isAvailable == (reason == nil), "\(state)")
            }
        }
    }

    /// A tier that is down says why, so the reason the reader is told is the
    /// on-device tier's own, `.unknown` only when that is what it said.
    @Test func aDownTierIsNeverReadAsUnknownUnlessItSaidSo() {
        for reason in AskUnavailability.allCases {
            let states = [
                AskTierState(tier: .privateCloud, speaksLanguage: true, unavailability: .offline),
                AskTierState(tier: .onDevice, speaksLanguage: true, unavailability: reason)
            ]
            #expect(askServableTiers(from: states).isEmpty)
            #expect(askUnavailability(from: states) == reason)
        }
    }

    /// A tier that gives a reason is down, however its other fields read:
    /// never servable, and never the held tier a turn is asked through.
    @Test func aTierWithAReasonIsNeverServedNorHeld() {
        for reason in AskUnavailability.allCases {
            let cloud = AskTierState(
                tier: .privateCloud, speaksLanguage: true, quotaReached: true, isCooled: true, unavailability: reason
            )
            #expect(!cloud.isAvailable && !cloud.isServable)
            #expect(askHeldTier(from: [cloud]) == nil)
        }
    }
}

#if canImport(FoundationModels) && !os(tvOS)

extension AskContradictionFreeStatesTests {

    // MARK: - A retry-after reading

    /// A rate limit is a reading only with the reset it named, and that date
    /// is the case's own, not an optional one beside it; only a quota's reset
    /// can be missing, and a quota without one is still a quota.
    @Test func aRateLimitsReadingAlwaysCarriesItsDate() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_060)
        let dated = LanguageModelError.rateLimited(.init(resetDate: reset, debugDescription: "slow down"))
        let reading = try #require(AskTriage.retryAfter(from: dated))
        switch reading {
        case .rateLimited(let until):
            let date: Date = until
            #expect(date == reset)
        case .quotaReached:
            Issue.record("a rate limit read as the quota")
        }
        let undated = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "slow down"))
        #expect(AskTriage.retryAfter(from: undated) == nil)

        let spent = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            .init(resetDate: nil, debugDescription: "spent")
        )
        #expect(AskTriage.retryAfter(from: spent) == .quotaReached(resetDate: nil))
    }
}
#endif

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)

extension AskContradictionFreeStatesTests {

    // MARK: - An evaluation's failure

    private func makeEval(
        states: [AskTierState] = [.serving(.privateCloud), .serving(.onDevice)]
    ) -> (AskEval<FakeDomain>, FakeSeam) {
        let domain = FakeDomain()
        let seam = FakeSeam(status: AskModelStatus(), states: states, bridge: domain.bridge)
        return (AskEval(domain: domain, seam: seam, log: FakeLogSink()), seam)
    }

    /// The verdict cell of a table row: the text between its last two bars.
    private func verdict(of row: String) -> String {
        let cells = row.split(separator: "|", omittingEmptySubsequences: false)
        return cells[cells.count - 2].trimmingCharacters(in: .whitespaces)
    }

    /// Only an ungrounded error is ungrounded, and an outcome with no failure
    /// has nothing to be ungrounded in: the flag and the failure can't
    /// disagree, and a good outcome is one with neither.
    @Test func onlyAnUngroundedFailureIsUngrounded() async {
        #expect(AskOutcome.Failure.error(.ungrounded).isUngrounded)
        let others: [AskOutcome.Failure] = [.error(.refused), .error(.couldNotAnswer), .untyped(tag: "ungrounded"), .noAnswer]
        #expect(!others.contains { $0.isUngrounded })

        var outcome = AskOutcome(id: "clean")
        #expect(outcome.failure?.isUngrounded == nil && outcome.isGood)
        outcome.failure = .error(.ungrounded)
        #expect(!outcome.isGood)

        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(FakeSession.Script(error: AskError.ungrounded, toolCallsAfter: 1))
        let ungrounded = await eval.run(AskScenario(id: "ungrounded", question: "q"))
        #expect(ungrounded.failure == .error(.ungrounded))
        #expect(ungrounded.failure?.isUngrounded == true && !ungrounded.isGood)
    }

    /// Each failure as the table spells it: the error as Swift describes it,
    /// the tag as it stands, and "no answer".
    @Test func eachFailureIsSpelledAsTheTablePrintedIt() {
        #expect(AskOutcome.Failure.error(.refused).description == "refused")
        #expect(AskOutcome.Failure.error(.quotaReached(resetDate: nil)).description
                == String(describing: AskError.quotaReached(resetDate: nil)))
        #expect(AskOutcome.Failure.untyped(tag: "NSURLErrorDomain#-1009").description == "NSURLErrorDomain#-1009")
        #expect(AskOutcome.Failure.noAnswer.description == "no answer")
        var outcome = AskOutcome(id: "tagged")
        outcome.failure = .untyped(tag: "NSURLErrorDomain#-1009")
        #expect(outcome.verdict == "NSURLErrorDomain#-1009")
    }

    /// The table's verdict for each way a run fails, pinned as text, so the
    /// reading a developer compares across runs stays the same words.
    @Test func theTablesVerdictReadsAsItDidForEveryFailure() async {
        let (down, _) = makeEval(states: [
            .down(.privateCloud, .notEntitled), .down(.onDevice, .appleIntelligenceOff)
        ])
        let unserved = await down.run(AskScenario(id: "down", question: "q"))

        let (eval, seam) = makeEval()
        let session = seam.session(for: .privateCloud)
        session.script(FakeSession.Script(error: AskError.ungrounded, toolCallsAfter: 1))
        let ungrounded = await eval.run(AskScenario(id: "ungrounded", question: "q"))
        session.script(FakeSession.Script(error: AskError.model(tag: "SomeError#7"), toolCallsAfter: 1))
        let tagged = await eval.run(AskScenario(id: "tagged", question: "q"))

        var script = FakeSession.Script(snapshots: [.answering("Rumours.")], toolCallsAfter: 1)
        script.holdsAfterSnapshots = true
        session.script(script)
        let run = Task { await eval.run(AskScenario(id: "let go", question: "q")) }
        await session.generationIsHeld()
        run.cancel()
        let letGo = await run.value
        session.releaseGeneration()

        #expect(unserved.failure == .error(.modelUnavailable(.appleIntelligenceOff)))
        #expect(letGo.failure == .noAnswer)
        let lines = AskEval<FakeDomain>.table([unserved, ungrounded, tagged, letGo])
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(verdict(of: lines[2]) == "modelUnavailable(AskCore.AskUnavailability.appleIntelligenceOff)")
        #expect(verdict(of: lines[3]) == "ungrounded")
        #expect(verdict(of: lines[4]) == #"model(tag: "SomeError#7")"#)
        #expect(verdict(of: lines[5]) == "no answer")
        #expect(lines.last == "0/4 grounded, clean and as expected.")
    }
}

#endif
