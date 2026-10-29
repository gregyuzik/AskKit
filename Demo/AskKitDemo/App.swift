import SwiftUI

import AskCore
// SPI for `askSimulatedFold(_:)` alone: the stand-in fold `-askFold` and the
// previews arrange the screen around. A host imports AskUI plainly.
@_spi(AskKitInternal) import AskUI

/// A host for AskUI with no app's data and no Private Cloud Compute entitlement
/// behind it, so the screen can be driven in the simulator in seconds and
/// `#Preview`s have somewhere to live. It declares none to the seam
/// (`DemoAsk`), so the tier caption always reads "On device": Private Cloud
/// Compute is exercised by a host that holds it, never here.
@main
struct AskKitDemoApp: App {
    @State private var host = DemoHost.atLaunch()

    #if DEBUG && os(macOS)
    /// `DemoLaunchArgument.captureWindow`: the window written to a PNG for
    /// the README, then the app quits (`DemoWindowCapture`).
    init() {
        DemoWindowCapture.startIfAsked()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                switch host {
                case .library(let ask): ContentView(ask: ask)
                case .assistant(let ask): DemoAssistantView(ask: ask)
                }
            }
            // A fold the simulator doesn't have, when the launch asks for
            // one, so the screen's arrangement around it can be seen.
            .askSimulatedFold(simulatedFold)
            #if os(macOS)
            // An Ask link goes to a window already open: without this the
            // Mac opens a new window for every link. Every window shows
            // the one store's draft, so another adds nothing. With none
            // open, the scene opens one for the link.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            #endif
        }
        // The Mac menu-bar item AskUI exports. Demonstrated here because a leg
        // nothing attaches is a leg nobody knows exists — and because this is
        // the shape a host copies.
        #if os(macOS)
        // `hasTurns`, never `!turns.isEmpty`: this is the scene's body, and a
        // read of `turns` here runs it again for every word an answer streams.
        .commands {
            AskCommands(isEnabled: host.hasTurns) { host.startOver() }
        }
        #endif
    }

    /// `DemoLaunchArgument.fold`: the fold to arrange the screen around, or
    /// nil for the device's own.
    private var simulatedFold: AskSimulatedFold? {
        switch DemoLaunchArgument.value(after: DemoLaunchArgument.fold) {
        case "book": .book()
        case "bookBent": .book(bend: 24)
        case "upright": .upright()
        case "uprightBent": .upright(bend: 24)
        default: nil
        }
    }
}

/// Which Ask the demo hosts, picked once at launch: the library
/// (`DemoDomain`), or the assistant under `DemoLaunchArgument.assistant`
/// (`DemoAssistantDomain`).
///
/// **Only the one picked is built.** A process has one model seam, and a
/// second `AppleModelSeam` alive is logged as a fault; building an Ask also
/// reads its folder, and under `-askFreshHistory` empties it. The store,
/// the engine and the screen are each generic over their domain, so the
/// pick is made here, at the root, and each case carries its own.
@MainActor
enum DemoHost {
    case library(DemoAsk<DemoDomain>)
    case assistant(DemoAsk<DemoAssistantDomain>)

    static func atLaunch() -> DemoHost {
        CommandLine.arguments.contains(DemoLaunchArgument.assistant)
            ? .assistant(DemoAsk())
            : .library(DemoAsk())
    }

    /// For the Mac's New Chat command (`AskCommands`), whichever Ask it is.
    var hasTurns: Bool {
        switch self {
        case .library(let ask): ask.store.hasTurns
        case .assistant(let ask): ask.store.hasTurns
        }
    }

    func startOver() {
        switch self {
        case .library(let ask): ask.store.startOver()
        case .assistant(let ask): ask.store.startOver()
        }
    }
}

/// The one Ask, owned by the app.
///
/// **Not by the view.** A generic store cannot have a `static let shared` and
/// should not: an iOS `TabView` keeps a tab alive across switches, but a Mac
/// `NavigationSplitView` rebuilds its detail on every sidebar change — so a
/// thread owned by the view would vanish because the reader glanced at another
/// screen, taking a turn in flight with it. This is the shape a host copies.
///
/// Generic over the domain, since the demo has two (`DemoHost`).
@MainActor
@Observable
final class DemoAsk<Domain: AskDomain> {
    let domain: Domain
    let seam: AppleModelSeam
    let engine: AskEngine<Domain>
    let store: AskConversationStore<Domain>

