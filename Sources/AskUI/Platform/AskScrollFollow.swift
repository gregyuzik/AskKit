#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// **Never pull the reader down a streaming answer, and never leave them
/// staring at the space where it is being written.**
///
/// - A new question lands at the foot of the thread, where the reader just
///   typed it, and the thread follows its own foot as the answer arrives, so
///   the newest line stays above the composer. The question leaves over the
///   top of a long answer, which is the only way one can be read as it comes.
/// - The follow holds only while the reader is already there, within
///   `followWithin` of the last turn's end. Scroll up once and the thread
///   stops moving.
/// - The follow holds only for the thread's own growth. Something the reader
///   opens in place in an answer that has settled, such as a host's card or
///   the rows behind an evidence line, grows the turn where it stands, and
///   the thread stays where the reader left it (`followsGrowth(at:)`).
/// - When the newest text is out of view, a "Jump to latest" pill says so,
///   and the reader decides. While something streams, that is any distance
///   past the follow boundary; on a settled thread it takes a deliberate
///   scroll away (`showsJumpPill`).
/// - A resize is never the reader's doing (a phone turned on its side, a
///   window dragged, iPhone Duo opened or closed), and a reader at the foot
///   as one begins is at the foot when it ends (`geometryChanged(_:at:)`).
///
/// **Anchored at the foot.** Nothing under the last turn is sized from a
/// measurement, there is one anchor, and every scroll has the same target:
/// the end of what has been written. Why not pin the question to the top:
/// ARCHITECTURE.md, Rejected designs. The anchor depends on two things, each
/// tested: every distance counts the top content inset
/// (`AskThreadGeometry.distanceFromContentFoot`), and the thread's growth
/// alone never clears `isAtFoot`.
///
/// **Every distance here is measured from the end of the last turn, not from
/// the end of the content**, because `restingTrailingSpace` sits between the
/// two. A reader with the newest line in view is at the foot for every
/// purpose this type serves.
@Observable
@MainActor
final class AskScrollFollow {
    /// How close to the last turn's end counts as "already there".
    static let followWithin: CGFloat = 80

    /// How far past it counts as "gone looking", on a thread that has stopped
    /// moving.
    ///
    /// Five times `followWithin`, and deliberately not the same number. The
    /// follow boundary is small because it decides whether the thread may move
    /// under the reader, and 80 pt of slack is the width of "still at the
    /// bottom". This one decides whether to put a button on the screen, so a
    /// reader who nudged the thread a screen corner's worth must not get one:
    /// it takes about a phone screen of scrolling to earn it.
    static let farFromFoot: CGFloat = 400

    /// The spacer under the last turn, so the newest line is never pinned
    /// against the composer bar.
    ///
    /// A constant, and the only thing kept under the last turn. Everything
    /// this type publishes measures from the turn's end rather than the
    /// content's, and this is the whole of the difference between them.
    static let restingTrailingSpace: CGFloat = 12

    /// The gap the thread's stack puts between one turn and the next, and
    /// between the last answer and the chips it earned.
    ///
    /// Lives here because two stacks read it, the thread's in `AskScreen` and
    /// each row's own in `AskThreadRow`, and a number spelled twice drifts.
    static let turnSpacing: CGFloat = 20

    /// How long a growth of the last turn is still the thread's own once
    /// nothing is streaming, counted from the thread's last move of its own: a
    /// turn starting, a stream starting or stopping, a jump to its end
    /// (`followsGrowth(at:)`).
    ///
    /// **A second, for growth that lands in milliseconds.** A turn's last
    /// growth is laid out in the frame `isThinking` goes false, and the chips
    /// in it were traced landing 10 to 20 ms into the follow that frame started
    /// (`fellShort(since:)` has the traces). A thread read back from disk is
    /// measured in its first layouts. Neither was timed on a slow phone, so
    /// the window is twice the 500 ms the check after the follow waits
    /// (`followQuiet`) rather than anything tighter.
    ///
    /// **No longer, because inside it the reader's growth is followed too.**
    /// An answer's last piece starts arriving no later than 600 ms after the
    /// answer ends (`AskArrival`), so only a card opened within a few hundred
    /// milliseconds of arriving is still chased to the foot. And nothing that
    /// grows on its own later than this is followed at all: a piece that loads
    /// late has to hold its shape while it loads, as a framed
    /// `AskPictureArrival` does.
    static let ownGrowthWindow: TimeInterval = 1

