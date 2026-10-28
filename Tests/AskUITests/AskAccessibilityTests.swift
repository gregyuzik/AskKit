#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Testing

@testable import AskUI

/// One namespace for every host, so one UI-test recipe drives them all
/// (`AskAccessibility`). This pins every one it lists: one `ask.` prefix, and
/// no two alike (`newChat` and `clear` share one string on purpose, so only
/// `clear` is listed). A rename inside the namespace still passes here, and
/// breaks any host's test that spells the old string. Add a new identifier
/// here as it is added there.
@Suite(.timeLimit(.minutes(1))) struct AskAccessibilityTests {
    @Test func identifiersShareOneNamespace() {
        let all = [
            AskAccessibility.root,
            AskAccessibility.question,
            AskAccessibility.answer,
            AskAccessibility.send,
            AskAccessibility.slotField,
            AskAccessibility.slotSend,
            AskAccessibility.attach,
            AskAccessibility.thinking,
            AskAccessibility.results,
            AskAccessibility.clear,
            AskAccessibility.done,
            AskAccessibility.retry,
            AskAccessibility.jumpToLatest,
            AskAccessibility.starters,
            AskAccessibility.followUps,
            AskAccessibility.coaching,
            AskAccessibility.anotherPick,
            AskAccessibility.basis,
            AskAccessibility.feedbackPositive,
            AskAccessibility.feedbackNegative,
            AskAccessibility.history,
            AskAccessibility.historyList,
            AskAccessibility.historyClose,
            AskAccessibility.historyCurrent,
            AskAccessibility.historyRow,
            AskAccessibility.historyDelete,
            AskAccessibility.historyDeleteAll,
            AskAccessibility.historyDeleteAllConfirm,
            AskAccessibility.historyPane,
            AskAccessibility.proposal,
            AskAccessibility.proposalConfirm,
            AskAccessibility.proposalDecline,
            AskAccessibility.proposalOutcome,
            AskAccessibility.pendingPhoto,
            AskAccessibility.removePhoto,
            AskAccessibility.questionPhoto,
            AskAccessibility.photoUnread,
            AskAccessibility.field,
            AskAccessibility.questionCopy,
            AskAccessibility.questionCopyAnswer,
            AskAccessibility.questionEdit,
            AskAccessibility.questionAskAgain,
            AskAccessibility.evidence,
            AskAccessibility.declineSuggestion,
            AskAccessibility.tryAsking,
            AskAccessibility.nothingAction,
            AskAccessibility.quotaShowOptions,
            AskAccessibility.privateCloudShowOptions,
            AskAccessibility.privateCloudRunEval,
            AskAccessibility.privateCloudShareResults,
            AskAccessibility.privateCloudShareFeedback
        ]
        #expect(all.allSatisfy { $0.hasPrefix("ask.") })
        #expect(Set(all).count == all.count)
        #expect(AskAccessibility.newChat == AskAccessibility.clear)
    }
}

