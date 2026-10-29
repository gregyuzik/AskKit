#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import SwiftUI
import Testing
@testable import AskUI

/// The shapes a host mounts `AskScreen` in, as the compiler sees them.
///
/// **The evidence disclosure and the answer footer are two view builders, and
/// the difference isn't cosmetic.** The evidence line's chevron is keyed to
/// `Disclosure` alone, so a host with a footer and no disclosure keeps a plain
/// line and a footer the reader can see. Were the two one view, a host's button
/// under each answer would put a chevron on every answer and then hide the
/// button behind it: a call to action nobody is called to.
///
/// **The type annotations are the assertions.** A unit test can draw a view
/// but can't ask what its body chose to show, such as whether the evidence
/// line has a chevron, so what is pinned here is the API surface: each `let`
/// spells out all five generic arguments, so dropping or renaming a modifier,
/// or one that sets its view in another view's generic position, stops
/// compiling in AskKit's own build rather than in a host's.
///
/// `_ = screen.body` only forces `body` to be formed, so a view builder wired
/// to the wrong generic argument fails here rather than in a host. Not
/// `#expect(screen.body is any View)`: that check always passes, the compiler
/// warns that it does, and the push gate fails on any warning.
@MainActor
@Suite("AskScreen view builders", .timeLimit(.minutes(1)))
struct AskScreenViewBuildersTests {

    /// Prose, tiles and a plain evidence line: no disclosure and no footer.
    @Test("Neither a disclosure nor a footer — the line stays plain")
    func neitherDisclosureNorFooter() {
        let screen: AskScreen<UIDomain, EmptyView, EmptyView, EmptyView, EmptyView> = AskScreen(
            store: makeStore(asker: ScriptedAsker()),
            accent: .accentColor
        )
        .mark { _ in EmptyView() }
        .tiles { _ in EmptyView() }
        _ = screen.body
    }

    /// A disclosure: the chevron opens the rows the answer read.
    @Test("A disclosure alone — the chevron has something to open")
    func disclosureOnly() {
        let screen: AskScreen<UIDomain, EmptyView, EmptyView, Text, EmptyView> = AskScreen(
            store: makeStore(asker: ScriptedAsker())
        )
        .mark { _ in EmptyView() }
        .tiles { _ in EmptyView() }
        .evidenceDisclosure { _ in Text(verbatim: "the rows this answer read") }
        _ = screen.body
    }

    /// A footer: a button under the answer, and no chevron over nothing.
    ///
    /// The fourth argument is `EmptyView` and the fifth is not. That ordering
    /// is the point: were the callout to land in the `Disclosure` position,
    /// the line would grow a chevron and the button would go behind it.
    @Test("A callout alone — no chevron, and the button is on show")
    func footerOnly() {
        let screen: AskScreen<UIDomain, EmptyView, EmptyView, EmptyView, Text> = AskScreen(
            store: makeStore(asker: ScriptedAsker())
        )
        .mark { _ in EmptyView() }
        .tiles { _ in EmptyView() }
        .answerFooter { _ in Text(verbatim: "Mark as lent") }
        _ = screen.body
    }

    /// Both, for a host that wants rows behind the chevron and a button on show.
    @Test("A disclosure and a footer — independent of each other")
    func disclosureAndFooter() {
        let screen: AskScreen<UIDomain, EmptyView, EmptyView, Text, Text> = AskScreen(
            store: makeStore(asker: ScriptedAsker())
        )
        .mark { _ in EmptyView() }
        .tiles { _ in EmptyView() }
        .evidenceDisclosure { _ in Text(verbatim: "rows") }
        .answerFooter { _ in Text(verbatim: "callout") }
        _ = screen.body
    }

    // MARK: - Tiles that read their turn

