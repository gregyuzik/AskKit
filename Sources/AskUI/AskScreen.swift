#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI
#if !os(macOS)
// For the pasteboard item's type identifier: `setItems(_:options:)` takes a
// dictionary keyed by type, where `.string` takes a bare string.
import UniformTypeIdentifiers
#endif

/// The id of the 12 pt spacer under the last turn: the scroll target for the
/// follow and for the scroll that brings a new question into view. Scrolled to
/// the bottom edge, it puts the foot just above the composer. A constant, not a
/// turn id: the place both scrolls want outlives every turn. At file scope
/// because `AskScreen` is generic, and a generic type can't hold a static
/// stored property.
private let askThreadFoot = "ask.thread.foot"

/// The id of the thread's `LazyVStack` itself: the pill's scroll target.
///
/// **Not the foot, because the foot lives inside the lazy stack and the pill is
/// the one scroll that starts far from it.** A reader far up the thread is out
/// of the stack's built range at the foot, and a `scrollTo` whose target isn't
/// built doesn't end where it lands: SwiftUI keeps the correction pending (a
/// drag doesn't clear it, nor does a later `scrollTo` to a built target) and
/// applies it at the content's next change of height. Traced on an iPhone 17
/// Pro simulator: the pill from the top, a drag up a screen, a card opened in
/// place, and the offset went 149 → 871 → 557 in two frames, throwing the
/// reader back toward a foot they had just left. The stack is always built, so
/// a scroll to its bottom leaves nothing behind: the same sequence held four
/// times on a two-turn thread (at 149, then at 166 three runs running) and at
/// 3259 on an eight-turn one, and the pill still lands with the end of the
/// content at the bottom edge.
///
/// The follow and the scroll that brings a new question into view keep the
/// foot. They start at it or near it, where it is built, and the growth that
/// follows each of them consumes what they ask for.
private let askThreadEnd = "ask.thread.end"

/// The Ask screen: the thread, the first screens, the wait row, the chips, the
/// composer and the toolbar.
///
/// **Everything host-specific arrives as a view builder or through `AskBrand`.**
/// The mark, the tiles under an answer, what the evidence line's chevron opens
/// and anything a host wants beneath an answer are the host's; the thread's
/// behavior is not. Holding that line is what lets every host share one
/// screen. It runs through the tiles too: each tile is the host's, and the bank
/// they sit in is `AskTileGrid`.
///
/// **Hosting it.** Show the screen in a `NavigationStack` titled with
/// `store.brand.title`. The screen sets no title of its own. It puts New Chat,
/// History for a domain that keeps its thread, and on iOS Done in the
/// navigation bar (the window's toolbar on the Mac), with the tier caption
/// under the title where the bar has room for a subtitle. Outside a
/// navigation container none of them has anywhere to render. Beside iPhone
/// Duo's fold the chats are a pane of the screen instead of History's list
/// (`AskFoldArrangement`). The generic
/// parameters are the host's domain and the types of the four views the host
/// draws in the screen: the mark, the tiles, the evidence disclosure and the
/// answer footer. `AskScreen(store:)` draws AskKit's own mark and tiles, and
/// the modifiers below it set the host's views one at a time.
///
/// **What it does on its own.** As it appears, the screen reads the saved
/// thread back, delivers any request to focus the composer that was made
/// before it existed, refreshes the store and lets it warm a session once a
/// question begins. As it goes, it releases that session. When the app comes
/// back to the foreground, it refreshes again.
///
/// Layout animates on `AskStage`, and on the keyboard's two keys: the first
/// screen making room, and the composer rising out of a host's slot. What an
/// answer brings besides its words is drawn in rather than laid out, a piece at
/// a time (`AskArrival`).
public struct AskScreen<Domain: AskDomain, Mark: View, Tiles: View, Disclosure: View, Footer: View>: View {
    /// The host's row type, which the tiles and the other views are handed.
    public typealias Row = Domain.Row

    @Bindable private var store: AskConversationStore<Domain>
    /// Everything else the host hands the screen besides its four views, in
    /// one value a modifier carries over whole (`AskScreenConfiguration`).
    private(set) var configuration: AskScreenConfiguration
    private let mark: (Bool) -> Mark
    /// The bank under an answer. It comes back as one view, so its tiles can
    /// only be brought in one by one from inside it, which is why the bank is
    /// AskKit's `AskTileGrid`.
    ///
    /// Handed the turn with the rows its answer chose. A host that passed the
    /// rows-only builder has it wrapped to leave the turn unread.
    private let tiles: (AskTurn<Row>, [Row]) -> Tiles
    /// What the evidence line's chevron opens, and whether the line has one
    /// (`evidenceDisclosure(_:)`).
    private let evidenceDisclosure: (AskTurn<Row>) -> Disclosure
    /// Drawn under every turn, always visible: a callout, not a disclosure. A
    /// call to action the reader is meant to see, such as a button, can't sit
    /// behind a chevron.
    private let answerFooter: (AskTurn<Row>) -> Footer

    private var accent: Color { configuration.accent }
    private var spectrum: AskSpectrum? { configuration.spectrum }
    private var onNothingAction: (() -> Void)? { configuration.onNothingAction }
    private var onAttach: (() -> Void)? { configuration.onAttach }
    private var composerAccessory: AskComposerAccessory? { configuration.composerAccessory }
    private var buildersToken: AskBuildersToken? { configuration.buildersToken }

    @FocusState private var isComposerFocused: Bool
    /// This screen's identity to the store, which keeps the warm session each
    /// screen wants apart: one store can stand behind a screen in each of
    /// several windows (`AskConversationStore.prewarm(for:)`).
    @State private var screenID = UUID()
    @State private var follow = AskScrollFollow()
    /// Bumped by the jump pill, so its request reaches the `ScrollViewReader`
    /// proxy, which exists only inside that closure. A counter rather than an
    /// id: the pill always means the end, and tapping it twice for the same
    /// last turn has to move the thread both times.
    @State private var jumpRequest = 0
    /// The composer bar's measured height, so the jump pill and the space under
    /// the first screen clear the bar as it is now: the field grows to four
    /// lines. 72 is a placeholder until the bar's first layout is measured.
    @State private var composerHeight: CGFloat = 72

    /// Whether the bar is showing Done.
    ///
    /// **A mirror of `isComposerFocused`, set inside `withAnimation`.** A
    /// `@FocusState` flip arrives from the system outside any transaction, so
    /// a toolbar item keyed on it appears and disappears with no animation
    /// while the bar's own layout animates around it.
    @State private var showsDoneItem = false
    /// Whether the screen's bars are in iPhone Duo's strip at the side of the
    /// display rather than along its top (`AskBarStripReader`). False off
    /// iOS, where there is no strip.
    @State private var barsAreInStrip = false
    /// Whether this screen's own keyboard is up, for the first screen to make
    /// room for: `firstScreenIsMakingRoom` says where it does, and
    /// `AskFirstScreen` how.
    ///
    /// **Changed by the keyboard's own notifications, inside its animation,
    /// and not mirrored from focus.** Handed down inside `withAnimation` on a
    /// focus flip, the column's change animated while the keyboard moved the
    /// scroll view under it, and the two fought: recorded at 120 fps in a host
    /// with a 24 fps `TimelineView` behind the screen, the column rose 55 pt past
    /// its resting place toward the navigation bar and came back in 15 to 29 pt
    /// steps. Changed in `keyboardWillShow` inside `withAnimation`, it overshot
    /// the same way, 79 pt on a cold show; changed there with no animation, it
    /// landed a frame before the keyboard's layout, and the headline jumped
    /// 81 pt in that frame. `AskKeyboard.change(_:to:duration:curve:in:)` has
    /// what works.
    ///
    /// Only for this screen's own field: the notifications are app-wide, and a
    /// keyboard raised anywhere else must not close the column up. But on the
    /// thread as well as the first screen: following that keyboard there is
    /// what lets New Chat, tapped with it up, build the first screen already
    /// making room, and it is what raises the composer out of a host's tab bar
    /// slot on either screen (`composerRests`). On iOS alone: the Mac keeps
    /// focus at rest with no keyboard to make room for, and visionOS draws its
    /// keyboard outside the window. An iPad with a hardware keyboard wasn't
    /// recorded: the show can arrive there for the shortcut bar alone, and the
    /// column would close up for a keyboard that hides little of it.
    @State private var firstScreenMakesRoom = false
    /// The composer up for a reader typing with no keyboard on screen (a
    /// hardware keyboard, Full Keyboard Access, a braille display), where no
    /// show arrives to raise it out of a host's tab bar slot. Set once focus
    /// has held 600 ms without a keyboard; `composerRests` has why. The slot
    /// empties while it's up, so the composer comes up in the face's place
    /// rather than over it (`askComposerSlotHeldUp`), and it's put down as
    /// the screen goes.
    @State private var composerHeldUp = false
    /// Whether the field is in the hierarchy to take a host's request for the
    /// composer: set as the screen's first task delivers a request that was
    /// waiting for it, and cleared as the screen goes. Only from then on does
    /// the window coming to the front deliver a request (`windowAppearsActive`),
    /// so that never focuses a field that isn't there yet, or one a tab switch
    /// has taken away.
    @State private var takesHostFocus = false
    /// The host's request this screen took last, and when, for its window
    /// losing the active appearance just after to hand it on
    /// (`AskHostFocusHandOver`). Nil once handed on, and as the screen goes.
    @State private var hostFocusTake: AskHostFocusTake?
    /// Whether this screen has handed a host's request on and its field still
    /// holds the focus it took for it: the field lets it go once another
    /// window's screen takes the request, and keeps it if this window comes
    /// back to the front and takes it again.
    @State private var hostFocusHandedOver = false
    #if os(iOS)
    /// The keyboard's show and hide, observed for `firstScreenMakesRoom`. An
    /// observation lasts as long as its token, so these last as long as the
    /// screen.
    @State private var keyboardObservations: [NotificationCenter.ObservationToken] = []
    /// The window this screen is in, which the keyboard's change lays out
    /// (`AskKeyboard.change(_:to:duration:curve:in:)`): this screen's and not
    /// the key window, which with two scenes up can be another's. Found by
    /// the probe that reads `windowHeight`.
    @State private var screenWindow = AskScreenWindow()
    #endif
    /// The height of the window this screen is in, for the first screen to
    /// arrange itself by (`AskFirstScreen.isSideBySide`). Zero until measured,
    /// and measured on iOS alone, the one platform where the first screen goes
    /// side by side.
    @State private var windowHeight: CGFloat = 0
    /// What iPhone Duo's fold, where it runs through the screen, decides about
    /// the screen's arrangement (`foldArrangement`). Never a fold off iOS
    /// (`AskFold.read(from:)`).
    @State private var foldReading = AskFoldReading.none
    /// Where the first screen goes around a fold across its scroll view, read
    /// from the scroll view itself (`firstScreenFoldSplit` says when it
    /// applies, and to which first screen).
    @State private var foldSplit: AskFoldSplit?
    /// Which turns have their evidence rows open. Held on the screen and not
    /// in the row, whose own state doesn't outlive the lazy stack rebuilding
    /// it when it scrolls away and back.
    @State private var expandedEvidence: Set<UUID> = []
    /// Whether the thread is moving on this screen's own scroll, until a beat
    /// after the last one (`scrollThreadItself`). The navigation bar holds
    /// open while it is, so only the reader's scroll minimizes it
    /// (`AskNavigationBarMinimization`).
    @State private var threadScrollsItself = false
    /// Counts this screen's own scrolls of the thread, so `threadScrollsItself`
    /// clears a beat after the last of them rather than the first.
    @State private var ownThreadScrolls = 0
    /// Whether the list of chats is up.
    @State private var showsHistory = false
    /// Where VoiceOver's focus goes next, until the element it names takes it
    /// (`AskVoiceOverTarget`): the first screen's headline after New Chat,
    /// and the composer's field after Edit & Resend or a tap on the face in a
    /// host's slot.
    @State private var voiceOverTarget: AskVoiceOverTarget?
    /// Whether Delete All Chats, chosen in the history sheet, has left the
    /// headline's request for the sheet to make as it goes: made while the
    /// sheet is still closing, the focus goes nowhere.
    @State private var headlineAwaitsSheet = false
    /// Whether the thread's first turn takes VoiceOver's focus on its wait
    /// row: set as a starter on the first screen is tapped, since the first
    /// screen and the starter with it go as the thread takes their place
    /// (`AskThreadList.firstWaitRowFocus`). Held here because the thread's
    /// rows don't exist yet at the tap.
    @State private var starterFocusesWaitRow = false
    /// The geometry a tapped chip shares with the question it becomes. Held
    /// here because the two ends are in different turns and only the screen
    /// spans both — see `AskChipMorph`.
    @Namespace private var chipMorph

