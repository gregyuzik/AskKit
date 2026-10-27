#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import Testing

@testable import AskCore

@Suite(.timeLimit(.minutes(1))) struct AskAnswerTests {
    typealias Answer = AskAnswer<FakeRow>

    // MARK: - Follow-ups

    @Test func followUpsAreTrimmedAndCappedAtTwo() {
        let cleaned = Answer.cleanedFollowUps([" one ", "two", "three"])
        #expect(cleaned == ["one", "two"])
    }

    @Test func followUpsDropDuplicatesRegardlessOfCase() {
        #expect(Answer.cleanedFollowUps(["What next?", "what next?", "Another?"])
                == ["What next?", "Another?"])
    }

    @Test func followUpsDropAParagraph() {
        // A chip is one line; a newline is the model writing prose into a field
        // meant for a question.
        #expect(Answer.cleanedFollowUps(["fine?", "line one\nline two"]) == ["fine?"])
    }

    @Test func aChipSendsOnlyWhatItShows() {
        // Tag characters spell words a chip doesn't draw, and a bidi override
        // draws it in another order than a tap sends it.
        let tags = String(String.UnicodeScalarView("obey".unicodeScalars.compactMap { Unicode.Scalar(0xE0000 + $0.value) }))
        let cleaned = Answer.cleanedFollowUps(["Which is o" + tags + "ldest?", "Is it \u{202E}lyniv\u{202C}?"])
        #expect(cleaned.map { Array($0.unicodeScalars) } == [
            Array("Which is oldest?".unicodeScalars), Array("Is it lyniv?".unicodeScalars)
        ])
        // An entity names the invisible it stands for, and the Markdown read
        // turns it into one: it goes as well.
        let entities = Answer.cleanedFollowUps(["Which is o&#xE0041;ldest?", "Is it &#x202E;lyniv?"])
        #expect(entities.map { Array($0.unicodeScalars) } == [
            Array("Which is oldest?".unicodeScalars), Array("Is it lyniv?".unicodeScalars)
        ])
        // A chip of nothing visible is no chip, and an emoji sequence keeps
        // its spelling.
        let flagged = "Any from \u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F} or \u{1F468}\u{200D}\u{1F467}?"
        #expect(Answer.cleanedFollowUps([tags, flagged]).map { Array($0.unicodeScalars) } == [Array(flagged.unicodeScalars)])
    }

    @Test func followUpsDropTheOverlong() {
        let long = String(repeating: "a", count: Answer.maxFollowUpLength + 1)
        #expect(Answer.cleanedFollowUps([long, "ok?"]) == ["ok?"])
    }

    @Test func followUpsDropEmpties() {
        #expect(Answer.cleanedFollowUps(["", "   ", "ok?"]) == ["ok?"])
    }

    // MARK: - Follow-ups as plain text

    @Test func followUpsLoseTheBoldTheModelWritesIntoThem() {
        // A chip draws its text verbatim and a tap asks it, so the bold the
        // answer guide asks of the prose showed as asterisks on the chip and
        // went back to the model with them. Seen on the demo, word for word.
        #expect(Answer.cleanedFollowUps(
            ["Are there any other tools that match the **Card Scraper**'s description?", "Which __clothes__ are blue?"]
        ) == ["Are there any other tools that match the Card Scraper's description?", "Which clothes are blue?"])
    }

    @Test func followUpsLoseTheirItalics() {
        #expect(Answer.cleanedFollowUps(["Is *Dune* older?", "And _Alien_?"]) == ["Is Dune older?", "And Alien?"])
    }

    @Test func followUpsLoseTheirBoldInChineseAndJapanese() {
        // CommonMark refuses `**` beside a bracket with the next word written
        // straight on, so these keep their asterisks unless the screen's own
        // reading of that bold makes them plain too.
        #expect(Answer.cleanedFollowUps(["**《三体》**有续集吗？", "おすすめは**「雪国」**ですか？"])
                == ["《三体》有续集吗？", "おすすめは「雪国」ですか？"])
    }

    @Test func followUpsKeepAnUnderscoreInsideAWordAndALoneAsterisk() {
        // Neither is emphasis: stripped, `snake_case` would become another
        // word and `5 * 3` another sum.
        #expect(Answer.cleanedFollowUps(["Which notes mention snake_case?", "What is 5 * 3?"])
                == ["Which notes mention snake_case?", "What is 5 * 3?"])
    }

    @Test func aLinkInAFollowUpKeepsOnlyItsLabel() {
        #expect(Answer.cleanedFollowUps(["Is [Dune](https://elsewhere.example/dune) on my shelf?"])
                == ["Is Dune on my shelf?"])
    }

    @Test func followUpsLoseTheirBackticks() {
        #expect(Answer.cleanedFollowUps(["Which notes mention `grep`?"]) == ["Which notes mention grep?"])
    }

    @Test func aFollowUpLosesALeadingListMarkerOrHeading() {
        #expect(Answer.cleanedFollowUps(["- Which is oldest?", "## Which is newest?"])
                == ["Which is oldest?", "Which is newest?"])
    }

    @Test func aFollowUpThatIsOnlyMarkupIsDropped() {
        // Markup with nothing inside it is no question, and would be a chip of
        // asterisks.
        #expect(Answer.cleanedFollowUps(["****", "` `", "__", "ok?"]) == ["ok?"])
    }

    @Test func aMarkedFollowUpAndItsPlainTwinAreOneChip() {
        // Compared once made plain: the two would ask the same question.
        #expect(Answer.cleanedFollowUps(["**Foo**?", "Foo?", "Bar?"]) == ["Foo?", "Bar?"])
    }

    @Test func theLengthLimitIsMeasuredAfterCleaning() {
        // The reader sees the plain text, so the markup counts for nothing.
        let fits = String(repeating: "a", count: Answer.maxFollowUpLength - 1)
        let over = String(repeating: "b", count: Answer.maxFollowUpLength)
        #expect(Answer.cleanedFollowUps(["**\(fits)**?", "*\(over)*?"]) == ["\(fits)?"])
    }

    @Test func cleaningACleanedFollowUpChangesNothing() {
        // The engine cleans a refine pass's follow-ups, which may be the first
        // answer's, already cleaned.
        let cleaned = Answer.cleanedFollowUps(
            ["Are there any other tools that match the **Card Scraper**'s description?", "What is 5 * 3?"]
        )
        #expect(Answer.cleanedFollowUps(cleaned) == cleaned)
    }

    // MARK: - Mentions and plain punctuation

    @Test func mentionReadsTypographicPunctuationAsPlain() {
        // The model writes an ellipsis where the catalogue stores three periods.
        #expect(Answer.mention(of: "...And Justice For All", in: "I'd play …And Justice For All") != nil)
        #expect(Answer.mention(of: "Don't Look Back", in: "Try “Don’t Look Back” tonight") != nil)
    }

    @Test func mentionIsCaseAndDiacriticInsensitive() {
        #expect(Answer.mention(of: "Café Bleu", in: "your copy of CAFE BLEU") != nil)
    }

    @Test func aShortTitleOnlyMatchesAsAWholeWord() {
        // "Go" is inside "Gloomhaven"; that must not count.
        #expect(Answer.mention(of: "Go", in: "your copy of Gloomhaven") == nil)
        #expect(Answer.mention(of: "Go", in: "you should play Go tonight") != nil)
    }

    @Test func aShortTitleWrittenWithoutSpacesIsStillAMention() {
        // Chinese, Japanese and Korean set words against each other with no
        // space, so the letter beside a short title ends a word there: a
        // follow-up naming 三体 is grounded as one naming "Go" is.
        #expect(Answer.mentioned(in: "三体是刘慈欣写的。", among: [FakeRow("三体")]).map(\.displayTitle) == ["三体"])
        #expect(Answer.mentioned(in: "雪国は川端康成の小説です。", among: [FakeRow("雪国")]).map(\.displayTitle) == ["雪国"])
        #expect(Answer.mentioned(in: "토지는 박경리의 소설입니다.", among: [FakeRow("토지")]).map(\.displayTitle) == ["토지"])
        #expect(Answer.mentioned(in: "其中三体是黑胶。", among: [FakeRow("三体")]).map(\.displayTitle) == ["三体"])
        // A Latin title written straight against such text is a word too.
        #expect(Answer.mention(of: "Go", in: "Go是一种棋。") != nil)
        #expect(Answer.mention(of: "Go", in: "おすすめはGoです。") != nil)
    }

    @Test func aShortTitleStillNeedsAWordBoundaryWhereWordsAreSpaced() {
        // The spaced scripts keep the rule: a neighbouring letter there is the
        // same word.
        #expect(Answer.mention(of: "It", in: "Play it with friends") != nil)
        #expect(Answer.mentioned(in: "Something with strings", among: [FakeRow("It")]).isEmpty)
        #expect(Answer.mention(of: "Go", in: "your copy of Gloomhaven") == nil)
        #expect(Answer.mention(of: "Го", in: "Голос") == nil)
    }

    @Test func aLongTitleMatchesAsASubstring() {
        // Long enough that a substring hit is the better trade — the answer may
        // inflect or possessive-ise it.
        #expect(Answer.mention(of: "Abbey Road", in: "Abbey Road's sleeve") != nil)
    }

    @Test func mentionedRowsComeBackInTheOrderTheProseNamesThem() {
        let answer = Answer(
            text: "Play Rumours, then Abbey Road.",
            matches: [FakeRow("Abbey Road"), FakeRow("Rumours")]
        )
        #expect(answer.mentioned.map(\.displayTitle) == ["Rumours", "Abbey Road"])
    }

    @Test func aTitleInsideALongerRowTheProseNamesIsThatRowsMention() {
        // "Aliens" contains "Alien", and "Dune Messiah" contains "Dune": prose
        // naming the longer title names that row, not the shorter one too.
        let aliens = Answer(text: "Aliens is the one to watch.", matches: [FakeRow("Alien"), FakeRow("Aliens")])
        #expect(aliens.mentioned.map(\.displayTitle) == ["Aliens"])
        let messiah = Answer(
            text: "Dune Messiah picks up the story.", matches: [FakeRow("Dune Messiah"), FakeRow("Dune")]
        )
        #expect(messiah.mentioned.map(\.displayTitle) == ["Dune Messiah"])
    }

    @Test func aShorterTitleTheProseAlsoNamesOnItsOwnStillCounts() {
        let answer = Answer(text: "Dune Messiah follows Dune.", matches: [FakeRow("Dune"), FakeRow("Dune Messiah")])
        #expect(answer.mentioned.map(\.displayTitle) == ["Dune Messiah", "Dune"])
    }

    @Test func onlyALongerRowTakesTheMentionFromAShorterTitle() {
        // With no "Aliens" row, the substring is still the better trade the
        // length rule makes: the prose may inflect the title it means.
        let answer = Answer(text: "Aliens was the sequel.", matches: [FakeRow("Alien")])
        #expect(answer.mentioned.map(\.displayTitle) == ["Alien"])
    }

    // MARK: - Tile resolution

    @Test func everyMatchShowsTheWholeTurn() {
        let tiles = Answer.tiles(
            named: [], showsEveryMatch: true, text: "Here they are.", matches: FakeRow.six
        )
        #expect(tiles.count == FakeRow.six.count)
    }

    @Test func everyMatchIsCappedAtMaxTiles() {
        let many = (0..<50).map { FakeRow("Record \($0)") }
        let tiles = Answer.tiles(named: [], showsEveryMatch: true, text: "", matches: many)
        #expect(tiles.count == Answer.maxTiles)
    }

    @Test func namedTilesResolveInTheModelsOrder() {
        let tiles = Answer.tiles(
            named: ["Rumours", "Abbey Road"], text: "…", matches: FakeRow.six
        )
        #expect(tiles.map(\.displayTitle) == ["Rumours", "Abbey Road"])
    }

    @Test func anExactTitleResolvesBeforeANearOneReadEarlier() {
        // A near match is for a model that paraphrased. When the title it wrote
        // is a row, that row is the one it meant, whichever was read first.
        let longerNamed = Answer.tiles(named: ["Aliens"], text: "…", matches: [FakeRow("Alien"), FakeRow("Aliens")])
        #expect(longerNamed.map(\.displayTitle) == ["Aliens"])
        let shorterNamed = Answer.tiles(named: ["Dune"], text: "…", matches: [FakeRow("Dune Messiah"), FakeRow("Dune")])
        #expect(shorterNamed.map(\.displayTitle) == ["Dune"])
    }

    @Test func aParaphraseResolvesToTheRowSharingMostOfIt() {
        // No row is "Blue Oxford". Blue, read first, holds four letters of it,
        // and Blue Oxford Shirt holds all of it: tapping the tile has to open
        // the shirt, not the record.
        let rows = [FakeRow("Kind of Blue"), FakeRow("Blue"), FakeRow("Blue Oxford Shirt")]
        #expect(Answer.tiles(named: ["Blue Oxford"], text: "…", matches: rows).map(\.displayTitle) == ["Blue Oxford Shirt"])
        // The other way round: the model's title holds the row's.
        let longer = [FakeRow("Abbey"), FakeRow("Abbey Road")]
        #expect(Answer.tiles(named: ["Abbey Road Remastered"], text: "…", matches: longer).map(\.displayTitle) == ["Abbey Road"])
        // Between equals, the one read first.
        let equals = [FakeRow("Blue Oxford Shirt"), FakeRow("Blue Oxford Coat")]
        #expect(Answer.tiles(named: ["Blue Oxford"], text: "…", matches: equals).map(\.displayTitle) == ["Blue Oxford Shirt"])
        // This turn's rows still come before the thread's, however near.
        let tiles = Answer.tiles(
            named: ["Blue Oxford"], text: "…",
            matches: [FakeRow("Blue Oxford Shirt"), FakeRow("Blue")], turnMatches: [FakeRow("Blue")]
        )
        #expect(tiles.map(\.displayTitle) == ["Blue"])
    }

    @Test func anExactTitleIgnoresCaseAccentsAndTypographicPunctuation() {
        let quoted = Answer.tiles(
            named: ["don't stop"], text: "…", matches: [FakeRow("Don't Stop Me Now"), FakeRow("Don’t Stop")]
        )
        #expect(quoted.map(\.displayTitle) == ["Don’t Stop"])
        let accented = Answer.tiles(
            named: ["CAFE BLEU"], text: "…", matches: [FakeRow("Café Bleu Live"), FakeRow("Café Bleu")]
        )
        #expect(accented.map(\.displayTitle) == ["Café Bleu"])
    }

    @Test func anExactTitleTheThreadReadBeatsANearOneThisTurnRead() {
        let tiles = Answer.tiles(
            named: ["Dune"], text: "…", matches: [FakeRow("Dune")], turnMatches: [FakeRow("Dune Messiah")]
        )
        #expect(tiles.map(\.displayTitle) == ["Dune"])
    }

    @Test func aNearTitleStillResolvesWhenNoRowIsExact() {
        let tiles = Answer.tiles(named: ["Dark Side of the Moon"], text: "…", matches: FakeRow.six)
        #expect(tiles.map(\.displayTitle) == ["The Dark Side of the Moon"])
    }

    @Test func aTitleThatResolvesToNothingIsDropped() {
        // The model may have paraphrased, and a tile must be a row the thread
        // actually read.
        let tiles = Answer.tiles(named: ["Something Invented"], text: "…", matches: FakeRow.six)
        #expect(tiles.isEmpty)
    }

    @Test func eachRowResolvesOnce() {
        let tiles = Answer.tiles(named: ["Rumours", "Rumours"], text: "…", matches: FakeRow.six)
        #expect(tiles.count == 1)
    }

    @Test func noNamesFallsBackToWhatTheProseNames() {
        let tiles = Answer.tiles(named: [], text: "Try Abbey Road.", matches: FakeRow.six)
        #expect(tiles.map(\.displayTitle) == ["Abbey Road"])
    }

    @Test func noNamesAndNoMentionsShowsNothing() {
        // The rows a turn read are its grounding, not its answer: an answer that
        // chose to show nothing shows nothing — never every row read.
        let tiles = Answer.tiles(named: [], text: "You own six records.", matches: FakeRow.six)
        #expect(tiles.isEmpty)
    }

    @Test func thisTurnsRowsResolveBeforeTheThreads() {
        let thread = [FakeRow(id: "old", displayTitle: "Rumours")]
        let turn = [FakeRow(id: "new", displayTitle: "Rumours")]
        let tiles = Answer.tiles(named: ["Rumours"], text: "…", matches: thread, turnMatches: turn)
        #expect(tiles.first?.id == "new")
    }

    @Test func aFollowUpCanShowAThreadRowItDidNotReadThisTurn() {
        let thread = FakeRow.six
        let turn = [FakeRow("Kind of Blue")]
        let tiles = Answer.tiles(named: ["Kind of Blue", "Rumours"], text: "…",
                                 matches: thread, turnMatches: turn)
        #expect(tiles.map(\.displayTitle) == ["Kind of Blue", "Rumours"])
    }

    // MARK: - Forward-compatible decode

    @Test func decodesWithEveryOptionalFieldAbsent() throws {
        // The synthesized decoder throws on a missing key, and the store drops
        // a turn whose answer throws, so an update that added a field would
        // cost every reader every turn written before it. Every field added
        // after the first release must survive absence.
        let json = #"{"text":"hello"}"#
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        #expect(answer.text == "hello")
        #expect(answer.matches.isEmpty)
        #expect(answer.tiles.isEmpty)
        #expect(answer.followUps.isEmpty)
        #expect(answer.questionKind == nil)
        #expect(answer.isTruncated == false)
        #expect(answer.basis == nil)
    }

    @Test func aRowThatNoLongerDecodesCostsThatRowNotTheTurn() throws {
        // A host that adds a field to its row makes every row saved before
        // it fail to decode. One such row must cost the answer that row, not
        // the whole saved turn.
        let json = #"""
        {"text":"Rumours and Go.",
         "matches":[{"id":"r","displayTitle":"Rumours"},{"id":"broken"},{"id":"g","displayTitle":"Go"}],
         "tiles":[{"displayTitle":"no id"},{"id":"r","displayTitle":"Rumours"}]}
        """#
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        #expect(answer.text == "Rumours and Go.")
        #expect(answer.matches.map(\.displayTitle) == ["Rumours", "Go"])
        #expect(answer.tiles.map(\.displayTitle) == ["Rumours"])
    }

    @Test func rowListsOfAnotherShapeDecodeAsNone() throws {
        let json = #"{"text":"hello","matches":null,"tiles":{"id":"r"}}"#
        let answer = try JSONDecoder().decode(Answer.self, from: Data(json.utf8))
        #expect(answer.matches.isEmpty)
        #expect(answer.tiles.isEmpty)
    }

    // MARK: - What every answer is held to

    @Test func tilesAreCutToTheMostAnAnswerShows() {
        let many = (0..<30).map { FakeRow("Row \($0)") }
        let capped = Answer(text: "Everything.", tiles: many).cappingTiles()
        #expect(capped.tiles.count == Answer.maxTiles)
        #expect(capped.tiles.first?.displayTitle == "Row 0")
        let few = Answer(text: "Two.", tiles: Array(many.prefix(2)))
        #expect(few.cappingTiles() == few)
    }

    @Test func aDomainsFollowUpsLoseOnlyTheirDuplicates() {
        // A domain's own follow-ups are its as given, but one chip per text:
        // two the same would collide as the chip row's ids.
        #expect(Answer.dedupedFollowUps(["What else?", " what else? ", "", "Which is oldest?", "And a third?"])
                == ["What else?", "Which is oldest?", "And a third?"])
    }

    @Test func aDomainsFollowUpsKeepTheirOwnText() {
        // The domain wrote these, so nothing is made plain: markup in one is
        // the domain's to keep or drop.
        #expect(Answer.dedupedFollowUps(["Is **Dune** older?"]) == ["Is **Dune** older?"])
    }

    @Test func roundTripsEveryField() throws {
        let answer = Answer(
            text: "hello", matches: FakeRow.six, tiles: [FakeRow("Rumours")],
            followUps: ["next?"], questionKind: AskQuestionKind.pick,
            isTruncated: true, basis: "because", grounding: .followUp
        )
        let data = try JSONEncoder().encode(answer)
        #expect(try JSONDecoder().decode(Answer.self, from: data) == answer)
    }

    // MARK: - What grounded it

    @Test func everyGroundingSurvivesTheThread() throws {
        let groundings: [AskGrounding?] = AskGrounding.allCases.map(Optional.some) + [nil]
        for grounding in groundings {
            let answer = Answer(text: "hello", grounding: grounding)
            let decoded = try JSONDecoder().decode(Answer.self, from: JSONEncoder().encode(answer))
            #expect(decoded.grounding == grounding, "\(grounding?.rawValue ?? "nil")")
        }
    }

    /// A grounding a newer build wrote costs the answer that field, never the
    /// answer, as a proposal does.
    @Test func aGroundingThisBuildDoesNotKnowReadsAsNone() throws {
        let decoded = try JSONDecoder().decode(
            Answer.self, from: Data(#"{"text":"hello","grounding":"telepathy","followUps":["next?"]}"#.utf8)
        )
        #expect(decoded.text == "hello")
        #expect(decoded.followUps == ["next?"])
        #expect(decoded.grounding == nil)
    }

    /// Every `replacing` rebuilds the answer, and none may drop what grounded
    /// it: the engine writes the grounding, then replaces the basis.
    @Test func everyReplacementKeepsTheGrounding() {
        let answer = Answer(
            text: "a", matches: [FakeRow("Rumours")], tiles: [FakeRow("Rumours")], followUps: ["Why?"],
            questionKind: AskQuestionKind.pick, basis: "b", payload: Data("p".utf8),
            proposal: AskProposal(title: "Lend it", actionLabel: "Lend"), grounding: .toolCall
        )
        #expect(answer.replacing(basis: "c").grounding == .toolCall)
        #expect(answer.replacing(payload: nil).grounding == .toolCall)
        #expect(answer.replacing(proposal: nil).grounding == .toolCall)
        #expect(answer.replacing(followUps: []).grounding == .toolCall)
        #expect(answer.replacing(tiles: []).grounding == .toolCall)
        #expect(Answer(text: "a", tiles: (0..<30).map { FakeRow("Row \($0)") }, grounding: .appRetrieved)
            .cappingTiles().grounding == .appRetrieved)

        let regrounded = answer.replacing(grounding: AskGrounding.nothing)
        #expect(regrounded.grounding == AskGrounding.nothing)
        #expect(regrounded.replacing(grounding: nil).grounding == nil)
        // And it keeps every other field.
        #expect(regrounded.replacing(grounding: .toolCall) == answer)
    }
}

#endif