    /// What the settings card's diagnostics row runs (`runEval()`).
    @ObservationIgnored private let scenarios: [AskScenario]

    /// `DemoLaunchArgument.prefill`'s link, until a screen takes it
    /// (`takeLaunchLink()`).
    @ObservationIgnored private var launchLink = DemoLaunchArgument.value(after: DemoLaunchArgument.prefill)
        .flatMap { URL(string: $0) }

    init(domain: Domain, scenarios: [AskScenario]) {
        #if DEBUG
        if CommandLine.arguments.contains(DemoLaunchArgument.freshHistory) {
            Self.forgetEveryChat(appDirectory: domain.brand.appDirectory)
        }
        #endif
        // Undeclared: the demo's entitlements carry no Private Cloud Compute,
        // and a request from a process without it is a fatal trap.
        let seam = AppleModelSeam.make(privateCloudCompute: .undeclared)
        let engine = AskEngine(domain: domain, seam: seam)
        self.domain = domain
        self.seam = seam
        self.engine = engine
        self.store = AskConversationStore(engine: engine)
        self.scenarios = scenarios
    }

    #if DEBUG
    /// `DemoLaunchArgument.freshHistory`: everything AskKit keeps for the
    /// demo, gone before the store exists to read any of it.
    ///
    /// **The folder, whole.** AskKit keeps all of it in the brand's folder
    /// under Application Support (`AskBrand.appDirectory`): the chat on disk,
    /// every earlier one, a thread set aside because it couldn't be read, and
    /// the feedback attachments. The demo keeps nothing of its own there. A
    /// host's Delete All Chats is `AskConversationStore.deleteAllThreads()`,
    /// which the History sheet calls; it waits for the saved chat to be read,
    /// so at launch it would show that chat for a moment before taking it
    /// away.
    ///
    /// **Debug builds only**, which is what the UI tests run. In a release
    /// build any local process could launch the app with the flag and have
    /// it delete its own chats from its container, which the container
    /// otherwise keeps that process out of.
    private static func forgetEveryChat(appDirectory: String) {
        // One folder, as AskKit checks its own (its check is the package's):
        // empty, "." or "..", or a name with a "/" or a NUL in it, would
        // reach Application Support itself or a folder beside it.
        guard !appDirectory.isEmpty, appDirectory != ".", appDirectory != "..",
              !appDirectory.contains("/"), !appDirectory.contains("\u{0}"),
              let support = try? FileManager.default.url(
                  for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
              ) else { return }
        try? FileManager.default.removeItem(at: support.appending(path: appDirectory, directoryHint: .isDirectory))
    }
    #endif

    /// The link the launch handed over, once: the first screen to appear
    /// opens it, and no screen after it does, a Mac window reopened or a tab
    /// switched back to. Kept here, on the one Ask, because a screen's own
    /// state is made again with the screen.
    func takeLaunchLink() -> URL? {
        defer { launchLink = nil }
        return launchLink
    }

    /// An Ask link prefills and never sends — `AskLink`'s rule, and the router
    /// shape a host copies.
    func open(_ url: URL) {
        guard let question = AskLink.question(from: url, scheme: DemoLink.scheme) else { return }
        store.prefill(question)
    }

    /// The scenarios through the real engine, as a table to read or share.
    /// What the settings card's diagnostics row runs.
    ///
    /// On an engine of its own, which `AskEval` builds: it resets its engine
    /// before every scenario, and on the thread's engine that reset would
    /// drop the chat's conversation. The domain and the seam are the app's,
    /// so the tiers and the generation gate are too.
    func runEval() async -> String {
        let eval = AskEval(domain: domain, seam: seam)
        let outcomes = await eval.run(scenarios)
        return AskEval<Domain>.table(outcomes)
    }
}

