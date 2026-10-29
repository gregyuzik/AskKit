import Testing

@testable import AskCore

/// Every length of time is a `Duration`, and what prints one prints what the
/// millisecond counts it replaced printed: the `[stream]` line and the
/// evaluation's table read the same, byte for byte, for the same times.
@Suite(.timeLimit(.minutes(1))) struct AskDurationsTests {

    /// What AskKit 0.2.0's engine logged for a time (`AskEngine.ms(_:)`, gone
    /// with the millisecond counts): the reference a whole-millisecond reading
    /// has to match.
    private func loggedBefore(_ duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) * 1e-15)
    }

    @Test func aWholeMillisecondReadingCutsTheFractionOff() {
        #expect(Duration.zero.wholeMilliseconds == 0)
        #expect(Duration.milliseconds(300).wholeMilliseconds == 300)
        #expect((Duration.milliseconds(300) + .microseconds(999)).wholeMilliseconds == 300)
        #expect((Duration.seconds(2) + .milliseconds(5)).wholeMilliseconds == 2_005)
        // Toward zero, as the count it replaced was cut, for a time a clock
        // set back could read.
        #expect(Duration.milliseconds(-1_500).wholeMilliseconds == -1_500)
        #expect(Duration.nanoseconds(-300_999_999).wholeMilliseconds == -300)
    }

    @Test func aWholeMillisecondReadingIsWhatTheEngineLoggedBefore() {
        // A clock reads in whole nanoseconds: every whole millisecond up to
        // two minutes, and a spread of uneven readings past it.
        let readings = (0...120_000).map { Duration.milliseconds($0) }
            + stride(from: Int64(0), through: 600_000_000_000, by: 7_919_113).map { Duration.nanoseconds($0) }
        let differing = readings.filter { $0.wholeMilliseconds != loggedBefore($0) }
        #expect(differing.isEmpty, "\(differing.prefix(5))")
    }

    @Test func theStreamLineReadsAsItDidForTheSameTimes() {
        // Fractions of a millisecond on every time, which the line never
        // printed: each is cut off, and the span is the last word's reading
        // less the first's (600), not their difference cut (599).
        var stats = AskTurnStats(tier: .privateCloud)
        stats.snapshots = 4
        stats.growths = 2
        stats.characters = 40
        stats.toolCalls = 1
        stats.rowsRead = 3
        stats.timeToFirstTool = .milliseconds(120) + .microseconds(700)
        stats.timeToFirstWord = .milliseconds(300) + .microseconds(900)
        stats.timeToLastWord = .milliseconds(900) + .microseconds(100)
        stats.duration = .milliseconds(1_000) + .nanoseconds(999_999)
        #expect(stats.streamLine == "[stream] privateCloud snapshots=4 growths=2 firstWord=300ms proseSpan=600ms "
            + "chars=40 meanDelta=20 firstTool=120ms tools=1 rows=3 grounding=none total=1000ms")
    }

    @Test func aStreamLineWithNoWordAndNoToolDashesThem() {
        #expect(AskTurnStats(tier: .onDevice).streamLine == "[stream] onDevice snapshots=0 growths=0 firstWord=– "
            + "proseSpan=– chars=0 meanDelta=0 firstTool=– tools=0 rows=0 grounding=none total=0ms")
    }
}

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)

extension AskDurationsTests {
    @Test func theEvalTablesMillisecondColumnReadsAsItDidForTheSameTime() {
        var slow = AskOutcome(id: "slow")
        slow.duration = .milliseconds(1_400) + .microseconds(500)
        let lines = AskEval<FakeDomain>.table([slow, AskOutcome(id: "instant")])
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "| scenario | tier | tools | restarts | rows | tiles | kind | card | ms | verdict |")
        #expect(lines[2] == "| slow | – | 0 | 0 | 0 | 0 | – | – | 1400 | ok |")
        #expect(lines[3] == "| instant | – | 0 | 0 | 0 | 0 | – | – | 0 | ok |")
    }
}

#endif
