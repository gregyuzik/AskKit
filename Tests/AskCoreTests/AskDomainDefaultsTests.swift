import Foundation
import Testing

// SPI for `AskPrompt.promptText`, to read the prompt a bare domain opens.
@_spi(AskKitInternal) @testable import AskCore

#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels

/// The `AskDomain` defaults every host inherits without writing a line.
///
/// Run here on a domain that overrides none of them, because `FakeDomain`
/// overrides several: a changed default moves every host's contract at once,
/// and only a domain that leaves the defaults alone turns the suite red.
@Suite(.timeLimit(.minutes(1))) struct AskDomainDefaultsTests {

    /// A domain overriding nothing that has a default.
    private struct BareDomain: AskDomain {
        typealias Row = FakeRow
        typealias SearchArguments = FakeSearchArguments

        var brand: AskBrand {
            AskBrand(
                title: "Bare", appDirectory: "AskKitTests",
                logSubsystem: "AskKit.tests", help: "help",
                firstScreenHeadline: "headline", firstScreenSentence: "sentence",
                nothingToAskCopy: "nothing", disclosureSentence: "disclosure",
                scopeCaveat: "caveat"
            )
        }
        func overview() async -> AskOverview { .empty }
        func makeTools(_ context: AskToolContext<FakeRow>) -> [any Tool] { [] }
        func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
        func search(_ arguments: FakeSearchArguments, context: AskToolContext<FakeRow>) async throws -> String { "" }
    }

    @Test func aBareDomainPutsNothingOfItsOwnAheadOfTheLines() {
        #expect(BareDomain().promptPrefix.isEmpty)
        #expect(AskPrompt.promptText(prefix: BareDomain().promptPrefix, lines: ["One row."], question: "how many?")
                == "One row.\n<user_request>how many?</user_request>")
    }

    @Test func aBareDomainsPlannerIsAskedForTheSearchAndTheToolGoesUnnamed() {
        // The planner's session has no tools, so instructions naming one ask
        // for a call it can't make.
        let instructions = BareDomain().searchPlanInstructions
        #expect(!instructions.isEmpty)
        #expect(!instructions.localizedCaseInsensitiveContains("tool"))
    }

    @Test func aBareDomainOffersNoStarters() {
        #expect(BareDomain().starters(overview: .empty, window: 8).isEmpty)
    }

    @Test func aBareDomainsReferentIsWhatTheAnswerShowed() {
        let answer = AskAnswer(
            text: "Tusk is louder than Rumours.",
            matches: [FakeRow("Rumours"), FakeRow("Tusk")],
            tiles: [FakeRow("Rumours")]
        )
        #expect(BareDomain().referent(from: answer) == ["Rumours"])
    }

    @Test func aBareDomainsReferentWithNoTilesIsWhatTheProseNamed() {
        // A count or a yes-or-no shows no tiles, and "which of those" still
        // means the rows it talked about, in the order it named them.
        let answer = AskAnswer(text: "Tusk, then Rumours.", matches: [FakeRow("Rumours"), FakeRow("Tusk")])
        #expect(BareDomain().referent(from: answer) == ["Tusk", "Rumours"])
    }

    @Test func theRowLimitIsHigherOnPrivateCloudThanOnDevice() {
        let domain = BareDomain()
        let cloud = domain.rowLimit(for: .privateCloud)
        let device = domain.rowLimit(for: .onDevice)
        #expect(cloud > 0)
        #expect(device > 0)
        #expect(cloud >= device, "the larger context should not read fewer rows")
    }

    @Test func theTurnCeilingIsPositiveOnBothTiers() {
        let domain = BareDomain()
        #expect(domain.maxTurns(for: .privateCloud) > 0)
        #expect(domain.maxTurns(for: .onDevice) > 0)
    }

    @Test func aBareDomainAnswersNothingDeterministicallyAndSaysSo() {
        // The pairing `AskEngine` checks at construction: a domain that has
        // not implemented the hook must not claim it has.
        let domain = BareDomain()
        #expect(!domain.implementsDeterministicAnswer)
        #expect(!domain.firstScreenPolicy.answersWithoutModel)
    }

    @Test func theDefaultQuestionKindsAreAllInTheSchemaVocabulary() {
        #expect(AskQuestionKind.unrecognized(in: BareDomain().questionKinds).isEmpty)
    }

    @Test func aBareDomainSuppliesNoWaitPhraseOfItsOwn() {
        #expect(BareDomain().phrase(for: .searching(scope: nil)) == nil)
    }

    @Test func aBareDomainOffersAnotherPickOnNothing() {
        // A domain that lists no `superlative` gets its superlatives as picks,
        // and only a domain can tell which is which — so nothing is rerollable
        // until one says so.
        let domain = BareDomain()
        #expect(domain.rerollableKinds.isEmpty)
        let kinds: [AskQuestionKind?] = [AskQuestionKind.pick, AskQuestionKind.suggestion, AskQuestionKind.lookup, nil]
        for kind in kinds {
            #expect(!domain.isRerollable(Self.answer(kind), question: "q"), "\(kind?.rawValue ?? "no kind")")
        }
    }

    @Test func theDefaultRerollReadsTheKindsADomainLists() {
        var domain = FakeDomain()
        domain.rerollKinds = [AskQuestionKind.suggestion]
        #expect(domain.isRerollable(Self.answer(AskQuestionKind.suggestion), question: "q"))
        #expect(!domain.isRerollable(Self.answer(AskQuestionKind.pick), question: "q"))
        #expect(!domain.isRerollable(Self.answer(nil), question: "q"))
    }

    @Test func aBareDomainTakesNoPhotosAndDrawsNoThumbnail() async {
        let domain = BareDomain()
        #expect(!domain.acceptsPhotoAttachments)
        #expect(await domain.photoThumbnail(for: AskQuestionPhoto(label: "Blue record sleeve", reference: "asset-1")) == nil)
    }

    @Test func aBareDomainWritesNoLineForAScope() {
        #expect(BareDomain().scopeLine(for: "records") == nil)
    }

    /// AskKit's own count under every answer, whatever grounded it, and no
    /// scope for it to name.
    @Test func aBareDomainLeavesTheEvidenceLineCountedAndUnscoped() {
        let groundings: [AskGrounding?] = [nil, .toolCall, .appRetrieved, .followUp, AskGrounding.nothing]
        for grounding in groundings {
            let answer = AskAnswer(text: "Two.", matches: [FakeRow("Rumours"), FakeRow("Tusk")], grounding: grounding)
            #expect(BareDomain().evidence(for: answer) == .counted, "\(String(describing: grounding))")
            #expect(BareDomain().evidenceScope(from: answer) == nil)
        }
    }

    // MARK: - A superlative

    @Test func aSuperlativeIsAPickForADomainThatListsPickAlone() {
        // A domain that lists `pick` and not `superlative` never asked for the
        // difference, so it gets "my oldest record" as a pick rather than as
        // `other`.
        var domain = FakeDomain()
        domain.kinds = [AskQuestionKind.pick, AskQuestionKind.count]
        #expect(domain.normalizedKind(AskQuestionKind.superlative.rawValue) == AskQuestionKind.pick)
        #expect(domain.normalizedKind(AskQuestionKind.pick.rawValue) == AskQuestionKind.pick)
    }

    @Test func aSuperlativeStaysOneForADomainThatListsIt() {
        var domain = FakeDomain()
        domain.kinds = [AskQuestionKind.pick, AskQuestionKind.superlative]
        #expect(domain.normalizedKind(AskQuestionKind.superlative.rawValue) == AskQuestionKind.superlative)
        #expect(domain.normalizedKind(AskQuestionKind.pick.rawValue) == AskQuestionKind.pick)
    }

    @Test func aSuperlativeIsOtherForADomainThatListsNeither() {
        // With no `pick` to stand in for it, a superlative is `other`, as any
        // kind the domain doesn't list is.
        var domain = FakeDomain()
        domain.kinds = [AskQuestionKind.lookup, AskQuestionKind.count]
        #expect(domain.normalizedKind(AskQuestionKind.superlative.rawValue) == AskQuestionKind.other)
        #expect(domain.normalizedKind(AskQuestionKind.pick.rawValue) == AskQuestionKind.other)
    }

    @Test func aDomainNamingNoKindsGetsSuperlativesAsPicks() {
        // The default list has `pick` and not `superlative`, so a domain that
        // names no kinds gets its superlatives as picks.
        #expect(AskQuestionKind.all.contains(AskQuestionKind.superlative))
        #expect(!AskQuestionKind.default.contains(AskQuestionKind.superlative))
        #expect(BareDomain().normalizedKind(AskQuestionKind.superlative.rawValue) == AskQuestionKind.pick)
    }

    private static func answer(_ kind: AskQuestionKind?) -> AskAnswer<FakeRow> {
        AskAnswer(text: "x", matches: [FakeRow("Rumours")], tiles: [FakeRow("Rumours")], questionKind: kind)
    }
}