/// Text and glyphs on glass at the contrast their size needs
/// (`AskGlassForeground`), and glyphs and words on the host's accent, white
/// until it falls under 3:1 (`AskOnAccent`, `AskOnAccentLabel`). WCAG 2's
/// arithmetic, on grounds AskUI estimates rather than measures.
@Suite(.timeLimit(.minutes(1))) struct AskContrastTests {
    private let systemBlue = AskContrast.RGB(red: 0, green: 136 / 255, blue: 1)

    /// The arithmetic agrees with WCAG's own end points and with the figures
    /// `askDeemphasizedText` was measured at.
    @Test func theRatioIsWCAGs() {
        #expect(abs(AskContrast.ratio(.white, .black) - 21) < 0.01)
        #expect(AskContrast.ratio(.white, .white) == 1)
        #if !os(macOS)
        let secondary = AskContrast.secondary(isLight: true)
        let onWhite = AskContrast.over(secondary.color, opacity: secondary.opacity, .white)
        #expect(abs(AskContrast.ratio(onWhite, .white) - 3.44) < 0.05)
        #endif
    }

    /// **Text on glass in light mode reads `.primary`.** `.secondary` is under
    /// 4.5:1 even on white, and on the composer's capsule, the system blue at
    /// half strength, it is 2.66:1, under a glyph's 3:1 too.
    @Test func lightGlassTakesPrimaryText() {
        let tint = AskContrast.Tint(systemBlue, opacity: 0.5)
        #expect(!AskContrast.secondaryClears(AskGlassForeground.text, isLight: true, tint: nil))
        #expect(!AskContrast.secondaryClears(AskGlassForeground.text, isLight: true, tint: tint))
        #if !os(macOS)
        #expect(!AskContrast.secondaryClears(AskGlassForeground.glyph, isLight: true, tint: tint))
        #endif
        // A glyph on untinted light glass clears 3:1 as it is.
        #expect(AskContrast.secondaryClears(AskGlassForeground.glyph, isLight: true, tint: nil))
    }

    /// In dark mode `.secondary` stays on untinted glass and on a dark accent's
    /// tint, and goes on a light one's.
    @Test func darkGlassKeepsSecondaryUnlessTheTintIsLight() {
        let navy = AskContrast.Tint(AskContrast.RGB(red: 26 / 255, green: 35 / 255, blue: 126 / 255), opacity: 0.5)
        let blue = AskContrast.Tint(systemBlue, opacity: 0.5)
        #expect(AskContrast.secondaryClears(AskGlassForeground.text, isLight: false, tint: nil))
        #expect(AskContrast.secondaryClears(AskGlassForeground.text, isLight: false, tint: navy))
        #expect(!AskContrast.secondaryClears(AskGlassForeground.text, isLight: false, tint: blue))
    }

    /// **White on the accent until it falls under 3:1, then black.** The
    /// system blue keeps its white arrow; a yellow or a mint accent takes a
    /// black one.
    @Test func aGlyphOnTheAccentIsBlackOnlyWhereWhiteFails() {
        let glyph = AskGlassForeground.glyph
        #expect(!AskContrast.prefersBlack(on: systemBlue, minimum: glyph))
        #expect(!AskContrast.prefersBlack(on: AskContrast.RGB(red: 0, green: 122 / 255, blue: 1), minimum: glyph))
        #expect(!AskContrast.prefersBlack(on: .black, minimum: glyph))
        #expect(AskContrast.prefersBlack(on: AskContrast.RGB(red: 1, green: 204 / 255, blue: 0), minimum: glyph))
        #expect(AskContrast.prefersBlack(on: AskContrast.RGB(red: 0, green: 199 / 255, blue: 190 / 255), minimum: glyph))
        #expect(AskContrast.prefersBlack(on: .white, minimum: glyph))
    }

    /// **Words on the accent are white, as the system's prominent buttons draw
    /// them, until white falls under 3:1.** White is 3.52:1 on the system blue,
    /// 3.23:1 on its dark #0091FF and 4.02:1 on #007AFF, where black would be
    /// 5.97:1, 6.49:1 and 5.23:1, and all three labels stay white; yellow and
    /// mint, where white is under 3:1, take black. The bar is a glyph's, not
    /// text on glass's 4.5:1.
    @Test func wordsOnTheAccentAreWhiteWhereWhiteHoldsThreeToOne() {
        let bar = AskContrast.whiteLabelMinimum
        let blue = AskContrast.RGB(red: 0, green: 122 / 255, blue: 1)
        let darkBlue = AskContrast.RGB(red: 0, green: 145 / 255, blue: 1)
        let navy = AskContrast.RGB(red: 26 / 255, green: 35 / 255, blue: 126 / 255)
        let yellow = AskContrast.RGB(red: 1, green: 204 / 255, blue: 0)
        let mint = AskContrast.RGB(red: 0, green: 199 / 255, blue: 190 / 255)
        #expect(bar == 3)
        #expect(bar == AskGlassForeground.glyph)
        #expect(bar < AskGlassForeground.text)
        #expect(abs(AskContrast.ratio(.white, systemBlue) - 3.52) < 0.01)
        #expect(abs(AskContrast.ratio(.black, systemBlue) - 5.97) < 0.01)
        #expect(abs(AskContrast.ratio(.white, darkBlue) - 3.23) < 0.01)
        #expect(abs(AskContrast.ratio(.white, blue) - 4.02) < 0.01)
        #expect(abs(AskContrast.ratio(.black, blue) - 5.23) < 0.01)
        #expect(!AskContrast.prefersBlack(on: systemBlue, minimum: bar))
        #expect(!AskContrast.prefersBlack(on: blue, minimum: bar))
        #expect(!AskContrast.prefersBlack(on: darkBlue, minimum: bar))
        #expect(!AskContrast.prefersBlack(on: navy, minimum: bar))
        #expect(!AskContrast.prefersBlack(on: .black, minimum: bar))
        #expect(AskContrast.prefersBlack(on: yellow, minimum: bar))
        #expect(AskContrast.prefersBlack(on: mint, minimum: bar))
        #expect(AskContrast.prefersBlack(on: .white, minimum: bar))
        // A glyph and a label take the same color on every accent here.
        #expect(AskContrast.prefersBlack(on: yellow, minimum: AskGlassForeground.glyph))
        #expect(!AskContrast.prefersBlack(on: systemBlue, minimum: AskGlassForeground.glyph))
    }

    /// **The threshold sits at white's 3:1**, between the grays #949494, where
    /// white is 3.03:1, and #959595, where it is 2.995:1; and on every gray the
    /// label is white exactly where white holds the bar and holds the bar
    /// itself, black being over 7:1 wherever white is under 3:1.
    @Test func theLabelTurnsBlackAtWhiteThreeToOne() {
        let bar = AskContrast.whiteLabelMinimum
        let at148 = AskContrast.RGB(red: 148 / 255, green: 148 / 255, blue: 148 / 255)
        let at149 = AskContrast.RGB(red: 149 / 255, green: 149 / 255, blue: 149 / 255)
        #expect(abs(AskContrast.ratio(.white, at148) - 3.03) < 0.01)
        #expect(abs(AskContrast.ratio(.white, at149) - 2.995) < 0.001)
        #expect(!AskContrast.prefersBlack(on: at148, minimum: bar))
        #expect(AskContrast.prefersBlack(on: at149, minimum: bar))

        for step in 0...255 {
            let value = Double(step) / 255
            let accent = AskContrast.RGB(red: value, green: value, blue: value)
            let label: AskContrast.RGB = AskContrast.prefersBlack(on: accent, minimum: bar) ? .black : .white
            #expect(AskContrast.ratio(label, accent) >= bar, "gray \(step)")
            #expect((label == .white) == (AskContrast.ratio(.white, accent) >= bar), "gray \(step)")
        }
    }

    /// **The light deemphasized gray is pinned**: iOS's secondary label hue at
    /// 76%, where `.secondary` is 60% and under 4.5:1 on a light ground. Apple's
    /// audit passes this strength and not the 60% or the 68% before it
    /// (`testTheScreenPassesApplesAccessibilityAudit`).
    @Test func theLightDeemphasizedGrayHoldsTheBarWhereSecondaryDoesNot() {
        let gray = AskContrast.deemphasizedLight
        #expect(gray.color == AskContrast.RGB(red: 60 / 255, green: 60 / 255, blue: 67 / 255))
        #expect(gray.opacity == 0.76)
        let grouped = AskContrast.RGB(red: 242 / 255, green: 242 / 255, blue: 247 / 255)
        let onWhite = AskContrast.over(gray.color, opacity: gray.opacity, .white)
        let onGrouped = AskContrast.over(gray.color, opacity: gray.opacity, grouped)
        #expect(abs(AskContrast.ratio(onWhite, .white) - 5.31) < 0.01)
        #expect(abs(AskContrast.ratio(onGrouped, grouped) - 4.98) < 0.01)
        #expect(gray.opacity > AskContrast.secondary(isLight: true).opacity)
        #expect(!AskContrast.secondaryClears(AskGlassForeground.text, isLight: true, tint: nil))
    }

    // MARK: The question bubble and the composer on a light accent

    private let yellow = AskContrast.RGB(red: 1, green: 214 / 255, blue: 10 / 255)
    private let mint = AskContrast.RGB(red: 99 / 255, green: 230 / 255, blue: 226 / 255)
    private let cyan = AskContrast.RGB(red: 100 / 255, green: 210 / 255, blue: 1)
    private let indigo = AskContrast.RGB(red: 94 / 255, green: 92 / 255, blue: 230 / 255)

    private func bubble(_ accent: AskContrast.RGB) -> AskContrast.Tint {
        AskContrast.Tint(accent, opacity: AskQuestionBubble.fillOpacity)
    }

    /// The words on the fill, as the bubble draws them: `.primary` or its
    /// opposite, black or white.
    private func words(on accent: AskContrast.RGB, isLight: Bool) -> AskContrast.RGB {
        let inverse = AskOnFill.isInverse(fill: bubble(accent), isLight: isLight)
        return AskContrast.primary(isLight: inverse ? !isLight : isLight)
    }

    private func ground(_ accent: AskContrast.RGB, isLight: Bool) -> AskContrast.RGB {
        AskContrast.over(accent, opacity: AskQuestionBubble.fillOpacity, AskContrast.screen(isLight: isLight))
    }

    /// **A question's words turn black on a light accent in dark mode, and stay
    /// `.primary` everywhere else.** White on yellow, mint or cyan at the
    /// bubble's 60% falls under 4.5:1 over a dark screen, where black clears
    /// it; the system blue holds white, and in light mode black holds on every
    /// accent, indigo the darkest of them.
    @Test func aQuestionsWordsAreBlackOnALightAccentInDarkMode() {
        #expect(AskQuestionBubble.fillOpacity == 0.6)
        for accent in [yellow, mint, cyan] {
            #expect(AskOnFill.isInverse(fill: bubble(accent), isLight: false))
            #expect(AskContrast.ratio(.white, ground(accent, isLight: false)) < AskGlassForeground.text)
        }
        #expect(!AskOnFill.isInverse(fill: bubble(systemBlue), isLight: false))
        #expect(!AskOnFill.isInverse(fill: bubble(indigo), isLight: false))
        for accent in [systemBlue, yellow, mint, cyan, indigo] {
            #expect(!AskOnFill.isInverse(fill: bubble(accent), isLight: true))
        }
        #expect(abs(AskContrast.ratio(.white, ground(systemBlue, isLight: false)) - 6.68) < 0.01)
        #expect(abs(AskContrast.ratio(.black, ground(systemBlue, isLight: true)) - 9.83) < 0.01)
        #expect(abs(AskContrast.ratio(.white, ground(yellow, isLight: false)) - 3.29) < 0.01)
        #expect(abs(AskContrast.ratio(.black, ground(yellow, isLight: false)) - 6.38) < 0.01)
        #expect(abs(AskContrast.ratio(.black, ground(indigo, isLight: true)) - 8.56) < 0.01)
    }

    /// Whichever color the rule draws, a question's words hold 4.5:1 on the
    /// fill of every accent measured, in both appearances, and on a sweep of
    /// grays, which run the whole range of light to dark.
    @Test func aQuestionsWordsHoldTheTextBarOnEveryAccent() {
        let accents = [systemBlue, yellow, mint, cyan, indigo] + stride(from: 0, through: 255, by: 15).map { step in
            AskContrast.RGB(red: Double(step) / 255, green: Double(step) / 255, blue: Double(step) / 255)
        }
        for accent in accents {
            for isLight in [true, false] {
                let held = AskContrast.ratio(words(on: accent, isLight: isLight), ground(accent, isLight: isLight))
                #expect(held >= AskGlassForeground.text, "\(accent), light \(isLight): \(held)")
            }
        }
    }

    /// **The composer's tint gives way on a light accent in dark mode**, so
    /// its white words keep 4.5:1, and every other accent keeps half.
    @Test func theComposersTintGivesWayOnALightAccentInDarkMode() {
        #expect(AskComposer.tint == 0.5)
        #if !os(visionOS)
        #expect(AskComposer.tint(for: yellow, isLight: false) == 0.43)
        #expect(AskComposer.tint(for: mint, isLight: false) == 0.45)
        #expect(AskComposer.tint(for: cyan, isLight: false) == 0.49)
        #expect(AskComposer.tint(for: systemBlue, isLight: false) == 0.5)
        #expect(AskComposer.tint(for: indigo, isLight: false) == 0.5)
        for accent in [systemBlue, yellow, mint, cyan, indigo] {
            #expect(AskComposer.tint(for: accent, isLight: true) == 0.5)
        }
        // At the tint it gives way to, the words clear the bar, and a hundredth
        // more and they wouldn't.
        let worn = AskContrast.ground(isLight: false, tint: AskContrast.Tint(yellow, opacity: 0.43))
        let over = AskContrast.ground(isLight: false, tint: AskContrast.Tint(yellow, opacity: 0.44))
        #expect(AskContrast.ratio(.white, worn) >= AskGlassForeground.text)
        #expect(AskContrast.ratio(.white, over) < AskGlassForeground.text)
        #endif
    }

    /// On every gray, the composer's words keep 4.5:1 on the tint it chooses,
    /// light or dark.
    @Test func theComposersWordsHoldTheTextBarOnEveryGray() {
        #if !os(visionOS)
        for step in stride(from: 0, through: 255, by: 5) {
            let gray = AskContrast.RGB(red: Double(step) / 255, green: Double(step) / 255, blue: Double(step) / 255)
            for isLight in [true, false] {
                let tint = AskComposer.tint(for: gray, isLight: isLight)
                let ground = AskContrast.ground(isLight: isLight, tint: AskContrast.Tint(gray, opacity: tint))
                #expect(AskContrast.ratio(AskContrast.primary(isLight: isLight), ground) >= AskGlassForeground.text, "gray \(step)")
            }
        }
        #endif
    }
}

