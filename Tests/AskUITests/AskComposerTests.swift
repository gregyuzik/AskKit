#if os(iOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#endif
import SwiftUI
import Testing

@testable import AskUI

/// The composer's field under a hardware keyboard: what return does.
@Suite(.timeLimit(.minutes(1))) struct AskComposerTests {
    /// Plain return sends a question, and shift-return keeps its newline
    /// whatever else is going on.
    @Test func returnSendsAndShiftReturnKeepsItsNewline() {
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: false, isComposing: false) == .send)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: false, isComposing: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "", isThinking: false, isComposing: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: true, isComposing: false) == .newline)
    }

    /// **Taken, not let through.** Let through, a return the composer can't
    /// send would type a newline: into an empty field that is a draft of one
    /// blank line, which the store reads as a question begun and warms a
    /// session for, and under a turn in flight a line break the reader never
    /// meant to type.
    @Test func returnWithNothingToSendTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: false, isComposing: false) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: " \n ", isThinking: false, isComposing: false) == .nothing)
    }

    @Test func returnWhileATurnIsInFlightTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: true, isComposing: false) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: true, isComposing: false) == .nothing)
    }

    /// The handler takes the key to send or to type nothing, and lets it
    /// through to the field for Shift's newline.
    @Test func sendingAndNothingTakeTheKeyAndANewlineLetsItThrough() {
        #expect(AskComposerReturn.send.result == .handled)
        #expect(AskComposerReturn.nothing.result == .handled)
        #expect(AskComposerReturn.newline.result == .ignored)
    }
}

/// A hardware Return while an input method is composing in the field: typing
/// Japanese, Chinese or Korean, the Return that confirms the conversion
/// (`AskMarkedText`).
@Suite(.timeLimit(.minutes(1))) struct AskComposerCompositionTests {
    /// **Composing beats sending.** Taken to send, the Return never reaches
    /// the input method, and the question goes half composed while the
    /// conversion is left in the field.
    @Test func aReturnWhileComposingConfirmsRatherThanSends() {
        let route = AskComposerReturn.of(shift: false, draft: "日本の", isThinking: false, isComposing: true)
        #expect(route == .composing)
        #expect(route.result == .ignored)
    }

    /// **Composing beats nothing to send**, whatever the draft holds. Taken
    /// as nothing to send, the Return that confirms a conversion would be
    /// swallowed, and the conversion couldn't be confirmed from the keyboard.
    /// On iOS SwiftUI's draft holds the marked text too (measured on the 27.2
    /// simulator), so this is the order pinned for a draft that doesn't.
    @Test func aReturnWhileComposingInAnEmptyFieldIsNotSwallowed() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: false, isComposing: true) == .composing)
        #expect(AskComposerReturn.of(shift: false, draft: " ", isThinking: false, isComposing: true) == .composing)
    }

    /// **Composing beats a turn in flight**, which takes a Return so it types
    /// nothing, and would take the one that confirms the next question's
    /// first word.
    @Test func aReturnWhileComposingUnderATurnInFlightIsNotSwallowed() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: true, isComposing: true) == .composing)
        #expect(AskComposerReturn.of(shift: false, draft: "日本の", isThinking: true, isComposing: true) == .composing)
    }

    /// Shift-Return is let through whether or not anything is being
    /// composed: to the field for its newline, or to the input method.
    @Test func shiftReturnIsLetThroughWhileComposing() {
        #expect(AskComposerReturn.of(shift: true, draft: "日本の", isThinking: false, isComposing: true).result == .ignored)
        #expect(AskComposerReturn.of(shift: true, draft: "日本の", isThinking: false, isComposing: false) == .newline)
    }

    /// Once the conversion is confirmed, the next Return sends what it
    /// confirmed, as it would have without an input method.
    @Test func theReturnAfterTheConversionSends() {
        #expect(AskComposerReturn.of(shift: false, draft: "日本の首都は", isThinking: false, isComposing: false) == .send)
    }
}

/// A color that follows Increase Contrast, as an asset color with a High
/// Contrast variant does: `standard`, and `increased` where the environment
/// asks for more contrast.
nonisolated private struct AskContrastVariantColor: ShapeStyle, Hashable {
    let standard: Color.Resolved
    let increased: Color.Resolved

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        environment.colorSchemeContrast == .increased ? increased : standard
    }
}

/// How strongly the composer's capsule wears the host's accent.
@Suite(.timeLimit(.minutes(1))) struct AskComposerTintTests {
    /// **Worked out on the accent the capsule wears.** An accent with a
    /// High Contrast variant, the system blue in dark mode (#0091FF) and
    /// yellow (#FFD60A) under Increase Contrast: the capsule wears the yellow
    /// there, and at half strength white words on it fall to 3.86:1, so it
    /// gives way to 0.43. Resolved in an environment of its own, given the
    /// appearance and nothing else, the accent was the blue, which keeps half.
    @Test func theCapsulesTintIsWorkedOutOnTheVariantItWears() {
        #if !os(visionOS)
        let accent = Color(AskContrastVariantColor(
            standard: Color.Resolved(red: 0, green: 145 / 255, blue: 1),
            increased: Color.Resolved(red: 1, green: 214 / 255, blue: 10 / 255)
        ))
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        #expect(AskComposer.tint(for: accent, in: environment) == AskComposer.tint)
        // `colorSchemeContrast` has no public setter: the system sets it.
        environment._colorSchemeContrast = .increased
        #expect(AskComposer.tint(for: accent, in: environment) == 0.43)
        #endif
    }
}

