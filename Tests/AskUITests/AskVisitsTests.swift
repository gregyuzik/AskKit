#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Testing

@testable import AskUI

/// The reader's visits to Ask, which the starter's tip waits for the second
/// of: what begins one, and what is the same one going on.
@Suite(.timeLimit(.minutes(1))) struct AskVisitsTests {
    private let start = ContinuousClock.now
    private let screen = UUID()

    @Test func theFirstScreenToAppearBeginsAVisit() {
        var visits = AskVisits()
        let began = visits.screenAppeared(screen, at: start)
        #expect(began)
    }

    /// A tab switch away and back, whether the tab kept the screen or built
    /// it again.
    @Test func aScreenThatComesBackAfterItLeftBeginsAnother() {
        var visits = AskVisits()
        _ = visits.screenAppeared(screen, at: start)
        visits.screenDisappeared(screen, underPushedItem: false, at: start + .seconds(5))
        let keptBegan = visits.screenAppeared(screen, at: start + .seconds(20))
        #expect(keptBegan)

        visits.screenDisappeared(screen, underPushedItem: false, at: start + .seconds(25))
        let builtAgainBegan = visits.screenAppeared(UUID(), at: start + .seconds(40))
        #expect(builtAgainBegan)
    }

    /// A host whose layout changes builds the screen again, and the new one
    /// may appear before the old one goes.
    @Test func aScreenBuiltAgainWhileTheOldOneIsUpIsTheSameVisit() {
        var visits = AskVisits()
        let rebuilt = UUID()
        _ = visits.screenAppeared(screen, at: start)
        let rebuiltBegan = visits.screenAppeared(rebuilt, at: start + .seconds(5))
        #expect(!rebuiltBegan)
        visits.screenDisappeared(screen, underPushedItem: false, at: start + .seconds(5))

        // The rebuilt one is the screen now: its going ends the visit.
        visits.screenDisappeared(rebuilt, underPushedItem: false, at: start + .seconds(9))
        let nextBegan = visits.screenAppeared(UUID(), at: start + .seconds(30))
        #expect(nextBegan)
    }

    /// Or after it has gone, inside `AskVisits.rebuild`.
    @Test func aScreenBuiltAgainJustAfterTheOldOneWentIsTheSameVisit() {
        var visits = AskVisits()
        let left = start + .seconds(5)
        _ = visits.screenAppeared(screen, at: start)
        visits.screenDisappeared(screen, underPushedItem: false, at: left)
        let began = visits.screenAppeared(UUID(), at: left + AskVisits.rebuild - .milliseconds(1))
        #expect(!began)
    }

    @Test func aScreenThatComesBackOnceTheRebuildIsPastBeginsAnother() {
        var visits = AskVisits()
        let left = start + .seconds(5)
        _ = visits.screenAppeared(screen, at: start)
        visits.screenDisappeared(screen, underPushedItem: false, at: left)
        let began = visits.screenAppeared(UUID(), at: left + AskVisits.rebuild)
        #expect(began)
    }

    /// The reader never left Ask: they opened an item from it and came back,
    /// however long they read it.
    @Test func aScreenBackFromUnderAPushedItemIsTheSameVisit() {
        var visits = AskVisits()
        _ = visits.screenAppeared(screen, at: start)
        visits.screenDisappeared(screen, underPushedItem: true, at: start + .seconds(5))
        let poppedBegan = visits.screenAppeared(screen, at: start + .seconds(600))
        #expect(!poppedBegan)

        // And the visit ends as that screen next leaves, as any does.
        visits.screenDisappeared(screen, underPushedItem: false, at: start + .seconds(610))
        let nextBegan = visits.screenAppeared(screen, at: start + .seconds(700))
        #expect(nextBegan)
    }

    /// A push covers one screen, not the reader's whole stay: a screen that
    /// was never under it is judged as any other.
    @Test func anotherScreenAppearingWhileOneIsCoveredBeginsAVisit() {
        var visits = AskVisits()
        _ = visits.screenAppeared(screen, at: start)
        visits.screenDisappeared(screen, underPushedItem: true, at: start + .seconds(5))
        let began = visits.screenAppeared(UUID(), at: start + .seconds(600))
        #expect(began)
    }

    /// A second window on the Mac or iPad, and iPhone Duo's Split View.
    @Test func aSecondWindowsScreenIsTheSameVisitWhileTheFirstIsUp() {
        var visits = AskVisits()
        let second = UUID()
        _ = visits.screenAppeared(screen, at: start)
        let openedBegan = visits.screenAppeared(second, at: start + .seconds(60))
        #expect(!openedBegan)
        visits.screenDisappeared(second, underPushedItem: false, at: start + .seconds(90))
        let reopenedBegan = visits.screenAppeared(second, at: start + .seconds(300))
        #expect(!reopenedBegan)
    }

    /// The visit ends as the last screen up leaves, and the rebuild is
    /// measured from then.
    @Test func theVisitEndsAsTheLastScreenLeaves() {
        var visits = AskVisits()
        let second = UUID()
        let lastLeft = start + .seconds(30)
        _ = visits.screenAppeared(screen, at: start)
        _ = visits.screenAppeared(second, at: start + .seconds(1))
        visits.screenDisappeared(screen, underPushedItem: false, at: start + .seconds(2))
        visits.screenDisappeared(second, underPushedItem: false, at: lastLeft)
        let began = visits.screenAppeared(UUID(), at: lastLeft + .milliseconds(10))
        #expect(!began)
    }

    /// SwiftUI may call `onAppear` again for a view that never went.
    @Test func aScreenAppearingTwiceBeginsOneVisit() {
        var visits = AskVisits()
        let began = visits.screenAppeared(screen, at: start)
        let beganAgain = visits.screenAppeared(screen, at: start + .seconds(60))
        #expect(began)
        #expect(!beganAgain)
    }

    /// A disappearance with no appearance before it is no visit ending, so
    /// the first screen after it isn't taken for a rebuild.
    @Test func aScreenNeverSeenLeavingChangesNothing() {
        var visits = AskVisits()
        visits.screenDisappeared(UUID(), underPushedItem: false, at: start)
        #expect(visits == AskVisits())
        let began = visits.screenAppeared(screen, at: start)
        #expect(began)
    }
}

#endif
