import Foundation
import Synchronization
import Testing

@testable import AskCore

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)

/// `AskEval`: what a scenario's outcome records, what makes it good, and how
/// the table reports it, `invented`'s narrow scope included.
///
/// `invented`'s doc is what a developer trusts when deciding whether a change
/// is safe to land, and only a test keeps the doc and the code from drifting
/// apart.
@Suite(.timeLimit(.minutes(1))) struct AskEvalTests {

    private func makeEval(
        domain: FakeDomain = FakeDomain(),
        states: [AskTierState] = [.serving(.privateCloud), .serving(.onDevice)]
    ) -> (AskEval<FakeDomain>, FakeSeam) {
        let seam = FakeSeam(status: AskModelStatus(), states: states, bridge: domain.bridge)
        return (AskEval(domain: domain, seam: seam, log: FakeLogSink()), seam)
    }

    private func grounded(_ text: String, kind: AskQuestionKind? = nil, tiles: [String]? = nil) -> FakeSession.Script {
        FakeSession.Script(snapshots: [.answering(text, kind: kind, tiles: tiles)], toolCallsAfter: 1)
    }

    private func offering(_ text: String) -> FakeSession.Script {
        var script = grounded(text)
        script.proposal = AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent")
        return script
    }

    @Test func aGroundedAnswerRecordsItsTierAndNamedTitles() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own Rumours and Blue."))

        let outcome = await eval.run(
            AskScenario(id: "names", question: "what do I own?", expectedTitles: ["Rumours", "Blue"])
        )

        #expect(outcome.id == "names")
        #expect(outcome.tier == .privateCloud)
        #expect(outcome.failure == nil)
        #expect(Set(outcome.named) == ["Rumours", "Blue"])
        #expect(outcome.text == "You own Rumours and Blue.")
    }

    @Test func aTurnThatCannotBeServedRecordsTheFailureAndNotACrash() async {
        let (eval, _) = makeEval(states: [
            .down(.privateCloud, .notEntitled), .down(.onDevice, .appleIntelligenceOff)
        ])
        let outcome = await eval.run(AskScenario(id: "down", question: "q"))
        #expect(outcome.failure != nil)
        #expect(outcome.text.isEmpty)
    }

    /// A run let go before its answer ends its stream with neither an answer
    /// nor an error, and that is no answer: never "ok", and never good.
    @Test func aRunLetGoBeforeItsAnswerIsNoAnswer() async {
        let (eval, seam) = makeEval()
        let session = seam.session(for: .privateCloud)
        var script = grounded("Rumours.")
        script.holdsAfterSnapshots = true
        session.script(script)
        let run = Task { await eval.run(AskScenario(id: "let go", question: "q")) }
        await session.generationIsHeld()
        run.cancel()
        let outcome = await run.value
        session.releaseGeneration()
        #expect(outcome.failure != nil)
        #expect(!outcome.isGood)
        #expect(outcome.verdict != "ok")
    }

    @Test func inventedIsScopedToTheScenariosOwnExpectedTitles() async {
        // Not *any* title the answer named that the turn never read: the scan
        // runs over `scenario.expectedTitles` only, so an invention the
        // scenario did not happen to list — which is the invention most worth
        // catching — is invisible to the measure.
        //
        // Pinned rather than widened: catching an arbitrary invented title
        // needs a corpus of real titles the eval has no access to.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own Rumours and Nevermind."))

        let listed = await eval.run(
            AskScenario(id: "listed", question: "q", expectedTitles: ["Nevermind"])
        )
        #expect(listed.invented == ["Nevermind"],
                "a title the prose names that the turn never read, and the scenario listed it")

        let unlisted = await eval.run(AskScenario(id: "unlisted", question: "q"))
        #expect(unlisted.invented.isEmpty,
                "the same invention, unlisted — which is the limit of the measure")
    }

    @Test func aTitleTheTurnReadIsNotInventedWhateverItsCaseOrPunctuation() async {
        // The scenario's straight apostrophes against the catalogue's curly
        // ones, and lower case against title case: the same rows, read.
        let domain = FakeDomain()
        domain.bridge.rows.withLock { $0 = [FakeRow("Don’t Stop Believin’"), FakeRow("Abbey Road")] }
        let (eval, seam) = makeEval(domain: domain)
        seam.session(for: .privateCloud).script(grounded("Play Don’t Stop Believin’, then Abbey Road."))

        let outcome = await eval.run(AskScenario(
            id: "plain", question: "what should I play?", expectedTitles: ["Don't Stop Believin'", "abbey road"]
        ))

        #expect(Set(outcome.named) == ["Don't Stop Believin'", "abbey road"])
        #expect(outcome.invented.isEmpty)
        #expect(outcome.isGood)
    }

    @Test func aTitleOnlyInsideOneTheTurnReadIsStillInvented() async {
        // Membership is the same title, not a near one: reading Dune Messiah
        // is not reading Dune.
        let domain = FakeDomain()
        domain.bridge.rows.withLock { $0 = [FakeRow("Dune Messiah")] }
        let (eval, seam) = makeEval(domain: domain)
        seam.session(for: .privateCloud).script(grounded("Start with Dune."))

        let outcome = await eval.run(AskScenario(id: "near", question: "what should I read?", expectedTitles: ["Dune"]))

        #expect(outcome.invented == ["Dune"])
    }

    @Test func scenariosRunInOrderAndEachGetsItsOwnOutcome() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("An answer."))
        let outcomes = await eval.run([
            AskScenario(id: "one", question: "a"),
            AskScenario(id: "two", question: "b"),
            AskScenario(id: "three", question: "c")
        ])
        #expect(outcomes.map(\.id) == ["one", "two", "three"])
    }

    @Test func toolCallsAreTheEnginesCountWhateverTheToolReports() async {
        // The engine's count, not the `.searching` activity the tools report:
        // counted by activity, a tool that reports anything else would read 0
        // on a turn it had grounded.
        let (eval, seam) = makeEval()
        var custom = grounded("The Peregrine is on loan.")
        custom.toolActivity = .custom("checking-loans")
        seam.session(for: .privateCloud).script(custom)
        let reportsCustom = await eval.run(AskScenario(id: "custom", question: "is The Peregrine on loan?"))
        #expect(reportsCustom.toolCalls == 1)

        // A search that also says what it read is one call.
        var searching = grounded("You own Rumours.")
        searching.relayReports = [.reading(shown: 6, total: 6, scope: "records")]
        seam.session(for: .privateCloud).script(searching)
        let reportsSearch = await eval.run(AskScenario(id: "search", question: "what do I own?"))
        #expect(reportsSearch.toolCalls == 1)
    }

    @Test func aTierThatSkipsItsToolsReadsNoCallsAndOneRestart() async {
        // The grounded retry: the model answered without reading and the app
        // searched for it. The outcome must not credit the model with the
        // app's search, because this is the reading an instruction change
        // waits on.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(
            FakeSession.Script(snapshots: [.answering("You own Rumours.")], toolCallsAfter: 0)
        )
        let outcome = await eval.run(AskScenario(id: "skipped", question: "what do I own?"))
        #expect(outcome.failure == nil)
        #expect(outcome.restarts == 1)
        #expect(outcome.toolCalls == 0)
    }

    @Test func everyScenarioIsAFirstQuestion() async {
        // A typed question continues the conversation the engine kept, so on
        // one engine the second scenario would run as a follow-up of the
        // first. A follow-up does not send the schema again, which is what
        // this reads.
        let (eval, seam) = makeEval()
        let session = seam.session(for: .privateCloud)
        session.script(grounded("An answer."))
        _ = await eval.run([
            AskScenario(id: "one", question: "a"),
            AskScenario(id: "two", question: "b")
        ])
        #expect(session.schemaFlags.withLock { $0 } == [true, true])
    }

    @Test func anEvaluationLeavesTheThreadsFollowUpChipsAlone() async {
        // An evaluation runs on an engine of its own, but the seam, and the
        // mirror the screen reads, can be the thread's: the demo's are. Every
        // scenario resets its engine, and the thread's engine still keeps its
        // conversation, so the thread's follow-up chips stay.
        let domain = FakeDomain()
        let seam = FakeSeam(
            status: AskModelStatus(), states: [.serving(.privateCloud), .serving(.onDevice)], bridge: domain.bridge
        )
        let thread = AskEngine(domain: domain, seam: seam, log: FakeLogSink())
        let session = seam.session(for: .privateCloud)
        session.script(grounded("You own Rumours.", tiles: ["Rumours"]))
        _ = await record(thread.ask("what do I own?"))
        #expect(await thread.hasKeptConversation)

        let eval = AskEval(domain: domain, seam: seam, log: FakeLogSink())
        _ = await eval.run(AskScenario(id: "answers", question: "what do I own?"))
        session.script(FakeSession.Script(error: AskError.refused, toolCallsAfter: 1))
        _ = await eval.run(AskScenario(id: "fails", question: "q"))
        #expect(await thread.hasKeptConversation)
    }

    @Test func aScenarioThatReachesNoModelDoesNotReadTheOneBefore() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("An answer."))
        let first = await eval.run(AskScenario(id: "first", question: "a"))
        #expect(first.toolCalls == 1)

        seam.set([.down(.privateCloud, .notEntitled), .down(.onDevice, .appleIntelligenceOff)])
        let second = await eval.run(AskScenario(id: "second", question: "b"))
        #expect(second.failure != nil)
        #expect(second.toolCalls == 0)
    }

    // MARK: - Held to the scenario's shape

    @Test func aKindOutsideTheScenariosListIsAMiss() async {
        // A count answered as a lookup misses, even when it names nothing it
        // had not read.
        let (eval, seam) = makeEval()
        let counts = [AskQuestionKind.count]
        seam.session(for: .privateCloud).script(grounded("You own six.", kind: AskQuestionKind.lookup))
        let lookup = await eval.run(AskScenario(id: "lookup", question: "how many?", expectedKinds: counts))
        #expect(lookup.misses == [.kind(expected: counts, got: AskQuestionKind.lookup)])
        #expect(!lookup.isGood)

        // Claiming no kind at all misses a scenario that lists one.
        seam.session(for: .privateCloud).script(grounded("You own six."))
        let none = await eval.run(AskScenario(id: "none", question: "how many?", expectedKinds: counts))
        #expect(none.misses == [.kind(expected: counts, got: nil)])
        #expect(!none.isGood)
    }

    @Test func aListedKindIsNotAMiss() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own six.", kind: AskQuestionKind.count))
        let outcome = await eval.run(AskScenario(
            id: "count", question: "how many?", expectedKinds: [AskQuestionKind.lookup, AskQuestionKind.count]
        ))
        #expect(outcome.misses.isEmpty)
        #expect(outcome.isGood)
    }

    @Test func anEmptyKindListExpectsNothing() async {
        // A scenario that lists no kinds holds the answer to none, claimed or
        // not.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own six.", kind: AskQuestionKind.lookup))
        let claimed = await eval.run(AskScenario(id: "claimed", question: "how many?"))
        #expect(claimed.misses.isEmpty)
        #expect(claimed.isGood)

        seam.session(for: .privateCloud).script(grounded("You own six."))
        let unclaimed = await eval.run(AskScenario(id: "unclaimed", question: "how many?"))
        #expect(unclaimed.misses.isEmpty)
        #expect(unclaimed.isGood)
    }

    @Test func tilesUnderACountAreAMiss() async {
        // The kind is left unclaimed: a claimed count or total has its tiles
        // dropped before the eval sees them, so what this catches is an answer
        // that did not read the question as a count.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own Rumours.", tiles: ["Rumours"]))
        let count = await eval.run(AskScenario(id: "count", question: "how many?", expectsNoTiles: true))
        #expect(count.misses == [.tiles(1)])
        #expect(!count.isGood)

        let silent = await eval.run(AskScenario(id: "silent", question: "what do I own?"))
        #expect(silent.tiles == 1)
        #expect(silent.misses.isEmpty, "the same tiles, under a scenario that asks nothing of them")
    }

    @Test func aRequestToActWithNoCardIsAMiss() async {
        // A request to act answered in prose alone.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("The Peregrine is on your shelf."))
        let outcome = await eval.run(AskScenario(id: "lend", question: "lend The Peregrine to Sam", expectsProposal: true))
        #expect(!outcome.proposed)
        #expect(outcome.misses == [.noProposal])
        #expect(!outcome.isGood)
    }

    @Test func anUnaskedForCardIsAMiss() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(offering("The Peregrine is on your shelf. Lend it?"))
        let outcome = await eval.run(AskScenario(id: "shelf", question: "is The Peregrine on my shelf?", expectsProposal: false))
        #expect(outcome.proposed)
        #expect(outcome.misses == [.unexpectedProposal])
        #expect(!outcome.isGood)
    }

    @Test func aCardTheScenarioAskedForIsRecorded() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(offering("Mark The Peregrine as lent?"))
        let outcome = await eval.run(AskScenario(id: "lend", question: "lend The Peregrine to Sam", expectsProposal: true))
        #expect(outcome.proposed)
        #expect(outcome.misses.isEmpty)
        #expect(outcome.isGood)
    }

    @Test func aScenarioSilentOnCardsReadsOkEitherWay() async {
        // nil, the default, asks for neither.
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(offering("Mark The Peregrine as lent?"))
        let offered = await eval.run(AskScenario(id: "offered", question: "lend The Peregrine to Sam"))
        #expect(offered.proposed)
        #expect(offered.isGood)

        seam.session(for: .privateCloud).script(grounded("The Peregrine is on your shelf."))
        let plain = await eval.run(AskScenario(id: "plain", question: "is The Peregrine on my shelf?"))
        #expect(!plain.proposed)
        #expect(plain.isGood)
    }

    @Test func aFailedTurnHoldsNothingToItsExpectations() async {
        // The failure is the verdict. Misses on top of it would count one
        // turn's trouble twice, and read as though an answer had arrived.
        let (eval, _) = makeEval(states: [
            .down(.privateCloud, .notEntitled), .down(.onDevice, .appleIntelligenceOff)
        ])
        let outcome = await eval.run(AskScenario(
            id: "down", question: "lend The Peregrine to Sam",
            expectedKinds: [AskQuestionKind.count], expectsNoTiles: true, expectsProposal: true,
            expectsGrounding: true
        ))
        #expect(outcome.failure != nil)
        #expect(outcome.misses.isEmpty)
        #expect(outcome.grounding == nil)
        #expect(outcome.verdict == outcome.failure?.description)
    }

    // MARK: - What grounded the answer

    /// What grounded the answer is the outcome's, whatever the scenario asks.
    @Test func anOutcomeRecordsWhatGroundedItsAnswer() async {
        let (eval, seam) = makeEval()
        seam.session(for: .privateCloud).script(grounded("You own six."))
        let outcome = await eval.run(AskScenario(id: "count", question: "how many?"))
        #expect(outcome.grounding == .toolCall)
        #expect(outcome.isGood)
    }

    /// `true` asks for an answer something grounded: one that recorded
    /// nothing did, which only a domain that keeps such answers gives, misses.
    @Test func aScenarioExpectingGroundingMissesAnAnswerNothingGrounded() async {
        var domain = FakeDomain()
        domain.grounding = .notRequired
        let (eval, seam) = makeEval(domain: domain)
        seam.session(for: .privateCloud).script(
            FakeSession.Script(snapshots: [.answering("Paris is in France.")], toolCallsAfter: 0)
        )
        let outcome = await eval.run(AskScenario(id: "paris", question: "where is Paris?", expectsGrounding: true))
        #expect(outcome.failure == nil)
        #expect(outcome.grounding == AskGrounding.nothing)
        #expect(outcome.misses == [.noGrounding])
        #expect(!outcome.isGood)

        seam.session(for: .privateCloud).script(grounded("Paris is in France."))
        let met = await eval.run(AskScenario(id: "paris", question: "where is Paris?", expectsGrounding: true))
        #expect(met.grounding == .toolCall)
        #expect(met.misses.isEmpty)
        #expect(met.isGood)
    }

    /// An answer the domain gave without a model recorded nothing, which
    /// `true` misses as well.
    @Test func aScenarioExpectingGroundingMissesAnAnswerThatRecordedNothing() async {
        var domain = FakeDomain()
        domain.deterministic = AskAnswer(text: "Hello.")
        let (eval, _) = makeEval(domain: domain)
        let outcome = await eval.run(AskScenario(id: "hi", question: "hi", expectsGrounding: true))
        #expect(outcome.grounding == nil)
        #expect(outcome.misses == [.noGrounding])

        let unasked = await eval.run(AskScenario(id: "hi", question: "hi", expectsGrounding: false))
        #expect(unasked.misses.isEmpty)
    }

    /// `false` asks for an answer nothing grounded, such as "thanks" to a
    /// domain that keeps those: a tool called for it misses.
    @Test func aScenarioExpectingNoGroundingMissesAToolCall() async {
        var domain = FakeDomain()
        domain.grounding = .notRequired
        let (eval, seam) = makeEval(domain: domain)
        seam.session(for: .privateCloud).script(grounded("You're welcome."))
        let outcome = await eval.run(AskScenario(id: "thanks", question: "thanks", expectsGrounding: false))
        #expect(outcome.grounding == .toolCall)
        #expect(outcome.misses == [.unexpectedGrounding(.toolCall)])
        #expect(!outcome.isGood)

        seam.session(for: .privateCloud).script(
            FakeSession.Script(snapshots: [.answering("You're welcome.")], toolCallsAfter: 0)
        )
        let met = await eval.run(AskScenario(id: "thanks", question: "thanks", expectsGrounding: false))
        #expect(met.grounding == AskGrounding.nothing)
        #expect(met.misses.isEmpty)
        #expect(met.isGood)
    }

    /// nil, the default, asks for neither.
    @Test func aScenarioSilentOnGroundingReadsOkEitherWay() async {
        var domain = FakeDomain()
        domain.grounding = .notRequired
        let (eval, seam) = makeEval(domain: domain)
        seam.session(for: .privateCloud).script(
            FakeSession.Script(snapshots: [.answering("Paris is in France.")], toolCallsAfter: 0)
        )
        let bare = await eval.run(AskScenario(id: "bare", question: "where is Paris?"))
        #expect(bare.grounding == AskGrounding.nothing)
        #expect(bare.isGood)

        seam.session(for: .privateCloud).script(grounded("Paris is in France."))
        let looked = await eval.run(AskScenario(id: "looked", question: "where is Paris?"))
        #expect(looked.grounding == .toolCall)
        #expect(looked.isGood)
    }

    @Test func aGroundingMissIsSpelledInTheTable() {
        #expect(AskOutcome.Miss.noGrounding.line == "NOT GROUNDED, expected grounding")
        #expect(AskOutcome.Miss.unexpectedGrounding(.toolCall).line == "GROUNDED by tool call, expected nothing")
        var outcome = AskOutcome(id: "thanks")
        outcome.misses = [.unexpectedGrounding(.followUp)]
        #expect(AskEval<FakeDomain>.table([outcome]).contains("| GROUNDED by follow-up, expected nothing |"))
    }

    // MARK: - A scope

    @Test func aScenarioIsAskedWithItsScope() async throws {
        // Asked from a shelf, "What should I play?" names no shelf. Only the
        // scope's line says which, so a scenario that dropped it would measure
        // a question the app never sends.
        var domain = FakeDomain()
        domain.scopeLines = ["records": "Asked from the Records shelf."]
        let (eval, seam) = makeEval(domain: domain)
        let session = seam.session(for: .privateCloud)
        session.script(grounded("Rumours."))

        _ = await eval.run(AskScenario(id: "shelf", question: "What should I play?", scope: "records"))
        _ = await eval.run(AskScenario(id: "anywhere", question: "What should I play?"))

        let prompts = session.prompts.withLock { $0 }
        #expect(prompts.count == 2)
        #expect(try #require(prompts.first).contains("Asked from the Records shelf."))
        #expect(!(try #require(prompts.last).contains("Asked from the Records shelf.")),
                "the scope is the scenario's, not the engine's: the next scenario asks without it")
    }

    @Test func theTableRendersAHeaderAndOneRowPerOutcome() {
        let table = AskEval<FakeDomain>.table([
            AskOutcome(id: "one"),
            AskOutcome(id: "two")
        ])
        #expect(table.contains("| scenario |"))
        #expect(table.contains("one"))
        #expect(table.contains("two"))
    }

    @Test func theTableShowsRestartsTheCardAndTheMisses() {
        // The restarts column carries the reading an instruction change waits
        // on, a tier skipping its tools, which the tools column alone shows
        // only as a 0.
        var retried = AskOutcome(id: "retried")
        retried.restarts = 2
        retried.proposed = true
        retried.invented = ["Nevermind"]
        retried.misses = [.tiles(3), .unexpectedProposal]
        let lines = AskEval<FakeDomain>.table([retried, AskOutcome(id: "clean")])
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines[0] == "| scenario | tier | tools | restarts | rows | tiles | kind | card | ms | verdict |")
        let bars = { (line: String) in line.filter { $0 == "|" }.count }
        #expect(bars(lines[1]) == bars(lines[0]), "a separator short of the header breaks the markdown")
        #expect(lines[2] == "| retried | – | 0 | 2 | 0 | 0 | – | yes | 0 "
                + "| INVENTED Nevermind; 3 TILES, expected none; CARD, expected none |")
        #expect(lines[3] == "| clean | – | 0 | 0 | 0 | 0 | – | – | 0 | ok |")
        #expect(lines.last == "1/2 grounded, clean and as expected.")
    }
}

#endif
