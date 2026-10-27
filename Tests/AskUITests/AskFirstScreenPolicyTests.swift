#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// The two first-screen assumptions that aren't universal.
///
/// Both defaults describe a host whose Ask is about the reader's own library
/// and needs a model to say anything. A host whose subject exists whether or
/// not the reader has collected any of it, such as a guide to a city's parks,
/// and which answers several questions from its own data, is neither. Left to
/// the defaults, it would lose two behaviours silently: a "nothing to ask
/// about" screen for a reader who has saved nothing, and a dead end on every
/// device without Apple Intelligence. So the policy is pinned here rather than
/// trusted to a review.
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenPolicyTests {

    private func stage(
        overview: AskOverview,
        unavailability: AskUnavailability? = nil,
        policy: AskFirstScreenPolicy,
        hasNothingToAskCopy: Bool = true
    ) -> AskStage.Phase {
        AskStage.of(
            turns: [AskTurn<UIRow>](), isThinking: false,
            overview: overview, unavailability: unavailability, policy: policy,
            hasNothingToAskCopy: hasNothingToAskCopy
        ).phase
    }

    private let empty = AskOverview.empty
    private let owned = AskOverview(scopes: [.init(id: "r", name: "Records", count: 3)], total: 3)

    @Test func anOwnedLibraryIsTheDefaultAndUnchanged() {
        #expect(stage(overview: empty, policy: .ownedLibrary) == .nothingToAskAbout)
        #expect(stage(overview: owned, policy: .ownedLibrary) == .ready)
    }

    /// A host whose subject exists whether or not the reader has collected any
    /// of it is ready with an empty library.
    @Test func aDomainThatNeedsNoOwnedRowsIsNeverEmpty() {
        let policy = AskFirstScreenPolicy(needsOwnedRows: false)
        #expect(stage(overview: empty, policy: policy) == .ready)
        #expect(stage(overview: owned, policy: policy) == .ready)
    }

    /// A host whose subject isn't the reader's rows, and needs a model: the
    /// ready screen with nothing counted, and the reason without a model,
    /// with no starters under it.
    @Test func anOpenSubjectIsReadyWithNothingCountedAndNeedsAModel() {
        #expect(AskFirstScreenPolicy.openSubject == AskFirstScreenPolicy(answersWithoutModel: false, needsOwnedRows: false))
        #expect(!AskFirstScreenPolicy.openSubject.needsOwnedRows)
        #expect(!AskFirstScreenPolicy.openSubject.answersWithoutModel)
        #expect(stage(overview: empty, policy: .openSubject) == .ready)
        #expect(stage(overview: owned, policy: .openSubject) == .ready)
        #expect(stage(overview: empty, unavailability: .modelNotReady, policy: .openSubject) == .cannotServe(.modelNotReady))
    }

    /// No copy, no nothing-to-ask screen: a brand with no words for it gets
    /// the ready screen, as a policy that doesn't need owned rows does,
    /// rather than a mark with nothing under it.
    @Test func anEmptyLibraryWithNoCopyForItIsReady() {
        #expect(stage(overview: empty, policy: .ownedLibrary, hasNothingToAskCopy: false) == .ready)
        #expect(stage(overview: owned, policy: .ownedLibrary, hasNothingToAskCopy: false) == .ready)
        #expect(
            stage(overview: empty, unavailability: .deviceNotEligible, policy: .ownedLibrary, hasNothingToAskCopy: false)
                == .cannotServe(.deviceNotEligible)
        )
    }

    /// The reason still outranks everything: a reader who cannot be served
    /// needs to know that before being told anything else.
    @Test func theReasonStillComesFirst() {
        for policy in [AskFirstScreenPolicy.ownedLibrary, AskFirstScreenPolicy(answersWithoutModel: true, needsOwnedRows: false)] {
            #expect(
                stage(overview: empty, unavailability: .deviceNotEligible, policy: policy)
                    == .cannotServe(.deviceNotEligible)
            )
        }
    }

    /// A turn on the thread outranks every first screen, policy or no policy.
    @Test func aThreadOutranksEveryFirstScreen() {
        let turn = AskTurn<UIRow>(question: "q", origin: .typed)
        let phase = AskStage.of(
            turns: [turn], isThinking: false, overview: .empty,
            unavailability: .appleIntelligenceOff,
            policy: AskFirstScreenPolicy(answersWithoutModel: true, needsOwnedRows: false)
        ).phase
        #expect(phase == .thread)
    }

    /// No first screen until the model's state has been read as well as the
    /// library: before it, a device that can't serve reads as one that can,
    /// and the ready screen would offer starters for the length of a Private
    /// Cloud Compute probe.
    @Test func noFirstScreenUntilTheModelsStateIsRead() {
        func stage(overviewIsRead: Bool, statusIsRead: Bool) -> AskStage {
            AskStage.of(
                turns: [AskTurn<UIRow>](), isThinking: false, overview: owned, unavailability: nil,
                overviewIsRead: overviewIsRead, statusIsRead: statusIsRead
            )
        }
        #expect(!stage(overviewIsRead: true, statusIsRead: false).firstScreenIsKnown)
        #expect(!stage(overviewIsRead: false, statusIsRead: true).firstScreenIsKnown)
        #expect(stage(overviewIsRead: true, statusIsRead: true).firstScreenIsKnown)
        // A thread is known whatever is read.
        let thread = AskStage.of(
            turns: [AskTurn<UIRow>(question: "q", origin: .typed)], isThinking: false, overview: .empty,
            unavailability: nil, overviewIsRead: false, statusIsRead: false
        )
        #expect(thread.firstScreenIsKnown)
    }

    /// Two waits end sooner: a device that can't serve is known on the
    /// model's state alone, since its reason outranks the library, and an
    /// overview past its deadline is waited for no longer, opening the ready
    /// screen, since a library never read can't be called empty.
    @Test func cannotServeAndAnOverdueOverviewEndTheWait() {
        let cannotServe = AskStage.of(
            turns: [AskTurn<UIRow>](), isThinking: false, overview: .empty, unavailability: .deviceNotEligible,
            overviewIsRead: false, statusIsRead: true
        )
        #expect(cannotServe.firstScreenIsKnown)
        #expect(cannotServe.phase == .cannotServe(.deviceNotEligible))
        let overdue = AskStage.of(
            turns: [AskTurn<UIRow>](), isThinking: false, overview: .empty, unavailability: nil,
            overviewIsRead: false, overviewIsOverdue: true, statusIsRead: true
        )
        #expect(overdue.firstScreenIsKnown)
        #expect(overdue.phase == .ready)
        // Neither before the model's state is read.
        let unread = AskStage.of(
            turns: [AskTurn<UIRow>](), isThinking: false, overview: .empty, unavailability: nil,
            overviewIsRead: false, overviewIsOverdue: true, statusIsRead: false
        )
        #expect(!unread.firstScreenIsKnown)
    }

    /// A snapshot that names a tier and a reason none can serve says two
    /// things; the tier wins, so the can't-serve screen never covers a tier
    /// that answers.
    @MainActor
    @Test func aSnapshotWithATierAndAReasonReadsAsTheTierServing() {
        let status = AskModelStatus()
        status.apply(.init(nextTier: .onDevice, unavailability: .appleIntelligenceOff))
        #expect(status.nextTier == .onDevice)
        #expect(status.unavailability == nil)
        #expect(status.hasHeardFromSeam)
        status.apply(.init(nextTier: nil, unavailability: .deviceNotEligible))
        #expect(status.unavailability == .deviceNotEligible)
    }

    @Test func theDefaultsAreTheOwnedLibraryOnes() {
        let fresh = AskFirstScreenPolicy()
        #expect(fresh == .ownedLibrary)
        #expect(!fresh.answersWithoutModel)
        #expect(fresh.needsOwnedRows)
    }
}

#endif
