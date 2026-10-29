#if canImport(FoundationModels) && !os(tvOS)

import Foundation

/// One question to put through the real engine, with what a good answer looks
/// like.
///
/// Expectations are shapes, not prose: whether the turn read anything, what kind
/// of question it decided this was, whether it showed tiles, whether it offered
/// to do something, whether something grounded it, whether it named something
/// it never read. Prose is not
/// asserted: a model writes it differently every time, and pinning it would
/// make the harness measure the seed.
///
/// The kinds, the tiles, the card and the grounding are held against the
/// answer: whatever it misses is on `AskOutcome.misses` and costs the scenario
/// `isGood`. The titles
/// are read for `named` and `invented`, and only an invented one costs it.
nonisolated public struct AskScenario: Sendable, Identifiable {
    /// The scenario's name in the table.
    public let id: String
    /// The question, asked as a reader would type it.
    public let question: String
    /// Where the question is asked from, as the app passes it to
    /// `prefill(_:scope:send:)`: a shelf's id, say. The domain's
    /// `scopeLine(for:)` turns it into the prompt's line. Nil, the default,
    /// asks the question as typed anywhere else.
    ///
    /// A scenario for a question that only makes sense with its scope has to
    /// carry it. A shelf's "What should I play?" names no shelf, and asked
    /// unscoped it measures a question the app never sends.
    public let scope: String?
    /// The question kinds a good answer might claim. An answer claiming
    /// another, or none, misses. Empty means any, and is all a domain whose
    /// reply shape is `.prose` asks: every answer its model writes is
    /// `other`, and shows no tiles.
    public let expectedKinds: [AskQuestionKind]
    /// Titles the answer ought to name, if it is any good.
    public let expectedTitles: [String]
    /// A count or a total: tiles would be wrong, and an answer showing any
    /// misses.
    public let expectsNoTiles: Bool
    /// Whether a good answer offers to do something, which the reader then
    /// confirms on a card: `true` for a request to act, `false` for a question
    /// an offer would be wrong for, nil, the default, for neither.
    ///
    /// Optional because `false` has to mean "offers nothing". With a default of
    /// `false` standing for "not asked", a scenario that spelled out `false`
    /// would read as the opposite of what it held.
    public let expectsProposal: Bool?
    /// Whether a good answer rests on something (`AskAnswer.grounding`):
    /// `true` for a question a tool, the app's search or the thread's rows
    /// should ground, which an answer that recorded `AskGrounding.nothing`, or
    /// nothing at all, misses; `false` for one that should be answered from
    /// the conversation alone, such as "thanks" to a domain whose policy keeps
    /// such answers (`AskGroundingPolicy.notRequired`), which an answer
    /// something grounded misses. Nil, the default, for neither.
    ///
    /// Optional for `expectsProposal`'s reason.
    public let expectsGrounding: Bool?

    /// A scenario. Every expectation left out asks for nothing.
    public init(
        id: String,
        question: String,
        scope: String? = nil,
        expectedKinds: [AskQuestionKind] = [],
        expectedTitles: [String] = [],
        expectsNoTiles: Bool = false,
        expectsProposal: Bool? = nil,
        expectsGrounding: Bool? = nil
    ) {
        self.id = id
        self.question = question
        self.scope = scope
        self.expectedKinds = expectedKinds
        self.expectedTitles = expectedTitles
        self.expectsNoTiles = expectsNoTiles
        self.expectsProposal = expectsProposal
        self.expectsGrounding = expectsGrounding
    }
}

