#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// iPhone Duo's fold where it runs through the Ask screen: its frame in the
/// screen's own space, and whether the device is bent along it.
///
/// **Flat or bent, the fold is there.** Partially folded, the region is
/// active and as wide as the bend and its touch margins. Lying flat, it's
/// inactive, and the default query leaves it out, so the screen asks with
/// `.includeInactive` and splits at the hinge either way: on its line flat,
/// and either side of the bend bent.
///
/// **Flat is the region being inactive, never its width.** Apple's guide has
/// a flat fold zero wide. The iPhone Duo simulator (iOS 27.1) reports the same
/// 40 pt at 180° as at 130°, inactive, on its side and upright alike. Taken
/// at that width, the screen stood flat as it stands bent: the panes 40 pt
/// apart down a display with no bend to keep clear of, and upright the first
/// screen's halves 40 pt apart across one. That is the simulator's region and
/// not the display's, so the screen is arranged around `arranged`: the frame
/// while the region is active, and the line through its middle while it
/// isn't. The bend then opens the line by half its width each way, which is
/// what a fold zero wide lying flat does on any device.
///
/// **The system animates the region, and the screen goes with it.** Recorded
/// on the simulator's inner display on its side, the first screen across both
/// panes: the composer's leading edge stood at x 497.5 lying flat and 516.5
/// at 130°, and went from one to the other through a dozen frames or two
/// each time the hinge moved, none of them a jump. Nothing here animates it.
///
/// A plain value rather than the `ReservedRegion` it is read from, which has
/// no public initializer: a simulated fold (`AskSimulatedFold`) and the
/// package's tests make one. Read on iOS alone (`read(from:)`); everywhere
/// else there is never a fold.
nonisolated struct AskFold: Equatable, Sendable {
    /// The fold's frame, margins included, in the space of the view that read
    /// it, and mirrored in a right-to-left layout, so its x counts from the
    /// leading edge.
    var frame: CGRect
    /// Whether the device is partially folded along it.
    var isActive: Bool

    /// Whether it runs top to bottom: the inner display on its side, held like
    /// a book. The inner display upright folds across, into a laptop or a
    /// tabletop. Flat, the frame runs the same way, at its bent width or at
    /// none, which says which.
    var isVertical: Bool { frame.height >= frame.width }

    /// What the screen is arranged around: the fold's frame while the device
    /// is bent along it, and the line through the frame's middle while it
    /// lies flat, whatever width the region is reported at (the type has why).
    var arranged: CGRect {
        guard !isActive else { return frame }
        return isVertical
            ? CGRect(x: frame.midX, y: frame.minY, width: 0, height: frame.height)
            : CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: 0)
    }
}

#if os(iOS)
nonisolated extension AskFold {
    /// The fold in `proxy`'s space, active or not, or nil: on every device
    /// without one, and on iPhone Duo's outer display.
    ///
    /// Nonisolated, because `onGeometryChange` reads geometry off the main
    /// actor, and the package's default would make this a main-actor call
    /// that the proxy can't be sent to.
    ///
    /// `simulated` stands in for the device's own where a host asked for one
    /// (`askSimulatedFold(_:)`), through the middle of the view read.
    static func read(from proxy: GeometryProxy, simulated: AskSimulatedFold? = nil) -> AskFold? {
        if let simulated { return simulated.fold(in: proxy.size) }
        guard let region = proxy.reservedRegions(kind: .division, options: .includeInactive).first else { return nil }
        return AskFold(frame: region.frame, isActive: region.isActive)
    }
}
#endif