    /// Every shape again, with tiles handed the turn beside its rows: for a
    /// tile that says something of the question, which it would otherwise have
    /// to look up in the thread (`AskTilesBuilderTurnTests`).
    @Test("Every shape takes tiles that read their turn")
    func tilesThatReadTheirTurn() {
        let store = makeStore(asker: ScriptedAsker())
        let neither: AskScreen<UIDomain, EmptyView, Text, EmptyView, EmptyView> = AskScreen(store: store)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
        let disclosure: AskScreen<UIDomain, EmptyView, Text, Text, EmptyView> = AskScreen(store: store)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
        let footer: AskScreen<UIDomain, EmptyView, Text, EmptyView, Text> = AskScreen(store: store)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
            .answerFooter { _ in Text(verbatim: "callout") }
        let both: AskScreen<UIDomain, EmptyView, Text, Text, Text> = AskScreen(store: store)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
            .answerFooter { _ in Text(verbatim: "callout") }
        _ = neither.body
        _ = disclosure.body
        _ = footer.body
        _ = both.body
    }

    /// A builder that names only `$0` is the one more than one of the three
    /// `tiles(_:)` could be offered, and the demo's is one. It has to take the
    /// rows-only modifier, in every shape, rather than stop compiling as
    /// ambiguous.
    @Test("A $0 builder takes the rows-only tiles, in every shape")
    func aDollarZeroBuilderTakesTheRowsOnlyTiles() {
        let store = makeStore(asker: ScriptedAsker())
        let neither: AskScreen<UIDomain, AskDefaultMark, Text, EmptyView, EmptyView> = AskScreen(store: store)
            .tiles { Text(verbatim: "\($0.count)") }
        let disclosure: AskScreen<UIDomain, AskDefaultMark, Text, Text, EmptyView> = AskScreen(store: store)
            .tiles { Text(verbatim: "\($0)") }
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
        let footer: AskScreen<UIDomain, AskDefaultMark, Text, EmptyView, Text> = AskScreen(store: store)
            .answerFooter { _ in Text(verbatim: "callout") }
            .tiles { Text(verbatim: "\($0.count)") }
        let both: AskScreen<UIDomain, EmptyView, Text, Text, Text> = AskScreen(store: store)
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
            .answerFooter { _ in Text(verbatim: "callout") }
            .tiles { Text(verbatim: "\($0)") }
            .mark { _ in EmptyView() }
        _ = neither.body
        _ = disclosure.body
        _ = footer.body
        _ = both.body
    }

    // MARK: - No view builders, and the builders one at a time

    /// A host that sets no view builder: AskKit's mark, a title card for each
    /// row, a plain line and nothing under the answer.
    @Test("No view builders — AskKit's mark and tiles")
    func noViewBuilders() {
        let screen: AskScreen<UIDomain, AskDefaultMark, AskDefaultTiles<UIRow>, EmptyView, EmptyView> = AskScreen(
            store: makeStore(asker: ScriptedAsker())
        )
        _ = screen.body
    }

    /// The one initializer takes the screen's options, each defaulting, and
    /// none of its views: those are the modifiers'.
    @Test("The initializer takes every option, and each defaults")
    func theInitializerTakesEveryOption() {
        let store = makeStore(asker: ScriptedAsker())
        let spelled: AskScreen<UIDomain, AskDefaultMark, AskDefaultTiles<UIRow>, EmptyView, EmptyView> = AskScreen(
            store: store,
            accent: .blue,
            spectrum: .aurora,
            nothingToAskAction: AskNothingToAskAction("Add Your First Record") {},
            onAttach: {},
            composerAccessory: AskComposerAccessory(
                systemImage: "dice", label: Text(verbatim: "Surprise me"), identifier: "surprise"
            ) {}
        )
        let defaulted: AskScreen<UIDomain, AskDefaultMark, AskDefaultTiles<UIRow>, EmptyView, EmptyView> =
            AskScreen(store: store, onAttach: {})
        _ = spelled.body
        _ = defaulted.body
    }