    /// How long after `jumped(at:)` an animated step back up the thread is
    /// still the jump's own (`geometryChanged(_:at:)`). Twice the 0.25 s an
    /// animated scroll on the screen takes.
    static let jumpGlideWindow: TimeInterval = 0.5

    /// How long after the thread's width last changed its steps are still the
    /// resize's own, and a reader who was at the foot is kept there
    /// (`geometryChanged(_:at:)`). `jumpGlideWindow`'s half-second: a phone
    /// turned on its side was traced reaching its final layout inside a quarter of one, and a
    /// scroll that reports no hold goes unread for this long after the window
    /// stops moving. On the Mac, where no scroll phase is read at all, that
    /// includes the wheel.
    static let resizeWindow: TimeInterval = 0.5

    /// Whether the last turn's end is close enough that following it is what
    /// the reader expects.
    ///
    /// **Latched, not sampled.** Being within `followWithin` of the last
    /// turn's end sets it, and only a scroll up clears it. That is meant to be
    /// the reader's scroll; the thread's own follow has been traced clearing
    /// it too, which is one reason `fellShort(since:)` doesn't read it. A
    /// thread that grows away from a reader who hasn't moved is still a thread
    /// the reader is following. Read off the distance alone, the flag would
    /// leave a long answer streaming off the bottom of the screen:
    /// `AskThreadGeometry.readerScrolledUp(from:)` has the trace.
    private(set) var isAtFoot = true
    /// Whether the reader has scrolled a long way from it.
    private(set) var isFar = false

    /// Whether the last turn grew while the reader was somewhere else, and they
    /// haven't been back to the foot since.
    ///
    /// **Without it, the band between the two boundaries is a dead zone.** A
    /// reader who nudges the thread while an answer is arriving has the follow
    /// let go, rightly, since they scrolled up. Then the turn ends: the tiles,
    /// the evidence line and the follow-ups all land in one growth, below the
    /// bottom edge, and `showsJumpPill` flips from the streaming rule to the
    /// settled one in the same frame. At 300 pt from the foot that is neither
    /// a follow nor a pill, so the newest half of the answer sits under the
    /// composer with nothing to say it is there.
    ///
    /// Measured on the demo on an iPhone 17 Pro: a drag of about 190 pt during
    /// an answer leaves the reader at `distance=373`, and `farFromFoot` is 400. The
    /// number isn't bad luck: a turn's last growth is about 300 pt, so the
    /// band is exactly where the end of a turn puts a reader who touched the
    /// thread.
    ///
    /// Kept apart from `isFar` rather than combined with it, because the two
    /// answer different questions: this one is "something arrived that you
    /// haven't seen", and `isFar` is "you have gone looking". A reader browsing
    /// a settled thread has missed nothing, and still has to earn the pill at
    /// 400.
    private(set) var hasUnseenGrowth = false

    /// Whether the thread has anywhere to scroll to.
    ///
    /// **A scroll view whose content fits doesn't refuse a `scrollTo`.**
    /// Measured on an iPhone 17 Pro with a two-line first turn: asking for the
    /// foot on 294 pt of content in a 670 pt thread took `contentOffset.y` to
    /// -232, a whole navigation bar above its own rest position of -116, and
    /// it bounced back the next frame. So the thread lifted itself under the
    /// bar and dropped back for a question that was on screen the whole time.
    ///
    /// A thread that fits is showing everything there is to show, so no
    /// scroll on this screen runs unless this holds. The follow, the scroll
    /// that brings a new question into view and a resize's each check it, and
    /// the pill's scroll comes only from a pill that shows only while it
    /// holds.
    private(set) var isScrollable = false

    /// How many times a resize has asked for the thread's foot. `AskScreen`
    /// scrolls there, instantly, each time this changes while
    /// `keepsFootThroughResize` still holds (`geometryChanged(_:at:)`).
    private(set) var footRequests = 0

    /// The last turn's measured height: the follow's trigger, and nothing
    /// else.
    ///
    /// **Nothing is sized from it.** A measurement arrives one layout pass
    /// after the layout that produced it, so anything laid out from one is
    /// laid out from a height that no longer holds. Why not size space under
    /// the last turn from it: ARCHITECTURE.md, Rejected designs. This only
    /// asks whether the layout grew.
    ///
    /// `AskScreen` scrolls the foot back into view when this changes, which is
    /// the layout growing rather than a token arriving. A keyboard rising, the
    /// composer growing a line, a bar resolving its height: none of them move
    /// this number, so none of them can move the thread. Opening something in
    /// place in the last turn does move it, and `followsGrowth(at:)` is what
    /// keeps that from moving the thread.
    private(set) var lastTurnHeight: CGFloat = 0