/// What Voice Control answers to on an element that shows words
/// (`AskSpokenName`).
@Suite(.timeLimit(.minutes(1))) struct AskSpokenNameTests {
    /// The opening is the first four words as the text spells them, without
    /// what follows the fourth.
    @Test func theOpeningIsTheFirstFourWords() {
        #expect(AskSpokenName.opening(of: "What's the oldest thing I have?") == "What's the oldest thing")
        #expect(AskSpokenName.opening(of: "Which records, if any, are signed?") == "Which records, if any")
        #expect(AskSpokenName.opening(of: "Oldest book?") == "Oldest book")
        #expect(AskSpokenName.opening(of: "") == "")
    }

    /// Text written without spaces is still divided into words.
    @Test func textWithoutSpacesStillYieldsWords() {
        let question = "一番古い本はどれですか"
        let opening = AskSpokenName.opening(of: question)
        #expect(!opening.isEmpty)
        #expect(opening.count < question.count)
        #expect(question.hasPrefix(opening))
    }

    /// The opening leads, then the whole where it is longer; a short text is
    /// itself once, and nothing shown adds nothing.
    @Test func theOpeningLeadsThenTheWhole() {
        #expect(AskSpokenName.words(opening: "What's the oldest thing", whole: "What's the oldest thing I have?")
            == ["What's the oldest thing", "What's the oldest thing I have?"])
        #expect(AskSpokenName.words(opening: "Oldest book", whole: "Oldest book") == ["Oldest book"])
        #expect(AskSpokenName.words(opening: "", whole: "").isEmpty)
        #expect(AskSpokenName.words(opening: "", whole: "?!") == ["?!"])
    }
}

