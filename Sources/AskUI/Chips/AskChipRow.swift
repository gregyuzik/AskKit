#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import SwiftUI

/// A bank of chips, each a question to ask with a tap: the first screen's
/// starters, the follow-ups under an answer, or the coaching pair under a
/// refused or ungrounded failure.
///
/// Chips wrap onto as many lines as they need (`AskChipFlow`), which is why
/// this is a row only in the sense that the bank is one thing.
///
/// **One glass group per bank on glass (`AskGlassGroup`), and nothing else
/// grouped.** Inside one group the capsules blend and morph as a set. A group
/// wrapping the whole screen would make every glass surface on it a candidate
/// for blending with every other, which is how a composer ends up bleeding
/// into a toolbar.
///
/// **A bank in the thread is a fill, not glass** (`Surface`), on iOS and the
/// Mac: it scrolls under the glass bar and behind the glass composer, and glass
/// can't sample glass, the reason the question bubble is a fill
/// (`AskQuestionBubble`). The first screen's starters, and a host's own bank,
/// stay glass.
public struct AskChipRow: View {

    /// Which bank a chip came from. It decides the hint VoiceOver reads on the
    /// chip, and nothing else.
    ///
    /// Usable from any context, on the main actor or off it: a kind can be
    /// compared, hashed, made from its raw value and sent anywhere, which
    /// `AskCrossPostureTests` pins.
    public enum Kind: String, Sendable {
        /// A starter: on the first screen, or in the coaching pair.
        case starter
        /// A follow-up under an answer.
        case followUp
    }

    /// A chip that isn't a question, such as "Another pick", with a glyph
    /// ahead of its words. It is drawn first and inside the same glass group,
    /// so it sits with the questions beside it rather than as a second bank of
    /// one.
    ///
    /// **Isolation.** An action is main-actor isolated, as the views it goes
    /// in are: build it on the main actor, and read its fields and run it
    /// there. That isolation makes it `Sendable`, so once built it can be held
    /// anywhere, a host's own `Sendable` value included, which
    /// `AskCrossPostureTests` pins.
    public struct Action {
        /// The chip's words.
        public let title: Text
        /// The SF Symbol drawn ahead of the words.
        public let systemImage: String
        /// What VoiceOver says the chip does.
        public let hint: Text
        /// The chip's accessibility identifier.
        public let identifier: String
        /// What a tap does.
        public let perform: () -> Void

        /// Creates a chip that isn't a question.
        ///
        /// - Parameters:
        ///   - title: The chip's words.
        ///   - systemImage: The SF Symbol drawn ahead of the words.
        ///   - hint: What VoiceOver says the chip does.
        ///   - identifier: The chip's accessibility identifier.
        ///   - perform: What a tap does.
        public init(title: Text, systemImage: String, hint: Text, identifier: String, perform: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.hint = hint
            self.identifier = identifier
            self.perform = perform
        }
    }

    private let starters: [AskStarter]
    private let kind: Kind
    private let identifier: String
    private let alignment: HorizontalAlignment
    private let morph: Namespace.ID?
    private let leading: Action?
    private let onTap: (AskStarter) -> Void
    private let onDecline: ((AskStarter) -> Void)?
    private let surface: Surface

    @Namespace private var glass

    /// A line of a chip's words as the text size scales it: `.subheadline`,
    /// 20 pt at the default size.
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = AskChipOutline.line

