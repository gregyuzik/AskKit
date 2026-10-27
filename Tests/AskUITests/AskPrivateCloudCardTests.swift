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

    @Test func theResetTimeIsAppendedOnlyWhenThereIsOne() {
        let withoutDate = AskPrivateCloudState.limitReached.message(resetDate: nil)
        let withDate = AskPrivateCloudState.limitReached.message(
            resetDate: Date(timeIntervalSinceReferenceDate: 0)
        )
        #expect(!withoutDate.isEmpty)
        #expect(withDate.hasPrefix(withoutDate))
        #expect(withDate.count > withoutDate.count)
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
        #expect(AskPrivateCloudState.shown(for: status) == nil)

        status.apply(.init(nextTier: .onDevice, privateCloudUnavailability: .notEntitled))
        #expect(AskPrivateCloudState.shown(for: status) == .notEntitled)
        status.apply(.init(nextTier: .privateCloud))
        #expect(AskPrivateCloudState.shown(for: status) == .serving)
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
}

#endif
