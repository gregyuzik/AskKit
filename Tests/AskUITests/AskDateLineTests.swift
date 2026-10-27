#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// Which turns of a thread get a date above them: the first, and one asked on
/// a different day from the turn before it.
///
/// Days by the reader's own calendar and time zone, as the line reads them.
/// Every date here is built from that calendar's components, in the middle of
/// June and away from any clock change, so the same wall times are the same
/// days wherever the test runs.
@Suite(.timeLimit(.minutes(1))) struct AskDateLineTests {

    private func turn(day: Int, hour: Int, minute: Int = 0) throws -> AskTurn<UIRow> {
        let components = DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)
        let askedAt = try #require(Calendar.current.date(from: components))
        return AskTurn<UIRow>(question: "q", origin: .typed, askedAt: askedAt)
    }

    private func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)))
    }

    @Test func theLabelTurnsFromTheTimeToYesterdayToTheDateAtMidnight() throws {
        // Read against the moment it is drawn, so a line still on screen past
        // midnight reads "Yesterday" once its timeline draws it again.
        let asked = try date(day: 10, hour: 23, minute: 30)
        let lateThatNight = try date(day: 10, hour: 23, minute: 59)
        let midnight = try date(day: 11, hour: 0)
        let nextNight = try date(day: 11, hour: 23, minute: 59)
        let theMidnightAfter = try date(day: 12, hour: 0)
        #expect(AskDateLine.label(for: asked, now: lateThatNight) == asked.formatted(date: .omitted, time: .shortened))
        #expect(AskDateLine.label(for: asked, now: midnight) == AskDateLine.yesterday)
        #expect(AskDateLine.label(for: asked, now: nextNight) == AskDateLine.yesterday)
        #expect(AskDateLine.label(for: asked, now: theMidnightAfter) == asked.formatted(date: .abbreviated, time: .omitted))
    }

    @Test func theLineIsDrawnAtTheStartOfItsDayAndAgainAtTheTwoMidnightsAfter() throws {
        let asked = try date(day: 10, hour: 23, minute: 30)
        let redraws = [try date(day: 10, hour: 0), try date(day: 11, hour: 0), try date(day: 12, hour: 0)]
        #expect(AskDateLine.redraws(for: asked) == redraws)
    }

    @Test func theFirstDrawHasAnEntryAtOrBeforeTheTurn() throws {
        // A timeline draws with the entry that most closely precedes the moment
        // it appears. The two midnights alone gave it none, and a question
        // asked minutes earlier was drawn as "Yesterday".
        let asked = try date(day: 10, hour: 14, minute: 20)
        let first = try #require(AskDateLine.redraws(for: asked).first)
        #expect(first <= asked)
    }

    @Test func theLineReadsTheTimeTodayYesterdayTheDayAfterAndTheDateAWeekOn() throws {
        // What the line reads when it appears: drawn with the latest entry at
        // or before that moment, as a timeline draws it.
        let asked = try date(day: 10, hour: 14, minute: 20)
        let redraws = AskDateLine.redraws(for: asked)
        func drawn(at now: Date) throws -> String {
            let entry = try #require(redraws.last { $0 <= now })
            return AskDateLine.label(for: asked, now: entry)
        }
        let minutesLater = try date(day: 10, hour: 14, minute: 24)
        let nextMorning = try date(day: 11, hour: 9)
        let aWeekOn = try date(day: 17, hour: 9)
        #expect(try drawn(at: minutesLater) == asked.formatted(date: .omitted, time: .shortened))
        #expect(try drawn(at: nextMorning) == AskDateLine.yesterday)
        #expect(try drawn(at: aWeekOn) == asked.formatted(date: .abbreviated, time: .omitted))
    }

    @Test func theFirstTurnHasOne() throws {
        #expect(AskDateLine.shows(above: try turn(day: 10, hour: 12), after: nil))
    }

    @Test func aTurnOnTheSameDayAsTheOneBeforeHasNone() throws {
        // A minute after midnight and a minute before the next: one day.
        let morning = try turn(day: 10, hour: 0, minute: 1)
        let night = try turn(day: 10, hour: 23, minute: 59)
        #expect(!AskDateLine.shows(above: night, after: morning))
    }

    @Test func aTurnOnAnotherDayHasOneHoweverCloseInTime() throws {
        // Two minutes apart across midnight are two days.
        let beforeMidnight = try turn(day: 10, hour: 23, minute: 59)
        let afterMidnight = try turn(day: 11, hour: 0, minute: 1)
        #expect(AskDateLine.shows(above: afterMidnight, after: beforeMidnight))
        // And a week on, at the same time of day.
        #expect(AskDateLine.shows(above: try turn(day: 17, hour: 12), after: try turn(day: 10, hour: 12)))
    }
}

#endif
