#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The key phases the composer's field handles a Return in
/// (`AskComposerReturn.phases`).
@Suite(.timeLimit(.minutes(1))) struct AskComposerReturnPhasesTests {
    /// **A held Return's repeats are taken too.** A repeat is a phase of its
    /// own, and a handler for the press alone lets each through to the field:
    /// in an empty composer the first press is taken and the repeats type
    /// newlines, a draft of blank lines the store takes for a question begun.
    @Test func aHeldReturnsRepeatsAreHandledAsThePressIs() {
        #expect(AskComposerReturn.phases.contains(.down))
        #expect(AskComposerReturn.phases.contains(.repeat))
    }

    /// The release isn't a keystroke the field would act on twice.
    @Test func theReleaseIsNotHandled() {
        #expect(!AskComposerReturn.phases.contains(.up))
    }

    /// A repeat meets the draft the press left behind: a send has emptied it,
    /// so the held key sends once and then types nothing.
    @Test func aRepeatAfterASendHasNothingLeftToSend() {
        #expect(AskComposerReturn.of(shift: false, draft: "What's the oldest?", isThinking: false) == .send)
        #expect(AskComposerReturn.of(shift: false, draft: "", isThinking: false) == .nothing)
    }
}

#endif
