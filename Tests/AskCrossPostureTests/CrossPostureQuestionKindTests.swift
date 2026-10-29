import AskCore
import Foundation
import Testing

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// Question kinds as a type, used as a host without the posture uses them: no
/// `swiftSettings`, so nonisolated by default (`CrossPostureTests` says why
/// the target has none). A member, a kind built from a word, its stored form,
/// the kinds that show no tiles, and a domain that lists its own.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureQuestionKindTests {

    /// The type's members and conformances, off any actor: what a host's
    /// domain, its own eval test and its log bridge reach for.
    @Test func aKindIsBuiltComparedAndPrintedWithoutThePosture() {
        let count = AskQuestionKind.count
        #expect(count == AskQuestionKind(rawValue: "count"))
        #expect(count.rawValue == "count" && count.description == "count")
        #expect(AskQuestionKind.showNoTiles.contains(count))
        #expect(!AskQuestionKind.showNoTiles.contains(.pick))
        let cuont = AskQuestionKind(rawValue: "cuont")
        #expect(AskQuestionKind.unrecognized(in: [count, cuont]) == [cuont])
    }

    /// A kind's stored form, off any actor, as a host's own archive of answers
    /// writes and reads it: the bare word, and back.
    @Test func aKindRoundTripsThroughJSONWithoutThePosture() throws {
        let data = try JSONEncoder().encode(AskQuestionKind.superlative)
        #expect(String(bytes: data, encoding: .utf8) == #""superlative""#)
        #expect(try JSONDecoder().decode(AskQuestionKind.self, from: data) == .superlative)
        let feedback = AskFeedback(
            sentiment: .negative, tier: .privateCloud, questionKind: .superlative,
            tilesShown: 1, rowsRead: 4, wasTruncated: false
        )
        #expect(feedback.questionKind == .superlative)
        #expect(feedback.line.contains(" kind=superlative "))
    }

    #if canImport(FoundationModels) && !os(tvOS)
    /// A domain listing its own kinds and the ones it rerolls, as a host
    /// spells them, and the default reroll reading them off any actor.
    @Test func aDomainsOwnKindsAreReadWithoutThePosture() {
        let domain = KindsDomain()
        #expect(domain.questionKinds.contains(.superlative))
        #expect(AskQuestionKind.unrecognized(in: domain.questionKinds).isEmpty)
        let pick = AskAnswer<AskNoRow>(text: "Dune.", questionKind: .pick)
        let oldest = AskAnswer<AskNoRow>(text: "Dune.", questionKind: .superlative)
        #expect(domain.isRerollable(pick, question: "What should I read?"))
        #expect(!domain.isRerollable(oldest, question: "What's my oldest book?"))
    }
    #endif
}

#if canImport(FoundationModels) && !os(tvOS)

/// A domain naming its own kinds, as a host's does.
private struct KindsDomain: AskDomain {
    let brand = AskBrand(
        title: "Ask the Shelf", appDirectory: "AskKitCrossPostureKinds",
        logSubsystem: "askkit.crossposture", help: "Ask about the shelf.",
        firstScreenHeadline: "Ask about the shelf", firstScreenSentence: "Answers come from the model.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    var questionKinds: [AskQuestionKind] { AskQuestionKind.default + [.superlative] }
    var rerollableKinds: Set<AskQuestionKind> { [.pick] }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer briefly."
    }
}

#endif