    /// A fold a host asked the screen to arrange itself around on a device
    /// with none (`askSimulatedFold(_:)`): read in place of the device's own.
    @Environment(\.askSimulatedFold) private var simulatedFold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Whether the host rests the composer in its tab bar's slot
    /// (`askComposerSlot`), which keeps this screen's own composer down until
    /// its keyboard is up (`composerRests`).
    @Environment(\.askComposerRestsInSlot) private var composerRestsInSlot
    /// Whether an item is pushed over this screen, for a host's slot to put
    /// its face away (`AskComposerSlotCover`). This screen reports it, and the
    /// slot hands it down only while the Ask tab is up.
    @Environment(\.askComposerSlotCover) private var slotCover
    /// Where a host's slot hears this screen's accent, spectrum and accessory
    /// button, for its face to draw with (`askComposerSlotFaceStyle`).
    @Environment(\.askComposerSlotFaceStyle) private var slotFaceStyle
    /// Where a host's slot hears that this screen's composer is up over its
    /// face (`askComposerSlotRaised`).
    @Environment(\.askComposerSlotRaised) private var slotRaised
    /// A tap on the face in this window's slot, asking this screen and no
    /// other for the composer (`askComposerSlotFocusRequest`).
    @Environment(\.askComposerSlotFocusRequest) private var slotFocusRequest
    /// Whether this screen's window is the one the reader is in, which takes
    /// a host's request for the composer (`deliverComposerFocus(_:)`).
    ///
    /// **The window's active appearance, not the key window.** With two
    /// windows of the demo side by side on an iPad mini (iOS 27.2), each read
    /// `isKeyWindow` true, its own scene's key window, while this read true in
    /// the window in front alone (UIKit's `activeAppearance`, which SwiftUI
    /// bridges). It moves to a window the reader taps only after the tap's
    /// action has run, which `AskHostFocusHandOver` makes up for. On the Mac
    /// it is AppKit's key window, which a click makes key before its action.
    /// In one window, as on every iPhone, it reads true while the app is in
    /// front, so the screen takes the request as it always has.
    ///
    /// UIKit documents it as the app's being in front on an iPhone and for a
    /// full-screen iPad app, so in iPhone Duo's Split View both windows may
    /// read true (not seen), and on visionOS it wasn't read at all. Wherever
    /// two screens read true, the store gives the request to the first to
    /// claim it, one window and not both
    /// (`AskConversationStore.claimComposerFocus(_:)`). And where none does,
    /// as when the app isn't in front, the request waits for the first window
    /// that comes to the front, rather than going to one picked at random.
    @Environment(\.appearsActive) private var windowAppearsActive
    /// Whether the host has an item pushed over this screen, which keeps the
    /// navigation bar from minimizing (`AskNavigationBarMinimization`).
    @Environment(\.askItemIsPushed) private var itemIsPushed
    // A tab bar along the bottom is where the composer has a capsule to line
    // up with: `composerMargin` says what with. iPadOS hangs the bar off the
    // top in regular width and there is nothing below to match, and the Mac
    // has no size class at all. Outside a tab view, compact width stands in
    // for the placement.
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    /// Where a host's slot hears whether the tab bar runs along the bottom,
    /// which this screen reports from inside its tab
    /// (`AskComposerSlotPolicy.tabBarRunsAlongBottom`).
    @Environment(\.askComposerSlotTabBar) private var slotTabBar
    /// Where a host's slot hears that this screen holds its composer up with
    /// no keyboard on screen (`composerHeldUp`), handed down only while the
    /// Ask tab is up.
    @Environment(\.askComposerSlotHeldUp) private var slotHeldUp
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Compact height is a phone on its side, where the first screen never
    // closes up for the keyboard: `firstScreenIsMakingRoom` says why.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    /// The screen for `store` with `configuration` and the host's four views:
    /// where the public initializer and every modifier end up.
    init(
        store: AskConversationStore<Domain>,
        configuration: AskScreenConfiguration,
        mark: @escaping (Bool) -> Mark,
        tiles: @escaping (AskTurn<Row>, [Row]) -> Tiles,
        evidenceDisclosure: @escaping (AskTurn<Row>) -> Disclosure,
        answerFooter: @escaping (AskTurn<Row>) -> Footer
    ) {
        self.store = store
        self.configuration = configuration
        self.mark = mark
        self.tiles = tiles
        self.evidenceDisclosure = evidenceDisclosure
        self.answerFooter = answerFooter
    }

    private var stage: AskStage { store.stage }

    /// How the screen sits around iPhone Duo's fold, from the last reading:
    /// two panes where the domain keeps its chats and both sides fit
    /// (`AskFoldArrangement.resolve(fold:width:listsChats:)`).
    private var foldArrangement: AskFoldArrangement {
        foldReading.arrangement(listsChats: store.offersHistory)
    }

