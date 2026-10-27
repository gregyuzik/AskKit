#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// An answer's prose.
///
/// **The growing text isn't read aloud, but the element is still there.**
/// VoiceOver re-reading a growing paragraph from the top on every snapshot is
/// unusable, so the value stays empty until the answer lands. Hidden outright,
/// though, the element would leave a VoiceOver reader nothing between their
/// own question and the footer from the first word to the last, after the wait
/// row has gone: nothing saying an answer is on its way.
///
/// So while it is incomplete it is an element that says it is writing, marked
/// `.updatesFrequently` so VoiceOver knows not to hold on to it. The terminal
/// announcement still tells the reader the answer is *ready*.
///
/// **It takes VoiceOver's focus from a wait row that had it as it went**, so a
/// reader who was on the wait row isn't left to wherever the system puts the
/// focus when the first word replaces it (`AskWaitRowHandoff`).
struct AskAnswerProse: View {
    private let attributed: AttributedString
    private let chunks: [AskRevealChunk]
    private let isComplete: Bool
    private let accent: Color
    private let spectrum: AskSpectrum?
    private let takesFocus: Bool
    private let onFocusTaken: () -> Void
    private let onStop: () -> Void
    private let onCopy: () -> Void

    @AccessibilityFocusState private var isFocused: Bool
    /// Under Increase Contrast the caret is the accent's, spectrum or not
    /// (`AskSpectrumLook`).
    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - spectrum: The host's spectrum, which the caret is drawn in.
    ///   - takesFocus: Whether the prose takes VoiceOver's focus now that it
    ///     is there: the wait row had it as the first word replaced it.
    ///   - onFocusTaken: Called once the prose has taken it.
    ///   - onStop: Stops the turn while the prose is being written:
    ///     VoiceOver's Magic Tap on it.
    ///   - onCopy: Copies the answer's words: VoiceOver's Copy answer action
    ///     on it.
    init(
        attributed: AttributedString,
        chunks: [AskRevealChunk],
        isComplete: Bool,
        accent: Color,
        spectrum: AskSpectrum? = nil,
        takesFocus: Bool = false,
        onFocusTaken: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onCopy: @escaping () -> Void = {}
    ) {
        self.attributed = attributed
        self.chunks = chunks
        self.isComplete = isComplete
        self.accent = accent
        self.spectrum = spectrum
        self.takesFocus = takesFocus
        self.onFocusTaken = onFocusTaken
        self.onStop = onStop
        self.onCopy = onCopy
    }

    var body: some View {
        AskStreamingText(
            attributed,
            chunks: chunks,
            showsCaret: !isComplete,
            caret: AskSpectrumLook.of(accent: accent, spectrum: spectrum, contrast: contrast).caret
        )
        .font(.body)
        .lineSpacing(3)
        // **Asked for on every platform, and inert on iOS.** Measured by the
        // demo's `testTheAnswersProseReachesNoMenuOfItsOwn` on an iOS
        // simulator: a long press on a finished answer reaches no selection
        // and no menu, on the combined element or on the prose itself, while
        // the same press on the question bubble brings up its menu. The prose
        // pressed there is a plain `Text` with no renderer, and why the press
        // selects nothing isn't known. macOS and visionOS haven't been
        // measured. It stays because the ask is right: if selection starts
        // working, the answer becomes selectable without anyone having to
        // notice. Until then `AskQuestionBubble`'s "Copy answer" is how a
        // touch takes the answer's words, and VoiceOver has it here too
        // (below).
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isComplete
                ? Text("Answer", bundle: #bundle, comment: "VoiceOver label for the answer text in the Ask thread.")
                : Text("Writing answer", bundle: #bundle, comment: "VoiceOver label for an Ask answer that is still arriving.")
        )
        .accessibilityValue(isComplete ? String(attributed.characters) : "")
        .accessibilityAddTraits(isComplete ? [] : .updatesFrequently)
        .accessibilityTextContentType(.narrative)
        .accessibilityIdentifier(AskAccessibility.answer)
        .accessibilityFocused($isFocused)
        // **The question's Copy answer here too.** A VoiceOver or Switch
        // Control reader who has just heard the answer would otherwise go
        // back up to the question bubble for it (`AskQuestionBubble`).
        .accessibilityActions {
            Button(action: onCopy) { AskQuestionBubble.copyAnswerTitle }
        }
        // **Magic Tap stops the answer being written**, as it does on the wait
        // row (`AskThinkingRow`). Kept on a finished answer, where it does
        // nothing: added and taken away as the answer finished, the action
        // would change the element under VoiceOver's focus at that moment.
        // The Mac has no Magic Tap.
        #if !os(macOS)
        .accessibilityAction(.magicTap) {
            guard !isComplete else { return }
            onStop()
        }
        #endif
        // In a task, once the prose is in the accessibility tree: asked for in
        // the update that inserted it, the focus goes nowhere
        // (`AskThinkingRow`). Not watched under VoiceOver: no simulator runs
        // it.
        .task(id: takesFocus) {
            guard takesFocus else { return }
            isFocused = true
            onFocusTaken()
        }
    }
}

#endif
