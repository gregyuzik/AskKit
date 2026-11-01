#if os(iOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
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
/// **The hint never sizes the field.** One line, whatever its length, so an
/// empty field is one line tall. A narrow column stands in for a large text
/// size or a long locale here, since the Mac's body font doesn't scale.
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

    /// Where a stand-in field says its first baseline is.
    enum Baseline: Sendable {
        /// Where its text's is, as the Mac's field reports, empty or not.
        case text
        /// At its top edge, as UIKit's empty field reports
        /// (`AskComposerHintLayout`).
        case top
        /// At its bottom edge, as SwiftUI reports for a view with no text in
        /// it.
        case bottom
    }

    /// What the field holds: `lines` lines of body text, drawn in no ink,
    /// `inset` inside its frame above and below, and reporting its first
    /// baseline at `baseline`.
    private func field(lines: Int = 1, inset: CGFloat = 0, baseline: Baseline = .text) -> some View {
        Text(verbatim: (1...lines).map(String.init).joined(separator: "\n"))
            .font(.body)
            .lineLimit(AskComposerMetrics.lines)
            .hidden()
            .padding(.vertical, inset)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                switch baseline {
                case .text: dimensions[.firstTextBaseline]
                case .top: 0
                case .bottom: dimensions.height
                }
            }
    }

    private func render(_ placeholder: String?, lines: Int = 1, inset: CGFloat = 0, baseline: Baseline = .text) throws -> NSBitmapImageRep {
        let stack = AskComposerFieldStack(
            placeholder: placeholder,
            style: AskGlassForeground(minimum: AskGlassForeground.text),
            focusField: {},
            field: { field(lines: lines, inset: inset, baseline: baseline) }
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

    /// A hint of any length leaves the empty field one line tall: a long
    /// one ends in an ellipsis rather than wrapping.
    @Test func aHintOfAnyLengthLeavesTheFieldOneLineTall() throws {
        let oneLine = try render(nil).pixelsHigh
        #expect(try render(Self.short).pixelsHigh == oneLine)
        #expect(try render(Self.long).pixelsHigh == oneLine)
        #expect(try render(Self.longest).pixelsHigh == oneLine)
        #expect(try render(nil, lines: 2).pixelsHigh > oneLine)
    }

    /// A truncated hint is still drawn: the ellipsis shortens it, and leaves
    /// ink on its line.
    @Test func aLongHintIsStillDrawn() throws {
        #expect(try firstInk(in: render(Self.long)) != nil)
    }

    /// **The hint sits on the field's first baseline**, where the draft's
    /// first line will be: a field whose text sits lower in its frame takes
    /// the hint down with it, where the field's top would leave it 10 pt
    /// above the text.
    @Test func theHintSitsOnTheFieldsFirstBaseline() throws {
        let level = try #require(firstInk(in: render(Self.short)))
        let lowered = try #require(firstInk(in: render(Self.short, inset: 10)))
        #expect(lowered == level + 10)
    }

    /// **A field that reports no first baseline** keeps the hint on its
    /// line, at its top, and stays one line tall. UIKit's empty field reports
    /// its first baseline at its top (`AskComposerHintLayout`): set on that,
    /// the hint drew a line above the field's on iOS and visionOS, and held
    /// the capsule two lines tall. Set on a view's bottom, the default where
    /// it has no text, the hint sat under the field's line.
    @Test(arguments: [Baseline.top, .bottom])
    func aFieldWithNoBaselineKeepsTheHintOnItsLine(_ baseline: Baseline) throws {
        let oneLine = try render(nil)
        let level = try #require(firstInk(in: render(Self.short)))
        let reported = try render(Self.short, baseline: baseline)
        #expect(reported.pixelsHigh == oneLine.pixelsHigh)
        #expect(firstInk(in: reported) == level)
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

/// Where the hint goes over the field (`AskComposerHintLayout.hintTop`), on
/// the numbers each platform's field reports.
@Suite(.timeLimit(.minutes(1))) struct AskComposerHintLayoutTests {
    /// UIKit's field on iOS reports its first baseline at its top while
    /// empty, and with a word in it 16.33 pt down a 22 pt line, as one line
    /// of the hint has its own: the hint goes at the field's top either way,
    /// where the draft's first baseline will be.
    @Test func onIOSTheHintGoesAtTheFieldsTop() {
        let hint: CGFloat = 49.0 / 3
        #expect(AskComposerHintLayout.hintTop(hintBaseline: hint, fieldBaseline: .leastNormalMagnitude, fieldHeight: 22, inset: 0) == 0)
        #expect(AskComposerHintLayout.hintTop(hintBaseline: hint, fieldBaseline: hint, fieldHeight: 22) == 0)
    }

    /// UIKit's field on visionOS reports its first baseline at its top while
    /// empty, and with a word in it 18 pt down a 26 pt line, where the hint's
    /// is 16: the hint goes 2 pt down, where the draft's will be.
    @Test func onVisionOSTheHintGoesWhereTheDraftsLineWillBe() {
        let empty = AskComposerHintLayout.hintTop(hintBaseline: 16, fieldBaseline: .leastNormalMagnitude, fieldHeight: 26, inset: 2)
        let typed = AskComposerHintLayout.hintTop(hintBaseline: 16, fieldBaseline: 18, fieldHeight: 26)
        #expect(empty == 2)
        #expect(empty == typed)
    }

    /// The Mac's field reports its baseline 13 pt down a 16 pt line, empty
    /// or not, as the hint's is.
    @Test func onTheMacTheHintGoesOnTheFieldsBaseline() {
        #expect(AskComposerHintLayout.hintTop(hintBaseline: 13, fieldBaseline: 13, fieldHeight: 16) == 0)
    }

    /// A field whose text sits lower in its frame takes the hint down by as
    /// much.
    @Test func aLowerBaselineTakesTheHintDown() {
        #expect(AskComposerHintLayout.hintTop(hintBaseline: 13, fieldBaseline: 23, fieldHeight: 36) == 10)
    }

    /// A baseline within a point of the field's top, or on its bottom edge,
    /// is none, and the hint goes down by the inset.
    @Test func aBaselineAtAnEdgeIsNone() {
        for reported: CGFloat in [-4, 0, .leastNormalMagnitude, 0.5, 16, 20] {
            #expect(AskComposerHintLayout.hintTop(hintBaseline: 13, fieldBaseline: reported, fieldHeight: 16, inset: 0) == 0)
            #expect(AskComposerHintLayout.hintTop(hintBaseline: 13, fieldBaseline: reported, fieldHeight: 16, inset: 2) == 2)
        }
    }
}

#if os(iOS) || os(visionOS)
/// The composer's stack around UIKit's own text field, the field
/// `AskComposerPlaceholderTests` stands in for on the Mac, measured in a
/// hosting controller. Height alone: the hint's ink can't be read here,
/// since `ImageRenderer` draws no UIKit view.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskComposerUIKitFieldTests {
    private func height(hint: String?, draft: String = "") -> CGFloat {
        let stack = AskComposerFieldStack(
            placeholder: hint,
            style: AskGlassForeground(minimum: AskGlassForeground.text),
            focusField: {},
            field: {
                TextField("", text: .constant(draft), axis: .vertical)
                    .lineLimit(AskComposerMetrics.lines)
                    .textFieldStyle(.plain)
                    .font(.body)
            }
        )
        return UIHostingController(rootView: stack)
            .sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// **The hint leaves the empty field one line tall.** UIKit's empty
    /// field reports its first baseline at its top (`AskComposerHintLayout`),
    /// and set on that, the hint drew a line above the field's: the stack
    /// was 38.33 pt tall, not 22, on the iOS 27.2 simulator.
    @Test func theHintLeavesTheEmptyFieldOneLineTall() {
        let oneLine = height(hint: nil)
        #expect(height(hint: "Ask about your things") == oneLine)
        #expect(height(hint: String(repeating: "Ask about your things. ", count: 6)) == oneLine)
        #expect(height(hint: nil, draft: "One\nTwo") > oneLine)
    }
}
#endif

#endif
