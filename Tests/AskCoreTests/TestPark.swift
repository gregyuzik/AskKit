import Synchronization

/// Where a fake's call waits until its test lets it go: a session's held
/// generation, a store fake's parked reset or stop, a domain's parked
/// perform.
///
/// **Deaf to cancellation**, as the network call or the long host work it
/// stands in for is: a task cancelled while it waits here goes on waiting, so
/// a test can change the chat while the call runs.
///
/// **And it can't lose its let-go.** A continuation stored in one lock after
/// its flag was read in another can miss a let-go that falls between the
/// two, or that comes before the call arrives, as one does when the test's
/// wait for the park gives up under load; nothing resumes it then, and the
/// run it is in never ends. Here the flag is read and the waiter stored under
/// the park's own lock, and a let-go is taken under it too.
///
/// Compiled into AskCoreTests and, through a link, AskUITests: edit this
/// file, never the link.
nonisolated final class TestPark: Sendable {
    private struct State {
        var waiting: [CheckedContinuation<Void, Never>] = []
        var letGoEarly = false
    }

    private let state = Mutex(State())

    /// How many calls are waiting here.
    var waiters: Int { state.withLock { $0.waiting.count } }

    /// Whether a call is waiting here.
    var isWaiting: Bool { waiters > 0 }

    /// Wait here while `shouldWait` says to, read under the park's lock, or
    /// go straight on past a let-go that came before any call waited.
    func wait(if shouldWait: () -> Bool = { true }) async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let goes = state.withLock { state -> Bool in
                if state.letGoEarly {
                    state.letGoEarly = false
                    return true
                }
                guard shouldWait() else { return true }
                state.waiting.append(waiter)
                return false
            }
            if goes { waiter.resume() }
        }
    }

    /// Let every waiting call go. With none waiting, the next call to arrive
    /// goes straight on, for a park whose flag stays set.
    func letGo() {
        let waiting = state.withLock { state in
            if state.waiting.isEmpty { state.letGoEarly = true }
            defer { state.waiting = [] }
            return state.waiting
        }
        for waiter in waiting { waiter.resume() }
    }

    /// Let every waiting call go, and clear the flag `wait(if:)` reads in
    /// the same lock, so a call that read it set is already waiting and goes,
    /// and one that reads it after finds it clear. Nothing is kept for later:
    /// a flag set again parks the next call.
    func letGo(disarming disarm: () -> Void) {
        let waiting = state.withLock { state in
            disarm()
            defer { state.waiting = [] }
            return state.waiting
        }
        for waiter in waiting { waiter.resume() }
    }
}
