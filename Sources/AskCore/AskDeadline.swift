import Foundation

/// Race an async operation against a wall-clock deadline.
///
/// Swift has no built-in timeout combinator. An expiry **abandons** the
/// operation: it cancels it and returns without waiting for it to stop. The
/// work under these budgets, such as a provider trickling bytes past its idle
/// timeout or a model call that hangs, is exactly the work that can't notice
/// cancellation, and a task-group deadline can only give up as fast as its
/// children choose to.
///
/// An abandoned Private Cloud Compute generation keeps spending quota on
/// Apple's side until it finishes. That is a known cost, documented rather
/// than fixed: the alternative is a caller held past its deadline.
nonisolated public enum AskDeadline {

    /// Run `operation`, giving up after `duration`, the length of time
    /// `AskDomain.turnDeadline` speaks.
    ///
    /// A deadline of zero or less sets its timer for no time. One further off
    /// than a timer can count (past about 68 years) sets no timer, and the
    /// operation runs as long as it takes.
    ///
    /// - Returns: the operation's value, or `nil` when the deadline won.
    /// - Throws: whatever `operation` throws, or `CancellationError` when the
    ///   *caller's* task was cancelled, so a caller can tell its own
    ///   cancellation from a deadline that passed.
    public static func run<T: Sendable>(
        _ duration: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        // A one-shot relay: whichever racer reports first is the answer.
        // Only the first element is read, and a finished stream ignores every
        // later yield, so "first wins" needs no lock of its own.
        let (stream, relay) = AsyncThrowingStream<T?, any Error>.makeStream()

        let work = Task {
            do {
                relay.yield(try await operation())
                relay.finish()
            } catch {
                relay.finish(throwing: error)
            }
        }
        let timer = Task {
            // No timer for a deadline a sleep can't count: it traps on one.
            guard let wait = timerWait(duration) else { return }
            try? await Task.sleep(for: wait)
            relay.yield(nil)
            relay.finish()
        }
        defer {
            work.cancel()
            timer.cancel()
        }

        var results = stream.makeAsyncIterator()
        let first = try await results.next()
        // A cancelled caller ends the iteration rather than throwing, which
        // would otherwise read as an expiry, and `nil` is what a caller
        // degrades on. So the cancellation check comes before the value is
        // trusted, not after.
        try Task.checkCancellation()
        return first ?? nil
    }

    /// The longest wait a deadline sets a timer for: about 68 years, far past
    /// any budget and well inside what a sleep can count. A `Duration` holds
    /// far more (`.seconds(Int.max)`), and a sleep traps on what it can't count.
    static let longestWait: Duration = .seconds(Int(Int32.max))

    /// The timer's wait for `duration`: none for zero or less, and no timer at
    /// all for one past `longestWait`.
    static func timerWait(_ duration: Duration) -> Duration? {
        guard duration > .zero else { return .zero }
        guard duration <= longestWait else { return nil }
        return duration
    }

    /// The same race against an instant: what is left of a budget begun
    /// earlier, which is how `AskEngine` gives a whole turn one deadline.
    /// Nothing left, and nothing is started, since an operation begun only to
    /// be abandoned would go on running.
    static func run<T: Sendable>(
        until deadline: ContinuousClock.Instant,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let remaining = deadline - ContinuousClock().now
        guard remaining > .zero else {
            try Task.checkCancellation()
            return nil
        }
        return try await run(remaining, operation)
    }
}