// MARK: - A domain without rows

extension AskDomainDefaultsTests {
    /// A domain whose tools read no rows, with nothing but the three members
    /// left without a default once it names neither associated type.
    private struct BareRowlessDomain: AskDomain {
        var brand: AskBrand {
            AskBrand(
                title: "Bare", appDirectory: "AskKitTests",
                logSubsystem: "AskKit.tests", help: "help",
                firstScreenHeadline: "headline", firstScreenSentence: "sentence",
                disclosureSentence: "disclosure", scopeCaveat: "caveat"
            )
        }
        func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }
        func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
    }

    @Test func aDomainNamingNeitherTypeGetsTheStandIns() {
        #expect(BareRowlessDomain.Row.self == AskNoRow.self)
        #expect(BareRowlessDomain.SearchArguments.self == AskNoSearchArguments.self)
    }

    /// Asked as the engine asks: through the protocol, from generic code.
    @Test func aRowlessDomainsOverviewIsEmpty() async {
        #expect(await Self.overviewAsked(of: BareRowlessDomain()) == .empty)
    }

    /// The grounded retry's search, asked as `plannedPrompt` asks it: it
    /// fails the turn as ungrounded, and records nothing on the way.
    @Test func aRowlessDomainsSearchFailsAsUngrounded() async {
        let collector = AskCollector<AskNoRow>()
        let context = AskToolContext(
            collector: collector, relay: AskActivityRelay(),
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        await #expect(throws: AskError.ungrounded) {
            try await Self.searchAsked(of: BareRowlessDomain(), context: context)
        }
        #expect(await collector.rows.isEmpty)
        #expect(await collector.toolCallCount == 0)
    }

    /// The defaults a rowless domain leaves alone are every other domain's:
    /// the ones it would want to change are its grounding policy, which
    /// stays `.retrieval`, and with it a first-screen policy of
    /// `.ownedLibrary`, until it names another, and its brand's copy, which
    /// it may leave out.
    @Test func aRowlessDomainKeepsTheOtherDefaults() {
        let domain = BareRowlessDomain()
        #expect(domain.grounding == .retrieval)
        #expect(domain.firstScreenPolicy == .ownedLibrary)
        #expect(domain.brand.nothingToAskCopy == nil)
        #expect(domain.referent(from: AskAnswer<AskNoRow>(text: "It is 14:05 in Lisbon.")).isEmpty)
        #expect(domain.evidence(for: AskAnswer<AskNoRow>(text: "It is 14:05 in Lisbon.")) == .counted)
    }

    @Test func aStandInRowIsNamedByItsID() throws {
        let row = AskNoRow(id: "Lisbon")
        #expect(row.displayTitle == "Lisbon")
        #expect(try JSONDecoder().decode(AskNoRow.self, from: JSONEncoder().encode(row)) == row)
    }

    /// The planner's answer, read as a session reads one: an empty struct is
    /// a schema with no properties, and content with none makes one.
    @Test func noSearchArgumentsAreMadeFromNoContent() throws {
        _ = AskNoSearchArguments.generationSchema
        _ = try AskNoSearchArguments(GeneratedContent(properties: [:]))
    }

    private static func overviewAsked<Domain: AskDomain>(of domain: Domain) async -> AskOverview {
        await domain.overview()
    }

    private static func searchAsked<Domain: AskDomain>(
        of domain: Domain, context: AskToolContext<Domain.Row>
    ) async throws -> String where Domain.SearchArguments == AskNoSearchArguments {
        try await domain.search(AskNoSearchArguments(), context: context)
    }
}

