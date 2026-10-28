#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import SwiftUI
import Testing

@testable import AskUI

/// Never pull the reader down a streaming answer, and never leave them staring
/// at the space where it is being written.
///
/// Easy to get wrong and hard to see wrong by watching a thread, and pure
/// arithmetic, so it is verified here.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskScrollFollowTests {

    /// An iPhone 17 Pro's thread: 670pt between the navigation bar and the
    /// composer. Every distance below is in that screen's terms.
    private static let readable: CGFloat = 670

    /// A phone's toolbar, so the rest position is `-116` as it is on the
    /// device.
    private static let insetTop: CGFloat = 116

    /// A sample of a thread sitting `distance` above its content's foot.
    ///
    /// The content height is arbitrary and the offset is solved for, because
    /// what every flag reads is the distance. Where a test needs the READER to
    /// have moved, it passes two samples with the same content and container
    /// — see `theThreadFollowsGrowthItHasNotCaughtUpWithYet`.
    private static func sample(
        distanceFromContentFoot distance: CGFloat,
        contentHeight: CGFloat = 4000,
        containerHeight: CGFloat = readable
    ) -> AskThreadGeometry {
        AskThreadGeometry(
            contentHeight: contentHeight,
            containerHeight: containerHeight,
            insetTop: insetTop,
            offset: contentHeight - containerHeight - insetTop - distance
        )
    }

    /// A phone's thread, its first sample taken at `now`.
    ///
    /// **Every call in this suite says when it happened.** The follow's
    /// windows are half a second to a second long, and a call left on its
    /// default reads the wall clock: such a test passes only while the machine
    /// running it keeps up, and one that mixes the two compares an instant in
    /// 2001 with today.
    private func onAPhone(at now: TimeInterval) -> AskScrollFollow {
        let follow = AskScrollFollow()
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 0), at: now)
        return follow
    }

    @Test func measurementsAreRoundedToWholePoints() {
        // Both arrive from geometry callbacks that move in fractions as text
        // reflows, and every change that is published costs a `body`.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(100.4, at: now)
        #expect(follow.lastTurnHeight == 100)
        follow.lastTurnHeightChanged(100.6, at: now)
        #expect(follow.lastTurnHeight == 101)
    }

    // MARK: - What is followed, and when

    @Test func aShortTurnIsFollowedTooBecauseThereIsNoSecondPhase() {
        // Nothing is held open under a question, so there is no "still
        // filling" state in which growth must be ignored: every turn is
        // followed from the frame it starts, which is what makes a two-line
        // answer and a two-screen one behave the same way.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(100, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 0), at: now)
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))
    }

    @Test func theFootIsFollowedAndOnlyFromTheFoot() {
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: now)
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))
        #expect(!follow.showsJumpPill)

        // Scrolled up: the thread stops moving and offers to catch up instead.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 400), at: now)
        #expect(!follow.isAtFoot)
        #expect(!follow.followsGrowth(at: now))
        #expect(follow.showsJumpPill)
    }

    @Test func theBoundaryIsEightyPointsFromTheLastTurnsEnd() {
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        let room = AskScrollFollow.restingTrailingSpace
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + AskScrollFollow.followWithin), at: now)
        #expect(follow.isAtFoot)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + AskScrollFollow.followWithin + 1), at: now)
        #expect(!follow.isAtFoot)
    }

    @Test func theLastGrowthOfATurnIsFollowedToo() {
        // The tiles, the evidence line and the follow-ups all arrive in the
        // frame the turn completes and `isThinking` goes false. A reader at
        // the foot should see them, so the follow isn't held to streaming
        // alone: `followsGrowth(at:)` explains, and `ownGrowthWindow` bounds it
        // instead.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: now)
        follow.streamingChanged(false, at: now)
        #expect(follow.followsGrowth(at: now))
    }

    @Test func theThreadFollowsGrowthItHasNotCaughtUpWithYet() {
        // **The thread growing away from the reader isn't the reader leaving.**
        // A reveal chunk lays out several hundred points in one pass, and the
        // geometry callback runs BEFORE the height change that would follow
        // it, so `isAtFoot`, read off the distance alone, would already be
        // false when the follow asked. The answer would then stream off the
        // bottom of the screen with the pill as the only way to reach it
        // (`AskThreadGeometry.readerScrolledUp(from:)` has the trace).
        //
        // The reader has not moved: same offset, taller content.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 12, contentHeight: 4000), at: now)
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))

        let grown = AskThreadGeometry(
            contentHeight: 4900,
            containerHeight: Self.readable,
            insetTop: Self.insetTop,
            offset: Self.sample(distanceFromContentFoot: 12, contentHeight: 4000).offset
        )
        #expect(grown.distanceFromContentFoot - AskScrollFollow.restingTrailingSpace
                > AskScrollFollow.followWithin)
        follow.geometryChanged(grown, at: now)
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))
        // And no pill for a thread that is about to catch up by itself.
        #expect(!follow.showsJumpPill)
    }

    @Test func aReaderWhoScrollsUpStopsTheFollowEvenMidGrowth() {
        // The other half of the same sample: content unchanged, offset down.
        // That is a drag, a wheel or the momentum of one, and it is the only
        // thing that may take the thread away from its own foot.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 12), at: now)
        #expect(follow.followsGrowth(at: now))

        follow.geometryChanged(Self.sample(distanceFromContentFoot: 600), at: now)
        #expect(!follow.isAtFoot)
        #expect(!follow.followsGrowth(at: now))
        #expect(follow.showsJumpPill)

        // Scrolling back down needs no special case: arriving within the
        // boundary is what says the reader is back.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 12), at: now)
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))
    }

    @Test func aKeyboardCannotTakeTheThreadOffItsFoot() {
        // A keyboard rising shrinks the container and moves the offset with
        // it, which is the shape a naive "the offset went down" test would
        // read as a drag. `readerScrolledUp(from:)` requires the container to
        // have held still.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 12), at: now)
        #expect(follow.followsGrowth(at: now))

        follow.geometryChanged(
            Self.sample(distanceFromContentFoot: 600, containerHeight: Self.readable - 336), at: now
        )
        #expect(follow.isAtFoot)
        #expect(follow.followsGrowth(at: now))
    }

    @Test func aThreadThatFitsIsNeverScrolled() {
        // **A scroll view whose content fits does not refuse a `scrollTo`.**
        // Measured on an iPhone 17 Pro with a two-line first turn: asking for
        // the foot on 294pt of content in a 670pt thread took the offset to -232,
        // a whole navigation bar above its own rest position of -116, and it
        // bounced back the next frame. Nothing was off screen; the thread
        // lifted itself under the bar for no reason and dropped back.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(74, at: now)
        follow.geometryChanged(
            AskThreadGeometry(
                contentHeight: 294, containerHeight: Self.readable,
                insetTop: Self.insetTop, offset: -Self.insetTop
            ),
            at: now
        )
        #expect(!follow.isScrollable)
        #expect(!follow.followsGrowth(at: now))
        #expect(!follow.showsJumpPill)
    }

    @Test func aThreadThatOverflowsIsFollowedAgain() {
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(74, at: now)
        follow.geometryChanged(
            AskThreadGeometry(
                contentHeight: 294, containerHeight: Self.readable,
                insetTop: Self.insetTop, offset: -Self.insetTop
            ),
            at: now
        )
        #expect(!follow.followsGrowth(at: now))

        // A point past the bottom edge and the thread has somewhere to go.
        follow.geometryChanged(
            AskThreadGeometry(
                contentHeight: Self.readable + 1, containerHeight: Self.readable,
                insetTop: Self.insetTop, offset: -Self.insetTop
            ),
            at: now
        )
        #expect(follow.isScrollable)
        #expect(follow.followsGrowth(at: now))
    }

    // MARK: - Whose growth it is

    @Test func whatTheReaderOpensInASettledTurnDoesNotMoveTheThread() {
        // **What `ownGrowthWindow` is for.** A host's card that opens in place
        // in the settled last turn, taken for the answer arriving, would have
        // the follow scroll the thread to its foot: the chips would stay pinned
        // over the composer and the card would go up under the navigation bar.
        // The rows behind an evidence line open the same way.
        let follow = onAPhone(at: 100)
        follow.streamingChanged(true, at: 100)
        follow.lastTurnHeightChanged(Self.readable + 400, at: 110)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: 110)
        follow.streamingChanged(false, at: 112)

        // Read for a few seconds, then a card opened.
        follow.lastTurnHeightChanged(Self.readable + 700, at: 116)
        #expect(follow.isAtFoot)
        #expect(!follow.followsGrowth(at: 116))
        #expect(!follow.showsJumpPill)
    }

    @Test func theGrowthATurnEndsWithIsStillTheThreads() {
        // The tiles, the evidence line and the chips land in the frame the
        // stream stops, milliseconds after it.
        let follow = onAPhone(at: 100)
        follow.streamingChanged(true, at: 100)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: 100)
        follow.streamingChanged(false, at: 112)
        follow.lastTurnHeightChanged(Self.readable + 400, at: 112.02)
        #expect(follow.followsGrowth(at: 112.02))
        #expect(!follow.followsGrowth(at: 112 + AskScrollFollow.ownGrowthWindow))
    }

    @Test func aStreamIsTheThreadsForAsLongAsItRuns() {
        // The window is for what lands after a stream; a stream needs none,
        // however long the model takes over it.
        let follow = onAPhone(at: 100)
        follow.streamingChanged(true, at: 100)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: 100)
        #expect(follow.followsGrowth(at: 140))
    }

    @Test func aThreadReadBackFromDiskLandsThroughItsFirstMeasurements() {
        // A restored thread, or one opened from the list of chats, arrives
        // through `turnStarted` with nothing streaming, and is measured as it
        // is first laid out.
        let follow = onAPhone(at: 100)
        follow.turnStarted(at: 100)
        follow.lastTurnHeightChanged(Self.readable + 400, at: 100.3)
        #expect(follow.followsGrowth(at: 100.3))
        #expect(!follow.followsGrowth(at: 100 + AskScrollFollow.ownGrowthWindow))
    }

    @Test func thePillLandsTheThreadThroughWhatItBuildsOnTheWay() {
        // The rows a jump to the end builds are measured as they come, and
        // their growth is the thread's.
        let follow = onAPhone(at: 200)
        follow.jumped(at: 200)
        follow.lastTurnHeightChanged(Self.readable + 300, at: 200.2)
        #expect(follow.followsGrowth(at: 200.2))
        #expect(!follow.followsGrowth(at: 200 + AskScrollFollow.ownGrowthWindow))
    }

    @Test func theReadersOwnGrowthArmsNoPill() {
        // A reader who nudged a settled thread up and then opened something in
        // place grew the turn with their own tap. A pill would report what
        // they are already looking at.
        let follow = onAPhone(at: 100)
        let room = AskScrollFollow.restingTrailingSpace
        follow.streamingChanged(true, at: 100)
        follow.lastTurnHeightChanged(Self.readable + 300, at: 110)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room), at: 110)
        follow.streamingChanged(false, at: 112)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: 115)
        #expect(!follow.isAtFoot)

        follow.lastTurnHeightChanged(Self.readable + 600, at: 120)
        #expect(!follow.hasUnseenGrowth)
        #expect(!follow.showsJumpPill)
    }

    // MARK: - A thread that appears mid-stream

    @Test func aThreadBuiltMidStreamFollowsTheAnswerPastTheOwnGrowthWindow() {
        // **A second window, or a split view's detail rebuilt, while an answer
        // streams.** The screen's follow is new and has heard no stream start:
        // told only that the thread was sent to its end, it followed for
        // `ownGrowthWindow` and then let the answer write itself below the
        // composer, with no pill, until the turn ended.
        let follow = AskScrollFollow()
        follow.threadAppeared(streaming: true, at: 100)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: 100)
        follow.lastTurnHeightChanged(Self.readable + 400, at: 105)
        #expect(follow.followsGrowth(at: 105))

        // The reader scrolls up mid-stream: the way back down is offered at
        // the follow boundary, as on any stream.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace + 250), at: 106)
        #expect(!follow.followsGrowth(at: 106))
        #expect(follow.showsJumpPill)
        follow.lastTurnHeightChanged(Self.readable + 600, at: 107)
        #expect(follow.hasUnseenGrowth)
    }

    @Test func aThreadBuiltWithNothingStreamingKeepsOnlyTheOwnGrowthWindow() {
        // A thread read back from disk or opened from the chats lands through
        // its first measurements, and what grows after that is the reader's.
        let follow = AskScrollFollow()
        follow.threadAppeared(streaming: false, at: 100)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: 100)
        follow.lastTurnHeightChanged(Self.readable + 400, at: 100.3)
        #expect(follow.followsGrowth(at: 100.3))
        #expect(!follow.followsGrowth(at: 100 + AskScrollFollow.ownGrowthWindow))
    }

    @Test func aThreadThatAppearsAfterItsStreamEndedFollowsNoStream() {
        // The appearance says what is streaming now, both ways, so a stream
        // the follow last heard of doesn't outlive the turn it belonged to.
        let follow = onAPhone(at: 100)
        follow.streamingChanged(true, at: 100)
        follow.threadAppeared(streaming: false, at: 110)
        #expect(!follow.followsGrowth(at: 110 + AskScrollFollow.ownGrowthWindow))
    }

    // MARK: - The way back down

    @Test func aFinishedThreadOffersTheWayBackButOnlyFromAWayOff() {
        // The pill is not symmetrical with the follow. A settled thread the
        // reader has scrolled a long way up is exactly where a way back down
        // earns its place, since threads grow long, so the pill appears at
        // `farFromFoot`, five times the follow boundary, and never at the 81pt
        // that would put a floating button over the composer of someone who
        // scrolled one line.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        let room = AskScrollFollow.restingTrailingSpace

        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 10), at: now)
        #expect(!follow.showsJumpPill)

        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + AskScrollFollow.followWithin + 1), at: now)
        #expect(!follow.showsJumpPill)

        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + AskScrollFollow.farFromFoot + 1), at: now)
        #expect(follow.showsJumpPill)
    }

    @Test func aStreamUsesTheFollowBoundaryAndNotTheFarOne() {
        // The two distances are not interchangeable: while an answer is
        // growing off the bottom of the screen, anything past the follow
        // boundary means the reader is missing it, and waiting for 400pt
        // would leave four fifths of a screen unreported.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        let room = AskScrollFollow.restingTrailingSpace
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + AskScrollFollow.followWithin + 1), at: now)
        #expect(follow.showsJumpPill)
        #expect(!follow.isFar)
    }

    @Test func theWayBackDownSurvivesTheStreamEnding() {
        // A reader who scrolled up mid-answer and left it there still has the
        // pill when the turn lands. Taking the pill away at the moment the
        // answer finishes is the opposite of what the reader was waiting for.
        //
        // **900pt is past `farFromFoot`, so this holds on the settled rule
        // alone and proves nothing about the sentence above it.** The band
        // between the two boundaries is the case that matters, and
        // `aTurnThatLandedWhileTheReaderWasAwayKeepsTheWayBack` pins it.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace + 900), at: now)
        #expect(follow.showsJumpPill)
        follow.streamingChanged(false, at: now)
        #expect(follow.showsJumpPill)
    }

    @Test func aTurnThatLandedWhileTheReaderWasAwayKeepsTheWayBack() {
        // **The dead zone `hasUnseenGrowth` closes.** Without it, between
        // `followWithin` and `farFromFoot` a settled thread offers neither
        // behaviour: the follow is disengaged, correctly, because the reader
        // scrolled up, and the pill is withheld because 300pt is not 400. So
        // the tiles, the evidence line and the follow-ups all land under the
        // composer and nothing says so.
        //
        // Measured on the demo, iPhone 17 Pro: a reader who drags ~190pt while
        // an answer is arriving settles at `distance=373`, and 373 < 400. That
        // is not an unlucky number: a turn's last growth (tiles, evidence line
        // and chips) is ~300pt, so the band is exactly where one turn's ending
        // puts a reader who touched the thread.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        let room = AskScrollFollow.restingTrailingSpace
        // Away from the foot, but not a way off: inside the band.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: now)
        // The turn ends: tiles, evidence line and follow-ups in one growth,
        // all of it below the bottom edge.
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.streamingChanged(false, at: now)

        #expect(!follow.isAtFoot)
        #expect(!follow.isFar)
        #expect(follow.showsJumpPill)
    }

    @Test func aReaderBrowsingASettledThreadStillEarnsThePill() {
        // The other half, and the reason the band is not simply widened: a
        // reader scrolling back through a long thread that has stopped moving
        // has missed nothing, so a nudge must not summon a floating button
        // over the composer. `farFromFoot` still governs that, unchanged.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        let room = AskScrollFollow.restingTrailingSpace
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        // Back at the foot, having seen the whole of the last turn.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room), at: now)
        // Now they go looking — nothing has arrived since.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: now)

        #expect(!follow.isAtFoot)
        #expect(!follow.showsJumpPill)
    }

    @Test func scrollingBackDownIsAsGoodAsTappingThePill() {
        // The pill is not the only way back, and the flag that keeps it alive
        // has to notice the other one. A reader who drags down to the foot
        // never calls `jumped()`, so clearing the unseen tail there alone
        // would leave the pill armed for the rest of the thread's life — and
        // the next one-line nudge would put it back at 81pt, which is the
        // thing `farFromFoot` exists to prevent.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        let room = AskScrollFollow.restingTrailingSpace
        follow.streamingChanged(true, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.streamingChanged(false, at: now)
        #expect(follow.showsJumpPill)

        // Dragged back down, no pill tapped.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room), at: now)
        #expect(follow.isAtFoot)
        #expect(!follow.showsJumpPill)

        // And the thread is an ordinary settled one again.
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: now)
        #expect(!follow.showsJumpPill)
    }

    @Test func aTurnSettlingToFewerLinesIsNotSomethingTheReaderMissed() {
        // `lastTurnHeightChanged` fires on every reflow, and a good half of
        // them are shrinks — measured on the demo, a turn rewrapping from
        // 724pt to 704pt as the final snapshot tidies its prose. A turn that
        // got SHORTER has put nothing out of sight, so it must not arm the
        // pill on a thread the reader is merely browsing.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        let room = AskScrollFollow.restingTrailingSpace
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room), at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: room + 250), at: now)
        follow.lastTurnHeightChanged(Self.readable + 280, at: now)

        #expect(!follow.showsJumpPill)
    }

    @Test func aTurnStartingDoesNotAssumeTheFootIsInView() {
        // A new question is sent to the thread's foot and the screen does
        // that, but this type hears about the stream before that scroll
        // reports back — so on a long thread the reader is still somewhere
        // else the moment the turn begins. Assuming otherwise is how a thread
        // yanks itself down on the first token.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace + 600), at: now)
        follow.streamingChanged(true, at: now)
        #expect(!follow.isAtFoot)
        #expect(!follow.followsGrowth(at: now))
        #expect(follow.showsJumpPill)
    }

    @Test func tappingThePillCatchesUpAndTheThreadResumesFollowing() {
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.streamingChanged(true, at: now)
        follow.lastTurnHeightChanged(Self.readable + 400, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace + 600), at: now)
        #expect(follow.showsJumpPill)

        follow.jumped(at: now)
        #expect(follow.isAtFoot)
        #expect(!follow.isFar)
        #expect(follow.followsGrowth(at: now))
        #expect(!follow.showsJumpPill)
    }

    // MARK: - The thread's own jump

    @Test func aJumpReAimedMidGlideIsNotTheReaderLeaving() {
        // Traced on every send under a tall turn: the new row appended at an
        // estimate, the jump's animation aimed at that estimate's foot, then
        // the row measured 373pt shorter and the offset dropped by the whole
        // correction in one sample with the content unchanged: a drag, to two
        // samples. The thread is still on its way to its foot.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        let atFoot = Self.sample(distanceFromContentFoot: 0, contentHeight: 1288)
        follow.geometryChanged(atFoot, at: now)
        follow.streamingChanged(true, at: now)
        follow.turnStarted(at: now)
        follow.scrollPhaseChanged(.animating)

        var estimated = atFoot
        estimated.contentHeight = 1613
        follow.geometryChanged(estimated, at: now + 0.008)
        var measured = estimated
        measured.contentHeight = 1240
        follow.geometryChanged(measured, at: now + 0.009)
        var reAimed = measured
        reAimed.offset -= 372
        follow.geometryChanged(reAimed, at: now + 0.011)

        #expect(follow.isAtFoot)
        #expect(!follow.showsJumpPill)
        follow.lastTurnHeightChanged(139, at: now + 0.07)
        #expect(follow.followsGrowth(at: now + 0.07))
    }

    @Test func theSameStepAfterTheGlideIsTheReaders() {
        // Only the jump's own glide is set aside. `.animating`, the phase that
        // tells the check after the follow "not a hand", is no proof the scroll
        // was the thread's, so outside `jumpGlideWindow` a step back up clears
        // `isAtFoot` as any drag does.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        let atFoot = Self.sample(distanceFromContentFoot: 0, contentHeight: 1240)
        follow.geometryChanged(atFoot, at: now)
        follow.streamingChanged(true, at: now)
        follow.jumped(at: now)
        follow.scrollPhaseChanged(.animating)

        var up = atFoot
        up.offset -= 372
        follow.geometryChanged(up, at: now + AskScrollFollow.jumpGlideWindow + 0.1)

        #expect(!follow.isAtFoot)
        #expect(follow.showsJumpPill)
    }

    // MARK: - The check after the follow

    @Test func aFollowThatNeverMovedIsFinished() {
        // The first of the three ways a turn's last follow was traced falling
        // short: the chips grew the content and the offset stayed at the foot
        // of the thread as it had been. Nothing scrolled up, so `isAtFoot` is
        // still set and only the distance says anything is wrong.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        let before = Self.sample(distanceFromContentFoot: 0, contentHeight: 3441)
        follow.geometryChanged(before, at: now)
        let holds = follow.readerHolds

        var grown = before
        grown.contentHeight = 3898
        follow.geometryChanged(grown, at: now)

        #expect(follow.isAtFoot)
        #expect(follow.fellShort(since: holds))
    }

    @Test func aFollowThatCameBackUpIsFinishedThoughItReadsAsADrag() {
        // The second: the scroll reached the foot and came back 220pt with the
        // content unchanged, which two samples cannot tell from a drag. So
        // `isAtFoot` is gone, and the pill with it — 208pt is short of
        // `farFromFoot` on a settled thread — with no finger on the glass. No
        // hold since the follow scrolled is what says it was not the reader.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 0, contentHeight: 4411), at: now)
        let holds = follow.readerHolds

        follow.scrollPhaseChanged(.animating)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 220, contentHeight: 4411), at: now)
        follow.scrollPhaseChanged(.idle)

        #expect(!follow.isAtFoot)
        #expect(!follow.showsJumpPill)
        #expect(follow.fellShort(since: holds))
    }

    @Test func aFollowStuckMidAnimationIsFinished() {
        // The third: `.animating`, then no geometry and no phase ever again,
        // 138pt short. A phase that never ends is still not a hand.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        let before = Self.sample(distanceFromContentFoot: 56, contentHeight: 4211)
        follow.geometryChanged(before, at: now)
        let holds = follow.readerHolds

        follow.scrollPhaseChanged(.animating)
        var grown = before
        grown.contentHeight = 4327
        follow.geometryChanged(grown, at: now)

        #expect(follow.isAtFoot)
        #expect(follow.fellShort(since: holds))
    }

    @Test func theCheckAfterTheFollowLeavesTheReadersScrollAlone() {
        // A hold since the follow scrolled is the reader's, however little it
        // moved the thread: let go inside the follow boundary, with `isAtFoot`
        // still set and the last line a nudge below the bottom edge, it is
        // theirs.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 0), at: now)
        let holds = follow.readerHolds

        follow.scrollPhaseChanged(.tracking)
        follow.scrollPhaseChanged(.interacting)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 50), at: now)
        // And while the hand is still there, whatever mark the follow took.
        #expect(!follow.fellShort(since: follow.readerHolds))
        follow.scrollPhaseChanged(.decelerating)
        #expect(!follow.fellShort(since: follow.readerHolds))
        follow.scrollPhaseChanged(.idle)

        #expect(follow.isAtFoot)
        #expect(!follow.fellShort(since: holds))
        // One hold, however many phases it passed through.
        #expect(follow.readerHolds == holds + 1)
    }

    @Test func aThreadWithItsLastLineInViewHasNothingToFinish() {
        // Measured from the last turn's end, like every distance here: the
        // spacer under it may sit below the bottom edge without hiding
        // anything.
        let now: TimeInterval = 100
        let follow = onAPhone(at: now)
        follow.lastTurnHeightChanged(Self.readable + 300, at: now)
        follow.geometryChanged(Self.sample(distanceFromContentFoot: 0), at: now)
        #expect(!follow.fellShort(since: follow.readerHolds))
        follow.geometryChanged(Self.sample(distanceFromContentFoot: AskScrollFollow.restingTrailingSpace), at: now)
        #expect(!follow.fellShort(since: follow.readerHolds))
    }

    // MARK: - A resize

    /// The demo's thread on an iPhone 18 Pro simulator, as traced turning it
    /// onto its side and back: `width` across the space between the bars and
    /// `container` down it.
    private static func traced(
        width: CGFloat, container: CGFloat, content: CGFloat,
        offset: CGFloat, inset: CGFloat = insetTop
    ) -> AskThreadGeometry {
        AskThreadGeometry(
            contentHeight: content, containerHeight: container,
            insetTop: inset, offset: offset, containerWidth: width
        )
    }

    /// Upright and at the foot, with the end of the content at the bottom
    /// edge.
    private static let upright = traced(width: 402, container: 670, content: 1657, offset: 871)

    @Test func aPhoneTurnedOnItsSideKeepsTheReaderAtTheFoot() {
        // **A turned phone isn't a drag.** A settled thread, the reader at its
        // foot, the phone turned. The scroll view reported the new width at
        // the old offset, then the offset 117pt lower with nothing else
        // changed: a drag, to two samples. Read as one, it would leave the
        // reader 645pt above the foot once the phone is on its side, behind
        // the pill.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)

        // A width of the rotation's own first, the rows still at estimates for
        // it.
        follow.geometryChanged(Self.traced(width: 340, container: 722, content: 1480, offset: 871), at: now + 0.001)
        follow.geometryChanged(Self.traced(width: 340, container: 722, content: 2205, offset: 871), at: now + 0.008)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 871), at: now + 0.023)
        let beforeTheStep = follow.footRequests
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 754), at: now + 0.028)
        #expect(follow.isAtFoot)
        #expect(!follow.showsJumpPill)
        #expect(follow.footRequests > beforeTheStep)

        // The bars' new inset, then the rows measured at the new width, each
        // leaving the foot further down and each asked for again.
        let beforeTheRows = follow.footRequests
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 1765, offset: 792, inset: 78), at: now + 0.034
        )
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 1771, offset: 792, inset: 78), at: now + 0.226
        )
        #expect(follow.isAtFoot)
        #expect(!follow.showsJumpPill)
        #expect(follow.footRequests == beforeTheRows + 2)

        // The screen's scroll lands, and there is nothing left to ask for.
        let landed = follow.footRequests
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 1771, offset: 1443, inset: 78), at: now + 0.24
        )
        #expect(follow.isAtFoot)
        #expect(follow.footRequests == landed)
    }

    @Test func theSameStepAfterTheResizeIsTheReaders() {
        // Only the resize's own steps are set aside. Past `resizeWindow` the
        // traced step clears the flag as any drag does, and at 408pt from the
        // last turn's end it is far enough to earn the pill.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 871), at: now + 0.01)
        let asked = follow.footRequests

        let later = now + 0.01 + AskScrollFollow.resizeWindow + 0.1
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 754), at: later)
        #expect(!follow.isAtFoot)
        #expect(follow.showsJumpPill)
        #expect(follow.footRequests == asked)
    }

    @Test func aHandOnTheThreadMidResizeIsTheReaders() {
        // A reader who takes hold of the thread while it is being resized has
        // it from there: the step is theirs, and nothing carries them back to
        // the foot once they let go.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 871), at: now + 0.01)
        let asked = follow.footRequests

        follow.scrollPhaseChanged(.interacting)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 754), at: now + 0.02)
        #expect(!follow.isAtFoot)
        follow.scrollPhaseChanged(.idle)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1771, offset: 754), at: now + 0.03)
        #expect(!follow.isAtFoot)
        #expect(follow.footRequests == asked)
    }

    @Test func aReaderUpTheThreadIsLeftWhereTheyWere() {
        // Traced as well: 645pt from the foot upright, and 645pt again with
        // the phone turned back, nothing asked for either way.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 402, container: 670, content: 1657, offset: 226), at: now + 1)
        #expect(!follow.isAtFoot)
        #expect(follow.showsJumpPill)

        follow.geometryChanged(Self.traced(width: 340, container: 722, content: 1671, offset: 226), at: now + 10)
        follow.geometryChanged(Self.traced(width: 340, container: 722, content: 2205, offset: 226), at: now + 10.005)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1829, offset: 226), at: now + 10.016)
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 1829, offset: 264, inset: 78), at: now + 10.021
        )
        #expect(!follow.isAtFoot)
        #expect(follow.showsJumpPill)

        follow.geometryChanged(Self.traced(width: 402, container: 670, content: 1657, offset: 226), at: now + 15)
        #expect(!follow.isAtFoot)
        #expect(follow.footRequests == 0)
    }

    @Test func aResizeLeavesWhatTheReaderOpenedWhereTheyOpenedIt() {
        // The latch that keeps a growing thread followed survives the reader's
        // own growth too: a card opened in place in a settled last turn
        // pushes the foot 400pt down and leaves `isAtFoot` set. The resize
        // reads the distance, so it does not carry the reader off the card.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 402, container: 670, content: 2057, offset: 871), at: now + 5)
        #expect(follow.isAtFoot)

        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1940, offset: 871), at: now + 10)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1940, offset: 754), at: now + 10.005)
        #expect(follow.footRequests == 0)
    }

    @Test func aKeyboardIsNotAResize() {
        // It takes the height and never the width, so a settled thread it
        // rises over stays where it was, 294pt of it under the keyboard as
        // traced. `aKeyboardCannotTakeTheThreadOffItsFoot` pins the flag's
        // half of that decision; this pins the scroll's.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 402, container: 376, content: 1657, offset: 871), at: now + 0.01)
        #expect(follow.isAtFoot)
        #expect(follow.footRequests == 0)
    }

    @Test func aResizesRequestsLapseWithIt() {
        // `AskScreen` answers `footRequests` from a task that also runs each
        // time the thread appears, with whatever count the last resize left,
        // so it asks this first: no once the window has passed, and no once a
        // hand is on the thread.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 871), at: now + 0.01)
        #expect(follow.footRequests > 0)
        #expect(follow.keepsFootThroughResize(at: now + 0.02))
        #expect(!follow.keepsFootThroughResize(at: now + 0.01 + AskScrollFollow.resizeWindow + 0.1))

        follow.scrollPhaseChanged(.interacting)
        #expect(!follow.keepsFootThroughResize(at: now + 0.02))
    }

    // MARK: - The navigation bar

    @Test func theBarLooksOpenUntilTheInsetShrinks() {
        // Measured beside a fold on an iPhone 18 Pro simulator: the bar
        // minimizing took 54 pt out of the inset.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        #expect(!follow.barLooksMinimized)

        follow.geometryChanged(Self.traced(width: 402, container: 724, content: 1657, offset: 900, inset: 62), at: now + 1)
        #expect(follow.barLooksMinimized)

        follow.geometryChanged(Self.traced(width: 402, container: 670, content: 1657, offset: 700), at: now + 2)
        #expect(!follow.barLooksMinimized)
    }

    @Test func aPhoneTurnedOnItsSideStartsTheBarOverAtItsNewInset() {
        // The bars' shorter inset on its side arrives a few milliseconds after
        // the width, inside the resize: that is the open bar there, not a
        // minimized one.
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(Self.upright, at: now)
        follow.geometryChanged(Self.traced(width: 750, container: 250, content: 1540, offset: 871), at: now + 0.023)
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 1765, offset: 792, inset: 78), at: now + 0.034
        )
        #expect(!follow.barLooksMinimized)

        // Minimized on its side, well after the turn.
        follow.geometryChanged(
            Self.traced(width: 750, container: 300, content: 1765, offset: 820, inset: 30), at: now + 5
        )
        #expect(follow.barLooksMinimized)
    }

    @Test func aThreadThatFitsEitherWayAsksForNothing() {
        let follow = AskScrollFollow()
        let now: TimeInterval = 100
        follow.geometryChanged(
            Self.traced(width: 402, container: 670, content: 294, offset: -Self.insetTop), at: now
        )
        follow.geometryChanged(
            Self.traced(width: 750, container: 250, content: 210, offset: -Self.insetTop), at: now + 0.01
        )
        #expect(!follow.isScrollable)
        #expect(follow.footRequests == 0)
    }
}