    /// Whether a fold is on its way through this screen, reported or not:
    /// the bars in iPhone Duo's strip at regular width, which is its inner
    /// display on its side. The outer display has the strip at compact width,
    /// and the inner display upright has no strip. Until the system reports
    /// the fold, a frame after the scene is active, the screen stands in two
    /// even panes (`AskFoldArrangement.awaitingFold(width:)`).
    private var expectsFold: Bool {
        #if os(iOS)
        barsAreInStrip && horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    /// The reader's chats in the pane beside the fold (`AskChatsPane`), loaded
    /// as the pane appears. A chat opens in the conversation beside it, and
    /// the pane stays.
    private var chatsPane: some View {
        AskChatsPane(
            current: store.currentSummary,
            history: store.history,
            accent: accent,
            onOpen: { summary in Task { await store.openThread(summary) } },
            onDelete: { summary in Task { await store.deleteThread(summary) } },
            // Animated as New Chat is, since the chat on screen ends here too.
            onDeleteAll: { withAnimation(reduceMotion ? .none : .snappy) { store.deleteAllThreads(from: screenID) } }
        )
        .task { await store.loadHistory() }
    }

    /// The pane on the leading side of iPhone Duo's fold: the reader's chats,
    /// or the first screen's leading half, what Ask is or why it can't serve,
    /// while they have none and nothing has been asked
    /// (`firstScreenTakesBothPanes`).
    ///
    /// **Nothing until it knows which** (`AskLeadingPane`): before the saved
    /// chats are read, and before the first screen is known where there are
    /// none.
    ///
    /// The change from one to the other is the Stage's, a question asked or
    /// New Chat, or the list's own, a chat deleted, so it rides the Stage's
    /// animation as the conversation beside it does (house rule 4).
    @ViewBuilder
    private var leadingPane: some View {
        Group {
            switch leadingPaneContent {
            case .blank:
                Color.clear
            case .about:
                firstScreenAbout
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            case .chats:
                chatsPane
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : AskStage.animation, value: stage)
    }

    /// Which of the three the leading pane is (`AskLeadingPane`).
    private var leadingPaneContent: AskLeadingPane {
        AskLeadingPane.resolve(
            firstScreenTakesBothPanes: firstScreenTakesBothPanes,
            chatsAreRead: store.hasRestored,
            hasChats: hasChats,
            firstScreenIsKnown: stage.firstScreenIsKnown
        )
    }

    /// Whether the reader has a chat to list: the one on screen, once a turn
    /// of it has ended, or an earlier one.
    private var hasChats: Bool {
        store.currentSummary != nil || !store.history.isEmpty
    }

    /// The banners, the first screen or the thread, the composer under them
    /// and the pill over them: everything but the reader's chats. Beside
    /// iPhone Duo's fold this is the trailing pane (`AskFoldPanes`), which is
    /// why the composer's bar and the pill ride on it and not on the screen:
    /// on the screen, the bar would inset the chats too.
    private var conversation: some View {
        VStack(spacing: 0) {
            quotaBanner
            unreadableThreadBanner
            content
        }
        // The root identifier goes here, on the thread, and not on the whole
        // screen. One level out it swallows `ask.send`: the composer rides in a
        // `safeAreaBar`, and an identifier on the view that owns the bar
        // reaches the bar's contents and overwrites what they set for
        // themselves. Measured on iOS 27, the send button reported `ask.root`,
        // the identifier UI tests find the screen by, so every query for the
        // button matched the screen instead. The thread's own rows kept their
        // identifiers throughout, which hid it until a device was driven.
        .accessibilityIdentifier(AskAccessibility.root)
        .safeAreaBar(edge: .bottom) { composerBar }
        #if os(iOS)
        // The window's height, from behind the screen rather than around it:
        // `AskWindowHeightReader` says why the window's and not a SwiftUI one.
        .background { AskWindowHeightReader(window: screenWindow) { windowHeight = $0 } }
        #endif
        // Below the bar, so the composer is inside the Stage transaction. Above
        // it, the bar's contents are outside every animation scope on the
        // screen, and the send-to-stop `symbolEffect(.replace)`, which needs a
        // transaction to run in, never runs. House rule 4 makes `stage` and the
        // keyboard's two keys layout's only animation keys, and this is also how
        // the composer inherits the Reduce Motion answer rather than restating it.
        .animation(reduceMotion ? .none : AskStage.animation, value: stage)
        // In a glass group of its own, which outlives the pill, so the pill's
        // glass materializes as it comes and goes (`askGlassTransition`).
        //
        // **Animated on whether it shows, inside the overlay alone.** It flips
        // on the follow's reading of a scroll, in an update with no animation
        // of its own, and out here past the Stage's `.animation`: in a screen
        // recording it came and went between one frame and the next, so the
        // glass had no transaction to materialize in. Animated here, recorded
        // on an iPhone 18 Pro simulator, it materialized over six frames and
        // went over five, after a drag and after a tap. Scoped to the overlay,
        // the animation reaches the pill and nothing under it, so no frame of
        // the thread or the composer moves with it (house rule 4).
        .overlay(alignment: .bottom) {
            AskGlassGroup { jumpPill }
                .animation(reduceMotion ? .none : AskStage.animation, value: showsJumpPill)
        }
    }

    public var body: some View {
        // Around iPhone Duo's fold where one runs through the screen: the
        // reader's chats beside the conversation, the first screen's two
        // halves before there are any, or the conversation clear of a bend
        // (`AskFoldArrangement`). Everywhere else the conversation is the
        // whole screen.
        AskFoldPanes(arrangement: foldArrangement, showsHairline: leadingPaneContent == .chats) {
            leadingPane
        } conversation: {
            conversation
        }
        #if os(iOS)
        // Read in the panes' own space, so the fold's x counts from the
        // screen's leading edge, mirrored right to left, and from the screen's
        // whole width, chats included. A reading that decides nothing new, a
        // keyboard changing the screen's height, writes nothing.
        .onGeometryChange(for: AskFoldReading.self) { [simulatedFold, expectsFold] proxy in
            AskFoldReading(
                fold: AskFold.read(from: proxy, simulated: simulatedFold),
                width: proxy.size.width, expectsFold: expectsFold
            )
        } action: { reading in
            foldReading = reading
        }
        #endif
        .toolbar { toolbarItems }
        // The screen's own scroll lets the bar go a beat after its last step:
        // `jumpGlideWindow`, twice the 0.25 s an animated scroll here takes.
        // On the screen and not the thread, so a thread that goes mid-scroll,
        // as New Chat takes it, can't leave the bar held open.
        .task(id: ownThreadScrolls) {
            guard threadScrollsItself else { return }
            try? await Task.sleep(for: .seconds(AskScrollFollow.jumpGlideWindow))
            guard !Task.isCancelled else { return }
            threadScrollsItself = false
        }
        // **The navigation bar minimizes as the reader scrolls down**, SDK 27's
        // `toolbarMinimizationBehavior`, and comes back as they scroll up.
        //
        // **`.never` while the thread moves on the screen's own scroll**
        // (`threadScrollsItself`), so the screen never moves its own chrome
        // while an answer arrives or a chat opens. `.onScrollDown` can't tell
        // whose scroll it read: an earlier chat opened beside a fold minimized
        // the bar every time, and following answers to the foot sometimes did
        // (`AskNavigationBarMinimization`).
        //
        // **`.never` while Done is showing.** A minimized bar hides its items,
        // and Done is one of them: the keyboard would come up under a bar with
        // nothing in it. Pinned, the bar opens as the keyboard arrives, Done is
        // there to put it away, and the bar stays open after it until the
        // reader scrolls down again.
        //
        // **`.never` while the host has an item pushed over the screen**
        // (`askItemIsPushed`), from the push's own update: a page pushed under
        // a minimized bar hangs the app (`AskNavigationBarMinimization`).
        //
        // The navigation bar alone. The tab bar is the host's, which minimizes
        // it with `tabBarMinimizeBehavior(.onScrollDown)` on its own `TabView`:
        // this modifier's `.tabBar` placement minimizes nothing, since SDK 27
        // documents `.navigationBar` as the one placement it supports.
        // iOS only: `.onScrollDown` and `.never` exist nowhere else.
        #if os(iOS)
        .toolbarMinimizationBehavior(
            AskNavigationBarMinimization.minimizes(
                showsDoneItem: showsDoneItem, itemIsPushed: itemIsPushed, threadScrollsItself: threadScrollsItself
            ) ? .onScrollDown : .never,
            for: .navigationBar
        )
        // **While the reader types, the bar strip keeps the screen's items and
        // minimizes the tab bar.** iPhone Duo moves every bar into one strip
        // at the side, and the keyboard shortens it: on the outer display
        // turned there isn't height for the tab bar, Done, New Chat and
        // History together. By default the items overflow first and the tab
        // bar stays, the right order for a screen moved about in, and the
        // wrong one for a reader mid-question, who needs Done to put the
        // keyboard away and has no use for the tabs until they have.
        // Not seen on the device.
        .modifier(AskTypingKeepsBarItems(isTyping: showsDoneItem, barsAreInStrip: $barsAreInStrip))
        #endif
        // **The headline takes VoiceOver's focus once the sheet has gone.**
        // Delete All Chats closes the sheet as it empties the thread, and a
        // focus set while a sheet is still on screen goes nowhere: the request
        // was spent behind it, and the focus went back wherever the system put
        // it as the sheet went (`headlineAwaitsSheet`).
        .sheet(isPresented: $showsHistory) {
            guard headlineAwaitsSheet else { return }
            headlineAwaitsSheet = false
            voiceOverTarget = .headline
        } content: {
            AskThreadHistorySheet(
                current: store.currentSummary,
                history: store.history,
                onOpen: { summary in Task { await store.openThread(summary) } },
                onDelete: { summary in Task { await store.deleteThread(summary) } },
                // Animated as New Chat is, since the chat on screen ends here too.
                onDeleteAll: {
                    headlineAwaitsSheet = true
                    withAnimation(reduceMotion ? .none : .snappy) { store.deleteAllThreads(from: screenID) }
                }
            )
        }
        .askTierCaption(store.captionTier)
        .task {
            await store.restoreIfNeeded()
            // Not for a screen already gone, which would spend a host's
            // request for the composer on a field that isn't there, leaving
            // none for the screen the reader comes back to.
            guard !Task.isCancelled else { return }
            // After a suspension, so the field is in the hierarchy to take it:
            // a request made before this screen existed is still waiting.
            takesHostFocus = true
            deliverComposerFocus(store.composerFocusRequest)
            await store.refresh()
            // Not for a screen already gone. `onDisappear` has released the
            // warm session by then, and arming it again would keep one for a
            // screen nobody is on.
            guard !Task.isCancelled else { return }
            // Arms the warm session rather than making one: it is made as a
            // question begins, since a warm session on Private Cloud Compute
            // costs a request of the reader's daily quota.
            await store.prewarm(for: screenID)
        }
        // The face in a host's tab bar slot (`askComposerSlot`) draws with
        // this screen's accent, its spectrum and the button before its field,
        // handed to this window's slot and no other's. The thread coming back from under a
        // pushed item gives the slot back its face (`AskComposerSlotCover`).
        .onAppear {
            writeSlotFaceStyle()
            updateSlotCover { $0.screenAppeared() }
        }
        // A host's accent can change on screen, such as one that dims with
        // its window, and so can its spectrum and its accessory button.
        .onChange(of: AskComposerFaceLook(accent: accent, spectrum: spectrum, accessory: slotFaceAccessory)) { _, _ in
            writeSlotFaceStyle()
        }
        // The warm session is released on the way out, unless another
        // window's screen is up; the engine keeps it while a conversation is
        // kept.
        //
        // An item pushed over the thread leaves the slot's cover with the
        // screen and marks the screen covered, so the face goes with it. A tab
        // switch has already taken the cover away, and marks nothing.
        .onDisappear {
            updateSlotCover { $0.screenDisappeared() }
            // Focus goes with the screen, and the task that would put a held-up
            // composer down is cancelled with it. Left up, the composer would
            // come back raised over a slot that forgot it as the tab went
            // (`askComposerSlotHeldUp`), two capsules again until the task ran.
            composerHeldUp = false
            takesHostFocus = false
            hostFocusTake = nil
            hostFocusHandedOver = false
            Task { [screenID] in await store.screenDisappeared(screenID) }
        }
        // The slot's face is under the keyboard while the composer is raised,
        // and takes itself out of VoiceOver's way on this. Written only when it
        // changes, since the face reads it.
        .onChange(of: composerRestsInSlot && !composerRests, initial: true) { _, raised in
            guard let slotRaised, slotRaised.wrappedValue != raised else { return }
            slotRaised.wrappedValue = raised
        }
        #if os(iOS)
        // A host's slot sits on the tab view, outside the tab that hears where
        // the tab bar is, so this screen tells it, and the slot holds the face
        // wherever the bar runs along the bottom rather than in compact width
        // alone (`AskComposerSlotPolicy.tabBarRunsAlongBottom`). Written only
        // when it changes, since the slot's whole body reads it.
        .onChange(of: slotHearsBarAlongBottom, initial: true) { _, runsAlongBottom in
            guard let slotTabBar, slotTabBar.wrappedValue != runsAlongBottom else { return }
            slotTabBar.wrappedValue = runsAlongBottom
        }
        // A composer held up where no keyboard came would sit over its own
        // face, so the slot empties while it's up, and the composer comes up
        // in the face's place (`AskComposerSlotPolicy.showsFace`). On the
        // rise's own clock, since the slot giving back its inset is the same
        // rise: the second of the keyboard's two keys (house rule 4).
        .onChange(of: composerHeldUp) { _, heldUp in
            guard let slotHeldUp, slotHeldUp.wrappedValue != heldUp else { return }
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.2)) { slotHeldUp.wrappedValue = heldUp }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            // A tier that was downloading, or off, may be ready now, and a warm
            // session made before the app left may have aged out, which
            // matters only to a question already half-typed. The refresh goes
            // first, so a new warm session is built on the tier that serves
            // now.
            guard phase == .active else { return }
            Task {
                await store.refresh()
                await store.rewarm()
            }
        }
        // New Chat or Delete All emptied the thread: the reader goes to the
        // composer for the next question, and VoiceOver's focus, which was on
        // the thread or the button that emptied it, to the first screen's
        // headline (`AskVoiceOverTarget`). A starter tapped before the last
        // chat ended never reached its wait row, and is forgotten with it.
        //
        // The focus goes to the screen that emptied it, or to every screen
        // where the host did (`threadEndOrigin`). The screen in another window
        // on the store empties too, and takes no focus. From the history
        // sheet, it goes once the sheet has gone (`headlineAwaitsSheet`).
        .onChange(of: store.threadGeneration) { _, _ in
            starterFocusesWaitRow = false
            guard store.threadEndOrigin.map({ $0 == screenID }) ?? true else { return }
            isComposerFocused = true
            guard !headlineAwaitsSheet else { return }
            voiceOverTarget = .headline
        }
        .onChange(of: store.composerFocusRequest) { taken, request in
            // A request this screen handed on went to another window's screen
            // (taken by a claim that wasn't this screen's), so the field here
            // lets go of the focus the earlier request gave it.
            if request == nil, hostFocusHandedOver, taken != hostFocusTake?.request {
                letHandedOverFocusGo()
            }
            deliverComposerFocus(request)
        }
        // A host's request no screen took, because no window on the store was
        // in front as it was made, goes to the window that comes to the front:
        // a launch with the app not yet in front, the Mac's app in the
        // background, the host's own window in front with no Ask screen in it,
        // or a request handed on by the screen whose window this one has just
        // taken the front from (`AskHostFocusHandOver`), which is what this
        // window losing it starts.
        .onChange(of: windowAppearsActive) { _, active in
            guard active else { return handHostFocusOver() }
            guard takesHostFocus else { return }
            deliverComposerFocus(store.composerFocusRequest)
        }
        // The face in this window's slot was tapped: the field here takes
        // focus, and the keyboard coming raises the composer over the face.
        // VoiceOver's focus goes to the field too, since the face it was on
        // goes under the composer, and the field takes it as the composer
        // comes up (`AskVoiceOverTarget`). Not through the store, whose
        // request goes to the window that appears active, which the face's
        // own window, tapped from the back, isn't yet
        // (`AskHostFocusHandOver`): the face's tap is the screen's under it.
        .onChange(of: slotFocusRequest) { _, request in
            guard request != nil else { return }
            isComposerFocused = true
            voiceOverTarget = .field
        }
        .onChange(of: store.isThinking) { _, thinking in
            follow.streamingChanged(thinking)
            // A question asked makes a request for the headline or the field
            // moot: the turn's own wait row, or the reader's place, is where
            // they are now.
            if thinking {
                voiceOverTarget = nil
                headlineAwaitsSheet = false
            }
            // **The keyboard leaves with the question.** A thread here is an
            // answer to read, not a chat to keep typing into, and a keyboard
            // left up hides half a phone's screen while the answer arrives.
            //
            // Keyed on the turn starting rather than on the send button, so a
            // starter, a follow-up chip, a coaching chip, Try Again and Ask
            // again all take the keyboard with them. Touch platforms only: on
            // the Mac, focus is the field's resting state and there is no
            // keyboard to put away.
            //
            // **Through `AskKeyboard`, as the screen's own ways out are.** This
            // runs inside SwiftUI's update, and a resign from inside one is the
            // failure `AskKeyboard` describes. Recorded with the keyboard up on
            // the first screen, a starter's tap written here as
            // `isComposerFocused = false` took the composer to the bottom edge
            // in one frame, behind the keyboard still sliding away, and out of
            // sight for a tenth of a second until the keyboard uncovered it.
            // Put away from the next turn of the main queue, it rode the
            // keyboard down, as it did under a question typed and sent from the
            // thread. Only while the composer has focus, because the resign is
            // app-wide: a turn started while another field is being typed into
            // must not take that field's keyboard.
            #if os(iOS) || os(visionOS)
            if thinking, isComposerFocused { AskKeyboard.putAway($isComposerFocused) }
            #endif
        }
        .onChange(of: isComposerFocused) { _, focused in
            withAnimation(reduceMotion ? .none : .snappy) { showsDoneItem = focused }
        }
        #if os(iOS)
        // The fallback for raising the composer out of a host's slot
        // (`composerHeldUp`). Focus lands 59 to 438 ms before the keyboard's
        // show (logged below, beside the observers), so 600 ms of focus with
        // no show is a reader with no keyboard on screen. Focus dropping takes
        // it down, keyboard or not.
        .task(id: showsDoneItem) {
            guard showsDoneItem else {
                composerHeldUp = false
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, showsDoneItem, composerRestsInSlot, !firstScreenMakesRoom else { return }
            composerHeldUp = true
        }
        // The first screen makes room on the keyboard's clock, and
        // `firstScreenMakesRoom` says why these and not focus. Focus lands
        // before the keyboard shows (logged, 59 to 196 ms before on warm shows
        // and 438 ms on a cold one), so the show can ask whether the field is
        // this screen's. The hide arrives 6 to 14 ms before focus drops, so it
        // can't ask, and has no need to: all it does is undo a show.
        //
        // **UIKit's typed messages, delivered inside the post** as every
        // main-actor message is, so the change still opens its animation in
        // the keyboard's own turn. Observed from the first appearance for as
        // long as the screen exists, and not from a `task`, which would stop
        // at every tab switch and miss a hide arriving then. The closures take
        // the two bindings and the window's holder rather than the screen:
        // they outlive the body that made them, and a binding reads the state
        // as it is now, as the holder reads the window.
        .onAppear {
            guard keyboardObservations.isEmpty else { return }
            let center = NotificationCenter.default
            let focused = $isComposerFocused
            let makesRoom = $firstScreenMakesRoom
            let window = screenWindow
            keyboardObservations = [
                center.addObserver(of: UIScreen.self, for: .keyboardWillShow) { keyboard in
                    guard focused.wrappedValue, !makesRoom.wrappedValue else { return }
                    AskKeyboard.change(
                        makesRoom, to: true, duration: keyboard.animationDuration, curve: keyboard.animationCurve,
                        in: window.window
                    )
                },
                center.addObserver(of: UIScreen.self, for: .keyboardWillHide) { keyboard in
                    guard makesRoom.wrappedValue else { return }
                    AskKeyboard.change(
                        makesRoom, to: false, duration: keyboard.animationDuration, curve: keyboard.animationCurve,
                        in: window.window
                    )
                }
            ]
        }
        #endif
        .onChange(of: store.lastTurnID) { _, id in
            // **A new question lands at the foot of the thread, and the
            // thread follows its own foot as the answer arrives.**
            // `AskScrollFollow` is the whole of that behavior. Why not pin the
            // question to the top: ARCHITECTURE.md, Rejected designs.
            //
            // The reset is meant to land before the first height the new row
            // publishes, so the previous turn's height isn't read as the new
            // one's. **On a send it lands after:** traced, the new row's first
            // height arrived as a shrink from the last turn's, 283 to 78 pt,
            // before this closure ran. A shrink arms nothing, and the next
            // growth still measures up from the zero written here, so nothing
            // was seen to go wrong. The reset also turns the follow on for the
            // first snapshot, which `onScrollGeometryChange` would report too
            // late to be of use. `thread`'s `.task(id:)` does the scrolling,
            // one layout pass later, when the `LazyVStack` has built a row for
            // it to reach.
            //
            // **The two don't run in the order they're written.** Traced on the
            // demo, the `.task` body runs before this closure does: a
            // `.task(id:)` starts as the update is applied, and this fires
            // after. Neither the reset nor the scroll depends on the other.
            guard id != nil else {
                // The thread is gone, and what was measured of it goes too.
                // Kept, the next chat's first short turn would pass the scroll
                // guard on the last thread's `isScrollable` and lift itself
                // under the bar.
                follow = AskScrollFollow()
                return
            }
            follow.turnStarted()
        }
        // Keyed on which turn ended, not on what the line says: two grounded
        // answers in a row produce the same string, and `onChange` on the
        // string alone would announce the first and go silent for the second.
        // House rule 8 wants every terminal state spoken.
        //
        // **Once for the app, and not over a failure line VoiceOver is
        // reading** (`AskSpeechLedger`): a main-actor turn later, so a wait
        // row handing its focus to the failure line in this same update has
        // claimed the ending first, and a second window's screen finds it
        // claimed too.
        .onChange(of: store.lastTerminalTurn) { _, ended in
            guard let ended, let line = terminalAnnouncement(for: ended) else { return }
            Task { @MainActor in
                guard AskSpeech.ledger.claim(.ending(ended)) else { return }
                // `.high`, and an `AttributedString` because that is the only
                // shape the priority can ride on. At default priority
                // VoiceOver speaks the refocused send button over this — the
                // announcement house rule 8 asks for, lost to the focus change
                // that follows it.
                Self.announce(line, priority: .high)
            }
        }
        // **The quota banner says its line once as it arrives**, at low
        // priority, so a reader who can't see it learns that Private Cloud
        // Compute is spent without having to come across the banner. Once for
        // the app however many screens show it, and again only once the quota
        // has come back and been spent again (`AskSpeechLedger`).
        .onChange(of: store.status.quotaReached, initial: true) { _, reached in
            guard reached else { return AskSpeech.ledger.forget(.quotaReached) }
            guard AskSpeech.ledger.claim(.quotaReached) else { return }
            Self.announce(AskQuotaBanner.line(resetDate: store.status.resetDate), priority: .low)
        }
        // **What came of a proposal is spoken once, by the card, and not
        // announced here as well.** A yes or a not now on the card moves
        // VoiceOver's focus to the line where the buttons were
        // (`AskConfirmationCard`), and focus landing reads that line, which
        // is the line `proposalAnnouncement` holds: announced too, the reader
        // heard it twice, or the announcement cut into the focus's reading of
        // it. A hand-off speaks nothing here either: the host's editor opens
        // over the thread and takes the focus, and what the reader hears is
        // the editor. `proposalAnnouncement` stays for a host whose own
        // control confirms or declines, which no card is waiting on.
    }

    /// Over the thread, not in it: the quota is a fact about the next question,
    /// not about any turn that has already run.
    ///
    /// Glass that comes and goes, so it materializes, in a glass group of its
    /// own that holds nothing while it's away (`askGlassTransition`).
    ///
    /// **Animated on whether it shows, on the group alone**, as the jump pill
    /// is (`conversation`): the quota is read from the seam, in an update with
    /// no animation of its own, so the glass had no transaction to
    /// materialize in. On the group, so the animation is the banner's and not
    /// the thread's below it (house rule 4). Neither banner has been watched
    /// arriving on a simulator: the demo can't spend a quota or write a thread
    /// that doesn't decode.
    private var quotaBanner: some View {
        AskGlassGroup {
            if store.status.quotaReached {
                AskQuotaBanner(
                    resetDate: store.status.resetDate,
                    canRequestMore: store.status.hasLimitIncreaseSuggestion,
                    onShowOptions: { Task { await self.store.showLimitIncrease() } }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                .askReadingColumn()
                .askGlassTransition(reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? .none : AskStage.animation, value: store.status.quotaReached)
    }

    /// Over the first screen, never over a thread: it explains an empty screen
    /// where the reader's chat used to be, and goes once something fills it.
    /// It materializes as the quota banner does, on an animation of its own.
    private var unreadableThreadBanner: some View {
        AskGlassGroup {
            if store.showsUnreadableThreadNotice {
                AskUnreadableThreadBanner()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .askReadingColumn()
                    .askGlassTransition(reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? .none : AskStage.animation, value: store.showsUnreadableThreadNotice)
    }

    @ViewBuilder
    private var content: some View {
        if case .thread = stage.phase {
            thread
        } else if stage.firstScreenIsKnown {
            firstScreen
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        } else {
            // No first screen until the library has been read, while every
            // library reads as empty (`AskStage.firstScreenIsKnown`). Clear
            // rather than absent, so the composer keeps its place at the bottom
            // of the screen.
            Color.clear
        }
    }

    /// **A scroll view, because the first screen has to survive a reader who
    /// needs large text.** Centered and unscrollable, it truncates instead of
    /// wrapping at Accessibility XXL: the headline, the sentence, the caveat
    /// and the disclosure each cut to one line with an ellipsis, on the one
    /// screen whose whole job is to say what Ask can do and where the question
    /// goes. A `VStack` given less height than it needs compresses its text
    /// rather than overflowing, and nothing about that is visible at the
    /// default size.
    ///
    /// **Three anchors, one for each kind of change, and none keyed on focus.**
    /// `.defaultScrollAnchor(.center)` alone centers the content whether or not
    /// it fits, so a column taller than the viewport opens scrolled to its own
    /// middle: the mark cut in half by the navigation bar and the disclosure
    /// under the composer, clipped at both ends with nothing to say either is
    /// there. A keyboard makes that ordinary: it takes about half the screen,
    /// leaving this column about 436 pt on an iPhone 17 Pro against the 525 pt
    /// or so it wants at the default text size.
    /// - `.initialOffset` opens an overflowing column at the top: at the
    ///   accessibility sizes, the headline is what a reader wants first.
    /// - `.alignment` centers a column that fits, which includes a column
    ///   making room under the keyboard. It also moves a column the keyboard
    ///   still makes overflow: the column stops fitting, the scroll view keeps
    ///   its center where it was, and that lifts the chips and the disclosure
    ///   above the composer, where the reader about to type can reach them,
    ///   while the mark scrolls away under the bar rather than being cut. A
    ///   column that still fits under the keyboard is re-centered both ways:
    ///   the centering inset changes and the column stays scrolled to its top.
    /// - `.sizeChanges` is `.bottom`, but the keyboard never reaches it at the
    ///   default text size: `.bottom`, `.top` and no anchor at all recorded
    ///   identically, read frame by frame.
    ///
    /// The anchors bring a column the keyboard makes overflow up, and never
    /// take it back down: `AskInRangeScrollTarget` does that. Either way the
    /// column moves with the keyboard only while the keyboard isn't put away
    /// from inside a SwiftUI render, which `AskKeyboard` keeps the screen's own
    /// ways out from doing.
    ///
    /// **Making room.** Keyed on focus, the column's change would pop, since a
    /// focus flip isn't a Stage change and nothing animates it; and closing
    /// the gaps alone doesn't make the column fit. So the column makes room on
    /// the keyboard's own animation (`firstScreenMakesRoom`), and
    /// `AskFirstScreen` lets its sentence and caveat go as well as closing its
    /// gaps, so the column fits through extra-large text. Above that it doesn't
    /// make room at all (`firstScreenIsMakingRoom`).
    ///
    /// **The anchors are chosen, not measured.** Why not measure the column:
    /// ARCHITECTURE.md, Rejected designs. The window's height is read
    /// (`AskWindowHeightReader`), from UIKit and not from this scroll view, and
    /// only to choose the column's arrangement.
    private var firstScreen: some View {
        ScrollView {
            VStack(spacing: 0) {
                // What to ask alone where the screen takes both panes beside
                // iPhone Duo's fold: what only informs is in the leading pane
                // (`firstScreenAbout`).
                firstScreenView(
                    firstScreenTakesBothPanes ? .ask : .whole
                )
                .frame(maxWidth: .infinity)
                // Around a fold across it, where there is one: what only
                // informs above the fold and what to tap below
                // (`AskFoldSplit`).
                .environment(\.askFoldSplit, firstScreenFoldSplit)
                // Trimmed on a phone on its side over a host's slot, where the
                // tab bar and the face take the foot of the screen
                // (`AskFirstScreenArrangement.trimsOverSlot`).
                .environment(\.askFirstScreenIsOverSlot, firstScreenIsOverSlot)
                // Half the lead in compact height, where the screen has little
                // height to spare. None around a fold, whose halves are
                // measured from the bar's edge.
                .padding(.top, firstScreenLead)
                // Space under the column for the composer bar
                // (`firstScreenSpaceUnder`).
                Color.clear.frame(height: firstScreenSpaceUnder)
            }
            .askDismissesKeyboardOnTap($isComposerFocused)
        }
        #if os(iOS)
        // A fold across the scroll view, read from the scroll view and not
        // from its content, which moves as it scrolls: the scroll view's
        // frame holds still, so the split never chases the scroll. What the
        // bars and the composer leave is that frame, whole, because the
        // scroll view is laid out inside them
        // (`AskFoldSplit.around(_:height:)`).
        .onGeometryChange(for: AskFoldSplit?.self) { [simulatedFold] proxy in
            AskFoldSplit.around(AskFold.read(from: proxy, simulated: simulatedFold), height: proxy.size.height)
        } action: { split in
            foldSplit = split
        }
        #endif
        // `.initialOffset` stays `.top`, and one path is knowingly left with it
        // wherever a column still overflows under the keyboard: New Chat tapped
        // from a thread whose field had focus builds this screen straight into
        // the keyboard-sized container, so no size change fires, and the
        // column opens from the top with its last chip under the composer.
        // Where the column makes room, that path fits, because
        // `firstScreenMakesRoom` is already true when the screen is built:
        // recorded at the default text size, the screen came in making room,
        // mark to disclosure above the composer, and nothing on it moved once
        // the blur had cleared.
        //
        // Opening from the bottom when the field has focus
        // (`isComposerFocused ? .bottom : .top`) is the obvious fix, and isn't
        // taken: a first screen built already scrolled to its end under an up
        // keyboard is where `.interactively` was seen to strand the keyboard
        // half-way down, and whether `.immediately` does the same wasn't
        // measured. A chip a scroll reaches isn't worth finding out on a
        // reader. Every other way the keyboard meets this screen arrives as a
        // size change.
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(.center, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        // The way back down, on iOS alone. A target behavior also decides
        // where a finger's scroll comes to rest, so it reaches no platform
        // beyond the one the stranding was measured on. That was an iPhone;
        // the iPad shares its platform and is unmeasured there.
        #if os(iOS)
        .scrollTargetBehavior(AskInRangeScrollTarget())
        #endif
        // `.always` on iOS, so a drag has travel when the column fits:
        // `.immediately` dismisses on a drag, and a scroll view that won't move
        // for a column shorter than itself gives the finger nothing to drag.
        // Everywhere else a column that fits stays still.
        #if os(iOS)
        .scrollBounceBehavior(.always)
        #else
        .scrollBounceBehavior(.basedOnSize)
        #endif
        // The first screen sits under the same bar and passes under it the
        // moment the keyboard makes it scrollable. Each platform treats it as
        // it treats the thread: iOS takes the SDK's automatic edge effect and
        // the Mac hides the effect, and `threadScroll` says why.
        #if os(macOS)
        .scrollEdgeEffectHidden(true, for: .top)
        #endif
        // The composer sits under this screen too, so the keyboard can be up
        // here just as over the thread. Same mode, same platform gate and the
        // same ways out as `threadScroll`, which says why. A first screen
        // scrolled to its end under an up keyboard is one of the two places
        // `.interactively` stranded the keyboard.
        #if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
    }

    /// Whether the first screen makes room for the keyboard: on the ready
    /// screen, under this screen's own keyboard, and at a text size where the
    /// column making room was seen to fit.
    ///
    /// **Through extra-large, because making room costs the space under the
    /// column.** A column that fits wants 12 pt under it and no more; a column
    /// that overflows wants the whole space, which is what keeps its disclosure
    /// clear of the composer. Recorded on an iPhone 17 Pro with the column
    /// making room at every size, it fit at large and at extra-large. At
    /// extra-extra-large the disclosure's second line went under the composer,
    /// at extra-extra-extra-large most of the disclosure did, and at the first
    /// accessibility size the mark went under the navigation bar while the
    /// third starter went under the composer with the disclosure. Above
    /// extra-large the screen keeps its copy, its gaps and its whole space. The
    /// column's height is the host's copy's, so a host with longer copy than
    /// the column recorded here may not fit at extra-large.
    ///
    /// **The ready screen alone.** It is the one that closes up, and the one
    /// recorded doing it: `AskFirstScreen`'s `spacing` says why the other two
    /// keep their gaps, and they keep their space with them.
    /// `firstScreenMakesRoom` follows the keyboard whatever the screen, because
    /// the notifications' guards read it, and because every first screen's
    /// arrangement around a fold across it ends on it (`firstScreenFoldSplit`).
    ///
    /// **Never in compact height.** Every size above was recorded on a phone
    /// held upright. Turned on its side, an iPhone 18 Pro has 402 pt in all,
    /// and the keyboard leaves the column a sliver between the navigation bar
    /// and the composer, so no column fits there, closed up or not, and the
    /// copy and the gaps stay put. iPhone Duo's outer display is the same case
    /// turned. Upright, that display is regular height but 678 pt tall, and
    /// closed up isn't enough there: the keyboard left the column 238 pt of
    /// the 314 it wants, so in a window that short the mark and the headline go
    /// too (`AskFirstScreenArrangement.shortMakingRoomHeight` has the
    /// measurements).
    private var firstScreenIsMakingRoom: Bool {
        firstScreenMakesRoom && firstScreenWouldMakeRoom
    }

    /// Whether the first screen makes room once this screen's keyboard is up
    /// (`firstScreenIsMakingRoom` says where and why), which the space under
    /// its column reads with the keyboard down too.
    private var firstScreenWouldMakeRoom: Bool {
        stage.phase == .ready && dynamicTypeSize <= .xLarge && !isCompactHeight
    }

    /// The first screen's column, whole or one half of it
    /// (`AskFirstScreenPart`). The same arguments either way, so the two
    /// halves in two panes close up for the keyboard as one column does, and
    /// both hear the keyboard the same.
    private func firstScreenView(_ part: AskFirstScreenPart) -> some View {
        AskFirstScreen(
            phase: stage.phase,
            brand: store.brand,
            starters: store.availableStarters,
            policy: store.domain.firstScreenPolicy,
            isMakingRoom: firstScreenIsMakingRoom,
            windowHeight: windowHeight,
            onStarter: { starter in
                starterFocusesWaitRow = true
                store.ask(starter)
            },
            onNothingAction: onNothingAction,
            onDecline: { store.decline($0) },
            mark: mark
        )
        .environment(\.askFirstScreenPart, part)
        // The keyboard itself, for the two first screens that don't make
        // room: what they animate the end of a fold's arrangement on
        // (`AskFirstScreen.onKeyboard`).
        .environment(\.askFirstScreenKeyboardIsUp, firstScreenMakesRoom)
        // The headline takes VoiceOver's focus after New Chat.
        .environment(\.askVoiceOverTarget, $voiceOverTarget)
    }

    /// The lead over the first screen's column: 24 pt, 12 in compact height,
    /// and none where it is arranged around a fold across it.
    private var firstScreenLead: CGFloat {
        firstScreenFoldSplit != nil ? 0 : isCompactHeight ? 12 : 24
    }

    /// The space under the first screen's column, for the composer bar: the
    /// bar's height and 24 pt more, 12 pt (`keepsWholeSpace` says when), or
    /// none around a fold.
    ///
    /// **The whole space keeps the disclosure above the bar's glass.** With
    /// the keyboard up, a column that no longer fits keeps its center, which
    /// leaves the content's last 83 pt under the glass; this space is what
    /// goes there, so the disclosure stays above the capsule instead of behind
    /// it. Measured on the demo, the bar's height alone left the disclosure
    /// 18 pt inside the capsule's top, so the 24 pt also pays for the bar's own
    /// spacing above the keyboard.
    ///
    /// **12 pt where the whole space does no good**, since the space is
    /// content too, and the whole of it under a column that otherwise fits
    /// tips it back into overflowing.
    ///
    /// **None around a fold**: the column fills what the bars leave, down to
    /// the composer's edge, in two halves or with its lower half empty, and
    /// the keyboard never meets it, since its show ends the split
    /// (`firstScreenFoldSplit`).
    private var firstScreenSpaceUnder: CGFloat {
        if firstScreenFoldSplit != nil { return 0 }
        return AskFirstScreenArrangement.keepsWholeSpace(
            isMakingRoom: firstScreenIsMakingRoom,
            isCompactHeight: isCompactHeight,
            wouldMakeRoom: firstScreenWouldMakeRoom,
            windowHeight: windowHeight
        ) ? composerBarHeight + 24 : 12
    }

    /// Whether the first screen on show has two halves to part around iPhone
    /// Duo's fold: the ready one, and the one that can't serve while it keeps
    /// its starters (`AskFirstScreenArrangement.hasTwoHalves`). From the
    /// starters the screen is handed, the ones the reader hasn't passed over.
    private var firstScreenHasTwoHalves: Bool {
        AskFirstScreenArrangement.hasTwoHalves(
            phase: stage.phase,
            answersWithoutModel: store.domain.firstScreenPolicy.answersWithoutModel,
            hasStarters: !store.availableStarters.isEmpty
        )
    }

    /// Whether the first screen takes both panes beside iPhone Duo's fold:
    /// what only informs in the leading pane, where the reader's chats will
    /// be listed once there is one, and what to ask in the conversation's
    /// (`AskFirstScreenArrangement.takesBothPanes`). Not before the first
    /// screen is known, when the conversation's pane shows none.
    private var firstScreenTakesBothPanes: Bool {
        AskFirstScreenArrangement.takesBothPanes(
            hasTwoPanes: foldArrangement.listsChats,
            hasTwoHalves: firstScreenHasTwoHalves && stage.firstScreenIsKnown,
            hasChats: hasChats,
            chatsAreRead: store.hasRestored,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    /// What only informs, in the pane on the leading side of iPhone Duo's
    /// fold: the first screen's other half, what Ask is or why it can't
    /// serve, while the reader has no chats to list there.
    ///
    /// **On one line with the half across the fold.** The conversation's
    /// column is centered in what its composer leaves, so this one keeps the
    /// same lead and the same space under it, and stands clear of the
    /// composer's height as if the bar ran under it too. Without that it is
    /// centered in the whole pane, half the bar's height lower than the
    /// starters it belongs beside.
    ///
    /// A scroll view for the reason the conversation's is one: at a large
    /// text size, or over a keyboard, the copy wraps and scrolls rather than
    /// being cut. Centered where it fits, which is nearly always.
    private var firstScreenAbout: some View {
        ScrollView {
            VStack(spacing: 0) {
                firstScreenView(.about)
                    .frame(maxWidth: .infinity)
                    .padding(.top, firstScreenLead)
                Color.clear.frame(height: firstScreenSpaceUnder)
            }
            .askDismissesKeyboardOnTap($isComposerFocused)
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaPadding(.bottom, composerBarHeight)
    }

    /// Where the first screen goes around a fold across it: iPhone Duo's
    /// inner display upright, flat or bent into a tabletop.
    ///
    /// **Two halves part at the fold, flat or bent**: the ready screen's, and
    /// those of the one that can't serve while it keeps its starters
    /// (`firstScreenHasTwoHalves`). **A screen with none keeps clear of a
    /// bend alone**: the nothing-to-ask screen and the one that can't serve
    /// with no starters stand in the upper half of a tabletop, and lying flat
    /// they get no split, so they keep the lead and the space under them and
    /// stay the one column they are with no fold
    /// (`AskFirstScreenArrangement.foldSplit(_:hasTwoHalves:)`).
    ///
    /// **Not while this screen's keyboard is up.** The keyboard covers the
    /// lower half, and the column is one column instead, centered in what the
    /// keyboard leaves, as it is on any phone. The keyboard's hide brings
    /// the arrangement back on the keyboard's first key (house rule 4): the
    /// ready column animates it on its making room, which ends in the same
    /// update wherever it makes room, and the other two on the flag itself
    /// (`AskFirstScreen.onKeyboard`, which has why the split is in hand by
    /// then, and what its show does). Above extra-large text the ready
    /// screen doesn't make room (`firstScreenIsMakingRoom`), and nothing
    /// animates its split there.
    ///
    /// **Not at the accessibility sizes**, where a half outgrows its side and
    /// the column scrolls anyway.
    private var firstScreenFoldSplit: AskFoldSplit? {
        guard !firstScreenMakesRoom, !dynamicTypeSize.isAccessibilitySize else { return nil }
        return AskFirstScreenArrangement.foldSplit(foldSplit, hasTwoHalves: firstScreenHasTwoHalves)
    }

    /// Whether the first screen sits over a host's slot with a tab bar along
    /// the bottom under it: the composer rests in the slot, and the tab bar is
    /// under the face rather than in iPhone Duo's strip at the side, where it
    /// takes none of the screen's height. `tabBarPlacement` reads `.bottomBar`
    /// in the strip too, so the strip is asked for by name (`barsAreInStrip`).
    private var firstScreenIsOverSlot: Bool {
        #if os(iOS)
        composerRestsInSlot && tabBarRunsAlongBottom && !barsAreInStrip
        #else
        false
        #endif
    }

    /// A phone on its side, or iPhone Duo's outer display turned.
    private var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: - The thread

    /// How every scroll on this screen moves: bringing a new question into
    /// view, following an answer as it is written, and the pill's way back
    /// down.
    ///
    /// **One curve for all three, and not a spring.** A spring overshoots, and
    /// a scroll view that overshoots its own foot pulls the newest line back
    /// off the bottom of the screen before it comes to rest: the reader
    /// watches the text they're reading bounce. `easeOut` also blends when it is
    /// interrupted, which is the case that matters: the reveal delivers a line
    /// about every 180 ms, so each follow retargets while the one before it is
    /// still decelerating, and the steps read as one continuous roll rather
    /// than as a stack of jumps. Long enough to be motion at a line's distance,
    /// and short enough that a tile grid arriving whole, the biggest single
    /// growth a turn has, is carried rather than dwelt on.
    ///
    /// Reduce Motion takes the position without the travel, which is house
    /// rule 8's answer here.
    private var threadMotion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.25)
    }

    /// The follow holds while the last of a finished answer's prose is still
    /// being drawn, and then takes the reader to the foot.
    ///
    /// **A turn's last growth is everything under the prose at once.** The
    /// turn settles, and in that one layout the tiles, the evidence line, the
    /// cards, the callout and the chips all land together, several hundred
    /// points of them, while the sentence above them is still being drawn.
    /// Following that growth to the foot carries the sentence off the top of
    /// the viewport mid-sweep, so the reader scrolls back up to prose that
    /// finished drawing without them, which is indistinguishable from prose
    /// that never drew at all: to the reader, the text popped in with no
    /// animation once the tiles were showing.
    ///
    /// **A cloud-tier shape.** The on-device tier writes a few characters at a
    /// time, and each sweep is over long before the answer is, so the ink has
    /// always finished by the last growth. One chunk the size of a Private
    /// Cloud Compute snapshot lands *with* the answer and is still drawing when
    /// the rest of the answer arrives under it. The demo, which answers on
    /// device, never shows it.
    ///
    /// **Only at the end of a turn.** Mid-stream a growth arrives about every
    /// 180 ms and a chunk takes 330 ms to settle, so a wait on every growth
    /// would hold every follow for longer than the gap to the next one, and the
    /// thread would never keep up at all. The chips land a frame later and
    /// restart the task with whatever ink is left, so the remainder is measured
    /// again rather than waited twice.
    ///
    /// Bounded by the sweep itself: `AskArrivals.settle(forLength:)` stops
    /// growing at 0.75 s (the 0.5 s longest sweep and the 0.25 s fade), so this
    /// waits at most 0.75 s, and less in practice, since the prose lands a beat
    /// before the rest. Nothing under Reduce Motion, where there is no sweep
    /// to wait for.
    private func waitForChunksToSettle() async {
        guard !reduceMotion, let turn = store.turns.last, turn.isComplete else { return }
        // The same clock the stamps were written against and the same one
        // `AskArrival` reads: the store's, whose default this is.
        let remaining = AskArrivals.timeUntilSettled(turn.chunks, at: Date.timeIntervalSinceReferenceDate)
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    /// Scrolls the thread on this screen's own account, never the reader's,
    /// and holds an open navigation bar open until a beat after
    /// (`threadScrollsItself`).
    ///
    /// **A bar the reader minimized is left minimized.** The scroll is down
    /// the thread, which `.onScrollDown` never answers by opening the bar, and
    /// `.never` would open it: measured on an iPhone 18 Pro simulator, a bar
    /// the reader's scroll had minimized opened as the pill's jump began.
    private func scrollThreadItself(_ scroll: () -> Void) {
        if !follow.barLooksMinimized { threadScrollsItself = true }
        ownThreadScrolls += 1
        scroll()
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            threadScroll
                // **`.task(id:)`, not `onChange`.** Both see the new turn, but
                // only this one runs after the update that appended it has been
                // laid out, and a scroll issued before the `LazyVStack` has
                // built the row resolves against the content as it was and does
                // nothing at all. Measured through three spellings of the
                // scroll (`scrollPosition(id:)`, `ScrollPosition.scrollTo` and
                // this proxy): the timing, not the API, decides it.
                //
                // It also runs on the thread's first appearance, which is
                // right: arriving at a restored conversation should show its
                // end.
                .task(id: store.lastTurnID) {
                    guard store.lastTurnID != nil else { return }
                    follow.jumped()
                    // **The end of the thread, whatever brought us here.** One
                    // target and one anchor: a question the reader just sent
                    // is at the end, and so is the answer they came back to on
                    // a restored conversation. Why not the top of the screen:
                    // ARCHITECTURE.md, Rejected designs.
                    guard follow.isScrollable else { return }
                    scrollThreadItself {
                        withAnimation(threadMotion) {
                            proxy.scrollTo(askThreadFoot, anchor: .bottom)
                        }
                    }
                }
                // **The follow.** Keyed on the last turn's measured height
                // rather than on its text, so it fires once per layout that
                // actually grew: the reveal repainting the same glyphs can't
                // reach it, and neither can a keyboard or a composer growing a
                // line.
                //
                // **Animated.** House rule 4 is about what the reveal does to
                // the text, and carrying the reader to text already drawn
                // doesn't pace it. An instant follow jumps the thread by a line
                // every 180 ms, and by a whole tile grid when the tiles land.
                // `threadMotion` says why the curve is what it is.
                //
                // **A task, with a check after it.** The scroll a turn's last
                // growth asks for doesn't reliably arrive, and when it falls
                // short the chips sit under the composer with no pill:
                // `AskScrollFollow.fellShort(since:)` has the three ways it was
                // traced doing so. Every growth restarts the task and cancels
                // the wait, so only a growth that nothing follows for
                // `followQuiet` (500 ms) is checked: a turn's last one always,
                // a pause mid-stream sometimes.
                //
                // **The check's own scroll is instant**, because an animated
                // one is what fell short, and an instant one frees a scroll
                // view stuck in `.animating`. Measured on an iPhone 17 Pro
                // simulator over eight sends, typed and chip, every one ended
                // with the chips above the composer. Two of the eight turns
                // stuck as traced (the chips' 116 pt landing about 20 ms into
                // the follow's animation, then no geometry and no phase), and
                // both times the check's scroll took the thread to its foot and
                // the phase back to `.idle` 14 ms after it fired. The other
                // checks found nothing to finish.
                //
                // **On iOS alone**, where the traces came from. The check tells
                // the reader from the thread by scroll phase, so a reader's
                // scroll that reports no hold is one it would undo, and no
                // other platform's phases were measured; a Mac's wheel is the
                // one to fear. The iPad shares the platform and takes the check
                // unmeasured. Everywhere else the follow is the task alone.
                //
                // **And it lets a finished answer's ink finish first**:
                // `waitForChunksToSettle` has the whole of that, and why it
                // reaches no other growth.
                .task(id: follow.lastTurnHeight) {
                    guard !Task.isCancelled, follow.lastTurnHeight > 0, follow.followsGrowth else { return }
                    await waitForChunksToSettle()
                    // Asked again, because the wait is long enough for a reader
                    // to have put a finger on the thread, and carrying them
                    // back from somewhere they chose to be is the one thing
                    // this screen never does.
                    guard !Task.isCancelled, follow.followsGrowth else { return }
                    scrollThreadItself {
                        withAnimation(threadMotion) {
                            proxy.scrollTo(askThreadFoot, anchor: .bottom)
                        }
                    }
                    #if os(iOS)
                    let holds = follow.readerHolds
                    try? await Task.sleep(for: AskScrollFollow.followQuiet)
                    guard !Task.isCancelled, follow.fellShort(since: holds) else { return }
                    scrollThreadItself { proxy.scrollTo(askThreadFoot, anchor: .bottom) }
                    #endif
                }
                // **A resize keeps a reader at the foot there**: a phone turned
                // on its side, a window dragged, iPhone Duo opened or closed.
                // `AskScrollFollow.geometryChanged(_:at:)` decides who is kept,
                // and asks again for every sample the resize leaves short.
                // Instant, because the resize is already the motion: a glide
                // after it would be a second one.
                //
                // Asked again rather than read off the count, because the task
                // also runs each time the thread appears, with whatever count
                // the last resize left, beside the glide that brings the newest
                // question into view.
                .task(id: follow.footRequests) {
                    guard follow.keepsFootThroughResize, follow.isScrollable else { return }
                    scrollThreadItself { proxy.scrollTo(askThreadFoot, anchor: .bottom) }
                }
                .onChange(of: jumpRequest) { _, _ in
                    scrollThreadItself {
                        withAnimation(threadMotion) {
                            // The stack's bottom, not the foot inside it:
                            // `askThreadEnd` has the trace.
                            proxy.scrollTo(askThreadEnd, anchor: .bottom)
                        }
                    }
                }
        }
    }

    private var threadScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AskScrollFollow.turnSpacing) {
                // The one body on the screen that reads `turns`:
                // `AskThreadList` says why it is a view of its own.
                AskThreadList(
                    store: store,
                    follow: follow,
                    expandedEvidence: $expandedEvidence,
                    firstWaitRowFocus: $starterFocusesWaitRow,
                    accent: accent,
                    spectrum: spectrum,
                    morph: chipMorph,
                    mark: mark,
                    tiles: tiles,
                    evidenceDisclosure: evidenceDisclosure,
                    answerFooter: answerFooter,
                    buildersToken: buildersToken,
                    onCopy: { copy($0) },
                    onEdit: { editAndResend($0) }
                )
                // A 12 pt spacer under the last turn, so the newest line is
                // never pinned against the bar, and the scroll target for the
                // follow and for the scroll that brings a new question into
                // view, both of which want the end of what has been written.
                // The pill wants the same place and asks for it through the
                // stack's own id; `askThreadEnd` says why.
                //
                // A constant, and the only thing kept under the last turn. Why
                // not a screen's height of space for a question pinned at the
                // top to be answered into: ARCHITECTURE.md, Rejected designs.
                Color.clear
                    .frame(height: AskScrollFollow.restingTrailingSpace)
                    .id(askThreadFoot)
            }
            .id(askThreadEnd)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .askReadingColumn()
            // A hook a host can act on. Without it, a host that wants to redact
            // the thread (backgrounding, screen sharing, an app lock) has
            // nothing to reach for and has to blur the whole screen.
            .privacySensitive()
            .askDismissesKeyboardOnTap($isComposerFocused)
        }
        // **Nothing on iOS: the thread takes SDK 27's automatic edge effect,**
        // which is what a native bar wants for content passing under it. Why
        // not `.hard`: ARCHITECTURE.md, Rejected designs.
        //
        // **On the Mac the effect is hidden.** A Mac window's toolbar is
        // already a glass surface with its own separator, and the thread's top
        // inset there is the toolbar's, 52 pt on the demo once the window's
        // opening animation has ended. So a `.hard` effect paints a block over
        // exactly that band and rules a second line across the content under
        // it: the line under an iOS navigation bar, on a platform with no
        // navigation bar. Hidden rather than left to `.automatic`, whose look
        // under a Mac toolbar wasn't measured, since the toolbar's own glass is
        // already the separation.
        //
        // Nothing on visionOS, for a different reason: the modifier is
        // unavailable there, as `scrollDismissesKeyboard` and
        // `ToolbarItemVisibilityPriority.high` are, since a spatial window has
        // no bar for content to pass under. The push gate's visionOS build
        // fails on any of them left outside a platform gate.
        #if os(macOS)
        .scrollEdgeEffectHidden(true, for: .top)
        #endif
        // `.alignment` puts a thread too short to fill the screen at the top
        // rather than floating it in the middle.
        //
        // **No `.sizeChanges` anchor, and that is a measurement, not an
        // omission:** the anchor never moved this thread, so the follow is an
        // explicit `scrollTo` on the foot (see `thread`). Why not the anchor,
        // and what to reproduce before reinstating it: ARCHITECTURE.md,
        // Rejected designs.
        .defaultScrollAnchor(.top, for: .alignment)
        // `.immediately`: a drag puts the keyboard away the instant it begins,
        // on the keyboard's own animation. It serves the reader who tapped the
        // field and changed their mind; a turn starting already drops focus (see
        // `onChange(of: store.isThinking)`), so no answer is read behind a
        // keyboard. Why not `.interactively`: ARCHITECTURE.md, Rejected
        // designs.
        //
        // Not on visionOS, where the modifier is unavailable: the tap on the
        // content is what visionOS has instead.
        #if !os(visionOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
        // **All five numbers, raw**, because two consecutive samples are what
        // say whether the reader moved or the thread grew away from them:
        // `AskThreadGeometry` does the arithmetic and carries the trace for
        // both halves. Two of them don't mean what they look like:
        // `containerSize` is the space between the bars, 670 pt where the
        // scroll view itself is 874, and `contentOffset.y` rests at
        // `-contentInsets.top`, not at zero. A distance computed without that
        // inset reads 116 pt at the foot of every thread on this screen, which
        // is past the follow boundary.
        .onScrollGeometryChange(for: AskThreadGeometry.self) { geometry in
            AskThreadGeometry(
                contentHeight: geometry.contentSize.height,
                containerHeight: geometry.containerSize.height,
                insetTop: geometry.contentInsets.top,
                offset: geometry.contentOffset.y,
                containerWidth: geometry.containerSize.width
            )
        } action: { _, metrics in
            follow.geometryChanged(metrics)
        }
        // What lets the check after the follow tell a hand on the thread from
        // the thread's own motion (`AskScrollFollow.fellShort(since:)`). On iOS
        // alone, like the check; the follow's task says why.
        #if os(iOS)
        .onScrollPhaseChange { _, phase in
            follow.scrollPhaseChanged(phase)
        }
        #endif
        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
    }

    /// Edit & Resend: the question goes back in the composer with what it was
    /// asked with (`AskConversationStore.edit(_:)`), and the reader with it,
    /// VoiceOver's focus included: the menu it was chosen from closes, and
    /// the focus would go wherever the system put it, not to the field
    /// holding the question to edit.
    private func editAndResend(_ turn: AskTurn<Row>) {
        store.edit(turn)
        isComposerFocused = true
        voiceOverTarget = .field
    }

    /// A host asked for the composer (`AskConversationStore.prefill` without
    /// sending, or `focusComposer()`): the field takes focus, so the draft
    /// waits with the keyboard up (on the Mac, with key focus), and the thread
    /// stays where it is. No animation of its own; the keyboard brings its own.
    ///
    /// **This screen takes it only in the window the reader is in**
    /// (`windowAppearsActive`), and only if no other screen has taken it
    /// first (`AskConversationStore.claimComposerFocus(_:)`). The screen in
    /// every window on the store hears the request; ARCHITECTURE.md, "A host's
    /// request for the composer", says why only one takes it. A request this
    /// screen leaves waits, for another window's screen, a screen that
    /// appears, or this window coming to the front.
    private func deliverComposerFocus(_ request: UUID?) {
        guard let request, windowAppearsActive, store.claimComposerFocus(request) else { return }
        hostFocusTake = AskHostFocusTake(request: request, at: .now)
        hostFocusHandedOver = false
        isComposerFocused = true
    }

    /// This window stopped appearing active just after its screen took a
    /// host's request, so the tap that made the request was most likely in
    /// another window, which comes to the front only after the tap's action
    /// has run (`AskHostFocusHandOver`): ask again, for the screen there. The
    /// field keeps its focus until another screen takes the request.
    private func handHostFocusOver() {
        guard AskHostFocusHandOver.handsOver(hostFocusTake, now: .now, fieldIsFocused: isComposerFocused) else {
            return
        }
        hostFocusTake = nil
        hostFocusHandedOver = true
        store.repostComposerFocus()
    }

    /// The screen in the window in front took the request this screen handed
    /// on: the field here lets its focus go, or this window would keep a
    /// focused field and a Done with the keyboard in another.
    ///
    /// **The binding, not `AskKeyboard.putAway`**, whose resign goes to
    /// whichever first responder UIKit sends it to, app-wide: that can be the
    /// field the other window has just focused. The keyboard is the other
    /// window's now, so there's no hide here for the write to fall outside of.
    private func letHandedOverFocusGo() {
        hostFocusHandedOver = false
        guard isComposerFocused, !windowAppearsActive else { return }
        isComposerFocused = false
    }

    // MARK: - Chrome

    /// Whether the composer is down in a host's tab bar slot rather than up in
    /// this screen's bar.
    ///
    /// **Down until this screen's own keyboard is up.** The slot holds the
    /// composer's face and cannot take typing (`askComposerSlot` has the
    /// measurements), so the face asks for focus and the composer here takes
    /// it. The field stays in the bar at no height the whole time, because
    /// focus goes to a field that exists; it is the keyboard arriving that
    /// raises it, on the flag the first screen makes room on, so the composer
    /// comes up with the keyboard rather than a beat before it, over the face.
    /// `composerHeldUp` raises it where no keyboard comes.
    private var composerRests: Bool {
        composerRestsInSlot && !typingRaisesComposer
    }

    /// The bar's height, for the space the first screen and the jump pill keep
    /// for it: none while the composer rests in a host's slot with no photo
    /// waiting over it, since the bar has none then, whatever was measured
    /// last. The measurement lags a layout pass behind the bar. The composer
    /// comes up while the Ask tab is away, because the slot goes down with the
    /// tab, so without this the tab's first layout on its return, and the
    /// first at launch, would keep space for a composer that isn't there.
    private var composerBarHeight: CGFloat {
        composerRests && store.pendingPhoto == nil ? 0 : composerHeight
    }

    /// Whether the reader typing here raises the composer out of a host's
    /// slot: this screen's keyboard is up, or focus has held where none comes.
    /// The composer's rise animates on this and nothing else (`composerBar`).
    private var typingRaisesComposer: Bool {
        firstScreenMakesRoom || composerHeldUp
    }

    /// The button the face in a host's slot draws before its field: the one
    /// this screen's composer draws (`AskComposerAccessory.leading`).
    private var slotFaceAccessory: AskComposerAccessory? {
        .leading(composerAccessory, acceptsAttachments: store.domain.acceptsPhotoAttachments, onAttach: onAttach)
    }

    /// Hands the face in a host's slot this screen's accent, spectrum and
    /// accessory button, action and all: as the screen appears, and whenever
    /// what the face draws of them changes (`AskComposerFaceLook`).
    private func writeSlotFaceStyle() {
        slotFaceStyle?.update(accent: accent, spectrum: spectrum, accessory: slotFaceAccessory)
    }

    /// Hands the slot's cover what this screen's coming or going did to it,
    /// and animates the face in or out only when that changes whether the
    /// screen is covered. A tab switch changes nothing here, and must write
    /// nothing: a write inside `withAnimation` in the switch's update could
    /// lend the animation to the slot's swap between the face and a host's
    /// accessory.
    private func updateSlotCover(_ change: (inout AskComposerSlotCover) -> Void) {
        guard let slotCover else { return }
        var cover = slotCover.wrappedValue
        change(&cover)
        guard cover != slotCover.wrappedValue else { return }
        withAnimation(reduceMotion ? .none : .smooth(duration: 0.28)) { slotCover.wrappedValue = cover }
    }

    /// The room between the photo waiting for the next question and the
    /// composer under it.
    private static var photoChipGap: CGFloat { 6 }

    private var composerBar: some View {
        VStack(spacing: Self.photoChipGap) {
            // The photo waiting for the next question, over the field it goes
            // with. No animation of its own: it arrives when the host hands it
            // over, and the bar animates only on `stage` and on the composer
            // rising out of a host's slot.
            if let pending = store.pendingPhoto {
                AskPhotoChip(
                    pending: pending,
                    isHeldBack: store.status.nextTier.map { !$0.readsPhotos } ?? false,
                    onRemove: { store.removePhoto() }
                )
            }
            AskComposer(
                draft: $store.draft,
                isFocused: $isComposerFocused,
                placeholder: store.brand.help,
                accent: accent,
                spectrum: spectrum,
                isThinking: store.isThinking,
                acceptsAttachments: store.domain.acceptsPhotoAttachments,
                onSend: { store.ask(store.draft) },
                onStop: { store.stop(byReader: true) },
                onAttach: onAttach,
                accessory: composerAccessory
            )
            // The field takes VoiceOver's focus after Edit & Resend, after a
            // tap on the face in a host's slot, and after New Chat where the
            // first screen has no headline. Not while the composer rests in
            // the slot, hidden from VoiceOver: the request waits until the
            // composer comes up.
            .environment(\.askVoiceOverTarget, composerRests ? nil : $voiceOverTarget)
            // Its buttons hide by name while it rests (`askComposerRests`).
            .environment(\.askComposerRests, composerRests)
            // Resting in the slot: no height, so the bar adds nothing to the
            // inset the slot already takes, and nothing to see or touch.
            .opacity(composerRests ? 0 : 1)
            .frame(height: composerRests ? 0 : nil, alignment: .top)
            // **Not out of touch while the field has focus.** Hit testing off
            // turns the text view's `isUserInteractionEnabled` off, and UIKit,
            // finding it first responder, resigns it and marks it to become
            // first responder again when it can. The composer goes to rest in
            // the keyboard's hide, which arrives while the field is still
            // resigning, so every way the keyboard left marked the field, and
            // the next time the Ask tab came back UIKit put it back in the
            // field: the keyboard came up over the tab bar on its own. Traced
            // in lldb on the demo on the iOS 27.0 simulator, through
            // `-[UIView _promoteSelfOrDescendantToFirstResponderIfNecessary]`
            // as the tab bar controller put the tab's view back. Keyed on
            // focus too, hit testing goes once the field has resigned.
            .allowsHitTesting(!composerRests || isComposerFocused)
            // By name both ways, not `askAccessibilityHidden`, whose new
            // identity at each flip would take the field's focus with it as
            // the composer rose. The buttons hide by name inside it
            // (`askComposerRests`).
            .accessibilityHidden(composerRests)
        }
        .padding(.horizontal, composerMargin)
        .askReadingColumn()
        .padding(.bottom, composerRests && store.pendingPhoto == nil ? 0 : 6)
        .disabled(store.composerIsDisabled)
        // **The composer rising out of a host's slot animates on its own key,
        // the second of the keyboard's two that house rule 4 allows.** The
        // flag changes inside the keyboard's animation, which carries the bar
        // up and down with the keyboard but can't move SwiftUI's layout inside
        // it (`AskKeyboard.change`), so the composer's fade and its height
        // take an animation of their own. It changes only with this screen's
        // keyboard, never on a stream.
        //
        // **Keyed on the typing, not on `composerRests`.** A change to the
        // slot itself lands in place: a tab switch takes the slot down as Ask
        // goes and brings it back as Ask returns, and a change of size class
        // moves the composer between the slot and this bar. Keyed on
        // `composerRests`, this would run on every tab switch: logged on the
        // demo, the composer rose as Ask went and was put down again as Ask
        // came back, and in a host's recorded frames it faded out over the
        // face. A tab switch shows the tab as it was left, with no animation.
        .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: typingRaisesComposer)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
    }

    /// What the composer keeps between its capsule and the screen's edges.
    ///
    /// **21 pt where the tab bar runs along the bottom, because that is where
    /// its capsule ends.** The bar under the composer isn't the screen's width: it is a
    /// floating capsule sized to its own items, then clamped to the screen less
    /// 21 pt on each side. Measured at 3x on an iPhone 17 Pro (402 pt) and an
    /// iPhone 18 Pro Max (440 pt): Files' three tabs come to the same 274 and
    /// 275 pt on both, inset 64 and 82, while Fitness' four reach the clamp on
    /// both, 361 of 402 and 398 of 440, which is 21 on each side each time.
    /// Apple Music is the case this matches: on an iPhone 17 Pro its mini
    /// player and its five-tab bar measure pixel-identical, 359.9 pt wide and
    /// inset 21.05. At 12, the composer would stand 9 pt wider on each side.
    ///
    /// **So 21 is the clamp, not the bar.** It is right for a host whose tab
    /// bar reaches the clamp, as four tabs at Fitness' label lengths do, and
    /// five. A three-tab bar stops well inside the clamp, and the composer
    /// would stand about 40 pt proud of it on each side: re-measure for one.
    /// Outside a tab view compact width stands in for the placement, so a host
    /// with no tab bar gets 21 there too.
    ///
    /// Along the bottom only. In regular width iPadOS hangs the bar off the
    /// top, and there the reading column is what sets the composer's width
    /// anyway.
    private var composerMargin: CGFloat {
        #if os(iOS)
        tabBarRunsAlongBottom ? 21 : 12
        #else
        12
        #endif
    }

    #if os(iOS)
    /// Whether a tab bar runs along the bottom under this screen: what its tab
    /// hears (`tabBarPlacement`), and compact width outside a tab view.
    private var tabBarRunsAlongBottom: Bool {
        AskComposerSlotPolicy.tabBarRunsAlongBottom(
            reported: tabBarPlacement.map { $0 == .bottomBar },
            isCompactWidth: horizontalSizeClass == .compact
        )
    }

    /// What this screen tells a host's slot about the tab bar: whether it runs
    /// along the bottom, as this tab hears it, or nil outside a tab view.
    ///
    /// **No beside iPhone Duo's fold, whatever the tab hears**, so the
    /// composer stays in the conversation's pane rather than resting in the
    /// slot. The slot is the tab view's bottom accessory, laid out by the
    /// system against the window, not the pane: on the outer display it sat
    /// at the foot of the whole column beside the bar strip, and held like a
    /// book that column runs across the fold. Where it sits there wasn't seen.
    private var slotHearsBarAlongBottom: Bool? {
        if foldArrangement.narrowsConversation { return false }
        return tabBarPlacement.map { $0 == .bottomBar }
    }
    #endif

    /// Whether "Jump to latest" shows: when the follow says so, on the thread
    /// alone. After New Chat from a thread scrolled up a screen, the pill
    /// would float over the first screen as a button that does nothing, for
    /// VoiceOver too.
    private var showsJumpPill: Bool {
        if case .thread = stage.phase { return follow.showsJumpPill }
        return false
    }

    @ViewBuilder
    private var jumpPill: some View {
        if showsJumpPill {
            AskJumpToLatestPill {
                follow.jumped()
                jumpRequest += 1
            }
            // Measured, not a constant: the field grows to four lines
            // (`.lineLimit(1...4)` at `.font(.body)`), and a padding tuned to
            // one line lands the pill's glass capsule on the composer's under a
            // multi-line draft or a large text size.
            .padding(.bottom, composerBarHeight + 12)
            .askGlassTransition(reduceMotion: reduceMotion)
        }
    }

    /// **New Chat always, Done while the keyboard is up, and the subtitle is
    /// what pays for the second one.**
    ///
    /// Done costs the title its center unless the subtitle is short: a
    /// navigation bar centers a title *stack* only while the subtitle clears
    /// the items on both sides. A caption such as "Answering with Private Cloud
    /// Compute" is 213 pt against 361 pt of usable bar on an iPhone 17 Pro, a
    /// budget of one narrow item on one side. The caption is the tier's name
    /// alone (`AskTierCaption` says why), 128 pt, and two items fit on either
    /// side of it. **That is a measurement, not an inference**: driven on an
    /// iPhone 17 Pro with the keyboard up, both items present and the caption
    /// forced to its longest string, the title's center sits within a point of
    /// the screen's. Measure again before widening the caption: the words and
    /// the item are the same budget.
    ///
    /// **Done is a symbol as well as a word**: the composer's own
    /// `keyboard.chevron.compact.down`. iPhone Duo moves the bars into a strip
    /// down the side of the display, and a title-only item never goes there,
    /// so with the keyboard up on the Duo's outer display the word alone would
    /// move into the overflow menu at best. A bar along the top shows the
    /// symbol too, so there the glyph stands where the word would, and "Done"
    /// is what VoiceOver and the overflow menu call it. The glyph is narrower
    /// than the word, which the title's centering can only gain from.
    ///
    /// Why not the keyboard's own toolbar (`placement: .keyboard`):
    /// ARCHITECTURE.md, Rejected designs.
    ///
    /// Done isn't the only way out, and isn't what makes the keyboard
    /// tolerable: a turn starting drops focus (see
    /// `onChange(of: store.isThinking)`), so no answer is read behind one. It
    /// is the bar's share of the same job, and the one for a reader with a
    /// half-typed draft they don't want to send: the composer's circle is a
    /// chevron only while the field is empty, so with text in it Done is the
    /// control that says the keyboard can go.
    ///
    /// iOS only. The Mac has no software keyboard to dismiss, and on visionOS
    /// the leading placement is already taken: `AskTierCaption` puts the tier
    /// there, because an ornament has no subtitle to put it in.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        #if os(iOS)
        if showsDoneItem {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    AskKeyboard.putAway($isComposerFocused)
                } label: {
                    Label {
                        Text("Done", bundle: #bundle, comment: "Navigation bar button that puts the keyboard away while the reader is typing an Ask question. Apple's own term for this button in each language.")
                    } icon: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
                // Monochrome for the reason `AskNewChatButton` gives.
                .symbolRenderingMode(.monochrome)
                .accessibilityIdentifier(AskAccessibility.done)
            }
            // The last of the screen's items to go into the overflow menu when
            // the bar runs out of room, as iPhone Duo's bar strip does with the
            // keyboard up on its outer display turned: it is how the keyboard
            // goes away, and it shows only while the keyboard is up.
            .visibilityPriority(.high)
        }
        #endif
        // SDK 27 moves toolbar overflow into a trailing menu, and AskUI adds
        // items to a bar it doesn't own, beside the tier caption and whatever
        // the host puts there. New Chat is the only way to end a conversation,
        // so it is never the item that moves into the overflow menu: pinned
        // where the platform has a pin (`.topBarPinnedTrailing`, iOS and
        // visionOS alone), and on the Mac, which has none, the item the
        // overflow menu takes last.
        //
        // The priority is the Mac's alone: `ToolbarItemVisibilityPriority.high`
        // is unavailable on visionOS, and outside a platform gate it fails the
        // visionOS build, which the push gate builds.
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) { newChatButton }
            .visibilityPriority(.high)
        #else
        ToolbarItem(placement: .topBarPinnedTrailing) { newChatButton }
        #endif
        // Beside New Chat, at the default priority: when the bar runs out of
        // room, this is the item that moves into the overflow menu. New Chat is
        // the only way to end a chat; the list is a way back, and it can wait
        // one more tap.
        //
        // Not while the chats are on screen in the pane beside iPhone Duo's
        // fold, and not while the reader types with the bars in its strip,
        // where the keyboard's predictive bar covers the item
        // (`AskHistoryItem`). It goes and comes back with Done, on the same
        // animated flip.
        if AskHistoryItem.shows(
            offersHistory: store.offersHistory, listsChats: foldArrangement.listsChats,
            isTyping: showsDoneItem, barsAreInStrip: barsAreInStrip
        ) {
            ToolbarItem(placement: .primaryAction) {
                AskHistoryButton {
                    Task { await store.loadHistory() }
                    showsHistory = true
                }
            }
        }
    }

    private var newChatButton: some View {
        AskNewChatButton(isEnabled: store.hasTurns) {
            withAnimation(reduceMotion ? .none : .snappy) { store.startOver(from: screenID) }
        }
    }

    // MARK: - Accessibility

    /// The line VoiceOver hears when a turn reaches a terminal state:
    /// `AskAnnouncement` owns the choice, so it can be tested.
    ///
    /// Looked up by the id the store published rather than taken from
    /// `turns.last`, so it describes the turn that actually ended.
    private func terminalAnnouncement(for id: UUID) -> String? {
        AskAnnouncement.terminal(for: store.turns.first { $0.id == id })
    }

    /// Posts `line` for VoiceOver at `priority`, which rides only on an
    /// `AttributedString`.
    private static func announce(
        _ line: String,
        priority: AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute.AnnouncementPriority
    ) {
        var spoken = AttributedString(line)
        spoken.accessibilitySpeechAnnouncementPriority = priority
        AccessibilityNotification.Announcement(spoken).post()
    }

    /// Copy the reader's own question, or the answer to it, so it doesn't
    /// travel. A question is the reader's own words about their own library,
    /// and an answer is a model's words about it: both are about what the
    /// reader owns, so both stay on this device.
    ///
    /// On iOS and visionOS through `setItems(_:options:)` rather than
    /// `.string`: `.localOnly` keeps it off Universal Clipboard and every
    /// other signed-in device, and the 120 s expiry stops it sitting there for
    /// any app that comes forward to read.
    ///
    /// On the Mac through `prepareForNewContents(with: .currentHostOnly)`,
    /// which empties the pasteboard as `clearContents()` does and keeps what
    /// follows off Universal Clipboard. AppKit has no expiry to set, so there
    /// it stays until something else is copied.
    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(120)
            ]
        )
        #endif
    }
}

