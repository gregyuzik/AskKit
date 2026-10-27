#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the host rests the composer in its tab view's bottom accessory
    /// (`askComposerSlot`), so `AskScreen` keeps its own composer down until
    /// its keyboard is up. Always false off iOS, where there is no slot.
    @Entry var askComposerRestsInSlot = false
    /// Whether an item is pushed over the Ask screen under a host's slot
    /// (`AskComposerSlotCover`), which the screen reports as it comes and
    /// goes. Each slot hands down its own, and only while the Ask tab is up.
    /// Nil where there is no slot, and on the way out of the tab.
    @Entry var askComposerSlotCover: Binding<AskComposerSlotCover>?
    /// Whether the tab bar over a host's slot runs along the bottom, which the
    /// Ask screen reads from inside its tab (`tabBarPlacement`) and reports,
    /// since the slot sits on the tab view, outside the tabs that hear it.
    /// Each slot hands down its own. Nil where there is no slot.
    @Entry var askComposerSlotTabBar: Binding<Bool?>?
    /// Whether the Ask screen holds its own composer up for a reader typing
    /// with no keyboard on screen (`AskScreen.composerHeldUp`), which the slot
    /// empties for (`AskComposerSlotPolicy.showsFace`). The screen reports it.
    /// Each slot hands down its own, and only while the Ask tab is up. Nil
    /// where there is no slot, and on the way out of the tab.
    @Entry var askComposerSlotHeldUp: Binding<Bool>?
    /// What the face in a host's slot draws with, the Ask screen's accent,
    /// spectrum and accessory button (`AskComposerFaceStyle`), which the
    /// screen writes as it appears and whenever one changes. Each slot hands
    /// down its own,
    /// so a window's face draws its own screen's, and its accessory button
    /// opens that window's picker. Nil where there is no slot.
    @Entry var askComposerSlotFaceStyle: AskComposerFaceStyle?
    /// Whether the Ask screen has its own composer up over the keyboard, or
    /// held up where none came, which the screen reports: the face is under
    /// it then, and keeps out of VoiceOver's way. Each slot hands down its
    /// own, so a reader typing in one window hides only that window's face.
    /// Nil where there is no slot.
    @Entry var askComposerSlotRaised: Binding<Bool>?
    /// A tap on the face in a host's slot, asking the Ask screen under it to
    /// put the reader in its composer: a new token for each tap, which the
    /// screen answers by focusing its field. Each slot hands down its own, so
    /// the face in one window raises that window's composer and no other's.
    /// The store's `composerFocusRequest` is the host's, which goes to the
    /// screen in whichever window appears active, and a window tapped while
    /// another does comes to the front only after the tap's action has run
    /// (`AskHostFocusHandOver`). Nil before the face is first tapped, and
    /// where there is no slot.
    @Entry var askComposerSlotFocusRequest: UUID?
    /// Whether `AskScreen`'s composer rests in a host's slot right now, at no
    /// height and no opacity and hidden from VoiceOver, with the face standing
    /// in for it. The composer hides its buttons by name while it does
    /// (`AskComposer`). False for a composer a host draws itself.
    @Entry var askComposerRests = false
}