/// Two localized sentences joined into one line (`AskSentences`).
@Suite(.timeLimit(.minutes(1))) struct AskSentencesTests {
    /// A space after a sentence that ends in a mark that wants one.
    @Test func sentencesAreJoinedWithASpace() {
        #expect(AskSentences.joined("You've reached today's limit.", "It resets at 5:00 PM.")
            == "You've reached today's limit. It resets at 5:00 PM.")
        #expect(AskSentences.joined("Límite alcanzado.", "Se restablece a las 17:00.")
            == "Límite alcanzado. Se restablece a las 17:00.")
    }

    /// **No space after a full-width sentence end**, which carries its own:
    /// Japanese and Chinese run the next sentence on.
    @Test func noSpaceFollowsAFullWidthSentenceEnd() {
        #expect(AskSentences.joined("本日の上限に達しました。", "17:00にリセットされます。") == "本日の上限に達しました。17:00にリセットされます。")
        #expect(AskSentences.joined("已达到今日上限！", "将于17:00重置。") == "已达到今日上限！将于17:00重置。")
        #expect(AskSentences.joined("已達到今日上限？", "將於17:00重置。") == "已達到今日上限？將於17:00重置。")
    }

    /// An empty sentence adds nothing, not even the space.
    @Test func anEmptySentenceAddsNothing() {
        #expect(AskSentences.joined("", "It resets at 5:00 PM.") == "It resets at 5:00 PM.")
        #expect(AskSentences.joined("You've reached today's limit.", "") == "You've reached today's limit.")
    }
}

