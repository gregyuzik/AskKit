import os
import Testing

@testable import AskCore

/// The levels the default sink logs at, which decide what the log store keeps
/// and what Console shows.
///
/// Pinned here rather than read back from the process's own log store: reading
/// it (`OSLogStore(scope: .currentProcessIdentifier)`) holds every other test
/// in the process for seconds, and the suite's deadline tests then fail. Read
/// once by hand, the store holds a routing line at notice and a domain mistake
/// at fault.
@Suite(.timeLimit(.minutes(1))) struct AskEngineLogLevelTests {

    /// The routing lines, the tags a failed turn leaves among them, are
    /// notices, which the store keeps: at info level they were kept in memory
    /// only. A mistake in the domain is a fault, which Console and Xcode set
    /// apart.
    @Test func routingIsANoticeAndADomainMistakeIsAFault() {
        #expect(AskOSLogSink.routingLevel == .default)
        #expect(AskOSLogSink.domainMistakeLevel == .fault)
    }
}
