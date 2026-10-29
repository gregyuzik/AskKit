#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
import SwiftUI
#endif

/// A domain's one word that it answers without a model, the answer it gives
/// then with a payload of its own type, and the nothing-to-ask screen's button
/// as one value, called as a host without the posture calls them: no
/// `swiftSettings`, so nonisolated by default (`CrossPostureTests` says why
/// the target has none).
@Suite(.timeLimit(.minutes(1))) struct CrossPostureFirstScreenCopyTests {

    /// A domain that answers without a model says so in one word, and its
    /// hook builds the answer with a payload of the host's own plain type,
    /// which AskKit encodes and reads back as that type. A payload that
    /// doesn't encode throws out of the hook, asked as the engine asks it.
    @Test func aDomainAnswersWithoutAModelInOneWordAndItsPayloadIsTyped() async throws {
        let domain = ShelfScriptDomain()
        #expect(domain.answersWithoutModel)
        #expect(domain.brand.nothingToAskCopy == nil)

        let answer = try #require(try await Self.answered(by: domain, "How old are my records?"))
        #expect(answer.payload(as: ShelfScriptSpan.self) == ShelfScriptSpan(oldest: 1959, newest: 1977))
        let moved = try answer.replacing(payload: ShelfScriptSpan(oldest: 1960, newest: 1977))
        #expect(moved.payload(as: ShelfScriptSpan.self)?.oldest == 1960)
        #expect(moved.text == answer.text)

        await #expect(throws: EncodingError.self) {
            try await Self.answered(by: domain, ShelfScriptDomain.unencodable)
        }
        #expect(try await Self.answered(by: domain, "Something else") == nil)
    }

    /// Asked through the protocol, from generic code, as the engine asks.
    private static func answered<Domain: AskDomain>(
        by domain: Domain, _ question: String
    ) async throws -> AskAnswer<Domain.Row>? {
        try await domain.deterministicAnswer(for: question)
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    /// The nothing-to-ask button, its label and what it does in one value:
    /// built off any actor, and run on the main actor, where a tap runs it.
    @Test func theNothingToAskButtonIsOneValueBuiltOffAnyActor() async {
        let taps = await MainActor.run { ShelfScriptTaps() }
        let action = AskNothingToAskAction("Add Your First Record") { taps.count += 1 }
        #expect(action.label == "Add Your First Record")
        await MainActor.run { action.handler() }
        #expect(await MainActor.run { taps.count } == 1)
    }

    /// The first screen takes the domain's word and the button, each with a
    /// default, as a host that draws it on its own passes them: the
    /// nothing-to-ask one in the words of a brand that has them.
    @MainActor
    @Test func theFirstScreenTakesTheDomainsWordAndTheButton() {
        let domain = ShelfScriptDomain()
        _ = AskFirstScreen(
            phase: .cannotServe(.appleIntelligenceOff), brand: domain.brand,
            starters: [AskStarter(text: "How old are my records?")],
            answersWithoutModel: domain.answersWithoutModel,
            onStarter: { _ in }, mark: { AskDefaultMark(isLit: $0) }
        ).body
        let records = AskBrand(
            title: "Ask My Records", appDirectory: "AskKitCrossPostureShelfScript",
            logSubsystem: "askkit.crossposture", help: "Ask about your records.",
            firstScreenHeadline: "Ask about your records", firstScreenSentence: "Find what is in your crates.",
            nothingToAskCopy: "Add a record to start asking.",
            disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
        )
        _ = AskFirstScreen(
            phase: .nothingToAskAbout, brand: records, starters: [],
            onStarter: { _ in },
            nothingToAskAction: AskNothingToAskAction("Add Your First Record") {},
            mark: { AskDefaultMark(isLit: $0) }
        ).body
    }
    #endif
}

/// A host's payload type, plain: nonisolated by this target's default.
private struct ShelfScriptSpan: Codable, Equatable, Sendable {
    let oldest: Int
    let newest: Int
}

/// A payload JSON can't hold.
private struct ShelfScriptReading: Codable, Sendable {
    let value: Double
}

/// A domain with no rows of its own that answers some questions itself, and
/// leaves the rest to the model, whose answers needn't be grounded.
private struct ShelfScriptDomain: AskDomain {
    /// The question whose answer carries a payload that doesn't encode.
    static let unencodable = "What is the average age of nothing?"

    let brand = AskBrand(
        title: "Ask About Records", appDirectory: "AskKitCrossPostureShelfScript",
        logSubsystem: "askkit.crossposture", help: "Ask about records.",
        firstScreenHeadline: "Ask about records", firstScreenSentence: "Some answers need no model.",
        disclosureSentence: "Questions are answered on this device.", scopeCaveat: "It can be wrong."
    )

    var grounding: AskGroundingPolicy { .notRequired }

    var answersWithoutModel: Bool { true }

    func deterministicAnswer(for question: String) async throws -> AskAnswer<AskNoRow>? {
        if question == Self.unencodable {
            return try AskAnswer(text: "No records.", payload: ShelfScriptReading(value: .nan))
        }
        guard question.contains("How old") else { return nil }
        return try AskAnswer(
            text: "From 1959 to 1977.", questionKind: AskQuestionKind.count,
            payload: ShelfScriptSpan(oldest: 1959, newest: 1977)
        )
    }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer briefly."
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
/// How many times a button ran, on the main actor, where it runs.
@MainActor
private final class ShelfScriptTaps {
    var count = 0
}
#endif

#endif
