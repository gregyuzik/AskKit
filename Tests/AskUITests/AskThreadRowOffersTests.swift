#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// When a failure offers Try Again (`AskTurn.offersRetry(isNewest:whileThinking:)`).
@Suite(.timeLimit(.minutes(1))) struct AskTryAgainOfferTests {
    private func failed(retryable: Bool = true) -> AskTurn<UIRow> {
        var turn = AskTurn<UIRow>(question: "What's the oldest?", origin: .typed)
        turn.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", retryable: retryable)
        return turn
    }

    /// A failure that can be asked again, on the newest turn, offers it.
    @Test func theNewestRetryableFailureOffersTryAgain() {
        #expect(failed().offersRetry(isNewest: true, whileThinking: false))
    }

    /// **Not while a question waits to be asked.** The store is thinking from
    /// the tap, the waiting question has no turn yet, so the failed one is
    /// still the newest, and `retry` does nothing until the question has been
    /// asked: a Try Again shown then took the tap and did nothing with it.
    @Test func aQuestionWaitingToBeAskedTakesTryAgainAway() {
        #expect(!failed().offersRetry(isNewest: true, whileThinking: true))
    }

    /// Only the newest turn, and only a failure that can be asked again.
    @Test func anOlderOrAnUnretryableFailureOffersNothing() {
        #expect(!failed().offersRetry(isNewest: false, whileThinking: false))
        #expect(!failed(retryable: false).offersRetry(isNewest: true, whileThinking: false))
        let unfailed = AskTurn<UIRow>(question: "What's the oldest?", origin: .typed)
        #expect(!unfailed.offersRetry(isNewest: true, whileThinking: false))
    }
}

/// The wait row's live line: the phrase, and the count joined to it by each
/// locale's own separator (`AskWaitRowLine`).
@Suite(.timeLimit(.minutes(1))) struct AskWaitRowLineTests {
    /// The join's key, as `String(localized:)` writes the interpolation.
    private static let key = "%@ · %@"

    /// Before the turn has read anything the line is the phrase alone, and
    /// after, the phrase and the count.
    @Test func theCountFollowsThePhraseOnceThereIsOne() {
        #expect(AskWaitRowLine.joining("Searching", read: nil) == "Searching")
        let joined = AskWaitRowLine.joining("Searching", read: "12 read")
        #expect(joined.hasPrefix("Searching"))
        #expect(joined.hasSuffix("12 read"))
    }

    /// **Every locale has the join**, so a language with its own separator
    /// says it its own way. Spelled into the code, " · " was the one part of
    /// the line no translation could change. English is the key itself, and
    /// its table holds only the lines that differ from their keys.
    @Test func everyLocaleTranslatesTheJoin() throws {
        let missing = "\u{0}missing"
        let locales = Bundle.module.localizations.filter { $0 != "Base" && $0 != "en" }
        #expect(locales.count >= 24, "every locale the package translates")
        for locale in locales {
            let url = try #require(Bundle.module.url(forResource: locale, withExtension: "lproj"), "\(locale)")
            let table = try #require(Bundle(url: url), "\(locale)")
            let line = table.localizedString(forKey: Self.key, value: missing, table: nil)
            #expect(line != missing, "\(locale)")
            #expect(line.components(separatedBy: "%").count == 3, "\(locale): two placeholders")
        }
    }
}

#endif
