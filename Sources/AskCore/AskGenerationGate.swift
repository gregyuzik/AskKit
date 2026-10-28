import Foundation
import os
import Synchronization

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
        logger.error("generation held the gate past \(deadline.components.seconds, privacy: .public)s — presumed wedged; releasing")
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
    /// The generation gate moves on once the body has returned and so has
    /// every generation it started in a task of its own
    /// (`AskGenerationProducers`): an `AppleAskSession` stream the body let
    /// go of holds it until the task running `streamResponse` has returned.
    ///
    /// - Parameters:
    ///   - isolation: the caller's actor, which the body runs on.
    ///   - gate: the generation gate to wait at: `shared`, unless the caller
    ///     has one of its own.
    ///   - deadline: how long the body, and the generations it started, may
    ///     hold the generation gate before the holder is presumed wedged and
    ///     the next caller is let in. Neither is stopped, but the call returns
    ///     by then once the body has.
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
        // The holder's time starts here, for the watchdog and for the wait on
        // its producers alike.
        let acquired = ContinuousClock.now
        // Detached, so the watchdog takes neither the caller's actor nor its
        // priority: it only sleeps, then tells the generation gate this
        // holder's time is up.
        let watchdog = Task.detached(priority: .utility) {
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled else { return }
            await gate.expire(owner: id, after: deadline)
        }
        let producers = AskGenerationProducers()
        // However the body ends, in this order: the generations it started
        // return, the generation gate moves on, then the watchdog stands
        // down. One `defer` rather than a release on each path: Swift 6.4
        // lets a `defer` await (SE-0493).
        defer {
            await producers.settle(by: acquired + deadline)
            await gate.release(owner: id)
            watchdog.cancel()
        }
        return try await AskGenerationProducers.$current.withValue(producers) { try await body() }
    }
}

/// The generations a holder's body started that run in a task of their own,
/// which the generation gate waits for before it lets the next caller in.
///
/// **A reader that stops reading doesn't stop the generation.** A streamed
/// generation runs in a task of its own (`AppleAskSession`'s `stream`), which
/// letting the stream go only cancels. A turn that is stopped, or abandoned
/// at its deadline, ends its loop at once, and its body returns while
/// `streamResponse` is still unwinding. Released then, the generation gate
/// would let the next generation in beside it: the overlap it exists to
/// prevent. So the session hands that task to the holder it was started
/// under (`current`), and `AskGenerationGate.run` waits for it to return,
/// for no longer than the holder's deadline.
nonisolated final class AskGenerationProducers: Sendable {
    /// The producers of the holder whose body this task runs in, or nil
    /// outside one: a Private Cloud Compute generation, and a stream read
    /// outside the generation gate, hand their task to nobody.
    @TaskLocal static var current: AskGenerationProducers?

    private let tasks = Mutex<[Task<Void, Never>]>([])

    /// Hold the generation gate until `task` has returned too.
    func adopt(_ task: Task<Void, Never>) {
        tasks.withLock { $0.append(task) }
    }

    /// Wait until every task adopted has returned, or `deadline` passes.
    ///
    /// **Deaf to the caller's cancellation**, since a cancelled caller is the
    /// case it exists for: a stopped turn's generation is cancelled, not
    /// awaited. So the wait runs in a task of its own, which inherits no
    /// cancellation, and awaiting that task's value doesn't answer to it
    /// either. `AskDeadline` bounds it, because a producer stuck on a hung
    /// framework call never returns.
    func settle(by deadline: ContinuousClock.Instant) async {
        let pending = tasks.withLock { tasks in
            defer { tasks = [] }
            return tasks
        }
        guard !pending.isEmpty else { return }
        let wait = Task {
            _ = try? await AskDeadline.run(until: deadline) {
                for task in pending { await task.value }
            }
        }
        await wait.value
    }
}
