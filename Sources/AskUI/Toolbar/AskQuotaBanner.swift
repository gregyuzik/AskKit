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
        // merged into the sentence's.
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
        .accessibilityIdentifier(AskAccessibility.quotaShowOptions)
    }

    private var line: String {
        Self.line(resetDate: resetDate)
    }

    /// What the banner says, and what VoiceOver hears as it arrives
    /// (`AskScreen`): the limit's sentence, and when it resets where that is
    /// known.
    static func line(resetDate: Date?) -> String {
        // The limit's sentence is AskCore's: the same words the thread shows
        // when a turn fails on the quota, from the same catalog. Two copies
        // would drift.
        let reached = AskError.quotaReached(resetDate: resetDate).errorDescription ?? ""
        guard let resetDate else { return reached }
        let resets = String(
            localized: "It resets at \(resetDate.formatted(date: .omitted, time: .shortened)).",
            bundle: #bundle,
            comment: "Follows the Private Cloud Compute limit line: the time of day the daily limit comes back. The placeholder is a time alone, such as 5:00 PM."
        )
        // With no space after a full-width full stop (`AskSentences`).
        return AskSentences.joined(reached, resets)
    }
}

#endif
