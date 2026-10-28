#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The composer's field under a hardware keyboard: what return does.
@Suite(.timeLimit(.minutes(1))) struct AskComposerTests {
    /// Plain return sends a question, and shift-return keeps its newline
    /// whatever else is going on.
    @Test func returnSendsAndShiftReturnKeepsItsNewline() {
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: false) == .send)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "", isThinking: false) == .newline)
        #expect(AskComposerReturn.of(shift: true, draft: "What's the oldest?", isThinking: true) == .newline)
    }

    /// **Taken, not let through.** Let through, a return the composer can't
    /// send would type a newline: into an empty field that is a draft of one
    /// blank line, which the store reads as a question begun and warms a
    /// session for, and under a turn in flight a line break the reader never
    /// meant to type.
    @Test func returnWithNothingToSendTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: false) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: " \n ", isThinking: false) == .nothing)
    }

    @Test func returnWhileATurnIsInFlightTypesNothing() {
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: true) == .nothing)
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: true) == .nothing)
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
/// The composer's placeholder, the host's hint, read off a render: how tall
/// the composer is with it.
///
/// **The hint sizes the field.** Laid over the field, it was offered the
/// field's one line and ended in an ellipsis at the accessibility sizes,
/// however many lines it could wrap to. A narrow composer stands in for a
/// large text size here: the Mac's body font doesn't scale.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskComposerPlaceholderTests {
    private struct Composer: View {
        let draft: String
        let placeholder: String
        @FocusState private var isFocused: Bool

        init(draft: String, placeholder: String) {
            self.draft = draft
            self.placeholder = placeholder
        }

        var body: some View {
            AskComposer(
                draft: .constant(draft), isFocused: $isFocused, placeholder: placeholder,
                accent: .blue, isThinking: false, onSend: {}, onStop: {}
            )
        }
    }

    private static let short = "Ask"
    /// Two or three lines in the field of a composer 200 pt wide.
    private static let long = "Ask about the things you keep here, and when"
    /// More lines than the field grows to.
    private static let longest = String(repeating: "Ask about the things you keep here. ", count: 6)

    /// The composer's height, 200 pt wide.
    private func height(placeholder: String, draft: String = "") throws -> Int {
        let renderer = ImageRenderer(content: Composer(draft: draft, placeholder: placeholder))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 200, height: nil)
        return try #require(renderer.cgImage).height
    }

    /// A hint longer than a line wraps, and the composer grows to hold it.
    @Test func aLongHintWrapsAndTheComposerGrowsWithIt() throws {
        #expect(try height(placeholder: Self.long) > height(placeholder: Self.short))
    }

    /// As many lines as the field grows to, and no more: a hint too long for
    /// four makes the composer as tall as four lines of draft do, and a
    /// longer draft than that doesn't make it taller.
    @Test func theHintWrapsToTheFieldsFourLinesAndNoMore() throws {
        let fourLines = try height(placeholder: Self.short, draft: "1\n2\n3\n4")
        #expect(try height(placeholder: Self.longest) == fourLines)
        #expect(try height(placeholder: Self.short, draft: "1\n2\n3\n4\n5\n6") == fourLines)
    }

    /// The hint goes with the first character typed, and the field is the
    /// draft's size again.
    @Test func aDraftTakesTheHintsRoom() throws {
        #expect(try height(placeholder: Self.long, draft: "Hi") == height(placeholder: Self.short))
        #expect(try height(placeholder: Self.longest, draft: "Hi") == height(placeholder: Self.short, draft: "Hi"))
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