#if os(macOS)
/// The composer's placeholder, the host's hint, beside its field, read off a
/// render on white, one point to a pixel.
///
/// **The hint sizes the field.** Laid over the field, it was offered the
/// field's one line and ended in an ellipsis at the accessibility sizes,
/// however many lines it could wrap to. A narrow column stands in for a large
/// text size here, since the Mac's body font doesn't scale.
///
/// **A stand-in for the text field**, lines of text drawn in no ink: a
/// `TextField` drawn in this process brings up `NSApplication`, after which
/// `ImageRenderer` draws the system's buttons too, which
/// `AskFirstScreenFoldTests` relies on it not doing.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskComposerPlaceholderTests {
    private static let short = "Ask"
    /// Two or three lines 120 pt wide.
    private static let long = "Ask about the things you keep here"
    /// More lines than the field grows to.
    private static let longest = String(repeating: "Ask about the things you keep here. ", count: 6)

    /// What the field holds: `lines` lines of body text, drawn in no ink,
    /// `inset` under the top of its frame.
    private func field(lines: Int = 1, inset: CGFloat = 0) -> some View {
        Text(verbatim: (1...lines).map(String.init).joined(separator: "\n"))
            .font(.body)
            .lineLimit(AskComposerMetrics.lines)
            .hidden()
            .padding(.top, inset)
    }

    private func render(_ placeholder: String?, lines: Int = 1, inset: CGFloat = 0) throws -> NSBitmapImageRep {
        let stack = AskComposerFieldStack(
            placeholder: placeholder,
            style: AskGlassForeground(minimum: AskGlassForeground.text),
            focusField: {},
            field: { field(lines: lines, inset: inset) }
        )
        let renderer = ImageRenderer(content: stack.foregroundStyle(.black).background(.white))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 120, height: nil)
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// The first pixel row from the top with any of the hint's ink on it.
    private func firstInk(in image: NSBitmapImageRep) -> Int? {
        (0..<image.pixelsHigh).first { y in
            (0..<image.pixelsWide).contains { x in
                (image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.8
            }
        }
    }

    /// A hint longer than a line wraps, and the field grows to hold it. A
    /// hint of one line, or none, leaves the field its own size.
    @Test func aLongHintWrapsAndTheFieldGrowsWithIt() throws {
        #expect(try render(Self.long).pixelsHigh > render(Self.short).pixelsHigh)
        #expect(try render(Self.short).pixelsHigh == render(nil).pixelsHigh)
    }

    /// As many lines as the field grows to, and no more: a hint too long for
    /// four is as tall as four lines of draft.
    @Test func theHintWrapsToTheFieldsFourLinesAndNoMore() throws {
        let fourLines = try render(nil, lines: 4).pixelsHigh
        #expect(try render(Self.longest).pixelsHigh == fourLines)
        #expect(try render(nil, lines: 6).pixelsHigh == fourLines)
    }

    /// **The hint's first line sits on the field's first baseline**, so it
    /// is where the draft's first line will be: a field whose text sits
    /// lower in its frame takes the hint down with it.
    @Test func theHintSitsOnTheFieldsFirstBaseline() throws {
        let level = try #require(firstInk(in: render(Self.short)))
        let lowered = try #require(firstInk(in: render(Self.short, inset: 10)))
        #expect(lowered == level + 10)
    }
}
#endif

#if os(macOS)
/// What the composer hands the menu bar: a value that changes only when Send
/// or Stop turns on or off, so `AskCommands` isn't rebuilt on every keystroke.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskComposerCommandTests {
    /// The composer builds a new value on every pass of its body, with new
    /// closures each time. Handed to the same actions object, it compares
    /// equal, and a call runs the closures handed in last.
    @Test func aNewPassWithTheSameFlagsIsNoChange() {
        let actions = AskComposerActions()
        var sent = ""
        let first = AskComposerCommand(sends: true, stops: false, actions: actions.holding(send: { sent = "first" }, stop: {}))
        let second = AskComposerCommand(sends: true, stops: false, actions: actions.holding(send: { sent = "second" }, stop: {}))
        #expect(first == second)
        first.send()
        #expect(sent == "second")
    }

    /// A flag turning is a change, and so is another composer's object.
    @Test func aFlagOrAnotherComposerIsAChange() {
        let actions = AskComposerActions()
        let sending = AskComposerCommand(sends: true, stops: false, actions: actions)
        #expect(sending != AskComposerCommand(sends: false, stops: false, actions: actions))
        #expect(sending != AskComposerCommand(sends: true, stops: true, actions: actions))
        #expect(sending != AskComposerCommand(sends: true, stops: false, actions: AskComposerActions()))
    }
}
#endif

#endif
