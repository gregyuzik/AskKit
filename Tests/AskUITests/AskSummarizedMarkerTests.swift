#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The hairline either side of "Earlier in this chat is summarized".
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskSummarizedMarkerTests {
    /// **One device pixel on every screen.** A fixed third of a point is one
    /// pixel only at 3x: on a 2x iPad or Retina Mac it draws a soft line two
    /// thirds of a pixel wide, and on a 1x external display a third of one.
    @Test func theHairlineIsOneDevicePixelAtEveryScale() {
        #expect(AskSummarizedMarker.thickness(displayScale: 1, contrast: .standard) == 1)
        #expect(AskSummarizedMarker.thickness(displayScale: 2, contrast: .standard) == 0.5)
        #expect(AskSummarizedMarker.thickness(displayScale: 3, contrast: .standard) == CGFloat(1) / 3)
    }

    /// Increase Contrast makes it a line, as it does the hairline around
    /// `AskAnswerCard`.
    @Test func increaseContrastMakesItALine() {
        #expect(AskSummarizedMarker.thickness(displayScale: 2, contrast: .increased) == 1)
        #expect(AskSummarizedMarker.thickness(displayScale: 3, contrast: .increased) == 1)
    }
}

#endif
