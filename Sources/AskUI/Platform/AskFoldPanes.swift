#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI

/// The screen laid out around iPhone Duo's fold (`AskFoldArrangement`): a
/// pane on the leading side beside the conversation, or the conversation
/// alone, clear of a bend or across the whole width. The leading pane is the
/// reader's chats, or the first screen's leading half before they have any
/// (`AskScreen.leadingPane`).
///
/// **The conversation is one view in every arrangement**: always the last
/// child and never swapped, so opening or closing the device, which moves the
/// scene from one display to the other, keeps its scroll position and its
/// focus. Only the leading pane comes and goes, and what it holds is a list
/// the store reloads or copy that keeps no state.
///
/// **Narrowed, the conversation is a phone's**: a side of the inner display is
/// about the outer display's size, so it lays out at compact width whatever
/// the window's size class says. Otherwise the first screen, which goes side
/// by side in a short regular-width window, would put its halves about
/// 150 pt apiece.
///
/// **As wide as it is offered, whatever the panes hold.** The fold is read in
/// this view's space and the leading pane is as wide as the fold's x there
/// (`AskScreen.body`), so this view must stand where it is put, or the
/// reading moves what it reads. On the iPhone Duo simulator (iOS 27.1) open
/// on its side, a side of the inner display is off the pixel grid, 371.17 pt
/// of an 867 pt screen, and a conversation holding a ready first screen read
/// wider than that, 371.33. The stack was a sixth of a point wider than the
/// screen and, centered, stood a twelfth of a point to the left: the fold's x
/// grew by that, the leading pane with it, and the next reading differed
/// again. 967 readings in 7 s, closing on 455.67 by halves and starting over
/// from 455.5, each one a rebuild of the screen: the main thread never left
/// the update and the first screen was never drawn.
/// Around a fold, a zero minimum on the conversation's frame and on the
/// stack's keeps each to its offer (`keepsToItsOffer`), and what is wider
/// runs over on the trailing side.
struct AskFoldPanes<Leading: View, Conversation: View>: View {
    let arrangement: AskFoldArrangement
    /// Whether the fold is drawn as a hairline between the panes: between the
    /// chats and the conversation, which are two things, and not between the
    /// first screen's two halves, which are one, nor beside a pane with
    /// nothing in it yet.
    var showsHairline = true
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let conversation: () -> Conversation

    var body: some View {
        HStack(spacing: 0) {
            if case .panes(let width, let gap) = arrangement {
                leading()
                    .frame(width: width)
                // The fold: a hairline in the middle of the gap, or where the
                // panes meet when a flat fold reports no width. Hidden rather than
                // removed where it isn't drawn, so the panes keep their places.
                Divider()
                    .padding(.horizontal, gap / 2)
                    .opacity(showsHairline ? 1 : 0)
            }
            conversation()
                .frame(maxWidth: conversationWidth)
                .frame(minWidth: keepsToItsOffer, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, conversationInset)
                #if os(iOS)
                .transformEnvironment(\.horizontalSizeClass) { sizeClass in
                    if narrows { sizeClass = .compact }
                }
                #endif
        }
        .frame(minWidth: keepsToItsOffer, maxWidth: narrows ? .infinity : nil, alignment: .leading)
    }

    /// The conversation's width where it keeps to the leading side of a bend.
    private var conversationWidth: CGFloat? {
        if case .leading(let width) = arrangement { width } else { nil }
    }

    /// How far the conversation starts from the leading edge where it keeps to
    /// the trailing side of a bend.
    private var conversationInset: CGFloat {
        if case .trailing(let inset) = arrangement { inset } else { 0 }
    }

    private var narrows: Bool { arrangement.narrowsConversation }

    /// The least width of the conversation's frame and of the stack's, around
    /// a fold: none, so each is as wide as it is offered and no wider (the
    /// type has why). Away from a fold nothing is read from where the stack
    /// stands, and it keeps its content's own least width.
    private var keepsToItsOffer: CGFloat? { narrows ? 0 : nil }
}

/// What the pane on the leading side of iPhone Duo's fold holds, decided
/// apart from the screen so the cases can be pinned (`AskFoldTests`).
nonisolated enum AskLeadingPane: Equatable, Sendable {
    /// Nothing yet: it can't be said which of the other two the pane is.
    case blank
    /// The first screen's leading half, before the reader has a chat: what
    /// Ask is, or why it can't serve where it still has starters to offer
    /// (`AskFirstScreenArrangement.takesBothPanes`).
    case about
    /// The reader's chats (`AskChatsPane`).
    case chats

    /// **Blank until the pane knows what it is.** Before the saved chats are
    /// read, none listed means none read. With them read and none there, the
    /// pane is the first screen's or an empty list's, and which depends on a
    /// first screen that isn't known until the library is read: a list drawn
    /// meanwhile would say "No earlier chats" for a moment at every launch,
    /// and then be replaced. A reader with chats sees them as soon as they
    /// are read.
    static func resolve(
        firstScreenTakesBothPanes: Bool,
        chatsAreRead: Bool,
        hasChats: Bool,
        firstScreenIsKnown: Bool
    ) -> AskLeadingPane {
        if firstScreenTakesBothPanes { return .about }
        guard chatsAreRead, hasChats || firstScreenIsKnown else { return .blank }
        return .chats
    }
}

#endif