extension View {
    /// A tap on the screen puts the keyboard away: for the reader who tapped
    /// the field and changed their mind, which is the only reader left with a
    /// keyboard up once a turn starting drops focus.
    ///
    /// **Simultaneous**, so whatever is under the finger still fires: a chip,
    /// a tile, the evidence line's button. A starter tapped with the keyboard
    /// up is a send, and a send dismisses on its own, so the two never fight.
    ///
    /// Not on the Mac: focus is where a Mac reader keeps it between questions,
    /// and a click on the thread, whose text has selection enabled, must not
    /// take it away.
    ///
    /// **On the scroll content, never on the `ScrollView`.** Attached to the
    /// scroll view itself, the gesture never fires on iOS 27: not on a tap over
    /// text, not on a tap over empty space. Measured on the demo with a log
    /// line in the closure, which stayed silent through every tap until the
    /// modifier moved inside, onto the content stack, where it fired and focus
    /// dropped. The content shape is what makes the gaps between chips count
    /// as the content and not as nothing.
    ///
    /// The keyboard goes through `AskKeyboard`, as it does for the chevron and
    /// Done, and not through the binding.
    @ViewBuilder
    fileprivate func askDismissesKeyboardOnTap(_ isFocused: FocusState<Bool>.Binding) -> some View {
        #if os(iOS) || os(visionOS)
        contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { AskKeyboard.putAway(isFocused) })
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Where the first screen's scroll view may come to rest: never past either
/// end of its own content.
///
/// **Without it, the keyboard going away leaves the column past the end.**
/// Under the keyboard the column no longer fits, and the scroll view keeps the
/// column's center where it was: the container shrinks 294 pt on an iPhone 17
/// Pro and the offset moves 147. When the keyboard goes, the column fits again,
/// and the scroll view adds back its centering inset without undoing that
/// move: offset −97.7 where −180.3 is the only offset a fitting column has,
/// the column 83 pt above its rest and staying there. A drag comes to rest in
/// range on its own, but the composer's chevron, Done and a tap on the screen
/// never end a scroll gesture, and without this all three leave the column
/// stranded.
///
/// **A target behavior, because it runs inside the keyboard's update.** The
/// scroll view asks for a target when its size changes, so the clamped offset
/// lands in the same update as the keyboard's own layout and animates with
/// it. Corrections made after that update snap instead: scrolling a bound
/// `ScrollPosition` to an edge, plain or inside `withAnimation`, moved the
/// column its 83 pt in a single frame. Recorded on the demo and read frame by
/// frame, the chevron, Done and the tap bring the column the full 147 pt back,
/// the largest single-frame step about 21 pt, the size of the keyboard's own
/// on the way up.
///
/// **The keyboard's update is inside its animation only if the keyboard isn't
/// put away from inside a SwiftUI render.** When it is, the clamp runs with
/// the rest of that layout on the frame after, outside the animation:
/// `AskKeyboard` has the recordings and how the screen puts the keyboard away.
///
/// The target's origin is in content coordinates, so 0 is the top and
/// `contentSize − containerSize` the largest offset; a column that fits has
/// only 0.
nonisolated private struct AskInRangeScrollTarget: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let maxOffset = max(0, context.contentSize.height - context.containerSize.height)
        target.rect.origin.y = min(max(target.rect.origin.y, 0), maxOffset)
    }
}

