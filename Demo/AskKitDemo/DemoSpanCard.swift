import AskCore
import AskUI
import SwiftUI

/// What a turn's search also knew, under the answer: the years its rows span.
///
/// The two halves a payload card needs — a payload the tool recorded
/// (`DemoYearSpan`, read back with `AskAnswer.payload(as:)`) and
/// `AskAnswerCard` to draw it in, so every host's cards under an answer read as
/// one family. A turn that recorded nothing draws nothing, and neither does a
/// payload that no longer decodes.
struct DemoSpanCard: View {
    let turn: AskTurn<DemoRow>

    var body: some View {
        if let span = turn.answer?.payload(as: DemoYearSpan.self) {
            AskAnswerCard {
                // One line while both pieces fit on it. Side by side at the
                // largest text sizes each had half a phone's column, less
                // than a word, and broke inside "searched" and the years.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        count(of: span)
                        Spacer(minLength: 8)
                        years(of: span)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        count(of: span)
                        years(of: span)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
            }
            .accessibilityIdentifier(DemoAccessibility.spanCard)
            // The footer's first piece, so the step after the evidence line.
            .askArrival()
        }
    }

    private func count(of span: DemoYearSpan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: "\(span.count) searched")
        }
    }

    private func years(of span: DemoYearSpan) -> some View {
        Text(verbatim: "\(year(span.oldest))–\(year(span.newest))")
            .monospacedDigit()
    }

    private func year(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }
}
