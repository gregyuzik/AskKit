#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Testing

@testable import AskUI

/// What AskUI's catalog hands back for `en`, read from the compiled `en` table
/// and not through the process's language, so the answer is the same on a Mac
/// set to French.
///
/// The keys are the source text, written with the typewriter apostrophe so that
/// code and translations hang on one spelling; the English a reader sees takes
/// the typographic one (`TRANSLATION.md`). An `en` value that differs from its
/// key is how the catalog says so.
@Suite(.timeLimit(.minutes(1))) struct AskEnglishCatalogTests {
    private static var english: Bundle {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url)
        else { preconditionFailure("the package ships an en table") }
        return bundle
    }

    private static var keys: [String] {
        guard let url = english.url(forResource: "Localizable", withExtension: "strings"),
              let data = try? Data(contentsOf: url),
              let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String]
        else { preconditionFailure("the en table is a strings file") }
        return table.keys.sorted()
    }

    @Test func everyKeyWithAnApostropheReadsWithTheTypographicOne() {
        let apostrophed = Self.keys.filter { $0.contains("'") }
        #expect(apostrophed.count >= 9, "the table was found, and it is not empty")
        for key in apostrophed {
            let line = String(localized: String.LocalizationValue(key), bundle: Self.english)
            #expect(line == key.replacingOccurrences(of: "'", with: "\u{2019}"), "\(key)")
        }
    }

    @Test func noEnglishLineHoldsATypewriterApostrophe() {
        for key in Self.keys {
            let line = String(localized: String.LocalizationValue(key), bundle: Self.english)
            #expect(!line.contains("'"), "\(key)")
        }
    }
}

#endif
