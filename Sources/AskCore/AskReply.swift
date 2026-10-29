#if canImport(FoundationModels) && !os(tvOS)

import FoundationModels

/// The question kinds a reply may claim.
///
/// **One static vocabulary, deliberately.** `@Generable` builds a *static*
/// `generationSchema`: the macro can't read an instance's
/// `AskDomain.questionKinds`, and `AskReply` can't be generic over a domain,
/// so `.anyOf` here has to be a compile-time list. It is the union of the
/// kinds real hosts needed, so a few (`totalValue`, `wear`, `pairing`,
/// `suggestion`) belong to one kind of app. Each domain narrows it two ways:
/// its own `questionKinds` is what the engine normalizes the answer against
/// (anything outside becomes `other`), and its prompt's steer line is what
/// tells the model which of these its questions actually come in.
///
/// Why not a schema per domain: ARCHITECTURE.md, Rejected designs.
nonisolated public enum AskQuestionKind {
    /// Anything else about what the reader has.
    public static let lookup = "lookup"
    /// How many: the number is the answer, so no tiles.
    public static let count = "count"
    /// What a set is worth all together: likewise no tiles.
    public static let totalValue = "totalValue"
    /// A recommendation: a choice among things that could each be right, so
    /// one or two tiles, and another pick is a fair thing to ask for.
    public static let pick = "pick"
    /// The one that ranks first by a measure: the oldest, the most valuable,
    /// the highest rated. One right answer, so another pick of it is a wrong
    /// one. A domain that lists `pick` without this kind gets its superlatives
    /// as picks.
    public static let superlative = "superlative"
    /// A which/what/do-I-have question asking for all of them.
    public static let everyMatch = "everyMatch"
    /// A plain yes or no: the word is the answer, so no tiles.
    public static let yesNo = "yesNo"
    /// What has or hasn't been used, as in a wardrobe's wear history.
    public static let wear = "wear"
    /// What goes with one particular piece, such as what to wear with a
    /// jacket.
    public static let pairing = "pairing"
    /// A whole outfit or plan for an occasion.
    public static let suggestion = "suggestion"
    /// None of the above.
    public static let other = "other"

    /// The full vocabulary, for the schema.
    public static let all = [
        lookup, count, totalValue, pick, superlative, everyMatch, yesNo, wear, pairing, suggestion, other
    ]

    /// The default a domain gets when it names none.
    public static let `default` = [lookup, count, pick, everyMatch, yesNo, other]

    /// The kinds for which a number or a plain yes or no, not the things, is
    /// the answer, so no tiles are shown whatever the model returned. The
    /// `tiles` guide asks for none for each of them, and an empty list is not
    /// enough to say so: it falls back to the rows the prose names.
    public static let showNoTiles: Set<String> = [count, totalValue, yesNo]

    /// Anything in a domain's `questionKinds` that this vocabulary doesn't
    /// contain, which can only be a typo.
    ///
    /// The schema's vocabulary is fixed and shared, so a domain listing
    /// `"cuont"` isn't declaring a kind of its own: it is failing to declare
    /// `count`. The engine then normalizes the model's correct `count` to
    /// `other`, so the kind no longer decides that a count shows no tiles
    /// (house rule 7), and nothing else says so. `AskEngine` logs what this
    /// finds when it is built.
    ///
    /// A *subset* is normal and isn't reported: every domain lists only the
    /// kinds it asks about.
    public static func unrecognized(in kinds: [String]) -> [String] {
        let known = Set(all)
        return kinds.filter { !known.contains($0) }
    }
}

/// What one turn asks the model to write, unless its domain's reply shape is
/// `.prose` (`AskProseReply`).
///
/// **The order is load-bearing.** `answer` comes first so the prose streams into
/// the thread while everything after it is still being written; `questionKind`
/// comes before the tile decision it drives; `followUps` last, since they are
/// shown only once the turn has landed.
///
/// The follow-ups are MODEL OUTPUT that becomes a PROMPT when tapped, so they
/// ride back in through `ask` and are fenced by `AskPrompt` like any other
/// question. `AskAnswer.cleanedFollowUps` makes them plain text, since a chip
/// shows its text as it is, and is the length-and-shape guard, not the
/// injection one.
@Generable
nonisolated public struct AskReply: Sendable {
    /// The answer's prose, streamed while the rest is still being written.
    @Guide(description: AskReply.answerGuide)
    public var answer: String

    /// What kind of question the reader asked, from `AskQuestionKind.all`.
    ///
    /// **Every host's model reads this text, so a word here changes every
    /// host's answers.** Its examples are drawn from real hosts, and they are
    /// measured, not decoration: without `pick`'s example, "What should I
    /// watch?" tiled every row it read in 6 runs of 6, and without
    /// `suggestion`'s example and `pairing`'s "one particular piece", "What
    /// should I wear tomorrow?" was filed as a pairing in 7 of 8.
    ///
    /// So are its words. `lookup` is "anything else about what they have", not
    /// the neutral-sounding "about what the app holds": on the on-device model
    /// that one filed "What do I have that's good for work?" as a pairing on 8
    /// of 9 samples, and "Do I own anything in green?" outside `lookup` on 3 of
    /// 9, both `lookup` on baseline; "what they have" filed them `lookup` on 11
    /// of 12. A possessive question needs a possessive anchor.
    @Guide(description: """
        What kind of question this was, whatever language it was asked in — what the USER asked \
        for, never what your own answer happens to mention: an answer that volunteers what \
        something is worth, or how many there are, does not make the question a "totalValue" or a \
        "count" one. "count" for how many — the number is the answer. "totalValue" for what a set \
        is worth all together. "pick" for a recommendation (what to watch, play or read next): a \
        choice. "superlative" for the one that ranks first by a measure (the oldest, the most \
        valuable, the highest rated). "everyMatch" for a which, what or do-I-have question asking \
        for all of them. "yesNo" for a plain yes or no. "wear" for what has or hasn't been used. \
        "pairing" for what goes with one particular piece. "suggestion" for a whole plan for a day \
        or an occasion (what to wear today or tomorrow). "lookup" for anything else about what \
        they have. "other" when the question is about none of that.
        """, .anyOf(AskQuestionKind.all))
    public var questionKind: String

    /// Whether the answer is every row the tools found, so all of them show as
    /// tiles.
    @Guide(description: """
        True only when the answer IS the set of things the tools found — a which, what or do-I-have \
        question asking for all of them — so every one found is shown as a picture tile. False for \
        a pick or a superlative (a choice: one or two tiles), a how-many or what-is-it-worth \
        question (the number is the answer), a plain yes or no, or an answer that concerns no \
        particular thing.
        """)
    public var showsEveryMatch: Bool

    /// The titles of the rows to show as tiles, in order, when
    /// `showsEveryMatch` is false.
    @Guide(description: """
        When showsEveryMatch is false: the things to show as picture tiles under the answer, each \
        by its EXACT title from the tool results, in display order — only the one or two \
        recommended for a pick or a superlative, and none for a how-many or total-value question, \
        a plain yes or no, or an answer that concerns no particular thing. Empty when \
        showsEveryMatch is true.
        """)
    public var tiles: [String]

    /// Two questions the reader might ask next, offered as chips under the
    /// answer.
    @Guide(description: AskReply.followUpsGuide, .count(2))
    public var followUps: [String]
}

