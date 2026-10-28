#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// What the screen shows before anything has been asked.
///
/// Three of them (ready, nothing to ask about, and can't serve), and which one
/// shows is `AskStage.Phase`'s decision, not this view's: a reader who can't
/// be served needs to know that before being told they own nothing.
public struct AskFirstScreen<Mark: View>: View {
    private let phase: AskStage.Phase
    private let brand: AskBrand
    private let starters: [AskStarter]
    private let policy: AskFirstScreenPolicy
    /// Whether the screen is making room for the keyboard. The ready screen
    /// lets its sentence and caveat go, and what stays closes up, so the mark,
    /// the headline, the chips and the disclosure all fit above the composer.
    /// They fit through extra-large text and not above it, where the
    /// disclosure goes under the composer, so `AskScreen` makes room through
    /// extra-large alone: its `firstScreenIsMakingRoom` has the recordings.
    /// In a window too short for even that, iPhone Duo's outer display, the
    /// mark and the headline go too (`keepsMarkAndHeadline`).
    ///
    /// `AskScreen` changes it inside the keyboard's own animation and outside
    /// any SwiftUI one, so the column animates the change itself (`ready`).
    private let isMakingRoom: Bool
    /// The height of the window this sits in, or zero before it has been
    /// measured. `AskScreen` reads it (`AskWindowHeightReader`), and
    /// `isSideBySide` says what it decides.
    private let windowHeight: CGFloat
    private let onStarter: (AskStarter) -> Void
    private let onNothingAction: (() -> Void)?
    private let onDecline: ((AskStarter) -> Void)?
    private let mark: (Bool) -> Mark

    /// The gap between the mark, the copy, the chips and the disclosure: 16 pt,
    /// and 10 pt while the ready screen makes room for the keyboard.
    ///
    /// Keyed on `isMakingRoom` rather than on focus, and paired with letting
    /// two lines of copy go. A focus flip arrives outside any transaction, so
    /// gaps keyed on it would pop as the keyboard left, and closing the gaps
    /// alone leaves the column short of fitting. The column animates on
    /// `isMakingRoom`, and it takes the copy out as well as closing the gaps.
    ///
    /// The other two screens keep 16 pt. They don't make room: neither was
    /// recorded under a keyboard, and all they animate on it is where they
    /// stand around a fold (`onKeyboard`).
    private var spacing: CGFloat { isMakingRoom && phase == .ready ? 10 : 16 }

