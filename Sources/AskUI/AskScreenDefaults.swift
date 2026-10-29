#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
import os
public import SwiftUI

/// The mark `AskScreen` draws when the host gives it none: the sparkles
/// symbol, tertiary when unlit, and when lit in the environment's tint. That
/// tint is the app's accent color unless the host sets another with `.tint`;
/// the screen's `accent` doesn't reach it.
///
/// `AskScreen.mark(_:)` says where a mark is lit. Hidden from VoiceOver, since
/// it only decorates the screen.
public struct AskDefaultMark: View {
    private let isLit: Bool

    /// Creates the mark.
    ///
    /// - Parameter isLit: Whether to draw it lit, which is what `AskScreen`
    ///   hands a mark.
    public init(isLit: Bool) {
        self.isLit = isLit
    }

    public var body: some View {
        Image(systemName: "sparkles")
            .resizable()
            .scaledToFit()
            .padding(6)
            .foregroundStyle(isLit ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .accessibilityHidden(true)
    }
}

/// The bank `AskScreen` draws when the host gives it no tiles: a card for each
/// row an answer chose, titled with its `displayTitle`, in an `AskTileGrid`.
///
/// A card is a button that opens its row through `askItemOpener` when the host
/// wired one for the row's id type, and plain text otherwise, which is what
/// `askItemOpener` asks of every tile. An opener wired for another id type is
/// logged, as it is for a builder's tiles (`AskOpeningTiles`).
public struct AskDefaultTiles<Row: AskRow>: View {
    private let rows: [Row]
    private let logSubsystem: String

    @Environment(\.askItemOpener) private var opener
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the bank. A mismatched opener is logged under the app's bundle
    /// identifier.
    ///
    /// - Parameter rows: The rows the answer chose, in the order to show them.
    public init(rows: [Row]) {
        self.init(rows: rows, logSubsystem: AskBrand.subsystem(nil))
    }

    /// The bank `AskScreen` draws, logging under the store's subsystem.
    init(rows: [Row], logSubsystem: String) {
        self.rows = rows
        self.logSubsystem = logSubsystem
    }

    public var body: some View {
        let wired = AskOpenerMismatch.opener(opener, for: Row.ID.self, subsystem: logSubsystem)
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        AskTileGrid(rows, columns: AskDefaultTileText.columns(isAccessibilitySize: isAccessibilitySize), spacing: 10) { row, _ in
            card(row, opener: wired, lineLimit: AskDefaultTileText.lineLimit(isAccessibilitySize: isAccessibilitySize))
        }
    }

    /// The radius of a card's corners.
    private static var corner: CGFloat { 12 }

    @ViewBuilder
    private func card(_ row: Row, opener: AskItemOpenAction?, lineLimit: Int?) -> some View {
        let title = Text(verbatim: row.displayTitle)
            .font(.subheadline.weight(.medium))
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            // **At least a touch target tall** (`AskGrowth.touchTarget`). One
            // line of the title with its padding came to about 40 pt, and the
            // whole card is what a tap lands on.
            .frame(minHeight: AskGrowth.touchTarget)
            // A fill, not glass: tiles are content.
            .background(.fill.tertiary, in: .rect(cornerRadius: Self.corner))
        if let opener {
            Button { opener.open(row.id) } label: { title }
                .buttonStyle(.plain)
                // Lit in the card's own corners. The fill is the card's
                // shape, so Button Shapes adds none.
                .askHoverEffect(in: .rect(cornerRadius: Self.corner))
        } else {
            title
        }
    }
}

/// How AskKit's default tiles lay out their titles, apart from the view so the
/// sizes can be pinned (`AskTileGridTests`).
///
/// **Columns a title can live in, and at the accessibility sizes a column
/// that grows with it.** 132 to 200 pt is room for two lines of a title at the
/// default size, where `AskLayout.tileColumns(for:tallestAspect:spacing:)`
/// sizes columns for pictures. Neither grows with the text, so at the largest
/// size two lines of a 200 pt column held about twelve characters of a title.
/// There the columns are at least 264 pt, one across a phone and two across
/// the reading width, and a title takes the lines it needs. Below the
/// accessibility sizes nothing changes.
nonisolated enum AskDefaultTileText {
    static func columns(isAccessibilitySize: Bool) -> AskTileColumns {
        isAccessibilitySize
            ? .adaptive(minimum: 264, maximum: AskLayout.readingWidth, spacing: 10)
            : .adaptive(minimum: 132, maximum: 200, spacing: 10)
    }

    /// Two lines, or all of them at the accessibility sizes.
    static func lineLimit(isAccessibilitySize: Bool) -> Int? {
        isAccessibilitySize ? nil : 2
    }
}

/// The tiles of a builder that takes an `open` (`AskScreen.tiles(_:)`): the
/// host's `askItemOpener`, typed by the row's id.
///
/// `open` is nil where there is nowhere to go, so the tile stays inert, as
/// `askItemOpener` promises: no opener at all, or one the host wired for
/// another id type. The second is a wiring mistake that would otherwise open
/// nothing and say nothing, so it is logged, once for each id type.
struct AskOpeningTiles<Row: AskRow, Tiles: View>: View {
    let turn: AskTurn<Row>
    let rows: [Row]
    let logSubsystem: String
    let tiles: (AskTurn<Row>, [Row], ((Row.ID) -> Void)?) -> Tiles

    @Environment(\.askItemOpener) private var opener

    var body: some View {
        tiles(turn, rows, open)
    }

    private var open: ((Row.ID) -> Void)? {
        guard let opener = AskOpenerMismatch.opener(opener, for: Row.ID.self, subsystem: logSubsystem) else {
            return nil
        }
        return { opener.open($0) }
    }
}

/// The id types an opener was found not to take, each logged once.
enum AskOpenerMismatch {
    private static var reported: Set<ObjectIdentifier> = []

    /// `opener` when it opens rows with ids of `type`, and nil when there is
    /// none or it takes another type. The second is a wiring mistake that
    /// would otherwise open nothing and say nothing, so it is logged, once for
    /// each id type.
    static func opener<ID>(_ opener: AskItemOpenAction?, for type: ID.Type, subsystem: String) -> AskItemOpenAction? {
        guard let opener else { return nil }
        guard opener.opens(type) else {
            report(type, subsystem: subsystem)
            return nil
        }
        return opener
    }

    /// Whether a mismatch for `type` has been logged.
    static func hasReported<ID>(_ type: ID.Type) -> Bool {
        reported.contains(ObjectIdentifier(type))
    }

    private static func report<ID>(_ type: ID.Type, subsystem: String) {
        guard reported.insert(ObjectIdentifier(type)).inserted else { return }
        Logger(subsystem: subsystem, category: "ask").fault(
            "askItemOpener takes another id type than \(String(reflecting: type), privacy: .public), so the tiles open nothing"
        )
    }
}

/// A value the host's builders draw from, compared the way a row's own values
/// are (`AskScreen.buildersDepend(on:)`). Two tokens are equal when the second
/// one's value casts to the first one's type and the two compare equal.
struct AskBuildersToken: Equatable {
    private let value: any Equatable

    init(_ value: some Equatable) {
        self.value = value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.isEqual(to: rhs.value)
    }
}

private extension Equatable {
    /// Equal to `other` when `other` is a value of this type, and equal.
    func isEqual(to other: any Equatable) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

#endif
