#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// What the thread reads off its scroll view, in one value because
/// `onScrollGeometryChange` tracks one.
///
/// **The arithmetic lives here so it can be tested**, because getting it wrong
/// is silent: every flag `AskScrollFollow` publishes is derived from these
/// numbers, and no assertion could see them computed inside a view closure.
///
/// Five numbers, all of them read, because two consecutive samples are what
/// say whether the reader moved: `readerScrolledUp(from:)` decides that,
/// except for the steps `AskScrollFollow.geometryChanged(_:at:)` sets aside.
nonisolated struct AskThreadGeometry: Equatable {
    /// The scroll view's content height, and the space between the bars.
    ///
    /// **`containerSize` isn't the scroll view's own height**: it is the space
    /// between the bars, 670 pt on an iPhone 17 Pro where the scroll view
    /// itself is 874.
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    /// The top content inset: the navigation bar on iOS, the toolbar on the
    /// Mac.
    var insetTop: CGFloat
    /// `contentOffset.y`, which **rests at `-insetTop`, not at zero.**
    var offset: CGFloat
    /// The space between the bars, across: what a rotation, a window resize
    /// or iPhone Duo opening and closing all change and a keyboard never
    /// does. Zero in a sample built without one, which is every test that
    /// never resizes the thread.
    var containerWidth: CGFloat = 0

    /// How far the content's foot sits below the bottom edge.
    /// `AskScrollFollow` subtracts the spacer it keeps under the last turn
    /// (`restingTrailingSpace`) to get the distance the reader can see.
    ///
    /// **`insetTop` is the term that is easy to miss.** Without it, a thread
    /// sitting exactly at its foot reports the height of its navigation bar,
    /// 116 pt, which is past `AskScrollFollow.followWithin`: the follow never
    /// engages and the "Jump to latest" pill never goes away. Measured on the
    /// demo: `content=713 container=670 offset=-116 insetTop=116`.
    ///
    /// **The Mac has the same shape**, so the term belongs on both platforms.
    /// One sample of the demo's macOS window read `container=344 visible=514
    /// insetTop=116 insetBottom=54 offset=-116`: `containerSize` is the space
    /// between the bars there too, and the rest position is `-insetTop`.
    /// `AskScreen`'s note on the Mac's top edge has the toolbar's inset at
    /// 52 pt once the window's opening animation ends. Whichever value the
    /// toolbar has, a distance without the term is off by all of it.
    var distanceFromContentFoot: CGFloat {
        contentHeight - containerHeight - insetTop - offset
    }

    /// Whether the reader moved the thread away from where it was, as opposed
    /// to the thread growing away from the reader.
    ///
    /// **The two are indistinguishable by distance.** A reveal chunk that lays
    /// out several hundred points in one pass puts the content's foot that
    /// much further below the bottom edge, and the geometry callback runs
    /// before the height change that would have followed it. Read off the
    /// distance alone, the follow's `isAtFoot` is already false by the time
    /// the follow asks, and a long answer streams off the bottom of the screen
    /// with the pill as the only way to reach it. Traced on the demo with
    /// `isAtFoot` read off the distance: `content=938 atFoot=true` →
    /// `content=1065 lastTurn=503 atFoot=false`, and the thread never moved
    /// again.
    ///
    /// The signal that tells them apart is already here. Growth changes
    /// `contentHeight`. A keyboard changes `containerHeight`, and a rotation
    /// or a window resize changes `containerWidth` with it. A bar resolving
    /// its height changes `insetTop`. What decreases `offset` with all four
    /// unchanged is a drag, a wheel, a trackpad, or the momentum of one, **and
    /// the thread's own scroll.** Traced on an iPhone 17 Pro simulator, a
    /// follow that reached the foot at 3673.6 was back at 3453.3 20 ms later
    /// with the content unchanged and no finger on the glass. Two samples
    /// can't tell that from a drag. On iOS, where it was traced,
    /// `AskScrollFollow.fellShort(since:)` answers it, and
    /// `AskScrollFollow.geometryChanged(_:at:)` sets aside the step that the
    /// scroll bringing a new question into view, or the pill's, takes while it
    /// glides; on the other platforms nothing does. The steps a resize takes
    /// are set aside on every platform. Scrolling back down increases the
    /// offset, and needs no special case: arriving within `followWithin` of
    /// the last turn's end is what says the reader is back.
    func readerScrolledUp(from previous: AskThreadGeometry) -> Bool {
        guard contentHeight == previous.contentHeight,
              containerHeight == previous.containerHeight,
              containerWidth == previous.containerWidth,
              insetTop == previous.insetTop
        else { return false }
        return offset < previous.offset
    }
}

#endif