#if os(iOS)
extension View {
    /// Rests the Ask composer in the tab view's bottom accessory, the slot,
    /// wherever the tab bar runs along the bottom
    /// (`AskComposerSlotPolicy.tabBarRunsAlongBottom`). Put it on the
    /// `TabView` that holds the Ask tab. With
    /// `tabBarMinimizeBehavior(.onScrollDown)` on the same `TabView`, the
    /// composer's face rides beside the bar when the bar minimizes.
    ///
    /// The slot holds the face: the draft on one line, the accessory button
    /// and the send, washed in the screen's accent. A tap on the draft raises
    /// `AskScreen`'s own composer over the keyboard. The face is in the slot
    /// from the Ask tab's first frame, and switching tabs never animates it.
    /// The one exception is a launch at regular width with the bar along the
    /// bottom (`AskComposerSlotPolicy.tabBarRunsAlongBottom`).
    /// An item pushed over the thread takes it out of the slot, and the thread
    /// coming back brings it back, without the host tracking the push
    /// (`AskComposerSlotCover`). So does a reader typing with no keyboard on
    /// screen, on a hardware keyboard: the composer comes up all the same,
    /// and the slot empties for it. Where the tab bar hangs off the top, as an
    /// iPad's does at regular width, the composer stays in the screen's own
    /// bar.
    ///
    /// **The slot is the one view the system moves as the tab bar
    /// minimizes.** Nothing in SDK 27 tells a tab's content that its tab bar
    /// has minimized, so a composer in `AskScreen`'s own bar stays where the
    /// expanded bar reached, over an empty strip beside the minimized one. The
    /// bottom accessory is what Apple Music's mini player rides: above the
    /// expanded bar, beside the selected tab's button once the bar minimizes,
    /// and back up when it expands, all on the system's own animation.
    /// Measured on an iPhone 18 Pro simulator: 360 × 48 pt, 8 pt above the
    /// expanded bar; with the bar minimized, 14 pt right of the Ask button on
    /// its center line.
    ///
    /// **A face, because the slot can't take typing.** A field in the slot
    /// stays under the keyboard whether the bar is expanded or minimized, and
    /// the slot holds one 48 pt line: three typed lines squeeze its field to
    /// 26 pt. So the face waits under the keyboard while the screen's own
    /// composer is up over it, and is there again when the keyboard goes.
    /// Where no keyboard comes, nothing would hide it, so the slot empties
    /// instead (`AskComposerSlotPolicy.showsFace`).
    ///
    /// **The store is all the host hands it.** The slot is mounted on the
    /// `TabView`, away from the screen's arguments, and a host's photo or scan
    /// button opens state that belongs to the screen's own view. So the Ask
    /// screen in the tab hands the face its accent, its spectrum and its
    /// accessory button as it appears and whenever one changes, through the
    /// slot's environment (`askComposerSlotFaceStyle`), and not through the
    /// store, which one app shares across its windows. Until it first
    /// appears, the face draws in the app's accent color with no spectrum and
    /// no accessory button.
    ///
    /// On macOS and visionOS, which have no bottom accessory, this does
    /// nothing, so a host shared across platforms mounts it with no `#if`.
    ///
    /// - Parameters:
    ///   - store: The store the Ask tab's `AskScreen` shows.
    ///   - isEnabled: Whether the Ask tab is the selected one. Turn the slot on
    ///     and off here, never with an `if` inside a builder, which leaves an
    ///     empty glass capsule on the other tabs.
    /// - Returns: The tab view, with the face in its bottom accessory while the
    ///   Ask tab is selected under a tab bar along the bottom and nothing is
    ///   pushed over the thread.
    public func askComposerSlot<Domain: AskDomain>(
        _ store: AskConversationStore<Domain>,
        isEnabled: Bool
    ) -> some View {
        askComposerSlot(store, isEnabled: isEnabled, accessoryIsEnabled: false) { EmptyView() }
    }

    /// Rests the Ask composer in the tab view's bottom accessory, as
    /// `askComposerSlot(_:isEnabled:)` does, and shares the slot with a
    /// bottom accessory the host shows on its other tabs.
    ///
    /// **One accessory, holding either.** A tab view has one bottom accessory,
    /// and how a second `tabViewBottomAccessory` on the same `TabView` gets on
    /// with the first is unmeasured, so the host hands its own over and the
    /// slot shows it wherever the face isn't. On the way out the slot keeps
    /// whichever it last showed, so leaving Ask for a tab with nothing in the
    /// slot doesn't flash the host's accessory in the face's place.
    ///
    /// On macOS and visionOS this does nothing, and `accessory` is never
    /// called.
    ///
    /// - Parameters:
    ///   - store: The store the Ask tab's `AskScreen` shows.
    ///   - isEnabled: Whether the Ask tab is the selected one.
    ///   - accessoryIsEnabled: Where the host's own accessory shows, as the
    ///     host would pass it to `tabViewBottomAccessory(isEnabled:)`. Where
    ///     the face shows too, the face has the slot.
    ///   - accessory: The host's own accessory.
    /// - Returns: The tab view, with the face or the host's accessory in its
    ///   bottom accessory.
    public func askComposerSlot<Domain: AskDomain, Accessory: View>(
        _ store: AskConversationStore<Domain>,
        isEnabled: Bool,
        accessoryIsEnabled: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        modifier(AskComposerSlot(
            store: store,
            isEnabled: isEnabled,
            accessoryIsEnabled: accessoryIsEnabled,
            accessory: accessory()
        ))
    }
}