    /// The previous geometry sample, which is what says whether the reader
    /// moved.
    ///
    /// **`@ObservationIgnored`.** Consecutive samples always differ, so an
    /// observed property would publish a mutation on every one, once a frame
    /// for the whole of every scroll, for a value nothing draws from. It is a
    /// comparison and nothing else.
    @ObservationIgnored private var lastGeometry: AskThreadGeometry?

    /// The scroll view's phase as `onScrollPhaseChange` last reported it, which
    /// is how the check after the follow tells a hand on the thread from the
    /// thread's own motion (`fellShort(since:)`).
    @ObservationIgnored private var scrollPhase: ScrollPhase = .idle

    /// How many times the reader has taken hold of the thread: a finger, a
    /// trackpad, or either one catching the momentum of the last. Compared
    /// only with itself, by `fellShort(since:)`.
    @ObservationIgnored private(set) var readerHolds = 0

    private var isStreaming = false

    /// The thread's last move of its own, which `ownGrowthWindow` is counted
    /// from. Ignored by observation for `lastGeometry`'s reason: nothing draws
    /// from it.
    @ObservationIgnored private var ownGrowthSince: TimeInterval?

    /// When `jumped(at:)` last ran, which `jumpGlideWindow` is counted from.
    /// Ignored by observation for `lastGeometry`'s reason.
    @ObservationIgnored private var jumpedAt: TimeInterval?

    /// When the thread's width last changed, which `resizeWindow` is counted
    /// from. Ignored by observation for `lastGeometry`'s reason.
    @ObservationIgnored private var resizedAt: TimeInterval?

    /// Whether the resize under way keeps the reader at the foot, which
    /// `resized(to:at:)` decides once as it begins.
    @ObservationIgnored private var resizeKeepsFoot = false

    /// The thread's top inset in the last sample, and the tallest it has been
    /// since the thread last took a new width (`barLooksMinimized`). Ignored by
    /// observation for `lastGeometry`'s reason: read when the screen scrolls,
    /// never drawn from.
    @ObservationIgnored private var insetTop: CGFloat = 0
    @ObservationIgnored private var tallestInsetTop: CGFloat = 0

    init() {}

    /// Whether to offer the pill.
    ///
    /// **Two distances, because a stream and a settled thread ask different
    /// questions.** While something is streaming, the answer is growing off
    /// the bottom of the screen, and anything past the follow boundary means
    /// the reader is missing it. On a settled thread nothing is moving, so the
    /// pill is a way back down a long read rather than a report, and offering
    /// it at 81 pt would put a floating button over the composer of anyone who
    /// scrolled one line. A thread grows long: without the pill, a reader six
    /// turns back has no way down but a drag.
    ///
    /// **A thread that settled while the reader was away is the third case.**
    /// `hasUnseenGrowth` carries it, and it takes the streaming rule, because
    /// there is something to report rather than only somewhere to go back to.
    /// Without it, the pill would go out in the frame `isThinking` goes false,
    /// the moment the tiles and the follow-ups land under the composer.
    var showsJumpPill: Bool {
        isScrollable && ((isStreaming || hasUnseenGrowth) ? !isAtFoot : isFar)
    }

    /// Whether the thread should keep its own foot in view as the last turn
    /// grows now (`followsGrowth(at:)`).
    var followsGrowth: Bool { followsGrowth(at: Date.timeIntervalSinceReferenceDate) }

    /// Whether the thread should keep its own foot in view as the last turn
    /// grows at `now`: whenever the reader is at the foot and the growth is
    /// the thread's own.
    ///
    /// **Streaming alone is too narrow a condition, and none at all is too
    /// wide.** Held to streaming, the follow would miss the last growth of
    /// every turn: the tiles, the evidence line and the follow-ups arrive in
    /// the frame the turn completes and `isThinking` goes false, and a reader
    /// at the foot should see them. With no condition, it would chase growth
    /// the reader made: a host's card that opens in place in the settled last
    /// turn would be taken for the answer arriving, and the follow would
    /// scroll the thread to its foot, keeping the chips over the composer and
    /// sending the card up under the navigation bar. The rows behind an
    /// evidence line open the same way.
    ///
    /// So a growth is the thread's while a stream runs and for
    /// `ownGrowthWindow` after the thread's last move of its own, and the
    /// reader's after that. The keyboard reaches neither: the trigger is
    /// `lastTurnHeight`, which only the turn's own layout changes.
    func followsGrowth(at now: TimeInterval) -> Bool {
        isAtFoot && isScrollable && ownsGrowth(at: now)
    }

