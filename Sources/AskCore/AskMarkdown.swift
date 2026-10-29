package import Foundation

/// The one reading of the inline Markdown a model writes: the one AskUI draws
/// an answer's prose with (`AskArrivals.parse`), and the one that makes a
/// follow-up plain text (`AskAnswer.cleanedFollowUps(_:)`), so a chip says
/// what the prose would have drawn.
nonisolated package enum AskMarkdown {
    /// `text` as attributed text: its inline Markdown parsed, line breaks
    /// kept, and nothing that would restructure it (a "- " list stays a list
    /// of dashes). A string the parser rejects comes back as it came.
    ///
    /// Bold against Chinese and Japanese punctuation is taken out of the
    /// parser's hands first (`unspacedBold(in:)`): `takenOver` says there was
    /// some, and each such stretch is left between `boldOpens` and
    /// `boldCloses` for the caller to bold, or to drop the marks.
    package static func parse(_ text: String) -> (parsed: AttributedString, takenOver: Bool) {
        let (source, takenOver) = unspacedBold(in: text)
        let parsed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
        return (parsed, takenOver)
    }

    /// `text` as the plain characters its parse draws: emphasis, code spans
    /// and strikethrough lose their marks, a link or an image keeps only its
    /// label, and an escape or an entity becomes the character it stands for.
    /// What CommonMark doesn't read as Markdown stays, as `snake_case` and
    /// `5 * 3` do.
    static func plainText(_ text: String) -> String {
        let (parsed, takenOver) = parse(text)
        let plain = String(parsed.characters)
        return takenOver ? plain.filter { $0 != boldOpens && $0 != boldCloses } : plain
    }

    /// Where a pair `unspacedBold` took over opens and closes, carried through
    /// the parse: private-use characters, which no answer writes and the
    /// parser passes through as letters.
    package static let boldOpens: Character = "\u{E000}"
    package static let boldCloses: Character = "\u{E001}"

    /// `text` with each `**` pair CommonMark would refuse for the script of
    /// the word beside it swapped for `boldOpens` and `boldCloses`, and
    /// whether there was one.
    ///
    /// The answer guide asks for names in bold, and a Chinese or Japanese
    /// answer puts a name in its own brackets and writes the next word
    /// straight on: `**《三体》**是…`, `おすすめは**「雪国」**です`. CommonMark
    /// won't close `**` after punctuation with a letter straight after it,
    /// nor open one after a letter with punctuation straight after, so those
    /// asterisks would show.
    ///
    /// The pairs are the `**` runs taken two by two in order, as the model
    /// writes them. A pair is taken over only where CommonMark's flanking
    /// rule fails it for a word written straight on: an opener with
    /// punctuation inside it and, outside, a letter of a script that sets no
    /// spaces between words, or a closer the same way round. Everywhere else
    /// the parser's verdict stands, so spaced prose parses as CommonMark says.
    /// A text that already holds a mark is left whole.
    static func unspacedBold(in text: String) -> (String, Bool) {
        guard text.contains("**"), !text.contains(boldOpens), !text.contains(boldCloses) else { return (text, false) }
        var characters = Array(text)
        // Every run of exactly two asterisks: one or three are something else.
        let runs = characters.indices.filter { index in
            characters[index] == "*" && index + 1 < characters.count && characters[index + 1] == "*"
                && (index == 0 || characters[index - 1] != "*")
                && (index + 2 == characters.count || characters[index + 2] != "*")
        }
        var takenOver: [(opens: Int, closes: Int)] = []
        var pending = runs.makeIterator()
        while let opens = pending.next(), let closes = pending.next() {
            let inner = characters[(opens + 2)..<closes]
            guard let first = inner.first, let last = inner.last,
                  !first.isWhitespace, !last.isWhitespace, !inner.contains(where: \.isNewline) else { continue }
            let before = opens > 0 ? characters[opens - 1] : nil
            let after = closes + 2 < characters.count ? characters[closes + 2] : nil
            let openerRefused = isPunctuation(first) && before.map(writesOn) == true
            let closerRefused = isPunctuation(last) && after.map(writesOn) == true
            if openerRefused || closerRefused { takenOver.append((opens, closes)) }
        }
        guard !takenOver.isEmpty else { return (text, false) }
        // From the end, so every earlier offset stays where it was.
        for pair in takenOver.reversed() {
            characters.replaceSubrange(pair.closes..<(pair.closes + 2), with: [boldCloses])
            characters.replaceSubrange(pair.opens..<(pair.opens + 2), with: [boldOpens])
        }
        return (String(characters), true)
    }

    /// Punctuation as CommonMark's flanking rule reads it: Unicode's
    /// punctuation and symbols.
    private static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    /// A letter of a script that writes its next word straight on.
    private static func writesOn(_ character: Character) -> Bool {
        character.isLetter && AskScripts.writesWordsWithoutSpaces(character)
    }
}
