import AskCore
import Foundation
import Testing

/// The shapes that can't contradict themselves, built, switched over and read
/// as a host without the posture does: no `swiftSettings`, so nonisolated by
/// default (`CrossPostureTests` says why the target has none). A tier's
/// availability read from its reason, a retry-after reading's two cases, and
/// an evaluation's one failure value.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureContradictionFreeStatesTests {

    /// A seam of a host's own says why a tier is down, and its availability
    /// is read from that, off any actor.
    @Test func aTiersAvailabilityIsReadFromItsReasonWithoutThePosture() {
        let down = AskTierState(tier: .privateCloud, speaksLanguage: true, isCooled: true, unavailability: .offline)
        #expect(!down.isAvailable && down.unavailability == .offline && !down.isServable)
        let up = AskTierState(tier: .onDevice, speaksLanguage: true)
        #expect(up.isAvailable && up.unavailability == nil && up.isServable)
    }
}

#if canImport(FoundationModels) && !os(tvOS)

extension CrossPostureContradictionFreeStatesTests {

    /// A retry-after reading switched over, as a host's own router does with
    /// what its sessions' failures say, off any actor, ending in
    /// `@unknown default` since `AskRetryAfter` is open.
    @Test func aRetryAfterReadingIsSwitchedOverWithoutThePosture() {
        let reset = Date(timeIntervalSinceReferenceDate: 0)
        let readings: [AskRetryAfter] = [.rateLimited(until: reset), .quotaReached(resetDate: nil)]
        let resets = readings.map { reading -> Date? in
            switch reading {
            case .rateLimited(let until): until
            case .quotaReached(let resetDate): resetDate
            @unknown default: nil
            }
        }
        #expect(resets == [reset, nil])
    }

    /// An outcome's failure, set and read as a host's own eval test does, off
    /// any actor: whether it was ungrounded, and how the table spells it.
    @Test func anOutcomesFailureIsReadWithoutThePosture() {
        var outcome = AskOutcome(id: "count")
        outcome.failure = .error(.ungrounded)
        #expect(outcome.failure?.isUngrounded == true && !outcome.isGood)
        let failures: [AskOutcome.Failure] = [.error(.refused), .untyped(tag: "NSURLErrorDomain#-1009"), .noAnswer]
        #expect(!failures.contains { $0.isUngrounded })
        #expect(failures.map(\.description) == ["refused", "NSURLErrorDomain#-1009", "no answer"])
    }
}

#endif
