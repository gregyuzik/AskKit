#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// The "Jump to latest" pill: a glass capsule offering to take the reader
/// back to the newest text when it is out of view. `AskScreen` decides when
/// it shows.
public struct AskJumpToLatestPill: View {
    private let action: () -> Void

    /// Creates the pill.
    ///
    /// - Parameter action: What a tap does, such as scrolling the thread to
    ///   its end.
    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // A `Label` rather than a hand-built `HStack`: it hides the icon
            // from VoiceOver for free, which is what the arrow needs, since
            // the words beside it already say where the button goes.
            Label {
                Text("Jump to latest", bundle: #bundle, comment: "Button that scrolls the Ask thread down to the answer being written, shown when the reader has scrolled away from it.")
            } icon: {
                Image(systemName: "arrow.down")
            }
            .labelStyle(.titleAndIcon)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            // A touch target, 60 pt on visionOS (`AskGrowth.touchTarget`).
            .frame(minHeight: AskGrowth.touchTarget)
            // A `.plain` button hit-tests its label's content, so without
            // this naming the capsule, the padding and the `minHeight` slack
            // around the words would be dead. `AskChipRow` says the rest.
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Lit in its capsule: on visionOS the glass under it is a fill that
        // answers no gaze (`askGlass`).
        .askHoverEffect(in: .capsule)
        .askGlass(.interactive, in: .capsule)
        .accessibilityIdentifier(AskAccessibility.jumpToLatest)
    }
}

#endif
