#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Testing

@testable import AskUI

/// Which line a first screen closes on, and whether Apple Intelligence's glyph
/// stands beside it (`AskFirstScreenDisclosure`).
///
/// Pinned here because the mistake is silent: a line saying Apple Intelligence
/// answers, under a reason saying it can't serve, over chips the domain's own
/// data answers. A host shipped exactly that under "Apple Intelligence doesn't
/// support this language yet." in eight languages' store screenshots.
@Suite(.timeLimit(.minutes(1))) struct AskFirstScreenDisclosureTests {

    private let tiers = "Answered by Apple Intelligence."
    private let ownData = "Answered from your shelf, on this device."

    private var tiersLine: AskFirstScreenDisclosure {
        AskFirstScreenDisclosure(text: tiers, showsAppleIntelligenceGlyph: true)
    }

    private func line(
        _ phase: AskStage.Phase, withoutModel: String?, answersWithoutModel: Bool
    ) -> AskFirstScreenDisclosure? {
        let brand = AskBrand(
            title: "Ask the Shelf", appDirectory: "AskKitTests", logSubsystem: "AskKit.tests",
            help: "Ask about your shelf", firstScreenHeadline: "Ask about your shelf",
            firstScreenSentence: "Some answers need no model.",
            disclosureSentence: tiers, disclosureSentenceWithoutModel: withoutModel,
            scopeCaveat: "It can be wrong."
        )
        return AskFirstScreenDisclosure(phase: phase, brand: brand, answersWithoutModel: answersWithoutModel)
    }

    /// Where a tier serves, the tiers' line and its glyph, whether or not the
    /// domain answers without a model, and whatever the brand says for that.
    @Test func theReadyScreenClosesOnTheTiersLine() {
        for answersWithoutModel in [false, true] {
            for withoutModel in [nil, ownData] {
                #expect(
                    line(.ready, withoutModel: withoutModel, answersWithoutModel: answersWithoutModel) == tiersLine,
                    "\(answersWithoutModel) \(withoutModel ?? "nil")"
                )
            }
        }
    }

    /// Where nothing serves, for every reason, a domain that answers without
    /// a model closes on its own line with no glyph: its own data answers
    /// every question there, and no tier does.
    @Test(arguments: AskUnavailability.allCases)
    func aDomainThatAnswersWithoutAModelClosesOnItsOwnLine(why: AskUnavailability) {
        #expect(
            line(.cannotServe(why), withoutModel: ownData, answersWithoutModel: true)
                == AskFirstScreenDisclosure(text: ownData, showsAppleIntelligenceGlyph: false)
        )
    }

    /// A brand with no such line keeps the tiers' there, as it was. So does a
    /// domain that needs a model, whatever its brand says: its composer is
    /// off, and nothing of its own answers under the reason.
    @Test func withoutTheLineOrWithoutTheDomainsAnswersTheTiersLineStays() {
        for why in [AskUnavailability.languageNotSupported, .appleIntelligenceOff] {
            #expect(line(.cannotServe(why), withoutModel: nil, answersWithoutModel: true) == tiersLine)
            #expect(line(.cannotServe(why), withoutModel: ownData, answersWithoutModel: false) == tiersLine)
        }
    }

    /// The nothing-to-ask screen and the thread close on no line.
    @Test func theOtherPhasesCloseOnNone() {
        for phase in [AskStage.Phase.nothingToAskAbout, .thread] {
            #expect(line(phase, withoutModel: ownData, answersWithoutModel: true) == nil)
        }
    }
}

#endif
