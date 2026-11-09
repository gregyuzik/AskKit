#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// The one-line note under an answer that didn't finish. Not a failure: the
/// prose above it is real, kept by the rule a finished answer is kept by, just
/// unfinished.
///
/// **Two sentences for three causes.** `isTruncated` means "the deadline
/// stopped it", "the token cap stopped it" or "the reader stopped it", and
/// `AskTurn.stopped` tells the reader's stop from the other two, so the note
/// never blames the time limit for the reader's own Stop. The deadline and the
/// cap share "Answer cut short", which is true of both.
struct AskTruncatedNote: View {
    private let byReader: Bool

    init(byReader: Bool = false) {
        self.byReader = byReader
    }

    var body: some View {
        note
            .font(.caption)
            .askDeemphasizedText()
    }

    private var note: Text {
        byReader
            ? Text("You stopped this answer", bundle: #bundle, comment: "Note under an Ask answer the reader stopped before it finished.")
            : Text("Answer cut short", bundle: #bundle, comment: "Note under an Ask answer that was cut short before it finished: by the time limit, or by a stop the reader didn't ask for.")
    }
}

#endif