/// House rule 8: VoiceOver hears every terminal state. Which line it hears is
/// pinned here, because what was spoken is the one thing a screenshot can
/// never show.
@Suite(.timeLimit(.minutes(1))) struct AskAnnouncementTests {

    private func turn(_ question: String = "q") -> AskTurn<UIRow> {
        AskTurn<UIRow>(question: question, origin: .typed)
    }

    @Test func aTurnStillRunningSaysNothing() {
        var running = turn()
        running.write("half a sen", at: 0)
        #expect(AskAnnouncement.terminal(for: running) == nil)
        #expect(AskAnnouncement.terminal(for: AskTurn<UIRow>?.none) == nil)
    }

    @Test func aFinishedAnswerIsAnnouncedReady() {
        var done = turn()
        done.settle(AskAnswer(text: "done", matches: [UIRow("A")]), at: 0)
        #expect(AskAnnouncement.terminal(for: done) == "Answer ready")
    }

    @Test func aTruncatedAnswerSaysSoInsteadOfClaimingItIsReady() {
        var cut = turn()
        cut.settle(AskAnswer(text: "as far as it", matches: [], isTruncated: true), at: 0)
        #expect(AskAnnouncement.terminal(for: cut) == "Answer cut short")
    }

    /// The failure's own words, not a generic one — the reader who cannot see
    /// the row gets exactly what the row says.
    @Test func aFailureIsAnnouncedInItsOwnWords() {
        var failed = turn()
        failed.failure = AskTurn<UIRow>.Failure(message: "Couldn't answer that.", retryable: true)
        #expect(AskAnnouncement.terminal(for: failed) == "Couldn't answer that.")
    }

    /// A failure *under* prose still announces the failure: the turn said
    /// something and then broke, and "Answer ready" would be a lie.
    @Test func aFailureBeneathProseAnnouncesTheFailure() {
        var failed = turn()
        failed.write("Going by what you own,", at: 0)
        failed.failure = AskTurn<UIRow>.Failure(message: "Try again.", retryable: true)
        #expect(AskAnnouncement.terminal(for: failed) == "Try again.")
    }
}

