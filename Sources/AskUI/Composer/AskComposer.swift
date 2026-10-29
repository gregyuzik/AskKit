#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// The Ask composer: a text field and its circle on a glass capsule, tinted
/// with the host's accent at up to half strength, lighter than the question
/// bubble's fill of it, so the place you type and the thing you typed read as
/// one.
/// `AskScreen` draws one in its bottom bar.
///
/// The field grows from one line to four, and the capsule with it, its
/// corners keeping the radius they have at one line
/// (`AskComposerMetrics.corner`). The circle at its trailing end
/// sends, and while a turn is in flight it stops: the same spot, the same
/// circle, one glyph turning into the other. With nothing to send it puts the
/// reader in the field, or, on iOS and visionOS with the field focused, puts
/// the keyboard away. At most one accessory button sits before the field
/// (`AskComposerAccessory`).
///
/// **Keys.** A hardware Return sends, Shift-Return inserts a newline, and a
/// Return with nothing to send, or with a turn in flight, types nothing. A
/// Return while an input method is composing, typing Japanese, Chinese or
/// Korean, goes to the input method to confirm its conversion, and sends
/// nothing: on the Mac, and on iOS in `AskScreen`.
/// ⌘Return presses the circle; while a turn is in flight the shortcut is ⌘.
/// instead, which stops it. The software keyboard's return key inserts a
/// newline.
///
/// **Isolation.** A composer is main-actor isolated, as the views it goes in
/// are: build it on the main actor. That isolation makes it `Sendable`, so
/// once built it can be held anywhere, which `AskCrossPostureTests` pins.
public struct AskComposer: View {
    private let placeholder: String
    private let accent: Color
    /// What the send circle wears in place of the accent: `AskScreen`'s
    /// spectrum, which a host sets on the screen (`AskSpectrum`).
    private let spectrum: AskSpectrum?
    private let isThinking: Bool
    private let acceptsAttachments: Bool
    private let onSend: () -> Void
    private let onStop: () -> Void
    private let onAttach: (() -> Void)?
    private let accessory: AskComposerAccessory?

    @Binding private var draft: String
    @FocusState.Binding private var isFocused: Bool
    /// Where `AskScreen` wants VoiceOver's focus (`AskVoiceOverTarget`): the
    /// field after Edit & Resend, or after New Chat where the first screen has
    /// no headline, which the field takes when it can.
    @Environment(\.askVoiceOverTarget) private var voiceOverTarget
    /// VoiceOver's focus on the field.
    @AccessibilityFocusState private var fieldHasVoiceOver: Bool
    /// Whether `AskScreen` has this composer resting in a host's slot
    /// (`askComposerRests`), where both buttons hide by name.
    @Environment(\.askComposerRests) private var rests
    /// What the accent is resolved in to choose the capsule's tint
    /// (`capsuleTint`): the whole environment, not the appearance alone, since
    /// an asset color's variants follow Increase Contrast as well.
    @Environment(\.self) private var environment
    /// Whether the reader has Button Shapes on, which rings the accessory
    /// button's glyph (`AskBareButtonShape`).
    @Environment(\.accessibilityShowBorders) private var showsBorders
    #if os(iOS)
    /// The window `AskScreen` is in, where the chevron puts the keyboard away
    /// and a hardware Return asks whether an input method is composing
    /// (`askScreenWindow`, `isComposing`): nil for a composer a host draws
    /// outside the screen.
    @Environment(\.askScreenWindow) private var screenWindow
    #endif
    #if os(macOS)
    /// What the menu bar's Send and Stop call (`AskComposerCommand`): one
    /// object for the composer's life, so the value handed up compares equal
    /// until what it says changes.
    @State private var commandActions = AskComposerActions()
    #endif

