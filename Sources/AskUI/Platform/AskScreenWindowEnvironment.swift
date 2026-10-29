#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    /// The window the screen is in, as its probe finds it (`AskScreenWindow`),
    /// which `AskScreen` sets on its composer so the chevron puts the keyboard
    /// away in that window and no other (`AskKeyboard.putAway(_:in:)`), and a
    /// hardware Return asks that window's first responder whether an input
    /// method is composing (`AskMarkedText`). Nil for a composer a host draws
    /// outside the screen: its chevron writes its focus binding, and its
    /// Return asks nothing.
    @Entry var askScreenWindow: AskScreenWindow?
}
#endif