    /// Each modifier sets its own view builder, in its own generic position,
    /// and leaves the others as they were.
    @Test("Each modifier sets its own view builder")
    func eachModifierSetsItsOwnViewBuilder() {
        let store = makeStore(asker: ScriptedAsker())
        let mark: AskScreen<UIDomain, EmptyView, AskDefaultTiles<UIRow>, EmptyView, EmptyView> =
            AskScreen(store: store).mark { _ in EmptyView() }
        let footer: AskScreen<UIDomain, AskDefaultMark, AskDefaultTiles<UIRow>, EmptyView, Text> =
            AskScreen(store: store).answerFooter { _ in Text(verbatim: "callout") }
        let disclosure: AskScreen<UIDomain, AskDefaultMark, AskDefaultTiles<UIRow>, Text, EmptyView> =
            AskScreen(store: store).evidenceDisclosure { _ in Text(verbatim: "rows") }
        let rowsOnly: AskScreen<UIDomain, AskDefaultMark, Text, EmptyView, EmptyView> =
            AskScreen(store: store).tiles { Text(verbatim: "\($0.count)") }
        let every: AskScreen<UIDomain, EmptyView, Text, Text, Text> = AskScreen(store: store)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
            .answerFooter { _ in Text(verbatim: "callout") }
            .buildersDepend(on: 1)
        let opening = AskScreen(store: store)
            .tiles { _, rows, open in Text(verbatim: "\(rows.count) \(open == nil)") }
            .answerFooter { _ in Text(verbatim: "callout") }
        _ = mark.body
        _ = footer.body
        _ = disclosure.body
        _ = rowsOnly.body
        _ = every.body
        _ = opening.body
    }

    /// **No spectrum is today's screen**: a screen built without one holds
    /// none, so its composer, its face and its caret take the accent's path.
    /// And a spectrum a host sets outlives every modifier, each of which
    /// builds a screen of a new type from the old one's parts.
    @Test("A spectrum, or none, survives every modifier")
    func theSpectrumSurvivesEveryModifier() {
        let store = makeStore(asker: ScriptedAsker())
        #expect(AskScreen(store: store).configuration.spectrum == nil)
        #expect(AskScreen(store: store, accent: .orange, onAttach: {}).configuration.spectrum == nil)
        #expect(AskScreen(store: store).mark { _ in EmptyView() }.configuration.spectrum == nil)
        let every = AskScreen(store: store, spectrum: .aurora)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in Text(verbatim: "\(turn.question): \(rows.count)") }
            .evidenceDisclosure { _ in Text(verbatim: "rows") }
            .answerFooter { _ in Text(verbatim: "callout") }
            .buildersDepend(on: 1)
        #expect(every.configuration.spectrum == .aurora)
        #expect(every.configuration.accent == .accentColor)
        _ = every.body
    }
}

/// What the tiles builder is handed, drawn: the turn each bank is under.
///
/// A builder that found its turn by searching `turns` for the rows it was
/// given would pick the wrong one as soon as two answers chose the same rows,
/// two questions about one record, and would tie every row's drawing to every
/// snapshot besides.
@MainActor
@Suite("The tiles builder's turn", .timeLimit(.minutes(1)))
struct AskTilesBuilderTurnTests {

    /// What a builder was handed, in the order it was called.
    private final class Heard {
        var calls: [(id: UUID, rows: [String])] = []
    }

    /// The thread's rows alone, with what the row needs from a screen.
    private struct Host: View {
        let store: AskConversationStore<UIDomain>
        let tiles: (AskTurn<UIRow>, [UIRow]) -> Text
        let follow = AskScrollFollow()
        @Namespace private var morph
        @State private var expanded: Set<UUID> = []
        @State private var firstWaitRowFocus = false

        var body: some View {
            VStack(alignment: .leading) {
                AskThreadList(
                    store: store, follow: follow, expandedEvidence: $expanded,
                    firstWaitRowFocus: $firstWaitRowFocus,
                    accent: .blue, morph: morph,
                    mark: { _ in EmptyView() }, tiles: tiles,
                    evidenceDisclosure: { _ in EmptyView() }, answerFooter: { _ in EmptyView() },
                    onCopy: { _ in }, onEdit: { _ in }
                )
            }
        }
    }

    @Test func twoAnswersThatChoseTheSameRowsEachHandOverTheirOwnTurn() async throws {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(asker: asker)
        store.ask("What should I play?")
        await settle(store)
        store.ask("What should I play tonight?")
        await settle(store)
        #expect(store.turns.count == 2)
        #expect(store.turns.allSatisfy { $0.answer?.tiles == [UIRow("Rumours")] })

        let heard = Heard()
        let host = Host(store: store) { turn, rows in
            heard.calls.append((turn.id, rows.map(\.displayTitle)))
            return Text(verbatim: turn.question)
        }
        let renderer = ImageRenderer(content: host.frame(width: 400, height: 1200))
        _ = try #require(renderer.cgImage)

        #expect(Set(heard.calls.map(\.id)) == Set(store.turns.map(\.id)), "each bank was handed its own turn")
        #expect(heard.calls.allSatisfy { $0.rows == ["Rumours"] }, "and the rows its answer chose")
    }
}

