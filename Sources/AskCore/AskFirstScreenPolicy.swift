/// What the first screen may show for one host.
///
/// **Two of AskUI's three first screens aren't universal.** Both defaults
/// describe a host whose Ask is about the reader's own library and needs a
/// model to say anything at all. Both are wrong for a host whose subject
/// exists whether or not the reader has collected any of it, such as a guide
/// to a city's parks, and which can answer several questions from its own
/// data.
///
/// Left unstated, such a host would lose two behaviors by adopting AskKit: a
/// reader who has saved nothing would be told there was nothing to ask about
/// while "which parks are open late?" works, and a device without Apple
/// Intelligence would show a dead end where working starters could be.
nonisolated public struct AskFirstScreenPolicy: Sendable, Equatable {
    /// The host can answer its own starters, and route a typed question, with
    /// no model at all.
    ///
    /// When true, a device that can't serve still gets the starters under the
    /// reason, and a live composer: the reason is a caption, not a wall.
    /// `AskDomain.deterministicAnswer(for:)` is what actually answers them,
    /// and a domain that sets this without implementing that hook gets a
    /// screen whose chips fail. The engine logs that mismatch when it is
    /// built (`AskDomain.implementsDeterministicAnswer`).
    public var answersWithoutModel: Bool

    /// Whether an empty library really means there is nothing to ask about.
    ///
    /// True for a host whose every question is about rows the reader owns: an
    /// empty overview (`AskOverview.isEmpty`) shows the nothing-to-ask first
    /// screen, in the brand's words (`AskBrand.nothingToAskCopy`, without
    /// which it shows the ready one). False for one whose subject exists
    /// whether or not the reader has collected any of it, which shows the
    /// ready first screen instead.
    public var needsOwnedRows: Bool

    /// A policy with each field as given. The defaults are `ownedLibrary`'s.
    public init(answersWithoutModel: Bool = false, needsOwnedRows: Bool = true) {
        self.answersWithoutModel = answersWithoutModel
        self.needsOwnedRows = needsOwnedRows
    }

    /// A host whose Ask is about the reader's own library, and needs a model:
    /// the default `AskDomain.firstScreenPolicy` for a domain that retrieves
    /// (`AskGroundingPolicy.retrieval`).
    public static let ownedLibrary = AskFirstScreenPolicy()

    /// A host whose subject isn't the reader's own rows, and needs a model:
    /// the ready first screen whatever the overview says, with starters only
    /// where a tier can serve. The default `AskDomain.firstScreenPolicy` for a
    /// domain that doesn't retrieve (`AskGroundingPolicy.toolCall` or
    /// `.notRequired`), and what a domain whose tools read no rows
    /// (`AskNoRow`) sets under `.retrieval`, since its overview is empty.
    public static let openSubject = AskFirstScreenPolicy(answersWithoutModel: false, needsOwnedRows: false)
}

/// Which answers the engine keeps, by what grounded them: one domain's
/// policy for its life (`AskDomain.grounding`), never one question's.
///
/// **Grounded** is judged the same way under all three. The model called a
/// tool, the app searched for it (the grounded retry), or, on a follow-up, the
/// turn read rows or its prose names a row the thread has already read. The
/// answer records which (`AskAnswer.grounding`). The policies differ only in
/// what they do with a turn nothing grounded.
///
/// Ungated, as `AskFirstScreenPolicy` is, so a host's shared code can name it
/// on every platform it builds for.
nonisolated public enum AskGroundingPolicy: String, Sendable, Equatable, Codable {
    /// An answer with no retrieval behind it is never shown, and the app
    /// retrieves for a model that didn't. Prose draws only once the turn is
    /// grounded. A first answer on a fresh session that ends ungrounded gets
    /// the grounded retry: the planner fills in the domain's
    /// `SearchArguments`, the app runs `AskDomain.search(_:context:)`, and the
    /// question is asked again with the rows fenced as data. An ungrounded
    /// follow-up on a kept conversation fails as `AskError.ungrounded`, with
    /// coaching.
    ///
    /// The default, and the policy for a domain over the reader's own data,
    /// where an answer that read none of it is invented (house rule 2).
    case retrieval
    /// Exactly `.retrieval` without the grounded retry. Grounding is judged
    /// the same way, a follow-up included, which the thread's rows still
    /// ground, and prose draws only once the turn is grounded. But a first
    /// answer that ends ungrounded fails as `AskError.ungrounded` at once,
    /// with coaching: no planner, no search and no second generation, so
    /// `SearchArguments`, `search(_:context:)` and `searchPlanInstructions`
    /// go unused.
    ///
    /// For a domain whose every question is a lookup or an action, so its
    /// tools ground every answer worth keeping.
    case toolCall
    /// Grounding is recorded, never required. Prose draws from the first
    /// token, no turn is asked again for want of it, no turn fails as
    /// `AskError.ungrounded`, and the deadline keeps a truncated answer by the
    /// same rule as a finished one, grounded or not. The answer records what
    /// grounded it, or that nothing did (`AskGrounding.nothing`).
    ///
    /// For a domain whose answers needn't rest on the reader's data, such as
    /// an assistant whose tools convert, look up the time or take actions, and
    /// whose model may answer "thanks" or "say that more simply" from the
    /// conversation alone.
    case notRequired
}