    /// Creates a composer.
    ///
    /// The composer never clears `draft`: `onSend` does what sending means,
    /// such as asking the question and emptying the field.
    ///
    /// - Parameters:
    ///   - draft: The text in the field.
    ///   - isFocused: Whether the field has focus. The circle focuses the
    ///     field when there is nothing to send, and on iOS and visionOS takes
    ///     the focus of a focused, empty field away.
    ///   - placeholder: What the field shows while `draft` is empty, on one
    ///     line, ending in an ellipsis where it is longer than the field is
    ///     wide. Only a draft grows the capsule.
    ///   - accent: The capsule's tint, at up to half strength (less on a
    ///     light accent in dark mode, where the draft's words would fall under
    ///     4.5:1 at half), and the circle's fill.
    ///   - isThinking: Whether a turn is in flight. The circle then stops, the
    ///     accessory button is disabled, and Return types nothing.
    ///   - acceptsAttachments: Whether the domain takes photos. With
    ///     `onAttach`, it puts the photo button before the field, unless
    ///     `accessory` is set.
    ///   - onSend: Sends the draft. Called from the circle, a hardware Return
    ///     or ⌘Return, and only while the draft holds more than whitespace and
    ///     no turn is in flight.
    ///   - onStop: Stops the turn in flight, from the circle or ⌘.
    ///   - onAttach: What the photo button does, such as presenting a picker.
    ///     Unused while `accessory` is set.
    ///   - accessory: The accessory button before the field, in place of the
    ///     photo button. It shows whatever `acceptsAttachments` says, so the
    ///     photo button passed here (`AskComposerAccessory.photo(_:)`) shows
    ///     for a domain that takes no photos too: pass `onAttach` instead for
    ///     one that shows only where the domain takes them.
    public init(
        draft: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        placeholder: String,
        accent: Color,
        isThinking: Bool,
        acceptsAttachments: Bool = false,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onAttach: (() -> Void)? = nil,
        accessory: AskComposerAccessory? = nil
    ) {
        self.init(
            draft: draft, isFocused: isFocused, placeholder: placeholder,
            accent: accent, spectrum: nil, isThinking: isThinking,
            acceptsAttachments: acceptsAttachments, onSend: onSend, onStop: onStop,
            onAttach: onAttach, accessory: accessory
        )
    }

    /// The composer `AskScreen` draws, its send circle in the screen's
    /// spectrum where the host set one.
    init(
        draft: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        placeholder: String,
        accent: Color,
        spectrum: AskSpectrum?,
        isThinking: Bool,
        acceptsAttachments: Bool,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onAttach: (() -> Void)?,
        accessory: AskComposerAccessory?
    ) {
        _draft = draft
        _isFocused = isFocused
        self.placeholder = placeholder
        self.accent = accent
        self.spectrum = spectrum
        self.isThinking = isThinking
        self.acceptsAttachments = acceptsAttachments
        self.onSend = onSend
        self.onStop = onStop
        self.onAttach = onAttach
        self.accessory = accessory
    }

    /// The button before the field, if any (`AskComposerAccessory.leading`).
    private var leadingAccessory: AskComposerAccessory? {
        .leading(accessory, acceptsAttachments: acceptsAttachments, onAttach: onAttach)
    }

    /// The widest glyph a circle shows, as the body font scales it
    /// (`AskComposerMetrics`): the circles and their targets grow by what it
    /// grows.
    @ScaledMetric(relativeTo: .body) private var widestGlyph: CGFloat = AskComposerMetrics.widestGlyph

