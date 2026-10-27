import Foundation
import Testing

@testable import AskCore

/// Tier selection, the unavailability reason, and what counts as an outage —
/// the three decisions a turn makes before it sends anything.
@Suite(.timeLimit(.minutes(1))) struct AskPolicyTests {

    private func state(
        _ tier: AskTier, available: Bool = true, language: Bool = true,
        quota: Bool = false, cooled: Bool = false, why: AskUnavailability? = nil
    ) -> AskTierState {
        AskTierState(tier: tier, isAvailable: available, speaksLanguage: language,
                     quotaReached: quota, isCooled: cooled, unavailability: why)
    }

    // MARK: - Servability

    @Test func privateCloudLeadsWhenBothServe() {
        let tiers = askServableTiers(from: [state(.privateCloud), state(.onDevice)])
        #expect(tiers == [.privateCloud, .onDevice])
    }

    @Test func aReachedQuotaExcludesPrivateCloudAtTurnStart() {
        let tiers = askServableTiers(from: [state(.privateCloud, quota: true), state(.onDevice)])
        #expect(tiers == [.onDevice])
    }

    @Test func anApproachingQuotaDemotesNothing() {
        // A quota excludes Private Cloud Compute only once it is reached.
        // Demoting on an approaching one would be the same downgrade one step
        // earlier, while the tier could still answer.
        let approaching = AskTierState(
            tier: .privateCloud, isAvailable: true, speaksLanguage: true, quotaReached: false
        )
        #expect(askServableTiers(from: [approaching, state(.onDevice)]).first == .privateCloud)
    }

    @Test func aCooledTierSitsOut() {
        #expect(askServableTiers(from: [state(.privateCloud, cooled: true), state(.onDevice)])
                == [.onDevice])
    }

    @Test func aTierThatCannotSpeakTheLanguageCannotServe() {
        #expect(askServableTiers(from: [state(.privateCloud, language: false), state(.onDevice)])
                == [.onDevice])
    }

    @Test func nothingServesWhenBothAreDown() {
        #expect(askServableTiers(from: [
            state(.privateCloud, available: false, why: .systemNotReady),
            state(.onDevice, available: false, why: .appleIntelligenceOff)
        ]).isEmpty)
    }

    // MARK: - Why not

    @Test func languageOutranksAvailability() {
        // The one case where "turn on Apple Intelligence" is not merely
        // unhelpful but wrong: it is already on. Hebrew.
        let why = askUnavailability(from: [
            state(.privateCloud, language: false),
            state(.onDevice, language: false)
        ])
        #expect(why == .languageNotSupported)
    }

    @Test func theOnDeviceReasonIsTheHonestOne() {
        // Private Cloud Compute can be out for reasons of its own that say
        // nothing about whether Ask could work at all.
        let why = askUnavailability(from: [
            state(.privateCloud, available: false, why: .notEntitled),
            state(.onDevice, available: false, why: .deviceNotEligible)
        ])
        #expect(why == .deviceNotEligible)
    }

    @Test func eachOnDeviceReasonSurvives() {
        for reason in [AskUnavailability.appleIntelligenceOff, .deviceNotEligible, .modelNotReady] {
            let why = askUnavailability(from: [
                state(.privateCloud, available: false, why: .systemNotReady),
                state(.onDevice, available: false, why: reason)
            ])
            #expect(why == reason)
        }
    }

    @Test func noStatesAtAllReadsAsUnknown() {
        #expect(askUnavailability(from: []) == .unknown)
    }

    // MARK: - Outage

    @Test func onlyTheTiersOwnFailuresAreOutages() {
        #expect(askIsTierOutage(.privateCloudUnreachable))
        #expect(askIsTierOutage(.quotaReached(resetDate: nil)))
    }

    @Test func aVerdictOnTheQuestionIsNotAnOutage() {
        // A smaller model reaches the same verdict, and its window is four times
        // smaller so it overflows harder. `model(tag:)` is unclassified by
        // definition and must not license re-running every unknown failure.
        #expect(!askIsTierOutage(.refused))
        #expect(!askIsTierOutage(.contextTooLarge))
        #expect(!askIsTierOutage(.ungrounded))
        #expect(!askIsTierOutage(.couldNotAnswer))
        #expect(!askIsTierOutage(.model(tag: "whatever")))
        #expect(!askIsTierOutage(.stopped))
        #expect(!askIsTierOutage(.modelUnavailable(.unknown)))
    }

    @Test func aPhotoTheSessionCantTakeIsNotAnOutage() {
        // A fact about the session, not the tier's health: the tier below reads
        // no photos at all.
        #expect(!askIsTierOutage(.photosNotSupported))
    }

    // MARK: - Retryability

    @Test func whatOffersTryAgain() {
        #expect(AskError.couldNotAnswer.isRetryable)
        #expect(AskError.ungrounded.isRetryable)
        #expect(AskError.privateCloudUnreachable.isRetryable)
        #expect(AskError.quotaReached(resetDate: nil).isRetryable)
        #expect(AskError.model(tag: "x").isRetryable)
        #expect(AskError.stopped.isRetryable)
    }

    @Test func whatDoesNot() {
        // A refusal and an overflow are verdicts on the question; no model at
        // all needs Settings, not a retry.
        #expect(!AskError.refused.isRetryable)
        #expect(!AskError.contextTooLarge.isRetryable)
        #expect(!AskError.modelUnavailable(.appleIntelligenceOff).isRetryable)
        // Asking again with the photo fails the same way.
        #expect(!AskError.photosNotSupported.isRetryable)
    }

    @Test func aPhotoTheSessionCantTakeHasItsOwnLine() {
        // Not the unavailable-model line: a model was there, and answers
        // the same question without the photo.
        let line = AskError.photosNotSupported.errorDescription
        #expect(line != nil)
        #expect(line != AskError.modelUnavailable(.unknown).errorDescription)
        #expect(line != AskError.couldNotAnswer.errorDescription)
    }

    @Test func aPhotoTheSessionCantTakeIsKeptOnDiskByItsName() throws {
        // A failed turn persists its case, not its sentence.
        let encoded = try JSONEncoder().encode(AskError.photosNotSupported)
        #expect(String(bytes: encoded, encoding: .utf8)?.contains("photosNotSupported") == true)
        #expect(try JSONDecoder().decode(AskError.self, from: encoded) == .photosNotSupported)
    }

    @Test func everyErrorHasCopy() {
        let errors: [AskError] = [
            .couldNotAnswer, .ungrounded, .refused, .privateCloudUnreachable,
            .contextTooLarge, .photosNotSupported, .quotaReached(resetDate: nil), .model(tag: "x"), .stopped
        ] + AskUnavailability.allCases.map { AskError.modelUnavailable($0) }
        for error in errors {
            let message = error.errorDescription
            #expect(message?.isEmpty == false, "\(error) has no copy")
        }
    }

    @Test func everyUnavailabilityReasonHasItsOwnLineOrASharedOne() {
        // Four reasons get their own sentence; the rest share the neutral line.
        let distinct = Set(AskUnavailability.allCases.map(AskError.unavailableMessage))
        #expect(distinct.count == 5)
    }
}