    /// The glass a chip sits on, its hit region and the preview its menu
    /// lifts: one outline for the three (`AskChipOutline`).
    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: AskChipOutline.radius(line: line), style: .circular)
    }

    /// Creates a bank of chips.
    ///
    /// - Parameters:
    ///   - starters: The chips, in order, each a question the reader can ask
    ///     with a tap.
    ///   - kind: Which bank this is, for the hint VoiceOver reads on each
    ///     chip.
    ///   - identifier: The bank's accessibility identifier. It names one
    ///     container that holds the chips.
    ///   - alignment: Where a line that doesn't fill the width sits, and how
    ///     a chip that wraps aligns its own lines.
    ///   - morph: The namespace a chip shares with the question it becomes
    ///     once tapped (`AskChipMorph`), or nil for chips that don't travel.
    ///   - leading: A chip that isn't a question, drawn first.
    ///   - onTap: What a tap on a chip does, handed its starter.
    ///   - onDecline: "Don't suggest this" on a chip's long press, and as a
    ///     VoiceOver action, handed its starter. Nil for a bank whose chips
    ///     can't be passed over: the coaching pair is the reader's way out,
    ///     not a suggestion.
    public init(
        starters: [AskStarter],
        kind: Kind,
        identifier: String = AskAccessibility.starters,
        alignment: HorizontalAlignment = .leading,
        morph: Namespace.ID? = nil,
        leading: Action? = nil,
        onTap: @escaping (AskStarter) -> Void,
        onDecline: ((AskStarter) -> Void)? = nil
    ) {
        self.init(
            starters: starters, kind: kind, identifier: identifier, alignment: alignment,
            morph: morph, leading: leading, surface: .glass, onTap: onTap, onDecline: onDecline
        )
    }

    /// A bank on `surface`: the thread's own, on a fill.
    init(
        starters: [AskStarter],
        kind: Kind,
        identifier: String = AskAccessibility.starters,
        alignment: HorizontalAlignment = .leading,
        morph: Namespace.ID? = nil,
        leading: Action? = nil,
        surface: Surface,
        onTap: @escaping (AskStarter) -> Void,
        onDecline: ((AskStarter) -> Void)? = nil
    ) {
        self.starters = starters
        self.kind = kind
        self.identifier = identifier
        self.alignment = alignment
        self.morph = morph
        self.leading = leading
        self.surface = surface
        self.onTap = onTap
        self.onDecline = onDecline
    }

    /// What a bank's chips sit on.
    enum Surface: Equatable {
        /// Interactive glass, in a glass group of the bank's own: the first
        /// screen's starters, over nothing that is glass.
        case glass
        /// A fill: the thread's banks, on content that scrolls under the
        /// glass bar and behind the glass composer. On visionOS the same as
        /// glass, whose `askGlass` is already a fill on the window's glass.
        case fill
    }

    public var body: some View {
        bank
            // **A container, said outright.** The smoke suite reaches a chip
            // as `ask.starters`'s first button, so the identifier has to name
            // an element that holds the chips. Left alone, the glass group
            // surfaces as such an element only by accident, and a tap gesture
            // on the scroll content behind it (`AskScreen`'s keyboard
            // dismissal) is enough to stop it: the identifier then lands on
            // each chip, and `ask.starters` resolves to the first chip, which
            // has no buttons inside it. `.contain` pins the shape the
            // identifier promises, and VoiceOver still walks the chips one by
            // one.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    /// The chips, in a glass group where they are glass, and in none on a
    /// fill, where nothing blends.
    @ViewBuilder
    private var bank: some View {
        switch surface {
        case .glass:
            AskGlassGroup(spacing: 10) { flow }
        case .fill:
            flow
        }
    }

    private var flow: some View {
        AskChipFlow(alignment: alignment) {
            if let leading {
                actionChip(leading)
            }
            ForEach(starters.enumerated(), id: \.element.id) { position, starter in
                Button {
                    onTap(starter)
                } label: {
                    Text(starter.text)
                        .font(.subheadline)
                        // **Wraps rather than truncates.** A starter is a
                        // whole question. Held to one line, it would put
                        // the ellipsis back where the flow layout removes
                        // it: at an accessibility text size every starter
                        // is wider than any phone's column, so a one-line
                        // chip would cut every question mid-word for the
                        // readers least able to guess the rest.
                        // `AskChipFlow` measures each chip against the
                        // full column and takes the tallest in a line, so
                        // a chip that needs two lines simply gets them,
                        // and its outline keeps a one-line chip's corners
                        // (`AskChipOutline`).
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                        // Under the turn that has just ended, each
                        // question comes up out of a blur, as an answer's
                        // words do, a step behind the chip before it.
                        // Anywhere else, simply drawn.
                        //
                        // **The words and not the capsule, and the capsule
                        // is in first.** Glass is drawn by the bank's group
                        // and materializes on the Stage's own transaction,
                        // and a fill is drawn with the chip; neither
                        // carries a delay of its own, so an empty capsule
                        // is there first and the question comes up on it.
                        .askArrival(position + (leading == nil ? 0 : 1), as: .line)
                        .padding(.horizontal, 14)
                        .frame(minHeight: AskChipOutline.minimumHeight)
                        // **Without this the chip answers only where its
                        // glyphs are.** A `.plain` button takes its hit
                        // region from what the label draws, and neither
                        // the 14 pt at each end nor the slack a
                        // `minHeight` opens above and below one line of
                        // subheadline draws anything, so the capsule the
                        // reader aims at would be mostly dead. A finger is
                        // broad enough to find the words anyway, and a
                        // pointer isn't: on the Mac, a click beside the
                        // words would do nothing. `AskEvidenceLine`
                        // carries the same line for the same reason, and
                        // the capsule's surface is applied outside the
                        // button, so it is a backdrop and never a target.
                        .contentShape(outline)
                }
                .buttonStyle(.plain)
                // Lit in the chip's own outline, not the rectangle round its
                // frame. On visionOS the capsule is a fill on the window's
                // glass (`askGlass`), which answers no gaze of its own.
                .askHoverEffect(in: outline)
                // **Inside the surface, not outside it.** Interactive
                // glass takes the touches under it for its own press
                // effect, so a menu attached outside the capsule never
                // sees the long press: pressed in the smoke suite, the
                // starter was asked instead of offering to turn it down.
                .modifier(AskChipDeclineMenu(starter: starter, outline: outline, onDecline: onDecline))
                // Glass takes the chip's id in this bank's own namespace,
                // so it stays the chip's own as the chips around it
                // change. No two banks share a namespace: a starter never
                // morphs into a follow-up.
                .modifier(AskChipSurface(surface: surface, outline: outline, id: starter.id, in: glass))
                // **Outside the surface, not inside it.** The two effects
                // answer different questions: `askGlassID` morphs a
                // capsule into the next capsule *within this bank*, and
                // this carries the whole chip to a question bubble in
                // another part of the thread. Applied under the glass,
                // the capsule stays put while its label flies off it.
                .askChipMorph(starter.text, in: morph)
                .accessibilityHint(hint)
            }
        }
        // Breathing room for the glass, which draws slightly outside the
        // capsule it is on.
        .padding(.horizontal, 2)
    }

    /// The same capsule as a question chip, with a glyph ahead of its words so
    /// it reads as something to do rather than something to ask.
    private func actionChip(_ action: Action) -> some View {
        Button(action: action.perform) {
            Label {
                action.title
            } icon: {
                Image(systemName: action.systemImage)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            // First in the bank, so first to arrive, as the question chips do.
            .askArrival(0, as: .line)
            .padding(.horizontal, 14)
            .frame(minHeight: AskChipOutline.minimumHeight)
            .contentShape(outline)
        }
        .buttonStyle(.plain)
        .askHoverEffect(in: outline)
        .modifier(AskChipSurface(surface: surface, outline: outline, id: "ask.chip.action", in: glass))
        .accessibilityHint(action.hint)
        .accessibilityIdentifier(action.identifier)
    }

    /// How a wrapped chip's own lines sit, following the bank's alignment: a
    /// centered bank's chips center their second line, and a leading one's
    /// don't.
    private var textAlignment: TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private var hint: Text {
        switch kind {
        case .starter:
            Text("Asks this example question", bundle: #bundle, comment: "VoiceOver hint on a suggested starting question on the Ask first screen.")
        case .followUp:
            Text("Asks this follow-up question", bundle: #bundle, comment: "VoiceOver hint on a suggested follow-up question under an Ask answer.")
        }
    }
}

/// A chip's outline: a capsule round one line of words, and a capsule's
/// corners round more.
///
/// **Not a capsule at every height.** A capsule's ends are half its height
/// deep, so round three lines they reach far enough in to cut across the ends
/// of the first line and the last. At the largest text sizes every question
/// wraps, and its words would run out of the glass at the corners. The
/// corners here are half a one-line chip's height instead, and drawn circular:
/// a rounded rectangle's corners stop at half its shorter side, so a chip one
/// line tall is a capsule, and a taller one keeps that capsule's corners.
/// `AskLargeTextTests` pins the radius.
nonisolated enum AskChipOutline {
    /// The least a chip is tall: a full target round one line of words, 44 pt,
    /// and 60 on visionOS, where eyes and hands land on it
    /// (`AskGrowth.touchTarget`). There a starter's capsule is that tall: the
    /// chips sit 8 pt apart, too close for a hit region to reach past what is
    /// drawn.
    static let minimumHeight: CGFloat = AskGrowth.touchTarget

    /// A line of `.subheadline` at the default text size.
    static let line: CGFloat = 20

    /// The corner radius of a chip whose line of words is the given height:
    /// half of a chip one line tall, which is the minimum height until the
    /// line itself is taller.
    ///
    /// The line handed in is a scaled 20 pt and not a measured one. Where it
    /// runs ahead of the real line the radius passes half the chip's height,
    /// and the chip is the same capsule.
    static func radius(line scaled: CGFloat) -> CGFloat {
        max(minimumHeight, scaled) / 2
    }
}

/// What a chip sits on (`AskChipRow.Surface`): interactive glass that
/// materializes and morphs within its bank, or a fill.
///
/// **The fill is the system's tertiary fill**, which is what `askGlass` draws
/// for plain glass on visionOS, so a bank in the thread reads the same there
/// and here. The chip's words stay `.primary`, which holds far more than 4.5:1
/// on it in either appearance. A `.plain` button on a fill has no press effect
/// beyond the label's own dimming, where interactive glass flexes under the
/// finger.
private struct AskChipSurface<ID: Hashable & Sendable>: ViewModifier {
    let surface: AskChipRow.Surface
    let outline: RoundedRectangle
    let id: ID
    let namespace: Namespace.ID

    init(surface: AskChipRow.Surface, outline: RoundedRectangle, id: ID, in namespace: Namespace.ID) {
        self.surface = surface
        self.outline = outline
        self.id = id
        self.namespace = namespace
    }

    func body(content: Content) -> some View {
        switch surface {
        case .glass:
            content
                .askGlass(.interactive, in: outline)
                .askGlassID(id, in: namespace)
                .askGlassMaterialize()
        case .fill:
            #if os(visionOS)
            content.askGlass(.interactive, in: outline)
            #else
            content.background(.fill.tertiary, in: outline)
            #endif
        }
    }
}

/// "Don't suggest this" on a chip: a long-press menu item, and the same thing
/// as a named VoiceOver action, since a long press isn't a gesture every
/// reader can make.
///
/// Applied or not for the life of the row, since whether there is a handler
/// doesn't change between renders, so the conditional doesn't churn the
/// chip's identity.
private struct AskChipDeclineMenu: ViewModifier {
    let starter: AskStarter
    /// The chip's outline, which the lifted preview takes.
    let outline: RoundedRectangle
    let onDecline: ((AskStarter) -> Void)?

    func body(content: Content) -> some View {
        if let onDecline {
            content
                // The lifted preview takes the chip's outline rather than
                // the system's rounded rectangle around its words. A Mac menu
                // lifts no preview, and the kind doesn't exist there.
                #if !os(macOS)
                .contentShape(.contextMenuPreview, outline)
                #endif
                .contextMenu {
                    Button {
                        onDecline(starter)
                    } label: {
                        Label {
                            Self.title
                        } icon: {
                            Image(systemName: "hand.raised.slash")
                        }
                    }
                    .accessibilityIdentifier(AskAccessibility.declineSuggestion)
                }
                // Menu icons are hidden by default on iPadOS 27 and in macOS
                // 27 context menus; `AskQuestionBubble` opts back in for the
                // same reason.
                .labelStyle(.titleAndIcon)
                .accessibilityAction(named: Self.title) { onDecline(starter) }
        } else {
            content
        }
    }

    private static var title: Text {
        Text("Don't suggest this", bundle: #bundle, comment: "Menu item on a suggested Ask question that takes the suggestion away for the rest of this chat.")
    }
}

#endif
