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
/// **One at a time, the first that applies** (`AskTips.group`). Each tip's one
/// rule is its surface being on screen with nothing over it, which `AskScreen`
/// works out and writes to `AskTipGates`, so the group's current tip is always
/// one a view is drawing. Each goes once its action has been done, from the
/// menu, the swipe or VoiceOver, or once it's closed with its ×.
///
/// **No tip moves a frame** (house rule 4): the question's and the chat's are
/// popovers, and the starter's is drawn in an overlay beside the bank
/// (`AskStarterTip`).
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

/// "Don't suggest this" in a starter's menu. Drawn beside the first screen's
/// bank (`AskStarterTip`), and retired as a starter or a follow-up is turned
/// down, which is the same item under the same gesture.
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

/// Where a tip's arrow points (`tipAnchor(_:)`).
nonisolated enum AskTipAnchor: Hashable, Sendable {
    /// A starter on the first screen, by its id (`AskStarterTipAnchor`).
    case starter(String)
}

/// The starter tip, over the first screen's bank with its arrow on the first
/// starter (`AskStarterDeclineTip`).
///
/// **Inline, aimed with an anchor, not a popover.** The starters are
/// interactive glass, and a popover tip on a button in glass never presented
/// (Compact, iPhone Duo and iPhone 18 Pro simulators, 2026-10-31): an inline
/// tip with `anchorID` beside the glass did.
///
/// **In an overlay, grown up from the bank's top edge**, so it moves no frame
/// (house rule 4): a frame of no height on the edge, the tip standing on it.
/// It covers "Try asking" and the copy above, not the chips, whose menu it
/// asks the reader to open. Outside the bank's own accessibility container,
/// whose first button the smoke suite and VoiceOver take for the first
/// starter, and outside its glass group, since the tip is no capsule.
///
/// At most 340 pt wide, and less where the column is narrower, wrapping
/// rather than cutting its words.
struct AskStarterTip: View {
    /// The starter the arrow points at: the first the bank shows.
    let first: AskStarter?

    var body: some View {
        if let first, AskTips.isCurrent(AskStarterDeclineTip()) {
            TipView(AskStarterDeclineTip(), arrowEdge: .bottom, anchorID: AskTipAnchor.starter(first.id))
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .frame(height: 0, alignment: .bottom)
        }
    }
}

#endif
