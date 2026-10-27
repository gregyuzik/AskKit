import Foundation

/// The one deep-link shape every host opens Ask with: `<scheme>://ask?q=<question>`.
///
/// **A link prefills; it never sends.** A URL can come from anywhere (a web
/// page, a message, a QR code), and a question that ran the moment it was
/// opened would be the app acting on words the reader never chose to send. The
/// host hands the question to `AskConversationStore.prefill(_:scope:send:)`
/// without `send`, the composer shows it with the keyboard up, and the reader
/// sends it.
///
/// Behind no platform gate: a widget or a complication can build the link on
/// a platform that never shows Ask.
nonisolated public enum AskLink {
    /// The URL's host component, which a host's router matches: `ask`.
    public static let host = "ask"
    /// The query item that carries the question.
    public static let questionItem = "q"

    /// A link that opens Ask with `question` in the composer, or with an empty
    /// composer when there is no question. The question is made what a link
    /// reads back (`question(from:scheme:)`): what the reader can't see goes,
    /// its line breaks become spaces, and it is trimmed and clamped to 500
    /// characters, each held to its first 16 Unicode scalars, as every
    /// question is (`AskPrompt.clampQuestion`). One left empty is left out.
    ///
    /// Nil for a scheme that isn't one: a letter, then letters, digits, `+`,
    /// `-` and `.` (RFC 3986), such as `askkitdemo`, never `askkitdemo://`.
    public static func url(scheme: String, question: String? = nil) -> URL? {
        // Checked here: `URLComponents` traps on a scheme it can't hold
        // rather than leaving the URL nil.
        guard isScheme(scheme) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let question {
            let visible = visibleQuestion(question)
            if !visible.isEmpty {
                components.queryItems = [URLQueryItem(name: questionItem, value: visible)]
            }
        }
        return components.url
    }

    /// Whether `url` is an Ask link for `scheme` at all, with or without a
    /// question. The scheme and the URL's host are compared without regard to
    /// case.
    public static func matches(_ url: URL, scheme: String) -> Bool {
        guard let urlScheme = url.scheme, urlScheme.caseInsensitiveCompare(scheme) == .orderedSame else {
            return false
        }
        return url.host(percentEncoded: false)?.lowercased() == host
    }

    /// The question an Ask link carries as the composer may show it, or nil
    /// when the link carries none, or isn't an Ask link for `scheme`.
    ///
    /// **Only what the reader can see.** The words are neither the reader's
    /// nor the host's, and the reader sends what the composer shows, so
    /// whatever it wouldn't show goes first: tag characters that spell words
    /// in no glyph, the other invisible format characters, and bidi controls
    /// that draw text in another order than it is sent. The joiners and the
    /// variation selectors stay where text puts them, and so do the tags of
    /// England's, Scotland's and Wales's flags. Line breaks become spaces,
    /// since the composer shows a few lines at a time and a question is one.
    /// Then it is trimmed and clamped to 500 characters, each held to its
    /// first 16 Unicode scalars (`AskPrompt.clampQuestion`), so the limit
    /// counts what is sent.
    public static func question(from url: URL, scheme: String) -> String? {
        guard matches(url, scheme: scheme),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == questionItem })?.value else { return nil }
        let visible = visibleQuestion(raw)
        return visible.isEmpty ? nil : visible
    }

    /// A question as a link carries it: visible, one line, clamped. Made
    /// visible again once clamped, so a cut can never leave part of a
    /// sequence the first pass kept whole.
    static func visibleQuestion(_ raw: String) -> String {
        let oneLine = AskPrompt.droppingInvisibles(raw).split(whereSeparator: \.isNewline).joined(separator: " ")
        return AskPrompt.droppingInvisibles(AskPrompt.clampQuestion(oneLine))
    }

    /// Whether `scheme` can be a URL's scheme: an ASCII letter, then ASCII
    /// letters, digits, `+`, `-` and `.`.
    static func isScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else { return false }
        return scheme.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "+-.".unicodeScalars.contains(scalar))
        }
    }
}
