import Foundation
import os

/// The generation gate: on-device generation, serialized across the process,
/// first in, first out.
///
/// The on-device runtime is one resource per process, and it isn't robust to
/// overlapping generation: two `respond` or `streamResponse` calls in flight
/// at once race inside the framework and can trip an internal trap (measured
/// crashing on macOS 26.5). A host generates from more than one place, such
/// as an Ask turn's streamed answer, a background summary or a classifier, so
/// at most one on-device generation runs at a time, in the order they asked,
/// and everything else waits.
///
/// **Private Cloud Compute passes straight through.** It runs on Apple's
/// servers and contends for none of the on-device runtime, so the seam runs
/// its generations without the generation gate
/// (`AskModelSeam.withGeneration(onDevice:_:)`). Serializing them would only
/// make two questions queue behind each other for nothing.
///
/// Two liveness guards, because a session can hang forever mid-request (after
/// an OS suspend, for one). A queued waiter whose task is cancelled leaves the
/// queue and throws `CancellationError` rather than waiting behind a hung
/// holder. A holder that runs past `holderDeadline` is presumed wedged, and
/// the generation gate moves on without it: the wedged task stays suspended
/// on its own call, but every caller after it proceeds.
///
/// Not re-entrant: a `run` body that calls `run` waits behind itself until
/// its own deadline presumes it wedged.
public actor AskGenerationGate {
    /// The generation gate the process shares: the default for `run` and for
    /// `AppleModelSeam`. A host's own on-device generations go through it
    /// too.
    ///
    /// Readable from any actor, and as a default argument on another one,
    /// such as `AppleModelSeam`'s initializer. That holds without the
    /// `nonisolated`: the package's main-actor default isolation reaches a
    /// struct's static members but never an actor's, so the spelling only
    /// states what is already true.
    nonisolated public static let shared = AskGenerationGate()

    /// How long a holder may keep the generation gate before it is presumed
    /// wedged and the next caller is let in: 90 s, far above any legitimate
    /// generation. `run`'s default.
    public static let holderDeadline: Duration = .seconds(90)

    private var currentOwner: UInt64?
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID: UInt64 = 0
    private let logger: Logger

    /// A generation gate of its own, which serializes only what runs through
    /// it. Almost every caller wants `shared`, which logs under the app's
    /// bundle identifier.
    ///
    /// - Parameter logSubsystem: the subsystem a wedged holder is logged
    ///   under: `AskBrand.logSubsystem`. Nil logs under the app's bundle
    ///   identifier.
    public init(logSubsystem: String? = nil) {
        logger = Logger(subsystem: AskBrand.subsystem(logSubsystem), category: "gate")
    }

    private func acquire() async throws -> UInt64 {
        nextID &+= 1
        let id = nextID
        if currentOwner == nil {
            currentOwner = id
            return id
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
        return id
    }

    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release(owner id: UInt64) {
        guard currentOwner == id else { return }
        admitNext()
    }

    private func expire(owner id: UInt64, after deadline: Duration) {
        guard currentOwner == id else { return }
        logger.fault("generation held the gate past \(deadline.components.seconds, privacy: .public)s — presumed wedged; releasing")
        admitNext()
    }

    /// Let the longest waiter in, or leave the generation gate free when
    /// nobody waits.
    private func admitNext() {
        if waiters.isEmpty {
            currentOwner = nil
        } else {
            let next = waiters.removeFirst()
            currentOwner = next.id
            next.continuation.resume()
        }
    }

    /// How many callers are waiting behind the holder. Test-facing: the FIFO
    /// order is the property worth pinning, and it is otherwise invisible.
    var queueDepth: Int { waiters.count }

    /// Run `body` with exclusive access to the on-device runtime, once the
    /// callers queued before it have had their turn, and return what it
    /// returns.
    ///
    /// The body runs in the caller's isolation: the generation gate only
    /// serializes, and never moves work elsewhere.
    ///
    /// - Parameters:
    ///   - isolation: the caller's actor, which the body runs on.
    ///   - gate: the generation gate to wait at: `shared`, unless the caller
    ///     has one of its own.
    ///   - deadline: how long the body may hold the generation gate before it
    ///     is presumed wedged and the next caller is let in. The body itself
    ///     isn't stopped.
    ///   - body: the generation.
    /// - Throws: `CancellationError` when the caller's task is cancelled while
    ///   it waits, or whatever `body` throws.
    public static func run<T>(
        isolation: isolated (any Actor)? = #isolation,
        gate: AskGenerationGate = .shared,
        deadline: Duration = holderDeadline,
        _ body: () async throws -> T
    ) async throws -> T {
        let id = try await gate.acquire()
        // Detached, so the watchdog takes neither the caller's actor nor its
        // priority: it only sleeps, then tells the generation gate this
        // holder's time is up.
        let watchdog = Task.detached(priority: .utility) {
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled else { return }
            await gate.expire(owner: id, after: deadline)
        }
        // However the body ends, in this order: the generation gate moves on,
        // then the watchdog stands down. One `defer` rather than a release on
        // each path: Swift 6.4 lets a `defer` await (SE-0493).
        defer {
            await gate.release(owner: id)
            watchdog.cancel()
        }
        return try await body()
    }
}