private struct AskComposerSlot<Domain: AskDomain, Accessory: View>: ViewModifier {
    let store: AskConversationStore<Domain>
    let isEnabled: Bool
    let accessoryIsEnabled: Bool
    let accessory: Accessory

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// What the slot showed last, which it keeps while it goes away.
    @State private var lastShown = AskComposerSlotContent.face
    /// Whether an item is pushed over the screen under this slot, as the
    /// screen reports it. Held here rather than in the store, so a push in a
    /// second window marks its own screen and no other.
    @State private var cover = AskComposerSlotCover()
    /// Whether the tab bar runs along the bottom, as the Ask screen last
    /// reported it (`askComposerSlotTabBar`), or nil before it has.
    @State private var tabBarRunsAlongBottom: Bool?
    /// Whether the Ask screen holds its composer up with no keyboard on
    /// screen, as it reports it (`askComposerSlotHeldUp`). Held here rather
    /// than in the store, as the cover is, so a reader typing in one window
    /// empties only that window's slot.
    @State private var composerIsHeldUp = false
    /// What the face draws with, as the Ask screen last wrote it
    /// (`askComposerSlotFaceStyle`), which it keeps while the screen is away.
    /// Held here rather than in the store, as the cover is, so each window's
    /// face draws its own screen's accent and opens its own screen's picker.
    @State private var faceStyle = AskComposerFaceStyle()
    /// Whether the Ask screen has its composer raised over the face, as it
    /// reports it (`askComposerSlotRaised`). Held here rather than in the
    /// store, so a composer raised in one window hides only that window's face
    /// from VoiceOver.
    @State private var composerIsRaised = false
    /// The face's last request to put the reader in this window's composer
    /// (`askComposerSlotFocusRequest`). Held here rather than in the store, as
    /// the cover is: the store's own request goes to the window that appears
    /// active, which a face tapped in the window at the back isn't yet, so
    /// through the store the composer would come up in the other window
    /// first (ARCHITECTURE.md, "A host's request for the composer", says why
    /// only one window's screen answers a request).
    @State private var focusRequest: UUID?

    func body(content: Content) -> some View {
        let rests = AskComposerSlotPolicy.rests(
            isEnabled: isEnabled,
            tabBarRunsAlongBottom: AskComposerSlotPolicy.tabBarRunsAlongBottom(
                reported: tabBarRunsAlongBottom, isCompactWidth: horizontalSizeClass == .compact
            )
        )
        let shown = AskComposerSlotContent.of(
            showsFace: AskComposerSlotPolicy.showsFace(
                rests: rests, isCovered: cover.isCovered, composerIsHeldUp: composerIsHeldUp
            ),
            accessoryIsEnabled: accessoryIsEnabled
        )
        content
            .tabViewBottomAccessory(isEnabled: shown != nil) {
                switch shown ?? lastShown {
                case .face:
                    AskComposerFace(
                        store: store,
                        style: faceStyle,
                        isUnderRaisedComposer: composerIsRaised,
                        focusComposer: { focusRequest = UUID() }
                    )
                case .accessory: accessory
                }
            }
            // From the first value on, so a slot that first holds the host's
            // accessory keeps that as it goes, rather than the face it starts
            // out naming.
            .onChange(of: shown, initial: true) { _, shown in
                if let shown { lastShown = shown }
            }
            // A composer held up as the reader left the tab is no longer up
            // when they come back, so the face is in the tab's first frame as
            // ever. Written while the tab is down, when no face shows to move.
            .onChange(of: isEnabled) { _, isEnabled in
                if !isEnabled { composerIsHeldUp = false }
            }
            .environment(\.askComposerRestsInSlot, rests)
            // Only while the Ask tab is up. A tab switch takes both away before
            // the screen goes, so it never marks the screen covered, and the
            // screen putting a held-up composer down as it goes writes nothing
            // into the switch, where the write's animation could carry the
            // slot's swap to a host's accessory.
            .environment(\.askComposerSlotCover, isEnabled ? $cover : nil)
            .environment(\.askComposerSlotHeldUp, isEnabled ? $composerIsHeldUp : nil)
            .environment(\.askComposerSlotTabBar, $tabBarRunsAlongBottom)
            // Whether the tab is up or not: the screen writes its style as it
            // appears and as it changes, and puts its composer down as the tab
            // goes, and neither write moves anything on another tab. The style
            // is an object, the same one on every pass, so the screen's writes
            // draw the face again and nothing else.
            .environment(\.askComposerSlotFaceStyle, faceStyle)
            .environment(\.askComposerSlotRaised, $composerIsRaised)
            // The value rather than a binding: the screen only answers it, and
            // a new token for each tap is a change it hears every time.
            .environment(\.askComposerSlotFocusRequest, focusRequest)
    }
}

