import Foundation

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// The language a session's answers are asked for in, named the two ways a
/// model reads it: in English, as the seam names it
/// (`AskModelSeam.answerLanguage(for:)`), and in its own words, as
/// "Japanese (日本語)".
///
/// The engine hands one to `AskDomain.toolResultEnding(answerLanguage:)`
/// outside English. A domain can build its own in
/// `instructions(tier:isConversation:answerLanguage:)`, from the English name
/// it is given there, so its instructions and its tool results name the
/// language alike.
nonisolated public struct AskAnswerLanguage: Sendable, Hashable {
    /// The language's English name, as the seam gave it: "Japanese", or
    /// "Chinese, Traditional" where the script matters.
    public let englishName: String
    /// Its name in its own words, "日本語", read from the app's localization:
    /// nil for English, for no localization, and for a localization of
    /// another language than `englishName`.
    public let ownName: String?

    /// "Japanese (日本語)", or `englishName` alone where there is no own name.
    public var promptName: String {
        ownName.map { "\(englishName) (\($0))" } ?? englishName
    }

    /// The language the seam named, its own name read from the app's
    /// localization: the main bundle's first preferred one, the language the
    /// app runs in. Nil for a nil or empty name, which is English, since the
    /// seam names no language there.
    public init?(englishName: String?) {
        self.init(englishName: englishName, localization: Bundle.main.preferredLocalizations.first)
    }

    /// The language the seam named, its own name read from `localization`, a
    /// language tag such as "ja" or "es-MX". Nil for a nil or empty name.
    public init?(englishName: String?, localization: String?) {
        guard let englishName, !englishName.isEmpty else { return nil }
        self.englishName = englishName
        self.ownName = Self.ownName(of: localization, namedInEnglish: englishName)
    }

    /// `localization`'s name for itself, when `englishName` names its
    /// language: "日本語" for "ja" under "Japanese", "español (México)" for
    /// "es-MX" under "Spanish". None for English, and never one language's own
    /// name beside another's English one ("German (日本語)"): the seam can name
    /// another language than the app's, when the app's isn't one a tier
    /// writes.
    static func ownName(of localization: String?, namedInEnglish englishName: String) -> String? {
        guard let localization,
              let code = Locale.Language(identifier: localization).languageCode?.identifier, code != "en",
              let english = Locale(identifier: "en").localizedString(forLanguageCode: code),
              englishName.hasPrefix(english),
              let own = Locale(identifier: localization).localizedString(forIdentifier: localization),
              !own.isEmpty
        else { return nil }
        return own
    }
}

#if canImport(FoundationModels) && !os(tvOS)

/// A domain's tool whose every result ends on the domain's line
/// (`AskDomain.toolResultEnding(answerLanguage:)`), after a blank line. Its
/// name, description and parameters are the tool's own, so the model is
/// offered the same tool; only what it reads back grows by the line.
nonisolated struct AskEndingTool<Arguments: ConvertibleFromGeneratedContent>: Tool {
    let base: any Tool<Arguments, String>
    let ending: String

    var name: String { base.name }
    var description: String { base.description }
    var parameters: GenerationSchema { base.parameters }
    var includesSchemaInInstructions: Bool { base.includesSchemaInInstructions }

    @concurrent func call(arguments: Arguments) async throws -> String {
        try await base.call(arguments: arguments) + "\n\n" + ending
    }
}

/// How a session's tools take the domain's line at the end of their results.
nonisolated enum AskToolEnding {
    /// `tools`, in their order, each one whose output is `String` ending its
    /// results on `ending`, and the names of the rest, passed through as they
    /// are: only text has an end a line can follow.
    static func wrap(_ tools: [any Tool], ending: String) -> (tools: [any Tool], passedThrough: [String]) {
        var passedThrough: [String] = []
        let wrapped = tools.map { tool -> any Tool in
            guard let ended = ended(tool, ending: ending) else {
                passedThrough.append(tool.name)
                return tool
            }
            return ended
        }
        return (wrapped, passedThrough)
    }

    /// `tool` ending its results on `ending`, or nil when its output isn't
    /// `String`.
    private static func ended<T: Tool>(_ tool: T, ending: String) -> (any Tool)? {
        guard let text = tool as? any Tool<T.Arguments, String> else { return nil }
        return AskEndingTool(base: text, ending: ending)
    }
}

#endif
