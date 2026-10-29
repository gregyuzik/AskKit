#if os(iOS) || os(macOS)

import Testing
#if os(iOS)
import UIKit
#endif

@testable import AskUI

#if os(iOS)
/// What the composer asks UIKit before a hardware Return sends: whether the
/// focused text input in the screen's window holds an input method's marked
/// text (`AskMarkedText`).
///
/// **A stand-in for focus, and UIKit's own marked text.** The test host has
/// no scene to put a window in, and a text view out of a window can't become
/// first responder: measured on the iOS 27.2 simulator, `becomeFirstResponder()`
/// returns false there. So `AskFocusedTextView` says it is the first
/// responder. Its marked text is a text view's own: out of a window too,
/// `setMarkedText(_:selectedRange:)` marks the text it is handed, which
/// `markedTextRange` reports and `unmarkText()` clears, as an input method's
/// conversion and its confirmation do.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskMarkedTextTests {
    /// A text view that says it has the focus.
    private final class AskFocusedTextView: UITextView {
        override var isFirstResponder: Bool { true }
    }

    /// A view that says it has the focus and takes no text.
    private final class AskFocusedView: UIView {
        override var isFirstResponder: Bool { true }
    }

    /// A screen's worth of views, with `focused` a few levels down and
    /// another text view beside it.
    private func screen(holding focused: UIView, beside other: UIView = UITextView()) -> UIView {
        let screen = UIView()
        let bar = UIView()
        let capsule = UIView()
        screen.addSubview(UIView())
        screen.addSubview(bar)
        bar.addSubview(other)
        bar.addSubview(capsule)
        capsule.addSubview(focused)
        return screen
    }

    /// Composing from the first marked character to the confirmation: marked
    /// text in the focused field is composing, and once confirmed it isn't.
    @Test func markedTextInTheFocusedFieldIsComposing() throws {
        let field = AskFocusedTextView()
        let screen = screen(holding: field)
        #expect(!AskMarkedText.isComposing(in: screen))
        field.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
        try #require(field.markedTextRange != nil)
        #expect(AskMarkedText.isComposing(in: screen))
        field.unmarkText()
        #expect(!AskMarkedText.isComposing(in: screen))
    }

    /// Only the focused field's marked text counts: a hardware Return reaches
    /// the field with the focus, and marked text in another isn't its input
    /// method's to confirm.
    @Test func markedTextOutsideTheFocusedFieldIsNotComposing() throws {
        let other = UITextView()
        other.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        try #require(other.markedTextRange != nil)
        #expect(!AskMarkedText.isComposing(in: screen(holding: AskFocusedTextView(), beside: other)))
    }

    /// No window, or a focus that takes no text: nothing is composing, and
    /// a Return does what it did before.
    @Test func noWindowOrNoFocusedTextIsNotComposing() {
        #expect(!AskMarkedText.isComposing(in: nil))
        #expect(!AskMarkedText.isComposing(in: screen(holding: AskFocusedView())))
        #expect(!AskMarkedText.isComposing(in: screen(holding: UIView())))
    }
}
#endif

#if os(macOS)
/// What the composer asks AppKit before a hardware Return sends
/// (`AskMarkedText`).
///
/// **Only the case with nothing to ask.** The input context is the key
/// window's first responder's, and a test process has no key window: a text
/// view drawn here brings up `NSApplication`, which `AskComposerPlaceholderTests`
/// says the fold tests rely on it not doing.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskMarkedTextMacTests {
    /// With no input context active, nothing is composing, and a Return
    /// does what it did before.
    @Test func noActiveInputContextIsNotComposing() {
        #expect(!AskMarkedText.isComposing)
    }
}
#endif

#endif
