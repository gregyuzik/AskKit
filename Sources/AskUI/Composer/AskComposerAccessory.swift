#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// The accessory button: the one button a composer carries before its field,
/// such as a photo or a barcode scan, as a value the host hands the screen.
/// The composer draws it, and so does the face in a host's slot
/// (`askComposerSlot`).
///
/// **A value, not a view.** What the accessory button draws is always the
/// same shape, a glyph on the composer's glass in a circular hit region, so
/// the host supplies the glyph, the words and the action, and the composer
/// draws it the way it draws the photo button. Why not a view builder:
/// ARCHITECTURE.md, Rejected designs.
///
/// **One, deliberately.** The field is the composer. Two buttons before it on
/// a phone leave a question room for a word and a half.
///
/// **Isolation.** An accessory button is main-actor isolated, as the views it
/// goes in are: build it on the main actor, and read its fields and run its
/// action there. That isolation makes it `Sendable`, so once built it can be
/// held anywhere, a host's own `Sendable` value included, which
/// `AskCrossPostureTests` pins.
public struct AskComposerAccessory {
    /// The SF Symbol the button shows, drawn bare: in the secondary style
    /// where that holds 3:1 on the composer's tint, and in the primary style
    /// where it doesn't, as on the default accent's capsule in light mode, and
    /// under Increase Contrast.
    public let systemImage: String
    /// What VoiceOver calls it: the host's own words, from the host's own
    /// catalog, because the glyph's name isn't a label.
    public let label: Text
    /// Its accessibility identifier, for the host's UI tests.
    public let identifier: String
    /// What a tap does. The button is disabled while a turn is in flight.
    public let action: () -> Void

    /// Creates an accessory button.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol the button shows, drawn bare, in the
    ///     secondary style or, where that falls under 3:1 on the composer's
    ///     tint and under Increase Contrast, the primary.
    ///   - label: What VoiceOver calls the button, in the host's own words.
    ///   - identifier: The button's accessibility identifier.
    ///   - action: What a tap does, such as presenting the host's scanner.
    public init(systemImage: String, label: Text, identifier: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.action = action
    }

    /// The button before the field, if any: the host's accessory button, else
    /// the photo button where the domain accepts photos and the host can take
    /// one. The composer and its face in a tab bar's slot both draw this one.
    ///
    /// **The host's button wins, and shows whatever the domain takes.** With
    /// one set, `onAttach` goes unused, and the photo button passed as the
    /// host's own (`photo(_:)`) shows for a domain that takes no photos too.
    static func leading(
        _ accessory: AskComposerAccessory?, acceptsAttachments: Bool, onAttach: (() -> Void)?
    ) -> AskComposerAccessory? {
        if let accessory { return accessory }
        guard acceptsAttachments, let onAttach else { return nil }
        return .photo(onAttach)
    }

    /// The photo button: what a domain that accepts photo attachments gets
    /// when the host passes `onAttach`. Its glyph is `photo`, VoiceOver calls
    /// it "Add a photo", and its identifier is `AskAccessibility.attach`.
    ///
    /// Passed as the accessory button itself, it shows whether or not the
    /// domain accepts photos, and the `onAttach` beside it goes unused. Pass
    /// `onAttach` instead for a photo button that shows only where the
    /// domain takes photos.
    ///
    /// - Parameter action: What a tap does, such as presenting the host's
    ///   photo picker.
    public static func photo(_ action: @escaping () -> Void) -> AskComposerAccessory {
        AskComposerAccessory(
            systemImage: "photo",
            label: Text("Add a photo", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button that attaches a photo to the question."),
            identifier: AskAccessibility.attach,
            action: action
        )
    }
}

#endif