/// A row keyed by an `Int`, an id type no other test's tiles use, so the
/// mismatch it logs is its own.
private nonisolated struct NumberedRow: AskRow {
    let id: Int
    let displayTitle: String
}

/// The `open` a tiles builder is handed: the host's opener, typed by the
/// row's id, or nil where a tap would open nothing.
///
/// `askItemOpener` erases the router's id type to cross the environment, so
/// an opener wired for one id type and called with another would open nothing
/// and say nothing, with the tile looking as tappable as the rest. Handed nil
/// instead, the tile stays inert.
@MainActor
@Suite("The tiles builder's open", .timeLimit(.minutes(1)))
struct AskTilesBuilderOpenTests {

    /// A router for the rows' own id type, which also keeps the `open` the
    /// builder was handed.
    private final class Heard: AskItemRouter {
        /// The `open` the builder was handed, once it was drawn.
        var handed: ((String) -> Void)??
        var opened: [String] = []

        func open(_ id: String) {
            opened.append(id)
        }
    }

    /// A router for `UUID`s, an id type the rows don't have.
    private final class UUIDRoutes: AskItemRouter {
        var opened: [UUID] = []

        func open(_ id: UUID) {
            opened.append(id)
        }
    }

    private func draw(with opener: AskItemOpenAction?, heard: Heard) throws {
        let tiles = AskOpeningTiles<UIRow, Color>(
            turn: AskTurn<UIRow>(question: "What should I play?", origin: .typed),
            rows: [UIRow("Rumours")],
            logSubsystem: "AskKit.uitests"
        ) { _, _, open in
            heard.handed = .some(open)
            return Color.clear
        }
        let renderer = ImageRenderer(
            content: tiles.environment(\.askItemOpener, opener).frame(width: 10, height: 10)
        )
        _ = try #require(renderer.cgImage)
    }

    @Test func anOpenerForTheRowsIdTypeIsHandedOver() throws {
        let heard = Heard()
        try draw(with: AskItemOpenAction(heard), heard: heard)
        let handed = try #require(heard.handed, "the builder was drawn")
        let open = try #require(handed, "and handed an opener for the rows' ids")
        open("Rumours")
        #expect(heard.opened == ["Rumours"])
    }

    @Test func anOpenerForAnotherIdTypeLeavesTheTileInert() throws {
        let heard = Heard()
        let routes = UUIDRoutes()
        try draw(with: AskItemOpenAction(routes), heard: heard)
        let open = try #require(heard.handed, "the builder was drawn")
        #expect(open == nil)
        #expect(routes.opened.isEmpty)
    }

    @Test func noOpenerLeavesTheTileInert() throws {
        let heard = Heard()
        try draw(with: nil, heard: heard)
        let open = try #require(heard.handed, "the builder was drawn")
        #expect(open == nil)
    }

    @Test func theDefaultTilesLogAnOpenerForAnotherIdTypeToo() throws {
        // The default bank asks of its opener what a builder's tiles do, so a
        // mismatched one is logged instead of opening nothing in silence.
        let tiles = AskDefaultTiles(rows: [NumberedRow(id: 1, displayTitle: "Rumours")])
        let renderer = ImageRenderer(
            content: tiles
                .environment(\.askItemOpener, AskItemOpenAction(UUIDRoutes()))
                .frame(width: 200, height: 100)
        )
        _ = try #require(renderer.cgImage)
        #expect(AskOpenerMismatch.hasReported(Int.self))
    }
}

/// A value the host's builders draw from, and the finished rows SwiftUI
/// skips as unchanged.
///
/// `AskThreadRow` compares the values it draws from and not the builders,
/// which are closures. Unless the host names it (`buildersDepend(on:)`), a
/// flag a builder captures goes on being drawn at its old value in a finished
/// answer for as long as the row stays on screen.
@MainActor
@Suite("A row and what its builders draw from", .timeLimit(.minutes(1)))
struct AskThreadRowBuildersTokenTests {

    /// A namespace, which only a view can make.
    private struct NamespaceProbe: View {
        let heard: (Namespace.ID) -> Void
        @Namespace private var space

