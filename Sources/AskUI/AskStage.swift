#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import SwiftUI

// In AskUI's own names, for the doc below: the prose fades through
// `AskRevealRenderer` and the wait row's phrase through `.contentTransition`.
// The first screen's key is `AskFirstScreen`'s `isMakingRoom`, and the other
// two first screens animate on the keyboard flag it is made from
// (`AskFirstScreen.onKeyboard`); `AskKeyboard.change(_:to:duration:curve:in:)`
// has the recordings of the chips crossing their 102 pt in a single frame. The
// composer's key is `AskScreen`'s `typingRaisesComposer`.

/// **The one animation key a turn can reach.**
///
/// Layout animates on this value and on nothing else a turn produces. Not on
/// tokens, not on tool payloads, not on the turn array: a stream produces
/// thirty snapshots a second, and a layout animation keyed to any of them
/// re-runs the whole thread thirty times a second while the reader is trying to
/// read it (house rule 4).
///
/// So the value is coarse on purpose: it changes when the thread's *shape*
/// changes. A turn appears, the last turn gets its first words, a turn
/// completes, the wait row comes or goes, or the screen swaps between a first
/// screen and the thread. Everything finer is drawn, not animated: prose fades
/// in where it lands, the wait row's phrase cross-fades, and what an answer
/// brings besides its words comes up through `askArrival`, a piece at a time
/// and without moving a frame.
///
/// **Two other keys, both the keyboard's.** The first screen's column
/// animates as it closes up for the keyboard and opens out again. Its key
/// changes when the keyboard comes or goes, and otherwise only when the ready
/// screen itself arrives or leaves, the text size crosses extra-large, or the
/// window turns to compact height or back. The column it animates leaves the
/// screen the moment a turn starts, so no stream ever reaches it. Nor can the
/// keyboard's own animation do the job: it carries the scroll view around the
/// column, but a UIKit animation can't move SwiftUI's layout inside it, and
/// left to the keyboard alone the chips crossed the whole of their move in a
/// single frame.
///
/// The same key carries the other two first screens' columns, which never
/// make room: around a fold across the screen their arrangement ends for the
/// keyboard as the ready screen's does, and they animate its coming back on
/// the keyboard's own flag, the one the first key is made from. One key with
/// one more column on it, not a third: that flag changes when the keyboard
/// comes or goes and at no other time, and those columns leave the screen as a
/// turn starts too.
///
/// The second is the composer rising out of a host's slot
/// (`askComposerSlot`): `AskScreen` fades it in and gives it its height as the
/// screen's own keyboard comes and goes, or as focus holds where no keyboard
/// comes. It never changes on a stream, and never on a tab switch, which shows
/// the tab as it was left.
nonisolated public struct AskStage: Equatable, Sendable {
    /// Every turn on the thread, so an insertion or a New Chat is a change.
    public let turns: [UUID]
    /// Whether the last turn has written anything yet: the frame the wait row
    /// gives way to prose.
    public let lastHasText: Bool
    /// Whether the last turn is done: the frame the tiles and the evidence
    /// line arrive. The follow-ups wait for `isThinking` to fall, once the
    /// stream behind the answer has ended.
    public let lastIsComplete: Bool
    /// Whether a turn is in flight at all.
    public let isThinking: Bool
    /// Which screen shows: the thread, or one of the first screens. A change
    /// here is a whole-screen swap and wants its own transition.
    public let phase: Phase
    /// Whether `phase` can pick the first screen yet. False until the
    /// model's state has been read (`AskModelStatus.hasHeardFromSeam`, or the
    /// engine's first refresh returning), while a mirror nobody has published
    /// to reads as a tier serving, and until the library's overview has been
    /// read, while every library reads as empty. No first screen shows until
    /// it is true: otherwise a cold launch would open on "nothing to ask
    /// about", or on the ready screen with starters to tap on a device that
    /// can't serve, before the screen it means to show.
    ///
    /// Two waits end sooner. A device that can't serve is known once the
    /// model's state is, since its reason outranks the library. And an
    /// overview that doesn't come back within the domain's turn deadline is
    /// waited for no longer: the first screen opens as on a library it knows
    /// nothing of, which is never one it calls empty. A thread with turns is
    /// always known.
    public let firstScreenIsKnown: Bool

    /// Which screen shows: the thread, or one of the three first screens.
    nonisolated public enum Phase: Equatable, Sendable {
        /// The thread has turns.
        case thread
        /// Nothing asked yet, and something to ask about.
        case ready
        /// Nothing to ask about yet: an empty library, under a first-screen
        /// policy that needs the reader's own rows
        /// (`AskFirstScreenPolicy.needsOwnedRows`), from a host with words
        /// for it (`AskBrand.nothingToAskCopy`).
        case nothingToAskAbout
        /// No tier can serve, with the reason. It outranks an empty library.
        case cannotServe(AskUnavailability)
    }

    init(
        turns: [UUID],
        lastHasText: Bool,
        lastIsComplete: Bool,
        isThinking: Bool,
        phase: Phase,
        firstScreenIsKnown: Bool = true
    ) {
        self.turns = turns
        self.lastHasText = lastHasText
        self.lastIsComplete = lastIsComplete
        self.isThinking = isThinking
        self.phase = phase
        self.firstScreenIsKnown = firstScreenIsKnown
    }

    /// What layout animates on as the Stage changes: `AskScreen`'s
    /// conversation and the pane beside iPhone Duo's fold, and the face in a
    /// host's slot, which sits outside the screen's transaction
    /// (`AskComposerFace`). One value, so what one change of Stage moves, it
    /// moves on one curve. Reduce Motion takes none instead (house rule 8).
    static let animation = Animation.snappy(duration: 0.28)

    /// The stage a thread is at.
    static func of<Row: AskRow>(
        turns: [AskTurn<Row>],
        isThinking: Bool,
        overview: AskOverview,
        unavailability: AskUnavailability?,
        policy: AskFirstScreenPolicy = .ownedLibrary,
        hasNothingToAskCopy: Bool = true,
        overviewIsRead: Bool = true,
        overviewIsOverdue: Bool = false,
        statusIsRead: Bool = true
    ) -> AskStage {
        of(
            turnIDs: turns.map(\.id),
            lastHasText: !(turns.last?.text.isEmpty ?? true),
            lastIsComplete: turns.last?.isComplete ?? false,
            isThinking: isThinking, overview: overview,
            unavailability: unavailability, policy: policy,
            hasNothingToAskCopy: hasNothingToAskCopy,
            overviewIsRead: overviewIsRead, overviewIsOverdue: overviewIsOverdue,
            statusIsRead: statusIsRead
        )
    }

    /// The same stage from the thread's shape alone, which is what the store
    /// keeps (`AskConversationStore.shape`) so that reading the stage never
    /// reads the thread.
    ///
    /// `overviewIsOverdue` says the first read of the overview ran past the
    /// domain's turn deadline, so the first screen waits for it no longer.
    static func of(
        turnIDs: [UUID],
        lastHasText: Bool,
        lastIsComplete: Bool,
        isThinking: Bool,
        overview: AskOverview,
        unavailability: AskUnavailability?,
        policy: AskFirstScreenPolicy,
        hasNothingToAskCopy: Bool = true,
        overviewIsRead: Bool = true,
        overviewIsOverdue: Bool = false,
        statusIsRead: Bool = true
    ) -> AskStage {
        let phase: Phase
        if !turnIDs.isEmpty {
            phase = .thread
        } else if let unavailability {
            // The reason outranks an empty library: a reader who can't be
            // served needs to know that before being told they own nothing.
            phase = .cannotServe(unavailability)
        } else if overview.isEmpty, overviewIsRead, policy.needsOwnedRows, hasNothingToAskCopy {
            // Only where an empty library really is an empty Ask. A domain
            // whose subject is public, such as a guide to a city's parks, can be
            // asked about before the reader keeps anything of it, and telling
            // them there is nothing to ask about would be false.
            //
            // And only where the host has words for it. A brand with no
            // `nothingToAskCopy` gets the ready screen, as a policy that
            // doesn't need owned rows does, rather than a mark with nothing
            // under it; the engine logs the mismatch as it is built.
            //
            // And only for an overview that was read: one that never came
            // back says nothing about the library.
            phase = .nothingToAskAbout
        } else {
            phase = .ready
        }
        return AskStage(
            turns: turnIDs,
            lastHasText: lastHasText,
            lastIsComplete: lastIsComplete,
            isThinking: isThinking,
            phase: phase,
            firstScreenIsKnown: !turnIDs.isEmpty
                || (statusIsRead && (overviewIsRead || overviewIsOverdue || unavailability != nil))
        )
    }
}

#endif
