#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI
import TipKit

/// The tips that point out what the Ask screen keeps behind a long press, a
/// shortcut menu or a swipe: the menu on a question, "Don't suggest this" on a
/// starter, and deleting one chat. Nothing on screen says any of the three is
/// there, and on iOS the question's menu is the only way a touch reaches Copy
/// answer (`AskQuestionBubble`).
///
/// **The host's TipKit, never AskKit's.** AskKit never calls
/// `Tips.configure`: a host that configures TipKit gets these beside its own,
/// at its own cadence and under its own `Tips.hideAllTipsForTesting()` for its
/// captures, and one that doesn't sees none. Nothing here is public, so a host
/// has nothing to adopt.
///
/// **One at a time, the first that applies** (`AskTips.group`). Each tip's
/// rule is its surface being on screen with nothing over it, which `AskScreen`
/// works out and writes to `AskTipGates`, so the group's current tip is always
/// one a view is drawing. The starter's waits as well for the reader's second
/// visit to Ask (`AskVisits`). Each goes once its action has been done, from
/// the menu, the swipe or VoiceOver, or once it's closed with its ×.
///
/// **No tip moves a frame** (house rule 4): all three are popovers
/// (`askPopoverTip`), the starter's on the "Try asking" heading, the
/// question's on the newest question and the chat's on a row.
@MainActor
enum AskTips {
    /// The three, the question's first.
    ///
    /// **`.firstAvailable`, not `.ordered`.** The three are on different
    /// screens, and a reader who never meets one, a host whose domain keeps no
    /// chats or a reader who never comes back to the first screen, would
    /// otherwise hold the others back for good. In order, the question's
    /// comes first where two apply at once: beside iPhone Duo's fold the
    /// chats are on screen with the thread, and the first screen with them.
    ///
    /// **Static, so one group outlives every screen.** iPhone Duo opening or
    /// closing, a size class changing and a tab switch all rebuild the
    /// screen, and a group held by one would be a new group each time, whose
    /// `currentTip` the views drawing the tips wouldn't share. A `static let`
    /// is made on its first read, which is a body's, after a host's
    /// `Tips.configure` in its `App.init`.
    static let group = TipGroup(.firstAvailable) {
        AskQuestionMenuTip()
        AskStarterDeclineTip()
        AskChatDeleteTip()
    }

    /// Whether `tip` is the group's tip now, and so the one its view draws.
    /// By id, since `currentTip` is an existential.
    static func isCurrent(_ tip: some Tip) -> Bool {
        group.currentTip?.id == tip.id
    }

    /// The screens up and the visit they are (`AskVisits`). Static for the
    /// group's reason: a screen built again finds the visit the one before
    /// it began, and a second window's screen the first's.
    private static var visits = AskVisits()

    /// `screen`, by the identity it holds, has come on screen: where that
    /// begins a visit, TipKit hears of it (`AskVisits.begun`).
    static func screenAppeared(_ screen: UUID) {
        guard visits.screenAppeared(screen, at: .now) else { return }
        AskVisits.begun.sendDonation()
    }

    /// `screen` has gone, under an item a host pushed over it or for good.
    static func screenDisappeared(_ screen: UUID, underPushedItem: Bool) {
        visits.screenDisappeared(screen, underPushedItem: underPushedItem, at: .now)
    }
}

