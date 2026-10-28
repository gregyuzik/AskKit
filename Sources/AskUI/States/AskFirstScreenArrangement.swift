#if os(iOS) || os(macOS) || os(visionOS)

import CoreGraphics

/// When the first screen puts what Ask is beside what to ask
/// (`AskFirstScreen.isSideBySide`), when making room takes its mark and
/// headline too (`AskFirstScreen.keepsMarkAndHeadline`), how much space
/// `AskScreen` keeps under it (`keepsWholeSpace`), and which first screens
/// have two halves to part around iPhone Duo's fold (`hasTwoHalves`), decided
/// apart from the views so the cases can be pinned
/// (`AskFirstScreenArrangementTests`).
nonisolated enum AskFirstScreenArrangement {
    /// The window height below which a regular-width window is too short for
    /// the column stacked, at the default text size. `AskFirstScreen` scales
    /// it with the text.
    ///
    /// Measured on the demo in a windowed iPad Pro 13-inch (M5). At 704 × 486,
    /// the shortest window iPadOS allows, the stacked column and the room
    /// under it wanted about 510 pt below a 74 pt bar and had 412: the third
    /// starter ended 11 pt inside the composer's glass, and the disclosure sat
    /// behind it. At 704 × 608 it fit. So the demo's column wants about 580 pt
    /// of window. The stacked column is never wider than 460 pt, so at regular
    /// width its height is the copy's and the text size's, not the window
    /// width's, and one height serves every width. A host's copy can run
    /// longer than the demo's, and no host's column was measured here, in any
    /// language, so the line sits well above the demo's. Side by side a little
    /// early costs nothing at this width; stacked a little late puts a starter
    /// under the composer.
    static let shortWindowHeight: CGFloat = 700

    static func isSideBySide(
        isCompactHeight: Bool,
        isRegularWidth: Bool,
        windowHeight: CGFloat,
        shortBelow: CGFloat,
        isAccessibilitySize: Bool
    ) -> Bool {
        guard !isAccessibilitySize else { return false }
        if isCompactHeight { return true }
        // Unmeasured is zero, and until the height is read the column stays
        // stacked.
        guard isRegularWidth, windowHeight > 0 else { return false }
        return windowHeight < shortBelow
    }

    /// Which first screens have two halves to part around iPhone Duo's fold:
    /// what only informs, and what to ask.
    ///
    /// **The ready screen always has.** What Ask is, and what to ask: with
    /// every starter asked or passed over, its second half is still the
    /// disclosure of where a question goes.
    ///
    /// **The one that can't serve has while it keeps starters**: for a host
    /// that answers them without a model
    /// (`AskFirstScreenPolicy.answersWithoutModel`), and while it has one to
    /// offer. The reason is the first half, and the starters and the
    /// disclosure the second. Without starters it is a mark, a reason and a
    /// disclosure, one thing to read, as the nothing-to-ask screen is: a
    /// mark, a sentence and at most a button.
    ///
    /// `hasStarters` is the starters the screen is handed, less any the
    /// reader passed over, so passing over the last one where Ask can't serve
    /// takes the halves away where they stand, on no animation key: beside
    /// the fold the leading pane goes back to the chats.
    ///
    /// Read beside a fold from top to bottom (`takesBothPanes`) and across
    /// one (`foldSplit(_:hasTwoHalves:)`), so the two can't disagree about
    /// which screens part.
    static func hasTwoHalves(phase: AskStage.Phase, answersWithoutModel: Bool, hasStarters: Bool) -> Bool {
        switch phase {
        case .ready:
            true
        case .cannotServe:
            answersWithoutModel && hasStarters
        case .nothingToAskAbout, .thread:
            false
        }
    }

    /// What a first screen makes of a fold across it (`AskFoldSplit`): the
    /// split, for a screen whose two halves part at the fold, flat or bent,
    /// and for a screen with none only where the device is bent. Nil
    /// otherwise, which leaves the screen the one column it is with no fold.
    ///
    /// **Bent is the split's own word** (`AskFoldSplit.isBent`), the region
    /// being active, and never its gap: a flat fold can be reported at its
    /// bent height, and a flat display has nothing to keep clear of.
    ///
    /// `AskFirstScreen` reads it for the column, and `AskScreen` for the room
    /// it keeps over and under the column, which is none around a split. So a
    /// screen that stays one column lying flat keeps its room there too.
    static func foldSplit(_ split: AskFoldSplit?, hasTwoHalves: Bool) -> AskFoldSplit? {
        guard let split, hasTwoHalves || split.isBent else { return nil }
        return split
    }

    /// Whether the first screen takes both panes beside iPhone Duo's fold,
    /// what only informs in the leading one and what to ask in the
    /// conversation's: where the screen has two panes, the first screen has
    /// two halves (`hasTwoHalves`), and the reader has no chat to list in the
    /// first. The ready screen, and the one that can't serve while it keeps
    /// its starters.
    ///
    /// **An empty list would be half the display saying so.** Held like a
    /// book, the leading pane lists the reader's chats, and before the first
    /// one it would be an empty state beside a first screen squeezed into the
    /// other half. The first screen has two halves of its own, and the
    /// fold is where they part: glanceable on the leading side, and what to
    /// tap on the trailing side, nearest the composer.
    ///
    /// **Until a question is asked, not until a chat is listed.** A chat is
    /// listed once a turn of it has ended, a whole answer later. The first
    /// screen goes when the question is asked, on the Stage's own change, and
    /// its leading half goes with it: the pane is the chats' from then on,
    /// empty for the length of one answer. The conversation is in its pane
    /// throughout, so nothing the reader is reading moves.
    ///
    /// **Not before the saved chats are read**, when none listed means none
    /// read yet: the pane would say what Ask is and then change its mind.
    /// **Not at the accessibility sizes**, where a half outgrows its pane and
    /// the column scrolls as one.
    static func takesBothPanes(
        hasTwoPanes: Bool,
        hasTwoHalves: Bool,
        hasChats: Bool,
        chatsAreRead: Bool,
        isAccessibilitySize: Bool
    ) -> Bool {
        hasTwoPanes && hasTwoHalves && chatsAreRead && !hasChats && !isAccessibilitySize
    }

    /// How many starters the column offers where it is trimmed over a host's
    /// slot (`trimsOverSlot`).
    static let slotStarterBank = 2

    /// Whether the side-by-side column is trimmed, its sentence gone and its
    /// bank cut to `slotStarterBank`: in compact height, where the composer
    /// rests in a host's slot over a tab bar along the bottom.
    ///
    /// **Measured on an iPhone 18 Pro on its side, 874 × 402, in the demo's
    /// tab over its slot.** The bar's edge was at 78 pt, the composer's face
    /// at 284–328 and the tab bar at 338–402, which leaves the column 206 pt.
    /// Whole, it wants 241: the halves are 206, what Ask is, and 217, what to
    /// ask, with 12 pt above and 12 below. The scroll view kept the column's
    /// bottom, so the starters and the disclosure cleared the face, and "Try
    /// asking" and the mark's top went under the bar. Each half alone is too
    /// tall, so fitting means letting copy go from both: without the
    /// sentence the first is 148 pt, and with two starters the second is 164,
    /// which fits with 18 pt to spare for a host's longer copy.
    ///
    /// **The caveat stays, and the sentence goes.** The sentence says what
    /// Ask is, which the headline has said. The caveat is the one line that
    /// says what Ask reads and that it can be wrong.
    ///
    /// With the composer in the screen's own bar the whole column fits there:
    /// nothing stands under the composer, which leaves 252 pt. Stacked, the
    /// column is not this one, and a slot costs it nothing it wasn't already
    /// scrolling for.
    static func trimsOverSlot(isSideBySide: Bool, isCompactHeight: Bool, isOverSlot: Bool) -> Bool {
        isSideBySide && isCompactHeight && isOverSlot
    }

    /// The window height below which the stacked column, making room for the
    /// keyboard, lets its mark and headline go as well as its sentence and
    /// caveat.
    ///
    /// **Measured on iPhone Duo's outer display, 466 × 678, where closed up
    /// isn't enough.** On the demo upright with the keyboard up, the bar's
    /// edge was at 82 pt, the composer's top at 320 and the keyboard's at 374,
    /// which left 238 pt for a column that wants 314 closed up: the mark's
    /// 56 pt and the headline's line, 104 pt with their gaps, over 210 pt for
    /// "Try asking", the starters and the disclosure. The scroll view kept the
    /// column's center, so the mark went under the bar and the third starter
    /// under the composer, with the disclosure behind it. Without the mark and
    /// the headline, the 210 pt and the 36 pt of space above and below it come
    /// to 246, and the 8 over is that space's, not the column's.
    ///
    /// **Just under the shortest window recorded fitting them.** An iPhone 17
    /// Pro, 874 pt tall, fit them closed up through extra-large text
    /// (`AskScreen.firstScreenIsMakingRoom`). Between 678 and 874 nothing was
    /// measured, so a shorter phone lets them go: the cost there is a mark and
    /// a headline the reader has read already, against a starter under the
    /// composer where they don't fit. Not scaled with the text: making room
    /// stops above extra-large, and extra-large fit them at 874.
    static let shortMakingRoomHeight: CGFloat = 860

    /// Whether the mark and the headline stay: always unless the screen is
    /// making room in a stacked column and a measured window shorter than
    /// `shortMakingRoomHeight`. Side by side they are the whole of one half,
    /// and taking them would leave it empty beside the starters.
    static func keepsMarkAndHeadline(isMakingRoom: Bool, isSideBySide: Bool, windowHeight: CGFloat) -> Bool {
        guard isMakingRoom, !isSideBySide, windowHeight > 0 else { return true }
        return windowHeight >= shortMakingRoomHeight
    }

    /// Whether the space under the column is the whole of it, the composer
    /// bar's height and 24 pt more, rather than 12 pt (`AskScreen.firstScreen`
    /// says what it's for).
    ///
    /// **Not while the column makes room**, nor in compact height, where no
    /// part of the column clears the composer with the keyboard up, however
    /// much space sits under it. At rest the space only tips a column that
    /// fits into scrolling: on an iPhone 18 Pro on its side it scrolled the
    /// side-by-side column's top under the bar as the phone turned, "Try
    /// asking" clipped by the bar's edge.
    ///
    /// **Not at rest in a window shorter than `shortMakingRoomHeight`, where
    /// the column would make room.** There the column makes room whenever the
    /// keyboard is up, so the whole space never does its job, and at rest it
    /// tipped a column that fits into scrolling. On iPhone Duo's outer display
    /// upright, 466 × 678, the demo's column and the whole space came to
    /// 541 pt, where the bar and the composer left 508: the column opened at
    /// its top, and after the keyboard's show and hide the scroll view kept
    /// its center, 17 pt higher than it opened. With 12 pt it comes to 475,
    /// and fits. The inner display is as short on its side, 669 pt.
    static func keepsWholeSpace(
        isMakingRoom: Bool,
        isCompactHeight: Bool,
        wouldMakeRoom: Bool,
        windowHeight: CGFloat
    ) -> Bool {
        guard !isMakingRoom, !isCompactHeight else { return false }
        guard wouldMakeRoom, windowHeight > 0 else { return true }
        return windowHeight >= shortMakingRoomHeight
    }
}

/// Which of the first screen's two halves a view draws
/// (`AskFirstScreenArrangement.takesBothPanes`).
nonisolated enum AskFirstScreenPart: Equatable, Sendable {
    /// Both halves, stacked or side by side: everywhere but beside iPhone
    /// Duo's fold with no chats to list.
    case whole
    /// What only informs, in the pane on the fold's leading side: what Ask
    /// is, the mark, the headline, the sentence and the caveat, or why it
    /// can't serve, the unlit mark and the reason.
    case about
    /// What to ask: the starters and the disclosure, in the conversation's
    /// pane, over the composer.
    case ask
}

#endif