    /// Whether the last turn growing at `now` is the thread's doing rather than
    /// the reader's (`followsGrowth(at:)`).
    func ownsGrowth(at now: TimeInterval) -> Bool {
        isStreaming || ownGrowthSince.map { now - $0 < Self.ownGrowthWindow } ?? false
    }

    /// Whether the thread's own jump, the scroll that brings a new question
    /// into view or the pill's, is still gliding at `now`: the scroll view
    /// animating, inside `jumpGlideWindow` of the jump
    /// (`geometryChanged(_:at:)`).
    private func isJumpGliding(at now: TimeInterval) -> Bool {
        scrollPhase == .animating && jumpedAt.map { now - $0 < Self.jumpGlideWindow } ?? false
    }

    /// Whether the thread is inside `resizeWindow` of its width changing, with
    /// no hand on it (`geometryChanged(_:at:)`).
    private func isResizing(at now: TimeInterval) -> Bool {
        !isReaderScrolling && resizedAt.map { now - $0 < Self.resizeWindow } ?? false
    }

    /// Whether the navigation bar looks minimized: the thread's top inset is
    /// shorter than the tallest it has been at this width.
    ///
    /// **A minimizing bar takes its height out of the inset**, as SDK 27's
    /// automatic safe-area adjustment does: beside a fold on an iPhone 18 Pro
    /// simulator on its side, the bar minimizing moved the pane of chats up
    /// 54 pt. Nothing in SDK 27 says whether the bar is minimized, and the
    /// screen asks before it scrolls the thread itself: an open bar is held
    /// open through that scroll, and a minimized one is left alone, since a
    /// scroll down under `.onScrollDown` can't open it and `.never` would
    /// (`AskNavigationBarMinimization`).
    ///
    /// **The tallest is the inset as it is through a resize**, and the tallest
    /// since outside one: a phone turned on its side reports the bars' new,
    /// shorter inset a few milliseconds after its new width. Where the safe
    /// area doesn't follow the bar, the inset never shrinks and the bar always
    /// looks open.
    var barLooksMinimized: Bool { insetTop < tallestInsetTop - 1 }

    /// Whether a resize under way is keeping the reader at the foot now
    /// (`keepsFootThroughResize(at:)`).
    var keepsFootThroughResize: Bool { keepsFootThroughResize(at: Date.timeIntervalSinceReferenceDate) }

    /// Whether a resize under way at `now` is keeping the reader at the foot:
    /// what every `footRequests` is issued on, and what `AskScreen` asks again
    /// before it answers one. Its task also runs each time the thread appears,
    /// with whatever count the last resize left, and that is no resize at all.
    func keepsFootThroughResize(at now: TimeInterval) -> Bool {
        resizeKeepsFoot && isResizing(at: now)
    }

    /// Notes a change in the thread's width: a rotation, a window resize, or
    /// iPhone Duo moving the screen between its displays. Called before the
    /// sample is compared with the last one, which it reads.
    ///
    /// **Whether to keep the foot is decided once, as the resize begins**, from
    /// the sample before it, and each width change after that only extends the
    /// window. A phone turned on its side reports a width of its own on the
    /// way (402 → 340 → 750 on an iPhone 18 Pro, 16 ms apart), with the rows
    /// still at their estimates for it, and a decision read off that frame
    /// would drop a reader who was at the foot or catch one who wasn't.
    ///
    /// **From the distance, not `isAtFoot`**, which is latched. A reader who
    /// opened something in place in a settled last turn has the flag and not
    /// the foot, and a resize must not carry them away from what they opened.
    private func resized(to geometry: AskThreadGeometry, at now: TimeInterval) {
        guard let lastGeometry, geometry.containerWidth != lastGeometry.containerWidth else { return }
        if !(resizedAt.map { now - $0 < Self.resizeWindow } ?? false) {
            resizeKeepsFoot = lastGeometry.distanceFromContentFoot - Self.restingTrailingSpace <= Self.followWithin
        }
        resizedAt = now
    }

