#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The banner over the thread when the reader has used Private Cloud
/// Compute's quota for the day: the limit's sentence, when it resets where the
/// system says, and "Show options" where Apple offers a way to ask for more.
public struct AskQuotaBanner: View {
    private let resetDate: Date?
    private let canRequestMore: Bool
    private let onShowOptions: () -> Void

    /// Creates the banner.
    ///
    /// - Parameters:
    ///   - resetDate: When the quota comes back, or nil where the system
    ///     hasn't said.
    ///   - canRequestMore: Whether to offer "Show options", Apple's route to
    ///     a higher limit.
    ///   - onShowOptions: What "Show options" does, such as the store's
    ///     `showLimitIncrease()`.
    public init(resetDate: Date?, canRequestMore: Bool, onShowOptions: @escaping () -> Void) {
        self.resetDate = resetDate
        self.canRequestMore = canRequestMore
        self.onShowOptions = onShowOptions
    }

    /// The least the sentence is given beside "Show options" before the
    /// button goes under it, as the text scales it.
    @ScaledMetric(relativeTo: .footnote) private var sentenceWidth: CGFloat = 160

    public var body: some View {
        Group {
            if canRequestMore {
                // **Side by side where the sentence keeps a column it can be
                // read in, and the button under it where it doesn't**, as
                // `AskThreadRow`'s evidence line and thumbs do. Side by side at
                // every size, the button took its width first and the
                // sentence wrapped in what was left, a word or two a line at
                // the largest sizes. The sentence offers `sentenceWidth` as its
                // ideal, so the first arrangement fits wherever that much is
                // left beside the button, and the sentence then wraps in all
                // of what is left.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        sentence
                            .frame(idealWidth: sentenceWidth)
                        Spacer(minLength: 0)
                        showOptions
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        sentence
                        showOptions
                    }
                }
            } else {
                sentence
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .askGlass(.regular, in: .rect(cornerRadius: 14))
        // A container, not one element: the sentence is one stop and "Show
        // options" another, so VoiceOver, Voice Control and a UI test each
        // reach the button on its own. Combined, the button's name would be
        // joined to the sentence's.
        .accessibilityElement(children: .contain)
    }

    /// The glyph and the line, as one element.
    private var sentence: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Not `icloud.slash`: Apple reserves that glyph for iCloud itself
            // (`symbol_restrictions.strings`), and this is Private Cloud
            // Compute's day, which comes back at the time the line gives.
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                // `children: .combine` below joins every label in this row
                // into one string, so an unhidden glyph would put "hourglass"
                // ahead of the sentence VoiceOver reads.
                .accessibilityHidden(true)
            Text(line)
                .font(.footnote)
                // Text to read on glass: 4.5:1 (`AskGlassForeground`).
                .foregroundStyle(AskGlassForeground(minimum: AskGlassForeground.text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var showOptions: some View {
        Button(action: onShowOptions) {
            Text("Show options", bundle: #bundle, comment: "Button that opens Apple's route to request a higher Private Cloud Compute limit.")
                // A touch target, 60 pt on visionOS (`AskGrowth.touchTarget`).
                .frame(minHeight: AskGrowth.touchTarget)
                .contentShape(.rect)
        }
        .font(.footnote)
        // The button draws its words in the tint, as the card's "Show
        // options" and the confirmation card's "Not now" do. The system blue
        // is 3.52:1 on the glass's estimated light ground and 4.31:1 on its
        // dark one (`AskContrast.ground(isLight:tint:)`), under the 4.5:1 the
        // sentence beside it is held to (`AskGlassForeground`); `.primary`
        // clears it in both. Semibold, since the hue no longer sets it apart
        // from that sentence, and it has no fill to.
        .tint(.primary)
        .fontWeight(.semibold)
        .accessibilityIdentifier(AskAccessibility.quotaShowOptions)
    }

    private var line: String {
        Self.line(resetDate: resetDate)
    }

    /// What the banner says, what VoiceOver hears as it arrives
    /// (`AskScreen`), and what the settings card says at the limit
    /// (`AskPrivateCloudState.message(resetDate:)`): the limit's sentence, and
    /// when it resets where that is known and still to come.
    ///
    /// **When it resets, by the day it falls on.** A reset later today reads
    /// as its time, and one on a later day as its day and time. A time alone
    /// is read as its next coming, and the system's reset can be further off
    /// than that. A day rather than "tomorrow", since the line is read as it
    /// is drawn, and a banner still up past midnight would keep a "tomorrow"
    /// that had become today. A reset already past says nothing about when:
    /// as a bare time it would read as that time tomorrow, which nothing has
    /// said.
    ///
    /// - Parameters:
    ///   - resetDate: When the quota comes back, or nil where the system
    ///     hasn't said.
    ///   - now: The moment the line is read for.
    ///   - calendar: The calendar whose days the line counts in.
    /// - Returns: The line, localized.
    nonisolated static func line(resetDate: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        // The limit's sentence is AskCore's: the same words the thread shows
        // when a turn fails on the quota, from the same catalog. Two copies
        // would drift.
        let reached = AskError.quotaReached(resetDate: resetDate).errorDescription ?? ""
        guard let resetDate, resetDate > now else { return reached }
        let resets: String
        if calendar.isDate(resetDate, inSameDayAs: now) {
            resets = String(
                localized: "It resets at \(resetDate.formatted(date: .omitted, time: .shortened)).",
                bundle: #bundle,
                comment: "Follows the Private Cloud Compute limit line: the time of day the daily limit comes back. The placeholder is a time alone, such as 5:00 PM."
            )
        } else {
            // Formatted apart from the literal: the catalog check can't read a
            // key out of an interpolation that chains calls.
            let day = resetDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
            resets = String(
                localized: "It resets on \(day).",
                bundle: #bundle,
                comment: "Follows the Private Cloud Compute limit line when the daily limit comes back on a later day, such as tomorrow. The placeholder is the weekday, the date and the time together, such as Friday, Oct 30 at 5:00 AM."
            )
        }
        // With no space after a full-width full stop (`AskSentences`).
        return AskSentences.joined(reached, resets)
    }
}

#endif
