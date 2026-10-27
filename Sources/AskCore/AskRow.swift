/// One row of a host's own data that an answer can be grounded in and shown as
/// a tile.
///
/// The fields stay in the host: a book, a record and a tool have
/// nothing in common but a title and an identity, and the tile view is the
/// host's (`AskScreen`'s `tiles` builder). AskCore needs exactly this much:
/// something to record in the collector, resolve the model's tile names
/// against, name in a recap, and persist with a thread.
///
/// `Codable` because a row rides the thread to disk; `Equatable` so the store
/// and the UI can tell a changed turn from an unchanged one.
///
/// **A value, not a reference.** Make it a struct or an enum, or a class
/// whose fields never change: a row recorded into an answer is what the
/// answer showed, and a class mutated after it was recorded would change
/// answers already on screen and on disk, and an equality the store redraws
/// by would compare the row with itself.
nonisolated public protocol AskRow: Codable, Sendable, Identifiable, Equatable {
    /// The row's name as the model sees it in tool output and writes it back in
    /// `AskReply.tiles`: the string tile resolution matches on.
    var displayTitle: String { get }
}

/// The row type of a domain whose tools read no rows: the default
/// `AskDomain.Row`.
///
/// A stand-in for the generics the engine, the thread file and the screen
/// are written over, for a host whose tools return text or propose actions
/// and record nothing. Nothing needs to make one: an answer that read no rows
/// has no tiles and no counted evidence line, and its turn keeps empty row
/// lists in the thread file.
nonisolated public struct AskNoRow: AskRow {
    /// The row's identity, which is its title too.
    public let id: String
    /// `id`: a stand-in has nothing else to be called by.
    public var displayTitle: String { id }

    /// A row named `id`.
    public init(id: String) {
        self.id = id
    }
}
