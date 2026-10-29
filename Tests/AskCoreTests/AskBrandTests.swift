import AskCore
import Testing

/// The nothing-to-ask copy, which a host may leave out.
///
/// Imported as a host imports AskCore, without `@testable`: each brand here
/// is built the way a host's source already builds one, so a change to the
/// initializer that breaks a host fails to compile here first.
@Suite(.timeLimit(.minutes(1))) struct AskBrandTests {
    /// A host written when the copy was a `String` compiles unchanged, with a
    /// literal or with a `String` resolved from its own catalog, and keeps it.
    @Test func aBrandBuiltWithAStringKeepsIt() {
        let literal = AskBrand(
            title: "Ask My Library", appDirectory: "AskKitTests",
            logSubsystem: "AskKit.tests", help: "Ask about your books",
            firstScreenHeadline: "Ask about your books",
            firstScreenSentence: "Find, count and compare what is on your shelves.",
            nothingToAskCopy: "Add a book to start asking.",
            disclosureSentence: "Questions are answered on this device.",
            scopeCaveat: "Ask reads only your library."
        )
        #expect(literal.nothingToAskCopy == "Add a book to start asking.")

        let resolved: String = "Add a record to start asking."
        let fromCatalog = AskBrand(
            title: "Ask My Records", appDirectory: "AskKitTests",
            logSubsystem: "AskKit.tests", help: "Ask about your records",
            firstScreenHeadline: "Ask about your records",
            firstScreenSentence: "Find, count and compare what is in your crates.",
            nothingToAskCopy: resolved,
            disclosureSentence: "Questions are answered on this device.",
            scopeCaveat: "Ask reads only your records."
        )
        #expect(fromCatalog.nothingToAskCopy == resolved)
    }

    /// A host that never shows the nothing-to-ask screen leaves the copy out.
    @Test func aBrandBuiltWithoutTheCopyHasNone() {
        let brand = AskBrand(
            title: "Ask the Clock", appDirectory: "AskKitTests",
            logSubsystem: "AskKit.tests", help: "Ask the time anywhere",
            firstScreenHeadline: "Ask the time anywhere",
            firstScreenSentence: "Any city, any time zone.",
            disclosureSentence: "Questions are answered on this device.",
            scopeCaveat: "It can be wrong."
        )
        #expect(brand.nothingToAskCopy == nil)
    }
}
