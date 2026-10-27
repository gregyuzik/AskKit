#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// What the question's "Copy answer" puts on the pasteboard: the answer as the
/// reader reads it (`AskTurn.drawnText`), not the model's markdown. The
/// pasteboard call itself is the screen's own (`AskScreen.copy`), which these
/// don't reach; they pin the words handed to it.
@Suite(.timeLimit(.minutes(1))) struct AskCopyAnswerTests {
    private func answered(_ text: String) -> AskTurn<UIRow> {
        var turn = AskTurn<UIRow>(question: "What do I own by Miles Davis?", origin: .typed)
        turn.write(text, at: 0)
        return turn
    }

    /// Bold, a list and a link: the words survive, and the marks, the link's
    /// brackets and its destination don't.
    @Test func boldAListAndALinkCopyAsTheWordsTheReaderSees() {
        let turn = answered("""
            You own two records:
            - **Kind of Blue** by Miles Davis
            - *Rumours* by [Fleetwood Mac](https://example.com/fleetwood)
            """)

        let copied = turn.drawnText
        #expect(copied == "You own two records:\n- Kind of Blue by Miles Davis\n- Rumours by Fleetwood Mac")
        for leftover in ["*", "[", "]", "(", "https", "example.com"] {
            #expect(!copied.contains(leftover), "\(leftover) was copied")
        }
    }

    /// The prose the renderer draws and the words copied are one string, so a
    /// reader can't copy something the screen didn't show.
    @Test func theCopyIsTheCharactersTheRendererIsHanded() {
        let turn = answered("**Abbey Road** is the [newest](https://example.com/new) of the three.")
        #expect(turn.drawnText == String(turn.parsed.characters))
        #expect(turn.drawnText == "Abbey Road is the newest of the three.")
    }

    /// An answer with no markdown copies as it is written.
    @Test func plainProseCopiesUnchanged() {
        let text = "You own three records — the oldest is Kind of Blue.\nThe newest is Abbey Road."
        #expect(answered(text).drawnText == text)
    }

    /// A snapshot that replaces an earlier one is what a later copy reads.
    @Test func aLaterSnapshotIsWhatIsCopied() {
        var turn = answered("**Kind of")
        #expect(turn.drawnText == "**Kind of")
        turn.write("**Kind of Blue** is the oldest.", at: 1)
        #expect(turn.drawnText == "Kind of Blue is the oldest.")
    }

    /// Bold that CommonMark refuses beside Chinese punctuation is bolded by
    /// AskKit's own pass, whose private marks must not reach the pasteboard.
    @Test func boldAskKitTakesOverCopiesWithoutItsMarks() {
        let copied = answered("你拥有**《三体》**是…").drawnText
        #expect(copied == "你拥有《三体》是…")
    }

    /// A turn read back from disk is parsed on the way in, so it copies as a
    /// live one does.
    @Test func aRestoredTurnCopiesAsALiveOneDoes() {
        let entry = AskThreadEntry<UIRow>(
            question: "What do I own?",
            text: "You own **Rumours** — see [the shop](https://example.com/rumours).",
            answer: nil
        )

        #expect(AskTurn(entry: entry).drawnText == "You own Rumours — see the shop.")
    }

    /// A turn that has said nothing has nothing to copy, which is why the
    /// thread offers the item only once the answer has words.
    @Test func aTurnWithNoWordsCopiesNothing() {
        #expect(AskTurn<UIRow>(question: "q", origin: .typed).drawnText.isEmpty)
    }
}

#endif
