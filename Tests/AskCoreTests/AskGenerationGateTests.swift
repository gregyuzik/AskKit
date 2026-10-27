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