/// While the reader types, a short bar strip keeps the screen's items and
/// minimizes the tab bar (`toolbarVerticalCompressionBehavior`). The strip
/// exists only on iPhone Duo, so everywhere else the modifier changes nothing.
///
/// It also says whether the bars are in that strip (`AskBarStripReader`).
private struct AskTypingKeepsBarItems: ViewModifier {
    let isTyping: Bool
    @Binding var barsAreInStrip: Bool

    func body(content: Content) -> some View {
        content
            .toolbarVerticalCompressionBehavior(isTyping ? .prefersToolbarItems : .automatic)
            .background { AskBarStripReader(barsAreInStrip: $barsAreInStrip) }
    }
}

/// Whether the bars around the screen are in a strip at the side of the
/// display: `toolbarVerticalEdge` names the side, and is nil where the bars
/// run along the top and bottom.
private struct AskBarStripReader: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Binding var barsAreInStrip: Bool

    var body: some View {
        Color.clear
            .onChange(of: edge != nil, initial: true) { _, inStrip in
                barsAreInStrip = inStrip
            }
    }
}
#endif

/// The screen with AskKit's own mark and tiles, a plain evidence line and
/// nothing under the answer, which the modifiers below replace one view at a
/// time.
extension AskScreen
where Mark == AskDefaultMark, Tiles == AskDefaultTiles<Domain.Row>, Disclosure == EmptyView, Footer == EmptyView {
    /// Creates the screen for a conversation, drawing AskKit's own views: its
    /// mark (`AskDefaultMark`), a title card for each row an answer chose
    /// (`AskDefaultTiles`), a plain evidence line and nothing under the
    /// answer.
    ///
    /// The modifiers set the host's views one at a time, and document what
    /// the screen asks of each: `mark(_:)`, `tiles(_:)`,
    /// `evidenceDisclosure(_:)` and `answerFooter(_:)`, as in
    /// `AskScreen(store: store).tiles { rows in … }.answerFooter { turn in … }`.
    /// A value a view's builder captures reaches answers already drawn only
    /// through `buildersDepend(on:)`.
    ///
    /// - Parameters:
    ///   - store: The conversation to show: one for the app, held by the app
    ///     and not by a view (`AskConversationStore` says why).
    ///   - accent: The color the screen tints its own surfaces with: the
    ///     composer, the question bubbles, the reveal's caret, the wait row, a
    ///     proposal's card, and the face in a host's slot. The app's accent
    ///     color by default.
    ///   - spectrum: A run of colors for the spectrum look (`AskSpectrum`),
    ///     such as `.aurora`: the send circle and the reveal's caret in a
    ///     gradient of it in place of the accent, the send circle on the face
    ///     in a host's slot too. Everything else keeps the accent, and so do
    ///     those two under Increase Contrast. Nil by default, for none.
    ///   - onNothingAction: What the button on the nothing-to-ask first screen
    ///     does, such as opening the host's sheet for adding something. The
    ///     button shows only when this is set and the brand has a
    ///     `nothingToAskActionLabel`; without it the screen shows the brand's
    ///     copy alone.
    ///   - onAttach: What the composer's photo button does: present the host's
    ///     picker, then hand the photo to
    ///     `AskConversationStore.attachPhoto(_:label:reference:)`. The button
    ///     shows only when this is set, the domain accepts photos
    ///     (`acceptsPhotoAttachments`) and there is no `composerAccessory`.
    ///   - composerAccessory: The accessory button before the composer's field,
    ///     such as a scan, in place of the photo button. The face in a host's
    ///     slot draws it too.
    public init(
        store: AskConversationStore<Domain>,
        accent: Color = .accentColor,
        spectrum: AskSpectrum? = nil,
        onNothingAction: (() -> Void)? = nil,
        onAttach: (() -> Void)? = nil,
        composerAccessory: AskComposerAccessory? = nil
    ) {
        self.init(
            store: store,
            configuration: AskScreenConfiguration(
                accent: accent, spectrum: spectrum, onNothingAction: onNothingAction,
                onAttach: onAttach, composerAccessory: composerAccessory
            ),
            mark: { AskDefaultMark(isLit: $0) },
            tiles: { _, rows in AskDefaultTiles(rows: rows, logSubsystem: store.brand.logSubsystem) },
            evidenceDisclosure: { _ in EmptyView() }, answerFooter: { _ in EmptyView() }
        )
    }
}