/// What one scenario actually did.
nonisolated public struct AskOutcome: Sendable, Identifiable {
    /// The scenario's id.
    public var id: String
    /// The tier the turn ended on: after a hand-down, the one that took over.
    /// Nil when no tier was chosen.
    public var tier: AskTier?
    /// Tool calls in the generation that answered, as the engine counts them
    /// for the grounding rule. A grounded retry's answer was handed the app's
    /// rows and normally reads 0; with `restarts`, that's the sign a tier
    /// skipped its tools.
    public var toolCalls = 0
    /// How many rows stood behind the answer (`AskAnswer.matches`).
    public var rowsRead = 0
    /// How many tiles the answer showed.
    public var tiles = 0
    /// How long the turn took, from the question to its end. The table
    /// prints it in whole milliseconds.
    public var duration: Duration = .zero
    /// The question kind the answer claimed, in the domain's vocabulary.
    public var questionKind: AskQuestionKind?
    /// The turn threw away what it had and started over: the grounded retry,
    /// or a hand-down. (A follow-up that outgrew its window starts over too,
    /// and no scenario is a follow-up.)
    public var restarts = 0
    /// What the turn failed with: the `AskError`, a tag for any other error,
    /// or no answer for a turn whose stream ended with neither, as one let go
    /// before its answer does. Nil when it answered. Whether it failed as
    /// ungrounded is read off it (`Failure.isUngrounded`).
    public var failure: Failure?
    /// The expected titles the answer named.
    public var named: [String] = []
    /// A title from **this scenario's `expectedTitles`** that the prose names
    /// and the turn never read: an invention. The number that matters most.
    ///
    /// Scoped to the listed titles, which is narrower than it sounds: a title
    /// conjured out of nothing that the scenario did not happen to list is
    /// invisible here. Catching those needs a corpus of real titles the eval
    /// has no access to.
    public var invented: [String] = []
    /// The answer offered to do something: it carried a proposal, which a
    /// card would have asked the reader to confirm.
    public var proposed = false
    /// What grounded the answer (`AskAnswer.grounding`). Nil when the turn
    /// failed, and when the answer recorded nothing, as one the domain gave
    /// without a model does.
    public var grounding: AskGrounding?
    /// Where the answer differed from its scenario's shape: a kind outside
    /// `expectedKinds`, tiles under `expectsNoTiles`, a card where
    /// `expectsProposal` asks for none or none where it asks for one, and
    /// grounding where `expectsGrounding` asks for none or none where it asks
    /// for some. Only an answer is held to them: a turn that failed shows its
    /// failure, and no misses.
    public var misses: [Miss] = []
    /// The answer's prose, or empty when the turn failed.
    public var text = ""

    /// An outcome for scenario `id`, before the turn has run.
    public init(id: String) { self.id = id }

    /// Whether the turn answered, invented nothing and missed nothing. An
    /// answer nothing grounded, which only a domain whose policy keeps such
    /// answers is given, is good unless its scenario says otherwise
    /// (`AskScenario.expectsGrounding`).
    public var isGood: Bool {
        failure == nil && invented.isEmpty && misses.isEmpty
    }

    /// The table's last column: the failure, else what the answer invented
    /// and missed, else ok.
    var verdict: String {
        if let failure { return failure.description }
        var faults = invented.isEmpty ? [] : ["INVENTED \(invented.joined(separator: ", "))"]
        faults += misses.map(\.line)
        return faults.isEmpty ? "ok" : faults.joined(separator: "; ")
    }

    /// What a turn failed with: one value, so a failure can't be ungrounded
    /// without saying so, nor say so without having failed.
    nonisolated public enum Failure: Sendable, Equatable, CustomStringConvertible {
        /// The engine's error.
        case error(AskError)
        /// Any other error, by its tag (`AskTriage.tag(for:)`), never its
        /// description.
        case untyped(tag: String)
        /// The stream ended with neither an answer nor an error, as one let go
        /// before its answer does.
        case noAnswer

        /// The turn failed as ungrounded.
        public var isUngrounded: Bool {
            if case .error(.ungrounded) = self { true } else { false }
        }

        /// The failure as the table spells it: the error as Swift describes
        /// it, the tag, or "no answer".
        public var description: String {
            switch self {
            case .error(let error): String(describing: error)
            case .untyped(let tag): tag
            case .noAnswer: "no answer"
            }
        }
    }

    /// One way an answer differed from its scenario's shape.
    nonisolated public enum Miss: Sendable, Equatable {
        /// A kind the scenario did not list, or nil when the answer claimed
        /// none.
        case kind(expected: [AskQuestionKind], got: AskQuestionKind?)
        /// Tiles, this many, where the scenario expects none.
        case tiles(Int)
        /// No card, where the scenario expects one.
        case noProposal
        /// A card, where the scenario expects none.
        case unexpectedProposal
        /// Nothing grounded the answer, or it recorded nothing, where the
        /// scenario expects something to.
        case noGrounding
        /// This grounded the answer, where the scenario expects nothing to.
        case unexpectedGrounding(AskGrounding)

        /// The miss as the table spells it.
        public var line: String {
            switch self {
            case .kind(let expected, let got):
                return "KIND \(got?.rawValue ?? "none"), expected \(expected.map(\.rawValue).joined(separator: " or "))"
            case .tiles(let count):
                return "\(count) TILES, expected none"
            case .noProposal:
                return "NO CARD, expected one"
            case .unexpectedProposal:
                return "CARD, expected none"
            case .noGrounding:
                return "NOT GROUNDED, expected grounding"
            case .unexpectedGrounding(let grounding):
                return "GROUNDED by \(grounding.rawValue), expected nothing"
            }
        }
    }
}

