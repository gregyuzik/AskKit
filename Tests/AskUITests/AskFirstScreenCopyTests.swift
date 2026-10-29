#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Which first screen an empty thread shows, by the host's nothing-to-ask
/// copy (`AskBrand.nothingToAskCopy`), whose presence is the whole policy.
///
/// With it, the host's Ask is about the reader's own library, and an empty
/// one has nothing to ask about. Without it, the host's subject exists whether
/// or not the reader has collected any of it, such as a guide to a city's
/// parks, and a reader who has saved nothing is ready to ask. Pinned here
/// rather than trusted to a review, since either mistake is silent: a reader
/// told there is nothing to ask about while their question works, or a mark
/// with nothing under it.
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenCopyTests {

    private func stage(
        overview: AskOverview,
        unavailability: AskUnavailability? = nil,
        hasNothingToAskCopy: Bool
    ) -> AskStage.Phase {
        AskStage.of(
            turns: [AskTurn<UIRow>](), isThinking: false,
            overview: overview, unavailability: unavailability,
            hasNothingToAskCopy: hasNothingToAskCopy
        ).phase
    }

    private let empty = AskOverview.empty
    private let owned = AskOverview(scopes: [.init(id: "r", name: "Records", count: 3)], total: 3)

    /// With copy, an empty library has nothing to ask about, and one with
    /// something in it is ready.
    @Test func withCopyAnEmptyLibraryHasNothingToAskAbout() {
        #expect(stage(overview: empty, hasNothingToAskCopy: true) == .nothingToAskAbout)
        #expect(stage(overview: owned, hasNothingToAskCopy: true) == .ready)
    }

    /// Without copy, the ready screen whatever the overview counts, rather
    /// than a mark with nothing under it, and the reason where nothing can
    /// serve.
    @Test func withoutCopyAnEmptyLibraryIsReady() {
        #expect(stage(overview: empty, hasNothingToAskCopy: false) == .ready)
        #expect(stage(overview: owned, hasNothingToAskCopy: false) == .ready)
        #expect(
            stage(overview: empty, unavailability: .modelNotReady, hasNothingToAskCopy: false)
                == .cannotServe(.modelNotReady)
        )
    }

    /// The stage's own default is a host with copy: the screen it showed when
    /// a policy defaulted to the reader's own library.
    @Test func theStagesDefaultIsAHostWithCopy() {
        let phase = AskStage.of(turns: [AskTurn<UIRow>](), isThinking: false, overview: empty, unavailability: nil).phase
        #expect(phase == .nothingToAskAbout)
    }

    /// The reason still outranks everything: a reader who cannot be served
    /// needs to know that before being told anything else.
    @Test func theReasonStillComesFirst() {
        for hasNothingToAskCopy in [true, false] {
            #expect(
                stage(overview: empty, unavailability: .deviceNotEligible, hasNothingToAskCopy: hasNothingToAskCopy)
                    == .cannotServe(.deviceNotEligible)
            )
        }
    }

    /// A turn on the thread outranks every first screen, copy or no copy.
    @Test func aThreadOutranksEveryFirstScreen() {
        let turn = AskTurn<UIRow>(question: "q", origin: .typed)
        for hasNothingToAskCopy in [true, false] {
            let phase = AskStage.of(
                turns: [turn], isThinking: false, overview: .empty,
                unavailability: .appleIntelligenceOff, hasNothingToAskCopy: hasNothingToAskCopy
            ).phase
            #expect(phase == .thread)
        }
    }

    /// The domain's word that it answers without a model keeps the composer
    /// live where nothing can serve, and the brand's copy alone decides
    /// whether an empty library has nothing to ask about: the two reach the
    /// store from where the host states them, and neither moves the other.
    @MainActor
    @Test func theComposerStaysLiveForADomainThatAnswersWithoutAModel() async {
        for answersWithoutModel in [false, true] {
            var domain = UIDomain()
            domain.rows = []
            domain.answersWithoutModel = answersWithoutModel
            let store = makeStore(domain: domain, asker: ScriptedAsker())
            store.status.apply(.init(nextTier: .onDevice))
            await store.refresh()
            #expect(store.stage.phase == .nothingToAskAbout, "\(answersWithoutModel)")
            #expect(!store.composerIsDisabled, "\(answersWithoutModel)")

            store.status.apply(.init(nextTier: nil, unavailability: .appleIntelligenceOff))
            #expect(store.stage.phase == .cannotServe(.appleIntelligenceOff), "\(answersWithoutModel)")
            #expect(store.composerIsDisabled == !answersWithoutModel, "\(answersWithoutModel)")
        }
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
}

#endif
