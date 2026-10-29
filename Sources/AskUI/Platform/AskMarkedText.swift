#if os(iOS) || os(macOS) || os(visionOS)

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Whether an input method is composing in the field a hardware Return
/// reaches: typing Japanese, Chinese or Korean on a hardware keyboard, the
/// text being converted is the field's marked text, and the Return that
/// confirms the conversion is the input method's, not the composer's
/// (`AskComposerReturn.composing`).
///
/// **Asked of UIKit and AppKit, because SwiftUI shows no field's marked
/// text.** In 27.2's interfaces and documentation, `KeyPress` carries the
/// key, its characters, its phase and its modifiers, `EventModifiers` has no
/// flag for an input method, and `TextSelection` holds ranges alone. A
/// `UIViewRepresentable` text view of AskKit's own would see its marked text,
/// and would give up the field's focus binding, its growth from one line to
/// four, its placeholder on the first baseline and its accessibility.
///
/// Public API only, asked as the Return comes in, and false wherever there is
/// nothing to ask, so a Return does what it did before.
///
/// - **iOS:** the first responder in the screen's window
///   (`askScreenWindow`), if it is a text input with a marked range. SwiftUI's
///   vertical-axis field is a `UITextView` underneath: measured on the iOS
///   27.2 simulator, in a window, its text view takes
///   `setMarkedText(_:selectedRange:)` and reports the range. A composer a
///   host draws outside `AskScreen` has no window to ask.
/// - **macOS:** the active input context's client, which is the key window's
///   first responder, the field editor of the field the Return reached.
/// - **visionOS:** nothing yet. The walk would be the same UIKit calls, but
///   the screen finds its window on iOS alone (`AskScreenWindow`).
///
/// Read from UIKit's and AppKit's documented behavior: not yet watched with
/// an input method on a device.
enum AskMarkedText {
    #if os(iOS)
    /// Whether the first responder under `root`, the screen's window, is a
    /// text input holding marked text. False with no window.
    static func isComposing(in root: UIView?) -> Bool {
        guard let root, let input = firstResponder(in: root) as? any UITextInput else { return false }
        return input.markedTextRange != nil
    }

    /// The first responder in `view`'s tree, depth first: a window has one
    /// at most.
    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
    #elseif os(macOS)
    /// Whether the active input context's client holds marked text. False
    /// with no context active.
    static var isComposing: Bool {
        NSTextInputContext.current?.client.hasMarkedText() ?? false
    }
    #endif
}

#endif