        var body: some View {
            heard(space)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private final class Captured {
        var namespace: Namespace.ID?
    }

    private func namespace() throws -> Namespace.ID {
        let captured = Captured()
        let renderer = ImageRenderer(content: NamespaceProbe { captured.namespace = $0 })
        _ = try #require(renderer.cgImage)
        return try #require(captured.namespace)
    }

    /// One finished turn, the same for every row a test compares.
    private let turn: AskTurn<UIRow> = {
        var turn = AskTurn<UIRow>(question: "What should I play?", origin: .typed)
        turn.settle(AskAnswer(text: "Rumours.", matches: [UIRow("Rumours")], tiles: [UIRow("Rumours")]), at: 0)
        return turn
    }()

    private func row(
        _ token: AskBuildersToken?,
        morph: Namespace.ID,
        focusesWaitRow: Bool = false,
        spectrum: AskSpectrum? = nil
    ) -> AskThreadRow<UIDomain, EmptyView, EmptyView, EmptyView, EmptyView> {
        AskThreadRow(
            turn: turn, previous: nil, isLast: false, showsChips: false, followUps: [],
            offersAnotherPick: false, arrivalEnding: nil, offersFeedback: false, proposalPhase: nil,
            awaitsProposalOutcome: false, isEvidenceExpanded: false, focusesWaitRow: focusesWaitRow, accent: .blue, spectrum: spectrum,
            morph: morph, domain: UIDomain(),
            mark: { _ in EmptyView() }, tiles: { _, _ in EmptyView() },
            evidenceDisclosure: { _ in EmptyView() }, answerFooter: { _ in EmptyView() },
            buildersToken: token,
            onFollowUp: { _ in }, onCoaching: { _ in }, onDecline: { _ in }, onRerollPick: {},
            onRetry: {}, onStop: {}, onWaitRowFocused: {}, onFailureTakesFocus: {}, onRate: { _ in },
            onCopy: { _ in }, onCopyAnswer: {}, onEdit: {},
            onAskAgain: {}, evidenceExpansion: .constant(false), onConfirmProposal: {},
            onHandOffProposal: {}, onDeclineProposal: {}, onProposalOutcomeFocused: {}
        )
    }

    @Test func aChangedValueRedrawsAFinishedRow() throws {
        let morph = try namespace()
        #expect(row(AskBuildersToken(false), morph: morph) != row(AskBuildersToken(true), morph: morph))
        #expect(row(nil, morph: morph) != row(AskBuildersToken(true), morph: morph))
    }

    @Test func theSameValueLeavesItAlone() throws {
        let morph = try namespace()
        #expect(row(AskBuildersToken(true), morph: morph) == row(AskBuildersToken(true), morph: morph))
        #expect(row(nil, morph: morph) == row(nil, morph: morph))
    }

    /// The spectrum is one of the row's values, which its caret is drawn in,
    /// so a host that sets or changes it redraws the rows on screen.
    @Test func aChangedSpectrumRedrawsARow() throws {
        let morph = try namespace()
        #expect(row(nil, morph: morph) != row(nil, morph: morph, spectrum: .aurora))
        #expect(row(nil, morph: morph, spectrum: .aurora) != row(nil, morph: morph, spectrum: AskSpectrum([.red, .orange])))
        #expect(row(nil, morph: morph, spectrum: .aurora) == row(nil, morph: morph, spectrum: .aurora))
    }

    /// The wait row taking VoiceOver's focus after Try Again or a chip is one
    /// of the row's values, so a row SwiftUI would otherwise skip draws again
    /// when it changes (`AskThreadList.waitRowFocus`).
    @Test func takingTheWaitRowsFocusRedrawsTheRow() throws {
        let morph = try namespace()
        #expect(row(nil, morph: morph, focusesWaitRow: true) != row(nil, morph: morph))
        #expect(row(nil, morph: morph, focusesWaitRow: true) == row(nil, morph: morph, focusesWaitRow: true))
    }

    @Test func valuesOfTwoTypesAreNeverEqual() throws {
        let morph = try namespace()
        #expect(row(AskBuildersToken(1), morph: morph) != row(AskBuildersToken("1"), morph: morph))
    }
}

#endif
