#if os(iOS) || os(macOS) || os(visionOS)

import AskCore

/// The line a first screen closes on: the host's sentence, and whether Apple
/// Intelligence's glyph stands beside it.
///
/// **What it says is what answers there.** The ready screen's line is the
/// brand's `disclosureSentence`, which says where a question goes: a tier
/// serves. On the screen that can't serve no tier does, and a domain that
/// answers without a model (`AskDomain.answersWithoutModel`) answers there
/// itself, so its brand's `disclosureSentenceWithoutModel` takes the line's
/// place, without the glyph. A brand with none keeps `disclosureSentence` and
/// its glyph, as does a domain that needs a model, whose composer is off
/// there.
///
/// Keyed on whether the domain answers without a model, not on its starters:
/// with none to show, its composer is still live, and still answered by the
/// domain alone.
nonisolated struct AskFirstScreenDisclosure: Equatable {
    /// The host's sentence, from its brand.
    let text: String
    /// Whether the `apple.intelligence` glyph stands beside it: beside
    /// `disclosureSentence` only, never beside the line of a domain answering
    /// without a model.
    let showsAppleIntelligenceGlyph: Bool

    init(text: String, showsAppleIntelligenceGlyph: Bool) {
        self.text = text
        self.showsAppleIntelligenceGlyph = showsAppleIntelligenceGlyph
    }

    /// The line `phase`'s screen closes on, or nil for a phase that closes on
    /// none: the nothing-to-ask screen and the thread.
    init?(phase: AskStage.Phase, brand: AskBrand, answersWithoutModel: Bool) {
        switch phase {
        case .ready:
            self.init(text: brand.disclosureSentence, showsAppleIntelligenceGlyph: true)
        case .cannotServe:
            if answersWithoutModel, let line = brand.disclosureSentenceWithoutModel {
                self.init(text: line, showsAppleIntelligenceGlyph: false)
            } else {
                self.init(text: brand.disclosureSentence, showsAppleIntelligenceGlyph: true)
            }
        case .nothingToAskAbout, .thread:
            return nil
        }
    }
}

#endif
