#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// A turn that ended badly, or ended short.
///
/// **It renders beneath whatever the turn had already written, never instead of
/// it.** Nothing the thread has shown is taken back: a failure after two
/// sentences of correct prose leaves those two sentences on screen and says what
/// went wrong under them.
///
/// A refused or ungrounded failure has somewhere to go: the coaching, two
/// starters under the line, so a blocked reader isn't left at a dead end.
/// `AskConversationStore` decides when to offer them, and the thread row offers
/// them, and Try Again, under the newest turn only; this only draws them.
///
/// A turn the reader stopped before its first word ends here too, so they can
/// ask it again, under the line that says they stopped it. Nothing failed,
/// so it draws no warning glyph (`glyph(readerStopped:)`).
///
/// **The line takes VoiceOver's focus from a wait row that had it as it went**,
/// when the turn ends before its first word (`AskWaitRowHandoff`), and says
/// when the focus has landed on it, which is when VoiceOver reads it
/// (`AskSpeechLedger`).
///
/// **Try Again and the coaching are a fill, not glass**, on iOS and the Mac,
/// as the question bubble is: they scroll under the glass bar and behind the
/// glass composer, and glass can't sample glass (`AskQuestionBubble`).
struct AskFailureRow: View {
    private let message: String
    /// Whether the line is the reader's own stop, before the turn had a word
    /// (`AskTurn.isReadersStopBeforeAWord`).
    private let readerStopped: Bool
    private let retryable: Bool
    private let coaching: [AskStarter]
    private let takesFocus: Bool
    private let onRetry: () -> Void
    private let onCoaching: (AskStarter) -> Void
    private let onFocusTaken: () -> Void
    private let onLineFocused: () -> Void

    /// VoiceOver's focus on the line.
    @AccessibilityFocusState private var lineIsFocused: Bool

    /// - Parameters:
    ///   - takesFocus: Whether the line takes VoiceOver's focus now that it is
    ///     there: the wait row had it as the turn ended.
    ///   - onFocusTaken: Called once the line has asked for it.
    ///   - onLineFocused: Called as VoiceOver's focus lands on the line, from
    ///     the wait row or the reader's own swipe: VoiceOver reads the line
    ///     then.
    init(
        message: String,
        readerStopped: Bool = false,
        retryable: Bool,
        coaching: [AskStarter] = [],
        takesFocus: Bool = false,
        onRetry: @escaping () -> Void,
        onCoaching: @escaping (AskStarter) -> Void = { _ in },
        onFocusTaken: @escaping () -> Void = {},
        onLineFocused: @escaping () -> Void = {}
    ) {
        self.message = message
        self.readerStopped = readerStopped
        self.retryable = retryable
        self.coaching = coaching
        self.takesFocus = takesFocus
        self.onRetry = onRetry
        self.onCoaching = onCoaching
        self.onFocusTaken = onFocusTaken
        self.onLineFocused = onLineFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let glyph = Self.glyph(readerStopped: readerStopped) {
                    Image(systemName: glyph)
                        .foregroundStyle(.secondary)
                        // Decoration. The message beside it says what went
                        // wrong; the glyph reaching VoiceOver as its own stop
                        // under `children: .contain` would add a stop that
                        // says "warning" and nothing else.
                        .accessibilityHidden(true)
                }
                Text(message)
                    .font(.subheadline)
                    .askDeemphasizedText()
                    // The element VoiceOver lands on, not the container
                    // around it, which is a group and not a stop.
                    .accessibilityFocused($lineIsFocused)
            }
            if retryable {
                Button(action: onRetry) {
                    Text("Try Again", bundle: #bundle, comment: "Button under a failed Ask answer that asks the same question again.")
                        // **Room to wrap.** At the largest text sizes
                        // "Erneut versuchen" is wider than a phone's column,
                        // and a button can hold its label to one line.
                        // Spelled out with room to wrap, as the nothing-to-ask
                        // button's label is (`AskFirstScreen`), the button
                        // grows instead.
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // The way forward a retryable failure offers, so its
                        // label holds a touch target at any control size: 44
                        // pt, and 60 on visionOS (`AskGrowth.touchTarget`).
                        .frame(minHeight: AskGrowth.touchTarget)
                }
                // A fill and not glass (the type's note says why). On its
                // gray the label is `.primary`, as the card's Not now is
                // (`AskConfirmationCard`): the style draws its words in the
                // tint, and the system blue there falls under 4.5:1. visionOS
                // has no glass on content to keep off, and its
                // `askGlassButton` is `.bordered` already.
                #if os(visionOS)
                .askGlassButton()
                #else
                .buttonStyle(.bordered)
                .tint(.primary)
                #endif
                .accessibilityIdentifier(AskAccessibility.retry)
            }
            if !coaching.isEmpty {
                AskChipRow(
                    starters: coaching, kind: .starter,
                    identifier: AskAccessibility.coaching,
                    surface: .fill, onTap: onCoaching
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **A group with no label of its own.** The message is the `Text`'s,
        // a stop of its own under `.contain`; labelled with the message too,
        // the group said it on the way in and the line said it again.
        .accessibilityElement(children: .contain)
        // In a task, once the line is in the accessibility tree: asked for in
        // the update that inserted it, the focus goes nowhere
        // (`AskThinkingRow`). Not watched under VoiceOver: no simulator runs
        // it.
        .task(id: takesFocus) {
            guard takesFocus else { return }
            lineIsFocused = true
            onFocusTaken()
        }
        // **The focus landing, not the ask.** Written true above, the state
        // reads true only once an assistive technology has moved its focus
        // there: measured in an `NSHostingView` with none running, the write
        // reads back false and this never fires. So a move that misses claims
        // nothing, and the screen is left to say the ending.
        .onChange(of: lineIsFocused) { _, focused in
            if focused { onLineFocused() }
        }
    }

    /// The glyph beside the line: a warning, but for the reader's own stop,
    /// which isn't a failure and gets none.
    ///
    /// From the turn's state, as the thread row reads it
    /// (`AskTurn.isReadersStopBeforeAWord`), and never from the line's words:
    /// a host or a translation whose failure line happened to read the same
    /// as "You stopped this answer" would lose its warning.
    static func glyph(readerStopped: Bool) -> String? {
        readerStopped ? nil : "exclamationmark.triangle"
    }
}

#endif