/// The five numbers the thread reads off its scroll view, and the term in them
/// that is easy to miss.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskThreadGeometryTests {

    /// An iPhone 17 Pro's Ask screen, as instrumented on the demo: an 874pt
    /// scroll view with a 116pt navigation bar over it and an 88pt composer
    /// under it, leaving 670 between them.
    private static let container: CGFloat = 670
    private static let insetTop: CGFloat = 116
    private static let insetBottom: CGFloat = 88

    /// Where `contentOffset.y` sits when the content's foot is at the bottom
    /// edge.
    private static func offsetAtFoot(contentHeight: CGFloat) -> CGFloat {
        contentHeight + insetBottom - (container + insetTop + insetBottom)
    }

    @Test func theFootIsZeroAwayFromTheFoot() {
        // **The term that is easy to miss.** Without `insetTop` this reads
        // 116, the height of the navigation bar, which is past
        // `AskScrollFollow.followWithin`, so on every thread long enough to
        // scroll the follow would never engage and the pill would never leave.
        let metrics = AskThreadGeometry(
            contentHeight: 713,
            containerHeight: Self.container,
            insetTop: Self.insetTop,
            offset: Self.offsetAtFoot(contentHeight: 713)
        )
        #expect(metrics.distanceFromContentFoot == 0)
    }

    @Test func aThreadAtRestIsAsFarFromItsFootAsItOverflows() {
        // At rest the offset is `-insetTop`, not zero: the content starts
        // below the bar. What is left below the bottom edge is everything the
        // screen cannot hold.
        let content: CGFloat = 1039
        let metrics = AskThreadGeometry(
            contentHeight: content,
            containerHeight: Self.container,
            insetTop: Self.insetTop,
            offset: -Self.insetTop
        )
        #expect(metrics.distanceFromContentFoot == content - Self.container)
    }

    @Test func aDecreasedOffsetWithEverythingElseHeldStillReadsAsTheReader() {
        // What clears `AskScrollFollow.isAtFoot`. Growth changes the content,
        // a keyboard changes the container and a resize its width as well, a
        // bar resolving its height changes the inset, and each of those moves
        // the reader's distance from the foot without the reader having moved
        // at all. It isn't proof of a hand, though: the thread's own scroll
        // has been traced taking the reader's shape, which is what
        // `AskScrollFollow.fellShort(since:)` answers.
        let resting = AskThreadGeometry(
            contentHeight: 1000, containerHeight: Self.container,
            insetTop: Self.insetTop, offset: 200
        )

        var dragged = resting
        dragged.offset = 120
        #expect(dragged.readerScrolledUp(from: resting))

        var scrolledBackDown = resting
        scrolledBackDown.offset = 260
        #expect(!scrolledBackDown.readerScrolledUp(from: resting))

        var grown = resting
        grown.contentHeight = 1900
        #expect(!grown.readerScrolledUp(from: resting))

        // The shapes that move the offset for the reader. A keyboard rising
        // takes the container and the offset together; a bar resolving its
        // height takes the inset and the offset together. Both look like a
        // drag to anything that reads the offset alone.
        var keyboard = resting
        keyboard.containerHeight = Self.container - 336
        keyboard.offset = 120
        #expect(!keyboard.readerScrolledUp(from: resting))

        var barResolved = resting
        barResolved.insetTop = 0
        barResolved.offset = 84
        #expect(!barResolved.readerScrolledUp(from: resting))

        // A resize, which the width alone is enough to say.
        var turned = resting
        turned.containerWidth = 750
        turned.offset = 120
        #expect(!turned.readerScrolledUp(from: resting))
    }
}

#endif