/// The reader's visits to Ask, which the starter's tip waits for the second
/// of (`AskStarterDeclineTip`). A visit begins as a screen appears with none
/// up, and goes on until the last one leaves: opening Ask's tab, or the app
/// on it.
///
/// **Not every appearance begins one.** iPhone Duo opening or closing and a
/// size class changing build the screen again, an item a host pushes over
/// the screen takes it off until its pop, and a second window puts up a
/// screen of its own. Counted, any of them would bring the tip up on the
/// visit it sits out. So a screen appearing while another is up is the same
/// visit, as is one back from under a pushed item, and one that appears
/// within `rebuild` of the last one leaving.
///
/// **A value, so it can be tested** (`AskVisitsTests`): the screens report
/// to the one `AskTips` holds, and it never reads the clock itself.
nonisolated struct AskVisits: Equatable {
    /// A visit begun, donated once for each (`AskTips.screenAppeared(_:)`).
    /// TipKit keeps the newest two, which is all the starter tip's rule
    /// counts to.
    ///
    /// **An event, not a count kept in a parameter.** TipKit reads its store
    /// some time after `Tips.configure` returns. A parameter read in between
    /// was still its default, and that default plus one was what the store
    /// then kept: a count of 1 at every launch, for a reader who opens Ask
    /// first. Donations add to what the store holds, made before `configure`
    /// or after it, and TipKit works the rule out once it has read them
    /// (macOS 27.2, 2026-11-13). In a host that never configures TipKit a
    /// donation keeps nothing, and no tip shows there anyway.
    static let begun = Tips.Event(id: "AskKit.visitBegun", donationLimit: Tips.DonationLimit(maximumCount: 2))

    /// How long after the last screen left an appearance is still the same
    /// visit: a screen being built again, whose old one went first.
    static let rebuild = Duration.seconds(1)

    /// The screens on screen, by the identity each holds.
    private var screensUp: Set<UUID> = []
    /// The screens that went under an item a host pushed over them, until
    /// each comes back.
    private var screensCovered: Set<UUID> = []
    /// When the last screen up left, other than under a pushed item.
    private var lastLeft: ContinuousClock.Instant?

    /// `screen` has come on screen at `now`. True where that begins a visit.
    mutating func screenAppeared(_ screen: UUID, at now: ContinuousClock.Instant) -> Bool {
        let wasCovered = screensCovered.remove(screen) != nil
        let isRebuild = lastLeft.map { now - $0 < Self.rebuild } ?? false
        let goesOn = !screensUp.isEmpty || wasCovered || isRebuild
        screensUp.insert(screen)
        return !goesOn
    }

    /// `screen` has gone at `now`: `underPushedItem`, which its pop brings
    /// it back from on the same visit, or because the reader left. One that
    /// never appeared changes nothing.
    ///
    /// **A covered screen isn't counted as up.** A host can drop a screen
    /// it has pushed over without showing it again, and one counted as up
    /// for good would make every later appearance the same visit.
    mutating func screenDisappeared(_ screen: UUID, underPushedItem: Bool, at now: ContinuousClock.Instant) {
        guard screensUp.remove(screen) != nil else { return }
        if underPushedItem {
            screensCovered.insert(screen)
        } else if screensUp.isEmpty {
            lastLeft = now
        }
    }
}

/// What the tips wait for: each surface on screen with nothing over it, which
/// `AskScreen` writes from its own state (`AskTipGates.Reading`).
///
/// **Transient**, so each starts false at every launch and is true only once a
/// screen has said so: a tip can't come up on a screen that hasn't been drawn,
/// or over the welcome a host shows before it.
///
/// **Spelled out, not `@Parameter`.** The macro declares its parameter
/// `nonisolated(unsafe) static var` and reads it, unmarked, in accessors it
/// writes itself, so under strict memory safety each one is two warnings in a
/// macro's expansion buffer, which the push gate fails on and no `unsafe` here
/// can reach. Each is the same parameter the macro makes, with the same
/// initializer, held in a `let`: a parameter is a handle to TipKit's own store,
/// and a rule built from one copy reads what was written through another
/// (`write()`).
///
/// **So the rules are `Tips.Rule(_:_:)`, not `#Rule`**, which is what that
/// macro expands to. The macro tells a parameter from an event by the `$` in
/// its name, which only a macro's peer can have: handed one of these, it
/// reads it as an event and asks for a count.
nonisolated enum AskTipGates {
    /// The newest question is on screen, between the bars, under an answer
    /// with words in it, so its menu holds Copy answer.
    static let questionMenu = Tips.Parameter(AskTipGates.self, "questionMenu", false, .transient)
    /// A first screen offering starters is up.
    static let starterDecline = Tips.Parameter(AskTipGates.self, "starterDecline", false, .transient)
    /// The chats, in the sheet or in the pane beside iPhone Duo's fold, show a
    /// chat that can be deleted.
    static let chatDelete = Tips.Parameter(AskTipGates.self, "chatDelete", false, .transient)

    /// How long a gate holds open on a screen before the screen writes it
    /// (`AskScreen.settleTipGates()`): past the 12 ms a rebuilt screen took to
    /// hear the keyboard already up, and the 438 ms a cold keyboard's show
    /// trails the composer's focus (`AskScreen.composerHeldUp`).
    static let settling = Duration.milliseconds(500)

    /// What a screen settles its gates on (`AskScreen.settleTipGates()`): its
    /// reading, nil while the reader is in another window, and on visionOS how
    /// many times its window has been resized, after each of which the tips
    /// settle again.
    struct Settling: Equatable {
        var gates: Reading?
        var resizes = 0
    }

    /// The three gates as one screen reads them, written together when any
    /// of them changes (`write()`).
    struct Reading: Equatable {
        var questionMenu = false
        var starterDecline = false
        var chatDelete = false

        /// Writes each gate whose value differs, so a screen that reads the
        /// same thing again tells TipKit nothing.
        func write() {
            Self.write(questionMenu, to: AskTipGates.questionMenu)
            Self.write(starterDecline, to: AskTipGates.starterDecline)
            Self.write(chatDelete, to: AskTipGates.chatDelete)
        }

        /// This reading with each gate that isn't open in `settled` closed:
        /// the part of it that closes gates, and opens none.
        func closing(_ settled: Self) -> Self {
            Self(
                questionMenu: questionMenu && settled.questionMenu,
                starterDecline: starterDecline && settled.starterDecline,
                chatDelete: chatDelete && settled.chatDelete
            )
        }

        /// Writes `value` through a copy of `gate`, whose setter is mutating
        /// though what it sets is TipKit's store and not the copy.
        private static func write(_ value: Bool, to gate: Tips.Parameter<Bool>) {
            var gate = gate
            guard gate.wrappedValue != value else { return }
            gate.wrappedValue = value
        }
    }
}

