#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
public import SwiftUI

/// The chip a reader tapped traveling to where their question lands, rather
/// than vanishing while a bubble appears somewhere else.
///
/// **A chip and the question it becomes are the same sentence twice.** The
/// bank sits leading in untinted glass and the question sits trailing in the
/// app's accent, so without the morph a tap reads as one thing disappearing
/// and an unrelated one arriving, and the reader has to find the sentence
/// again to see that nothing changed but its status. Matching their geometry
/// carries it across, and the color cross-fades on the way.
///
/// **Keyed on the sentence, not on an identity either end owns.** The chip
/// belongs to the turn above and the bubble to the turn being appended, so
/// there is no id in common: the chip's `AskStarter.id` doesn't survive into
/// `AskTurn`, and the turn's `UUID` doesn't exist while the chip does. What
/// both hold is the text (`store.ask($0.text, …)` is the whole of the
/// journey), so that is the join.
///
/// That makes uniqueness the thing to watch, and it is why
/// `matches(_:isNewest:)` exists rather than every bubble opting in. A thread
/// that asked the same question twice would otherwise hold two views claiming
/// one id, and `matchedGeometryEffect` resolves that by picking one: the wrong
/// one, half the time, with a bubble flying up the thread from a turn six
/// back. Only the newest turn takes an id, and only while it is in flight.
/// Chips only ever exist on the newest turn, but that includes its own
/// follow-ups, which come up once its answer lands, and a model can offer the
/// very question it was asked. So the bubble lets the id go before they can
/// claim it, and at most one pair is ever in flight.
nonisolated enum AskChipMorph {

    /// The geometry id a chip and its question share.
    ///
    /// Namespaced against the rest of the screen: `matchedGeometryEffect` ids
    /// live in one flat space per namespace, and a bare question is a string a
    /// host could plausibly use for something of its own.
    static func id(for text: String) -> String { "ask.chip.\(text)" }

    /// Whether a turn is the one a chip could have just become: the newest,
    /// still in flight, and tapped from the follow-ups under the answer above
    /// it.
    ///
    /// **In flight, and no longer.** The journey is over by the time the
    /// answer lands, and the follow-ups that come up under it share the
    /// namespace. Nothing takes out a follow-up that repeats the question, so
    /// a bubble that kept its id past that point would share it with a chip,
    /// and either could take the other's frame. "Ask again" asks as a
    /// follow-up too, so its turns hold the id on the same terms.
    ///
    /// **`.starter` is deliberately out.** A starter is a chip that becomes a
    /// question too, so it reads like the same journey, but the first screen
    /// doesn't stay to watch. It leaves on a `.blurReplace` (`AskScreen`) in
    /// the same transaction, so the morph would carry one capsule across a
    /// screen dissolving behind it: two motions competing rather than one
    /// continuing. Whether that wants a morph at all is a question about the
    /// first screen's exit, not about chips. The coaching pair under a failure
    /// asks as `.starter` too, and its bank is given no namespace.
    ///
    /// `.typed` and `.prefilled` have no chip on screen to come from, and
    /// `.reroll` comes from "Another pick", which isn't a question and carries
    /// no morph.
    static func matches<Row: AskRow>(_ turn: AskTurn<Row>, isNewest: Bool) -> Bool {
        isNewest && !turn.isComplete && turn.origin == .followUp
    }
}

extension View {
    /// Ties a chip, or the question it becomes, to their shared geometry.
    ///
    /// `namespace` is nil where there is no morph to run: every bank but the
    /// follow-ups, and every question `AskChipMorph.matches(_:isNewest:)`
    /// turns down.
    func askChipMorph(_ text: String, in namespace: Namespace.ID?) -> some View {
        modifier(AskChipMorphEffect(id: AskChipMorph.id(for: text), shared: namespace))
    }
}

/// The geometry effect, applied whether there is a morph to run or not, so the
/// view under it stays one view when it starts or stops matching.
///
/// **Not an `if let`, which SwiftUI reads as two views**: the bubble with the
/// effect and the bubble without it. A question bubble stops matching in the
/// frame its answer lands, and a turn that stops being the newest in the
/// frame the next one is appended. Both are stage changes, inside
/// `AskScreen`'s animation, where a swap between the two views is a removal
/// and an insertion: the default opacity transition would fade one copy of
/// the bubble out over the other, just as the answer arrives, and close a
/// menu held open on it. Worked out from how SwiftUI treats a conditional,
/// not recorded on a device.
///
/// Without a morph the effect runs in a namespace of its own, where the view is
/// the only one with its id, so it has nothing to match and nothing moves.
private struct AskChipMorphEffect: ViewModifier {
    let id: String
    let shared: Namespace.ID?

    @Namespace private var alone

    func body(content: Content) -> some View {
        content.matchedGeometryEffect(id: id, in: shared ?? alone)
    }
}

#endif
