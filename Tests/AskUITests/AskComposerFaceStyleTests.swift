#if os(iOS) || os(macOS) || os(visionOS)

import Observation
import SwiftUI
import Testing

@testable import AskUI

/// Whether what `reads` read has been written since, armed once. Heard in
/// the write itself, which is on the main actor, as the screen's are.
@MainActor
private final class Written {
    private(set) var wasWritten = false

    init(_ reads: @escaping @MainActor () -> Void) {
        withObservationTracking { reads() } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.wasWritten = true }
        }
    }
}

/// What the face in a host's slot draws with, and how the Ask screen's style
/// reaches it: as the screen appears, and again whenever what the face draws
/// of it changes, not only as it appears.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskComposerFaceStyleTests {

    private func accessory(_ systemImage: String, _ identifier: String = "scan") -> AskComposerAccessory {
        AskComposerAccessory(systemImage: systemImage, label: Text(verbatim: "Scan"), identifier: identifier) {}
    }

    /// A slot's face draws the app's accent, no spectrum and no button until
    /// the screen under it first writes.
    @Test func aSlotsFaceStartsInTheAppsAccentWithNoButton() {
        let style = AskComposerFaceStyle()
        #expect(style.accent == .accentColor)
        #expect(style.spectrum == nil)
        #expect(style.accessory == nil)
    }

    /// The screen's spectrum reaches the face, which glows and fills its
    /// circle with it, and taking it away is a write the face hears too.
    @Test func aChangedSpectrumReachesTheFaceAfterTheScreenAppeared() {
        let style = AskComposerFaceStyle()
        style.update(accent: .blue, spectrum: nil, accessory: nil)
        let written = Written { _ = style.spectrum }
        style.update(accent: .blue, spectrum: .aurora, accessory: nil)
        #expect(written.wasWritten)
        #expect(style.spectrum == .aurora)
        let cleared = Written { _ = style.spectrum }
        style.update(accent: .blue, spectrum: nil, accessory: nil)
        #expect(cleared.wasWritten)
        #expect(style.spectrum == nil)
    }

    /// **A change after the screen appeared reaches the face.** The face reads
    /// the style in its body, so a write is one it hears and draws again on.
    @Test func aChangedAccentReachesTheFaceAfterTheScreenAppeared() {
        let style = AskComposerFaceStyle()
        style.update(accent: .blue, spectrum: nil, accessory: nil)
        let written = Written { _ = style.accent }
        style.update(accent: .orange, spectrum: nil, accessory: nil)
        #expect(written.wasWritten)
        #expect(style.accent == .orange)
    }

    @Test func aChangedAccessoryReachesTheFaceAfterTheScreenAppeared() {
        let style = AskComposerFaceStyle()
        style.update(accent: .blue, spectrum: nil, accessory: nil)
        let written = Written { _ = style.accessory }
        style.update(accent: .blue, spectrum: nil, accessory: accessory("barcode.viewfinder"))
        #expect(written.wasWritten)
        #expect(style.accessory?.systemImage == "barcode.viewfinder")
    }

    /// What the screen writes again on: any change to what the face draws of
    /// its style, the accent, the spectrum or the button's glyph, words or
    /// identifier.
    @Test func theScreenWritesAgainOnAnyChangeToWhatTheFaceDraws() {
        let scan = AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: accessory("barcode.viewfinder"))
        #expect(scan != AskComposerFaceLook(accent: .orange, spectrum: nil, accessory: accessory("barcode.viewfinder")))
        #expect(scan != AskComposerFaceLook(accent: .blue, spectrum: .aurora, accessory: accessory("barcode.viewfinder")))
        #expect(
            AskComposerFaceLook(accent: .blue, spectrum: .aurora, accessory: nil)
                != AskComposerFaceLook(accent: .blue, spectrum: AskSpectrum([.red, .orange]), accessory: nil)
        )
        #expect(scan != AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: accessory("dice")))
        #expect(scan != AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: accessory("barcode.viewfinder", "surprise")))
        #expect(scan != AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: nil))
        let photo = AskComposerAccessory.leading(nil, acceptsAttachments: true, onAttach: {})
        #expect(AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: photo) != AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: nil))
    }

    /// And on nothing else: a host's body building its accessory again, with
    /// a new closure and the same glyph, words and identifier, is no change
    /// for the face to draw.
    @Test func aRebuiltButtonThatDrawsTheSameIsNoChange() {
        #expect(
            AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: accessory("barcode.viewfinder"))
                == AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: accessory("barcode.viewfinder"))
        )
        // A host's body building the same spectrum again, too.
        #expect(
            AskComposerFaceLook(accent: .blue, spectrum: AskSpectrum([.red, .orange]), accessory: nil)
                == AskComposerFaceLook(accent: .blue, spectrum: AskSpectrum([.red, .orange]), accessory: nil)
        )
        // The photo button too, whose words come from AskKit's catalog: a
        // screen that passes `onAttach` builds it again on every pass.
        #expect(
            AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: .leading(nil, acceptsAttachments: true, onAttach: {}))
                == AskComposerFaceLook(accent: .blue, spectrum: nil, accessory: .leading(nil, acceptsAttachments: true, onAttach: {}))
        )
    }
}

#endif
