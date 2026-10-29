#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The accent the nothing-to-ask button is filled with and its label judged
/// on: the one the host handed `AskScreen`, which the screen sets in the
/// environment (`askFirstScreenAccent`), and the app's accent for a first
/// screen a host draws on its own.
///
/// **The values, not a render.** `ImageRenderer` draws nothing of the
/// button's glass, label included (`AskFirstScreenFoldTests`), and a render
/// of `AskScreen` itself would bring up its field. That the screen sets the
/// entry, and the button's look on a host's accent, are for a simulator.
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenAccentTests {
    /// A dark navy, which holds white words at 4.5:1, and a yellow, which
    /// doesn't.
    private let navy = Color(red: 0.05, green: 0.1, blue: 0.35)
    private let yellow = Color(red: 1, green: 0.8, blue: 0)

    /// Without a screen around it, the button wears the app's accent, which
    /// is also `AskScreen`'s default.
    @Test func aFirstScreenOnItsOwnWearsTheAppsAccent() {
        #expect(EnvironmentValues().askFirstScreenAccent == .accentColor)
    }

    /// **The host's accent reaches the label's judgment.** Set in the
    /// environment, as `AskScreen` sets it, it is what the label's color is
    /// worked out on: white on the navy, and black on the yellow where the
    /// accent fills the button.
    @Test func theScreensAccentIsWhatTheLabelIsJudgedOn() {
        var environment = EnvironmentValues()
        environment.askFirstScreenAccent = navy
        #expect(environment.askFirstScreenAccent == navy)
        #expect(!AskOnAccentLabel.isBlack(on: AskContrast.RGB(environment.askFirstScreenAccent.resolve(in: environment))))

        environment.askFirstScreenAccent = yellow
        #if os(visionOS)
        #expect(!AskOnAccentLabel.isBlack(on: AskContrast.RGB(environment.askFirstScreenAccent.resolve(in: environment))))
        #else
        #expect(AskOnAccentLabel.isBlack(on: AskContrast.RGB(environment.askFirstScreenAccent.resolve(in: environment))))
        #endif
    }
}

#endif
