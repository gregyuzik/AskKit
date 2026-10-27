import AskCore
import Foundation
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
import SwiftUI

/// The two routers a host conforms to open rows and editors, conformed here
/// under the posture a host that doesn't share AskKit's compiles under: no
/// `swiftSettings`, so nonisolated by default (`CrossPostureTests` says why
/// the target has none).
///
/// **Neither class spells `@MainActor`.** Each takes the main actor from the
/// protocol it conforms to, and is `Sendable` with it, so the plain shape a
/// host writes compiles. An action built from one is a value the host can
/// hand anywhere, and is compared off the main actor.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureRouterTests {

    /// What a host's tab builds: an opener for its rows and one for its
    /// editor, from its own routing object, handed to the screen's
    /// environment.
    @MainActor
    @Test func aHostsRoutersOpenWhatTheyAreHandedWithoutThePosture() {
        let routes = CrossPostureRoutes()
        let id = UUID()
        let opener = AskItemOpenAction(routes)
        opener(id)
        opener("an id of another type")
        let proposal = AskProposal(kind: .handOff, title: "Add Kind of Blue", actionLabel: "Add")
        let drafts = AskDraftOpenAction(routes)
        drafts(proposal)
        #expect(routes.pushed == [id])
        #expect(routes.drafted == [proposal])

        let titles = CrossPosturePlainRoutes()
        AskItemOpenAction(titles)("Rumours")
        #expect(titles.opened == ["Rumours"])

        _ = EmptyView()
            .environment(\.askItemOpener, opener)
            .environment(\.askDraftOpener, drafts)
    }

    /// Two actions on one router are one opener, compared where no actor is.
    @Test func anOpenerIsComparedOffTheMainActor() async {
        let (opener, again, other) = await MainActor.run {
            let routes = CrossPostureRoutes()
            return (AskItemOpenAction(routes), AskItemOpenAction(routes), AskItemOpenAction(CrossPostureRoutes()))
        }
        #expect(opener == again)
        #expect(opener != other)
        let (drafts, draftsAgain) = await MainActor.run {
            let routes = CrossPostureRoutes()
            return (AskDraftOpenAction(routes), AskDraftOpenAction(routes))
        }
        #expect(drafts == draftsAgain)
    }
}

/// A host's routing object as the demo's is: observable, and both routers.
@Observable
private final class CrossPostureRoutes: AskItemRouter, AskDraftRouter {
    var pushed: [UUID] = []
    var drafted: [AskProposal] = []

    func open(_ id: UUID) {
        pushed.append(id)
    }

    func open(_ proposal: AskProposal) {
        drafted.append(proposal)
    }
}

/// The plainest router: a class with the one method.
private final class CrossPosturePlainRoutes: AskItemRouter {
    var opened: [String] = []

    func open(_ id: String) {
        opened.append(id)
    }
}
#endif