    /// Called from `onScrollGeometryChange` with everything the scroll view
    /// reports, which is also the whole of what this type knows about scroll
    /// geometry. The arithmetic is `AskThreadGeometry`'s, so that it can be
    /// tested.
    ///
    /// Two samples decide the flags, not one. The distance says whether the
    /// reader is at the last turn's end; only a change between samples says
    /// whether they left it.
    func geometryChanged(_ geometry: AskThreadGeometry, at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        // From the end of the last turn, which is what every reading of these
        // two flags means. See the type's own note.
        let distance = geometry.distanceFromContentFoot - Self.restingTrailingSpace
        // **Not a step the thread's own jump took.** A question sent under a
        // tall turn is appended at the `LazyVStack`'s estimate of its row, the
        // animation that brings it into view sets off for the foot of that
        // estimate, and the row's measured height lands a frame later,
        // hundreds of points shorter. SwiftUI re-aims the animation at the new
        // foot but keeps the distance it still had to go, so the offset drops
        // by the whole correction in one sample with the content unchanged,
        // which `readerScrolledUp(from:)` reads as a drag. Traced on an iPhone
        // 17 Pro simulator, 15 sends of 15: 550 → 178, `isAtFoot` cleared, no
        // follow for the rest of the turn, and the answer written below the
        // bottom edge behind the pill. With the step set aside, five sends of
        // five followed their answers to the foot. The drop is still drawn for
        // a frame; this only stops it being taken for the reader.
        //
        // **Scoped to the jump, not to `.animating`.** That phase is how the
        // check after the follow tells it isn't a hand, but nothing has
        // measured which phase a VoiceOver or a status-bar scroll reports, and
        // a reader who scrolls up that way mid-answer must still stop the
        // follow. The follow's own step back keeps reading as a drag for the
        // same reason, and the check after the follow finishes it
        // (`aFollowThatCameBackUpIsFinishedThoughItReadsAsADrag`).
        //
        // **Nor a step the scroll view takes as the thread is resized.** An
        // iPhone 18 Pro simulator turned on its side reported the new width at
        // the old offset, then the offset 117 pt lower with nothing else
        // changed, then the bars' new inset. That middle sample is a drag to
        // `readerScrolledUp(from:)`, and a reader at the foot of a settled
        // thread came out of the turn 645 pt above it, behind the pill. A hand
        // on the thread is still the reader's, resize or not.
        resized(to: geometry, at: now)
        insetTopChanged(geometry.insetTop, at: now)
        let scrolledUp = !isJumpGliding(at: now)
            && !isResizing(at: now)
            && (lastGeometry.map(geometry.readerScrolledUp(from:)) ?? false)
        lastGeometry = geometry
        // **Within the boundary sets it; only a reader's scroll up clears
        // it.** The middle case, past the boundary with the reader still where
        // they were, is the thread having grown away from them, and it must
        // leave the flag alone so `followsGrowth` can catch up on the height
        // change that arrives right after. The geometry callback runs first,
        // so clearing here would be clearing before the follow has had a
        // chance to run.
        let atFoot = distance <= Self.followWithin ? true : (scrolledUp ? false : isAtFoot)
        // Whether there is anywhere to go. `containerHeight` is the space
        // between the bars, so content taller than it is content that
        // scrolls, and this is the whole test.
        let scrollable = geometry.contentHeight > geometry.containerHeight
        if scrollable != isScrollable { isScrollable = scrollable }
        // **Only on a change.** Swift 6.4's `@Observable` already compares an
        // `Equatable` value before it publishes: probed with
        // `withObservationTracking`, an equal `Bool` or `Double` written back
        // notifies nothing, and a changed one notifies. The guards say which
        // writes are expected to change anything.
        if atFoot != isAtFoot { isAtFoot = atFoot }
        // **Cleared here and not only in `jumped()`**, because tapping the
        // pill is one of two ways back and the other one never calls it: a
        // reader who drags down to the foot arrives through this branch. Left
        // to `jumped()` alone, the flag would survive the rest of the thread's
        // life, and the next one-line nudge would put the pill back at 81 pt,
        // which is what `farFromFoot` is there to prevent.
        if atFoot, hasUnseenGrowth { hasUnseenGrowth = false }
        // A second Bool rather than a computed one, because the distance
        // itself isn't kept: it differs on every sample, so storing it would
        // publish at display rate whatever the macro compares.
        //
        // `!atFoot` as well as the distance, because the pill is a report to
        // the reader, and the same growth that must not stop the follow must
        // not put a button on the screen either: a thread still following its
        // own foot is never far from it, however far the last chunk landed.
        let far = !atFoot && distance > Self.farFromFoot
        if far != isFar { isFar = far }
        // **A reader at the foot as a resize begins is at the foot when it
        // ends.** The scroll view keeps an offset, not a foot, and the rows are
        // measured at their new width over the next quarter-second: turned on
        // its side, the content went 1540 → 1765 → 1771 pt after the width had
        // changed. So every sample inside the window that leaves the last
        // turn's end below the bottom edge asks again, and the last one asked
        // lands.
        //
        // Not through `jumped(at:)`, which would make the rewrapped turn's
        // growth the thread's own and send the animated follow after the same
        // foot: two motions for one resize.
        if keepsFootThroughResize(at: now), atFoot, scrollable, distance > 0 {
            footRequests += 1
        }
    }

