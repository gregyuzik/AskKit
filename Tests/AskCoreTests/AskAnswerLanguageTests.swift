#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels
import Testing

@testable import AskCore

/// `AskAnswerLanguage`'s names, and the tool wrapper that ends a result on a
/// domain's line (`AskToolEnding`).
@Suite(.timeLimit(.minutes(1))) struct AskAnswerLanguageTests {
    // MARK: - Names

    @Test(arguments: [
        ("Japanese", "ja", "Japanese (日本語)"),
        ("German", "de", "German (Deutsch)"),
        ("Chinese", "zh-Hans", "Chinese (简体中文)"),
        ("Korean", "ko", "Korean (한국어)"),
        ("French", "fr", "French (français)"),
        ("Spanish", "es", "Spanish (español)"),
        ("Spanish", "es-MX", "Spanish (español (México))")
    ])
    func aLanguageIsNamedInEnglishAndInItsOwnWords(english: String, localization: String, named: String) {
        #expect(AskAnswerLanguage(englishName: english, localization: localization)?.promptName == named)
    }

    @Test func aLanguageTheAppDoesntRunInIsNamedInEnglishAlone() {
        // The seam can name another language than the app's, when the app's
        // isn't one a tier writes: never "German (日本語)".
        let german = AskAnswerLanguage(englishName: "German", localization: "ja")
        #expect(german?.ownName == nil)
        #expect(german?.promptName == "German")
        #expect(AskAnswerLanguage(englishName: "Japanese", localization: nil)?.promptName == "Japanese")
        #expect(AskAnswerLanguage(englishName: "English", localization: "en")?.ownName == nil)
    }

    @Test func noNameIsNoLanguage() {
        // English: the seam names no language there.
        #expect(AskAnswerLanguage(englishName: nil, localization: "ja") == nil)
        #expect(AskAnswerLanguage(englishName: "", localization: "ja") == nil)
    }

    // MARK: - The wrapper

    @Test func aTextToolsResultEndsOnTheLineOnce() async throws {
        let ended = AskToolEnding.wrap([EndingEchoTool()], ending: "Write your answer in Japanese (日本語).")
        #expect(ended.passedThrough.isEmpty)
        let result = try await callTool(try #require(ended.tools.first), text: "green")
        #expect(result == "Rows for green.\n\nWrite your answer in Japanese (日本語).")
    }

    @Test func theModelIsOfferedTheSameTool() throws {
        let base = EndingEchoTool()
        let wrapped = try #require(AskToolEnding.wrap([base], ending: "End.").tools.first)
        #expect(!(wrapped is EndingEchoTool))
        #expect(wrapped.name == base.name)
        #expect(wrapped.description == base.description)
        #expect(wrapped.includesSchemaInInstructions == base.includesSchemaInInstructions)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(wrapped.parameters) == encoder.encode(base.parameters))
    }

    @Test func aToolThatReturnsNoTextPassesThrough() throws {
        let ended = AskToolEnding.wrap([EndingListTool(), EndingEchoTool()], ending: "End.")
        #expect(ended.passedThrough == ["list"])
        #expect(ended.tools.count == 2)
        #expect(ended.tools.first is EndingListTool)
        #expect(ended.tools.last?.name == "echo")
    }
}

// MARK: - Tools

/// A tool that answers in text, as every tool in the apps and the demo does.
nonisolated struct EndingEchoTool: Tool {
    let name = "echo"
    let description = "Says which rows it found."
    let includesSchemaInInstructions = false

    @Generable
    nonisolated struct Arguments {
        var text: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        "Rows for \(arguments.text)."
    }
}

/// A tool that answers in something other than text.
nonisolated struct EndingListTool: Tool {
    let name = "list"
    let description = "Lists rows."

    @Generable
    nonisolated struct Arguments {
        var text: String
    }

    @concurrent func call(arguments: Arguments) async throws -> [String] {
        [arguments.text]
    }
}

/// What `tool` returns, called with `text`, when it returns text.
func callTool(_ tool: any Tool, text: String) async throws -> String? {
    func call<T: Tool>(_ tool: T) async throws -> String? {
        let arguments = try T.Arguments(GeneratedContent(properties: ["text": text]))
        return try await tool.call(arguments: arguments) as? String
    }
    return try await call(tool)
}

#endif
