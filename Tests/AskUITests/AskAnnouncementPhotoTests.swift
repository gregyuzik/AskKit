#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import Foundation
import Testing

@testable import AskUI

/// House rule 8 for a question asked with a photo: VoiceOver hears whether the
/// answer saw it, as the note under the question tells a reader who can look
/// (`AskTurn.answeredWithoutPhoto`).
@Suite(.timeLimit(.minutes(1))) struct AskAnnouncementPhotoTests {
    private static let photo = AskQuestionPhoto(label: "Navy blazer", reference: "asset-1")

    private func turn(photo: Bool, sawPhoto: Bool, tier: AskTier = .onDevice) -> AskTurn<UIRow> {
        var turn = AskTurn<UIRow>(
            question: "q", origin: .typed,
            photo: photo ? Self.photo : nil, photoImage: photo ? onePixel() : nil
        )
        turn.tier = tier
        turn.answerSawPhoto = sawPhoto
        return turn
    }

    private func ready(_ turn: AskTurn<UIRow>) -> String? {
        var settled = turn
        settled.settle(AskAnswer(text: "done", matches: [UIRow("A")]), at: 0)
        return AskAnnouncement.terminal(for: settled)
    }

    @Test func anAnswerThatSawNoPhotoSaysSoInsteadOfBeingReady() throws {
        let line = try #require(ready(turn(photo: true, sawPhoto: false)))
        let plain = try #require(ready(turn(photo: false, sawPhoto: false)))
        #expect(line != plain)
    }

    @Test func anAnswerThatSawThePhotoIsReady() throws {
        let saw = try #require(ready(turn(photo: true, sawPhoto: true, tier: .privateCloud)))
        let plain = try #require(ready(turn(photo: false, sawPhoto: false)))
        #expect(saw == plain)
    }

    /// An answer the app wrote on its own never saw the photo either, and no
    /// tier was ever chosen.
    @Test func anAnswerTheAppGaveOnItsOwnSaysSoToo() throws {
        var own = AskTurn<UIRow>(question: "q", origin: .typed, photo: Self.photo, photoImage: onePixel())
        own.settle(AskAnswer(text: "from the app", matches: []), at: 0)
        #expect(own.tier == nil)
        let line = try #require(AskAnnouncement.terminal(for: own))
        let plain = try #require(ready(turn(photo: false, sawPhoto: false)))
        #expect(line != plain)
    }

    /// A cut-short answer keeps its own line: the ending that matters most to
    /// the reader is that it stopped.
    @Test func aCutShortAnswerKeepsItsOwnLine() throws {
        var cut = turn(photo: true, sawPhoto: false)
        cut.settle(AskAnswer(text: "as far as it", matches: [], isTruncated: true), at: 0)
        var plainCut = turn(photo: false, sawPhoto: false)
        plainCut.settle(AskAnswer(text: "as far as it", matches: [], isTruncated: true), at: 0)
        #expect(AskAnnouncement.terminal(for: cut) == AskAnnouncement.terminal(for: plainCut))
    }

    @Test(.enabled(if: Bundle.module.preferredLocalizations.first == "en"))
    func inEnglishItSaysTheAnswerReadTheWordsOnly() {
        #expect(ready(turn(photo: true, sawPhoto: false)) == "Answer ready. It read your words only.")
        #expect(ready(turn(photo: true, sawPhoto: true, tier: .privateCloud)) == "Answer ready")
    }
}

#endif