/// Each thing VoiceOver is told, told once (`AskSpeechLedger`).
@Suite(.timeLimit(.minutes(1))) struct AskSpeechLedgerTests {
    /// **Two windows on one store hear a turn end, and one speaks.** The first
    /// screen to claim the ending speaks it; the second finds it claimed.
    @Test func aSecondScreenFindsTheEndingClaimed() {
        var ledger = AskSpeechLedger()
        let ending = UUID()
        let first = ledger.claim(.ending(ending))
        #expect(first)
        let second = ledger.claim(.ending(ending))
        #expect(!second)
        // Another turn's ending is its own.
        let another = ledger.claim(.ending(UUID()))
        #expect(another)
    }

    /// **A failure line VoiceOver's focus lands on speaks the ending itself.**
    /// The line claims it as the focus lands (`AskFailureRow`'s
    /// `onLineFocused`), so a screen claiming after it says nothing over the
    /// line being read.
    @Test func aFailureLineTakingTheFocusSilencesTheAnnouncement() {
        var ledger = AskSpeechLedger()
        let ending = UUID()
        // The line's claim, `AskThreadRow`'s `onFailureTakesFocus`.
        _ = ledger.claim(.ending(ending))
        // The screen's announcement, after it.
        let announced = ledger.claim(.ending(ending))
        #expect(!announced)
        // Without a hand-off, the screen speaks.
        let unhanded = ledger.claim(.ending(UUID()))
        #expect(unhanded)
    }

    /// The quota's line is spoken once while it is spent, and again once it
    /// has come back and been spent again.
    @Test func theQuotasLineIsSpokenOnceEachTimeItIsSpent() {
        var ledger = AskSpeechLedger()
        let spent = ledger.claim(.quotaReached)
        #expect(spent)
        let again = ledger.claim(.quotaReached)
        #expect(!again)
        ledger.forget(.quotaReached)
        let spentAgain = ledger.claim(.quotaReached)
        #expect(spentAgain)
    }

    /// **An outcome line VoiceOver's focus lands on claims the store's newest
    /// announcement**, where the line says its words: what a screen would
    /// otherwise post over the line being read.
    @Test func anOutcomeLineHeardClaimsTheNewestAnnouncementOfItsWords() throws {
        let newest = AskProposalAnnouncement(line: "That's done")
        let heard = try #require(AskSpeechLedger.Line.proposalOutcome(heard: "That's done", newest: newest))
        #expect(heard == .proposalOutcome(newest.id))

        var ledger = AskSpeechLedger()
        _ = ledger.claim(heard)
        let announced = ledger.claim(.proposalOutcome(newest.id))
        #expect(!announced)
    }

    /// An older card's line the reader passes, saying other words, claims
    /// nothing, and with no announcement there is nothing to claim.
    @Test func anOutcomeLineOfOtherWordsClaimsNothing() {
        let newest = AskProposalAnnouncement(line: "That's done")
        #expect(AskSpeechLedger.Line.proposalOutcome(heard: "Not done", newest: newest) == nil)
        #expect(AskSpeechLedger.Line.proposalOutcome(heard: "Not done", newest: nil) == nil)
    }

    /// **Each outcome is a line of its own**, a failure retried on the same
    /// card included: the second "That didn't work" is heard as the first was.
    @Test func eachOutcomeIsALineOfItsOwnThoughTheWordsRepeat() throws {
        let first = AskProposalAnnouncement(line: "That didn't work")
        let second = AskProposalAnnouncement(line: "That didn't work")
        var ledger = AskSpeechLedger()
        let firstHeard = try #require(AskSpeechLedger.Line.proposalOutcome(heard: first.line, newest: first))
        let firstClaimed = ledger.claim(firstHeard)
        #expect(firstClaimed)
        let secondHeard = try #require(AskSpeechLedger.Line.proposalOutcome(heard: second.line, newest: second))
        let secondClaimed = ledger.claim(secondHeard)
        #expect(secondClaimed)
    }

    /// It remembers a bounded number of lines, the oldest let go first.
    @Test func itRemembersABoundedNumberOfLines() {
        var ledger = AskSpeechLedger()
        let oldestEnding = UUID()
        let oldest = ledger.claim(.ending(oldestEnding))
        #expect(oldest)
        for _ in 0..<AskSpeechLedger.capacity {
            let newer = ledger.claim(.ending(UUID()))
            #expect(newer)
        }
        #expect(ledger.claimed.count == AskSpeechLedger.capacity)
        let oldestAgain = ledger.claim(.ending(oldestEnding))
        #expect(oldestAgain, "the oldest line has been let go")
    }
}