extension DemoAsk where Domain == DemoDomain {
    /// The library: thirty things behind one search.
    convenience init() {
        self.init(domain: DemoDomain(), scenarios: DemoDomain.scenarios)
    }
}

extension DemoAsk where Domain == DemoAssistantDomain {
    /// The assistant, with the list its reminders go to.
    convenience init() {
        self.init(domain: DemoAssistantDomain(reminders: DemoReminderList()), scenarios: DemoAssistantDomain.scenarios)
    }
}

struct ContentView: View {
    let ask: DemoAsk<DemoDomain>

    @State private var showsSettings = false
    /// Where a tile's row opens: a sheet, or a push. The router the tiles
    /// open with (`askItemOpener`), one object for the view's life.
    @State private var routes = DemoRoutes()
    /// Which tab is up, so the slot holds the face on Ask's alone.
    @State private var selectedTab = DemoTab.ask

    /// Leading on the phone, not `.secondaryAction`. SDK 27 moves a secondary
    /// action into the overflow menu, a "More" button beside New Chat, a second
    /// trailing item — and a title stack centres only while its subtitle
    /// clears the items on both sides, so the demo's title would sit left of
    /// centre where a host whose one bar item is New Chat has it centred. One
    /// item a side keeps the demo honest about the screen it exists to show.
    /// The Mac has no top bar to lead.
    ///
    /// **A cost that host does not pay.** `AskScreen` puts its own Done here
    /// while the keyboard is up, so the demo's bar carries three items where
    /// that host's carries two, and a title stack left-aligns once the sides
    /// stop clearing the subtitle. Measured on an iPhone with the caption at
    /// its longest: two items centre it to within a point, three leave the
    /// subtitle 12pt right of centre. So the demo's title is centred at rest
    /// and drifts while a question is being typed — the harness paying for a
    /// host item, not a bug in the screen.
    private var settingsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .secondaryAction
        #else
        .topBarLeading
        #endif
    }

    var body: some View {
        #if os(iOS)
        if hostsInTabs {
            TabView(selection: $selectedTab) {
                Tab(value: DemoTab.ask) {
                    askStack
                } label: {
                    Label {
                        Text(verbatim: "Ask")
                    } icon: {
                        // The speech bubble with sparkles whose bubble the
                        // app icon traces, in one colour like the bar's other
                        // items: the tint while Ask is selected and the bar's
                        // plain ink otherwise.
                        Image(systemName: "text.bubble.badge.sparkles")
                    }
                }
                Tab(value: DemoTab.library) {
                    NavigationStack {
                        Text(verbatim: "A second tab, so the bar has more than Ask in it.")
                            .askDeemphasizedText()
                            .navigationTitle(Text(verbatim: "Library"))
                    }
                } label: {
                    Label {
                        Text(verbatim: "Library")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            // The tab bar minimizes as the reader scrolls down, as a host's
            // does. `tabBarMinimizeBehavior` does that in SDK 27, and
            // `toolbarMinimizationBehavior(_:for: .tabBar)` doesn't: it
            // compiles, and SDK 27 documents `.navigationBar` as the one
            // placement it minimizes.
            .tabBarMinimizeBehavior(.onScrollDown)
            // The composer's face rides in the slot, beside the bar once it
            // minimizes: the shape a host copies. The slot holds the face on
            // the Ask tab, and the host's own accessory on the other tab. The
            // face takes its accent, its spectrum and its accessory button from
            // the screen.
            .askComposerSlot(
                ask.store,
                isEnabled: restsInSlot && selectedTab == .ask,
                accessoryIsEnabled: restsInSlot && selectedTab == .library
            ) {
                DemoGlance()
            }
        } else {
            askStack
        }
        #else
        askStack
        #endif
    }

    /// The screen as every host has it: in a stack, titled, with a host item
    /// of its own beside the screen's.
    private var askStack: some View {
        // A stack even on the Mac: `AskScreen` puts New Chat and the tier
        // caption in the navigation bar, and outside a navigation container
        // neither has anywhere to render.
        NavigationStack {
            AskScreen(
                store: ask.store,
                accent: .accentColor,
                // The icon's colors: the send circle and the caret in a
                // gradient of them (`AskSpectrum.aurora`).
                spectrum: .aurora,
                // `DemoLaunchArgument.emptyLibrary` with `button`: where a
                // host would take the reader to add a first item. The demo
                // has nothing to add, so it shows its Library tab, where
                // there is one.
                nothingToAskAction: DemoDomain.offersFirstItem
                    ? AskNothingToAskAction("Add Your First Item") { selectedTab = .library }
                    : nil,
                onAttach: offersPhotos ? { attachPhoto() } : nil,
                composerAccessory: offersPhotos ? nil : surpriseMe
            )
            .mark { DemoMark(isLit: $0) }
            .tiles { DemoTiles(rows: $0) }
            .answerFooter { DemoSpanCard(turn: $0) }
            .navigationTitle(ask.store.brand.title)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // The host's own item, beside AskScreen's: the screen adds New
                // Chat itself, and a host is free to add more.
                ToolbarItem(placement: settingsPlacement) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label {
                            Text(verbatim: "Ask settings")
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }
                    .symbolRenderingMode(.monochrome)
                }
            }
            .sheet(isPresented: $showsSettings) {
                DemoSettings(ask: ask)
            }
            .sheet(item: $routes.openedRow) { row in
                DemoRowDetail(row: row)
            }
            .navigationDestination(item: $routes.pushedRowID) { id in
                if let row = DemoRow.all.first(where: { $0.id == id }) {
                    DemoRowPage(row: row)
                }
            }
            // From the same state the push reads, so the screen's bar is open
            // in the push's own update.
            .environment(\.askItemIsPushed, routes.pushedRowID != nil)
        }
        // The verb the tiles open with (`DemoRoutes`). Built in the body, and
        // the same opener on every pass, since it holds the same router.
        .environment(\.askItemOpener, AskItemOpenAction(routes))
        .onOpenURL { ask.open($0) }
        // The same link handed over at launch — how the UI tests reach this
        // router, since a test cannot open a URL before the app is up. Once a
        // launch, not once a screen (`DemoAsk.takeLaunchLink()`).
        .task {
            guard let url = ask.takeLaunchLink() else { return }
            ask.open(url)
        }
    }

    /// `DemoLaunchArgument.tabs`.
    private var hostsInTabs: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.tabs)
    }

    /// `DemoLaunchArgument.slot`.
    private var restsInSlot: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.slot)
    }

    /// `DemoLaunchArgument.photos`: the composer's accessory button is the
    /// photo button instead of Surprise me.
    private var offersPhotos: Bool {
        CommandLine.arguments.contains(DemoLaunchArgument.photos)
    }

    /// What the photo button does in a host: the reader picks a photo and the
    /// host hands the store what they picked. The demo has no library, so it
    /// attaches the sleeve it draws.
    private func attachPhoto() {
        guard let image = DemoPhoto.draw() else { return }
        ask.store.attachPhoto(image, label: DemoPhoto.label, reference: DemoPhoto.reference)
    }

    /// The composer's accessory button, before the field, where a host puts an
    /// action of its own. Here it puts a starter in the field the way an entry
    /// point would: prefilled and focused, never sent.
    private var surpriseMe: AskComposerAccessory {
        AskComposerAccessory(
            systemImage: "dice",
            label: Text(verbatim: "Surprise me"),
            identifier: DemoAccessibility.surprise
        ) { [store = ask.store] in
            // Starters load with the screen; a tap that beats them still lands.
            let pool = store.availableStarters.isEmpty ? store.starters : store.availableStarters
            store.prefill(pool.randomElement()?.text ?? "What's the oldest thing I have?")
        }
    }
}

