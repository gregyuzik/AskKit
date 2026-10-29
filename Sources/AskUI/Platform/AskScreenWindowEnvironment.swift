#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    /// The window the screen is in, as its probe finds it (`AskScreenWindow`),
    /// which `AskScreen` sets on its composer so the chevron puts the keyboard
    /// away in that window and no other (`AskKeyboard.putAway(_:in:)`). Nil
    /// for a composer a host draws outside the screen.
    @Entry var askScreenWindow: AskScreenWindow?
}
#endif