/// The guides the two reply shapes share, written once: `answer`'s and
/// `followUps`' text in `AskReply` and in `AskProseReply` alike. A word changed
/// here changes what every host's model reads in both shapes, as `AskReply`'s
/// other guides do in one.
nonisolated extension AskReply {
    /// `answer`'s guide, in `AskReply` and `AskProseReply` alike.
    static let answerGuide = "The answer: one to three short plain sentences. Name things in **bold** the first time. No lists, no headings, no emoji."

    /// `followUps`' guide, in `AskReply` and `AskProseReply` alike.
    static let followUpsGuide = """
        Exactly two short questions the user could ask NEXT about what you just discussed, written \
        in their voice. Make them DIFFERENT SHAPES: one that narrows what was just answered, and \
        one that broadens it to something nearby. Each must be answerable with the tools you have. \
        Never a repeat of what they just asked.
        """
}

/// Which reply a domain's turns ask the model to write (`AskDomain.replyShape`).
///
/// **Two static schemas, and only two.** Each is a `@Generable` type of its
/// own, so each keeps typed `PartiallyGenerated` streaming, the reason a
/// schema built per domain was ruled out (ARCHITECTURE.md, Rejected designs).
/// A third case would be a new shape for every host's sessions to stream, and
/// a breaking change.
nonisolated public enum AskReplyShape: String, Sendable, Equatable {
    /// `AskReply`: the answer, the question kind, the tile choice and the
    /// follow-ups. The default.
    case full
    /// `AskProseReply`: the answer and the follow-ups alone, for a domain
    /// whose answers never show tiles. The model writes no question kind and
    /// chooses no tiles, so the window those fields cost is saved, and a
    /// domain with no rows has no tile titles invented for it.
    case prose
}

/// What one turn asks the model to write for a domain whose answers never
/// show tiles (`AskReplyShape.prose`): `AskReply` without the question kind
/// and the tile choice.
///
/// **The same two fields, word for word.** Each guide is `AskReply`'s own, so
/// a word changed for one shape is changed for both, and in `AskReply`'s
/// order, for its reasons: the answer streams first, and the follow-ups,
/// shown once the turn has landed, come last.
@Generable
nonisolated public struct AskProseReply: Sendable {
    /// The answer's prose, streamed while the follow-ups are still to come.
    @Guide(description: AskReply.answerGuide)
    public var answer: String

    /// Two questions the reader might ask next, offered as chips under the
    /// answer.
    @Guide(description: AskReply.followUpsGuide, .count(2))
    public var followUps: [String]
}

/// One streaming snapshot of an `AskReply` or an `AskProseReply`, as the
/// engine sees it. Each field is nil until the model has begun writing it, and
/// the three a prose reply doesn't have stay nil.
///
/// **The engine never touches `AskReply.PartiallyGenerated`.** A session is
/// reached only through `AskSession`, so a test's session can emit these
/// directly, and the whole turn loop (grounding, partials, tile resolution,
/// hand-downs, deadlines) runs without a model.
nonisolated public struct AskReplySnapshot: Sendable, Equatable {
    /// `AskReply.answer`, as far as it has been written.
    public var answer: String?
    /// `AskReply.questionKind`, as far as it has been written.
    public var questionKind: String?
    /// `AskReply.showsEveryMatch`, once the model has written it.
    public var showsEveryMatch: Bool?
    /// `AskReply.tiles`, as far as they have been written.
    public var tiles: [String]?
    /// `AskReply.followUps`, as far as they have been written.
    public var followUps: [String]?

    /// A snapshot, with nil for each field the model hasn't begun.
    public init(
        answer: String? = nil,
        questionKind: String? = nil,
        showsEveryMatch: Bool? = nil,
        tiles: [String]? = nil,
        followUps: [String]? = nil
    ) {
        self.answer = answer
        self.questionKind = questionKind
        self.showsEveryMatch = showsEveryMatch
        self.tiles = tiles
        self.followUps = followUps
    }
}

#endif