/// A fold to arrange the screen around on a device that has none: iPhone Duo's
/// inner display held like a book or upright, flat or bent, on any iPhone or
/// iPad, for a preview, the demo or a UI test.
///
/// **A stand-in for the arrangement, not for the device.** It puts a fold
/// through the middle of the view that reads it, so the panes and the first
/// screen's halves lay out as they do around a real one. Nothing else of the
/// Duo comes with it: not the bar strip, not the displays' sizes, not the
/// scene moving from one display to the other. What it shows is the
/// arrangement, and a check on the device is still owed.
@_spi(AskKitInternal) nonisolated public struct AskSimulatedFold: Equatable, Sendable {
    /// Whether it runs top to bottom, as held like a book, or across, as the
    /// inner display upright.
    var isVertical: Bool
    /// How wide the bend and its margins are: zero lying flat.
    var bend: CGFloat

    /// Held like a book, the fold top to bottom: lying flat, or bent `bend`
    /// points wide.
    public static func book(bend: CGFloat = 0) -> AskSimulatedFold {
        AskSimulatedFold(isVertical: true, bend: max(0, bend))
    }

    /// Upright, the fold across, as a laptop or a tabletop: lying flat, or
    /// bent `bend` points wide.
    public static func upright(bend: CGFloat = 0) -> AskSimulatedFold {
        AskSimulatedFold(isVertical: false, bend: max(0, bend))
    }

    /// The fold through the middle of a view `size` big, in its own space.
    func fold(in size: CGSize) -> AskFold {
        let frame = isVertical
            ? CGRect(x: (size.width - bend) / 2, y: 0, width: bend, height: size.height)
            : CGRect(x: 0, y: (size.height - bend) / 2, width: size.width, height: bend)
        return AskFold(frame: frame, isActive: bend > 0)
    }
}

/// What a reading of the fold decides: the arrangement for a domain that keeps
/// its chats and for one that doesn't, since the geometry is read off the main
/// actor, where the store can't be asked which.
///
/// **The arrangements, not the fold.** The fold's frame runs the screen's
/// height, which the keyboard changes, and a reading that kept the frame
/// would write the screen's state, and build its body, on every keyboard
/// for nothing. Two arrangements change only when the screen would.
nonisolated struct AskFoldReading: Equatable, Sendable {
    private var withChats: AskFoldArrangement
    private var withoutChats: AskFoldArrangement

    /// No fold read yet: the whole screen.
    static let none = AskFoldReading(fold: nil, width: 0)

    /// `expectsFold` says a fold is on its way though the system reports none
    /// yet (`AskFoldArrangement.awaitingFold(width:)`): the reader's chats
    /// take their side at once, and the fold only moves the line between.
    init(fold: AskFold?, width: CGFloat, expectsFold: Bool = false) {
        withChats = fold == nil && expectsFold
            ? AskFoldArrangement.awaitingFold(width: width)
            : AskFoldArrangement.resolve(fold: fold, width: width, listsChats: true)
        withoutChats = AskFoldArrangement.resolve(fold: fold, width: width, listsChats: false)
    }

    /// The arrangement for a domain that keeps its chats or doesn't.
    func arrangement(listsChats: Bool) -> AskFoldArrangement {
        listsChats ? withChats : withoutChats
    }
}

