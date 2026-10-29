#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels
import Testing

@testable import AskCore

/// Question kinds as a type: what a chat file holds, what the model is
/// offered, and the words a log line and the eval table print. Each is what
/// the `String` it replaced gave, so the type changes what a domain can
/// misspell and nothing a reader, a file or the model sees.
@Suite(.timeLimit(.minutes(1))) struct AskQuestionKindTests {

    /// The vocabulary's words, in the schema's order.
    private static let words = [
        "lookup", "count", "totalValue", "pick", "superlative", "everyMatch", "yesNo", "wear", "pairing",
        "suggestion", "other"
    ]

    // MARK: - On disk

    /// Stored as the bare word, as the `String` was, so a chat file written
    /// now holds the bytes one 0.2.0 wrote.
    @Test func aKindIsStoredAsItsBareWord() throws {
        #expect(String(bytes: try JSONEncoder().encode(AskQuestionKind.count), encoding: .utf8) == #""count""#)
        let kinds = try JSONEncoder().encode([AskQuestionKind.pick, AskQuestionKind.yesNo])
        #expect(String(bytes: kinds, encoding: .utf8) == #"["pick","yesNo"]"#)
    }

    /// A word the vocabulary doesn't have, such as the on-disk fixture's
    /// "which" or one a later AskKit adds, decodes as itself. A throw would
    /// drop the answer it belongs to, and with it the reader's turn.
    @Test func aWordTheVocabularyDoesntHaveStillDecodes() throws {
        let kind = try JSONDecoder().decode(AskQuestionKind.self, from: Data(#""which""#.utf8))
        #expect(kind == AskQuestionKind(rawValue: "which"))
        #expect(!AskQuestionKind.all.contains(kind))
    }

    /// An answer's kind sits under `questionKind` as the word, and reads back
    /// as the kind.
    @Test func anAnswersKindIsWrittenAsTheWord() throws {
        let data = try JSONEncoder().encode(AskAnswer<FakeRow>(text: "Six.", questionKind: .count))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["questionKind"] as? String == "count")
        #expect(try JSONDecoder().decode(AskAnswer<FakeRow>.self, from: data).questionKind == .count)
    }

    // MARK: - The vocabulary

    /// Each member's word is what the schema offers and a chat file holds, so
    /// a member is renamed only with both in mind.
    @Test func everyMembersWordIsPinned() {
        #expect(AskQuestionKind.all.map(\.rawValue) == Self.words)
        #expect(AskQuestionKind.default == [.lookup, .count, .pick, .everyMatch, .yesNo, .other])
        #expect(AskQuestionKind.showNoTiles == [.count, .totalValue, .yesNo])
    }

    /// A misspelling can only be built on purpose now, with
    /// `init(rawValue:)`, and is still caught: it would cost a count its "no
    /// tiles" (house rule 7).
    @Test func aMisspelledKindIsStillCaught() {
        let cuont = AskQuestionKind(rawValue: "cuont")
        #expect(AskQuestionKind.unrecognized(in: [.count, cuont, .pick]) == [cuont])
        #expect(AskQuestionKind.unrecognized(in: AskQuestionKind.all).isEmpty)
    }

    /// **The model is offered the same eleven words, in the same order.**
    /// Every host's model reads this list, so building it from the type
    /// changes nothing the model sees.
    @Test func theSchemaOffersTheModelTheSameWords() throws {
        let data = try JSONEncoder().encode(AskReply.generationSchema)
        let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let kind = try #require(properties["questionKind"] as? [String: Any])
        #expect(kind["enum"] as? [String] == Self.words)
        #expect(kind["type"] as? String == "string")
    }

    // MARK: - The words in a line

    /// A log line prints the word, not the type's description of itself.
    @Test func aKindPrintsAsItsWord() {
        #expect(AskQuestionKind.superlative.description == "superlative")
        #expect("\(AskQuestionKind.everyMatch)" == "everyMatch")
        let verdict = AskFeedback(
            sentiment: .positive, tier: .onDevice, questionKind: .yesNo, tilesShown: 0, rowsRead: 3, wasTruncated: false
        )
        #expect(verdict.line == "[feedback] positive tier=onDevice kind=yesNo tiles=0 rows=3")
    }

    /// The eval table's kind column and a kind miss print the words.
    @Test func theEvalTablePrintsTheWords() {
        var outcome = AskOutcome(id: "count")
        outcome.questionKind = .lookup
        outcome.misses = [.kind(expected: [.count, .totalValue], got: .lookup)]
        let row = AskEval<FakeDomain>.table([outcome]).split(separator: "\n").map(String.init)[2]
        #expect(row.hasPrefix("| count | – | 0 | 0 | 0 | 0 | lookup | – | "))
        #expect(row.hasSuffix(" | KIND lookup, expected count or totalValue |"))
        #expect(AskOutcome.Miss.kind(expected: [.count], got: nil).line == "KIND none, expected count")
    }
}

#endif
