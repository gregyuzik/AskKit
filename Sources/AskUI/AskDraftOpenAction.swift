#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import SwiftUI

/// How the host opens its own editor for a proposal that hands off
/// (`AskProposalKind.handOff`).
///
/// The sibling of `AskItemOpenAction`, and for the same reason: the door out of
/// a thread belongs to the app, not to AskKit. That one opens a row the answer
/// stood on; this one opens a form the answer offers to start: a host's
/// editor for a new item, seeded with a draft, or, where the reader named
/// nothing to seed it with, its menu of things to add, opened with nothing
/// chosen.
///
/// **A payload may carry an intent and no data.** That last case is the shape
/// to know: "add an item" names nothing, so there is no seed, and the card's
/// whole content is which door to open. It still needs a payload, because a
/// host reads one by trying its request types in order, and an empty one
/// declares none of their keys: untagged, it decodes as every one of them. A
/// one-case `Kind` on each request is what keeps them apart.
///
/// **It carries the whole `AskProposal`, not an id**, which is the one place it
/// differs from its sibling. `AskItemOpenAction` erases its router's id type
/// because hosts disagree about what an id is and `@Entry` can't be generic. A
/// proposal is one concrete type, so there is nothing to erase: the host reads
/// `payload(as:)` for its own seed and is done. The seed is the domain's own
/// encoding either way, so nothing here has to know what is in it.
///
/// **Nothing is saved by the tap.** The host opens its editor and returns; what
/// the reader does there is theirs, and a cancel isn't a failure. So this
/// returns nothing: there is no outcome to report, and the card says what it
/// opened rather than what came of it (`AskProposalOutcome.handedOff`).
///
/// **Open, don't perform.** A host tempted to do the work here instead of
/// opening should propose `.perform` and implement `AskDomain.perform(_:)`,
/// which is the path with an outcome, a failure line and a retry.
///
/// **The host conforms a class, and the action holds it**, as its sibling
/// does (`AskItemOpenAction`): the verb lives on the host's own object
/// (`AskDraftRouter`), so the action stores no closure, and two actions on one
/// router are equal. An action built in a body is the same opener on every
/// pass while its router is the same object; a new router draws every
/// confirmation card in the thread again. Keep the router in `@State` or on an
/// object the app holds.
nonisolated public struct AskDraftOpenAction: Sendable, Equatable {
    /// The host's router, compared by identity.
    private let router: any AskDraftRouter

    /// An action that opens the host's editor for a proposal through
    /// `router`.
    ///
    /// - Parameter router: The host's object that opens its editor for a
    ///   proposal.
    public init(_ router: some AskDraftRouter) {
        self.router = router
    }

    /// Opens the host's editor for `proposal`. The confirmation card calls
    /// it, and then records the hand-off on the turn.
    @MainActor
    public func callAsFunction(_ proposal: AskProposal) {
        router.open(proposal)
    }

    /// Two actions are the same opener when they hold the same router.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.router === rhs.router
    }
}

/// The host's object that opens its own editor for a proposal that hands off:
/// what `askDraftOpener` carries, wrapped in an `AskDraftOpenAction`.
///
/// A class on the main actor, for the reasons `AskItemRouter` gives: compared
/// by identity, so the same router written again is no change, and isolated
/// where the tap lands and the host's navigation state lives. One class can be
/// both routers: a proposal isn't `Hashable`, so its `open(_:)` never names an
/// item router's `RowID`.
@MainActor
public protocol AskDraftRouter: AnyObject, Sendable {
    /// Opens the editor the proposal names, seeded from its payload where it
    /// carries one, and returns without waiting for the reader.
    ///
    /// - Parameter proposal: The proposal the reader confirmed, whose
    ///   `payload(as:)` holds the domain's own seed.
    func open(_ proposal: AskProposal)
}

extension EnvironmentValues {
    /// Set by a host whose domain proposes hand-offs. **Nil means there is
    /// nowhere to go**, and the card's action is disabled rather than offering
    /// a tap that does nothing, the same bargain `askItemOpener` strikes for
    /// an inert tile. Not now stays live.
    ///
    /// A host whose domain only ever proposes `.perform` never sets it, and
    /// nothing about its cards changes.
    @Entry public var askDraftOpener: AskDraftOpenAction?
}

#endif
