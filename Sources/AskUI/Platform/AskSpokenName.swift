#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import SwiftUI

/// The names Voice Control answers to for an element that shows words of the
/// reader's or the host's: a question, a draft, a placeholder.
///
/// **The words on screen, then the element's name.** Voice Control matches what
/// a reader says against an element's input labels, and shows the first as its
/// name. Labelled "Your question" alone, the composer's field and every
/// question bubble shared one name, and "Tap" with the words the reader could
/// see matched nothing. So the opening words lead, short enough to say, then
/// the words whole where they run longer, then the element's own name.
nonisolated enum AskSpokenName {
    /// How many words lead: enough to tell two questions apart, few enough to
    /// say in one breath.
    static let openingWords = 4

    /// The first `count` words of `text`, as it spells them, without what
    /// follows the last of them. Words as the text's language divides them,
    /// so a Japanese or Chinese question, written without spaces, still
    /// yields words rather than the whole of it.
    static func opening(of text: String, words count: Int = openingWords) -> String {
        var end = text.startIndex
        var seen = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            end = range.upperBound
            seen += 1
            if seen == count { stop = true }
        }
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The opening words, the whole text where it is longer, and `name`: the
    /// input labels of an element that shows `visible`. Just `name` while
    /// nothing is shown.
    static func inputLabels(showing visible: String, named name: Text) -> [Text] {
        let whole = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = opening(of: whole)
        return words(opening: opening, whole: whole).map { Text(verbatim: $0) } + [name]
    }

    /// The spoken forms of `whole` ahead of the element's name: its opening,
    /// and the whole where that is longer. Apart from `Text` so it can be
    /// pinned.
    static func words(opening: String, whole: String) -> [String] {
        guard !opening.isEmpty else { return whole.isEmpty ? [] : [whole] }
        return opening == whole ? [whole] : [opening, whole]
    }
}

#endif
