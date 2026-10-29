import Foundation
import Synchronization
import Testing

@testable import AskCore

@Suite(.timeLimit(.minutes(1))) struct AskDeadlineTests {

    @Test func returnsTheValueWhenTheWorkWins() async throws {
        let value = try await AskDeadline.run(.seconds(5)) { "done" }
        #expect(value == "done")
    }

    @Test func returnsNilWhenTheDeadlineWins() async throws {
        let value = try await AskDeadline.run(.milliseconds(50)) { () -> String in
            try? await Task.sleep(for: .seconds(5))
            return "too late"
        }
        #expect(value == nil)
    }

    @Test func aDeadlineNoTimerCanHoldIsNoDeadline() async throws {
        // A sleep traps on a wait this long; the race sets no timer instead,
        // and the work it was given wins.
        for duration in [Duration.seconds(Int.max), .seconds(Int64(Int32.max) + 1)] {
            let value = try await AskDeadline.run(duration) { () -> String in
                try? await Task.sleep(for: .milliseconds(20))
                return "done"
            }
            #expect(value == "done", "\(duration)")
            #expect(AskDeadline.timerWait(duration) == nil)
        }
    }

    @Test func theLongestWaitSetsATimer() {
        // The edge of what a timer is set for, from either side.
        #expect(AskDeadline.timerWait(AskDeadline.longestWait) == AskDeadline.longestWait)
        #expect(AskDeadline.timerWait(AskDeadline.longestWait + .nanoseconds(1)) == nil)
        #expect(AskDeadline.timerWait(.nanoseconds(1)) == .nanoseconds(1))
    }

    @Test func aDeadlineAlreadyPastGivesUp() async throws {
        let value = try await AskDeadline.run(.seconds(-5)) { () -> String in
            try? await Task.sleep(for: .seconds(5))
            return "too late"
        }
        #expect(value == nil)
        #expect(AskDeadline.timerWait(.seconds(-5)) == .zero)
        #expect(AskDeadline.timerWait(.zero) == .zero)
    }

    @Test func rethrowsWhatTheOperationThrew() async {
        await #expect(throws: AskError.self) {
            _ = try await AskDeadline.run(.seconds(5)) { () -> String in
                throw AskError.refused
            }
        }
    }

    @Test func aThrownErrorArrivesUnchanged() async throws {
        do {
            _ = try await AskDeadline.run(.seconds(5)) { () -> String in
                throw AskError.quotaReached(resetDate: nil)
            }
            Issue.record("expected a throw")
        } catch let error as AskError {
            #expect(error == .quotaReached(resetDate: nil))
        }
    }

    @Test func aCancelledCallerThrowsCancellationNotAnExpiry() async throws {
        // The distinction is deliberate: nil is what a caller degrades on, and
        // the reader leaving is not the same event as the ceiling.
        let task = Task { () -> String? in
            try await AskDeadline.run(.seconds(10)) { () -> String in
                try? await Task.sleep(for: .seconds(10))
                return "never"
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func aSubSecondDurationIsHonoured() async throws {
        let value = try await AskDeadline.run(.milliseconds(50)) { () -> Int in
            try? await Task.sleep(for: .seconds(5))
            return 1
        }
        #expect(value == nil)
    }

    @Test func theWorkIsCancelledWhenTheDeadlineWins() async throws {
        // The expiry ABANDONS: it cancels and returns without waiting. What is
        // pinned here is that the cancellation is delivered at all.
        //
        // Awaited through a continuation the abandoned body resumes, rather
        // than slept past: a fixed margin is a guess about how long a
        // cancellation takes to be delivered, and a busy machine, such as one
        // running the push gate's builds, outlasts the guess.
        let cancelled = Mutex(false)
        let delivered = Mutex<CheckedContinuation<Void, Never>?>(nil)
        async let signal: Void = withCheckedContinuation { continuation in
            delivered.withLock { $0 = continuation }
        }

        _ = try await AskDeadline.run(.milliseconds(50)) { () -> String in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                cancelled.withLock { $0 = true }
                // Resume exactly once: the body is abandoned, not awaited, so
                // nothing else will.
                delivered.withLock { taken in
                    taken?.resume()
                    taken = nil
                }
            }
            return "x"
        }
        await signal
        #expect(cancelled.withLock { $0 })
    }

    // MARK: - What makes this a race and not a task group
    //
    // Both cases pin a property the type exists FOR and that no other test
    // here checks: an expiry abandons rather than awaits, and the work runs
    // off the caller's actor.

    @Test func expiryDoesNotWaitForWorkThatCannotNoticeCancellation() async throws {
        // A task-group race awaits every child before it returns, so it gives up
        // only as fast as the work it bounds chooses to notice `cancelAll()` —
        // and the work under these budgets largely cannot. The work here waits
        // on a continuation, which no cancellation reaches, until the test lets
        // it go.
        //
        // **Asserted as an order, not a duration.** Timing the wall clock
        // around a blocking `usleep` would hold a thread of the cooperative
        // pool, which the deadline's own timer needs, so a small runner could
        // fail it with nothing wrong.
        let work = Latch()
        let finished = Mutex(false)
        // A deadline that waited for the work would wait for ever: this lets
        // the work go in the end, so a regression fails instead of hanging.
        let backstop = Task {
            try? await Task.sleep(for: .seconds(30))
            work.open()
        }
        defer { backstop.cancel() }
        let value = try await AskDeadline.run(.milliseconds(100)) { () async throws -> Int in
            await work.wait()
            finished.withLock { $0 = true }
            return 7
        }
        let workFinishedFirst = finished.withLock { $0 }
        work.open()
        #expect(value == nil)
        #expect(!workFinishedFirst, "the deadline waited on work that cannot be cancelled")
    }

    @MainActor
    @Test func theWorkRunsOffTheCallersActorEvenOnMain() async throws {
        // A turn's deadline is taken out from MainActor-isolated code, and the
        // work under it is a model round trip. Unstructured `Task {}` inherits
        // its enclosing context, so this is pinned rather than assumed: that
        // work must not land on the main thread. `pthread_main_np()`, because
        // `Thread.isMainThread` is banned from async contexts.
        let ranOffMain = try await AskDeadline.run(.seconds(5)) { pthread_main_np() == 0 }
        #expect(ranOffMain == true)
    }
}

/// Something a task waits at until it is opened: before the wait, during it,
/// or after, and as often as anyone likes.
///
/// A continuation behind a lock, so no cancellation reaches the wait. That is
/// the point: it stands in for work that cannot notice being cancelled.
private nonisolated final class Latch: Sendable {
    private let state = Mutex<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

    func wait() async {
        await withCheckedContinuation { continuation in
            let openAlready = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.waiter = continuation
                return false
            }
            if openAlready { continuation.resume() }
        }
    }

    func open() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isOpen = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }
}