/// The composer as it rests in the slot, its face: the accessory button, the
/// draft or the placeholder on one line, and the send, in the screen's accent
/// and spectrum (`AskComposerFaceStyle`).
///
/// **A wash, not glass.** The slot draws its own glass capsule, so the accent
/// is painted inside it, at 35%; a second glass layer would be glass on
/// glass.
///
/// **Fixed metrics where the composer's scale.** The slot is 48 pt tall at
/// every text size, and a circle scaled past it would be cut off, so the
/// glyphs keep the composer's default 34 and 44 (`AskComposerMetrics`), and
/// the text stops growing at extra-extra-extra-large. The large content viewer
/// carries the buttons and the line past that, as it does the tab bar's own;
/// a tap on the line raises the composer, which scales all the way.
struct AskComposerFace<Domain: AskDomain>: View {
    let store: AskConversationStore<Domain>
    /// The accent, spectrum and accessory button of the Ask screen under this
    /// slot.
    let style: AskComposerFaceStyle
    /// Whether that screen's own composer is up over this face.
    let isUnderRaisedComposer: Bool
    /// Puts the reader in that screen's composer, and no other window's
    /// (`askComposerSlotFocusRequest`).
    let focusComposer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let glyph = AskComposerMetrics.circle
    private let target = AskComposerMetrics.target

    /// How strongly the face wears the accent: a wash at 35%, inside the
    /// slot's own glass.
    private static var wash: Double { 0.35 }

    private var accent: Color { style.accent }
    private var accessory: AskComposerAccessory? { style.accessory }

