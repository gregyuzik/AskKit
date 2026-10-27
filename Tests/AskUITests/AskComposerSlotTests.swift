#if os(iOS) || os(macOS) || os(visionOS)

import Testing

@testable import AskUI

/// A host's tab bar slot: where the composer rests, when the face shows, what
/// covers it or empties it, and what the face's circle does.
@Suite(.timeLimit(.minutes(1))) struct AskComposerSlotTests {
    @Test func theComposerRestsInTheSlotOnlyWhereTheBarRunsAlongTheBottom() {
        #expect(AskComposerSlotPolicy.rests(isEnabled: true, tabBarRunsAlongBottom: true))
        #expect(!AskComposerSlotPolicy.rests(isEnabled: true, tabBarRunsAlongBottom: false))
        #expect(!AskComposerSlotPolicy.rests(isEnabled: false, tabBarRunsAlongBottom: true))
    }

    /// What the Ask screen reports decides, whatever the width: iPhone Duo's
    /// inner display is regular width with its tab bar along the bottom, and
    /// an iPad at regular width hangs the bar off the top. Compact width
    /// stands in only until the screen has reported.
    @Test func theTabBarsPlacementDecidesAndCompactWidthStandsInUntilItIsReported() {
        #expect(AskComposerSlotPolicy.tabBarRunsAlongBottom(reported: true, isCompactWidth: false))
        #expect(!AskComposerSlotPolicy.tabBarRunsAlongBottom(reported: false, isCompactWidth: true))
        #expect(AskComposerSlotPolicy.tabBarRunsAlongBottom(reported: nil, isCompactWidth: true))
        #expect(!AskComposerSlotPolicy.tabBarRunsAlongBottom(reported: nil, isCompactWidth: false))
    }

    /// The face is in the slot wherever the composer rests, from the tab's
    /// first frame, and only an item pushed over the thread takes it away.
    @Test func theFaceShowsWithTheTabUnlessThePushedItemCoversTheScreen() {
        #expect(AskComposerSlotPolicy.showsFace(rests: true, isCovered: false, composerIsHeldUp: false))
        #expect(!AskComposerSlotPolicy.showsFace(rests: true, isCovered: true, composerIsHeldUp: false))
        #expect(!AskComposerSlotPolicy.showsFace(rests: false, isCovered: false, composerIsHeldUp: false))
        #expect(!AskComposerSlotPolicy.showsFace(rests: false, isCovered: true, composerIsHeldUp: false))
    }

    /// A composer held up where no keyboard came empties the slot, so it
    /// comes up in the face's place rather than over its own face. Only the
    /// face goes: where the host shows its own accessory on the Ask tab, the
    /// slot holds that, as it does under a push.
    @Test func aComposerHeldUpWithNoKeyboardEmptiesTheSlot() {
        #expect(!AskComposerSlotPolicy.showsFace(rests: true, isCovered: false, composerIsHeldUp: true))
        #expect(!AskComposerSlotPolicy.showsFace(rests: true, isCovered: true, composerIsHeldUp: true))
        #expect(!AskComposerSlotPolicy.showsFace(rests: false, isCovered: false, composerIsHeldUp: true))
        let heldUp = AskComposerSlotPolicy.showsFace(rests: true, isCovered: false, composerIsHeldUp: true)
        #expect(AskComposerSlotContent.of(showsFace: heldUp, accessoryIsEnabled: false) == nil)
        #expect(AskComposerSlotContent.of(showsFace: heldUp, accessoryIsEnabled: true) == .accessory)
    }

    /// A slot starts uncovered, so the face is in the Ask tab's first frame
    /// at launch, and the first time the tab is chosen, before any screen has
    /// appeared to say so.
    @Test func theSlotStartsUncovered() {
        let cover = AskComposerSlotCover()
        #expect(!cover.isCovered)
        #expect(AskComposerSlotPolicy.showsFace(rests: true, isCovered: cover.isCovered, composerIsHeldUp: false))
    }

    /// A screen that goes with the slot's cover in hand was pushed over, and
    /// stays covered until it comes back: through a trip to another tab and
    /// back, where the pushed item is still on top and the screen never
    /// appears, and through the window turning compact under the item.
    @Test func aPushCoversTheScreenUntilItComesBack() {
        var cover = AskComposerSlotCover()
        cover.screenDisappeared()
        #expect(cover.isCovered)
        // Away to another tab and back, or from regular width to compact:
        // nothing reaches the screen under the pushed item.
        #expect(!AskComposerSlotPolicy.showsFace(rests: true, isCovered: cover.isCovered, composerIsHeldUp: false))
        cover.screenAppeared()
        #expect(!cover.isCovered)
        #expect(AskComposerSlotPolicy.showsFace(rests: true, isCovered: cover.isCovered, composerIsHeldUp: false))
    }

    /// A host that shows its own accessory on other tabs shares the one slot:
    /// the face has it wherever the face shows, the host's accessory wherever
    /// it shows and the face doesn't, and otherwise it's empty.
    @Test func theFaceHasTheSlotOverTheHostsOwnAccessory() {
        #expect(AskComposerSlotContent.of(showsFace: true, accessoryIsEnabled: false) == .face)
        #expect(AskComposerSlotContent.of(showsFace: true, accessoryIsEnabled: true) == .face)
        #expect(AskComposerSlotContent.of(showsFace: false, accessoryIsEnabled: true) == .accessory)
        #expect(AskComposerSlotContent.of(showsFace: false, accessoryIsEnabled: false) == nil)
    }

    /// The composer's own rules for a field without focus: a turn in flight
    /// stops whatever the draft, a draft sends, and a field with nothing to
    /// send — whitespace included — raises the composer instead.
    @Test func theFacesCircleFollowsTheComposersRules() {
        #expect(AskComposerFaceAction.of(isThinking: true, draft: "") == .stop)
        #expect(AskComposerFaceAction.of(isThinking: true, draft: "What's the oldest?") == .stop)
        #expect(AskComposerFaceAction.of(isThinking: false, draft: "What's the oldest?") == .send)
        #expect(AskComposerFaceAction.of(isThinking: false, draft: "") == .focus)
        #expect(AskComposerFaceAction.of(isThinking: false, draft: " \n ") == .focus)
    }
}

#endif