/// The host's views, set one at a time, so a host spells only the ones it
/// draws: `AskScreen(store: store).tiles { rows in … }.answerFooter { turn in … }`.
/// Each modifier returns the same screen with that one view replaced, and keeps
/// the value `buildersDepend(on:)` named, so they go in any order.
extension AskScreen {
    /// Replaces the host's mark: a view for whether the mark is lit.
    ///
    /// Lit (`true`) on the ready first screen and in the wait row; unlit
    /// (`false`) on the nothing-to-ask and can't-serve first screens, where the
    /// can't-serve screen also dims it to 40% opacity. The screen frames the
    /// mark in a square, 56 pt on a first screen and 26 pt in the wait row, both
    /// scaled with Dynamic Type. Without one, the screen draws `AskDefaultMark`.
    ///
    /// The mark decorates, so hide it from VoiceOver, as `AskDefaultMark` is
    /// hidden: `.accessibilityHidden(true)`, or an `Image(decorative:)`. Left
    /// in, VoiceOver lands on it above the first screen's headline and reads
    /// "image", or the name of its symbol.
    ///
    /// - Parameter mark: The host's mark, handed whether it is lit.
    /// - Returns: The same screen, drawing this mark.
    public func mark<NewMark: View>(
        @ViewBuilder _ mark: @escaping (Bool) -> NewMark
    ) -> AskScreen<Domain, NewMark, Tiles, Disclosure, Footer> {
        AskScreen<Domain, NewMark, Tiles, Disclosure, Footer>(
            store: store, configuration: configuration,
            mark: mark, tiles: tiles,
            evidenceDisclosure: evidenceDisclosure, answerFooter: answerFooter
        )
    }