    private var circle: CGFloat { AskComposerMetrics.circle(widestGlyph: widestGlyph) }
    private var target: CGFloat { AskComposerMetrics.target(widestGlyph: widestGlyph) }
    private var corner: CGFloat { AskComposerMetrics.corner(widestGlyph: widestGlyph) }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether an input method is composing in the field (`AskMarkedText`),
    /// asked as a hardware Return comes in: on iOS in the screen's window,
    /// so never for a composer a host draws outside the screen; on the Mac
    /// of the active input context; on visionOS not at all.
    private var isComposing: Bool {
        #if os(iOS)
        AskMarkedText.isComposing(in: screenWindow?.window)
        #elseif os(macOS)
        AskMarkedText.isComposing
        #else
        false
        #endif
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if let leadingAccessory {
                accessoryButton(leadingAccessory)
            }
            field
            sendButton
        }
        // The field takes the screen's request for VoiceOver's focus once it
        // is in the tree to take it, and clears it. The screen hands no request
        // to a composer resting in a host's slot, hidden from VoiceOver, so it
        // waits until the composer comes up.
        .task(id: voiceOverTarget?.wrappedValue == .field) {
            guard let voiceOverTarget, voiceOverTarget.wrappedValue == .field else { return }
            fieldHasVoiceOver = true
            voiceOverTarget.wrappedValue = nil
        }
        // Keyed on the button being there, not on `acceptsAttachments`: a
        // domain that accepts photos in a host that passes no handler draws no
        // button, and the field would sit jammed against the capsule's edge.
        .padding(.leading, leadingAccessory == nil ? 18 : AskComposerMetrics.edge)
        .padding(.trailing, AskComposerMetrics.edge)
        .padding(.vertical, AskComposerMetrics.edge)
        // A capsule at one line, and as the field grows, a rectangle whose
        // corners keep that radius, concentric with the circles at the
        // bottom corners (`AskComposerMetrics.corner`).
        .askGlass(.tint(capsuleTint), in: .rect(cornerRadius: corner, style: .circular))
        #if os(macOS)
        // What the menu bar's Send and Stop act on (`AskCommands`), for the
        // window this composer is in. The same actions object every pass,
        // holding this pass's closures, so the value changes only when
        // `sends` or `stops` does, not with every character typed.
        .focusedSceneValue(\.askComposer, AskComposerCommand(
            sends: !isThinking && !trimmed.isEmpty,
            stops: isThinking,
            actions: commandActions.holding(send: onSend, stop: onStop)
        ))
        #endif
    }

    /// The most the capsule wears the accent: half, lighter than the question
    /// bubble's fill of it.
    static let tint = 0.5

    /// The accent as the capsule wears it, at `tint(for:in:)`.
    private var capsuleTint: Color {
        accent.opacity(Self.tint(for: accent, in: environment))
    }

    /// How strongly the capsule wears `accent` where it is drawn:
    /// `tint(for:isLight:)` on the accent as `environment` resolves it.
    ///
    /// **Resolved where it is drawn, not in an environment of its own.** An
    /// asset accent with a High Contrast variant resolves to it only in an
    /// environment asking for more contrast (measured on the Mac, with an
    /// asset catalog's color). Resolved in an empty environment given only
    /// the appearance, the standard variant is the one measured, and under
    /// Increase Contrast the capsule wears the other at the strength worked
    /// out for it.
    static func tint(for accent: Color, in environment: EnvironmentValues) -> Double {
        tint(for: AskContrast.RGB(accent.resolve(in: environment)), isLight: environment.colorScheme == .light)
    }

    /// How strongly the capsule wears `accent`: `tint`, or less where the
    /// draft would fall under 4.5:1 on it.
    ///
    /// **The draft is `.primary`, and stays so.** Text on glass is
    /// hierarchical (`AskGlassForeground`), so where white words fall short on
    /// a light accent's tint in dark mode, the tint gives way rather than the
    /// words turning black. Estimated on the glass's base
    /// (`AskContrast.ground(isLight:tint:)`), white at half strength is
    /// 3.86:1 on yellow (#FFD60A), 4.03:1 on mint (#63E6E2) and 4.42:1 on cyan
    /// (#64D2FF); their tints go to 0.43, 0.45 and 0.49. Every dark accent
    /// keeps half, as every accent does in light mode, where black on the
    /// lightest tint is over 10:1. The placeholder, held to 4.5:1 as well, is
    /// `.secondary` only where that clears it, so it holds on the same tint.
    /// visionOS keeps half: its tint is a faint fill on the window's glass
    /// (`AskGlass.visionTintOpacity`), and its words stay `.secondary`.
    static func tint(for accent: AskContrast.RGB, isLight: Bool) -> Double {
        #if os(visionOS)
        tint
        #else
        AskContrast.tintStrength(accent, ceiling: tint, isLight: isLight, minimum: AskGlassForeground.text)
        #endif
    }

    private func accessoryButton(_ accessory: AskComposerAccessory) -> some View {
        Button(action: accessory.action) {
            Image(systemName: accessory.systemImage)
                .font(.body)
                .frame(width: circle, height: circle)
                // A bare glyph, so under Button Shapes a ring the send
                // circle's size (`AskBareButtonShape`).
                .askButtonShapeRing(.circle, showsBorders: showsBorders)
                .frame(width: target, height: target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .askHoverEffect(in: .circle)
        // A glyph that says what it does: 3:1 on the capsule's tint, which
        // `.secondary` falls under on a light ground (`AskGlassForeground`).
        .foregroundStyle(AskGlassForeground(tint: capsuleTint, minimum: AskGlassForeground.glyph))
        .disabled(isThinking)
        // Named in words the host supplies, since VoiceOver would otherwise
        // read out the name of the glyph, and on the Mac shown in those words
        // as the pointer rests on it.
        .accessibilityLabel(accessory.label)
        .askHelp(accessory.label)
        .accessibilityIdentifier(accessory.identifier)
        .accessibilityShowsLargeContentViewer()
        // Hidden by name at rest, as the send is (`sendButton` says why).
        .askAccessibilityHidden(while: rests)
    }

    private var field: some View {
        AskComposerFieldStack(
            placeholder: draft.isEmpty ? placeholder : nil,
            // **Text a reader has to read, so 4.5:1 on the capsule's tint.**
            // `.secondary` comes to 2.66:1 there in light mode, estimated as
            // a flat blend of the system blue (#0088FF) at half strength over
            // white, and is 3.44:1 even on white (`AskGlassForeground`).
            style: AskGlassForeground(tint: capsuleTint, minimum: AskGlassForeground.text),
            focusField: { isFocused = true },
            field: { textField }
        )
        // A fixed inset, not one scaled with the text: the target grows
        // only by what the glyph grows (`AskComposerMetrics`), and an inset
        // scaled in proportion made one line of the largest text 132 pt
        // tall, a field taller than the button it was padded to match.
        .padding(.vertical, AskComposerMetrics.fieldInset)
        // **The row is bottom-aligned, so a field shorter than the button
        // sinks below the capsule's center.** Bottom is right for the
        // field that has grown: the circle stays with the last line, the
        // way Messages keeps it. It is wrong for the single line, which is
        // every line most readers ever type: measured on macOS, a 16 pt
        // field in a 44 pt row put the text 19 pt from the capsule's top
        // and 13 pt from its bottom. At least as tall as the button, the
        // one line centers, and once the field is taller than that, the
        // frame passes through and the bottom alignment has its row back.
        .frame(minHeight: target)
    }

    private var textField: some View {
        // An empty label and a placeholder drawn by hand
        // (`AskComposerFieldStack`):
        // SwiftUI draws a `prompt:` in its own placeholder color and discards
        // any style attached to it, and that color measures about 1.3:1 on
        // tinted glass.
        TextField("", text: $draft, axis: .vertical)
            .lineLimit(AskComposerMetrics.lines)
            .textFieldStyle(.plain)
            .font(.body)
            #if os(iOS) || os(visionOS)
            .textInputAutocapitalization(.sentences)
            #endif
            .focused($isFocused)
            .accessibilityFocused($fieldHasVoiceOver)
            // **No `.submitLabel(.send)`, and no send on a typed newline.**
            // The software keyboard's return key reads "return" and does what
            // it says, the way Messages does with a growing field, and the
            // arrow is the send. Why not `.submitLabel(.send)`:
            // ARCHITECTURE.md, Rejected designs.
            //
            // A hardware Return is a different gesture, and does send: plain
            // sends, and Shift keeps its newline. `onKeyPress` never fires for
            // a software keyboard, so the software keyboard is untouched: test
            // this with a hardware keyboard, since with the software one it
            // seems to do nothing.
            //
            // **A plain Return that can't send is taken, not let through.**
            // Let through, it types a newline: in an empty field that is a
            // draft of one blank line, which the store takes for a question
            // begun and warms a session for.
            //
            // **A held Return repeats, and a repeat is a phase of its own**
            // (`AskComposerReturn.phases`). Handled on the press alone, the
            // repeats went through to the field and typed newlines into it,
            // the same blank draft. A repeat is handled as the press it
            // repeats: a send has emptied the draft by then, so its repeats
            // are taken as nothing to send.
            //
            // **A Return while an input method is composing is let through to
            // it.** Typing Japanese, Chinese or Korean on a hardware keyboard,
            // the Return that confirms a conversion should confirm it and
            // send nothing. The draft holds the marked text as well
            // (measured on the iOS 27.2 simulator), so a Return that sent
            // there would send the reading as typed, unconverted. So the
            // handler asks for the field's marked text (`isComposing`) before
            // anything else: before a send, and before nothing to send and a
            // turn in flight, which would swallow it (`AskComposerReturn.of`).
            // Not yet watched with an input method: whether it takes the
            // Return before `onKeyPress` hears it, which would make this check
            // moot rather than wrong.
            .onKeyPress(.return, phases: AskComposerReturn.phases) { press in
                let route = AskComposerReturn.of(
                    shift: press.modifiers.contains(.shift), draft: draft,
                    isThinking: isThinking, isComposing: isComposing
                )
                if route == .send { onSend() }
                return route.result
            }
            .accessibilityLabel(AskComposerWords.yourQuestion)
            // The placeholder has no element of its own
            // (`AskComposerFieldStack`), so its words, the host's hint about
            // what to ask, reach VoiceOver here.
            .accessibilityHint(Text(placeholder))
            // Voice Control answers to the words in the field, the draft or
            // the placeholder, as well as to "Your question" (`AskSpokenName`).
            .accessibilityInputLabels(
                AskSpokenName.inputLabels(showing: draft.isEmpty ? placeholder : draft, named: AskComposerWords.yourQuestion)
            )
            .accessibilityIdentifier(AskAccessibility.field)
    }

    /// Whether the button's job right now is to put the keyboard away.
    ///
    /// The one state where an arrow means nothing: the field has focus and
    /// there is nothing in it to send, so the circle puts the keyboard away.
    /// The bar's Done handles the other half, a field with a draft in it,
    /// where this button is a send and must stay one. Never on the Mac, where
    /// focus is the normal resting state and there is no keyboard to put away.
    private var dismissesKeyboard: Bool {
        #if os(iOS) || os(visionOS)
        isFocused && trimmed.isEmpty
        #else
        false
        #endif
    }

    private var glyphName: String {
        if isThinking { return "stop.fill" }
        return dismissesKeyboard ? "keyboard.chevron.compact.down" : "arrow.up"
    }

    /// What VoiceOver calls the button in each of its four states, one for
    /// each thing a tap on it does (`sendButton`). The smoke suite reads this
    /// label to know which state the button is in.
    private var buttonLabel: Text {
        Self.buttonLabel(isThinking: isThinking, dismissesKeyboard: dismissesKeyboard, hasQuestion: !trimmed.isEmpty)
    }

    /// `buttonLabel` for each state, apart from the view so the words, which
    /// are the Mac's help tag too, can be pinned (`AskBareButtonTests`).
    static func buttonLabel(isThinking: Bool, dismissesKeyboard: Bool, hasQuestion: Bool) -> Text {
        if isThinking {
            return Text("Cancel", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button while a question is being answered — it stops the turn.")
        }
        if dismissesKeyboard {
            return Text("Dismiss keyboard", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button while the field is focused and empty — it puts the keyboard away.")
        }
        // Nothing to send, so the arrow puts the reader in the field. Called
        // Send, it would promise a question the tap never asks.
        if !hasQuestion {
            return Text("Write a question", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button while the field is empty — it takes the reader to the field to type a question, and sends nothing.")
        }
        return Text("Send", bundle: #bundle, comment: "VoiceOver label for the Ask composer's send button; and the Mac menu item, shortcut ⌘↩, that sends the question.")
    }

    /// Send, or stop, or put the keyboard away. An empty field sends nothing:
    /// unfocused, the tap says "I want to ask", and the keyboard comes up
    /// rather than a dimmed button doing nothing; focused, the tap says the
    /// opposite, and the keyboard goes.
    private var sendButton: some View {
        Button {
            if isThinking {
                onStop()
            } else if trimmed.isEmpty {
                // The action follows the glyph. An arrow focuses; the chevron
                // dismisses, through `AskKeyboard` rather than by writing the
                // binding (`AskKeyboard` says why), on iOS in the screen's own
                // window, as the screen's Done does. On the Mac the glyph is
                // always an arrow, so a click on an empty field only ever puts
                // the cursor in it, where a `toggle()` would take a Mac
                // reader's focus away instead.
                if dismissesKeyboard {
                    #if os(iOS)
                    AskKeyboard.putAway($isFocused, in: screenWindow)
                    #else
                    AskKeyboard.putAway($isFocused)
                    #endif
                } else {
                    isFocused = true
                }
            } else {
                onSend()
            }
        } label: {
            Image(systemName: glyphName)
                .font(.body.weight(.bold))
                // White, or black on an accent or a spectrum too light to
                // hold white at 3:1 (`AskOnAccent`, `AskSendGlyph`).
                .foregroundStyle(AskSendGlyph(accent: accent, spectrum: spectrum))
                .frame(width: circle, height: circle)
                // A fill, not glass: the composer's capsule is already glass,
                // and glass can't sample glass. The accent, or the spectrum's
                // gradient from corner to corner (`AskSendFill`).
                .background(AskSendFill(accent: accent, spectrum: spectrum), in: .circle)
                .contentTransition(.symbolEffect(.replace))
                // The circle grows by what its widest glyph grows from 34 pt,
                // and the hit region by the same from 44 (28 and 32 on the
                // Mac, and a 60 pt region on visionOS), so the glyph never
                // outgrows the fill behind it (`AskComposerMetrics`).
                .frame(width: target, height: target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // Lit in the hit region's circle, round the fill. The fill is the
        // button's shape already, so Button Shapes adds none.
        .askHoverEffect(in: .circle)
        .accessibilityShowsLargeContentViewer()
        .keyboardShortcut(isThinking ? "." : .return, modifiers: .command)
        .accessibilityLabel(buttonLabel)
        // What the circle does now, as the pointer rests on it on the Mac.
        .askHelp(buttonLabel)
        .accessibilityInputLabels(inputLabels)
        .accessibilityIdentifier(AskAccessibility.send)
        // **Hidden by name while the composer rests in a host's slot, as well
        // as with its row, and the accessory button with it.** Hidden with its
        // row alone, the resting send reported the glass capsule's frame
        // (360 × 48) as its own, over the face's field where XCUITest taps
        // `ask.send` (59 of 60 lowerings, iOS 27.2 simulator); hiding the
        // accessory button by name too keeps it from taking that frame. The
        // shortcut stays, so ⌘. stops a turn while the composer rests.
        .askAccessibilityHidden(while: rests)
    }

    /// What Voice Control answers to: the label, and for the stop square the
    /// word on its face as well, since a reader looking at a stop glyph says
    /// "stop" and the label says "Cancel".
    private var inputLabels: [Text] {
        guard isThinking else { return [buttonLabel] }
        return [buttonLabel, AskComposerWords.stop]
    }
}

/// The composer's field and the placeholder, the host's hint, in one stack:
/// apart from the composer so the layout can be drawn in a test with a
/// stand-in for the text field (`AskComposerPlaceholderTests`).
///
/// **One line, whatever its length**, so an empty field is the height of one
/// line of draft: a hint that wrapped held the capsule two lines tall before
/// the reader had typed a word. A hint longer than the field is wide ends in
/// an ellipsis, as a system text field's prompt does, and VoiceOver reads it
/// whole (`accessibilityHint`). Only a draft grows the capsule.
///
/// **On the field's first baseline**, so the hint's first line sits where the
/// draft's will: measured on the Mac, a text field padded 10 pt from the top
/// took the hint's first line down with it, where top alignment left the hint
/// 10 pt above the field's text.
struct AskComposerFieldStack<Field: View>: View {
    /// The host's hint, or nil once the draft has anything in it.
    let placeholder: String?
    /// What the hint is drawn in.
    let style: AskGlassForeground
    /// Puts the reader in the field.
    let focusField: () -> Void
    @ViewBuilder let field: Field

    var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            if let placeholder {
                Text(placeholder)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(style)
                    // **A tap on the hint puts the reader in the field.** The
                    // field lies over the hint and takes a tap there itself;
                    // this catches one on the rest of the hint's frame, where
                    // the field's own frame doesn't reach.
                    .contentShape(.rect)
                    .onTapGesture(perform: focusField)
                    // **No element, rather than a hidden one.** Hidden by
                    // name, it comes back wherever something above it is
                    // un-hidden by name: `AskScreen` hides the resting
                    // composer with `.accessibilityHidden(composerRests)`,
                    // and whenever the composer is up that is false, so the
                    // placeholder would be a second thing called "Your
                    // question" over the field. Walked in the demo on the iOS
                    // 27.1 simulator through UIAccessibility's container
                    // calls: listed under that modifier, not listed without
                    // it, and not listed with this.
                    .accessibilityRepresentation { EmptyView() }
            }
            field
        }
    }
}

/// Words the composer and its face in the slot share.
enum AskComposerWords {
    /// The stop square's name for Voice Control beside "Cancel", and the Mac
    /// menu item that stops a turn (`AskCommands`).
    static var stop: Text {
        Text("Stop", bundle: #bundle, comment: "Voice Control name for the Ask composer's stop button while a question is being answered, beside its VoiceOver label 'Cancel'; and the Mac menu item, shortcut ⌘., that stops the answer being written.")
    }

    /// What VoiceOver calls the field, on the composer and on the face, and
    /// one of the names Voice Control answers to there.
    static var yourQuestion: Text {
        Text("Your question", bundle: #bundle, comment: "VoiceOver label for the Ask composer's text field.")
    }
}

#if os(macOS)
/// What the composer in the focused window can do, for the menu bar's Send
/// and Stop (`AskCommands`): a value the composer hands up with
/// `focusedSceneValue`, so the menu acts on the window it is in and reads no
/// store in the scene's body.
///
/// **Two flags and an object, and no closure.** SwiftUI can't compare a
/// closure, so a value holding the composer's `send` and `stop` read as
/// changed on every pass of the composer's body, which is every character
/// typed, and ran `AskCommands`' body again each time. The actions object is
/// the composer's for its life and compares by identity, so the value changes
/// only when the menu's items should.
struct AskComposerCommand: Equatable {
    /// Whether there is a question to send and no turn in flight.
    let sends: Bool
    /// Whether a turn is in flight.
    let stops: Bool
    let actions: AskComposerActions

    /// Sends the composer's question, as its circle does.
    func send() {
        actions.send()
    }

    /// Stops the turn in flight.
    func stop() {
        actions.stop()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sends == rhs.sends && lhs.stops == rhs.stops && lhs.actions === rhs.actions
    }
}

/// The composer's send and stop as the menu bar calls them
/// (`AskComposerCommand`): handed the composer's closures as each pass of its
/// body builds them, so a call runs what the composer would run now.
///
/// Not observable, and nothing reads it in a body: what it holds changing
/// redraws nothing.
final class AskComposerActions {
    private var sends: () -> Void = {}
    private var stops: () -> Void = {}

    /// This, holding `send` and `stop` from here on.
    func holding(send: @escaping () -> Void, stop: @escaping () -> Void) -> AskComposerActions {
        sends = send
        stops = stop
        return self
    }

    func send() {
        sends()
    }

    func stop() {
        stops()
    }
}

extension FocusedValues {
    /// The focused window's composer (`AskComposerCommand`).
    @Entry var askComposer: AskComposerCommand?
}
#endif

/// How big the composer's two circles are, the accessory button and the send,
/// apart from the view so the arithmetic can be pinned (`AskLargeTextTests`).
///
/// **The glyphs scale with the body font, and the circles grow by what the
/// glyphs grow, not in proportion to them** (`AskGrowth`). In proportion, the
/// 44 pt target was about 137 at the largest text size, and with an accessory
/// button the two left a 402 pt phone's field about 70 pt: two or three
/// characters a line. Grown by the glyph, the room the default size leaves
/// around it stays as it was: the targets are 99 pt there, and the field
/// twice as wide.
///
/// **By the widest glyph a circle shows**, the chevron that puts the keyboard
/// away, 26 pt wide at the default body size: the arrow and the stop square
/// are as wide as the font is tall, and the chevron half as wide again, and
/// the fill has to hold it. Grown by the font's size alone, the chevron ran
/// out of its circle at the largest size. One measure for every glyph, so the
/// circle stays one size as the glyph changes under the reader's typing and
/// the field never moves.
///
/// **44 is a touch target, and the Mac has no touch.** At 44 on macOS, the
/// button sets the row's height and the capsule measures 48 pt around 16 pt
/// of laid-out text: an iPhone control in a Mac window, taller than the 36 pt
/// a question bubble comes to at the same body size. A pointer hits what it is
/// pointed at, so the Mac gets a circle sized to the glyph and a field padded
/// to match it, and the capsule lands at 36 with the text centered in it.
/// Measured in an `NSHostingView`, at one line and at four. visionOS keeps
/// iOS's circle and gives it a 60 pt target (`AskGrowth.touchTarget`): the hit
/// region grows, not the glyph.
nonisolated enum AskComposerMetrics {
    #if os(macOS)
    /// The widest glyph, 20 pt wide at the Mac's 13 pt default body size.
    static let widestGlyph: CGFloat = 20
    /// The circle at the default size, and the least it is at any.
    static let circle: CGFloat = 28
    /// The hit region at the default size, and the least it is at any.
    static let target: CGFloat = 32
    /// What pads the field to the button's height at one line.
    static let fieldInset: CGFloat = 8
    #else
    static let widestGlyph: CGFloat = 26
    static let circle: CGFloat = 34
    static let target: CGFloat = AskGrowth.touchTarget
    static let fieldInset: CGFloat = 11
    #endif

    /// The lines the field grows through as the draft does.
    static let lines: ClosedRange<Int> = 1...4

    /// The circle around the glyphs, given the widest one as the text scales
    /// it.
    static func circle(widestGlyph scaled: CGFloat) -> CGFloat {
        AskGrowth.grown(circle, glyph: widestGlyph, scaled: scaled)
    }

    /// The hit region around the circle, given the widest glyph as the text
    /// scales it.
    static func target(widestGlyph scaled: CGFloat) -> CGFloat {
        AskGrowth.grown(target, glyph: widestGlyph, scaled: scaled)
    }

    /// What the composer's capsule pads its row by, round the buttons.
    static let edge: CGFloat = 2

    /// The radius of the capsule's corners, given the widest glyph as the
    /// text scales it: half its height at one line, where it is a capsule,
    /// and the same as the field grows, so the circles, which sit at the
    /// bottom of the row, stay centred on the corners' centres, as far inside
    /// the edge at four lines as at one. A capsule four lines tall has ends
    /// 57 pt round, and its circles ran out over its rim.
    static func corner(widestGlyph scaled: CGFloat) -> CGFloat {
        edge + target(widestGlyph: scaled) / 2
    }
}

/// What a hardware Return does in the composer's field, apart from the view
/// so it can be tested. `AskComposer`'s field says why a hardware Return
/// sends at all.
nonisolated enum AskComposerReturn: Equatable {
    /// An input method is composing in the field (`AskMarkedText`): the key
    /// is the input method's, to confirm its conversion with, whatever the
    /// draft, the turn or the modifiers.
    case composing
    /// Shift-Return: the field keeps its newline.
    case newline
    /// A question to send and no turn in flight.
    case send
    /// Nothing to send, or a turn in flight: the key is taken and types
    /// nothing.
    case nothing

    /// The phases of a Return the field handles: the press and a held key's
    /// repeats, which reach the field if the handler doesn't take them.
    static let phases: KeyPress.Phases = [.down, .repeat]

    /// `isComposing` is what `AskMarkedText` says as the key comes in.
    ///
    /// **Composing comes first**, before nothing to send and a turn in
    /// flight as well as before a send: each of those takes the key, and the
    /// Return that confirms a conversion would never reach the input method.
    static func of(shift: Bool, draft: String, isThinking: Bool, isComposing: Bool) -> Self {
        if isComposing { return .composing }
        if shift { return .newline }
        if isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .nothing }
        return .send
    }

    /// What the field's handler answers the key press with: let through, to
    /// the input method or for the field's newline, or taken, to send or to
    /// type nothing.
    var result: KeyPress.Result {
        switch self {
        case .composing, .newline: .ignored
        case .send, .nothing: .handled
        }
    }
}

#endif