    /// How the copy leaves as the keyboard rises and comes back as it goes: out
    /// quickly, before the chips close up over where it stood, and in once
    /// they have moved away. A fade is also Reduce Motion's answer, so it stays
    /// when the column's own animation is off.
    private static var makingRoom: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 56
    /// `AskFirstScreenArrangement.shortWindowHeight`, grown with the text,
    /// since the stacked column grows with it.
    @ScaledMetric(relativeTo: .body) private var shortWindowHeight = AskFirstScreenArrangement.shortWindowHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the column goes around a fold across the screen, from
    /// `AskScreen` (`AskFoldSplit`), and `acrossFold` says what this screen
    /// makes of it. Stacked only: side by side, the halves are already either
    /// side of the middle.
    @Environment(\.askFoldSplit) private var foldSplit
    /// Whether this screen's own keyboard is up, from `AskScreen`
    /// (`firstScreenMakesRoom`). The screens that can't serve and that have
    /// nothing to ask about animate on it and lay nothing out by it
    /// (`onKeyboard`); the ready screen has `isMakingRoom`.
    @Environment(\.askFirstScreenKeyboardIsUp) private var keyboardIsUp
    /// Whether the composer rests in a host's slot over a tab bar along the
    /// bottom, from `AskScreen` (`trimsOverSlot` says what it decides).
    @Environment(\.askFirstScreenIsOverSlot) private var isOverSlot
    /// Which half this view draws where the screen takes both panes beside
    /// iPhone Duo's fold, from `AskScreen` (`AskFirstScreenPart`). Both
    /// everywhere else.
    @Environment(\.askFirstScreenPart) private var part
    /// Where `AskScreen` wants VoiceOver's focus (`AskVoiceOverTarget`): the
    /// headline after New Chat, which this screen takes as it appears.
    @Environment(\.askVoiceOverTarget) private var voiceOverTarget
    /// VoiceOver's focus on the headline.
    @AccessibilityFocusState private var headlineIsFocused: Bool
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    /// Whether what Ask is and what to ask sit side by side rather than one
    /// above the other: where there is width to spare and too little height,
    /// in compact height or in a regular-width window too short for the stack.
    ///
    /// **Stacked, the screen never fits a phone on its side.** It wants about
    /// 525 pt, and an iPhone 18 Pro in landscape has 402 in all. Recorded in a
    /// host app there, stacked: the composer sat over the disclosure, "Try
    /// asking" was behind it, the first starter was behind the tab bar, and
    /// the second was off the screen. A scroll reached them, but the starters
    /// are what the screen is for. iPhone Duo's outer display is the same case
    /// turned, at about 466 pt tall. Side by side on the demo at 874 × 402, the
    /// copy's column is centered at x≈257 and the starters' at x≈617, the bank
    /// running y 124–272 and the disclosure ending at 311, all between the bar
    /// and the composer's top at 330.
    ///
    /// **Compact height, not the orientation or the idiom.** The idiom is
    /// `.phone` on both of the Duo's displays, and the inner one ignores the
    /// orientation, so neither says anything there. The size class is
    /// compact on every iPhone in landscape and on the Duo's outer display
    /// turned. Its inner display is regular both ways and keeps the stack.
    ///
    /// **A short iPad window is regular height, though.** Windowed on an iPad
    /// Pro 13-inch (M5), the demo at 704 × 486, the shortest window iPadOS
    /// allows, still reported regular height. The size class kept the stack
    /// there, and the third starter sat under the composer's glass, as it did
    /// in a host app at the same size. So at regular width the window's height
    /// decides as well, and `AskFirstScreenArrangement.shortWindowHeight` has
    /// the measurements.
    /// Side by side at 704 × 486, both halves clear the bar and the composer.
    ///
    /// **Stacked again at the accessibility sizes**, where half the width
    /// holds a few words a line. The column scrolls there anyway.
    ///
    /// Only where there are starters to put beside the copy. The nothing-to-ask
    /// screen is a mark, a sentence and a button, which fits stacked.
    ///
    /// One layout swapped for another (`halves`), never one view for another,
    /// so turning the phone keeps every chip's identity and the glass group's
    /// morph with it.
    private var isSideBySide: Bool {
        #if os(iOS)
        // A half on its own has nothing to sit beside: the other is in the
        // pane across the fold.
        guard part == .whole else { return false }
        guard AskFirstScreenArrangement.isSideBySide(
            isCompactHeight: verticalSizeClass == .compact,
            isRegularWidth: horizontalSizeClass == .regular,
            windowHeight: windowHeight,
            shortBelow: shortWindowHeight,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        ) else { return false }
        switch phase {
        case .ready:
            return !starters.isEmpty
        case .cannotServe:
            return policy.answersWithoutModel && !starters.isEmpty
        case .nothingToAskAbout, .thread:
            return false
        }
        #else
        false
        #endif
    }

    /// Whether the mark and the headline stay while the ready screen makes room
    /// for the keyboard: everywhere but a stacked column in a window too short
    /// for them (`AskFirstScreenArrangement.shortMakingRoomHeight`), where they
    /// go with the sentence and the caveat and leave what to ask.
    ///
    /// The window's height doesn't change while the reader types, so this
    /// changes with `isMakingRoom` and nothing else, on that key's animation
    /// (house rule 4).
    private var keepsMarkAndHeadline: Bool {
        AskFirstScreenArrangement.keepsMarkAndHeadline(
            isMakingRoom: isMakingRoom && phase == .ready,
            // Either side of iPhone Duo's fold the halves are side by side
            // too, each in a pane of its own.
            isSideBySide: isSideBySide || part != .whole,
            windowHeight: windowHeight
        )
    }

    /// Whether this view draws the headline: the ready screen, while it keeps
    /// it, in the half that says what Ask is.
    private var showsHeadline: Bool {
        phase == .ready && keepsMarkAndHeadline && part != .ask
    }