    /// Keeps the top inset, and the tallest it has been, from every geometry
    /// sample (`barLooksMinimized`). Called after `resized(to:at:)`, which
    /// stamps the resize this reads.
    private func insetTopChanged(_ inset: CGFloat, at now: TimeInterval) {
        let resizing = resizedAt.map { now - $0 < Self.resizeWindow } ?? false
        tallestInsetTop = resizing || lastGeometry == nil ? inset : max(tallestInsetTop, inset)
        insetTop = inset
    }

    /// How long the check after the follow waits before it looks: twice the
    /// follow's own quarter-second travel, so a follow that is only late has
    /// landed before anything judges it. The frame a turn completes is the
    /// heaviest one a thread draws.
    static let followQuiet: Duration = .milliseconds(500)

    /// Called from `onScrollPhaseChange`, which `AskScreen` attaches on iOS
    /// alone.
    func scrollPhaseChanged(_ phase: ScrollPhase) {
        if Self.isHold(phase), !Self.isHold(scrollPhase) {
            readerHolds += 1
            // A hand on the thread mid-resize takes it from there.
            resizeKeepsFoot = false
        }
        scrollPhase = phase
    }

    /// Whether the follow asked for the foot and the thread isn't there, with
    /// nothing of the reader's in between.
    ///
    /// **The check after the follow, because a turn's last follow doesn't
    /// reliably arrive.** That growth (the tiles, the evidence line and the
    /// chips, in the frame `isThinking` goes false) lands inside the stage's
    /// `.snappy` transaction and on top of the scroll the growth before it
    /// started. With the follow a task, as `AskScreen` runs it, a send still
    /// ended 138 pt short. Traced on an iPhone 17 Pro simulator, the follow
    /// fell short three ways, each with the chips under the composer and no
    /// pill:
    ///
    /// - **It never moved.** Two follows were asked for 21 ms apart as the
    ///   content grew 3441 → 3898 pt, and the offset stayed at 2704, the foot
    ///   of the thread before either.
    /// - **It arrived and came back.** Offset 3294 → 3673.6 (the foot) →
    ///   3453.3 inside 29 ms with the content unchanged: the shape
    ///   `AskThreadGeometry.readerScrolledUp(from:)` reads as a drag, so
    ///   `isAtFoot` went false with no finger on the glass.
    /// - **It stuck.** The phase went `idle → animating` as the scroll began,
    ///   the chips grew the content 116 pt 10 ms later, a second follow was
    ///   asked for, and the scroll view reported no geometry and no phase
    ///   again, still `.animating`.
    ///
    /// Two of those leave `isAtFoot` set and one clears it, so it isn't what
    /// this reads. `holds` is `readerHolds` as the follow read it when it
    /// scrolled: a hold since, or one still under way, is the reader's to
    /// keep, however far from the foot it left the thread.
    ///
    /// **It can't tell the reader from a scroll that reports no hold.** One of
    /// those inside `followQuiet` of a growth the follow chased is undone
    /// once. Every growth restarts the wait, so the window is the half-second
    /// after a growth that no other growth follows inside it: a turn's last,
    /// and a stream's longer pauses. Which scrolls report none wasn't
    /// measured. On an iPhone the status bar's scroll to the top is the
    /// likeliest, and on a Mac it could be the wheel, a reader's everyday
    /// scroll, so `AskScreen` runs the check on iOS alone, where the traces
    /// came from.
    func fellShort(since holds: Int) -> Bool {
        guard isScrollable, holds == readerHolds, !isReaderScrolling, let lastGeometry else { return false }
        // The last turn's end below the bottom edge, which is this type's
        // meaning of "not at the foot": the spacer under it may sit there
        // hiding nothing.
        return lastGeometry.distanceFromContentFoot - Self.restingTrailingSpace > 0
    }

