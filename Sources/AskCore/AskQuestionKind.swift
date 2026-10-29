/// One of the question kinds a reply may claim.
///
/// **One static vocabulary, deliberately.** `@Generable` builds a *static*
/// `generationSchema`: the macro can't read an instance's
/// `AskDomain.questionKinds`, and `AskReply` can't be generic over a domain,
/// so its `.anyOf` has to be a compile-time list, which is `all`'s words. It
/// is the union of the kinds real hosts needed, so a few (`totalValue`,
/// `wear`, `pairing`, `suggestion`) belong to one kind of app. Each domain
/// narrows it two ways: its own `questionKinds` is what the engine normalizes
/// the answer against (anything outside becomes `other`), and its prompt's
/// steer line is what tells the model which of these its questions actually
/// come in.
///
/// **A type, not a string**, so a domain names a kind by its member and can't
/// misspell one: a domain listing `"cuont"` would get the model's correct
/// `count` normalized to `other`, a count that then shows tiles, and house
/// rule 7's decision lost. The model still writes the word
/// (`AskReply.questionKind`, `AskReplySnapshot.questionKind`), and the engine
/// turns it into a kind when it normalizes it against the domain's list.
///
/// Why not a schema per domain: ARCHITECTURE.md, Rejected designs.
nonisolated public struct AskQuestionKind: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    /// The word the schema offers the model and a chat file stores.
    public let rawValue: String

    /// The kind with this word. Never fails, as `Notification.Name`'s doesn't:
    /// a kind a later AskKit writes to a chat file, or one this vocabulary
    /// no longer has, still decodes, so the answer it belongs to isn't
    /// dropped. Not `ExpressibleByStringLiteral`, which would let `"cuont"`
    /// back in where a kind is asked for; `unrecognized(in:)` catches one
    /// built here.
    ///
    /// Encoded as the bare word, as a `String` was, so a chat file's bytes
    /// are the ones 0.2.0 wrote.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The word, so a log or table line prints `count`, not the type.
    public var description: String { rawValue }

    /// Anything else about what the reader has.
    public static let lookup = AskQuestionKind(rawValue: "lookup")
    /// How many: the number is the answer, so no tiles.
    public static let count = AskQuestionKind(rawValue: "count")
    /// What a set is worth all together: likewise no tiles.
    public static let totalValue = AskQuestionKind(rawValue: "totalValue")
    /// A recommendation: a choice among things that could each be right, so
    /// one or two tiles, and another pick is a fair thing to ask for.
    public static let pick = AskQuestionKind(rawValue: "pick")
    /// The one that ranks first by a measure: the oldest, the most valuable,
    /// the highest rated. One right answer, so another pick of it is a wrong
    /// one. A domain that lists `pick` without this kind gets its superlatives
    /// as picks.
    public static let superlative = AskQuestionKind(rawValue: "superlative")
    /// A which/what/do-I-have question asking for all of them.
    public static let everyMatch = AskQuestionKind(rawValue: "everyMatch")
    /// A plain yes or no: the word is the answer, so no tiles.
    public static let yesNo = AskQuestionKind(rawValue: "yesNo")
    /// What has or hasn't been used, as in a wardrobe's wear history.
    public static let wear = AskQuestionKind(rawValue: "wear")
    /// What goes with one particular piece, such as what to wear with a
    /// jacket.
    public static let pairing = AskQuestionKind(rawValue: "pairing")
    /// A whole outfit or plan for an occasion.
    public static let suggestion = AskQuestionKind(rawValue: "suggestion")
    /// None of the above.
    public static let other = AskQuestionKind(rawValue: "other")

    /// The full vocabulary, in the order the schema offers its words.
    public static let all: [AskQuestionKind] = [
        lookup, count, totalValue, pick, superlative, everyMatch, yesNo, wear, pairing, suggestion, other
    ]

    /// The default a domain gets when it names none.
    public static let `default`: [AskQuestionKind] = [lookup, count, pick, everyMatch, yesNo, other]

    /// The kinds for which a number or a plain yes or no, not the things, is
    /// the answer, so no tiles are shown whatever the model returned. The
    /// `tiles` guide asks for none for each of them, and an empty list is not
    /// enough to say so: it falls back to the rows the prose names.
    public static let showNoTiles: Set<AskQuestionKind> = [count, totalValue, yesNo]

    /// Anything in a domain's `questionKinds` that this vocabulary doesn't
    /// contain, which can only be a misspelling built with `init(rawValue:)`.
    ///
    /// The schema's vocabulary is fixed and shared, so a domain listing
    /// `AskQuestionKind(rawValue: "cuont")` isn't declaring a kind of its own:
    /// it is failing to declare `count`. The engine then normalizes the
    /// model's correct `count` to `other`, so the kind no longer decides that
    /// a count shows no tiles (house rule 7), and nothing else says so.
    /// `AskEngine` logs what this finds when it is built.
    ///
    /// A *subset* is normal and isn't reported: every domain lists only the
    /// kinds it asks about.
    public static func unrecognized(in kinds: [AskQuestionKind]) -> [AskQuestionKind] {
        let known = Set(all)
        return kinds.filter { !known.contains($0) }
    }
}