    /// Whether this view answers the screen's request for VoiceOver's focus on
    /// the headline: the whole column, or the half beside iPhone Duo's fold
    /// that holds the headline. The other half leaves it to that one.
    private var takesHeadlineRequest: Bool {
        voiceOverTarget?.wrappedValue == .headline && part != .ask
    }

    /// Whether the side-by-side column lets its sentence go and offers two
    /// starters: on a phone on its side over a host's slot, where the tab bar
    /// and the composer's face leave it too little height for the whole of
    /// either half (`AskFirstScreenArrangement.trimsOverSlot`).
    private var trimsOverSlot: Bool {
        #if os(iOS)
        AskFirstScreenArrangement.trimsOverSlot(
            isSideBySide: isSideBySide,
            isCompactHeight: verticalSizeClass == .compact,
            isOverSlot: isOverSlot
        )
        #else
        false
        #endif
    }

    /// How many starters the bank shows: the screen's bank, or two where the
    /// column is trimmed over a host's slot.
    private var starterBank: Int {
        trimsOverSlot ? AskFirstScreenArrangement.slotStarterBank : AskLayout.starterBank
    }

    /// Whether this screen has two halves to part around iPhone Duo's fold
    /// (`AskFirstScreenArrangement.hasTwoHalves`).
    private var hasTwoHalves: Bool {
        AskFirstScreenArrangement.hasTwoHalves(
            phase: phase,
            answersWithoutModel: policy.answersWithoutModel,
            hasStarters: !starters.isEmpty
        )
    }

    /// The fold across the screen that this column is arranged around, or
    /// nil: side by side, one half on its own in a pane, a screen with no
    /// halves lying flat, and everywhere there is no fold
    /// (`AskFirstScreenArrangement.foldSplit(_:hasTwoHalves:)`).
    private var acrossFold: AskFoldSplit? {
        guard !isSideBySide, part == .whole else { return nil }
        return AskFirstScreenArrangement.foldSplit(foldSplit, hasTwoHalves: hasTwoHalves)
    }

    /// The bend a screen with no two halves keeps clear of, in a tabletop:
    /// what only informs stands in the upper half, and a button in the lower
    /// (`AskFoldSplit` has why). Nil for a screen whose halves part at the
    /// fold instead, and wherever `acrossFold` is.
    private var bend: AskFoldSplit? {
        hasTwoHalves ? nil : acrossFold
    }

    /// What the nothing-to-ask button is filled with, and what its label's
    /// color is judged on: the app's accent, which is also `AskScreen`'s
    /// default accent. An accent a host hands `AskScreen` doesn't reach this
    /// view, which takes none.
    ///
    /// **One color for both, set on the button.** `.glassProminent` fills
    /// with the environment's tint, which a host can set around the screen,
    /// and nothing public reads a tint back: `TintShapeStyle` resolves to no
    /// color, and nothing documents whether `Color.accentColor` follows a
    /// `.tint`. A label judged on one color over a fill of another could keep
    /// white over a host's green, 2.22:1 on #34C759. Tinted with the color it
    /// is judged on, the fill and the label agree whatever surrounds them, as
    /// the confirmation card's do (`.tint(accent)` beside
    /// `AskOnAccentLabel(accent: accent)`).
    ///
    /// visionOS sets no tint: there the button is a platter with no fill of
    /// the accent (`askGlassButton`), and its label keeps the style's own
    /// color.
    private var actionAccent: Color { .accentColor }

