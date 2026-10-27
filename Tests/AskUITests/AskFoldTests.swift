#if os(iOS) || os(macOS) || os(visionOS)

import CoreGraphics
import Testing

@_spi(AskKitInternal) @testable import AskUI

/// How the screen sits around iPhone Duo's fold: two panes beside a fold that
/// runs top to bottom, flat or bent; the conversation clear of a bent one where
/// two panes don't fit; and the first screen's halves around one across it.
///
/// The inner display is about 951 × 669 pt on its side. The screen here is
/// 880 wide, the bar strip having taken the rest, with the hinge at 475.
@Suite(.timeLimit(.minutes(1))) struct AskFoldTests {

    private func vertical(at x: CGFloat, width: CGFloat = 0, active: Bool = false) -> AskFold {
        AskFold(frame: CGRect(x: x - width / 2, y: 0, width: width, height: 669), isActive: active)
    }

    private func across(at y: CGFloat, height: CGFloat = 0, active: Bool = false) -> AskFold {
        AskFold(frame: CGRect(x: 0, y: y - height / 2, width: 669, height: height), isActive: active)
    }

    private func arrangement(_ fold: AskFold?, width: CGFloat = 880, chats: Bool = true) -> AskFoldArrangement {
        AskFoldArrangement.resolve(fold: fold, width: width, listsChats: chats)
    }

    /// The outer display, an iPhone, an iPad, a Mac: one pane.
    @Test func noFoldIsOnePane() {
        #expect(arrangement(nil) == .whole)
    }

    /// A flat fold zero wide, as Apple's guide has it and the stand-in makes
    /// it: inactive, and the panes still meet at the hinge, with nothing
    /// between them.
    @Test func aFlatInnerDisplayOnItsSideSplitsAtTheHinge() {
        #expect(arrangement(vertical(at: 475)) == .panes(chats: 475, gap: 0))
    }

    /// What the iPhone Duo simulator reports lying flat on its side: the
    /// region inactive at its bent width, 40 pt, from 455.5 in a screen 867
    /// wide. Inactive is flat, whatever the width, so the panes meet on the
    /// line through its middle as they do around a fold zero wide, and only
    /// the bend opens them: 20 pt back on each side. A domain that keeps no
    /// chats has the whole width flat and keeps clear of the bend.
    @Test func aFlatFoldThatKeepsItsWidthIsTheLineThroughItsMiddle() {
        let flat = vertical(at: 475.5, width: 40)
        let bent = vertical(at: 475.5, width: 40, active: true)
        #expect(arrangement(flat, width: 867) == .panes(chats: 475.5, gap: 0))
        #expect(arrangement(flat, width: 867) == arrangement(vertical(at: 475.5), width: 867))
        #expect(arrangement(bent, width: 867) == .panes(chats: 455.5, gap: 40))
        #expect(arrangement(flat, width: 867, chats: false) == .whole)
        #expect(arrangement(bent, width: 867, chats: false) == .trailing(inset: 495.5))
    }

    /// The line a flat fold is: through the middle of whatever region is
    /// reported, the long way. A bent one is its own frame.
    @Test func aFlatFoldIsArrangedAroundAsALine() {
        #expect(vertical(at: 475.5, width: 40).arranged == CGRect(x: 475.5, y: 0, width: 0, height: 669))
        #expect(across(at: 475, height: 40).arranged == CGRect(x: 0, y: 475, width: 669, height: 0))
        #expect(vertical(at: 475).arranged == vertical(at: 475).frame)
        let bent = vertical(at: 475.5, width: 40, active: true)
        #expect(bent.arranged == bent.frame)
    }

    /// A flat region at the screen's edge is still a fold at the edge: its
    /// middle leaves no room for a pane on that side, and nothing splits.
    @Test func aFlatFoldThatKeepsItsWidthAtTheEdgeSplitsNothing() {
        #expect(arrangement(vertical(at: 860, width: 40), width: 880) == .whole)
        #expect(arrangement(vertical(at: 20, width: 40), width: 880) == .whole)
    }

    /// Bent like a book, the fold and its margins are the gap between the
    /// panes.
    @Test func aBentInnerDisplaySplitsAroundTheBend() {
        #expect(arrangement(vertical(at: 475, width: 24, active: true)) == .panes(chats: 463, gap: 24))
    }

    /// A domain that keeps no chats has nothing for the leading side: flat,
    /// the conversation keeps the whole width, and bent, it keeps clear on the
    /// trailing side.
    @Test func withNoChatsTheConversationKeepsClearOfABend() {
        #expect(arrangement(vertical(at: 475), chats: false) == .whole)
        #expect(arrangement(vertical(at: 475, width: 24, active: true), chats: false) == .trailing(inset: 487))
    }

    /// Beside a host's 320 pt sidebar the screen is 560 wide and the hinge
    /// 155 pt in, too narrow for the chats.
    @Test func besideAHostsSidebarTheConversationTakesTheTrailingSide() {
        #expect(arrangement(vertical(at: 155), width: 560) == .whole)
        #expect(arrangement(vertical(at: 155, width: 24, active: true), width: 560) == .trailing(inset: 167))
    }

    /// Where the trailing side is too narrow for the conversation, it keeps
    /// to the leading side of a bend.
    @Test func aNarrowTrailingSideKeepsTheConversationLeading() {
        let fold = vertical(at: 432, width: 24, active: true)
        #expect(arrangement(fold, width: 560) == .leading(width: 420))
    }

    /// The inner display in Split View: the hinge runs between the two apps,
    /// at an edge of this screen or outside it.
    @Test func aFoldAtTheEdgeSplitsNothing() {
        #expect(arrangement(vertical(at: 0, active: true), width: 475) == .whole)
        #expect(arrangement(vertical(at: 475, active: true), width: 475) == .whole)
        #expect(arrangement(vertical(at: 500, width: 24, active: true), width: 475) == .whole)
    }

    /// Upright, the inner display folds across, and the screen stays one pane.
    @Test func aFoldAcrossIsOnePane() {
        #expect(arrangement(across(at: 475, height: 24, active: true), width: 669) == .whole)
    }

    /// The conversation lays out at compact width wherever it is narrower
    /// than the screen, and the toolbar's chats button goes only where the
    /// chats are on screen.
    @Test func whatEachArrangementNarrowsAndLists() {
        #expect(!AskFoldArrangement.whole.narrowsConversation)
        #expect(!AskFoldArrangement.whole.listsChats)
        #expect(AskFoldArrangement.panes(chats: 475, gap: 0).narrowsConversation)
        #expect(AskFoldArrangement.panes(chats: 475, gap: 0).listsChats)
        #expect(AskFoldArrangement.trailing(inset: 487).narrowsConversation)
        #expect(!AskFoldArrangement.trailing(inset: 487).listsChats)
        #expect(AskFoldArrangement.leading(width: 420).narrowsConversation)
        #expect(!AskFoldArrangement.leading(width: 420).listsChats)
    }

    // MARK: - Before the fold is reported

    /// At launch on the inner display on its side the system reports no fold
    /// for a frame (`AskFoldArrangement.awaitingFold(width:)`). The Duo's
    /// screen is 867 wide there: two even panes, the chats listed from the
    /// first. Bent, the fold then moves their edge 22 pt and opens the line
    /// to its own 40; flat, it moves the line 42 pt to the hinge's and opens
    /// nothing.
    @Test func awaitingTheFoldTheScreenStandsInTwoEvenPanes() {
        let awaiting = AskFoldArrangement.awaitingFold(width: 867)
        #expect(awaiting == .panes(chats: 433.5, gap: 0))
        #expect(awaiting.listsChats)
        #expect(arrangement(vertical(at: 475.5, width: 40, active: true), width: 867) == .panes(chats: 455.5, gap: 40))
        #expect(arrangement(vertical(at: 475.5, width: 40), width: 867) == .panes(chats: 475.5, gap: 0))
    }

    /// Two even panes only where both fit, as around a fold: the
    /// conversation's 320 pt, each side.
    @Test func awaitingTheFoldAScreenTooNarrowForTwoPanesStaysWhole() {
        #expect(AskFoldArrangement.awaitingFold(width: 640) == .panes(chats: 320, gap: 0))
        #expect(AskFoldArrangement.awaitingFold(width: 639) == .whole)
        #expect(AskFoldArrangement.awaitingFold(width: 0) == .whole)
    }

    /// The reading the screen keeps while it expects a fold and none is
    /// reported: a domain that keeps its chats has them beside the
    /// conversation, and one that doesn't keeps the whole width, since nothing
    /// says yet whether the fold is bent.
    @Test func aReadingThatExpectsAFoldListsTheChatsBeforeItIsReported() {
        let reading = AskFoldReading(fold: nil, width: 867, expectsFold: true)
        #expect(reading.arrangement(listsChats: true) == .panes(chats: 433.5, gap: 0))
        #expect(reading.arrangement(listsChats: false) == .whole)
    }

    /// Once reported, the fold decides, expected or not. And a screen that
    /// expects none is arranged as it was: the outer display, the inner one
    /// upright, every other device.
    @Test func aReportedFoldDecidesExpectedOrNot() {
        let bent = vertical(at: 475.5, width: 40, active: true)
        #expect(AskFoldReading(fold: bent, width: 867, expectsFold: true) == AskFoldReading(fold: bent, width: 867))
        let upright = across(at: 393.5, height: 40)
        #expect(AskFoldReading(fold: upright, width: 669, expectsFold: true).arrangement(listsChats: true) == .whole)
        #expect(AskFoldReading(fold: nil, width: 867).arrangement(listsChats: true) == .whole)
        #expect(AskFoldReading(fold: nil, width: 867, expectsFold: false) == AskFoldReading(fold: nil, width: 867))
    }

    // MARK: - The first screen across a fold

    /// A keyboard shortens the screen and the fold's frame with it, which
    /// decides nothing new, so the reading the screen keeps is the same one
    /// and its state isn't written.
    @Test func aKeyboardShorteningTheFoldLeavesTheReadingAlone() {
        let flat = AskFold(frame: CGRect(x: 475, y: 0, width: 0, height: 669), isActive: false)
        let shortened = AskFold(frame: CGRect(x: 475, y: 0, width: 0, height: 365), isActive: false)
        #expect(AskFoldReading(fold: flat, width: 880) == AskFoldReading(fold: shortened, width: 880))
        #expect(AskFoldReading(fold: flat, width: 880).arrangement(listsChats: true) == .panes(chats: 475, gap: 0))
        #expect(AskFoldReading(fold: flat, width: 880).arrangement(listsChats: false) == .whole)
        #expect(AskFoldReading.none.arrangement(listsChats: true) == .whole)
    }

    /// The inner display upright, 669 × 951, with what the bars leave running
    /// from 106 to 868.
    /// A stand-in fold, for a device with none, runs through the middle of the
    /// view that reads it: flat it is zero wide and inactive, bent it is the
    /// bend wide and active, as the device's own is.
    @Test func aSimulatedFoldRunsThroughTheMiddleOfTheView() {
        let view = CGSize(width: 880, height: 669)
        #expect(AskSimulatedFold.book().fold(in: view) == vertical(at: 440))
        #expect(AskSimulatedFold.book(bend: 24).fold(in: view) == vertical(at: 440, width: 24, active: true))
        #expect(
            AskSimulatedFold.upright().fold(in: CGSize(width: 669, height: 880))
                == across(at: 440)
        )
        #expect(
            AskSimulatedFold.upright(bend: 24).fold(in: CGSize(width: 669, height: 880))
                == across(at: 440, height: 24, active: true)
        )
    }

    /// And the screen arranges itself around one as around the device's own:
    /// two panes held like a book, one pane upright.
    @Test func aSimulatedFoldArrangesTheScreenAsTheDevicesOwnDoes() {
        let view = CGSize(width: 880, height: 669)
        #expect(arrangement(AskSimulatedFold.book().fold(in: view)) == .panes(chats: 440, gap: 0))
        #expect(arrangement(AskSimulatedFold.book(bend: 24).fold(in: view)) == .panes(chats: 428, gap: 24))
        #expect(arrangement(AskSimulatedFold.upright().fold(in: view)) == .whole)
    }

    /// The split in a view 762 pt tall, the fold read in the view's own
    /// space, as `AskScreen` reads it from the scroll view the first screen
    /// sits in: under a 106 pt bar, the display's hinge at 475 is at 369.
    private func split(_ fold: AskFold?, height: CGFloat = 762) -> AskFoldSplit? {
        AskFoldSplit.around(fold, height: height)
    }

    /// A flat fold with no height, as Apple's guide has it and the stand-in
    /// makes it: the halves meet at the hinge with no gap.
    @Test func aFlatFoldAcrossSplitsTheFirstScreenAtTheHinge() {
        #expect(split(across(at: 369)) == AskFoldSplit(above: 369, gap: 0, below: 393, isBent: false))
    }

    /// A flat fold that keeps its height, as the iPhone Duo simulator's does
    /// with the inner display upright: 40 pt, inactive. Flat, the halves meet
    /// on the line through its middle, and the tabletop's bend parts them.
    @Test func aFlatFoldAcrossThatKeepsItsHeightIsTheLineThroughItsMiddle() {
        let flat = across(at: 369, height: 40)
        #expect(split(flat) == AskFoldSplit(above: 369, gap: 0, below: 393, isBent: false))
        #expect(split(flat) == split(across(at: 369)))
        #expect(
            split(across(at: 369, height: 40, active: true))
                == AskFoldSplit(above: 349, gap: 40, below: 373, isBent: true)
        )
    }

    /// Bent into a tabletop, the bend is the gap between the halves.
    @Test func aBentFoldAcrossSplitsTheFirstScreenAroundTheBend() {
        #expect(
            split(across(at: 369, height: 24, active: true))
                == AskFoldSplit(above: 357, gap: 24, below: 381, isBent: true)
        )
    }

    /// Bent is the region being active, never its height: a flat fold that
    /// keeps its 40 pt isn't bent, and an active one reported with none is.
    /// The screens with no two halves read it, to keep clear of a bend and of
    /// nothing else (`AskFirstScreenArrangement.foldSplit(_:hasTwoHalves:)`).
    @Test func aSplitIsBentWhereTheRegionIsActiveWhateverItsHeight() {
        #expect(split(across(at: 369, height: 40, active: true))?.isBent == true)
        #expect(split(across(at: 369, active: true))?.isBent == true)
        #expect(split(across(at: 369, height: 40))?.isBent == false)
        #expect(split(across(at: 369))?.isBent == false)
    }

    /// What the bars leave, top to bottom: both halves and the bend between.
    @Test func aSplitsWholeIsItsHalvesAndTheBend() {
        #expect(AskFoldSplit(above: 349, gap: 40, below: 373, isBent: true).whole == 762)
        #expect(AskFoldSplit(above: 369, gap: 0, below: 393, isBent: false).whole == 762)
    }

    /// With the keyboard up, what it leaves below the fold is too short for a
    /// half, and the column goes back to making room.
    @Test func aFoldTheKeyboardCoversSplitsNothing() {
        #expect(split(across(at: 369, height: 24, active: true), height: 494) == nil)
    }

    /// **The view's own height, with none of its insets taken off.** iPhone
    /// Duo's inner display upright in a tabletop, the screen in a tab over a
    /// host's slot, as the simulator laid it out: the scroll
    /// view 730 pt tall from y 82 of a window 951 tall, its safe area insets
    /// 82 and 139, and the bend from 373.5 to 413.5 in the view's own space,
    /// 455.5 to 495.5 on the display. The bars leave the whole of that view,
    /// so the halves are 373.5 and 316.5 and the column fills it.
    ///
    /// With the insets taken off as well, the halves came to 291.5 and 177.5:
    /// a column 509 pt tall that the scroll view centered in its 730, 28 pt
    /// below the bend, with what stands above ending 16 pt short of it.
    @Test func theSplitIsOfTheViewItIsReadInWithNoInsetsTakenOff() {
        let bend = AskFold(frame: CGRect(x: 0, y: 373.5, width: 669, height: 40), isActive: true)
        let split = AskFoldSplit.around(bend, height: 730)
        #expect(split == AskFoldSplit(above: 373.5, gap: 40, below: 316.5, isBent: true))
        #expect(split?.whole == 730)

        // Lying flat, the same region inactive: the line through its middle.
        let flat = AskFold(frame: bend.frame, isActive: false)
        #expect(
            AskFoldSplit.around(flat, height: 730)
                == AskFoldSplit(above: 393.5, gap: 0, below: 336.5, isBent: false)
        )
    }

    /// **The split is back before the keyboard's hide says so.** The view
    /// follows the keyboard, the heights here being the ones logged through
    /// a show and a hide on the same display: the keyboard's coming takes the
    /// lower half, and its going gives the view back while the composer is
    /// still held over where it was, 54 pt short of rest. That is tall enough
    /// for a half, so the screen has the split in hand when the hide's
    /// message lowers its flag, and the halves part in the flag's own
    /// transaction, on the keyboard's first key
    /// (`AskFirstScreen.onKeyboard`).
    ///
    /// With the insets taken off twice the lower half read 70 pt there, no
    /// split, and the split came back after the flag, on no key: the halves
    /// parted in one frame.
    @Test func theSplitIsBackWhileTheComposerIsStillUp() {
        let bend = AskFold(frame: CGRect(x: 0, y: 373.5, width: 669, height: 40), isActive: true)
        #expect(AskFoldSplit.around(bend, height: 730)?.below == 316.5)
        for keyboardUp in [519.0, 465, 374, 320] {
            #expect(AskFoldSplit.around(bend, height: keyboardUp) == nil)
        }
        #expect(
            AskFoldSplit.around(bend, height: 676)
                == AskFoldSplit(above: 373.5, gap: 40, below: 262.5, isBent: true)
        )
    }

    /// A fold top to bottom, or none, leaves the first screen centered.
    @Test func onlyAFoldAcrossSplitsTheFirstScreen() {
        #expect(split(vertical(at: 300, width: 24, active: true)) == nil)
        #expect(split(nil) == nil)
    }

    // MARK: The leading pane

    private func leadingPane(
        firstScreenTakesBothPanes: Bool = false, chatsAreRead: Bool = true,
        hasChats: Bool = false, firstScreenIsKnown: Bool = true
    ) -> AskLeadingPane {
        AskLeadingPane.resolve(
            firstScreenTakesBothPanes: firstScreenTakesBothPanes, chatsAreRead: chatsAreRead,
            hasChats: hasChats, firstScreenIsKnown: firstScreenIsKnown
        )
    }

    /// Before the reader has a chat, the pane is the first screen's.
    @Test func theLeadingPaneSaysWhatAskIsBeforeThereAreChats() {
        #expect(leadingPane(firstScreenTakesBothPanes: true) == .about)
    }

    /// A reader with chats sees them as soon as they are read, whatever is
    /// known of the first screen.
    @Test func theLeadingPaneListsTheChatsOnceRead() {
        #expect(leadingPane(hasChats: true) == .chats)
        #expect(leadingPane(hasChats: true, firstScreenIsKnown: false) == .chats)
    }

    /// Until the saved chats are read, none listed means none read.
    @Test func theLeadingPaneIsBlankUntilTheChatsAreRead() {
        #expect(leadingPane(chatsAreRead: false) == .blank)
        #expect(leadingPane(chatsAreRead: false, hasChats: true) == .blank)
    }

    /// With none to list and the first screen not yet known, the pane can't
    /// say whether it is the first screen's or an empty list.
    @Test func theLeadingPaneIsBlankUntilTheFirstScreenIsKnown() {
        #expect(leadingPane(firstScreenIsKnown: false) == .blank)
    }

    /// With none to list and a first screen that doesn't take both panes, a
    /// thread on screen or an accessibility size, the pane is the chats',
    /// empty.
    @Test func theLeadingPaneIsAnEmptyListOtherwise() {
        #expect(leadingPane() == .chats)
    }
}

#endif
