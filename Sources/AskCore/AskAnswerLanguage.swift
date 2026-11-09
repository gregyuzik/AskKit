import Foundation

/// The language a session's answers are asked for in, named the two ways a
/// model reads it: in English, as the seam names it
/// (`AskModelSeam.answerLanguage(for:)`), and in its own words, as
/// "Japanese (日本語)".
///
/// AskKit tells the model the language itself, in English, as Apple's
/// practice has it (`AskDomain.instructions(tier:isConversation:answerLanguage:)`).
/// A domain that names the language anywhere else, in its own words too, can
/// build one from the English name it is given there.
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
