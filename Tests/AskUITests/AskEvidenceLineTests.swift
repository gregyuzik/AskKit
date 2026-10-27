#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import FoundationModels
import Testing

@testable import AskUI

/// What the evidence line under an answer says, and whether it opens onto the
/// rows behind it (`AskEvidenceLine.Content`), as the thread row asks for it:
/// from the answer and its domain.
///
/// A unit test can draw the line but can't ask what its body chose to show,
/// so what is pinned here is the decision the body draws from. The line draws
/// nothing for a nil content, and a chevron only for content that opens onto
/// rows, and only where the host supplies a disclosure.
@Suite(.timeLimit(.minutes(1))) struct AskEvidenceLineTests {

    private static let three = UIRow.three
    private static let scope = "Vinyl Records"
    private static let worded = "From 3 status pages, read just now"

    private static func answer(
        matches: [UIRow] = three,
        grounding: AskGrounding? = .toolCall
    ) -> AskAnswer<UIRow> {
        AskAnswer(text: "Three of them.", matches: matches, grounding: grounding)
    }

    private static func content<Domain: AskDomain>(
        _ answer: AskAnswer<UIRow>, _ domain: Domain
    ) -> AskEvidenceLine.Content? where Domain.Row == UIRow {
        AskEvidenceLine.Content(answer: answer, domain: domain)
    }

    // MARK: - `.counted`, the default

    /// A domain that says nothing about the line gets AskKit's count, which
    /// opens onto the rows it counts.
    @Test func byDefaultTheLineCountsTheRowsBehindTheAnswer() throws {
        let line = try #require(Self.content(Self.answer(), PlainDomain()))
        #expect(line == .counted(3, scope: nil))
        #expect(line.opensOntoRows)
    }

    /// The domain's scope rides on the count, as it always has.
    @Test func theCountNamesTheDomainsScope() {
        let domain = WordingDomain(presentation: .counted, scope: Self.scope)
        #expect(Self.content(Self.answer(), domain) == .counted(3, scope: Self.scope))
    }

    /// Grounded by a tool that read no rows, such as a clock: nothing to
    /// count, so no line. The ungrounded line is for an answer nothing
    /// grounded, and this one was.
    @Test func aGroundedAnswerThatReadNoRowsHasNoLine() {
        for grounding: AskGrounding in [.toolCall, .appRetrieved, .followUp] {
            #expect(Self.content(Self.answer(matches: [], grounding: grounding), PlainDomain()) == nil, "\(grounding)")
        }
    }

    /// Whatever grounded it, an answer with rows behind it is counted.
    @Test func everyGroundingButNoneIsCounted() {
        for grounding: AskGrounding in [.toolCall, .appRetrieved, .followUp] {
            #expect(Self.content(Self.answer(grounding: grounding), PlainDomain()) == .counted(3, scope: nil), "\(grounding)")
        }
    }

    // MARK: - `.line`

    /// The domain's words replace the count, and the line still opens onto
    /// the rows behind the answer.
    @Test func aDomainsLineReplacesTheWordsAndKeepsTheExpansion() throws {
        let domain = WordingDomain(presentation: .line(Self.worded), scope: Self.scope)
        let line = try #require(Self.content(Self.answer(), domain))
        #expect(line == .worded(Self.worded, rowsBehind: 3))
        #expect(line.opensOntoRows)
    }

    /// With no rows behind the answer the domain's line still draws, as plain
    /// text: there is nothing for a chevron to open.
    @Test func aDomainsLineOverNoRowsIsPlainText() throws {
        let domain = WordingDomain(presentation: .line(Self.worded))
        let line = try #require(Self.content(Self.answer(matches: []), domain))
        #expect(line == .worded(Self.worded, rowsBehind: 0))
        #expect(!line.opensOntoRows)
    }

    /// A line with no words is no line, rather than an empty element that
    /// still takes the thread's spacing and VoiceOver's attention.
    @Test func anEmptyLineDrawsNothing() {
        for words in ["", " ", "\n"] {
            #expect(Self.content(Self.answer(), WordingDomain(presentation: .line(words))) == nil)
        }
    }

    // MARK: - `.hidden`

    /// No line, even with rows behind the answer.
    @Test func noneDrawsNothingEvenWithRowsBehindTheAnswer() {
        let domain = WordingDomain(presentation: .hidden, scope: Self.scope)
        #expect(Self.content(Self.answer(), domain) == nil)
    }

    // MARK: - An answer nothing grounded

    /// Under `.counted`, an answer nothing grounded says so, in place of a
    /// count, and opens onto nothing.
    @Test func anUngroundedAnswerSaysItIsNotFromTheAppsData() throws {
        let line = try #require(Self.content(Self.answer(matches: [], grounding: AskGrounding.nothing), PlainDomain()))
        #expect(line == .ungrounded)
        #expect(!line.opensOntoRows)
    }

    /// An ungrounded follow-up under `.notRequired` carries the thread's rows
    /// as its matches. They didn't ground it, so they aren't counted, and the
    /// line doesn't open onto them, disclosure or not.
    @Test func anUngroundedAnswerWithTheThreadsRowsIsStillNotCounted() throws {
        let line = try #require(Self.content(Self.answer(grounding: AskGrounding.nothing), PlainDomain()))
        #expect(line == .ungrounded)
        #expect(!line.opensOntoRows)
    }

    /// The domain's own words win over the ungrounded line.
    @Test func aDomainsLineWinsOverTheUngroundedLine() {
        let domain = WordingDomain(presentation: .line(Self.worded))
        #expect(Self.content(Self.answer(matches: [], grounding: AskGrounding.nothing), domain) == .worded(Self.worded, rowsBehind: 0))
    }

    /// And so does its choice of no line at all.
    @Test func aDomainsNoneWinsOverTheUngroundedLine() {
        let domain = WordingDomain(presentation: .hidden)
        #expect(Self.content(Self.answer(matches: [], grounding: AskGrounding.nothing), domain) == nil)
        #expect(Self.content(Self.answer(grounding: AskGrounding.nothing), domain) == nil)
    }

    // MARK: - Nobody judged it

    /// No grounding recorded (a deterministic answer, a stopped turn, a
    /// thread saved before answers recorded it) is not a claim that nothing
    /// grounded the answer: the line counts what it has, and draws nothing
    /// without rows.
    @Test func anAnswerWithNoGroundingRecordedIsCountedAsBefore() throws {
        let counted = try #require(Self.content(Self.answer(grounding: nil), PlainDomain()))
        #expect(counted == .counted(3, scope: nil))
        #expect(counted.opensOntoRows)
        #expect(Self.content(Self.answer(matches: [], grounding: nil), PlainDomain()) == nil)
    }

    // MARK: - The decision itself

    /// The scope is asked only for the line that names it.
    @Test func theScopeIsAskedOnlyForACountedLine() {
        var asked = 0
        func scope() -> String? {
            asked += 1
            return Self.scope
        }
        _ = AskEvidenceLine.Content(presentation: .line(Self.worded), grounding: .toolCall, rowsBehind: 3, scope: scope())
        _ = AskEvidenceLine.Content(presentation: .hidden, grounding: .toolCall, rowsBehind: 3, scope: scope())
        _ = AskEvidenceLine.Content(presentation: .counted, grounding: AskGrounding.nothing, rowsBehind: 3, scope: scope())
        _ = AskEvidenceLine.Content(presentation: .counted, grounding: .toolCall, rowsBehind: 0, scope: scope())
        #expect(asked == 0)
        #expect(AskEvidenceLine.Content(presentation: .counted, grounding: .toolCall, rowsBehind: 3, scope: scope()) == .counted(3, scope: Self.scope))
        #expect(asked == 1)
    }
}

// MARK: - Domains

nonisolated private let evidenceBrand = AskBrand(
    title: "Ask Test", shortLabel: "Ask", appDirectory: "AskKitUITests",
    logSubsystem: "AskKit.uitests", help: "help",
    firstScreenHeadline: "headline", firstScreenSentence: "sentence",
    disclosureSentence: "disclosure", scopeCaveat: "caveat"
)

/// A domain that says nothing about the evidence line: the defaults.
private nonisolated struct PlainDomain: AskDomain {
    typealias Row = UIRow

    var brand: AskBrand { evidenceBrand }
    func makeTools(_ context: AskToolContext<UIRow>) -> [any Tool] { [] }
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }
}

/// A domain that words the line its own way, and may name a scope.
private nonisolated struct WordingDomain: AskDomain {
    typealias Row = UIRow

    var presentation: AskEvidencePresentation
    var scope: String?

    var brand: AskBrand { evidenceBrand }
    func makeTools(_ context: AskToolContext<UIRow>) -> [any Tool] { [] }
    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "" }

    func evidence(for answer: AskAnswer<UIRow>) -> AskEvidencePresentation { presentation }
    func evidenceScope(from answer: AskAnswer<UIRow>) -> String? { scope }
}

#endif