    /// Creates the first screen.
    ///
    /// - Parameters:
    ///   - phase: Which screen shows (`AskStage.Phase`). `.thread` draws
    ///     nothing.
    ///   - brand: The host's words: the headline, the sentence, the scope and
    ///     caveat, the disclosure, and the nothing-to-ask copy and its
    ///     button's label.
    ///   - starters: The questions to offer, of which the first
    ///     `AskLayout.starterBank` show.
    ///   - policy: What the screen offers where nothing can serve
    ///     (`AskFirstScreenPolicy`).
    ///   - isMakingRoom: Whether the ready screen closes up for the keyboard.
    ///   - windowHeight: The height of the window this sits in, or zero
    ///     before it is measured, which `isSideBySide` reads.
    ///   - onStarter: What a tap on a starter does, handed the starter.
    ///   - onNothingAction: What the nothing-to-ask screen's button does. Nil,
    ///     or a brand with no `nothingToAskActionLabel`, for no button.
    ///   - onDecline: "Don't suggest this" on a starter, handed the starter.
    ///     Nil for no such action.
    ///   - mark: The host's mark, handed whether it is lit: lit on the ready
    ///     screen and unlit on the other two (`AskScreen.mark(_:)`). The
    ///     screen hides it from VoiceOver, since it decorates.
    public init(
        phase: AskStage.Phase,
        brand: AskBrand,
        starters: [AskStarter],
        policy: AskFirstScreenPolicy = .ownedLibrary,
        isMakingRoom: Bool = false,
        windowHeight: CGFloat = 0,
        onStarter: @escaping (AskStarter) -> Void,
        onNothingAction: (() -> Void)? = nil,
        onDecline: ((AskStarter) -> Void)? = nil,
        @ViewBuilder mark: @escaping (Bool) -> Mark
    ) {
        self.phase = phase
        self.brand = brand
        self.starters = starters
        self.policy = policy
        self.isMakingRoom = isMakingRoom
        self.windowHeight = windowHeight
        self.onStarter = onStarter
        self.onNothingAction = onNothingAction
        self.onDecline = onDecline
        self.mark = mark
    }

    public var body: some View {
        VStack(spacing: spacing) {
            switch phase {
            case .ready:
                ready
            case .nothingToAskAbout:
                nothing
            case .cannotServe(let why):
                cannotServe(why)
            case .thread:
                EmptyView()
            }
        }
        // Side by side, as wide as the thread's column: half of 460 would
        // leave each side too narrow for a starter.
        .frame(maxWidth: isSideBySide ? AskLayout.readingWidth : 460)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        // **After New Chat, VoiceOver's focus goes to the headline**, the
        // screen's title, rather than wherever the system puts it as the
        // thread it was on goes. Where this screen has no headline, to the
        // composer's field. The field has keyboard focus too (New Chat
        // focuses it), so the reader hears the headline with the keyboard up.
        .task(id: takesHeadlineRequest) {
            guard takesHeadlineRequest, let voiceOverTarget else { return }
            if showsHeadline {
                headlineIsFocused = true
                voiceOverTarget.wrappedValue = nil
            } else {
                voiceOverTarget.wrappedValue = .field
            }
        }
        // A headline that goes while it has VoiceOver's focus, as the ready
        // screen makes room in a window too short to keep it, hands the focus
        // to the field rather than to wherever the system puts it.
        .onChange(of: showsHeadline) { _, shows in
            guard !shows, headlineIsFocused else { return }
            voiceOverTarget?.wrappedValue = .field
        }
    }

