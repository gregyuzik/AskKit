#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// What the wait row says for an activity the domain doesn't word itself
/// (`AskActivityPhrase.fallback(for:)`).
@Suite(.timeLimit(.minutes(1))) struct AskActivityPhraseTests {
    /// A search or a read that names its scope says so.
    @Test func aScopeIsNamed() {
        let searching = AskActivityPhrase.fallback(for: .searching(scope: "records"))
        let reading = AskActivityPhrase.fallback(for: .reading(shown: 3, total: 40, scope: "records"))
        #expect(searching.contains("records"))
        #expect(reading.contains("records"))
        #expect(searching != AskActivityPhrase.thinking)
        #expect(reading != AskActivityPhrase.thinking)
    }

    /// **A scope with no words is no scope**, and reads as one that names
    /// none: "Thinking…". Set into the sentence, it read "Searching your …"
    /// and "Reading …".
    @Test(arguments: [nil, "", " ", "\n", " \t "] as [String?])
    func aBlankScopeIsNoScope(_ scope: String?) {
        #expect(AskActivityPhrase.fallback(for: .searching(scope: scope)) == AskActivityPhrase.thinking)
        #expect(AskActivityPhrase.fallback(for: .reading(shown: 3, total: 40, scope: scope)) == AskActivityPhrase.thinking)
    }
}

#endif
