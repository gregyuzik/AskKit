#if os(iOS) || os(macOS) || os(visionOS)

import Foundation

/// The two phrases the wait row holds: what the turn is doing, and what it was
/// doing just before.
///
/// **A grounded turn moves through phrases, and the row keeps the one before.**
/// Under the default grounding policy a turn's answer is shown only once it
/// has read something (house rule 2), so the real sequence is typically
/// "Thinking…", then a tool's own report, then what that tool found. A row that drew only the last of them would tell the
/// reader the turn is busy without ever telling them it got anywhere.
///
/// A value rather than a pair of `@State` strings read out of the view, so
/// tests can pin the rule below without building a view, as they do for
/// `AskPrivateCloudState`.
nonisolated struct AskWaitWindow: Sendable, Equatable {
    /// What the row is reporting now. Empty before the first phrase lands.
    var current: String = ""

    /// The phrase this one replaced, drawn dimmed above it. Nil until a second
    /// and *different* phrase has arrived, so a turn that never moves on shows
    /// one line for its whole wait.
    var previous: String?

    /// This window once `phrase` arrives.
    ///
    /// **Deduped on the rendered string, never on `AskActivity`.**
    /// `AskActivityPhrase.fallback` sends `.custom`, a scope-less `.searching`
    /// and a scope-less `.reading` all to "Thinking…", so three different
    /// activities reach the row as one word. Keyed on the activity, this would
    /// draw "Thinking… / Thinking…" and claim the turn had moved on at the
    /// moment it hadn't.
    ///
    /// **Fed the phrase, never the rendered line.** `AskThinkingRow.shownLine`
    /// appends "· N read", and N ticks with every row the tools pull back, so
    /// a window advanced on the line would churn its upper phrase several times
    /// a second inside a single activity, which is the opposite of what it is
    /// for.
    func advanced(to phrase: String) -> AskWaitWindow {
        guard phrase != current else { return self }
        return AskWaitWindow(current: phrase, previous: current.isEmpty ? nil : current)
    }
}

#endif
