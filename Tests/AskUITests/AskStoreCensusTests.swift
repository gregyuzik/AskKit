#if os(iOS) || os(macOS) || os(visionOS)

import Testing

@testable import AskUI

/// One store per app: a second alive over the same thread is reported.
@Suite(.timeLimit(.minutes(1))) struct AskStoreCensusTests {

    @Test func theSecondStoreOverOneThreadIsReportedOnce() {
        var census = AskStoreCensus()
        let first = census.arrive("/a/ask-thread.json")
        let second = census.arrive("/a/ask-thread.json")
        let third = census.arrive("/a/ask-thread.json")
        #expect(!first && second && !third)
        census.leave("/a/ask-thread.json")
        census.leave("/a/ask-thread.json")
        #expect(census.alive["/a/ask-thread.json"] == 1)
        // Reported once for that thread: a later second store is the same
        // misuse, already in the log.
        let later = census.arrive("/a/ask-thread.json")
        #expect(!later)
    }

    @Test func storesOverTheirOwnThreadsAreNotReported() {
        var census = AskStoreCensus()
        let one = census.arrive("/a/ask-thread.json")
        let other = census.arrive("/b/ask-thread.json")
        #expect(!one && !other)
        // A second over the other thread is reported for that one too.
        let secondOverOther = census.arrive("/b/ask-thread.json")
        #expect(secondOverOther)
    }

    @Test func storesBuiltOneAfterAnotherAreNotReported() {
        var census = AskStoreCensus()
        let first = census.arrive("/a/ask-thread.json")
        census.leave("/a/ask-thread.json")
        let next = census.arrive("/a/ask-thread.json")
        #expect(!first && !next)
        census.leave("/a/ask-thread.json")
        #expect(census.alive.isEmpty)
    }
}

#endif
