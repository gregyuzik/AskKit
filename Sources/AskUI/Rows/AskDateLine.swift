#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The date above a thread's first turn, and above the first turn of each
/// later day: the time for today, "Yesterday", or the date.
///
/// Only where it tells the reader something: the first turn, and any turn on a
/// different day from the one before it. A date line above every turn is noise.
struct AskDateLine: View {
    private let date: Date

    init(date: Date) {
        self.date = date
    }

    var body: some View {
        // Drawn again at the two midnights after its day, the only moments the
        // label can change: the time becomes "Yesterday", and "Yesterday"
        // becomes the date. Read once, it would keep today's time past
        // midnight until something rebuilt the row. The schedule opens at the
        // start of the turn's own day, so the first draw always has an entry
        // at or before the moment it appears: with the two midnights alone, a
        // question asked minutes earlier would be drawn as "Yesterday".
        TimelineView(.explicit(Self.redraws(for: date))) { context in
            Text(Self.label(for: date, now: context.date))
                .font(.caption)
                .askDeemphasizedText()
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The time for a date on `now`'s day, "Yesterday" for one on the day
    /// before, and the date otherwise.
    static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: dayBefore) {
            return yesterday
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static var yesterday: String {
        String(
            localized: "Yesterday",
            bundle: #bundle,
            comment: "Date separator above the first Ask question asked on the previous day."
        )
    }

    /// The moments the line is drawn: the start of `date`'s day, which the
    /// first draw reads, and the two midnights after it, when the label turns
    /// from the time to "Yesterday" and from "Yesterday" to the date.
    ///
    /// A timeline draws with the entry that most closely precedes the moment it
    /// appears, so a turn from today reads its time, one from yesterday today's
    /// midnight, and an older one the last midnight, its date.
    static func redraws(for date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        return [0, 1, 2].compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
    }

    /// Whether a date line belongs above `turn`.
    static func shows<Row: AskRow>(above turn: AskTurn<Row>, after previous: AskTurn<Row>?) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(turn.askedAt, inSameDayAs: previous.askedAt)
    }
}

#endif