    /// Replaces the bank under an answer with the host's tiles, drawn from the
    /// rows it chose.
    ///
    /// Called only for an answer that chose rows. Return an `AskTileGrid` of
    /// the host's tiles, so they come in a tile at a time (house rule 4).
    ///
    /// - Parameter tiles: The bank, handed the rows the answer chose.
    /// - Returns: The same screen, drawing these tiles.
    public func tiles<NewTiles: View>(
        @ViewBuilder _ tiles: @escaping ([Row]) -> NewTiles
    ) -> AskScreen<Domain, Mark, NewTiles, Disclosure, Footer> {
        self.tiles { _, rows in tiles(rows) }
    }

    /// Replaces the bank under an answer with the host's tiles, handed the
    /// turn as well as the rows it chose: for a tile that says something of the
    /// question, such as a caption for the kind of question it was.
    ///
    /// The rows-only `tiles(_:)` says when the bank is called and what to
    /// return. Read the turn from here, never look it up in the store: two
    /// answers can choose the same rows, so a search of `turns` for them can
    /// find the wrong turn, and a read of `turns` in a builder makes every turn
    /// redraw on every streamed snapshot.
    ///
    /// - Parameter tiles: The bank, handed the turn and the rows its answer
    ///   chose.
    /// - Returns: The same screen, drawing these tiles.
    public func tiles<NewTiles: View>(
        @ViewBuilder _ tiles: @escaping (AskTurn<Row>, [Row]) -> NewTiles
    ) -> AskScreen<Domain, Mark, NewTiles, Disclosure, Footer> {
        AskScreen<Domain, Mark, NewTiles, Disclosure, Footer>(
            store: store, configuration: configuration,
            mark: mark, tiles: tiles,
            evidenceDisclosure: evidenceDisclosure, answerFooter: answerFooter
        )
    }