/// How the Ask screen sits around a vertical fold: decided apart from the view
/// so the cases can be pinned (`AskFoldTests`).
///
/// **Two panes, the way the system's split views meet the fold.** Partially
/// folded, `NavigationSplitView` puts a column on each side of it. The screen
/// can't be one, since it sits inside a host's navigation stack, so it does
/// the same by hand: the reader's chats on the leading side, the conversation
/// on the trailing side, each as wide as its side. The conversation takes the
/// trailing side because prompts belong nearest where the outer display takes
/// over as the device closes, and because a side of the inner display is
/// about the outer display's size, so the conversation keeps the layout it
/// has there.
///
/// **The hinge's own place, flat as well as bent.** Apple's guidance takes
/// inactive regions for structure, split points included, so lying flat the
/// panes still split at the hinge: on its line (`AskFold.arranged`), with
/// nothing between them. Bending it puts the bend between them and moves
/// nothing across it.
///
/// An upright inner display folds across instead. The thread scrolls through
/// that fold, which Apple's guidance allows, and the composer is already in
/// the bottom half, where controls belong there, so only the first screens
/// arrange themselves around it (`AskFoldSplit`).
nonisolated enum AskFoldArrangement: Equatable, Sendable {
    /// One pane, the screen's whole width: no fold, one across, or a flat one
    /// with no room for two panes.
    case whole
    /// The reader's chats `chats` wide on the leading side, the fold `gap`
    /// wide, and the conversation in the rest.
    case panes(chats: CGFloat, gap: CGFloat)
    /// The conversation alone on the trailing side of a bent fold, starting
    /// `inset` from the leading edge: there are no chats to list, or the
    /// leading side is too narrow for them, such as beside a host's sidebar.
    case trailing(inset: CGFloat)
    /// The conversation alone on the leading side of a bent fold, `width`
    /// wide, where the trailing side is too narrow for it.
    case leading(width: CGFloat)

    /// The narrowest the chats are listed in: a summary's two lines and its
    /// date.
    static let chatsMinimumWidth: CGFloat = 240
    /// The narrowest the conversation is put beside a fold: a phone's reading
    /// column. iPhone Duo's sides are about 470 pt each.
    static let conversationMinimumWidth: CGFloat = 320

    /// The arrangement for `fold` in a screen `width` wide, where
    /// `listsChats` says the domain keeps its chats.
    ///
    /// **Two panes only where both fit.** A fold at the screen's edge or
    /// outside it splits nothing: the inner display in Split View, where the
    /// hinge runs between two apps.
    ///
    /// **Bent with no room for two, the conversation keeps clear of it** on
    /// the trailing side if it fits there, and on the leading side if not.
    /// Flat, it keeps the whole width: a flat display has no bend to keep
    /// clear of.
    static func resolve(fold: AskFold?, width: CGFloat, listsChats: Bool) -> AskFoldArrangement {
        guard let fold, fold.isVertical else { return .whole }
        let around = fold.arranged
        let leading = around.minX
        let trailing = width - around.maxX
        guard leading > 0, trailing > 0 else { return .whole }
        if listsChats, leading >= chatsMinimumWidth, trailing >= conversationMinimumWidth {
            return .panes(chats: leading, gap: around.width)
        }
        guard fold.isActive else { return .whole }
        if trailing >= conversationMinimumWidth { return .trailing(inset: around.maxX) }
        if leading >= conversationMinimumWidth { return .leading(width: leading) }
        return .whole
    }

    /// The arrangement for a domain that keeps its chats where a fold is on
    /// its way and the system reports none yet: two even panes, where both
    /// fit.
    ///
    /// **The system reports the fold a frame after the scene is active.**
    /// Traced on the iPhone Duo simulator (iOS 27.1), at launch on the inner
    /// display on its side: the screen is laid out at its full size with no
    /// division region, and the region arrives about 70 ms later. Arranged
    /// around no fold until then, the screen came up whole, the composer
    /// across the display and History in the bar, and rearranged: 0.42 s on
    /// screen, then the composer crossing the fold and History's glass
    /// closing over nothing.
    ///
    /// **Even, as the system's own split is before it hears.** There,
    /// `ArrangementView`'s split style stands its two views either side of
    /// the view's middle on the first layout and moves them to the fold when
    /// the region arrives, and Settings opens with a sidebar that then widens
    /// to the fold. So this is the system's arrangement, a frame early. The
    /// fold then moves the line from the view's middle to the display's, half
    /// the bar strip's width, and bent, opens it to the bend: on the Duo at
    /// 130° the chats' edge goes from 433.5 to 455.5 of 867 and the
    /// conversation's from 433.5 to 495.5, and flat both go to 475.5. Nothing
    /// changes sides, and History is never in the bar.
    ///
    /// The caller says where a fold is on its way: the bars in iPhone Duo's
    /// strip at regular width, which is its inner display on its side
    /// (`AskScreen.expectsFold`). With no fold ever reported there, the two
    /// even panes stay, which is where the system's split would stand too.
    ///
    /// A domain that keeps no chats still waits for the fold: flat it keeps
    /// the whole width and bent it keeps to the trailing side, and nothing
    /// says which before the fold does.
    static func awaitingFold(width: CGFloat) -> AskFoldArrangement {
        let half = width / 2
        guard half >= chatsMinimumWidth, half >= conversationMinimumWidth else { return .whole }
        return .panes(chats: half, gap: 0)
    }

    /// Whether the conversation is narrower than the screen: then it lays out
    /// at compact width, as on a phone, whatever the window says.
    var narrowsConversation: Bool { self != .whole }

    /// Whether the reader's chats are on screen beside the conversation, which
    /// takes the toolbar's button for them away.
    var listsChats: Bool {
        if case .panes = self { true } else { false }
    }
}