/// Runs a domain's scenarios through a real engine and reports what each one
/// did.
///
/// **Compiled into every build, gated at runtime.** Not `#if DEBUG`: a
/// TestFlight build is Release, and a signed build on a device is the only
/// place Private Cloud Compute can be measured, so the diagnostics row that
/// runs this has to work there. The row is what a runtime check hides
/// (`AskDiagnostics`), not this code.
nonisolated public struct AskEval<Domain: AskDomain>: Sendable {
    private let engine: AskEngine<Domain>

    /// An evaluation of `domain` on the tiers `seam` serves, on an engine of
    /// its own, built here, logging to `log` as `AskEngine.init(domain:seam:log:)`
    /// does.
    ///
    /// **Never the thread's engine.** Every scenario starts by resetting the
    /// engine, and on the thread's engine that is New Chat: the reader's
    /// conversation and warm session would go, and the store's copy of
    /// whether a conversation is kept would go stale. So the evaluation takes
    /// no engine, and builds its own.
    ///
    /// The domain and the seam can be the thread's, so the evaluation answers
    /// on the app's tiers and generation gate. Whether a conversation is kept
    /// is each engine's own (`AskEngine.hasKeptConversation`), so the
    /// evaluation's resets never hide the thread's follow-up chips.
    public init(domain: Domain, seam: any AskModelSeam, log: (any AskLogSink)? = nil) {
        engine = AskEngine(domain: domain, seam: seam, log: log)
    }

    /// Run one scenario through the real engine on whatever tier serves.
    public func run(_ scenario: AskScenario) async -> AskOutcome {
        var outcome = AskOutcome(id: scenario.id)
        // A first question every time. A typed question continues whatever
        // conversation the engine kept, so without the reset every scenario
        // after the first would run as a follow-up of the one before it.
        await engine.reset()
        let started = ContinuousClock().now
        var answered = false
        do {
            // Typed, with the scope the app would send it with: a shelf's
            // question is left in the composer, and the reader sends it.
            for try await event in engine.ask(scenario.question, origin: .typed, images: [], scope: scenario.scope) {
                switch event {
                case .tier(let tier):
                    outcome.tier = tier
                case .restarted:
                    outcome.restarts += 1
                case .answer(let answer):
                    answered = true
                    outcome.text = answer.text
                    outcome.rowsRead = answer.matches.count
                    outcome.tiles = answer.tiles.count
                    outcome.questionKind = answer.questionKind
                    let titles = answer.matches.map(\.displayTitle)
                    outcome.named = scenario.expectedTitles.filter {
                        AskAnswer<Domain.Row>.mention(of: $0, in: answer.text) != nil
                    }
                    // A title the prose names that the turn never read. The
                    // tiles cannot invent — they resolve against rows — so this
                    // is a scan of the prose against everything read. Read
                    // means the same title to `AskAnswer.titleEquals`, which
                    // is blind to case, diacritics and typographic
                    // punctuation, so a curly apostrophe or a capital is not
                    // an invention; a title only inside one it read still is.
                    outcome.invented = scenario.expectedTitles
                        .filter { expected in
                            !titles.contains { AskAnswer<Domain.Row>.titleEquals($0, name: expected) }
                        }
                        .filter { AskAnswer<Domain.Row>.mention(of: $0, in: answer.text) != nil }
                    outcome.proposed = answer.proposal != nil
                    outcome.grounding = answer.grounding
                    outcome.misses = Self.misses(of: outcome, against: scenario)
                case .partial, .rowsRead, .summarized, .refining, .activity, .activityEnded:
                    break
                }
            }
        } catch let error as AskError {
            outcome.failure = .error(error)
        } catch {
            outcome.failure = .untyped(tag: AskTriage.tag(for: error))
        }
        // A stream that ends with neither an answer nor an error, as one let
        // go before its answer does, answered nothing, and is no "ok".
        if !answered, outcome.failure == nil { outcome.failure = .noAnswer }
        outcome.duration = ContinuousClock().now - started
        // The engine's count, not the tools' activity: a tool says what it is
        // doing however its domain likes, and counting `.searching` would read
        // 0 for a domain whose tools report `.custom`.
        if let stats = await engine.lastTurnStats { outcome.toolCalls = stats.toolCalls }
        return outcome
    }

    /// Where an answer differs from its scenario's shape. Each check runs only
    /// when the scenario asks for it, so a scenario that asks for none misses
    /// nothing.
    private static func misses(of outcome: AskOutcome, against scenario: AskScenario) -> [AskOutcome.Miss] {
        var misses: [AskOutcome.Miss] = []
        if !scenario.expectedKinds.isEmpty, !scenario.expectedKinds.contains(where: { $0 == outcome.questionKind }) {
            misses.append(.kind(expected: scenario.expectedKinds, got: outcome.questionKind))
        }
        if scenario.expectsNoTiles, outcome.tiles > 0 {
            misses.append(.tiles(outcome.tiles))
        }
        if let expectsProposal = scenario.expectsProposal, expectsProposal != outcome.proposed {
            misses.append(expectsProposal ? .noProposal : .unexpectedProposal)
        }
        // What really grounded it: nil for an answer that recorded nothing and
        // for one nothing grounded alike.
        let grounding = outcome.grounding.flatMap { $0 == .nothing ? nil : $0 }
        if let expectsGrounding = scenario.expectsGrounding, expectsGrounding != (grounding != nil) {
            misses.append(grounding.map(AskOutcome.Miss.unexpectedGrounding) ?? .noGrounding)
        }
        return misses
    }

    /// Run every scenario in order, never in parallel: one turn at a time is
    /// the engine's own contract, and a parallel run would measure the
    /// serialization rather than the model.
    public func run(_ scenarios: [AskScenario]) async -> [AskOutcome] {
        var outcomes: [AskOutcome] = []
        for scenario in scenarios {
            outcomes.append(await run(scenario))
        }
        return outcomes
    }

    /// The outcomes as a Markdown table, ending with "N/M grounded, clean and
    /// as expected.": for a log, or to share from the diagnostics row.
    public static func table(_ outcomes: [AskOutcome]) -> String {
        var lines = ["| scenario | tier | tools | restarts | rows | tiles | kind | card | ms | verdict |",
                     "|---|---|---|---|---|---|---|---|---|---|"]
        for outcome in outcomes {
            lines.append(
                "| \(outcome.id) | \(outcome.tier?.rawValue ?? "–") | \(outcome.toolCalls) | \(outcome.restarts) "
                + "| \(outcome.rowsRead) | \(outcome.tiles) | \(outcome.questionKind?.rawValue ?? "–") "
                + "| \(outcome.proposed ? "yes" : "–") | \(outcome.duration.wholeMilliseconds) | \(outcome.verdict) |"
            )
        }
        let good = outcomes.filter(\.isGood).count
        lines.append("")
        lines.append("\(good)/\(outcomes.count) grounded, clean and as expected.")
        return lines.joined(separator: "\n")
    }
}

#endif
