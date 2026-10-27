#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

extension View {
    /// Hides the view from accessibility while `hidden` is true, and otherwise
    /// adds nothing: never `.accessibilityHidden(false)`.
    ///
    /// **A view un-hidden by `.accessibilityHidden(false)` isn't the view it
    /// was before it was hidden.** The face in a host's slot, hidden while the
    /// composer was up, came back listing its draft as a text element of its
    /// own over its field button, the button's whole size. A touch at the
    /// field's middle reached that text and not the button: the field wasn't
    /// hittable after 68 lowerings of 69 (a UI test on the demo, iPhone 18 Pro
    /// simulator, iOS 27.2, raising the composer out of the slot and putting it
    /// back three times a launch). Hidden this way it was hittable after 18 of
    /// 18, as it is before the first raise.
    ///
    /// **A new identity at each flip**, so only for a view that holds nothing
    /// that must outlive one: never a text field, whose focus goes with its
    /// identity. A composer re-created this way as it rose lost the keyboard.
    @ViewBuilder
    func askAccessibilityHidden(while hidden: Bool) -> some View {
        if hidden {
            accessibilityHidden(true)
        } else {
            self
        }
    }
}

#endif