// MARK: - The grounding policy

extension AskDomainDefaultsTests {
    /// A rowless domain naming its grounding policy and nothing else, so its
    /// first-screen policy is the default's to derive.
    private struct GroundingOnlyDomain: AskDomain {
        let grounding: AskGroundingPolicy

        var brand: AskBrand {
            AskBrand(
                title: "Bare", appDirectory: "AskKitTests",
                logSubsystem: "AskKit.tests", help: "help",
                firstScreenHeadline: "headline", firstScreenSentence: "sentence",
                disclosureSentence: "disclosure", scopeCaveat: "caveat"
            )
        }
        func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }
        func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
    }

    /// Every domain written before the policy keeps today's grounding rule,
    /// and the first screen that goes with it.
    @Test func aBareDomainRetrievesAndOwnsItsLibrary() {
        #expect(BareDomain().grounding == .retrieval)
        #expect(BareDomain().firstScreenPolicy == .ownedLibrary)
    }

    /// The default first screen follows the grounding: only a domain that
    /// retrieves reads an empty overview as nothing to ask about.
    @Test func theDefaultFirstScreenFollowsTheGroundingPolicy() {
        #expect(GroundingOnlyDomain(grounding: .retrieval).firstScreenPolicy == .ownedLibrary)
        #expect(GroundingOnlyDomain(grounding: .toolCall).firstScreenPolicy == .openSubject)
        #expect(GroundingOnlyDomain(grounding: .notRequired).firstScreenPolicy == .openSubject)
    }

    /// The policy's raw values are what a host's own settings or tests would
    /// write down, so they are pinned.
    @Test func thePoliciesRoundTripByName() {
        let policies: [AskGroundingPolicy] = [.retrieval, .toolCall, .notRequired]
        #expect(policies.map(\.rawValue) == ["retrieval", "toolCall", "notRequired"])
        #expect(policies.map(\.rawValue).compactMap(AskGroundingPolicy.init(rawValue:)) == policies)
    }
}

// MARK: - promptLines

extension AskDomainDefaultsTests {
    /// No lines from a domain that writes none, asked as the engine asks:
    /// through the protocol, from generic code.
    @Test func aDomainThatWritesNoLinesSendsNone() async {
        #expect(await Self.linesAsked(of: BareDomain(), question: "how many?").isEmpty)
    }

    private static func linesAsked<Domain: AskDomain>(of domain: Domain, question: String) async -> [String] {
        await domain.promptLines(question: question, overview: .empty)
    }
}

#endif
