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

    /// Run `operation`, giving up after `seconds`.
    ///
    /// A deadline of zero or less, `-infinity` included, sets its timer for no
    /// time. One that is no number (`nan`), `infinity`, or further off than a
    /// timer can count (past about 68 years) sets no timer, and the operation
    /// runs as long as it takes.
    ///
    /// - Returns: the operation's value, or `nil` when the deadline won.
    /// - Throws: whatever `operation` throws, or `CancellationError` when the
    ///   *caller's* task was cancelled, so a caller can tell its own
    ///   cancellation from a deadline that passed.
    public static func run<T: Sendable>(
        seconds: TimeInterval,
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
            // No timer for a deadline `Duration` can't hold: it traps on one.
            guard let wait = timerWait(seconds) else { return }
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
    /// any budget and well inside what a sleep can count.
    static let longestWait: TimeInterval = Double(Int32.max)

    /// The timer's wait for `seconds`: none for zero or less, and no timer at
    /// all for a value that is no number or past `longestWait`.
    static func timerWait(_ seconds: TimeInterval) -> Duration? {
        guard !seconds.isNaN else { return nil }
        guard seconds > 0 else { return .zero }
        guard seconds <= longestWait else { return nil }
        return .seconds(seconds)
    }

    /// The same race, in `Duration`, which `AskDomain.turnDeadline` speaks.
    public static func run<T: Sendable>(
        _ duration: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
        return try await run(seconds: seconds, operation)
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
