import Synchronization
import Testing

/// `TestPark`, which the fakes' parks share: a let-go that comes first is
/// kept, a disarming let-go clears its flag under the park's lock and keeps
/// nothing, a cancelled waiter goes on waiting, and one let-go wakes every
/// waiter. Each waits in a task of its own and is looked at with
/// `yieldUntil`, which gives up rather than hangs, and each lets go again
/// before it ends, so a park that lost a let-go fails its test and doesn't
/// hold the run.
@Suite(.timeLimit(.minutes(1))) struct TestParkTests {
    @Test func aLetGoBeforeAnyWaitLetsTheNextCallStraightOn() async {
        let park = TestPark()
        let passed = Mutex(false)
        park.letGo()
        let waiter = Task {
            await park.wait()
            passed.withLock { $0 = true }
        }
        await yieldUntil { passed.withLock { $0 } }
        #expect(passed.withLock { $0 })
        park.letGo()
        await waiter.value
    }

    @Test func aDisarmingLetGoClearsTheFlagTheNextCallReads() async {
        let park = TestPark()
        let parks = Mutex(true)
        park.letGo(disarming: { parks.withLock { $0 = false } })
        let passed = Mutex(false)
        let waiter = Task {
            await park.wait(if: { parks.withLock { $0 } })
            passed.withLock { $0 = true }
        }
        await yieldUntil { passed.withLock { $0 } }
        #expect(passed.withLock { $0 })
        park.letGo(disarming: {})
        await waiter.value
    }

    @Test func aDisarmingLetGoKeepsNothingForAFlagSetAgain() async {
        let park = TestPark()
        let parks = Mutex(true)
        park.letGo(disarming: { parks.withLock { $0 = false } })
        parks.withLock { $0 = true }
        let waiter = Task { await park.wait(if: { parks.withLock { $0 } }) }
        await yieldUntil { park.isWaiting }
        #expect(park.isWaiting)
        park.letGo(disarming: { parks.withLock { $0 = false } })
        await waiter.value
    }

    /// Yields, not a sleep: a park that heard the cancellation would let the
    /// waiter go, and a hundred yields give it the turns to say so. Under
    /// load they may give it too few, which can pass a regression but never
    /// fail a park that works.
    @Test func aCancelledWaiterGoesOnWaiting() async {
        let park = TestPark()
        let passed = Mutex(false)
        let waiter = Task {
            await park.wait()
            passed.withLock { $0 = true }
        }
        await yieldUntil { park.isWaiting }
        waiter.cancel()
        for _ in 0..<100 { await Task.yield() }
        #expect(!passed.withLock { $0 })
        #expect(park.isWaiting)
        park.letGo()
        await waiter.value
        #expect(passed.withLock { $0 })
    }

    @Test func oneLetGoWakesEveryWaiter() async {
        let park = TestPark()
        let passed = Mutex(0)
        let waiters = (0..<2).map { _ in
            Task {
                await park.wait()
                passed.withLock { $0 += 1 }
            }
        }
        await yieldUntil { park.waiters == 2 }
        #expect(park.waiters == 2)
        park.letGo()
        await yieldUntil { passed.withLock { $0 } == 2 }
        #expect(passed.withLock { $0 } == 2)
        park.letGo()
        for waiter in waiters { await waiter.value }
    }
}
