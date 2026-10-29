import Foundation
import Synchronization
import Testing

@testable import AskCore

@Suite(.timeLimit(.minutes(1))) struct AskGenerationGateTests {

    @Test func oneCallerRunsStraightThrough() async throws {
        let gate = AskGenerationGate()
        let value = try await AskGenerationGate.run(gate: gate) { 42 }
        #expect(value == 42)
    }

    @Test func atMostOneBodyRunsAtATime() async throws {
        let gate = AskGenerationGate()
        let concurrent = Mutex(0)
        let peak = Mutex(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try? await AskGenerationGate.run(gate: gate) {
                        let now = concurrent.withLock { $0 += 1; return $0 }
                        peak.withLock { $0 = max($0, now) }
                        try? await Task.sleep(for: .milliseconds(10))
                        concurrent.withLock { $0 -= 1 }
                    }
                }
            }
        }
        #expect(peak.withLock { $0 } == 1)
    }

    /// Spin until `condition` holds, or give up. Bounded, and it yields.
    private func spin(
        _ what: String, until condition: @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<4_000 {
            if await condition() { return }
            await Task.yield()
            try await Task.sleep(for: .microseconds(500))
        }
        Issue.record("timed out waiting for \(what)")
    }

    /// Wait until the generation gate's queue reaches `depth`, or give up.
    ///
    /// **Polling a real property, not sleeping a guessed margin.** These tests
    /// establish ordering, and a fixed `Task.sleep` between waiters is a guess
    /// at how long a task takes to queue. A margin that holds on an idle Mac
    /// is exactly the thing that stops holding under load, such as the push
    /// gate's builds running on the same machine.
    private func waitForQueue(_ gate: AskGenerationGate, depth: Int) async throws {
        try await spin("the gate's queue to reach depth \(depth)") {
            await gate.queueDepth >= depth
        }
    }

    @Test func waitersAreServedFirstInFirstOut() async throws {
        let gate = AskGenerationGate()
        let order = Mutex<[Int]>([])
        let release = Mutex(false)
        let holding = Mutex(false)
        // Holds until this test says so, and says when it has the generation
        // gate: the two facts a sleep would be guessing at.
        let holder = Task {
            try await AskGenerationGate.run(gate: gate) {
                holding.withLock { $0 = true }
                while !release.withLock({ $0 }) {
                    try await Task.sleep(for: .microseconds(500))
                }
            }
        }
        try await spin("the holder to take the gate") { holding.withLock { $0 } }

        var queued: [Task<Void, Never>] = []
        for index in 0..<3 {
            queued.append(Task {
                try? await AskGenerationGate.run(gate: gate) {
                    order.withLock { $0.append(index) }
                }
            })
            // Each waiter is IN the queue before the next is spawned, which is
            // the property a sleep between them would be guessing at.
            try await waitForQueue(gate, depth: index + 1)
        }

        release.withLock { $0 = true }
        try await holder.value
        for task in queued { await task.value }
        #expect(order.withLock { $0 } == [0, 1, 2])
    }

    @Test func aCancelledWaiterLeavesTheQueueRatherThanBlocking() async throws {
        let gate = AskGenerationGate()
        let release = Mutex(false)
        let holding = Mutex(false)
        let holder = Task {
            try await AskGenerationGate.run(gate: gate) {
                holding.withLock { $0 = true }
                while !release.withLock({ $0 }) {
                    try await Task.sleep(for: .microseconds(500))
                }
            }
        }
        try await spin("the holder to take the gate") { holding.withLock { $0 } }
        let waiter = Task {
            try await AskGenerationGate.run(gate: gate) { 1 }
        }
        // Cancelled once it is really queued, not once a guessed time has
        // passed.
        try await waitForQueue(gate, depth: 1)
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        // Released BEFORE the await, not in a `defer` — a `defer` runs after
        // the function body, so the holder would be waiting on a flag set only
        // once the wait it is blocking had already returned.
        release.withLock { $0 = true }
        try await holder.value
    }

    @Test func aBodyThatThrowsStillReleasesTheGate() async throws {
        let gate = AskGenerationGate()
        _ = try? await AskGenerationGate.run(gate: gate) { throw AskError.refused }
        let value = try await AskGenerationGate.run(gate: gate) { "after" }
        #expect(value == "after")
    }

    @Test func aWedgedHolderIsMovedPast() async throws {
        // A session can hang forever mid-request; the wedged task stays
        // suspended on its own call, but every successor proceeds.
        let gate = AskGenerationGate()
        let wedged = Task {
            try? await AskGenerationGate.run(gate: gate, deadline: .milliseconds(50)) {
                try? await Task.sleep(for: .seconds(30))
            }
        }
        try await Task.sleep(for: .milliseconds(120))
        let value = try await AskGenerationGate.run(gate: gate) { "through" }
        #expect(value == "through")
        wedged.cancel()
    }

    // MARK: - Where a wedged holder is logged

    /// The line a gate whose own subsystem is `com.example.gate` writes for
    /// a holder that never returns, run under `logSubsystem` or, for nil,
    /// under none, as the public `run` runs one, once its 50 ms are up.
    private func wedgedHolderLines(callerNamed logSubsystem: String?) async throws -> [GateTestWedgeLines.Line] {
        let lines = GateTestWedgeLines()
        let gate = AskGenerationGate(logSubsystem: "com.example.gate", logWedge: lines.write)
        let hold = GateTestHold()
        let holder = Task {
            if let logSubsystem {
                try await AskGenerationGate.run(
                    gate: gate, deadline: .milliseconds(50), logSubsystem: logSubsystem
                ) { await hold.hold() }
            } else {
                try await AskGenerationGate.run(gate: gate, deadline: .milliseconds(50)) { await hold.hold() }
            }
        }
        try await spin("the gate to log the wedged holder") { !lines.written.isEmpty }
        hold.release()
        try await holder.value
        return lines.written
    }

    @Test func aWedgedHolderIsLoggedUnderTheSubsystemItsCallerNamed() async throws {
        // A seam's generation, at the process's one gate: its line goes where
        // the seam's own lines go, not where the gate's do.
        let lines = try await wedgedHolderLines(callerNamed: "com.example.brand")
        #expect(lines == [.init(subsystem: "com.example.brand", deadline: .milliseconds(50))])
    }

    @Test func aWedgedHolderWhoseCallerNamedNoSubsystemIsLoggedUnderTheGates() async throws {
        // A host's own generation through the public `run`, which names no
        // subsystem.
        let lines = try await wedgedHolderLines(callerNamed: nil)
        #expect(lines == [.init(subsystem: "com.example.gate", deadline: .milliseconds(50))])
    }

    // MARK: - A holder's producers

    /// A stopped turn's generation, still unwinding: the reader has let the
    /// stream go, and the task that runs `streamResponse` hasn't returned.
    @Test func aStoppedHoldersProducerKeepsTheNextCallerWaitingUntilItReturns() async throws {
        let gate = AskGenerationGate()
        let unwinding = GateTestHold()
        let bodyReturned = Mutex(false)
        let order = Mutex<[String]>([])
        let holder = Task {
            try await AskGenerationGate.run(gate: gate) {
                // The task a session's stream runs its generation in, deaf to
                // the cancellation that stops its reader.
                let producer = Task {
                    await unwinding.hold()
                    order.withLock { $0.append("producer returned") }
                }
                AskGenerationProducers.current?.adopt(producer)
                // The reader, which stops when its task is cancelled, as the
                // engine's loop does when a turn is stopped or abandoned at
                // its deadline.
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
                bodyReturned.withLock { $0 = true }
            }
        }
        try await spin("the producer to start") { unwinding.hasArrived }
        let next = Task {
            try await AskGenerationGate.run(gate: gate) { order.withLock { $0.append("next entered") } }
        }
        try await waitForQueue(gate, depth: 1)
        holder.cancel()
        try await spin("the holder's body to return") { bodyReturned.withLock { $0 } }
        // A release once the body returned would let the next caller in
        // within a few actor hops: this is room for one that must not happen.
        try await Task.sleep(for: .milliseconds(200))
        #expect(order.withLock { $0 }.isEmpty)
        unwinding.release()
        try await next.value
        try await holder.value
        #expect(order.withLock { $0 } == ["producer returned", "next entered"])
    }

    @Test func aProducerThatNeverReturnsIsMovedPastAtTheHoldersDeadline() async throws {
        // A producer stuck on a hung framework call holds neither the next
        // caller nor its own past the deadline.
        let gate = AskGenerationGate()
        let wedged = GateTestHold()
        let holder = Task {
            try await AskGenerationGate.run(gate: gate, deadline: .milliseconds(100)) {
                let producer = Task { await wedged.hold() }
                AskGenerationProducers.current?.adopt(producer)
            }
        }
        try await spin("the producer to start") { wedged.hasArrived }
        let value = try await AskGenerationGate.run(gate: gate) { "through" }
        #expect(value == "through")
        try await holder.value
        #expect(!wedged.hasLeft)
        wedged.release()
    }

    // MARK: - One gate per process

    /// The public `run` takes no gate: it waits at `shared`, the process's
    /// one, where `AppleModelSeam` waits too, so a host's own generation
    /// never runs beside one there.
    @Test func thePublicRunWaitsAtTheSharedGate() async throws {
        let held = GateTestHold()
        let holder = Task { try await AskGenerationGate.run(gate: .shared) { await held.hold() } }
        try await spin("the holder to hold the shared gate") { held.hasArrived }
        let entered = Mutex(false)
        let host = Task { try await AskGenerationGate.run { entered.withLock { $0 = true } } }
        try await spin("a caller to queue at the shared gate") { await AskGenerationGate.shared.queueDepth >= 1 }
        // Room for an entry that must not happen: at a gate of its own, the
        // host's body would have run by now.
        try await Task.sleep(for: .milliseconds(200))
        #expect(!entered.withLock { $0 })
        held.release()
        try await host.value
        try await holder.value
        #expect(entered.withLock { $0 })
    }

    @Test func theQueueEmptiesWhenEveryoneHasRun() async throws {
        let gate = AskGenerationGate()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { try? await AskGenerationGate.run(gate: gate) {} }
            }
        }
        #expect(await gate.queueDepth == 0)
    }
}

