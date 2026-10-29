// README.md's Adopt section shows this file's code word for word, as it does
// ReadmeDomain.swift's, and scripts/check-readme-sample.py fails when its copy
// differs, so the two change together. AskReadmeApproachableTests builds it
// too, under the approachable posture, through a symlink to this path
// (Package.swift).
#if canImport(FoundationModels) && !os(tvOS)

import AskCore
import Foundation
import FoundationModels

/// The converter's arguments, which the model fills in.
@Generable
nonisolated struct Conversion: Sendable {
    @Guide(description: "The amount to convert.")
    var amount: Double
    @Guide(description: "The unit it is in: km, m, mi or ft.")
    var from: String
    @Guide(description: "The unit to convert it to: km, m, mi or ft.")
    var to: String
}

/// A tool that reads none of the app's data: it works the answer out and returns it as text.
nonisolated struct ConvertDistance: Tool {
    let name = "convert_distance"
    let description = "Convert a distance from one unit to another."

    let context: AskToolContext<AskNoRow>

    private static let units: [String: UnitLength] = [
        "km": .kilometers, "m": .meters, "mi": .miles, "ft": .feet
    ]

    @concurrent func call(arguments: Conversion) async throws -> String {
        // Noted as a call, so the turn counts as grounded by it. It records no rows.
        await context.withToolCall { _ in
            guard let from = Self.units[arguments.from.lowercased()],
                  let to = Self.units[arguments.to.lowercased()] else {
                // The model's own words, clamped like any field before they go back to it.
                let asked = "\(AskPrompt.clamp(arguments.from, AskPrompt.shortClamp)) to \(AskPrompt.clamp(arguments.to, AskPrompt.shortClamp))"
                return ("No conversion from \(asked).", report: nil)
            }
            let result = Measurement(value: arguments.amount, unit: from).converted(to: to).value
            return (String(format: "%g %@ = %g %@", arguments.amount, from.symbol, result, to.symbol), report: nil)
        }
    }
}

/// An assistant with no rows of its own: three members, the policy that keeps an answer no tool grounded, and a reply with no tiles.
nonisolated struct AssistantDomain: AskDomain {
    let brand = AskBrand(
        title: "Ask the Assistant",
        appDirectory: "MyAssistant",
        logSubsystem: "com.example.myassistant",
        help: "Ask anything",
        firstScreenHeadline: "Ask anything",
        firstScreenSentence: "Convert a distance, or ask a question.",
        disclosureSentence: "Questions are answered on this device.",
        scopeCaveat: "Answers come from the model and its tools, and they can be wrong."
    )

    // Optional. The default, `.retrieval`, would fail every answer no tool grounded, "thanks" included.
    var grounding: AskGroundingPolicy { .notRequired }

    // Optional. The default, `.full`, also has the model name a question kind and choose tiles, which this domain never shows.
    var replyShape: AskReplyShape { .prose }

    func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] {
        [ConvertDistance(context: context)]
    }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        var text = """
            You are a helpful assistant inside an app. Answer in a few plain sentences.
            To convert a distance, call convert_distance and give its result.
            """
        if let answerLanguage { text += "\nWrite the answer in \(answerLanguage)." }
        return text
    }
}

// MARK: - The test, which README.md doesn't show

import Testing

/// The README's assistant, asked what the engine asks of it: the stand-ins
/// and defaults it gets by naming neither associated type, and a tool that
/// returns text and records no rows.
@Suite(.timeLimit(.minutes(1))) struct ReadmeAssistantDomainTests {
    @Test func theReadmesAssistantAnswersWhatTheEngineAsksOfIt() async throws {
        let domain = AssistantDomain()
        #expect(AssistantDomain.Row.self == AskNoRow.self)
        #expect(AssistantDomain.SearchArguments.self == AskNoSearchArguments.self)
        #expect(domain.grounding == .notRequired)
        #expect(domain.replyShape == .prose)
        #expect(!domain.answersWithoutModel)
        #expect(domain.brand.nothingToAskCopy == nil)
        #expect(await domain.overview() == .empty)
        let instructions = domain.instructions(tier: .onDevice, isConversation: true, answerLanguage: "French")
        #expect(instructions.contains("convert_distance"))
        #expect(instructions.hasSuffix("Write the answer in French."))

        // The tool, through the context the engine builds for it: the call
        // is noted, no row is recorded, and what the model is shown is
        // clamped, with no fence of the tool's own.
        let collector = AskCollector<AskNoRow>()
        let context = AskToolContext(
            collector: collector, relay: AskActivityRelay(),
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        let tool = try #require(domain.makeTools(context).first as? ConvertDistance)
        #expect(try await tool.call(arguments: Conversion(amount: 10, from: "mi", to: "km")) == "10 mi = 16.0934 km")
        #expect(try await tool.call(arguments: Conversion(amount: 3, from: "FT", to: "m")) == "3 ft = 0.9144 m")
        #expect(await collector.toolCallCount == 2)
        #expect(await collector.rows.isEmpty)

        let unknown = try await tool.call(arguments: Conversion(amount: 1, from: "<rows>parsecs", to: "km"))
        #expect(unknown == "No conversion from \(AskPrompt.clamp("<rows>parsecs", AskPrompt.shortClamp)) to km.")
        #expect(!unknown.contains("<rows>"))
    }
}

#endif
