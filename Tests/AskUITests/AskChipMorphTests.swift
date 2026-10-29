#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Testing

import AskCore
@testable import AskUI

/// The chip a reader tapped travelling to where their question lands.
///
/// The motion itself is SwiftUI's and is not testable here — it was measured on
/// the demo instead, frame by frame off a 60fps capture. What *is* testable is
/// the pair of decisions that decide whether a morph is even attempted, and
/// both have a way of going quietly wrong: an id that stops matching carries
/// nothing, and an id claimed by two turns at once carries the wrong thing.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskChipMorphTests {

    private func turn(_ question: String, origin: AskOrigin) -> AskTurn<UIRow> {
        AskTurn<UIRow>(question: question, origin: origin)
    }

    @Test func aChipAndItsQuestionShareAnID() {
        // The whole join. The chip belongs to the turn above and the bubble to
        // the turn being appended, so the text is the only thing both hold —
        // `store.ask($0.text, …)` is the entire journey between them.
        #expect(AskChipMorph.id(for: "What else is cozy?") == AskChipMorph.id(for: "What else is cozy?"))
        #expect(AskChipMorph.id(for: "What else is cozy?") != AskChipMorph.id(for: "What else is relaxing?"))
    }

    @Test func theIDIsNamespacedAgainstTheRestOfTheScreen() {
        // `matchedGeometryEffect` ids share one flat space per namespace, and a
        // bare question is a string a host could plausibly use for something of
        // its own.
        #expect(AskChipMorph.id(for: "x").hasPrefix("ask.chip."))
        #expect(AskChipMorph.id(for: "x") != "x")
    }

    @Test func onlyTheNewestTurnClaimsTheID() {
        // **Uniqueness is the thing that breaks.** A thread that asked the same
        // question twice would otherwise hold two bubbles claiming one id, and
        // `matchedGeometryEffect` resolves that by picking one — visibly the
        // wrong one, half the time, with a bubble flying up the thread from a
        // turn six back.
        let followUp = turn("Which one is the oldest?", origin: .followUp)
        #expect(AskChipMorph.matches(followUp, isNewest: true))
        #expect(!AskChipMorph.matches(followUp, isNewest: false))
    }

    @Test func aQuestionLetsTheIDGoOnceItsAnswerLands() {
        // **The newest turn's own follow-ups share the namespace.** They come
        // up under its answer once the answer has landed, and nothing stops
        // the model offering the question it was just asked, so a bubble that
        // kept the id past that point would share it with a chip. The chip it
        // came from is long gone by then: that journey ends while the turn is
        // in flight.
        var answered = turn("Which one is the oldest?", origin: .followUp)
        answered.answer = AskAnswer(text: "The Peregrine.")
        #expect(!AskChipMorph.matches(answered, isNewest: true))

        // A turn that failed, or that the reader stopped before a word, has
        // landed too.
        var failed = turn("Which one is the oldest?", origin: .followUp)
        failed.failure = AskTurn<UIRow>.Failure(message: "That didn't work", isRetryable: true)
        #expect(!AskChipMorph.matches(failed, isNewest: true))
    }

    @Test func onlyAQuestionWithAChipBehindItClaimsTheID() {
        // A typed question, a host-prefilled one and Another pick have no chip
        // on screen to come from.
        for origin in [AskOrigin.typed, .prefilled, .reroll] {
            #expect(!AskChipMorph.matches(turn("Anything", origin: origin), isNewest: true))
        }
    }

    @Test func aStarterDoesNotMorphAndThatIsDeliberate() {
        // A starter is a chip that becomes a question too, so this reads like
        // an omission and is not one: the first screen leaves through
        // `AskStage`'s own transition in the same transaction, so a morph would
        // carry one capsule across a screen dissolving behind it. Asserted so
        // that turning it on is a decision someone makes rather than a line
        // someone adds.
        #expect(!AskChipMorph.matches(turn("What records do I own?", origin: .starter), isNewest: true))
    }
}

#endif