    /// Replaces the bank under an answer with the host's tiles, handed the
    /// turn, the rows it chose and a way to open a row: the host's
    /// `askItemOpener`, typed by the row's id, for a tile to call rather than
    /// read the environment itself. Otherwise as the `tiles(_:)` handed the
    /// turn.
    ///
    /// `open` is nil where there is nowhere to go: no opener, or one wired for
    /// another id type, which is logged once for each id type. A tile handed
    /// nil stays inert, as `askItemOpener` asks of every tile. The screen's
    /// tiles type is opaque, since the builder is wrapped to hand it `open`.
    ///
    /// - Parameter tiles: The bank, handed the turn, the rows its answer chose
    ///   and how to open one of them.
    /// - Returns: The same screen, drawing these tiles.
    public func tiles<NewTiles: View>(
        @ViewBuilder _ tiles: @escaping (AskTurn<Row>, [Row], ((Row.ID) -> Void)?) -> NewTiles
    ) -> AskScreen<Domain, Mark, some View, Disclosure, Footer> {
        let subsystem = store.brand.logSubsystem
        return self.tiles { turn, rows in
            AskOpeningTiles(turn: turn, rows: rows, logSubsystem: subsystem, tiles: tiles)
        }
    }

    /// Sets what the evidence line's chevron opens: a view beneath the line,
    /// handed the turn, such as the rows the line counts
    /// (`turn.answer?.matches`).
    ///
    /// The line gets its chevron from this view alone, keyed on its type: any
    /// type but `EmptyView` puts a chevron on every evidence line with rows
    /// behind it, a count or the domain's own words
    /// (`AskDomain.evidence(for:)`), whatever the view draws for that turn.
    /// A line saying the answer isn't from the app's data has none, and
    /// neither does a turn the domain gives no line. Each turn's line opens
    /// and closes on its own.
    ///
    /// - Parameter disclosure: The view the chevron opens, handed the turn.
    /// - Returns: The same screen, with a chevron on its evidence lines.
    public func evidenceDisclosure<NewDisclosure: View>(
        @ViewBuilder _ disclosure: @escaping (AskTurn<Row>) -> NewDisclosure
    ) -> AskScreen<Domain, Mark, Tiles, NewDisclosure, Footer> {
        AskScreen<Domain, Mark, Tiles, NewDisclosure, Footer>(
            store: store, configuration: configuration,
            mark: mark, tiles: tiles,
            evidenceDisclosure: disclosure, answerFooter: answerFooter
        )
    }

    /// Sets a callout under every turn, always on show, such as a button the
    /// reader is meant to see.
    ///
    /// It sits below the evidence line and any open disclosure, and above a
    /// proposal's card. It's called for every turn, one still in flight or one
    /// that failed included, so it draws nothing for a turn it has nothing for.
    /// Pieces that use `askArrival` count their steps from 0 and arrive after
    /// the evidence line; a proposal's card arrives on the footer's step 2.
    ///
    /// - Parameter footer: The callout, handed the turn.
    /// - Returns: The same screen, drawing this callout.
    public func answerFooter<NewFooter: View>(
        @ViewBuilder _ footer: @escaping (AskTurn<Row>) -> NewFooter
    ) -> AskScreen<Domain, Mark, Tiles, Disclosure, NewFooter> {
        AskScreen<Domain, Mark, Tiles, Disclosure, NewFooter>(
            store: store, configuration: configuration,
            mark: mark, tiles: tiles,
            evidenceDisclosure: evidenceDisclosure, answerFooter: footer
        )
    }

    /// Names what the host's views draw from besides the turn and rows they
    /// are handed, so a change to it redraws the answers already on screen.
    ///
    /// A finished answer is drawn again only when something it shows changes,
    /// and SwiftUI can't compare the builders, which are closures. So a value a
    /// builder captures, such as a flag in the host's state or a setting,
    /// reaches the answers on screen only when it is part of `value`. Pass every
    /// such value that can change while the screen is up, together in one
    /// `Equatable` value; a second call replaces the first. A change redraws
    /// every turn on the thread. A value that a host's own view reads from an
    /// `@Observable` in its body needs nothing, since that view redraws itself.
    ///
    /// The value reaches the mark, the tiles, the disclosure and the footer as
    /// the thread draws them. The modifiers that set those views keep it, so it
    /// can be named before or after them.
    ///
    /// - Parameter value: Everything the builders capture that can change.
    /// - Returns: The same screen, redrawing its answers when `value` changes.
    public func buildersDepend(on value: some Equatable) -> Self {
        var screen = self
        screen.configuration.buildersToken = AskBuildersToken(value)
        return screen
    }
}

/// What `AskScreen` is handed besides its store and the host's four views:
/// the accent and the spectrum, what the nothing-to-ask button and the photo
/// button do, the accessory button, and what the builders depend on.
///
/// **One value, so a modifier that replaces one view carries the rest over
/// whole.** Each of `mark(_:)`, `tiles(_:)`, `evidenceDisclosure(_:)` and
/// `answerFooter(_:)` makes a screen of a new type, which can't copy itself:
/// it builds the new screen from its parts. Spelled field by field, every
/// option the screen gained would have to be added to each modifier as well,
/// and one left out would be an option a host set that the next modifier
/// dropped. A new option goes here, and no modifier names it.
struct AskScreenConfiguration {
    /// The color the screen tints its own surfaces with.
    var accent: Color
    /// What the composer's send circle and the reveal's caret wear in place
    /// of the accent, or nil for the accent alone (`AskSpectrum`).
    var spectrum: AskSpectrum?
    /// What the button on the nothing-to-ask first screen does, or nil for no
    /// button. Only the host knows where adding something goes.
    var onNothingAction: (() -> Void)?
    /// What the composer's photo button does, and whether there is one (the
    /// initializer's `onAttach`).
    var onAttach: (() -> Void)?
    /// The accessory button before the composer's field, in place of the photo
    /// button.
    var composerAccessory: AskComposerAccessory?
    /// What the builders draw from besides the turn they are handed, when the
    /// host names it (`AskScreen.buildersDepend(on:)`). The thread's rows
    /// compare it.
    var buildersToken: AskBuildersToken?
}

#endif