/// Which wait row takes VoiceOver's focus as it appears (`AskWaitRowFocus`).
@Suite(.timeLimit(.minutes(1))) struct AskWaitRowFocusTests {
    @Test func aFirstQuestionAskedWithNoRequestKeepsTheFocusWhereItIs() {
        // A typed first question: the reader is in the field, and the wait
        // row has no business taking them out of it.
        #expect(!AskWaitRowFocus.takes(nil, firstTurn: false, after: nil))
        #expect(!AskWaitRowFocus.takes(nil, firstTurn: false, after: UUID()))
    }

    @Test func aStarterTapFocusesTheFirstTurnsWaitRow() {
        #expect(AskWaitRowFocus.takes(nil, firstTurn: true, after: nil))
        #expect(!AskWaitRowFocus.takes(nil, firstTurn: true, after: UUID()), "only the thread's first turn")
    }

    @Test func aControlUnderATurnFocusesTheTurnAfterIt() {
        let turn = UUID()
        #expect(AskWaitRowFocus.takes(AskWaitRowFocus(after: turn), firstTurn: false, after: turn))
        #expect(!AskWaitRowFocus.takes(AskWaitRowFocus(after: turn), firstTurn: false, after: UUID()))
        #expect(!AskWaitRowFocus.takes(AskWaitRowFocus(after: turn), firstTurn: false, after: nil))
        // Try Again on the thread's first turn: its turn takes the failed
        // one's place, after nothing.
        #expect(AskWaitRowFocus.takes(AskWaitRowFocus(after: nil), firstTurn: false, after: nil))
    }
}

#endif