    /// The screen's two halves, what only informs and what to ask, stacked or
    /// side by side (`isSideBySide`): what Ask is over its starters, or why it
    /// can't serve over the starters it keeps. Stacked, the gap between them
    /// is the gap inside them, so the column reads as one stack.
    ///
    /// Without `showsAbout` the half that says what Ask is goes as a whole, on
    /// the same transition as the copy that leaves while making room, rather
    /// than staying empty: an empty half still takes the gap. What to ask
    /// stays the second child either way, so its chips keep their identity.
    ///
    /// **Around a fold across the screen** (`split`), the halves part at it:
    /// each is centered in its side, at least as tall as the side, and the gap
    /// between them is the fold. The same two children in the same layout, so
    /// the bend arriving or going moves them without rebuilding them. Only
    /// for a screen with two halves (`hasTwoHalves`). The one that can't
    /// serve with no starters comes through here too, a reason over a
    /// disclosure with nothing between them to part: it keeps its gap, and
    /// `cannotServe` stands the whole of it above a bend.
    ///
    /// **Either side of a fold from top to bottom** (`part`), each half is a
    /// view of its own in its own pane, and this draws the one it is asked
    /// for: `AskScreen` puts what only informs in the leading pane and what
    /// to ask in the conversation's, over the composer.
    private func halves<About: View, Ask: View>(
        showsAbout: Bool = true,
        @ViewBuilder about: () -> About,
        @ViewBuilder ask: () -> Ask
    ) -> some View {
        let split = hasTwoHalves ? acrossFold : nil
        let layout = isSideBySide
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 40))
            : AnyLayout(VStackLayout(spacing: split?.gap ?? spacing))
        return layout {
            if showsAbout, part != .ask {
                VStack(spacing: spacing) { about() }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: split?.above)
                    .transition(Self.makingRoom)
            }
            if part != .about {
                VStack(spacing: spacing) { ask() }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: split?.below)
            }
        }
    }

    /// The host's mark in its square, lit or not, and hidden from VoiceOver.
    ///
    /// **It decorates, so no host has to remember to hide it.** The headline,
    /// the copy or the reason under it says what the screen is. A mark left
    /// in would be a stop of its own above them, read as "image" or as its
    /// symbol's name. `AskDefaultMark` hides itself as well, and a host's
    /// mark that does is hidden twice, to the same effect.
    private func hostMark(isLit: Bool) -> some View {
        mark(isLit)
            .frame(width: markSize, height: markSize)
            .accessibilityHidden(true)
    }

    private var ready: some View {
        halves(showsAbout: keepsMarkAndHeadline) {
            hostMark(isLit: true)
            Text(brand.firstScreenHeadline)
                .font(.title2.weight(.semibold))
                // The screen's title, as VoiceOver's headings rotor hears it.
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headlineIsFocused)
            // What Ask is and what it reads, said before the reader types and
            // let go while they do: a reader about to ask has already read
            // them, and with the keyboard up they are what stands between the
            // column and fitting.
            if !isMakingRoom {
                // Not over a host's slot on a phone on its side, where the
                // half is too tall with it (`trimsOverSlot`). The caveat
                // stays: it is the line that says Ask can be wrong.
                if !trimsOverSlot {
                    Text(brand.firstScreenSentence)
                        .font(.body)
                        .askDeemphasizedText()
                        .transition(Self.makingRoom)
                }
                // Scope and caveat in one line: what Ask reads, and that it can
                // be wrong. Both belong on the first screen and nowhere else: a
                // per-answer disclaimer is noise the reader learns to skip.
                Text(brand.scopeCaveat)
                    .font(.footnote)
                    .askDeemphasizedText()
                    .transition(Self.makingRoom)
            }
        } ask: {
            if !starters.isEmpty {
                tryAsking
            }
            disclosure
        }
        // The column's own key, beside the screen's `stage`: `AskStage` says
        // why a second one is allowed, and
        // `AskKeyboard.change(_:to:duration:curve:in:)` why the keyboard's
        // animation can't do this part. Over the keyboard's own 0.38 s, and
        // `easeInOut` rather than the Stage's `snappy` (`AskStage.animation`),
        // because a frame the main thread misses is made up in one step as
        // long as the curve traveled meanwhile, and `snappy` travels twice as
        // fast at its peak: with the main thread keeping up, it moved the chips
        // 15 to 17 pt a frame, and this 7 to 8. Recorded back to back on one
        // loaded simulator, three shows and three dismisses each,
        // `snappy(duration: 0.28)` stepped as far as 45 pt on a show and 53 pt
        // on a dismiss, and this 29 pt and 16 pt.
        //
        // The other two columns never make room, so this flag never rises on
        // them, and they ride the same key by the flag under it, the keyboard
        // itself (`onKeyboard`).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.38), value: isMakingRoom)
    }

    /// A mark, a sentence and at most a button: one column, with no two
    /// halves to part. A brand with no `nothingToAskCopy` has no sentence:
    /// `AskStage` shows the ready screen in its place, so only a host that
    /// draws this phase itself gets the mark and the button alone.
    ///
    /// **In a tabletop it keeps clear of the bend** (`bend`): the mark and the
    /// sentence, which only inform, centered in the upper half, and the
    /// button, the one thing to tap, centered in the lower. With no button
    /// the lower half is empty, and the column still runs to the foot of what
    /// the bars leave, or the scroll view would center it across the bend it
    /// is there to clear.
    ///
    /// **Frames on the same children, never another child.** The mark and
    /// the sentence are a stack of their own inside the column so the two can
    /// be centered above a bend together; with no bend every frame here is
    /// nil and the gap is the column's 16 pt, so the screen is the column it
    /// was (`AskFirstScreenFoldTests` compares the renders). An empty stack
    /// standing in for a missing button would take that gap for nothing.
    /// And the bend arriving or going moves the column without rebuilding
    /// it, as it does the ready screen's halves.
    private var nothing: some View {
        onKeyboard(
            VStack(spacing: bend?.gap ?? spacing) {
                VStack(spacing: spacing) {
                    hostMark(isLit: false)
                    if let copy = brand.nothingToAskCopy {
                        Text(copy)
                            .font(.body)
                            .askDeemphasizedText()
                    }
                }
                .frame(minHeight: bend?.above)
                if let onNothingAction, let label = brand.nothingToAskActionLabel {
                    // The label is a host's sentence, not a word, such as "Add
                    // Your First Item", and `Button(_:action:)`'s own `Text` is
                    // held to one line by the glass style's height, so at an
                    // accessibility size it runs straight out of its capsule.
                    // Spelled out with room to wrap, the capsule grows instead.
                    Button(action: onNothingAction) {
                        Text(label)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            // The style's white, or black where white falls
                            // under 4.5:1 on the accent (`AskOnAccentLabel`).
                            .modifier(AskOnAccentLabel(accent: actionAccent))
                    }
                    .askGlassButton(prominent: true)
                    #if !os(visionOS)
                    // Filled with the color its label is judged on, whatever
                    // tint the host set around the screen (`actionAccent`).
                    .tint(actionAccent)
                    #endif
                    .accessibilityIdentifier(AskAccessibility.nothingAction)
                    .frame(minHeight: bend?.below)
                }
            }
            .frame(minHeight: bend?.whole, alignment: .top)
        )
    }

    /// **The reason is a caption here, not always a wall.**
    ///
    /// An app whose Ask needs a model has nothing to offer a device that can't
    /// run one, and the unlit mark and the reason are the whole screen. An app
    /// that answers some of its own questions without a model
    /// (`AskFirstScreenPolicy.answersWithoutModel`), such as one whose own
    /// data answers its starters, keeps its starters and its composer under
    /// the same line, because those chips work. Without that, adopting
    /// Ask would turn a working screen into a dead end on every device without
    /// Apple Intelligence.
    ///
    /// **Around iPhone Duo's fold the two are two arrangements.** With its
    /// starters the screen has two halves, the reason and what to ask, and
    /// they part at the fold as the ready screen's do (`halves`). Without
    /// them it only informs, the disclosure included, so in a tabletop the
    /// whole column stands in the upper half and the lower is empty (`bend`):
    /// frames on the column, nil with no bend, so the screen is otherwise the
    /// column it was.
    private func cannotServe(_ why: AskUnavailability) -> some View {
        onKeyboard(
            halves {
                // Unlit: the mark says the feature is here and not available,
                // which is different from the feature being gone.
                hostMark(isLit: false)
                    .opacity(0.4)
                Text(AskError.unavailableMessage(why))
                    .font(.body)
                    .askDeemphasizedText()
            } ask: {
                if policy.answersWithoutModel, !starters.isEmpty {
                    tryAsking
                }
                disclosure
            }
            .frame(minHeight: bend?.above)
            .frame(minHeight: bend?.whole, alignment: .top)
        )
    }

    /// The keyboard's first key, carrying the two columns that don't make
    /// room: the screen that can't serve, with its starters or without, and
    /// the one with nothing to ask about.
    ///
    /// **What it animates is the fold's arrangement coming back.** While its
    /// keyboard is up `AskScreen` sets no split in the environment, since the
    /// keyboard takes the lower half, and the halves, or the column above a
    /// bend, close into the one column every phone shows. Parting again as the
    /// keyboard goes is SwiftUI's layout inside the scroll view, which the
    /// keyboard's own animation doesn't move
    /// (`AskKeyboard.change(_:to:duration:curve:in:)` has the recordings): on
    /// no key it lands in one frame while the scroll view glides around it.
    /// The ready column rides `isMakingRoom` for the same reason, and this is
    /// the same curve over the same 0.38 s (`ready` has the measurements).
    ///
    /// **The same key, one flag down, and not a third** (house rule 4).
    /// `isMakingRoom` never rises on these two, which don't make room, so they
    /// take the flag under it from the environment, `AskScreen`'s
    /// `firstScreenMakesRoom`, which the keyboard's show and hide set and
    /// nothing else does. No stream reaches it: these columns leave the
    /// screen as a turn starts.
    ///
    /// **With no fold it has nothing to animate.** Nothing else these columns
    /// lay out by changes with the keyboard: their gaps stay 16 pt
    /// (`spacing`), their copy stays, and the window's height, the size
    /// classes and whether the composer rests in a host's slot
    /// (`AskComposerSlotPolicy.rests`) are not the keyboard's.
    /// `AskFirstScreenFoldTests` pins that the flag alone moves nothing.
    ///
    /// **The way back is this key's because the split is back first.** A
    /// keyboard that covers the lower half takes the scroll view's own
    /// reading of the split away too (`AskFoldSplit.around(_:height:)`).
    /// Going, it gives the scroll view its height back before its hide's
    /// message arrives, 3 to 14 ms before on iPhone Duo's simulator, while
    /// the composer is still held up over where the keyboard was. The view
    /// is tall enough for a half by then, so the screen has the split in
    /// hand when the flag falls, and the halves part in the flag's own
    /// transaction. Recorded on the Duo in a tabletop and read a frame at a
    /// time, the nothing-to-ask button goes its 386 pt in 23 frames, 58 pt
    /// at most in one, and the starters of the other two screens glide down
    /// the same way.
    ///
    /// A split that came back after the flag would return in a transaction
    /// of its own, which carries no animation, and the halves would part in
    /// a frame. Taking the scroll view's insets off twice would do it: with
    /// the composer up the lower half would read 70 pt, under
    /// `AskFoldSplit.minimumHalf`, so the split would wait for the composer
    /// to rest, and the button would go 268 pt in one frame and ease the
    /// last 76.
    ///
    /// **The way in isn't this key's.** The keyboard shortens the scroll
    /// view before its show's message arrives too, so the reading ends the
    /// split while this flag is still down, in a transaction with no
    /// animation. Recorded on the same display the halves close with the
    /// keyboard all the same, and nothing here says why.
    private func onKeyboard(_ column: some View) -> some View {
        column.animation(reduceMotion ? nil : .easeInOut(duration: 0.38), value: keyboardIsUp)
    }

    private var tryAsking: some View {
        VStack(spacing: 10) {
            Text("Try asking", bundle: #bundle, comment: "Heading above the suggested starting questions on the Ask first screen.")
                .font(.footnote.weight(.medium))
                .askDeemphasizedText()
                // A heading over the bank, so the headings rotor lands on the
                // starters from the top of the screen.
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AskAccessibility.tryAsking)
            AskChipRow(
                starters: Array(starters.prefix(starterBank)), kind: .starter,
                alignment: .center, onTap: onStarter, onDecline: onDecline
            )
        }
        .padding(.top, 4)
    }

    /// One sentence, once, on the first screen. Not a toggle and not a
    /// per-answer disclaimer: the reader is told where their question goes
    /// before they ask one.
    private var disclosure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "apple.intelligence")
                .font(.caption)
                // Decoration beside a sentence that already says Apple
                // Intelligence: VoiceOver reading the glyph's name adds a
                // word, not information. `AskPrivateCloudCard` hides both of
                // its decorations for the same reason.
                .accessibilityHidden(true)
            Text(brand.disclosureSentence)
                .font(.caption)
        }
        .askDeemphasizedText()
        .padding(.top, 8)
    }
}

extension EnvironmentValues {
    /// Whether the first screen's composer rests in a host's slot over a tab
    /// bar along the bottom, which `AskScreen` sets in the environment, since
    /// it knows the slot and where the bars are. False everywhere else.
    @Entry var askFirstScreenIsOverSlot = false

    /// Which half of the first screen a view draws, which `AskScreen` sets in
    /// the environment where the screen takes both panes beside iPhone Duo's
    /// fold. Both everywhere else.
    @Entry var askFirstScreenPart = AskFirstScreenPart.whole

    /// Whether this screen's own keyboard is up, which `AskScreen` sets in the
    /// environment (`firstScreenMakesRoom`) for the first screens that don't
    /// make room to animate on (`AskFirstScreen.onKeyboard`). False everywhere
    /// else.
    @Entry var askFirstScreenKeyboardIsUp = false
}

#endif
