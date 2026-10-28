#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// What the wait row says, for an activity the domain did not name itself.
///
/// **The domain gets first refusal.** `AskDomain.phrase(for:)` returns nil for
/// anything it has no better word for, and these are the fallbacks: true for
/// every host, and worded so no host has to override them just to sound right.
///
/// "Thinking…" is the only line that isn't a report of something that
/// happened. It stands wherever no event has anything more specific to say:
/// before the model reaches for anything, while it composes once its tools
/// have gone idle, for a search or a read with no scope, and for a custom
/// activity the domain doesn't word. Every other line here corresponds to a
/// real event.
///
/// There is no "Writing…": the wait row is gone by then. The frame the first
/// words land it gives way to the prose, and the caret at the last glyph is what
/// says the writing is still going.
nonisolated enum AskActivityPhrase {

    static func text<Domain: AskDomain>(
        for activity: AskActivity?,
        domain: Domain
    ) -> String {
        guard let activity else { return thinking }
        if let own = domain.phrase(for: activity) { return own }
        return fallback(for: activity)
    }

    static func fallback(for activity: AskActivity) -> String {
        switch activity {
        case .searching(let scope):
            guard let scope else { return thinking }
            return String(
                localized: "Searching your \(scope)…",
                bundle: #bundle,
                comment: "Ask wait row while a tool looks through one part of the reader's library — the placeholder is that part's name."
            )
        case .reading(_, _, let scope):
            guard let scope else { return thinking }
            return String(
                localized: "Reading \(scope)…",
                bundle: #bundle,
                comment: "Ask wait row while the model reads what a tool found — the placeholder names what is being read."
            )
        case .custom:
            return thinking
        case .restarted:
            return String(
                localized: "Starting over…",
                bundle: #bundle,
                comment: "Ask wait row when a turn threw away what it had and began again — because the model answered without reading anything, because the tier serving it went out, or because a follow-up outgrew the model's context and is being asked again on a fresh session."
            )
        }
    }

    static var thinking: String {
        String(
            localized: "Thinking…",
            bundle: #bundle,
            comment: "Ask wait row wherever nothing more specific is happening: before the model has reached for anything, while it composes its answer once its tools have gone quiet, during a search or a read that names no part of the reader's things, and for an activity the app gives no words of its own. The only line here that is not a report of an event."
        )
    }
}

#endif