/// A point a test holds a task at until it says so, deaf to cancellation, as
/// a framework call that is still unwinding is.
nonisolated final class GateTestHold: Sendable {
    private struct State {
        var arrived = false
        var left = false
        var released = false
        var held: CheckedContinuation<Void, Never>?
    }
    private let state = Mutex(State())

    /// A task has reached `hold()`.
    var hasArrived: Bool { state.withLock { $0.arrived } }
    /// A task has gone on past `hold()`.
    var hasLeft: Bool { state.withLock { $0.left } }

    /// Wait here until `release()`, whatever happens to the task meanwhile.
    func hold() async {
        await withCheckedContinuation { continuation in
            let released = state.withLock { state in
                state.arrived = true
                if !state.released { state.held = continuation }
                return state.released
            }
            if released { continuation.resume() }
        }
        state.withLock { $0.left = true }
    }

    func release() {
        let held = state.withLock { state in
            state.released = true
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }
}

/// The lines a generation gate wrote for holders presumed wedged, recorded
/// rather than logged: `os.Logger` can't say which subsystem it writes
/// under, and reading the log store back stalls the test process.
nonisolated final class GateTestWedgeLines: Sendable {
    struct Line: Equatable {
        let subsystem: String
        let deadline: Duration
    }
    private let lines = Mutex<[Line]>([])

    var written: [Line] { lines.withLock { $0 } }

    /// The gate's `logWedge`.
    func write(_ subsystem: String, _ deadline: Duration) {
        lines.withLock { $0.append(Line(subsystem: subsystem, deadline: deadline)) }
    }
}
