#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// How the host opens one of the rows an answer stood on.
///
/// A tile belongs to the host (the `tiles` builder `AskScreen` takes draws it,
/// in an `AskTileGrid`), and so does what it opens, which often lives
/// elsewhere: the builder can sit in a shared module that the destination
/// isn't in, and iOS pushes a detail onto its stack where the Mac and
/// visionOS open a window. So the host supplies the verb and the tile supplies
/// the gesture, and neither has to know about the other.
///
/// It carries the row's **id**, never the row: a host's rows can be SwiftData
/// `@Model` objects, which aren't `Sendable`, and a host opens by id anyway,
/// with the same id an `openWindow(id:value:)` and a deep link use.
///
/// **Generic at both ends, erased in the middle,** because hosts don't agree
/// on what an id is: one's is a `UUID`, another's a `String`. An environment
/// value can't be generic (`@Entry` has nowhere to put the parameter), so the
/// action holds the router without its `RowID`, and an id is cast to the
/// router's own type on the way out. An action wired for one type and called
/// with another opens nothing rather than opening the wrong thing, and says
/// nothing. That's why a tile is better off with the
/// `open` the screen's `tiles(_:)` hands its builder: typed by the row's id,
/// and nil, so the tile is inert, when the host wired this for another type,
/// which the screen logs once for each id type.
///
/// **A zoom is the host's to draw as well, and AskUI draws no transition
/// source.** A zoom needs one `@Namespace` at both ends:
/// `matchedTransitionSource(id:in:)` on the tile, and
/// `navigationTransition(.zoom(sourceID:in:))` on the destination the host
/// pushes. The namespace reaches the tile however the host's modules allow:
/// through the host's own view that builds the tiles, or down the
/// environment when that view sits in a shared module the destination isn't
/// in. A tile built for the Mac as well can apply the source through a
/// wrapper of `matchedTransitionSource(id:in:)` that does nothing there, as
/// the first rule asks. Four rules:
/// - **Not on the Mac.** `navigationTransition(.zoom)` doesn't exist there,
///   and the Mac opens a row in a window, which has no source to match.
/// - **Key the source on the tile, not the row.** A row the thread showed in
///   two answers has a tile in each, and two sources under one id let SwiftUI
///   grow the zoom out of either, not necessarily the one under the reader's
///   finger. `AskTileGrid` hands each of its tiles an id of its own for that;
///   record the tapped one before opening the row.
/// - **An opening with no picture pushes plainly.** A row opened from text,
///   such as one listed in the evidence disclosure, names no source, and its
///   destination arrives by a plain push.
/// - **Say while something is pushed.** Set `askItemIsPushed` on the screen
///   from the state the push reads. The screen holds its navigation bar open
///   while it's true, because a page pushed under the minimized bar hangs the
///   app, zoom or not (`AskNavigationBarMinimization`).
///
/// **The host conforms a class, and the action holds it.** The verb lives on
/// the host's own object (`AskItemRouter`), so the action stores no closure,
/// and two actions on one router are equal. SwiftUI compares each value
/// written to `askItemOpener` with the last, and an equal one draws nothing
/// again, so an action built in a body is the same opener on every pass for
/// as long as its router is the same object: keep the router in `@State` or
/// on an object the app already holds. A new router is a new opener, and
/// every bank of tiles in the thread draws again. The demo's `DemoRoutes` is
/// that shape.
nonisolated public struct AskItemOpenAction: Sendable, Equatable {
    /// The host's router, compared by identity.
    private let router: any AskItemRouter

    /// An action that opens a row through `router`, by an id of the type the
    /// host's rows are identified by (the router's `RowID`, the `ID` of its
    /// `AskRow`).
    ///
    /// - Parameter router: The host's object that opens a row by its id.
    public init(_ router: some AskItemRouter) {
        self.router = router
    }

    /// Opens the row with `id`. An id of another type than the router's
    /// opens nothing, and says nothing.
    @MainActor
    public func callAsFunction(_ id: some Hashable & Sendable) {
        open(id)
    }

    /// Whether the host wired this for ids of `type`, so a caller can tell
    /// before a tap whether it would open anything.
    func opens<ID>(_ type: ID.Type) -> Bool {
        Self.takes(type, router)
    }

    /// The tap, by an id that need not be `Sendable`: a row's id is only
    /// `Hashable`, and the tap never leaves the main actor.
    @MainActor
    func open(_ id: some Hashable) {
        Self.open(id, through: router)
    }

    /// Two actions are the same opener when they hold the same router.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.router === rhs.router
    }

    /// Whether `router` opens ids of `type`, with the router's own type in
    /// hand to name its `RowID`.
    private static func takes<Router: AskItemRouter, ID>(_ type: ID.Type, _ router: Router) -> Bool {
        type is Router.RowID.Type
    }

    /// Hands `id` to `router` if it is of the router's `RowID` type.
    @MainActor
    private static func open<Router: AskItemRouter>(_ id: some Hashable, through router: Router) {
        guard let id = id as? Router.RowID else { return }
        router.open(id)
    }
}

/// The host's object that opens one of its rows by id: what `askItemOpener`
/// carries, wrapped in an `AskItemOpenAction`.
///
/// A class, so the opener is compared by identity: SwiftUI takes a write of
/// the same router for no change, where a closure, which never compares
/// equal, would be a change on every pass. On the main actor, where a tap
/// lands and where the host's navigation state lives, so a conforming class
/// is main-actor isolated too, and `Sendable` with it.
///
/// One router opens rows of one id type. A host whose rows are identified by
/// a `UUID` conforms with `func open(_ id: UUID)`, and that names the
/// `RowID`.
@MainActor
public protocol AskItemRouter: AnyObject, Sendable {
    /// The type the host's rows are identified by: the `ID` of its `AskRow`.
    associatedtype RowID: Hashable & Sendable

    /// Opens the row with `id`: push its page, open its window or show it in
    /// a sheet, as the host does.
    ///
    /// - Parameter id: The id of the row a tile, or a row the evidence
    ///   disclosure lists, stands for.
    func open(_ id: RowID)
}

extension EnvironmentValues {
    /// How the host opens a row, set by a host whose tiles open their rows.
    /// **Nil means there is nowhere to go**, and a tile stays inert rather
    /// than pretending: a host that never wires this gets an inert grid, not a
    /// tap that does nothing. AskUI's default tiles read it, and so does the
    /// `open` that `AskScreen.tiles(_:)` hands a builder.
    @Entry public var askItemOpener: AskItemOpenAction?
}

#endif
