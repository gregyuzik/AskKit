#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// A router that opens rows keyed by a `UUID`, keeping what it was handed.
@MainActor private final class UUIDRoutes: AskItemRouter {
    var opened: [UUID] = []

    func open(_ id: UUID) {
        opened.append(id)
    }
}

/// A router that opens rows keyed by a `String`.
@MainActor private final class StringRoutes: AskItemRouter {
    var opened: [String] = []

    func open(_ id: String) {
        opened.append(id)
    }
}

/// One class that is both routers, as a host's navigation object can be: a
/// proposal isn't `Hashable`, so its `open(_:)` leaves the item router's
/// `RowID` to the `UUID` one.
@MainActor private final class BothRoutes: AskItemRouter, AskDraftRouter {
    var openedRows: [UUID] = []
    var openedProposals: [AskProposal] = []

    func open(_ id: UUID) {
        openedRows.append(id)
    }

    func open(_ proposal: AskProposal) {
        openedProposals.append(proposal)
    }
}

/// The id crosses an environment value that cannot be generic, so the action
/// holds its router without the router's id type. A router wired for one id
/// type and called with another must open nothing, never the wrong row.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskItemOpenActionTests {

    @Test func theIdArrivesAtTheRouterWithItsTypeIntact() {
        let routes = UUIDRoutes()
        let id = UUID()
        AskItemOpenAction(routes)(id)
        #expect(routes.opened == [id])
    }

    @Test func aStringIdWorksJustAsWell() {
        let routes = StringRoutes()
        AskItemOpenAction(routes)("b6")
        #expect(routes.opened == ["b6"])
    }

    /// A router opens its own id type and ignores another's.
    @Test func aMismatchedIdTypeOpensNothing() {
        let routes = UUIDRoutes()
        let action = AskItemOpenAction(routes)
        action("not-a-uuid")
        action(7)
        #expect(routes.opened.isEmpty)
    }

    /// The tap by an id that is only `Hashable`, as a row's is.
    @Test func theTapReachesTheRouterByARowsId() {
        let routes = StringRoutes()
        let action = AskItemOpenAction(routes)
        action.open(UIRow("Rumours").id)
        action.open(UUID())
        #expect(routes.opened == ["Rumours"])
    }

    /// What the screen asks before it hands a tiles builder an `open`
    /// (`AskOpeningTiles`).
    @Test func itSaysWhichIdTypeItOpens() {
        let action = AskItemOpenAction(UUIDRoutes())
        #expect(action.opens(UUID.self))
        #expect(!action.opens(String.self))
    }

    /// **The point of a router.** SwiftUI compares each opener written to the
    /// environment with the last, so one built in a body from the same
    /// router must be the same opener, and one from another router must not.
    @Test func actionsAreTheSameOpenerExactlyWhenTheyHoldTheSameRouter() {
        let routes = UUIDRoutes()
        #expect(AskItemOpenAction(routes) == AskItemOpenAction(routes))
        #expect(AskItemOpenAction(routes) != AskItemOpenAction(UUIDRoutes()))
    }
}

/// The hand-off's door: the whole proposal reaches the host's router, and two
/// actions are one opener exactly when they hold one router.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskDraftOpenActionTests {

    private static let addRecord = AskProposal(
        kind: .handOff, title: "Add Kind of Blue", actionLabel: "Add",
        payload: Data(#"{"title":"Kind of Blue"}"#.utf8)
    )

    @Test func theProposalArrivesAtTheRouter() {
        let routes = BothRoutes()
        AskDraftOpenAction(routes)(Self.addRecord)
        #expect(routes.openedProposals == [Self.addRecord])
        #expect(routes.openedRows.isEmpty)
    }

    @Test func actionsAreTheSameOpenerExactlyWhenTheyHoldTheSameRouter() {
        let routes = BothRoutes()
        #expect(AskDraftOpenAction(routes) == AskDraftOpenAction(routes))
        #expect(AskDraftOpenAction(routes) != AskDraftOpenAction(BothRoutes()))
    }

    /// One object behind both doors, each opening only its own kind of thing.
    @Test func oneClassIsBothRouters() {
        let routes = BothRoutes()
        let id = UUID()
        AskItemOpenAction(routes)(id)
        AskDraftOpenAction(routes)(Self.addRecord)
        #expect(routes.openedRows == [id])
        #expect(routes.openedProposals == [Self.addRecord])
    }
}

#endif