/// The question's menu: Copy, Copy answer, Edit & Resend and Ask again. A
/// popover on the newest question (`AskQuestionBubble`), retired as any of the
/// four is done (`AskScreen.copy(_:)`, `editAndResend(_:)`, and the two places
/// Ask again lands).
nonisolated struct AskQuestionMenuTip: Tip {
    var title: Text {
        Text("Copy, Edit or Ask Again", bundle: #bundle, comment: "Title of a tip that points at the reader's own question in the Ask thread, whose menu copies the question or its answer, puts it back in the composer to edit, or asks it again.")
    }

    /// In each platform's words for what opens the menu. On the Mac a tip
    /// can't assume a pointer, since the touchscreen MacBook Pro opens the
    /// same menu with a finger, so it names the menu, as the Mac's own guides
    /// call it.
    var message: Text? {
        #if os(iOS)
        Text("Touch and hold a question to copy it or its answer, edit it, or ask it again.", bundle: #bundle, comment: "Tip on iPhone and iPad under 'Copy, Edit or Ask Again', pointing at the reader's own question in the Ask thread: what touching and holding it offers.")
        #elseif os(visionOS)
        Text("Pinch and hold a question to copy it or its answer, edit it, or ask it again.", bundle: #bundle, comment: "Tip on Apple Vision Pro under 'Copy, Edit or Ask Again', pointing at the reader's own question in the Ask thread: what pinching and holding it offers.")
        #else
        Text("Open a question's shortcut menu to copy it or its answer, edit it, or ask it again.", bundle: #bundle, comment: "Tip on the Mac under 'Copy, Edit or Ask Again', pointing at the reader's own question in the Ask thread. 'Shortcut menu' is the Mac's own term for a context menu; use the term the Mac uses in your language.")
        #endif
    }

    var rules: [Rule] {
        Tips.Rule(AskTipGates.questionMenu) { $0 }
    }
}

/// "Don't suggest this" in a starter's menu. A popover over the first
/// screen's "Try asking" heading (`AskFirstScreen`), and retired as a starter
/// or a follow-up is turned down, which is the same item under the same
/// gesture.
///
/// **From the reader's second visit to Ask** (`AskVisits`), and on every one
/// after it until the tip is done or closed. On the first the reader hasn't
/// read the screen it would stand over, or met a suggestion to turn down.
nonisolated struct AskStarterDeclineTip: Tip {
    var title: Text {
        Text("Hide a Suggestion", bundle: #bundle, comment: "Title of a tip that points at the suggested questions on the Ask first screen, any of which the reader can turn down.")
    }

    var message: Text? {
        #if os(iOS)
        Text("Touch and hold a suggestion to stop seeing it.", bundle: #bundle, comment: "Tip on iPhone and iPad under 'Hide a Suggestion', pointing at a suggested question on the Ask first screen.")
        #elseif os(visionOS)
        Text("Pinch and hold a suggestion to stop seeing it.", bundle: #bundle, comment: "Tip on Apple Vision Pro under 'Hide a Suggestion', pointing at a suggested question on the Ask first screen.")
        #else
        Text("Open a suggestion's shortcut menu to stop seeing it.", bundle: #bundle, comment: "Tip on the Mac under 'Hide a Suggestion', pointing at a suggested question on the Ask first screen. 'Shortcut menu' is the Mac's own term for a context menu; use the term the Mac uses in your language.")
        #endif
    }

    var rules: [Rule] {
        Tips.Rule(AskTipGates.starterDecline) { $0 }
        #Rule(AskVisits.begun) { $0.donations.count >= 2 }
    }
}

/// Deleting one chat, by its swipe or its menu. A popover on the first chat in
/// the list that can be deleted (`AskThreadHistoryList`, `AskChatsPane`), and
/// retired as one is.
nonisolated struct AskChatDeleteTip: Tip {
    var title: Text {
        Text("Delete a Chat", bundle: #bundle, comment: "Title of a tip that points at one of the reader's earlier Ask chats in the list of chats, any of which can be deleted on its own.")
    }

    var message: Text? {
        #if os(iOS)
        Text("Swipe across a chat, or touch and hold it, to delete it.", bundle: #bundle, comment: "Tip on iPhone and iPad under 'Delete a Chat', pointing at one of the reader's earlier Ask chats in the list of chats.")
        #elseif os(visionOS)
        Text("Pinch and hold a chat to delete it.", bundle: #bundle, comment: "Tip on Apple Vision Pro under 'Delete a Chat', pointing at one of the reader's earlier Ask chats in the list of chats.")
        #else
        Text("Open a chat's shortcut menu to delete it.", bundle: #bundle, comment: "Tip on the Mac under 'Delete a Chat', pointing at one of the reader's earlier Ask chats in the list of chats. 'Shortcut menu' is the Mac's own term for a context menu; use the term the Mac uses in your language.")
        #endif
    }

    var rules: [Rule] {
        Tips.Rule(AskTipGates.chatDelete) { $0 }
    }
}

/// Which side of its anchor a popover tip stands on (`askPopoverTip`).
///
/// **The Mac reads an arrow edge the other way round.** On iOS and visionOS
/// `arrowEdge` is the popover's own edge that carries the arrow, so `.top`
/// stands the tip under its anchor: the chat tip under its row on the iPhone
/// 18 Pro and Apple Vision Pro simulators. On macOS it is the anchor's side
/// the popover opens on, so `.top` stood the chat tip above its row and the
/// question tip above its bubble, `.bottom` stood the question tip under it,
/// and `.leading` beside it (macOS 27.2, 2026-10-31). A side here means the
/// same on all three.
nonisolated enum AskTipSide: Equatable {
    /// Whichever side the system finds room on.
    case any
    /// Above the anchor, the arrow pointing down at it.
    case above
    /// Below the anchor, the arrow pointing up at it.
    case below
    /// Above or below, whichever has room, never beside. The Mac has no
    /// form of the popover that takes a set of edges, so there it is `any`.
    case aboveOrBelow

    /// The edge `popoverTip(_:arrowEdge:)` takes for this side, nil for the
    /// system's choice.
    var arrowEdge: Edge? {
        switch self {
        case .any, .aboveOrBelow: nil
        #if os(macOS)
        case .above: .top
        case .below: .bottom
        #else
        case .above: .bottom
        case .below: .top
        #endif
        }
    }
}

extension View {
    /// `tip` as a popover from this view while `isShown`, on `side` of it, and
    /// nothing at all while it isn't: a clear view behind this one, its size,
    /// that holds the popover and comes and goes with it.
    ///
    /// **Never a popover modifier handed nil with its tip up.** The question
    /// tip moves to the next question as one is asked, and the chat tip to
    /// the next row that can go. Handed nil in the update that took the tip's
    /// rule away, `.popoverTip` let go of the tip before TipKit had taken the
    /// popover down, and it stayed up over the old question for as long as
    /// the screen did, while the new question never got one (iPhone 18 Pro
    /// simulator, 2026-10-31: Ask again, and a second question asked, each
    /// with the tip up). A view that leaves takes its popover with it, as New
    /// Chat with the tip up showed, so the anchor leaves instead.
    ///
    /// **Nothing while no tip is up**, so the view this is on has no
    /// container of TipKit's around it then. Put it outside the view's
    /// accessibility identifier: the anchor is a container of its own, and
    /// inside the identifier it took the identifier (`AskChatsPane`).
    ///
    /// **Touches go through the tip** (`tipBackgroundInteraction(_:)`), so the
    /// reader can scroll on, or do what it describes, with it up. Without it a
    /// popover tip lays a dismiss region over the window, and the first touch
    /// anywhere only closes the tip.
    func askPopoverTip(_ tip: some Tip, isShown: Bool, side: AskTipSide = .any) -> some View {
        background {
            if isShown {
                Color.clear
                    .askPopoverTip(tip, side: side)
                    .tipBackgroundInteraction(.enabled)
            }
        }
    }

    /// The popover itself, in the form each platform has.
    @ViewBuilder
    private func askPopoverTip(_ tip: some Tip, side: AskTipSide) -> some View {
        #if os(macOS)
        popoverTip(tip, arrowEdge: side.arrowEdge)
        #else
        if side == .aboveOrBelow {
            popoverTip(tip, arrowEdges: .vertical)
        } else {
            popoverTip(tip, arrowEdge: side.arrowEdge)
        }
        #endif
    }
}

extension EnvironmentValues {
    /// The tips' gates as the screen has settled them, which `AskScreen` sets
    /// in the environment (`settledTipGates`), so a view draws its tip only
    /// while its own surface is uncovered as well as while TipKit has the tip
    /// current. TipKit's status can lag a gate that has gone false, and kept
    /// a starter tip up over the keyboard (iPhone Duo simulator, 2026-10-31).
    /// All closed everywhere else.
    @Entry var askTipGates = AskTipGates.Reading()
}

#endif