/// Where a first screen goes around a fold across it: what only informs
/// above, and what to tap below, each centered in its half of what the bars
/// leave. Glanceable above and tappable below is Apple's rule for the
/// tabletop, and the column, centered, would otherwise sit on the fold.
///
/// **A screen with two halves parts at the fold, flat or bent**
/// (`AskFirstScreenArrangement.hasTwoHalves`): what Ask is, or why it can't
/// serve, above, and what to ask below. The hinge is where they part with or
/// without a bend.
///
/// **A screen with none keeps clear of a bend, and of nothing else.** The
/// nothing-to-ask screen and the one that can't serve with no starters are a
/// mark and a line or two, one thing to read, and centered in what the bars
/// leave they sit on the bend. Bent, they stand in the upper half, with the
/// nothing-to-ask screen's button, the one thing to tap, in the lower. Lying
/// flat they stay the one column they are with no fold: a flat display has
/// nothing to keep clear of
/// (`AskFirstScreenArrangement.foldSplit(_:hasTwoHalves:)`).
///
/// The heights are the halves' least, so a half that needs more, at a large
/// text size, grows the column into scrolling rather than overlapping the
/// other.
nonisolated struct AskFoldSplit: Equatable, Sendable {
    /// From the top of what the bars leave to the fold.
    var above: CGFloat
    /// The bend itself: zero lying flat.
    var gap: CGFloat
    /// From the fold to the bottom of what the bars leave.
    var below: CGFloat
    /// Whether the device is bent along the fold: the region being active,
    /// never its height, which the simulator keeps lying flat
    /// (`AskFold.arranged` has why). An active region reported with no height
    /// is still a bend.
    var isBent: Bool

    /// What the bars leave, from top to bottom: both halves and the bend
    /// between them.
    var whole: CGFloat { above + gap + below }

    /// The least room above or below the fold that a half is put in.
    static let minimumHalf: CGFloat = 160

    /// The split around `fold` in a view `height` tall, the fold in the
    /// view's own space. Nil for no fold, a fold that runs top to bottom, or
    /// one that leaves a half less than `minimumHalf`, such as one the
    /// keyboard covers.
    ///
    /// **The view's whole height, with no insets taken off it.** The view is
    /// the scroll view the first screen sits in, and as measured it stops
    /// at the bars: on iPhone Duo upright, in a tab over a host's slot, it
    /// runs from y 82 to 812 of a window 951 tall while it reads safe area
    /// insets of 82 and 139, and with the keyboard up it ends at the
    /// composer over the keyboard. So what the bars and the composer leave
    /// is the view itself, and the insets it reads are the bars outside
    /// it, not room to take off inside it.
    ///
    /// Taken off as well, the halves would come to 291 and 177 of 373 and
    /// 316. The column is 509 pt in a view of 730, so the scroll view would
    /// center it, and its halves would part 28 pt below the fold, half the
    /// difference between the insets, each crowded toward it: in a tabletop
    /// the ready screen's caveat would end 16 pt above the bend. And the
    /// split would come back late from the keyboard, which
    /// `AskFirstScreen.onKeyboard` has.
    static func around(_ fold: AskFold?, height: CGFloat) -> AskFoldSplit? {
        guard let fold, !fold.isVertical else { return nil }
        let around = fold.arranged
        let above = around.minY
        let below = height - around.maxY
        guard above >= minimumHalf, below >= minimumHalf else { return nil }
        return AskFoldSplit(above: above, gap: around.height, below: below, isBent: fold.isActive)
    }
}

extension EnvironmentValues {
    /// Where the first screen goes around a fold across it, set in the
    /// environment by `AskScreen`, which reads the fold from the scroll view
    /// the first screen sits in. Nil everywhere else.
    @Entry var askFoldSplit: AskFoldSplit?

    /// The fold a host asked the screen to arrange itself around in place of
    /// the device's own (`askSimulatedFold(_:)`). Nil everywhere else.
    @Entry var askSimulatedFold: AskSimulatedFold?
}

extension View {
    /// Arranges the Ask screen under this view around `fold`, on a device
    /// with no fold of its own: iPhone Duo's two panes or the first screen's
    /// halves, in a preview, a demo or a UI test (`AskSimulatedFold`). Nil
    /// leaves the device's own fold, or none.
    @_spi(AskKitInternal) public func askSimulatedFold(_ fold: AskSimulatedFold?) -> some View {
        environment(\.askSimulatedFold, fold)
    }
}

#endif