    private var action: AskComposerFaceAction {
        .of(isThinking: store.isThinking, draft: store.draft)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let accessory {
                accessoryButton(accessory)
            }
            field
            sendButton
        }
        .padding(.leading, accessory == nil ? 18 : 2)
        .padding(.trailing, 2)
        .frame(maxHeight: .infinity)
        .background(accent.opacity(Self.wash), in: .capsule)
        .disabled(store.composerIsDisabled)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Under the keyboard while the screen's own composer is up over it.
        // Never un-hidden by name: un-hidden that way, the face came back from
        // under the composer with its draft listed as an element of its own
        // over its field button, and an accessibility touch on the field
        // reached the draft instead (`askAccessibilityHidden`).
        .askAccessibilityHidden(while: isUnderRaisedComposer)
        // The send-to-stop `symbolEffect` needs a transaction to run in, and
        // the slot is outside the one `AskScreen` opens on the stage.
        .animation(reduceMotion ? .none : AskStage.animation, value: store.stage)
    }

    private func accessoryButton(_ accessory: AskComposerAccessory) -> some View {
        Button(action: accessory.action) {
            Image(systemName: accessory.systemImage)
                .font(.body)
                .frame(width: glyph, height: glyph)
                .frame(width: target, height: target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // 3:1 over the wash, as on the composer's capsule.
        .foregroundStyle(AskGlassForeground(tint: accent.opacity(Self.wash), minimum: AskGlassForeground.glyph))
        .disabled(store.isThinking)
        .accessibilityLabel(accessory.label)
        .accessibilityIdentifier(accessory.identifier)
        .accessibilityShowsLargeContentViewer()
    }

    /// The draft, or the placeholder, on one line: a tap raises the composer
    /// with the draft in it.
    private var field: some View {
        Button {
            focusComposer()
        } label: {
            line
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: target, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AskComposerWords.yourQuestion)
        .accessibilityValue(Text(verbatim: store.draft))
        // The host's hint about what to ask, as the composer's field has it.
        .accessibilityHint(Text(store.brand.help))
        // Voice Control answers to the words on the face, the draft or the
        // placeholder, as on the composer's field (`AskSpokenName`).
        .accessibilityInputLabels(
            AskSpokenName.inputLabels(
                showing: store.draft.isEmpty ? store.brand.help : store.draft,
                named: AskComposerWords.yourQuestion
            )
        )
        // The line stops growing at extra-extra-extra-large, so past that a
        // long press shows it at the reader's size, as the circles beside it
        // do.
        .accessibilityShowsLargeContentViewer {
            line
        }
        .accessibilityIdentifier(AskAccessibility.slotField)
    }

    /// The draft, or the placeholder while there is none: 4.5:1 over the
    /// wash, as on the composer's capsule.
    @ViewBuilder
    private var line: some View {
        if store.draft.isEmpty {
            Text(store.brand.help)
                .foregroundStyle(AskGlassForeground(tint: accent.opacity(Self.wash), minimum: AskGlassForeground.text))
        } else {
            Text(verbatim: store.draft)
        }
    }

    private var sendButton: some View {
        Button {
            switch action {
            case .stop: store.stop(byReader: true)
            case .send: store.ask(store.draft)
            case .focus: focusComposer()
            }
        } label: {
            Image(systemName: action == .stop ? "stop.fill" : "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(AskSendGlyph(accent: accent, spectrum: style.spectrum))
                .frame(width: glyph, height: glyph)
                // A fill, as on the composer: the slot is already glass.
                .background(AskSendFill(accent: accent, spectrum: style.spectrum), in: .circle)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: target, height: target)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel(buttonLabel)
        // "Stop" as well as "Cancel" for the stop square, as on the composer.
        .accessibilityInputLabels(action == .stop ? [buttonLabel, AskComposerWords.stop] : [buttonLabel])
        .accessibilityIdentifier(AskAccessibility.slotSend)
    }

    /// What VoiceOver calls the circle: what a tap on it does, in the
    /// composer's own words. The arrow on an empty face raises the composer
    /// and sends nothing, so it isn't called Send.
    private var buttonLabel: Text {
        switch action {
        case .stop: Text("Cancel", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button while a question is being answered — it stops the turn.")
        case .send: Text("Send", bundle: #bundle, comment: "VoiceOver label for the Ask composer's send button; and the Mac menu item, shortcut ⌘↩, that sends the question.")
        case .focus: Text("Write a question", bundle: #bundle, comment: "VoiceOver label for the Ask composer's button while the field is empty — it takes the reader to the field to type a question, and sends nothing.")
        }
    }
}
#else
extension View {
    /// Does nothing: the Mac and visionOS have no bottom accessory for the
    /// composer to rest in, so it stays in `AskScreen`'s own bar. The view
    /// comes back unchanged, and a host shared across platforms mounts the
    /// slot with no `#if` around it.
    ///
    /// - Parameters:
    ///   - store: The store the Ask screen shows. Unused here.
    ///   - isEnabled: Whether the Ask tab is the selected one. Unused here.
    /// - Returns: This view, unchanged.
    public func askComposerSlot<Domain: AskDomain>(
        _ store: AskConversationStore<Domain>,
        isEnabled: Bool
    ) -> some View {
        self
    }

    /// Does nothing, and the host's accessory goes unbuilt: it rides the tab
    /// view's bottom accessory, which the Mac and visionOS don't have.
    ///
    /// - Parameters:
    ///   - store: The store the Ask screen shows. Unused here.
    ///   - isEnabled: Whether the Ask tab is the selected one. Unused here.
    ///   - accessoryIsEnabled: Where the host's own accessory shows. Unused
    ///     here.
    ///   - accessory: The host's own accessory. Never called here.
    /// - Returns: This view, unchanged.
    public func askComposerSlot<Domain: AskDomain, Accessory: View>(
        _ store: AskConversationStore<Domain>,
        isEnabled: Bool,
        accessoryIsEnabled: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        self
    }
}
#endif

/// When the slot holds the composer, apart from the view so it can be tested:
/// on every platform, though only iOS has a slot, because the package's tests
/// run on the Mac.
nonisolated enum AskComposerSlotPolicy {
    /// Whether the composer rests in the slot: the host asks for it, and the
    /// tab bar runs along the bottom (`AskScreen.composerMargin` keys on the
    /// same).
    static func rests(isEnabled: Bool, tabBarRunsAlongBottom: Bool) -> Bool {
        isEnabled && tabBarRunsAlongBottom
    }

    /// Whether the tab bar runs along the bottom: what the Ask screen reports
    /// from inside its tab (`tabBarPlacement` is `.bottomBar`), and compact
    /// width until it has.
    ///
    /// **The placement, not the width.** iPhone Duo's inner display is
    /// regular width, and its tab bar still runs along the bottom, as an
    /// iPhone Pro Max's does on its side. Keyed on compact width there, the
    /// composer would stay in the screen's own bar, which a minimizing tab
    /// bar leaves behind (`askComposerSlot` says why the slot exists). An
    /// iPad at regular width hangs the bar off the top, and reports
    /// `.topBar`. The vertical strip iPhone Duo moves the bar into reports
    /// `.bottomBar`, and the face rests at the foot of the column beside it:
    /// measured on iPhone Duo's outer display.
    ///
    /// **Compact width until the screen reports.** The slot sits on the tab
    /// view, outside the tab that hears the placement, so it has nothing to
    /// read before the Ask screen's first update. Compact width is right up
    /// to then except at regular width with the bar along the bottom: iPhone
    /// Duo's inner display and a Pro Max on its side. An Ask tab that
    /// launches there starts with the composer in the screen's own bar, and
    /// the face takes the slot at the screen's first report. Not yet watched
    /// on either.
    static func tabBarRunsAlongBottom(reported: Bool?, isCompactWidth: Bool) -> Bool {
        reported ?? isCompactWidth
    }

    /// Whether the slot shows the face: where the composer rests, unless an
    /// item is pushed over the thread, or the screen holds its composer up
    /// with no keyboard on screen.
    ///
    /// **Out of the way of a composer held up with no keyboard.** Typing on a
    /// hardware keyboard raises the screen's composer with no keyboard coming
    /// over the slot (`AskScreen.composerHeldUp`), and the face stayed in
    /// sight under it: two capsules with one draft, only the upper one taking
    /// typing. Seen on iPhone Duo's outer display, on the 27.1 simulator with
    /// no software keyboard showing. With the slot empty, its inset goes, and
    /// the composer comes up where the face was rather than over it.
    ///
    /// **With the tab, not after the screen.** Waiting for the Ask screen's
    /// `onAppear`, which lands after the tab's first frame, the slot would
    /// come up empty every time Ask is chosen, and then the face would fade
    /// in while the inset it takes grows under the screen: recorded on the demo
    /// on an iPhone 18 Pro simulator, the first screen's column rose 28 pt
    /// over the fade. A tab switch shows the tab as it was left, with no
    /// animation. So nothing about the tab is waited for: the face is in the
    /// slot in the tab's first frame, at launch as well wherever compact width
    /// answers for the placement (`tabBarRunsAlongBottom`), and only what the
    /// screen reports takes it away: a push (`AskComposerSlotCover`), or its
    /// composer held up (`askComposerSlotHeldUp`), which the slot forgets as
    /// the tab goes.
    ///
    /// `rests` alone is what `AskScreen` reads, and neither report reaches
    /// its own bar: a screen with an item pushed over it is off screen, and
    /// one holding its composer up already has it there.
    static func showsFace(rests: Bool, isCovered: Bool, composerIsHeldUp: Bool) -> Bool {
        rests && !isCovered && !composerIsHeldUp
    }
}

/// Whether an item the host pushed over the thread hides the Ask screen under
/// a host's slot: one of the two things that keep the face out of a slot whose
/// tab is up, with the screen's composer held up where no keyboard came
/// (`AskComposerSlotPolicy.showsFace`). The screen reports it as it comes and
/// goes, so a host never tracks its own pushes. Each slot holds its own, so a
/// push in one window marks only that window's screen covered.
///
/// **A push marks the screen covered. A tab switch doesn't.** Both take the
/// screen off. The slot hands the screen its cover only while the Ask tab is
/// up (`askComposerSlotCover`), and a tab switch takes it away before the
/// screen goes. Logged on the demo on an iPhone 18 Pro simulator with iOS
/// 27.0, the host's new selection had re-run the slot, and re-run the screen
/// with the tab down, 10 to 50 ms before the screen's `onDisappear`, on every
/// switch. So a screen that goes with the cover in hand was pushed over, at
/// any width. A push made where the composer sits in the screen's own bar, in
/// a regular-width window, still marks the screen covered once the window
/// turns compact and the composer goes back to the slot: iPhone Duo closing
/// from its inner display onto its outer one, or an iPad window narrowed.
/// Should a disappearance ever arrive first, a switch would read as a push,
/// and the face would wait for the screen and fade in as it appears. The
/// composer is never lost either way.
nonisolated struct AskComposerSlotCover: Equatable {
    private(set) var isCovered = false

    /// The screen is in sight, so nothing is pushed over it.
    mutating func screenAppeared() {
        isCovered = false
    }

    /// The screen went out of sight with its tab up, so something was pushed
    /// over it.
    mutating func screenDisappeared() {
        isCovered = true
    }
}

/// What the slot holds, when it holds anything: the composer's face, or the
/// host's own accessory where the face isn't.
nonisolated enum AskComposerSlotContent: Equatable {
    case face
    case accessory

    /// The face wherever it shows, the host's accessory wherever the host
    /// shows one and the face doesn't, and nil for an empty slot.
    static func of(showsFace: Bool, accessoryIsEnabled: Bool) -> Self? {
        if showsFace { return .face }
        return accessoryIsEnabled ? .accessory : nil
    }
}

/// What the face in a host's tab bar slot draws with: the screen's accent, its
/// spectrum and its accessory button. The host mounts the slot on its `TabView`, away from
/// what it hands the screen, so the Ask screen writes them here as it appears
/// and whenever they change (`askComposerSlotFaceStyle`), and the face reads
/// them.
///
/// **An object the slot holds in its state, compared by identity.** The
/// environment carries the same one on every pass of the slot, so SwiftUI
/// sees no change there, and the screen's writes draw again only the face,
/// which reads them in its body. A value would be a new one on every pass,
/// and the accessory's action is a closure, which never compares equal.
@MainActor
@Observable
final class AskComposerFaceStyle {
    /// The screen's accent, or the app's accent color until it first writes.
    private(set) var accent: Color = .accentColor
    /// The screen's spectrum (`AskSpectrum`), or none, as there is until it
    /// first writes.
    private(set) var spectrum: AskSpectrum?
    /// The button before the field, the screen's
    /// (`AskComposerAccessory.leading`), or none.
    private(set) var accessory: AskComposerAccessory?

    /// The screen's accent, spectrum and accessory button, as it draws them
    /// now.
    func update(accent: Color, spectrum: AskSpectrum?, accessory: AskComposerAccessory?) {
        self.accent = accent
        self.spectrum = spectrum
        self.accessory = accessory
    }
}

/// What the face draws of a screen's style, for the screen to tell when it
/// changes: the accent, the spectrum, and the accessory button's glyph, words
/// and identifier. Not its action, a closure, which can't be compared: the
/// screen writes the action with the rest as it appears and at each change of
/// these.
nonisolated struct AskComposerFaceLook: Equatable {
    var accent: Color
    var spectrum: AskSpectrum?
    var systemImage: String?
    var label: Text?
    var identifier: String?

    @MainActor
    init(accent: Color, spectrum: AskSpectrum?, accessory: AskComposerAccessory?) {
        self.accent = accent
        self.spectrum = spectrum
        systemImage = accessory?.systemImage
        label = accessory?.label
        identifier = accessory?.identifier
    }
}

/// What the face's circle does, by the composer's own rules for a field
/// without focus: a turn in flight stops, a draft sends, and an empty field
/// raises the composer, since a tap there says "I want to ask".
nonisolated enum AskComposerFaceAction: Equatable {
    case stop
    case send
    case focus

    static func of(isThinking: Bool, draft: String) -> Self {
        if isThinking { return .stop }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .focus : .send
    }
}

#endif
