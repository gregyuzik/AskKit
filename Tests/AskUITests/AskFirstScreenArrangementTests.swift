#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import Testing

@testable import AskUI

/// When the first screen puts what Ask is beside what to ask, when it lets
/// its mark and headline go to make room for the keyboard, and how much space
/// sits under it.
///
/// The screens these pin were driven, not imagined: an iPhone on its side, a
/// windowed iPad at 704 × 486, the shortest window iPadOS allows, where the
/// stacked column put its third starter under the composer's glass, and iPhone
/// Duo's outer display with the keyboard up, where the column closed up did the
/// same.
///
/// Not the last of them: which first screens have two halves to part around
/// iPhone Duo's fold, and what the two without do across one, pin what was
/// decided for the screens that can't serve and that have nothing to ask
/// about, which no device has shown yet.
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenArrangementTests {

    private let shortBelow = AskFirstScreenArrangement.shortWindowHeight

    private func sideBySide(
        compactHeight: Bool = false,
        regularWidth: Bool = true,
        height: CGFloat,
        accessibilitySize: Bool = false
    ) -> Bool {
        AskFirstScreenArrangement.isSideBySide(
            isCompactHeight: compactHeight,
            isRegularWidth: regularWidth,
            windowHeight: height,
            shortBelow: shortBelow,
            isAccessibilitySize: accessibilitySize
        )
    }

    /// An iPhone 18 Pro on its side, 874 × 402.
    @Test func aPhoneOnItsSideIsSideBySide() {
        #expect(sideBySide(compactHeight: true, regularWidth: false, height: 402))
        // A Pro Max on its side is regular width and compact height.
        #expect(sideBySide(compactHeight: true, regularWidth: true, height: 440))
    }

    /// The iPad window the stacked column overflowed: 704 × 486, regular in
    /// both directions.
    @Test func aShortWindowAtRegularWidthIsSideBySide() {
        #expect(sideBySide(height: 486))
    }

    /// A whole iPad either way up, and an iPad mini on its side.
    @Test func aTallScreenStaysStacked() {
        #expect(!sideBySide(height: 1376))
        #expect(!sideBySide(height: 1032))
        #expect(!sideBySide(height: 744))
    }

    /// Half the width of a narrow window holds too few words a line, so a
    /// short one scrolls instead.
    @Test func aNarrowShortWindowStaysStacked() {
        #expect(!sideBySide(regularWidth: false, height: 486))
    }

    /// Where half the width holds a few words a line, whatever the height.
    @Test func theAccessibilitySizesStayStacked() {
        #expect(!sideBySide(compactHeight: true, regularWidth: false, height: 402, accessibilitySize: true))
        #expect(!sideBySide(height: 486, accessibilitySize: true))
    }

    /// Before the window's height has been measured: stacked.
    @Test func anUnmeasuredScreenStaysStacked() {
        #expect(!sideBySide(height: 0))
    }

    private func keepsMarkAndHeadline(makingRoom: Bool = true, sideBySide: Bool = false, height: CGFloat) -> Bool {
        AskFirstScreenArrangement.keepsMarkAndHeadline(
            isMakingRoom: makingRoom,
            isSideBySide: sideBySide,
            windowHeight: height
        )
    }

    /// iPhone Duo's outer display upright, 466 × 678, where the column closed
    /// up wanted 314 pt and the keyboard left it 238.
    @Test func theDuosOuterDisplayLetsTheMarkAndHeadlineGo() {
        #expect(!keepsMarkAndHeadline(height: 678))
    }

    /// An iPhone 17 Pro, 874 pt tall, where the column was recorded fitting
    /// closed up, and a Pro Max.
    @Test func aPhoneTheColumnFitsKeepsThem() {
        #expect(keepsMarkAndHeadline(height: 874))
        #expect(keepsMarkAndHeadline(height: 956))
    }

    /// With the keyboard down nothing makes room, however short the window.
    @Test func aScreenNotMakingRoomKeepsThem() {
        #expect(keepsMarkAndHeadline(makingRoom: false, height: 678))
    }

    /// Side by side they are the whole of one half, and taking them would leave
    /// that half empty beside the starters.
    @Test func sideBySideKeepsThem() {
        #expect(keepsMarkAndHeadline(sideBySide: true, height: 486))
    }

    /// Before the window's height has been measured, the column is the one
    /// that was recorded fitting.
    @Test func anUnmeasuredWindowKeepsThem() {
        #expect(keepsMarkAndHeadline(height: 0))
    }

    private func keepsWholeSpace(
        makingRoom: Bool = false,
        compactHeight: Bool = false,
        wouldMakeRoom: Bool = true,
        height: CGFloat
    ) -> Bool {
        AskFirstScreenArrangement.keepsWholeSpace(
            isMakingRoom: makingRoom,
            isCompactHeight: compactHeight,
            wouldMakeRoom: wouldMakeRoom,
            windowHeight: height
        )
    }

    /// iPhone Duo's outer display upright, 466 × 678, where the column and the
    /// whole space overflowed at rest, and its inner display on its side,
    /// 669 pt.
    @Test func theDuosShortWindowsKeepLittleSpaceAtRest() {
        #expect(!keepsWholeSpace(height: 678))
        #expect(!keepsWholeSpace(height: 669))
    }

    /// A phone the column fits with the whole space under it keeps the whole
    /// space at rest.
    @Test func aTallPhoneKeepsTheWholeSpaceAtRest() {
        #expect(keepsWholeSpace(height: 874))
        #expect(keepsWholeSpace(height: 956))
    }

    /// While making room, and in compact height, the space is 12 pt whatever
    /// the window.
    @Test func makingRoomAndCompactHeightKeepLittleSpace() {
        #expect(!keepsWholeSpace(makingRoom: true, height: 874))
        #expect(!keepsWholeSpace(compactHeight: true, height: 402))
    }

    /// A column that wouldn't make room, at a text size above extra-large or
    /// on the other two first screens, keeps the whole space for when the
    /// keyboard comes, however short the window.
    @Test func aColumnThatWontMakeRoomKeepsTheWholeSpace() {
        #expect(keepsWholeSpace(wouldMakeRoom: false, height: 678))
    }

    /// Before the window's height has been measured, the whole space.
    @Test func anUnmeasuredWindowKeepsTheWholeSpace() {
        #expect(keepsWholeSpace(height: 0))
    }

    // MARK: Trimmed over a host's slot

    /// A phone on its side over a host's slot: the tab bar and the composer's
    /// face leave the side-by-side column 206 pt of the 241 it wants, so it
    /// lets its sentence go and offers two starters.
    @Test func aPhoneOnItsSideOverTheSlotIsTrimmed() {
        #expect(AskFirstScreenArrangement.trimsOverSlot(isSideBySide: true, isCompactHeight: true, isOverSlot: true))
        #expect(AskFirstScreenArrangement.slotStarterBank == 2)
    }

    /// With the composer in the screen's own bar the whole column fits there.
    @Test func aPhoneOnItsSideWithItsOwnComposerKeepsEverything() {
        #expect(!AskFirstScreenArrangement.trimsOverSlot(isSideBySide: true, isCompactHeight: true, isOverSlot: false))
    }

    /// Stacked, or side by side in a short window of regular height, a slot
    /// trims nothing: only the phone on its side was measured short.
    @Test func aSlotTrimsNothingOutsideCompactHeight() {
        #expect(!AskFirstScreenArrangement.trimsOverSlot(isSideBySide: false, isCompactHeight: false, isOverSlot: true))
        #expect(!AskFirstScreenArrangement.trimsOverSlot(isSideBySide: true, isCompactHeight: false, isOverSlot: true))
        #expect(!AskFirstScreenArrangement.trimsOverSlot(isSideBySide: false, isCompactHeight: true, isOverSlot: true))
    }

    // MARK: Two halves to part

    private func hasTwoHalves(
        _ phase: AskStage.Phase, answersWithoutModel: Bool = false, hasStarters: Bool = true
    ) -> Bool {
        AskFirstScreenArrangement.hasTwoHalves(
            phase: phase, answersWithoutModel: answersWithoutModel, hasStarters: hasStarters
        )
    }

    /// What Ask is, and what to ask: the ready screen's second half still has
    /// the disclosure when every starter has been asked or passed over.
    @Test func theReadyScreenHasTwoHalvesWithOrWithoutStarters() {
        #expect(hasTwoHalves(.ready))
        #expect(hasTwoHalves(.ready, hasStarters: false))
        #expect(hasTwoHalves(.ready, answersWithoutModel: true, hasStarters: false))
    }

    /// The reason, and starters that work without a model: only a host that
    /// answers them itself keeps them, and only while there are some to keep.
    /// Whatever the reason.
    @Test func aScreenThatCantServeHasTwoHalvesOnlyWithStartersThatWork() {
        for why in AskUnavailability.allCases {
            #expect(hasTwoHalves(.cannotServe(why), answersWithoutModel: true))
            #expect(!hasTwoHalves(.cannotServe(why), answersWithoutModel: true, hasStarters: false))
            #expect(!hasTwoHalves(.cannotServe(why)))
            #expect(!hasTwoHalves(.cannotServe(why), hasStarters: false))
        }
    }

    /// A mark, a sentence and at most a button is one thing to read, and a
    /// thread has no first screen at all.
    @Test func theNothingToAskScreenAndAThreadHaveNoHalves() {
        for answersWithoutModel in [false, true] {
            for hasStarters in [false, true] {
                #expect(!hasTwoHalves(
                    .nothingToAskAbout, answersWithoutModel: answersWithoutModel, hasStarters: hasStarters
                ))
                #expect(!hasTwoHalves(.thread, answersWithoutModel: answersWithoutModel, hasStarters: hasStarters))
            }
        }
    }

    // MARK: Both panes beside the fold

    private func takesBothPanes(
        hasTwoPanes: Bool = true, hasTwoHalves: Bool = true, hasChats: Bool = false,
        chatsAreRead: Bool = true, isAccessibilitySize: Bool = false
    ) -> Bool {
        AskFirstScreenArrangement.takesBothPanes(
            hasTwoPanes: hasTwoPanes, hasTwoHalves: hasTwoHalves, hasChats: hasChats,
            chatsAreRead: chatsAreRead, isAccessibilitySize: isAccessibilitySize
        )
    }

    /// Beside iPhone Duo's fold with no chat to list, the ready first screen
    /// is the two panes: what Ask is, and what to ask.
    @Test func withNoChatsTheReadyScreenTakesBothPanes() {
        #expect(takesBothPanes())
        #expect(takesBothPanes(hasTwoHalves: hasTwoHalves(.ready, hasStarters: false)))
    }

    /// So is the one that can't serve and keeps its starters: the reason on
    /// the leading side, the starters and the disclosure over the composer.
    @Test func aScreenThatCantServeWithStartersTakesBothPanes() {
        let halves = hasTwoHalves(.cannotServe(.appleIntelligenceOff), answersWithoutModel: true)
        #expect(takesBothPanes(hasTwoHalves: halves))
    }

    /// Without starters it is a mark, a reason and a disclosure, one thing to
    /// read, and it keeps to the conversation's pane beside the empty list.
    @Test func aScreenThatCantServeWithoutStartersKeepsToOnePane() {
        let wall = hasTwoHalves(.cannotServe(.appleIntelligenceOff))
        let passedOver = hasTwoHalves(
            .cannotServe(.appleIntelligenceOff), answersWithoutModel: true, hasStarters: false
        )
        #expect(!takesBothPanes(hasTwoHalves: wall))
        #expect(!takesBothPanes(hasTwoHalves: passedOver))
    }

    /// One pane, or none beside a fold, has one place for the screen.
    @Test func withoutTwoPanesTheScreenKeepsToOne() {
        #expect(!takesBothPanes(hasTwoPanes: false))
    }

    /// A chat to list is what the leading pane is for: the one on screen, or
    /// any earlier one, after New Chat.
    @Test func aChatToListKeepsThePaneForTheChats() {
        #expect(!takesBothPanes(hasChats: true))
    }

    /// Asked a question, the first screen is gone, and its half of the fold
    /// goes with it rather than waiting a whole answer for the chat to be
    /// listed. The nothing-to-ask screen, a mark and a line, has no two
    /// halves to part either.
    @Test func onlyAScreenWithTwoHalvesTakesBothPanes() {
        #expect(!takesBothPanes(hasTwoHalves: false))
        #expect(!takesBothPanes(hasTwoHalves: hasTwoHalves(.thread)))
        #expect(!takesBothPanes(hasTwoHalves: hasTwoHalves(.nothingToAskAbout)))
    }

    /// Before the saved chats are read, none listed means none read yet.
    @Test func notBeforeTheSavedChatsAreRead() {
        #expect(!takesBothPanes(chatsAreRead: false))
    }

    /// At the accessibility sizes a half outgrows its pane, and the column
    /// scrolls as one.
    @Test func notAtTheAccessibilitySizes() {
        #expect(!takesBothPanes(isAccessibilitySize: true))
    }

    // MARK: Around a fold across

    private let flat = AskFoldSplit(above: 369, gap: 0, below: 393, isBent: false)
    private let bent = AskFoldSplit(above: 349, gap: 40, below: 373, isBent: true)

    /// Two halves part at a fold across the screen lying flat as well as
    /// bent: the hinge is where they part, with or without a bend.
    @Test func twoHalvesPartAtAFoldFlatOrBent() {
        #expect(AskFirstScreenArrangement.foldSplit(flat, hasTwoHalves: true) == flat)
        #expect(AskFirstScreenArrangement.foldSplit(bent, hasTwoHalves: true) == bent)
    }

    /// A screen with no halves has nothing to part, so lying flat it stays
    /// one column centered in the whole screen: a flat display has nothing to
    /// keep clear of. Bent, it keeps clear of the bend.
    @Test func aScreenWithNoHalvesIsArrangedAroundABendAlone() {
        #expect(AskFirstScreenArrangement.foldSplit(flat, hasTwoHalves: false) == nil)
        #expect(AskFirstScreenArrangement.foldSplit(bent, hasTwoHalves: false) == bent)
    }

    /// Bent is the split's own word, not its gap: an active region reported
    /// with no height is still a bend, and a flat one that keeps its height
    /// still isn't.
    @Test func aBendIsTheSplitsWordNotItsGap() {
        let bentWithNoGap = AskFoldSplit(above: 369, gap: 0, below: 393, isBent: true)
        let flatWithAGap = AskFoldSplit(above: 349, gap: 40, below: 373, isBent: false)
        #expect(AskFirstScreenArrangement.foldSplit(bentWithNoGap, hasTwoHalves: false) == bentWithNoGap)
        #expect(AskFirstScreenArrangement.foldSplit(flatWithAGap, hasTwoHalves: false) == nil)
    }

    /// No fold across, no split, whatever the screen.
    @Test func withNoFoldAcrossNothingIsArrangedAroundOne() {
        #expect(AskFirstScreenArrangement.foldSplit(nil, hasTwoHalves: true) == nil)
        #expect(AskFirstScreenArrangement.foldSplit(nil, hasTwoHalves: false) == nil)
    }
}

#endif