/// Where a tile's row opens: the router `askItemOpener` carries.
///
/// A host on the phone pushes the row, and on the Mac or visionOS it may open
/// a window; the demo has one row type and one window, so it shows a sheet —
/// the point is that the grid asks and the host answers, and that the id
/// survives the erasure the environment value needs to exist at all. Under
/// `DemoLaunchArgument.push` it pushes, as a phone host does.
///
/// **An object, so the opener is compared by identity** (`AskItemRouter`):
/// the action built from it in `ContentView`'s body is the same on every pass.
@MainActor
@Observable
final class DemoRoutes: AskItemRouter {
    /// The row a tile opened in a sheet.
    var openedRow: DemoRow?
    /// The row a tile pushed onto the Ask tab's stack, under
    /// `DemoLaunchArgument.push`: by id, since a destination is keyed on a
    /// hashable value and a row is only identifiable.
    var pushedRowID: String?

    func open(_ id: String) {
        if CommandLine.arguments.contains(DemoLaunchArgument.push) {
            pushedRowID = id
        } else {
            openedRow = DemoRow.all.first { $0.id == id }
        }
    }
}

/// The demo's two tabs.
enum DemoTab: Hashable {
    case ask
    case library
}

#if os(iOS)
/// A host's own bottom accessory, on the Library tab, in the slot that holds
/// the composer's face on Ask.
struct DemoGlance: View {
    var body: some View {
        Label {
            Text(verbatim: "A host's own accessory")
        } icon: {
            Image(systemName: "sun.max")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(DemoAccessibility.glance)
    }
}
#endif

/// What a tile opens onto, in a sheet.
struct DemoRowDetail: View {
    let row: DemoRow

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DemoRowPage(row: row)
                .toolbar {
                    // The system's own close button, labelled in the reader's
                    // language, as AskKit's History sheet has it: the sheet
                    // has nothing to confirm.
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

/// The row itself, as the sheet shows it and as a push does
/// (`DemoLaunchArgument.push`).
struct DemoRowPage: View {
    let row: DemoRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.title)
                .font(.largeTitle.weight(.semibold))
                // The one thing the smoke test needs from this screen: it
                // asserts the row that opened is the row the tile named,
                // which is what says the id survived the erasure
                // `AskItemOpenAction` needs to exist at all.
                .accessibilityIdentifier(DemoAccessibility.rowDetailTitle)
            Text(verbatim: "\(row.kind.scope) · \(year)")
                .askDeemphasizedText()
                // A pause where the eye has a middle dot, as on the tile
                // (`DemoTiles`): VoiceOver with punctuation on would say
                // "middle dot".
                .accessibilityLabel(Text(verbatim: "\(row.kind.scope), \(year)"))
            Text(row.note)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    /// The year as a year, with no grouping separator.
    private var year: String {
        row.year.formatted(.number.grouping(.never))
    }
}

/// Where `AskPrivateCloudCard` can actually be looked at.
///
/// The demo holds no Private Cloud Compute entitlement, so the card reads
/// "isn't enabled in this build" here, and its other states only in a host that
/// holds one. That is the honest answer, and the reason the card takes its
/// state from the seam's mirror rather than probing for itself.
struct DemoSettings<Domain: AskDomain>: View {
    let ask: DemoAsk<Domain>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AskPrivateCloudCard(store: ask.store, onRunEval: { [ask] in await ask.runEval() })
                } header: {
                    Text(verbatim: "Ask")
                }
            }
            .navigationTitle(Text(verbatim: "Settings"))
            .toolbar {
                // The system's close button, as `DemoRowDetail` says.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { await ask.seam.refreshStatus() }
        }
    }
}

/// The one Ask this file's previews share. The canvas runs them in one
/// process, which holds one model seam as the app does (`DemoHost`): an Ask
/// apiece would make a second seam, which is logged as a fault, and each
/// would read the same folder. Every preview shows the one store, as every
/// Mac window does.
private let previewAsk = DemoAsk<DemoDomain>()

#Preview {
    ContentView(ask: previewAsk)
}

// iPhone Duo's two arrangements, on whatever the canvas is set to. On the
// iPhone Duo destination with the canvas's Display set to the inner one, the
// stand-in fold supplies the region a preview doesn't have.
#Preview("Held like a book") {
    ContentView(ask: previewAsk)
        .askSimulatedFold(.book())
}

#Preview("Upright") {
    ContentView(ask: previewAsk)
        .askSimulatedFold(.upright())
}
