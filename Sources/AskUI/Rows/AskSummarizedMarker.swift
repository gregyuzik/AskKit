#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// The hairline above a turn whose fresh session opened with a recap
/// (`AskTurn.summarizedBefore`).
///
/// **Silent context truncation is the pitfall this exists to close.** When a
/// kept conversation ends, such as when it rolls over or the app relaunches,
/// the next question starts a fresh session with a recap, and without a mark
/// the reader sees an assistant that has quietly forgotten the earlier part of
/// what they said.
struct AskSummarizedMarker: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    init() {}

    var body: some View {
        HStack(spacing: 10) {
            line
            Text("Earlier in this chat is summarized", bundle: #bundle, comment: "Marker above an Ask question whose fresh session began with a summary of the chat so far: after a long chat rolled over, after an answer failed or was stopped, or when the chat was reopened.")
                .font(.caption2)
                .askDeemphasizedText()
                .multilineTextAlignment(.center)
                // **Wraps at full size, on as many lines as it needs.** It is
                // the one thing on screen that says earlier turns were
                // summarized, and it grows by half again in the longer
                // languages (Vietnamese is 50 characters to English's 34):
                // held to two lines and let shrink, it came out smaller and
                // then cut short in German, Polish and Vietnamese, which need
                // three. Fixed vertically only: `.fixedSize()` on both axes
                // forbids the wrap and pushes the hairlines off the row.
                .fixedSize(horizontal: false, vertical: true)
                // The words take the width before the hairlines do, which keep
                // a stub either side (`line`).
                .layoutPriority(1)
            line
        }
        .accessibilityElement(children: .combine)
    }

    /// A hairline, and under Increase Contrast a line: `AskAnswerCard`'s edge
    /// takes the same two steps, `.tertiary` to `.secondary`. Never shorter
    /// than a stub, so wrapped words still sit between two lines.
    private var line: some View {
        Rectangle()
            .fill(contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(minWidth: 16)
            .frame(height: Self.thickness(displayScale: displayScale, contrast: contrast))
    }

    /// One device pixel on every screen, and a full point under Increase
    /// Contrast, matching `AskAnswerCard`'s edge there. A fixed third of a
    /// point would be one pixel only at 3x: a soft line two thirds of a pixel
    /// wide on a 2x iPad or Mac, and a third of one on a 1x external display.
    static func thickness(displayScale: CGFloat, contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 1 : 1 / displayScale
    }
}

#endif
