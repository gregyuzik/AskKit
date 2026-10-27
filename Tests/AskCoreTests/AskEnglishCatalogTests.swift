import Foundation
import Testing

@testable import AskCore

/// What AskCore's catalog hands back for `en`, read from the compiled `en`
/// table and not through the process's language, so the answer is the same on
/// a Mac set to French.
///
/// The keys are the source text, written with the typewriter apostrophe so that
/// code and translations hang on one spelling; the English a reader sees takes
/// the typographic one (`TRANSLATION.md`). An `en` value that differs from its
/// key is how the catalog says so.
@Suite(.timeLimit(.minutes(1))) struct AskEnglishCatalogTests {
    private static let off = "Apple Intelligence is turned off. Turn it on in Settings."
    private static let notEligible = "This device can't run Apple Intelligence."

    /// The `en` table's bundle: the package's resources, narrowed to `en`.
    private static var english: Bundle {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url)
        else { preconditionFailure("the package ships an en table") }
        return bundle
    }

    private static func line(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: english)
    }

    /// Every key of the plain table, whatever it holds.
    private static var keys: [String] {
        guard let url = english.url(forResource: "Localizable", withExtension: "strings"),
              let data = try? Data(contentsOf: url),
              let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String]
        else { preconditionFailure("the en table is a strings file") }
        return table.keys.sorted()
    }

    @Test func everyKeyWithAnApostropheReadsWithTheTypographicOne() {
        // The line that varies by device is the next test's: on a Mac its
        // words differ from the key's beyond the apostrophe.
        let apostrophed = Self.keys.filter { $0.contains("'") && $0 != Self.notEligible }
        #expect(apostrophed.count >= 6, "the table was found, and it is not empty")
        for key in apostrophed {
            let expected = key.replacingOccurrences(of: "'", with: "\u{2019}")
            #expect(Self.line(key) == expected, "\(key)")
        }
    }

    @Test func noEnglishLineHoldsATypewriterApostrophe() {
        for key in Self.keys {
            #expect(!Self.line(key).contains("'"), "\(key)")
        }
    }

    /// The Mac's app is System Settings and the Mac says "this Mac" where the
    /// other devices say "this device"; the variation is the catalog's, and
    /// `other` is what everything else reads.
    @Test func theMacNamesItselfAndItsSettingsApp() {
        #if os(macOS)
        #expect(Self.line(Self.off) == "Apple Intelligence is turned off. Turn it on in System Settings.")
        #expect(Self.line(Self.notEligible) == "This Mac can\u{2019}t run Apple Intelligence.")
        #else
        #expect(Self.line(Self.off) == "Apple Intelligence is turned off. Turn it on in Settings.")
        #expect(Self.line(Self.notEligible) == "This device can\u{2019}t run Apple Intelligence.")
        #endif
    }

    /// The same lines through the code that shows them, when this process reads
    /// English.
    @Test(.enabled(if: Bundle.module.preferredLocalizations.first == "en"))
    func theErrorLinesReadTheCatalogsEnglish() {
        #expect(AskError.unavailableMessage(.appleIntelligenceOff) == Self.line(Self.off))
        #expect(AskError.unavailableMessage(.deviceNotEligible) == Self.line(Self.notEligible))
    }
}
