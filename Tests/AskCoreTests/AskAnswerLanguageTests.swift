import Foundation
import Testing

@testable import AskCore

/// `AskAnswerLanguage`'s names: in English, as the seam gives them, and in the
/// language's own words, from the app's localization.
@Suite(.timeLimit(.minutes(1))) struct AskAnswerLanguageTests {
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
}
