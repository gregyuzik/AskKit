#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Testing

@testable import AskUI

/// What the wait row keeps of the phrase before the one it is showing.
///
/// The row draws two lines and the upper one is history, so the only thing that
/// can be wrong here is *which* phrase is history — and every way of getting it
/// wrong looks fine in a screenshot and wrong only while a turn is running.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskWaitWindowTests {

    @Test func theFirstPhraseHasNothingAboveIt() {
        let window = AskWaitWindow().advanced(to: "Thinking…")
        #expect(window.current == "Thinking…")
        #expect(window.previous == nil, "a turn that has said one thing has no history to draw")
    }

    @Test func aSecondPhraseMovesTheFirstOneUp() {
        let window = AskWaitWindow()
            .advanced(to: "Thinking…")
            .advanced(to: "Searching your records…")
        #expect(window.current == "Searching your records…")
        #expect(window.previous == "Thinking…")
    }

    @Test func onlyTheOnePhraseBackIsKept() {
        let window = AskWaitWindow()
            .advanced(to: "Thinking…")
            .advanced(to: "Searching your records…")
            .advanced(to: "Reading 12 of 40…")
        #expect(window.current == "Reading 12 of 40…")
        #expect(window.previous == "Searching your records…", "the window is two lines, not a transcript")
    }

    /// `AskActivityPhrase.fallback` sends `.custom`, a scope-less `.searching`
    /// and a scope-less `.reading` all to "Thinking…", so three distinct
    /// activities reach the row as one word. Deduping on the activity instead of
    /// on the words would draw "Thinking… / Thinking…" and tell the reader the
    /// turn had moved on at the moment it had not.
    @Test func thePhraseRepeatingChangesNothing() {
        let once = AskWaitWindow().advanced(to: "Thinking…")
        let twice = once.advanced(to: "Thinking…")
        #expect(twice == once)
        #expect(twice.previous == nil)
    }

    /// The same, one phrase deeper: a turn already showing history must not
    /// shunt its own live line into the line above and stand there repeating
    /// itself.
    @Test func aRepeatDoesNotShuntTheLiveLineUpwards() {
        let window = AskWaitWindow()
            .advanced(to: "Thinking…")
            .advanced(to: "Reading 12 of 40…")
            .advanced(to: "Reading 12 of 40…")
        #expect(window.current == "Reading 12 of 40…")
        #expect(window.previous == "Thinking…")
    }

    /// A turn that goes back to something it was doing before — a second search
    /// after a read, or `.restarted` landing on the same fallback — is a real
    /// move, and the phrase it replaces is the one that belongs above it.
    @Test func returningToAnEarlierPhraseIsStillAMove() {
        let window = AskWaitWindow()
            .advanced(to: "Searching your records…")
            .advanced(to: "Reading 12 of 40…")
            .advanced(to: "Searching your records…")
        #expect(window.current == "Searching your records…")
        #expect(window.previous == "Reading 12 of 40…")
    }

    /// The guard that keeps the rows-read count out of the window. The row
    /// composes "phrase · N read" for the line it draws and advances the window
    /// on the *phrase*; were it ever advanced on the line instead, this is what
    /// the upper line would fill with: the same activity, several times a
    /// second, every time a tool pulled back another row.
    @Test func aCountTickingWithinOneActivityWouldBeTheBugToCatch() {
        let churned = AskWaitWindow()
            .advanced(to: "Reading 12 of 40… · 12 read")
            .advanced(to: "Reading 13 of 40… · 13 read")
        #expect(
            churned.previous == "Reading 12 of 40… · 12 read",
            "fed lines the window fills with one activity — which is why AskThinkingRow feeds it the phrase"
        )

        let steady = AskWaitWindow()
            .advanced(to: "Reading 12 of 40…")
            .advanced(to: "Reading 12 of 40…")
        #expect(steady.previous == nil)
    }
}

#endif