    /// A finger or a trackpad on the thread. `.decelerating` is the momentum
    /// one leaves behind: still the reader's, but not a new hold.
    private static func isHold(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting
    }

    private var isReaderScrolling: Bool {
        Self.isHold(scrollPhase) || scrollPhase == .decelerating
    }

    /// The last turn's measured height.
    ///
    /// Rounded to whole points: this arrives from `onGeometryChange` on a view
    /// whose height moves in fractions as text reflows, and every published
    /// change costs a `body`.
    func lastTurnHeightChanged(_ height: CGFloat, at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        let rounded = height.rounded()
        guard rounded != lastTurnHeight else { return }
        // **Growth only.** Half the changes that arrive here are shrinks (a
        // turn rewrapping to fewer lines as the final snapshot tidies its
        // prose, measured at 724 to 704 pt on the demo), and a turn that got
        // shorter has put nothing out of the reader's sight.
        //
        // **And only the thread's.** A reader who scrolled up and then opened
        // something in place grew the turn with their own tap, and a pill
        // would report what they are already looking at.
        if rounded > lastTurnHeight, !isAtFoot, ownsGrowth(at: now) { hasUnseenGrowth = true }
        lastTurnHeight = rounded
    }

    func streamingChanged(_ streaming: Bool, at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        isStreaming = streaming
        // Both ways: a turn's last growth lands as its stream stops, and that
        // growth is most of what `ownGrowthWindow` is for.
        ownGrowthSince = now
        // Deliberately doesn't assume the reader is at the foot. A new
        // question is sent to the thread's foot, and the screen does that, but
        // this type is told about streaming before that scroll reports back:
        // geometry decides, not this.
    }

    /// A new turn has been appended.
    ///
    /// Zero is the honest value for a turn nothing has measured yet, and it
    /// keeps `lastTurnHeight` from carrying the previous turn's height into
    /// the new one, where the first real measurement would read as a shrink
    /// rather than the growth it is, and the follow's trigger would fire a
    /// turn late. `jumped(at:)` beside it is the assumption that a reader who
    /// just asked something wants to see it answered.
    ///
    /// A thread read back from disk, or opened from the list of chats, arrives
    /// here too, with nothing streaming, and lands at its foot through its
    /// first measurements, which `jumped(at:)` makes the thread's own.
    func turnStarted(at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        lastTurnHeight = 0
        jumped(at: now)
    }

    /// The thread has appeared, or taken a new last turn, and the screen is
    /// sending it to its own end, with `streaming` saying whether an answer
    /// is being written as it does (`AskScreen`'s `thread`).
    ///
    /// **Told what is streaming, because the screen may be built mid-stream.**
    /// One store can stand behind a screen in each of several windows, and a
    /// split view's detail rebuilds its screen, so a screen can appear with an
    /// answer already streaming. Its follow is new, and `streamingChanged(_:at:)`
    /// hears only a stream starting or stopping: told only that the thread was
    /// sent to its end, the follow kept the answer's growth for
    /// `ownGrowthWindow` and then let it write itself below the composer, and
    /// `showsJumpPill` took the settled rule, so the reader got no pill either,
    /// until the turn ended. Both ways, so a stream this follow last heard of
    /// never outlives its turn.
    func threadAppeared(streaming: Bool, at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        isStreaming = streaming
        jumped(at: now)
    }

    /// The reader tapped the pill, or the thread was sent to its own end.
    ///
    /// Either way the thread is on its way to its foot, measuring the rows it
    /// builds on the way there, so their growth is its own for
    /// `ownGrowthWindow`, and the steps its glide takes are its own for
    /// `jumpGlideWindow`.
    func jumped(at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        isAtFoot = true
        isFar = false
        hasUnseenGrowth = false
        ownGrowthSince = now
        jumpedAt = now
    }
}

#endif
