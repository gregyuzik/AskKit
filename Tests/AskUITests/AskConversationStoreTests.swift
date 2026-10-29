#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import SwiftUI
import Synchronization
import Testing

@testable import AskUI

/// The thread, driven by scripted event streams.
///
/// The store makes what the thread shows out of what arrives on each turn's
/// stream, so these script the stream: none of them builds an `AskEngine`, a
/// seam or a model.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskConversationStoreTests {

    // MARK: - Nothing shown is taken back

    @Test func aFailureRendersBeneathThePartialProseItHad() async {
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .partial("You own"), .partial("You own three records")],
            error: AskError.privateCloudUnreachable
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)

        let turn = store.turns.last
        // The words stay.
        #expect(turn?.text == "You own three records")
        // And the message reads under them.
        #expect(turn?.failure?.message == AskError.privateCloudUnreachable.errorDescription)
        #expect(turn?.failure?.isRetryable == true)
        #expect(store.turns.count == 1)
    }

    @Test func aStoppedTurnKeepsItsTextAsItsAnswer() async {
        let asker = ScriptedAsker(.init(
            events: [.tier(.onDevice), .partial("Halfway through a")],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        // Let the partial land before stopping.
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.stop(byReader: true)

        let turn = store.turns.last
        #expect(store.isThinking == false)
        #expect(turn?.stopped == true)
        #expect(turn?.answer?.text == "Halfway through a")
        // Truncated, so the thread can say "Answer cut short".
        #expect(turn?.answer?.isTruncated == true)
        #expect(turn?.failure == nil)
    }

    @Test func aStopTheReaderDidNotAskForIsNotMarkedAsTheirs() async {
        // A host's own stop() cuts the answer short, and the thread says so
        // without telling the reader they stopped it.
        let asker = ScriptedAsker(.init(
            events: [.tier(.onDevice), .partial("Halfway through a")],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.stop()

        let turn = store.turns.last
        #expect(turn?.stopped == false)
        #expect(turn?.answer?.text == "Halfway through a")
        #expect(turn?.answer?.isTruncated == true)
    }

    @Test func retryLeavesAnAnsweredTurnAlone() async throws {
        // Try Again is for a failed turn. On an answer it would take the answer
        // away and ask the question again.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours."))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        let answered = try #require(store.turns.last)

        store.retry(answered)
        await settle(store)
        #expect(store.turns.count == 1)
        #expect(store.turns.last?.answer?.text == "Rumours.")
        #expect(asker.questions.withLock { $0 }.count == 1)
    }

    @Test func anEngineThatAnswersAndThenThrowsLeavesTheAnswer() async {
        // A turn ends once. A failure after the answer would put a failure row
        // under an answer the reader already has.
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .answer(.of("Rumours."))],
            error: AskError.couldNotAnswer
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)

        let turn = store.turns.last
        #expect(turn?.answer?.text == "Rumours.")
        #expect(turn?.failure == nil)
        #expect(store.isThinking == false)
    }

    @Test func aStoppedTurnWithNothingSaidOffersTryAgain() async {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)], hangs: true))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.tier != nil }
        store.stop(byReader: true)

        // The reader's own stop says so: "Couldn't answer that" would be
        // untrue. Try Again stays.
        let turn = store.turns.last
        #expect(turn?.stopped == true)
        #expect(turn?.answer == nil)
        #expect(turn?.failure?.isRetryable == true)
        #expect(turn?.failure?.error == .stopped)
        #expect(turn?.failure?.message == AskAnnouncement.stoppedByReader)
        #expect(AskAnnouncement.terminal(for: turn) == AskAnnouncement.stoppedByReader)
        #expect(turn?.isReadersStopBeforeAWord == true)
        #expect(AskFailureRow.glyph(readerStopped: turn?.isReadersStopBeforeAWord ?? false) == nil, "no warning: nothing failed")
    }

    @Test func aStopTheReaderDidNotAskForBeforeAWordSaysTheAppCouldNotAnswer() async {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)], hangs: true))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.tier != nil }
        store.stop()

        let turn = store.turns.last
        #expect(turn?.stopped == false)
        #expect(turn?.failure?.message == AskError.stopped.errorDescription)
        #expect(turn?.failure?.isRetryable == true)
        #expect(turn?.isReadersStopBeforeAWord == false)
        #expect(AskFailureRow.glyph(readerStopped: turn?.isReadersStopBeforeAWord ?? true) != nil)
    }

    @Test func aTruncatedAnswerArrivesTruncated() async {
        let asker = ScriptedAsker(.init(events: [
            .partial("As far as it got"),
            .answer(.of("As far as it got", truncated: true))
        ]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.answer?.isTruncated == true)
    }

    // MARK: - The turn's shape

    @Test func eachEventLandsOnTheTurn() async {
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .activity(.searching(scope: "records")),
            .rowsRead(UIRow.three),
            .partial("You own"),
            .answer(.of("You own three.", tiles: [UIRow("Rumours")], followUps: ["Which is oldest?"]))
        ]))
        let store = makeStore(asker: asker)
        store.ask("what do I own", origin: .typed)
        await settle(store)

        let turn = store.turns.last
        #expect(turn?.tier == .privateCloud)
        #expect(turn?.text == "You own three.")
        // The answer's tiles are its own: what the turn READ stays what it read.
        #expect(turn?.answer?.tiles == [UIRow("Rumours")])
        #expect(turn?.rowsRead == UIRow.three)
        #expect(turn?.isComplete == true)
        // The wait row's activity goes with the turn it belonged to.
        #expect(turn?.activity == nil)
        #expect(store.isThinking == false)
    }

    @Test func rowsReadWhileThinkingAreWhatTheTurnHasRead() async {
        let asker = ScriptedAsker(.init(events: [.rowsRead(UIRow.three)], hangs: true))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.rowsRead.isEmpty == false }
        #expect(store.turns.last?.rowsRead == UIRow.three)
        store.stop()
    }

    @Test func aRefinementBumpsTheRevisionRatherThanSwappingSilently() async {
        let asker = ScriptedAsker(.init(events: [
            .answer(.of("First read.")),
            .refining,
            .answer(.of("Second read, better."))
        ]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.text == "Second read, better.")
        #expect(store.turns.last?.revision == 1)
    }

    @Test func aRestartedTurnCarriesItsNewTier() async {
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .restarted(.onDevice),
            .tier(.onDevice),
            .answer(.of("From the device."))
        ]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.tier == .onDevice)
    }

    /// Private Cloud Compute wrote, went out, and the device took the turn
    /// over. The device has drawn nothing yet, so nothing the failed attempt
    /// wrote or read may stay on screen as if it were the turn's.
    @Test func aRestartTakesAwayWhatTheFailedAttemptLeft() async {
        let asker = ScriptedAsker(.init(
            events: [
                .tier(.privateCloud), .rowsRead(UIRow.three), .partial("Words from the attempt that failed"),
                .restarted(.onDevice), .tier(.onDevice)
            ],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.tier == .onDevice }
        #expect(store.turns.last?.text == "")
        #expect(store.turns.last?.hasContent == false)
        #expect(store.turns.last?.rowsRead.isEmpty == true)
        store.stop()
    }

    @Test func aStopDuringTheHandDownKeepsNothingOfTheFailedAttempt() async {
        let asker = ScriptedAsker(.init(
            events: [
                .tier(.privateCloud), .partial("Words from the attempt that failed"),
                .restarted(.onDevice), .tier(.onDevice)
            ],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.tier == .onDevice }
        store.stop(byReader: true)

        let turn = store.turns.last
        #expect(turn?.stopped == true)
        #expect(turn?.answer == nil, "The failed attempt's words are not the turn's answer.")
        #expect(turn?.hasContent == false)
    }

    @Test func theAttemptThatTakesOverWritesOnAClearPage() async {
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud), .partial("Words from the attempt that failed"),
            .restarted(.onDevice), .tier(.onDevice),
            .partial("From the"), .answer(.of("From the device."))
        ]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.text == "From the device.")
        #expect(store.turns.last?.answer?.text == "From the device.")
    }

    @Test func theSummarizedMarkerLandsOnTheTurnItPrecedes() async {
        let asker = ScriptedAsker(.init(events: [.summarized, .answer(.of("After a rollover."))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.summarizedBefore == true)
    }

    @Test func aStreamThatEndsWithNoAnswerIsAFailureNotASilentBlank() async {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.failure != nil)
        #expect(store.turns.last?.answer == nil)
    }

    // MARK: - The reveal

    @Test func onlyTheNewWordsFadeIn() async {
        let now = 1000.0
        let asker = ScriptedAsker(.init(events: [
            .partial("You own"),
            .partial("You own three records")
        ], hangs: true))
        let store = makeStore(asker: asker, clock: { now })
        store.ask("q")
        await yieldUntil { store.turns.last?.text == "You own three records" }

        let chunks = store.turns.last?.chunks ?? []
        #expect(chunks.count == 2)
        #expect(chunks.first?.length == "You own".count)
        #expect(chunks.map(\.length).reduce(0, +) == "You own three records".count)
        store.stop()
    }

    @Test func theFinishedAnswerFadesRatherThanPopping() async {
        // The last partial and the answer's tidied text usually differ, and the
        // answer goes through the same `write` — so the difference fades in
        // rather than replacing the paragraph.
        let asker = ScriptedAsker(.init(events: [
            .partial("You own three"),
            .answer(.of("You own three records."))
        ]))
        let store = makeStore(asker: asker, clock: { 1000 })
        store.ask("q")
        await settle(store)

        let chunks = store.turns.last?.chunks ?? []
        #expect(chunks.count == 2)
        #expect(chunks.last?.arrival == 1000)
        #expect(store.turns.last?.isRevealing(at: 1000.1) == true)
        #expect(store.turns.last?.isRevealing(at: 1000 + AskArrivals.settle + 0.1) == false)
    }

    /// What an answer brings besides its words arrives only near its ending
    /// (`AskArrival`), so the store says when a turn ended beside which one,
    /// and forgets both with the thread.
    @Test func aTurnThatEndsSaysWhen() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("You own three records."))]))
        let store = makeStore(asker: asker, clock: { 1000 })
        #expect(store.lastTerminalTurnEndedAt == nil)
        store.ask("q")
        await settle(store)
        #expect(store.lastTerminalTurn == store.turns.last?.id)
        #expect(store.lastTerminalTurnEndedAt == 1000)

        store.startOver()
        #expect(store.lastTerminalTurn == nil)
        #expect(store.lastTerminalTurnEndedAt == nil)
    }

    @Test func aFinishedTurnForgetsItsChunksOnTheStoresOwnClock() async {
        // The chunks are stamped on the store's clock, so how long they have
        // left to fade is read on it too. Read on the wall clock, a store on a
        // clock ahead of it would keep them, and the timeline that draws them,
        // for good.
        let ahead = Date.timeIntervalSinceReferenceDate + 1_000_000
        let asker = ScriptedAsker(.init(events: [.partial("You own three"), .answer(.of("You own three records."))]))
        let store = makeStore(asker: asker, clock: { ahead })
        store.ask("q")
        await settle(store)
        await eventually { store.turns.last?.chunks.isEmpty == true }
        #expect(store.turns.last?.chunks.isEmpty == true)
    }

    // MARK: - Lifecycle

    @Test func newChatEmptiesTheThreadAndBumpsTheGeneration() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        store.draft = "half typed"
        let before = store.threadGeneration

        store.startOver()

        #expect(store.turns.isEmpty)
        #expect(store.draft.isEmpty)
        #expect(store.isThinking == false)
        // A count, not a flag: two New Chats in a row are two events.
        #expect(store.threadGeneration == before + 1)
        store.startOver()
        #expect(store.threadGeneration == before + 2)
        // And the engine's own thread ends with it, from a task of the
        // store's own.
        await eventually { asker.resets.withLock { $0 } >= 1 }
        #expect(asker.resets.withLock { $0 } >= 1)
    }

    /// The screen whose New Chat ended the chat is named, so its composer
    /// takes the focus and the screen in another window on the store doesn't
    /// (`AskScreen`, on `threadGeneration`). A host's own New Chat, such as
    /// the Mac's menu bar item, names no screen, and every screen takes it.
    @Test func aScreensNewChatNamesTheScreenAndAHostsNamesNone() {
        let store = makeStore(asker: ScriptedAsker())
        let left = UUID()
        let right = UUID()
        let before = store.threadGeneration

        store.startOver(from: left)
        #expect(store.threadEndOrigin == left)
        #expect(store.threadGeneration == before + 1)
        store.startOver(from: right)
        #expect(store.threadEndOrigin == right, "the newer New Chat's screen")
        store.startOver()
        #expect(store.threadEndOrigin == nil, "a host's New Chat names no screen")
        #expect(store.threadGeneration == before + 3)
    }

    /// Delete All Chats names its screen the way New Chat does.
    @Test func aScreensDeleteAllNamesTheScreenAndAHostsNamesNone() async {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        await store.restoreIfNeeded()
        let screen = UUID()
        let before = store.threadGeneration

        store.deleteAllThreads(from: screen)
        #expect(store.threadEndOrigin == screen)
        #expect(store.threadGeneration == before + 1)
        store.deleteAllThreads()
        #expect(store.threadEndOrigin == nil, "a host's Delete All names no screen")
        #expect(store.threadGeneration == before + 2)
    }

    @Test func aSecondQuestionSettlesTheFirstRatherThanRunningBeside() async {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.partial("First, partly")], hangs: true),
            .init(events: [.answer(.of("Second, whole."))])
        ])
        let store = makeStore(asker: asker)
        store.ask("first")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.ask("second")
        await settle(store)

        #expect(store.turns.count == 2)
        // The first kept what it had said.
        #expect(store.turns[0].answer?.text == "First, partly")
        #expect(store.turns[0].stopped)
        #expect(store.turns[1].answer?.text == "Second, whole.")
    }

    @Test func anOvertakenTurnNeverClearsTheNewOnesThinkingFlag() async {
        // A turn whose stream has finished but whose completion has not yet run
        // is one MainActor hop from being overtaken. Without the id guard its
        // completion sets `isThinking = false` for the turn that replaced it,
        // and the wait row vanishes under an answer still being written.
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.answer(.of("First."))]),
            .init(events: [.partial("Second, still going")], hangs: true)
        ])
        let store = makeStore(asker: asker)
        store.ask("first")
        store.ask("second")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        // Give the first turn's completion every chance to run late.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.turns.count == 2)
        #expect(store.isThinking, "the second turn is still in flight")
        store.stop()
    }

    @Test func theMirrorIsReadThroughRatherThanCopied() async {
        // The screen and the seam cannot disagree about who is serving, because
        // there is only one value.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        store.status.apply(.init(nextTier: .privateCloud, quotaReached: true, resetDate: nil))
        #expect(store.status.quotaReached)
        #expect(store.unavailability == nil)

        store.status.apply(.init(nextTier: nil, unavailability: .offline))
        #expect(store.unavailability == .offline)
        #expect(!store.status.quotaReached)
    }

    @Test func theCaptionNamesWhoAnswersNextOnceATurnHasLanded() async {
        // The caption is read by someone deciding whether to ask, so it names
        // who would answer, not who answered last. Named for the last turn, a
        // thread whose last turn ran on Private Cloud Compute would go on
        // saying so after the quota was spent: the wrong answer to the only
        // question the line is for.
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(.of("From the cloud."))
        ]))
        let store = makeStore(asker: asker)
        store.status.apply(.init(nextTier: .privateCloud))
        store.ask("q", origin: .typed)
        await settle(store)
        #expect(store.turns.last?.tier == .privateCloud)

        store.status.apply(.init(nextTier: .onDevice))
        #expect(store.captionTier == .onDevice, "the mirror decides once the turn has landed")
    }

    @Test func theCaptionNamesTheTurnInFlightWhileOneIsRunning() async {
        // Mid-turn the question is settled and the answer is arriving, so the
        // line belongs to the turn on screen even if the mirror has already
        // moved on.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud)], hangs: true))
        let store = makeStore(asker: asker)
        store.status.apply(.init(nextTier: .privateCloud))
        store.ask("q", origin: .typed)
        await yieldUntil { store.turns.last?.tier != nil }
        #expect(store.isThinking)

        store.status.apply(.init(nextTier: .onDevice))
        #expect(store.captionTier == .privateCloud, "the turn in flight owns the line")
        store.stop()
    }

    @Test func theCaptionDoesNotBlinkBetweenTheSendAndTheTierEvent() async {
        // A turn is appended before the engine's `.tier` event arrives — that
        // event waits on `tierStates()` — so for those frames the turn's own
        // tier is nil. Reading it alone would empty the subtitle on every
        // send, and an emptying subtitle changes the navigation bar's height.
        let asker = ScriptedAsker(.init(events: [], hangs: true))
        let store = makeStore(asker: asker)
        store.status.apply(.init(nextTier: .privateCloud))
        store.ask("q", origin: .typed)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.isThinking)
        #expect(store.turns.last?.tier == nil, "no tier event has arrived")
        #expect(store.captionTier == .privateCloud, "the mirror fills the gap")
        store.stop()
    }

    @Test func retryReplacesTheFailedTurnRatherThanStackingOnIt() async {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer),
            .init(events: [.answer(.of("Worked this time."))])
        ])
        let store = makeStore(asker: asker)
        store.ask("q", origin: .starter)
        await settle(store)
        #expect(store.turns.count == 1)
        #expect(store.turns[0].failure != nil)

        store.retry(store.turns[0])
        await settle(store)

        #expect(store.turns.count == 1)
        #expect(store.turns[0].answer?.text == "Worked this time.")
        // Re-asked the way it was first asked.
        #expect(store.turns.map(\.origin) == [.starter])
        #expect(asker.questions.withLock { $0 }.map(\.1) == [.conversation, .conversation])
    }

    @Test func tryAgainUnderProseTheTurnDrewKeepsItAndAsksBelowIt() async throws {
        // An outage under the restart floor, or a stream that ends with no
        // answer, fails a turn under the prose it drew. Replaced by the re-ask,
        // that prose would go from the screen and, at the next save, from the
        // disk: nothing shown is taken back (house rule 5).
        let url = temporaryLocation("askkit-retry-prose").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .partial("You own three")], error: AskError.privateCloudUnreachable),
            .init(events: [.tier(.privateCloud), .answer(.of("You own three records."))])
        ])
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        store.ask("What do I own?", origin: .starter)
        await settle(store)
        let failed = try #require(store.turns.last)
        #expect(failed.failure?.isRetryable == true)

        store.retry(failed)
        await settle(store)
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["What do I own?", "What do I own?"])
        #expect(store.turns.first?.text == "You own three", "Try Again took back the prose the turn had drawn")
        #expect(store.turns.first?.failure != nil)
        #expect(store.turns.last?.answer?.text == "You own three records.")
        // Re-asked the way it was first asked, below it, as Ask again asks.
        #expect(store.turns.map(\.origin) == [.starter, .starter])
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: url).load().entries
        #expect(onDisk.map(\.text) == ["You own three", "You own three records."])

        // The kept failure is no longer the newest turn, so it asks nothing.
        store.retry(failed)
        await settle(store)
        #expect(store.turns.count == 2)
    }

    @Test func askAgainAddsATurnRatherThanReplacingOne() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        store.askAgain(store.turns[0])
        await settle(store)

        #expect(store.turns.count == 2)
        #expect(store.turns.map(\.origin) == [.typed, .followUp])
        #expect(asker.questions.withLock { $0 }.map(\.1) == [.conversation, .conversation])
    }

    @Test func theDraftIsClearedByATypedQuestionAndKeptByAStarter() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        store.draft = "what do I own"
        store.ask(store.draft, origin: .typed)
        #expect(store.draft.isEmpty)
        await settle(store)

        store.draft = "half a thought"
        store.ask(AskStarter(text: "Anything from 1970?"))
        await settle(store)
        // A chip must not eat what the reader was typing.
        #expect(store.draft == "half a thought")
    }

    @Test func aRerollAHostAsksRunsAsARerollAndLeavesTheComposerAlone() async throws {
        // Rewritten to `.typed`, a host's Another pick would run cool and
        // unsteered, and come back with the pick it asked to replace. It is
        // a question of its own, as a chip's is, so the draft waits on.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road."))]))
        let store = makeStore(asker: asker)
        store.ask("Which is the oldest?")
        await settle(store)
        store.draft = "half a thought"
        store.ask("Which is the oldest?", origin: .reroll)
        await settle(store)
        #expect(asker.questions.withLock { $0 }.last?.1 == .reroll)
        #expect(store.turns.map(\.origin) == [.typed, .reroll])
        #expect(store.draft == "half a thought")
        // Another pick under an answer asks the same way.
        store.rerollPick(try #require(store.turns.last))
        await settle(store)
        #expect(asker.questions.withLock { $0 }.last?.1 == .reroll)
        #expect(store.turns.last?.origin == .reroll)
    }

    @Test func anEmptyQuestionAsksNothing() async {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        store.ask("   \n  ")
        #expect(store.turns.isEmpty)
        #expect(asker.questions.withLock { $0 }.isEmpty)
    }

    // MARK: - Stopping a turn

    @Test func aTurnLetGoAsItsStreamEndsLeavesTheQuestionAfterItAlone() async throws {
        // Let go in the hop as its stream ends, by Stop and a question asked
        // after it, a turn that went on would stop the store thinking for the
        // waiting question, and drop the task Stop cancels it by.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road."))]))
        asker.parksKeptConversationRead.withLock { $0 = true }
        let store = makeStore(asker: asker)
        store.ask("Which is the oldest?")
        await asker.keptConversationReadIsParked()
        asker.parksStop.withLock { $0 = true }
        store.stop(byReader: true)
        store.ask("And the newest?")
        #expect(store.isThinking)

        asker.releaseKeptConversationRead()
        await yieldUntil { store.hasKeptConversation }
        #expect(store.isThinking, "the question waiting for Stop is still thinking")

        // So Stop still reaches it.
        store.stop(byReader: true)
        asker.releaseStop()
        await eventually { asker.stops.withLock { $0 } == 2 }
        await eventually(within: 0.5) { store.turns.count > 1 }
        #expect(store.turns.map(\.question) == ["Which is the oldest?"])
        #expect(asker.questions.withLock { $0 }.map(\.0) == ["Which is the oldest?"])
    }

    @Test func tryAgainLeavesAQuestionWaitingToBeAsked() async throws {
        // Try Again shows under the newest failed turn, and a question waiting
        // for Stop's word to reach the engine has no turn yet. Taken, it would
        // cancel that question, whose draft is already empty.
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud)], error: AskError.couldNotAnswer),
            .init(events: [.tier(.privateCloud), .answer(.of("Let It Be."))])
        ])
        let store = makeStore(asker: asker)
        store.ask("Which is the oldest?")
        await settle(store)
        let failed = try #require(store.turns.last)
        #expect(failed.failure?.isRetryable == true)

        asker.parksStop.withLock { $0 = true }
        store.stop(byReader: true)
        store.ask("And the newest?")
        store.retry(failed)
        asker.releaseStop()
        await eventually { store.turns.count == 2 }
        await settle(store)
        #expect(store.turns.map(\.question) == ["Which is the oldest?", "And the newest?"])
        #expect(store.turns.last?.answer?.text == "Let It Be.")
        #expect(asker.questions.withLock { $0 }.map(\.0) == ["Which is the oldest?", "And the newest?"])
    }

    @Test func newChatStopsTheEnginesTurnBeforeResettingIt() async {
        // A turn New Chat leaves running finishes unseen and spends its
        // request, so the engine hears Stop before it hears the reset.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .partial("Halfway")], hangs: true))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.startOver()
        await eventually { asker.lifecycle.withLock { $0 }.contains("reset") }
        #expect(Array(asker.lifecycle.withLock { $0 }.prefix(2)) == ["stop", "reset"])
    }

    @Test func deletingEveryChatStopsTheEnginesTurnToo() async {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .partial("Halfway")], hangs: true))
        let store = makeStore(domain: domain, asker: asker)
        await store.restoreIfNeeded()
        store.ask("q")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.deleteAllThreads()
        await eventually { asker.lifecycle.withLock { $0 }.contains("reset") }
        #expect(Array(asker.lifecycle.withLock { $0 }.prefix(2)) == ["stop", "reset"])
    }

    @Test func aTurnTheEngineCancelledSettlesAsStopped() async {
        // The store cancels its own turns before the engine hears of it, and
        // then returns quietly. A cancellation it didn't ask for (a host
        // resetting the engine, a second store on the same engine) ends the
        // stream the same way, and the turn must not be left thinking.
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .partial("Halfway through")],
            error: CancellationError()
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.isThinking == false)
        let turn = store.turns.last
        // Not the reader's: the thread says the answer was cut short, not
        // that they stopped it.
        #expect(turn?.stopped == false)
        #expect(turn?.answer?.text == "Halfway through")
        #expect(turn?.answer?.isTruncated == true)
    }

    @Test func aTurnTheEngineCancelledBeforeItSaidAnythingOffersTryAgain() async {
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud)], error: CancellationError()))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.isThinking == false)
        #expect(store.turns.last?.stopped == false)
        #expect(store.turns.last?.failure?.message == AskError.stopped.errorDescription)
    }

    @Test func aQuestionAskedRightAfterStopIsAnswered() async {
        // On an engine whose `stop()` cancels the turn in flight, as
        // `AskEngine`'s does, after a hop to its actor. A question asked in
        // the same tick as the stop has to reach the engine after it, or the
        // late stop cancels the new question ("Answer cut short").
        let words = (1...40).map { AskTurnEvent<UIRow>.partial(String(repeating: "word ", count: $0)) }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud)] + words + [.answer(.of("Answer."))]))
        // The first turn never finishes on its own, so the stop always cuts it.
        asker.scripts([.init(events: [.tier(.privateCloud), .partial("Halfway")], hangs: true)])
        asker.cancelsTheTurnInFlight.withLock { $0 = true }
        let store = makeStore(asker: asker)
        store.ask("Which records do I own?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }

        store.stop(byReader: true)
        store.ask("Anything from 1969?")
        await settle(store)

        #expect(store.turns.map(\.question) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.turns.first?.stopped == true)
        #expect(store.turns.last?.answer?.text == "Answer.", "the question was cut short")
        #expect(store.turns.last?.answer?.isTruncated == false)
        #expect(store.turns.last?.failure == nil)
        #expect(asker.lifecycle.withLock { $0 } == ["stop"])
    }

    @Test func stoppingATurnWhoseAnswerHasLandedStillEndsItsFade() async {
        // The answer lands a moment before the stream finishes. Stopped in that
        // moment, the turn's own task returns on cancellation without
        // forgetting its chunks, so whoever settles the turn has to, or its
        // text redraws every frame for the life of the screen.
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .partial("All of it."), .answer(.of("All of it."))],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("q")
        await yieldUntil { store.turns.last?.isComplete == true }
        #expect(store.turns.last?.chunks.isEmpty == false)
        store.stop()
        await eventually { store.turns.last?.chunks.isEmpty == true }
        #expect(store.turns.last?.chunks.isEmpty == true)
    }

    // MARK: - Chips

    @Test func aDeclinedChipDoesNotComeBackInThisThread() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        await store.refresh()
        #expect(store.availableStarters.count == 3)

        let first = store.availableStarters[0]
        store.decline(first)
        #expect(store.availableStarters.count == 2)
        #expect(!store.availableStarters.contains { $0.id == first.id })

        // Asking one also takes it off the board.
        store.ask(store.availableStarters[0])
        await settle(store)
        #expect(store.availableStarters.count == 1)

        // New Chat is a new thread, so the board is full again.
        store.startOver()
        #expect(store.availableStarters.count == 3)
    }

    @Test func followUpsAppearOnlyUnderAFinishedAnswer() async {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.answer(.of("An answer.", followUps: ["Which is oldest?", "Any on vinyl?"]))]),
            .init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer)
        ])
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.followUps.map(\.text) == ["Which is oldest?", "Any on vinyl?"])

        // A failed turn offers none — there is nothing to follow up on.
        store.ask("again")
        await settle(store)
        #expect(store.followUps.isEmpty)
    }

    @Test func followUpsWaitForTheEngineToKeepAConversation() async {
        // An engine that answered and keeps no conversation leaves "which of
        // those…" nothing to resolve against. Whether it keeps one is the
        // engine's own to say, read as the turn ends and as the store
        // refreshes.
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer.", followUps: ["Which is oldest?"]))]))
        asker.answersKeepAConversation.withLock { $0 = false }
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(!store.hasKeptConversation)
        #expect(store.followUps.isEmpty)

        asker.keepsConversation.withLock { $0 = true }
        await store.refresh()
        #expect(store.hasKeptConversation)
        #expect(store.followUps.map(\.text) == ["Which is oldest?"])
    }

    @Test func aNewChatReadsThatNoConversationIsKept() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer.", followUps: ["Which is oldest?"]))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        #expect(store.hasKeptConversation)

        store.startOver()
        await eventually { !store.hasKeptConversation }
        #expect(!store.hasKeptConversation)
    }

    @Test func aRefusalCoachesWithTwoStarters() async {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)], error: AskError.refused))
        let store = makeStore(asker: asker)
        await store.refresh()
        store.ask("something blocked")
        await settle(store)

        let failure = store.turns.last?.failure
        #expect(failure?.isRetryable == false)
        #expect(failure?.coaching.count == 2)
    }

    @Test func anOrdinaryFailureDoesNotCoach() async {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer))
        let store = makeStore(asker: asker)
        await store.refresh()
        store.ask("q")
        await settle(store)
        #expect(store.turns.last?.failure?.coaching.isEmpty == true)
    }

    @Test func oneRuleSaysWhichFailuresCoachForATurnAndForOneReadBack() {
        // A turn as it fails and one read back from disk are coached by the
        // same rule, so the two can't drift apart.
        let coached: [AskError] = [.refused, .ungrounded]
        let uncoached: [AskError] = [
            .couldNotAnswer, .stopped, .privateCloudUnreachable, .contextTooLarge, .photosNotSupported,
            .requestNotSupported, .quotaReached(resetDate: nil), .model(tag: "x"), .modelUnavailable(.offline)
        ]
        #expect(coached.map(\.isCoached) == [true, true])
        #expect(uncoached.filter(\.isCoached).isEmpty)
    }

    // MARK: - The stage

    @Test func theStageIsTheOnlyThingLayoutAnimatesOn() async {
        let asker = ScriptedAsker(.init(events: [
            .partial("One"), .partial("One two"), .partial("One two three"),
            .answer(.of("One two three."))
        ]))
        let store = makeStore(asker: asker)
        await store.refresh()

        let ready = store.stage
        #expect(ready.phase == .ready)
        #expect(!ready.isThinking)

        store.ask("q")
        await settle(store)

        let done = store.stage
        #expect(done.phase == .thread)
        #expect(done.lastIsComplete)
        #expect(done.turns.count == 1)
    }

    @Test func threeStreamedTokensAreOneStage() async {
        // The point of the whole value: a stream produces snapshots faster than
        // anything should re-lay-out, and the stage must not change on them.
        var turn = AskTurn<UIRow>(question: "q", origin: .typed)
        turn.write("One", at: 0)
        let first = AskStage.of(turns: [turn], isThinking: true, overview: .empty, unavailability: nil)
        turn.write("One two", at: 1)
        turn.write("One two three", at: 2)
        let later = AskStage.of(turns: [turn], isThinking: true, overview: .empty, unavailability: nil)
        #expect(first == later)

        // But the frame the first words land IS a change — the wait row gives
        // way to prose.
        var empty = AskTurn<UIRow>(question: "q", origin: .typed)
        let silent = AskStage.of(turns: [empty], isThinking: true, overview: .empty, unavailability: nil)
        empty.write("One", at: 0)
        let speaking = AskStage.of(turns: [empty], isThinking: true, overview: .empty, unavailability: nil)
        #expect(silent != speaking)
    }

    @Test func theReasonNothingCanServeOutranksAnEmptyLibrary() async {
        // A reader who cannot be served needs to know that before being told
        // they own nothing.
        var domain = UIDomain()
        domain.rows = []
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        store.status.apply(.init(nextTier: .onDevice))
        await store.refresh()
        #expect(store.stage.phase == .nothingToAskAbout)

        store.status.apply(.init(nextTier: nil, unavailability: .appleIntelligenceOff))
        #expect(store.stage.phase == .cannotServe(.appleIntelligenceOff))

        // And it clears when a tier comes back — the mirror is read through, so
        // the screen can never disagree with the seam about who is serving.
        store.status.apply(.init(nextTier: .onDevice))
        #expect(store.stage.phase == .nothingToAskAbout)
    }

    @Test func anEmptyLibraryWithNoNothingToAskCopyIsReady() async {
        // No copy, no nothing-to-ask screen: the brand's missing words reach
        // the stage through the store, and the reader gets the ready screen.
        var domain = UIDomain()
        domain.rows = []
        domain.nothingToAskCopy = nil
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        store.status.apply(.init(nextTier: .onDevice))
        await store.refresh()
        #expect(store.overview.isEmpty)
        #expect(store.stage.phase == .ready)
    }

    @Test func aThreadOutranksBothFirstScreens() async {
        var domain = UIDomain()
        domain.rows = []
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(domain: domain, asker: asker)
        await store.refresh()
        store.status.apply(.init(nextTier: nil, unavailability: .deviceNotEligible))
        store.ask("q")
        await settle(store)
        #expect(store.stage.phase == .thread)
    }

    // MARK: - Disk
    //
    // Through `makeStore`, so the archive and the feedback folder are
    // temporary too. A store built with only a thread keeps both at their
    // defaults in Application Support, and New Chat below would file its chat
    // into the developer's own Application Support on every run.

    @Test func aPerLaunchThreadIsNeverWritten() async {
        let directory = temporaryLocation("askkit-perlaunch").appendingPathExtension("json")
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker, threadURL: directory)
        store.ask("q")
        await settle(store)
        await store.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test func aPersistedThreadComesBackWithoutItsFadesOrItsFailures() async {
        let directory = temporaryLocation("askkit-thread").appendingPathExtension("json")
        var domain = UIDomain()
        domain.persistenceMode = .thread

        let asker = ScriptedAsker(.init(events: [
            .partial("You own"),
            .answer(.of("You own three.", tiles: [UIRow("Rumours")]))
        ]))
        let store = makeStore(domain: domain, asker: asker, threadURL: directory, clock: { 1000 })
        store.ask("what do I own")
        await settle(store)
        await store.flushPersistence()

        let reopened = makeStore(
            domain: domain, asker: ScriptedAsker(), threadURL: directory,
            clock: { Date.timeIntervalSinceReferenceDate }
        )
        await reopened.restoreIfNeeded()

        #expect(reopened.turns.count == 1)
        #expect(reopened.turns[0].question == "what do I own")
        #expect(reopened.turns[0].answer?.text == "You own three.")
        // No stamps, so no clock can hold a restored answer faint.
        #expect(reopened.turns[0].chunks.isEmpty)
        #expect(!reopened.turns[0].isRevealing(at: 1000))

        // And a second call does nothing.
        await reopened.restoreIfNeeded()
        #expect(reopened.turns.count == 1)
    }

    @Test func newChatForgetsTheThreadOnDiskToo() async {
        let directory = temporaryLocation("askkit-clear").appendingPathExtension("json")
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(domain: domain, asker: asker, threadURL: directory)
        store.ask("q")
        await settle(store)
        await store.flushPersistence()
        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))

        store.startOver()
        await store.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    @Test func aThreadThatIsNotAThreadIsSetAsideAndTheNextAnswerIsKept() async throws {
        // A file that is there and doesn't parse is set aside whole, the
        // first screen says so, and the chat goes on being saved. Restored as
        // `[]`, it would read as a fresh install, and the next answer would
        // write a one-entry array over the reader's whole conversation; left
        // in place and never written over, nothing the reader asked afterwards
        // would be kept.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let garbage = Data("[[[ not a thread".utf8)
        try garbage.write(to: threadURL)
        let (store, _) = keepingStore(
            asker: ScriptedAsker(.init(events: [.answer(.of("An answer."))])),
            threadURL: threadURL, archiveDirectory: archiveDirectory
        )
        await store.restoreIfNeeded()
        #expect(store.turns.isEmpty)
        #expect(store.readFailed)
        #expect(store.showsUnreadableThreadNotice)
        #expect(try setAsideFiles(in: folder).map { try Data(contentsOf: $0) } == [garbage])

        store.ask("a question that must not cost the reader their thread")
        await settle(store)
        await store.flushPersistence()
        #expect(!store.showsUnreadableThreadNotice)
        let saved = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load().entries
        #expect(saved.map(\.question) == ["a question that must not cost the reader their thread"])
        #expect(try setAsideFiles(in: folder).map { try Data(contentsOf: $0) } == [garbage])

        store.startOver()
        #expect(!store.readFailed)
    }

    @Test func aThreadThatCannotBeReadIsNeverWrittenOver() async throws {
        // A thread that can't be read at all (a locked device) may be a good
        // one, so it stays where it is, byte for byte. New Chat files what was
        // asked since, and sets the thread aside rather than deleting it.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer {
            for file in setAsideFiles(in: folder) + [threadURL] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
            }
            try? FileManager.default.removeItem(at: folder)
        }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).save([earlierEntry("Which records do I own?")])
        let written = try Data(contentsOf: threadURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: threadURL.path(percentEncoded: false))
        let (store, _) = keepingStore(
            asker: ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("An answer."))])),
            threadURL: threadURL, archiveDirectory: archiveDirectory
        )
        await store.restoreIfNeeded()
        #expect(store.readFailed)
        #expect(setAsideFiles(in: folder).isEmpty)

        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: threadURL.path(percentEncoded: false))
        #expect(try Data(contentsOf: threadURL) == written)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: threadURL.path(percentEncoded: false))

        store.startOver()
        await store.flushPersistence()
        #expect(!store.readFailed)
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(!FileManager.default.fileExists(atPath: threadURL.path(percentEncoded: false)))
        let aside = setAsideFiles(in: folder)
        #expect(aside.count == 1)
        for file in aside {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
        }
        #expect(try aside.map { try Data(contentsOf: $0) } == [written])
    }

    @Test func aThreadSetAsideThatReadsAgainComesBackWithTheEarlierChats() async throws {
        // Read on a later launch, by a build that can: filed with the earlier
        // chats before the list is read, and gone from beside the thread.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let aside = folder.appending(path: "ask-thread-unreadable-\(UUID().uuidString).json")
        try JSONEncoder().encode([earlierEntry("Which records do I own?")]).write(to: aside)
        let (store, _) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)

        await store.restoreIfNeeded()
        #expect(store.history.map(\.title) == ["Which records do I own?"])
        #expect(setAsideFiles(in: folder).isEmpty)
        #expect(!store.readFailed)
    }

    // MARK: - The engine's other calls

    @Test func refreshReadsTheLibraryAndReProbesTheModel() async {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.refresh()
        #expect(store.overview.total == UIRow.three.count)
        #expect(store.starters.count == 3)
        #expect(asker.refreshes.withLock { $0 } == 1)

        await store.prewarm()
        #expect(asker.prewarms.withLock { $0 } == 0, "an appearance alone warms nothing")
        store.draft = "W"
        await eventually { asker.prewarms.withLock { $0 } == 1 }
        #expect(asker.prewarms.withLock { $0 } == 1)
    }

    // MARK: - The warm session

    /// Long enough for a stray warm's task to have reached the engine.
    private func letStrayWarmsLand() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func theFirstKeystrokeWarmsTheQuestionItBegins() async {
        // A warm on Private Cloud Compute is a request against the reader's
        // daily quota, and most appearances of the screen ask nothing, so an
        // appearance, a return to the app and New Chat warm nothing on their
        // own. Typing is the first sign a question is coming.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.prewarm()
        #expect(asker.prewarms.withLock { $0 } == 0)
        store.draft = "W"
        await eventually { asker.prewarms.withLock { $0 } == 1 }
        store.draft = "Wh"
        store.draft = "What"
        await letStrayWarmsLand()
        #expect(asker.prewarms.withLock { $0 } == 1, "one warm per question begun, not one per keystroke")
    }

    @Test func newChatWarmsNothingUntilTheReaderTypes() async {
        // `AskEngine.reset` takes the warm with the chat. The next one waits
        // for the next question to begin, and it lands after the reset.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.prewarm()
        store.startOver()
        await eventually { asker.resets.withLock { $0 } == 1 }
        await letStrayWarmsLand()
        #expect(asker.lifecycle.withLock { $0 } == ["stop", "reset"])
        store.draft = "W"
        await eventually { asker.lifecycle.withLock { $0 } == ["stop", "reset", "prewarm"] }
        #expect(
            asker.lifecycle.withLock { $0 } == ["stop", "reset", "prewarm"],
            "warmed after the reset, never before it"
        )
    }

    @Test func aScreenThatHasGoneWarmsNothingWhateverIsTyped() async {
        // A warm nobody will take is held until the screen next disappears.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.prewarm()
        await store.releaseWarmSession()
        store.startOver()
        await eventually { asker.resets.withLock { $0 } == 1 }
        store.draft = "W"
        await letStrayWarmsLand()
        #expect(asker.lifecycle.withLock { $0 } == ["stop", "reset"])
    }

    @Test func aScreenGoingAwayTellsTheEngineToLetItsWarmGo() async {
        // The screen's disappearance is the only caller of the engine's
        // `forgetWarmIfEmpty`, and the only way a warm nobody took is let go.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.prewarm()
        #expect(asker.forgets.withLock { $0 } == 0)
        await store.releaseWarmSession()
        #expect(asker.forgets.withLock { $0 } == 1)
    }

    @Test func comingBackWarmsOnlyAHalfTypedQuestionOnAScreenThatIsUp() async {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        store.draft = "Is it"
        await store.rewarm()
        #expect(asker.prewarms.withLock { $0 } == 0, "no screen has asked for a warm")
        // The screen comes back to the question it left: that one is coming.
        await store.prewarm()
        #expect(asker.prewarms.withLock { $0 } == 1)
        // And a return to the app with it still there warms again, since one
        // made before the app left may have aged out; the engine keeps a
        // young one.
        await store.rewarm()
        #expect(asker.prewarms.withLock { $0 } == 2)
        store.draft = ""
        await store.rewarm()
        #expect(asker.prewarms.withLock { $0 } == 2, "an empty composer warms nothing on the way back")
        await store.releaseWarmSession()
        store.draft = "Is it signed"
        await store.rewarm()
        await letStrayWarmsLand()
        #expect(asker.prewarms.withLock { $0 } == 2, "the screen has gone")
    }

    /// The window the store asks for is the bank the first screen will draw:
    /// three on iPhone and iPad, eight on the Mac and Apple Vision Pro.
    /// `refreshReadsTheLibraryAndReProbesTheModel` can't see this: the fake
    /// domain offers exactly three questions, so it would pass on any window
    /// at all. This one gives it more than any platform asks for.
    @Test func refreshAsksForAsManyStartersAsTheFirstScreenCanShow() async {
        var domain = UIDomain()
        domain.starterTexts = (1...20).map { "Question \($0)?" }
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        await store.refresh()
        #expect(store.starters.count == AskLayout.starterBank)
    }

    // MARK: - A thread read back from disk

    @Test func aRestoredThreadHandsTheEngineItsTail() async {
        let url = temporaryLocation("askkit-resume").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        await AskThreadStore<UIRow>(appDirectory: "AskKitUITests", url: url).save([
            AskThreadEntry(question: "one", text: "One.", answer: .of("One.", tiles: [UIRow("Rumours")]), tier: .privateCloud),
            AskThreadEntry(question: "failed", text: "", answer: nil, failureMessage: "No."),
            // The domain's own answer: no tier, and no session ever heard it.
            AskThreadEntry(question: "hello", text: "Hi.", answer: .of("Hi.", tiles: [UIRow("Kind of Blue")])),
            AskThreadEntry(question: "two", text: "Two.", answer: .of("Two.", tiles: [UIRow("Abbey Road")]), tier: .onDevice)
        ])
        var domain = UIDomain()
        domain.persistenceMode = .thread
        domain.extraReferents = ["Kind of Blue"]
        let asker = ScriptedAsker()
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        await store.restoreIfNeeded()

        let tails = asker.resumedTails.withLock { $0 }
        #expect(tails.count == 1)
        let tail = tails.first ?? []
        // Exchanges a model answered only, oldest first — what a live session's
        // own tail would have held.
        #expect(tail.map(\.question) == ["one", "two"])
        #expect(tail.first?.rowTitles == ["Rumours"])
        // The newest is widened to the referent a follow-up's "those" reads.
        #expect(tail.last?.rowTitles == ["Abbey Road", "Kind of Blue"])
        #expect(tail.last?.answer == "Two.")
    }

    @Test func aRestoredThreadOffersItsFollowUpsOnceItsTailIsResumed() async {
        // The engine keeps no session across a relaunch, but the tail it is
        // handed counts as a kept conversation: the next question's recap
        // gives a chip's "those" something to resolve against.
        let url = temporaryLocation("askkit-resume").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        await AskThreadStore<UIRow>(appDirectory: "AskKitUITests", url: url).save([
            AskThreadEntry(
                question: "one", text: "One.",
                answer: .of("One.", tiles: [UIRow("Rumours")], followUps: ["Which is oldest?"]), tier: .privateCloud
            )
        ])
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker()
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        await store.restoreIfNeeded()
        #expect(store.hasKeptConversation)
        #expect(store.followUps.map(\.text) == ["Which is oldest?"])
    }

    @Test func aLongRestoredThreadHandsOnlyWhatARecapCarries() async {
        let url = temporaryLocation("askkit-resume").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        await AskThreadStore<UIRow>(appDirectory: "AskKitUITests", url: url).save(
            (1...5).map { AskThreadEntry(question: "q\($0)", text: "a", answer: .of("a"), tier: .privateCloud) }
        )
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker()
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        await store.restoreIfNeeded()

        let tail = asker.resumedTails.withLock { $0 }.first ?? []
        #expect(tail.count == AskContinuation.recapDepth)
        #expect(tail.last?.question == "q5")
    }

    @Test func aPerLaunchThreadHandsTheEngineNothing() async {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.restoreIfNeeded()
        #expect(asker.resumedTails.withLock { $0 }.isEmpty)
    }

    // MARK: - A question before the thread is read

    /// A store over a saved thread of one answered question, "one", that has
    /// not read it yet: the store at launch, before the screen appears.
    private func storeOverASavedThread(asker: ScriptedAsker, url: URL) async -> AskConversationStore<UIDomain> {
        await AskThreadStore<UIRow>(appDirectory: "AskKitUITests", url: url).save([
            AskThreadEntry(question: "one", text: "One.", answer: .of("One."), tier: .privateCloud)
        ])
        var domain = UIDomain()
        domain.persistenceMode = .thread
        return makeStore(domain: domain, asker: asker, threadURL: url)
    }

    /// The questions in the thread on disk.
    private func questionsOnDisk(_ url: URL) async -> [String] {
        guard case .thread(let entries, _) = await AskThreadStore<UIRow>(appDirectory: "AskKitUITests", url: url).load()
        else { return [] }
        return entries.map(\.question)
    }

    @Test func aQuestionSentBeforeTheThreadIsReadIsAskedAfterIt() async {
        // An entry point that sends as it opens Ask gets there before the
        // screen. Asked at once, its question would keep the saved thread from
        // coming back, and the save after its answer would write a thread of
        // one over it.
        let url = temporaryLocation("askkit-early").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Two."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        store.prefill("two", send: true)
        await settle(store)
        await store.restoreIfNeeded()
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["one", "two"])
        #expect(asker.resumedTails.withLock { $0 }.map { $0.map(\.question) } == [["one"]],
                "the engine was handed the thread, so the question starts its session with a recap")
        #expect(await questionsOnDisk(url) == ["one", "two"])
    }

    @Test func everyCallerWaitsForTheSameRead() async {
        // The screen restores as it appears, and a host can too. A second call
        // waits for the read the first started rather than returning before
        // the thread is back.
        let url = temporaryLocation("askkit-reread").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = await storeOverASavedThread(asker: ScriptedAsker(), url: url)

        let screen = Task { await store.restoreIfNeeded() }
        await Task.yield()
        await store.restoreIfNeeded()
        #expect(store.turns.map(\.question) == ["one"])
        await screen.value
    }

    @Test func aQuestionAskedWhileTheThreadIsReadLandsAfterIt() async {
        // Asked during the read, the question would be replaced by the
        // thread, or would keep the thread from coming back.
        let url = temporaryLocation("askkit-during").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.answer(.of("Two."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        let screen = Task { await store.restoreIfNeeded() }
        await Task.yield()
        store.ask("two")
        await screen.value
        await settle(store)
        #expect(store.turns.map(\.question) == ["one", "two"])
    }

    @Test func aQuestionStoppedBeforeTheThreadIsReadAsksNothingAndWritesNothing() async {
        let url = temporaryLocation("askkit-stopped-early").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.answer(.of("Two."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        store.ask("two")
        #expect(store.isThinking, "thinking from the tap, so the keyboard leaves with the question")
        store.stop()
        await store.restoreIfNeeded()
        for _ in 0..<3 { await Task.yield() }
        await store.flushPersistence()

        #expect(!store.isThinking)
        #expect(asker.questions.withLock { $0 }.isEmpty)
        #expect(store.turns.map(\.question) == ["one"])
        #expect(await questionsOnDisk(url) == ["one"],
                "Stop wrote the empty thread it had over the one it had not read yet")
    }

    @Test func aQuestionStoppedWhileItWaitsGoesBackToTheComposer() async {
        // It has no turn yet, and the draft was emptied as it was sent:
        // dropped, it would be gone without a trace, where a stopped turn
        // keeps its question.
        let url = temporaryLocation("askkit-stopped-back").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.answer(.of("Two."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        store.draft = "two"
        store.ask(store.draft)
        #expect(store.draft.isEmpty)
        store.stop(byReader: true)
        #expect(store.draft == "two", "the reader would type the question again")
        await store.restoreIfNeeded()
        await store.flushPersistence()
        #expect(asker.questions.withLock { $0 }.isEmpty)
        #expect(store.turns.map(\.question) == ["one"])

        // A draft the reader has begun since is theirs, and stays.
        store.draft = ""
        asker.parksStop.withLock { $0 = true }
        store.stop(byReader: true)
        store.ask("three")
        store.draft = "four"
        store.stop(byReader: true)
        #expect(store.draft == "four")
        asker.releaseStop()
    }

    @Test func aQuestionAskedWhileAnotherWaitsPutsTheOtherBackInTheComposer() async {
        // Asked over a turn in flight, a question stops that turn where it
        // stands, and the stopped turn keeps its question. One still waiting
        // has no turn to keep it, so it goes back to the composer.
        let url = temporaryLocation("askkit-second-waiting").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        store.ask("Anything from 1970?", origin: .starter)
        store.draft = "Which are on vinyl?"
        store.ask(store.draft)
        #expect(store.draft == "Anything from 1970?", "the first question went without a trace")
        await store.restoreIfNeeded()
        await settle(store)
        #expect(store.turns.map(\.question) == ["one", "Which are on vinyl?"])
        #expect(asker.questions.withLock { $0 }.map(\.0) == ["Which are on vinyl?"])
    }

    // MARK: - Entry points

    @Test func aPrefillPutsTheQuestionInTheComposerAndAsksNothing() throws {
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        store.prefill("  Is the Fair Isle vest too warm?  ")
        #expect(store.draft == "Is the Fair Isle vest too warm?")
        let request = try #require(store.composerFocusRequest)
        #expect(store.turns.isEmpty)
        #expect(asker.questions.withLock { $0 }.isEmpty)

        #expect(store.claimComposerFocus(request))
        #expect(store.composerFocusRequest == nil)
        #expect(store.draft == "Is the Fair Isle vest too warm?")
    }

    @Test func twoPrefillsAreTwoRequestsAndTheNewerQuestionWins() {
        let store = makeStore(asker: ScriptedAsker())
        store.prefill("one")
        let first = store.composerFocusRequest
        store.prefill("two")
        #expect(store.composerFocusRequest != first)
        #expect(store.draft == "two")
    }

    @Test func aPrefillThatSendsAsksItAsPrefilled() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I read tonight?", send: true)
        await settle(store)
        #expect(store.turns.map(\.origin) == [.prefilled])
        #expect(asker.questions.withLock { $0 }.map { $0.1 } == [.conversation])
        #expect(store.turns.first?.question == "What should I read tonight?")
        #expect(store.composerFocusRequest == nil)
    }

    @Test func anEmptyPrefillChangesNothing() {
        let store = makeStore(asker: ScriptedAsker())
        store.draft = "half a question"
        store.prefill("   ")
        #expect(store.draft == "half a question")
        #expect(store.composerFocusRequest == nil)
    }

    @Test func focusingTheComposerAsksForItAndNothingElse() {
        // A Control Center control opens Ask with no question to put there, and
        // `prefill` refuses an empty one.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        store.draft = "half a question"
        store.focusComposer()
        let first = store.composerFocusRequest
        #expect(first != nil)
        #expect(store.draft == "half a question", "the reader's draft is left where it was")
        store.focusComposer()
        #expect(store.composerFocusRequest != first, "two requests are two")
        #expect(store.turns.isEmpty)
        #expect(asker.questions.withLock { $0 }.isEmpty)
    }

    /// A host's request for the composer is taken by one screen, the first
    /// in a window the reader is in to claim it (`AskScreen`, on
    /// `composerFocusRequest`). The screen in another window on the store
    /// hears the same request in the same update, and its claim fails, so
    /// that window keeps no focused field and no Done once the keyboard has
    /// gone. The draft is the store's, and every window shows it.
    @Test func aHostsRequestForTheComposerIsTakenByOneScreen() throws {
        let store = makeStore(asker: ScriptedAsker())
        store.prefill("What should I read tonight?")
        let request = try #require(store.composerFocusRequest)

        #expect(store.claimComposerFocus(request), "the first screen to claim it takes it")
        #expect(!store.claimComposerFocus(request), "a second screen hearing the same request doesn't")
        #expect(store.composerFocusRequest == nil)
        #expect(store.draft == "What should I read tonight?", "the draft stays the store's")
    }

    /// A request no screen has taken waits, for a screen that appears or a
    /// window the reader comes to, and a screen still answering an older
    /// request takes nothing and leaves the newer one waiting.
    @Test func aWaitingRequestIsTakenOnceAndAnOlderOneTakesNothing() throws {
        let store = makeStore(asker: ScriptedAsker())
        store.focusComposer()
        let older = try #require(store.composerFocusRequest)
        store.focusComposer()
        let newer = try #require(store.composerFocusRequest)

        #expect(!store.claimComposerFocus(older), "the older request is no longer there to take")
        #expect(store.composerFocusRequest == newer, "and the newer one still waits")
        #expect(store.claimComposerFocus(newer))
        #expect(!store.claimComposerFocus(newer), "taken once")
        #expect(store.composerFocusRequest == nil)
    }

    /// A screen that took a host's request as the reader's tap was bringing
    /// another window to the front asks again (`AskHostFocusHandOver`): a new
    /// request every screen hears, which the one in front takes, with the
    /// draft as the host left it.
    @Test func aRequestHandedOnIsANewOneForTheWindowInFront() throws {
        let store = makeStore(asker: ScriptedAsker())
        store.prefill("What should I read tonight?")
        let first = try #require(store.composerFocusRequest)
        #expect(store.claimComposerFocus(first), "the window that appeared active took it")

        store.repostComposerFocus()
        let handedOn = try #require(store.composerFocusRequest)
        #expect(handedOn != first, "a new request, which every screen hears as one")
        #expect(!store.claimComposerFocus(first), "the request already taken takes nothing")
        #expect(store.claimComposerFocus(handedOn), "the screen in front takes the new one")
        #expect(store.draft == "What should I read tonight?", "the draft is untouched")
    }

    // MARK: - A scope

    @Test func aPrefillThatSendsAsksInItsScope() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Rumours."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records", send: true)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == ["records"])
        #expect(store.turns.first?.scope == "records")
    }

    @Test func aPrefilledQuestionGoesInItsScopeEditedOrNot() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Rumours."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records")
        #expect(asker.scopes.withLock { $0 }.isEmpty, "a prefill that does not send asks nothing")
        store.draft += " Something loud."
        store.ask(store.draft)
        await settle(store)
        // The next question from the composer is the reader's own.
        store.draft = "And after that?"
        store.ask(store.draft)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == ["records", nil])
        #expect(store.turns.map(\.scope) == ["records", nil])
    }

    @Test func aDraftEmptiedLosesItsScope() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records")
        store.draft = ""
        store.draft = "How many coins do I have?"
        store.ask(store.draft)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == [nil])
    }

    @Test func aNewerPrefillReplacesTheScope() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records")
        store.prefill("What should I read?", scope: "books")
        store.ask(store.draft)
        await settle(store)
        store.prefill("What should I play?", scope: "records")
        store.prefill("What's new?")
        store.ask(store.draft)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == ["books", nil])
    }

    @Test func aStarterOrAChipAsksUnscopedAndLeavesTheDraftItsScope() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records")
        store.ask(AskStarter(text: "What do I own?"))
        await settle(store)
        store.ask("And the oldest?", origin: .followUp)
        await settle(store)
        #expect(store.draft == "What should I play?", "a starter and a chip are questions of their own")
        store.ask(store.draft)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == [nil, nil, "records"])
    }

    @Test func everyReAskKeepsTheTurnsScope() async throws {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud)], error: AskError.privateCloudUnreachable)
        ])
        asker.script(.init(events: [
            .answer(.of("Rumours.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records", send: true)
        await settle(store)
        let failed = try #require(store.turns.last)
        #expect(failed.failure != nil)

        store.retry(failed)
        await settle(store)
        store.askAgain(try #require(store.turns.last))
        await settle(store)
        store.rerollPick(try #require(store.turns.last))
        await settle(store)

        #expect(store.turns.map(\.origin) == [.prefilled, .followUp, .reroll])
        #expect(asker.questions.withLock { $0 }.map(\.1) == [.conversation, .conversation, .conversation, .reroll])
        #expect(asker.scopes.withLock { $0 } == ["records", "records", "records", "records"])
    }

    @Test func editAndResendPutsTheTurnsScopeBackWithIt() async throws {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records", send: true)
        await settle(store)
        store.ask("How many coins do I have?")
        await settle(store)
        let scoped = try #require(store.turns.first)
        let unscoped = try #require(store.turns.last)

        store.edit(scoped)
        #expect(store.draft == "What should I play?")
        store.ask(store.draft)
        await settle(store)
        // The scope a prefill left goes with the draft it left it in.
        store.prefill("What should I read?", scope: "books")
        store.edit(unscoped)
        #expect(store.draft == "How many coins do I have?")
        store.ask(store.draft)
        await settle(store)

        #expect(asker.scopes.withLock { $0 } == ["records", nil, "records", nil])
    }

    @Test func editAndResendPutsThePhotoBackWhileThereArePixels() async throws {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.ask("What goes with this?")
        await settle(store)
        #expect(store.pendingPhoto == nil)

        store.edit(try #require(store.turns.last))
        #expect(store.draft == "What goes with this?")
        #expect(store.pendingPhoto?.photo.label == "Navy blazer")
    }

    @Test func newChatTakesTheScopeWithTheDraft() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.prefill("What should I play?", scope: "records")
        store.startOver()
        #expect(store.draft.isEmpty)
        store.draft = "What should I play?"
        store.ask(store.draft)
        await settle(store)
        #expect(asker.scopes.withLock { $0 } == [nil])
    }

    @Test func aScopedQuestionSentBeforeTheThreadIsReadKeepsItsScope() async {
        // The wait for the read is the turn's own task, and the scope has to
        // survive it.
        let url = temporaryLocation("askkit-early-scope").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Two."))]))
        let store = await storeOverASavedThread(asker: asker, url: url)

        store.prefill("two", scope: "records", send: true)
        await settle(store)
        await store.restoreIfNeeded()

        #expect(store.turns.map(\.question) == ["one", "two"])
        #expect(asker.scopes.withLock { $0 } == ["records"])
        #expect(store.turns.last?.scope == "records")
    }

    @Test func aScopedQuestionStillReachesAnEngineThatKnowsNoScopes() async {
        let store = AskConversationStore(
            domain: UIDomain(),
            engine: WordsOnlyAsker(),
            thread: AskThreadStore<UIRow>(
                appDirectory: "AskKitUITests",
                url: temporaryLocation("askkit-words-scope").appendingPathExtension("json")
            ),
            archive: AskThreadArchive<UIRow>(
                appDirectory: "AskKitUITests", directory: temporaryLocation("askkit-words-scope-archive")
            ),
            feedbackAttachments: AskFeedbackAttachments(
                appDirectory: "AskKitUITests", directory: temporaryLocation("askkit-words-scope-feedback")
            )
        )
        store.prefill("What should I play?", scope: "records", send: true)
        await settle(store)
        #expect(store.turns.last?.answer?.text == "Words.")
        #expect(store.turns.last?.failure == nil)
    }

    // MARK: - Another pick

    @Test func aPickWithTilesOffersAnotherPick() async throws {
        let asker = ScriptedAsker(.init(events: [
            .answer(.of("Wear the navy blazer.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker)
        store.ask("What should I wear?")
        await settle(store)
        #expect(store.offersAnotherPick)

        let turn = try #require(store.turns.last)
        store.rerollPick(turn)
        await settle(store)
        let asked = asker.questions.withLock { $0 }
        #expect(asked.map { $0.0 } == ["What should I wear?", "What should I wear?"])
        #expect(asked.last?.1 == .reroll)
        // A new turn, beneath the first: nothing shown is taken back.
        #expect(store.turns.count == 2)
    }

    @Test func nothingButASettledPickWithTilesOffersAnotherPick() async {
        let answers: [AskAnswer<UIRow>] = [
            .of("Six.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.count),
            .of("Nothing fits.", kind: AskQuestionKind.pick),
            .of("Wear the", tiles: [UIRow("Rumours")], truncated: true, kind: AskQuestionKind.pick),
            .of("Here they are.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.everyMatch),
            .of("No kind at all.", tiles: [UIRow("Rumours")])
        ]
        for answer in answers {
            let store = makeStore(asker: ScriptedAsker(.init(events: [.answer(answer)])))
            store.ask("q")
            await settle(store)
            #expect(!store.offersAnotherPick, "\(answer.text)")
        }
    }

    @Test func theDomainDecidesWhichKindsCanBeRerolled() async {
        var domain = UIDomain()
        domain.rerollKinds = [AskQuestionKind.lookup]

        let pick = makeStore(domain: domain, asker: ScriptedAsker(.init(events: [
            .answer(.of("Wear it.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ])))
        pick.ask("q")
        await settle(pick)
        #expect(!pick.offersAnotherPick)

        let lookup = makeStore(domain: domain, asker: ScriptedAsker(.init(events: [
            .answer(.of("That one.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.lookup))
        ])))
        lookup.ask("q")
        await settle(lookup)
        #expect(lookup.offersAnotherPick)
    }

    @Test func aCountIsNeverRerollableWhateverTheDomainSays() async {
        var domain = UIDomain()
        domain.rerollKinds = [AskQuestionKind.count]
        let store = makeStore(domain: domain, asker: ScriptedAsker(.init(events: [
            .answer(.of("Six.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.count))
        ])))
        store.ask("q")
        await settle(store)
        #expect(!store.offersAnotherPick)
    }

    @Test func theDomainCanSayAPickHasOneRightAnswer() async {
        // "My oldest record" is a pick, and another pick of it is a wrong one.
        var domain = UIDomain()
        domain.nonRerollableQuestions = ["Which is my oldest record?"]
        let store = makeStore(domain: domain, asker: ScriptedAsker(.init(events: [
            .answer(.of("Kind of Blue.", tiles: [UIRow("Kind of Blue")], kind: AskQuestionKind.pick))
        ])))
        store.ask("Which is my oldest record?")
        await settle(store)
        #expect(!store.offersAnotherPick)
    }

    @Test func aDeclinedFollowUpStaysGoneForTheThread() async throws {
        let asker = ScriptedAsker(.init(events: [
            .answer(.of("An answer.", followUps: ["Which is oldest?", "Any on vinyl?"]))
        ]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        let offered = store.followUps
        try #require(offered.count == 2)
        store.decline(offered[0])
        #expect(store.followUps.map(\.text) == ["Any on vinyl?"])
    }

    @Test func aFollowUpAndAStarterAreDeclinedApartWhateverTheirWords() async throws {
        // A follow-up is known by its words and a host's starter by its id, a
        // slug such as "vinyl". In one set, declining either would hide the
        // other wherever the two strings met.
        var domain = UIDomain()
        domain.starterIDs = ["owned", "1970", "vinyl"]
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer.", followUps: ["vinyl"]))]))
        let store = makeStore(domain: domain, asker: asker)
        await store.refresh()
        store.ask("q")
        await settle(store)
        let starter = try #require(store.availableStarters.first { $0.id == "vinyl" })

        store.decline(starter)
        #expect(store.followUps.map(\.text) == ["vinyl"], "declining a starter hid a follow-up")
        store.decline(try #require(store.followUps.first))
        #expect(store.followUps.isEmpty)
        #expect(store.availableStarters.map(\.id) == ["owned", "1970"])

        // And the other way about.
        store.startOver()
        store.ask("q")
        await settle(store)
        store.decline(try #require(store.followUps.first))
        #expect(store.availableStarters.map(\.id) == ["owned", "1970", "vinyl"], "declining a follow-up hid a starter")
    }

    // MARK: - A reader's verdict

    @Test func aVerdictIsKeptOnTheTurnAndSentToTheEngine() async throws {
        let attachments = temporaryLocation("askkit-feedback")
        defer { try? FileManager.default.removeItem(at: attachments) }
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(.of("Rumours.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker, attachmentsDirectory: attachments)
        store.ask("q")
        await settle(store)
        let turn = try #require(store.turns.last)

        store.rate(turn, .positive)
        #expect(store.turns.last?.feedback == .positive)
        await store.flushFeedback()

        let sent = asker.feedbacks.withLock { $0 }
        #expect(sent.count == 1)
        #expect(sent.first?.isLatestTurn == true)
        #expect(sent.first?.feedback == AskFeedback(
            sentiment: .positive, tier: .privateCloud, questionKind: AskQuestionKind.pick,
            tilesShown: 1, rowsRead: 1, wasTruncated: false
        ))
        // The attachment the engine handed back waits for the diagnostics row.
        let kept = await AskFeedbackAttachments(appDirectory: "unused", directory: attachments).urls()
        #expect(kept.count == 1)
    }

    @Test func withDiagnosticsOffAVerdictKeepsNoAttachment() async throws {
        // A host's own thumbs reach `rate` with the diagnostics row off,
        // where nothing could share an attachment, and a transcript would sit
        // on the device for nothing.
        let attachments = temporaryLocation("askkit-feedback-off")
        defer { try? FileManager.default.removeItem(at: attachments) }
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(.of("Rumours.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker, attachmentsDirectory: attachments)
        store.diagnosticsOverride = false
        #expect(!store.offersFeedback)
        store.ask("q")
        await settle(store)

        store.rate(try #require(store.turns.last), .positive)
        await store.flushFeedback()
        #expect(store.turns.last?.feedback == .positive)
        #expect(asker.feedbacks.withLock { $0 }.count == 1)
        // Nor is the engine asked to take one: the SDK logs and serializes the
        // session's transcript as it hands it over, kept or not.
        #expect(asker.feedbacks.withLock { $0 }.first?.isLatestTurn == false, "an attachment nothing keeps was taken")
        #expect(await AskFeedbackAttachments(appDirectory: "unused", directory: attachments).urls().isEmpty)
    }

    @Test func theSameThumbTwiceIsOneVerdictAndTheOtherReplacesIt() async throws {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        let turn = try #require(store.turns.last)

        store.rate(turn, .positive)
        store.rate(turn, .positive)
        store.rate(turn, .negative)
        await store.flushFeedback()
        #expect(store.turns.last?.feedback == .negative)
        #expect(asker.feedbacks.withLock { $0 }.map { $0.feedback.sentiment } == [.positive, .negative])
    }

    @Test func anOlderAnswerIsRatedWithoutAnAttachment() async throws {
        let asker = ScriptedAsker(.init(events: [.answer(.of("An answer."))]))
        let store = makeStore(asker: asker)
        store.ask("one")
        await settle(store)
        store.ask("two")
        await settle(store)
        let older = try #require(store.turns.first)

        store.rate(older, .negative)
        await store.flushFeedback()
        #expect(asker.feedbacks.withLock { $0 }.first?.isLatestTurn == false)
    }

    @Test func anAnswerGivenWithoutAModelIsRatedWithoutAnAttachment() async throws {
        // No tier is the domain's own answer. No session wrote it, and the kept
        // session's transcript would describe some other exchange.
        let asker = ScriptedAsker(.init(events: [.answer(.of("Hello.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(asker: asker)
        store.ask("hi")
        await settle(store)
        let turn = try #require(store.turns.last)

        store.rate(turn, .positive)
        await store.flushFeedback()
        #expect(asker.feedbacks.withLock { $0 }.first?.isLatestTurn == false)
    }

    @Test func newChatRemovesTheThreadsFeedbackAttachments() async throws {
        let attachments = temporaryLocation("askkit-feedback")
        defer { try? FileManager.default.removeItem(at: attachments) }
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(.of("Rumours.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker, attachmentsDirectory: attachments)
        store.ask("q")
        await settle(store)
        let turn = try #require(store.turns.last)

        // New Chat a moment after the thumb, while its attachment is still on
        // its way: it is written and then removed, never written afterwards.
        store.rate(turn, .negative)
        store.startOver()
        await store.flushFeedback()
        #expect(asker.feedbacks.withLock { $0 }.first?.isLatestTurn == true)
        let kept = await AskFeedbackAttachments(appDirectory: "unused", directory: attachments).urls()
        #expect(kept.isEmpty)
    }

    @Test func aFailedTurnCannotBeRated() async throws {
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        let turn = try #require(store.turns.last)

        store.rate(turn, .negative)
        await store.flushFeedback()
        #expect(store.turns.last?.feedback == nil)
        #expect(asker.feedbacks.withLock { $0 }.isEmpty)
    }

    @Test func aVerdictComesBackWithTheThread() async throws {
        let url = temporaryLocation("askkit-verdict").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let store = makeStore(
            domain: domain, asker: ScriptedAsker(.init(events: [.answer(.of("An answer."))])), threadURL: url
        )
        store.ask("q")
        await settle(store)
        let turn = try #require(store.turns.last)
        store.rate(turn, .negative)
        await store.flushPersistence()

        let reopened = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: url)
        await reopened.restoreIfNeeded()
        #expect(reopened.turns.last?.feedback == .negative)
    }

    // MARK: - A photo with the question

    private static let blazer = AskQuestionPhoto(label: "Navy blazer", reference: "asset-1")

    @Test func aPhotoWaitsInTheComposerAndGoesWithTheReadersQuestion() async throws {
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("It goes with grey."))]))
        let store = makeStore(asker: asker)
        store.attachPhoto(onePixel(), label: "Navy blazer", reference: "asset-1")
        #expect(store.pendingPhoto?.photo == Self.blazer)

        store.draft = "What goes with this?"
        store.ask(store.draft)
        await settle(store)

        let turn = try #require(store.turns.last)
        #expect(turn.photo == Self.blazer)
        #expect(turn.photoImage != nil)
        #expect(turn.answerSawPhoto)
        #expect(!turn.answeredWithoutPhoto)
        #expect(store.pendingPhoto == nil, "It left the composer with the question.")
        #expect(asker.imageLabels.withLock { $0 } == [["Navy blazer"]])
    }

    @Test func aStarterLeavesThePhotoForTheReadersOwnQuestion() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Three."))]))
        let store = makeStore(asker: asker)
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.ask(AskStarter(text: "What do I own?"))
        await settle(store)
        #expect(store.turns.last?.photo == nil)
        #expect(store.pendingPhoto != nil)
        #expect(asker.imageLabels.withLock { $0 } == [[]])
    }

    @Test func aPhotoTakenBackOutGoesNowhere() async {
        let asker = ScriptedAsker(.init(events: [.answer(.of("Three."))]))
        let store = makeStore(asker: asker)
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.removePhoto()
        store.ask("What do I own?")
        await settle(store)
        #expect(store.turns.last?.photo == nil)
        #expect(asker.imageLabels.withLock { $0 } == [[]])
    }

    @Test func aDomainThatTakesNoPhotosIsHandedNone() {
        var domain = UIDomain()
        domain.acceptsPhotos = false
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        store.attachPhoto(onePixel(), label: "Navy blazer")
        #expect(store.pendingPhoto == nil)
    }

    @Test func aTurnSaysNothingAboutItsPhotoUntilSomethingIsKnown() {
        var turn = AskTurn<UIRow>(question: "q", origin: .typed, photo: Self.blazer, photoImage: onePixel())
        #expect(!turn.answeredWithoutPhoto)
        turn.tier = .privateCloud
        turn.answerSawPhoto = true
        #expect(!turn.answeredWithoutPhoto)
        turn.tier = .onDevice
        turn.answerSawPhoto = false
        #expect(turn.answeredWithoutPhoto)
    }

    @Test func theThreadSaysWhenTheAnswerReadOnlyTheWords() async {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.onDevice), .answer(.of("From the words."))]),
            .init(events: [.tier(.privateCloud), .restarted(.onDevice), .tier(.onDevice), .answer(.of("Handed down."))]),
            .init(events: [.answer(.of("The app's own."))])
        ])
        let store = makeStore(asker: asker)
        for question in ["On the device?", "Handed down?", "With no model?"] {
            store.attachPhoto(onePixel(), label: "Navy blazer")
            store.ask(question)
            await settle(store)
        }
        // The photo went to Private Cloud Compute on the second, and the answer
        // on screen still came from the device.
        #expect(store.turns.map(\.answeredWithoutPhoto) == [true, true, true])
    }

    @Test func tryAgainSendsThePhotoAgain() async throws {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud)], error: AskError.privateCloudUnreachable),
            .init(events: [.tier(.privateCloud), .answer(.of("It goes with grey."))])
        ])
        let store = makeStore(asker: asker)
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.ask("What goes with this?")
        await settle(store)
        let failed = try #require(store.turns.last)
        #expect(failed.failure != nil)

        store.retry(failed)
        await settle(store)
        #expect(asker.imageLabels.withLock { $0 } == [["Navy blazer"], ["Navy blazer"]])
        #expect(store.turns.last?.answerSawPhoto == true)
    }

    @Test func aPhotoComesBackWithTheThreadWithoutItsPixels() async throws {
        let url = temporaryLocation("askkit-photo").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: [.tier(.onDevice), .answer(.of("From the words."))]))
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        store.attachPhoto(onePixel(), label: "Navy blazer", reference: "asset-1")
        store.ask("What goes with this?")
        await settle(store)
        await store.flushPersistence()

        let again = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Asked again."))]))
        let reopened = makeStore(domain: domain, asker: again, threadURL: url)
        await reopened.restoreIfNeeded()
        let restored = try #require(reopened.turns.last)
        #expect(restored.photo == Self.blazer)
        #expect(restored.photoImage == nil)
        #expect(restored.answeredWithoutPhoto, "The line under the question comes back with it.")

        // Asked again, it goes on the words alone: there are no pixels to send,
        // so even Private Cloud Compute answering has not seen the photo.
        reopened.askAgain(restored)
        await settle(reopened)
        #expect(again.imageLabels.withLock { $0 } == [[]])
        #expect(reopened.turns.last?.photo == Self.blazer)
        #expect(reopened.turns.last?.answeredWithoutPhoto == true)
    }

    @Test func newChatTakesTheWaitingPhotoWithIt() {
        let store = makeStore(asker: ScriptedAsker())
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.startOver()
        #expect(store.pendingPhoto == nil)
    }

    @Test func anEngineThatReadsNoPhotosFailsAPhotoTurnRatherThanDroppingThePhoto() async {
        let store = AskConversationStore(
            domain: UIDomain(),
            engine: WordsOnlyAsker(),
            thread: AskThreadStore<UIRow>(
                appDirectory: "AskKitUITests",
                url: temporaryLocation("askkit-words").appendingPathExtension("json")
            ),
            archive: AskThreadArchive<UIRow>(
                appDirectory: "AskKitUITests", directory: temporaryLocation("askkit-words-archive")
            ),
            feedbackAttachments: AskFeedbackAttachments(
                appDirectory: "AskKitUITests", directory: temporaryLocation("askkit-words-feedback")
            )
        )
        store.attachPhoto(onePixel(), label: "Navy blazer")
        store.ask("What goes with this?")
        await settle(store)
        #expect(store.turns.last?.failure?.error == .photosNotSupported)
        // No Try Again: it would send the photo again, and fail the same way.
        #expect(store.turns.last?.failure?.isRetryable == false)

        // With no photo, the same engine answers.
        store.ask("What do I own?")
        await settle(store)
        #expect(store.turns.last?.answer?.text == "Words.")
    }

    // MARK: - What an answer offers to do

    /// An offer the domain carries out itself: a `.perform`, the default kind.
    private static let lendBook = AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent")

    /// An offer that opens the host's editor instead: a `.handOff`.
    private static let addRecord = AskProposal(kind: .handOff, title: "Add Kind of Blue", actionLabel: "Add")

    /// A store whose one answer offers `proposal`, or `lendBook` when none is
    /// given.
    private func offeringStore(
        domain: UIDomain = UIDomain(), threadURL: URL? = nil, archiveDirectory: URL? = nil, proposal: AskProposal? = nil
    ) async throws -> (AskConversationStore<UIDomain>, AskTurn<UIRow>) {
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(AskAnswer(text: "The Peregrine is on your shelf.", proposal: proposal ?? Self.lendBook))
        ]))
        let store = makeStore(domain: domain, asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        store.ask("Can I lend The Peregrine to Sam?")
        await settle(store)
        return (store, try #require(store.turns.last))
    }

    @Test func theNewestCardTakesATapFromTheMomentItsAnswerLands() async throws {
        // Not from when the turn's stream ends a moment later: the card would
        // arrive reading "Not done" and then turn into buttons.
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .answer(AskAnswer(text: "The Peregrine is on your shelf.", proposal: Self.lendBook))],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("Can I lend The Peregrine to Sam?")
        await yieldUntil { store.turns.last?.answer != nil }
        let offer = try #require(store.turns.last)
        #expect(store.isThinking)
        #expect(store.proposalPhase(for: offer) == .awaiting)

        // A question waiting to be asked is newer, though it has no turn yet.
        asker.parksStop.withLock { $0 = true }
        store.stop(byReader: true)
        store.ask("And Rumours?")
        #expect(store.proposalPhase(for: offer) == .notDone)
        asker.releaseStop()
        store.stop(byReader: true)
    }

    @Test func aConfirmedOfferIsCarriedOutOnceAndSaysSo() async throws {
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain)
        #expect(store.proposalPhase(for: turn) == .awaiting)

        store.confirmProposal(turn)
        store.confirmProposal(turn)
        #expect(store.proposalPhase(for: turn) == .performing)
        await store.flushProposal()

        #expect(domain.performed.proposals == [Self.lendBook])
        #expect(store.turns.last?.proposalOutcome == .confirmed("Marked The Peregrine as lent."))
        #expect(store.proposalPhase(for: turn) == .done("Marked The Peregrine as lent."))
        #expect(store.proposalAnnouncement?.line == "Marked The Peregrine as lent.")

        // Done is done: the card takes no more taps.
        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.proposals.count == 1)
    }

    /// A hand-off never reaches the domain: the card opened the host's editor,
    /// and the turn records only that.
    @Test func aHandOffOpensTheEditorAndNeverPerforms() async throws {
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain, proposal: Self.addRecord)
        #expect(store.proposalPhase(for: turn) == .awaiting)

        store.handOffProposal(turn, line: "Opened in Add")
        #expect(store.proposalPhase(for: turn) == .handedOff("Opened in Add"))
        #expect(store.turns.last?.proposalOutcome == .handedOff("Opened in Add"))
        #expect(store.proposalAnnouncement?.line == "Opened in Add")

        await store.flushProposal()
        #expect(domain.performed.proposals.isEmpty)

        // Opened is settled: the card takes no more taps, either way.
        store.handOffProposal(turn, line: "Again")
        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(store.proposalPhase(for: turn) == .handedOff("Opened in Add"))
        #expect(domain.performed.proposals.isEmpty)
    }

    /// The two paths do not cross: a `.perform` is not settled by the hand-off
    /// route, which would file it as opened without anything being done.
    @Test func handingOffAPerformProposalDoesNothing() async throws {
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain)
        store.handOffProposal(turn, line: "Opened in Add")
        #expect(store.proposalPhase(for: turn) == .awaiting)
        #expect(store.turns.last?.proposalOutcome == nil)
    }

    @Test func aDeclinedOfferIsNeverCarriedOut() async throws {
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain)
        store.declineProposal(turn)
        #expect(store.proposalPhase(for: turn) == .declined)
        #expect(store.proposalAnnouncement?.line == AskAnnouncement.proposal(.declined))

        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.proposals.isEmpty)
    }

    @Test func anOfferLeftUnansweredTakesNoTapOnceTheReaderAsksAgain() async throws {
        let domain = UIDomain()
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.answer(AskAnswer(text: "The Peregrine is on your shelf.", proposal: Self.lendBook))]),
            .init(events: [.answer(.of("Rumours is on your shelf too."))])
        ])
        let store = makeStore(domain: domain, asker: asker)
        store.ask("Can I lend The Peregrine to Sam?")
        await settle(store)
        let offer = try #require(store.turns.last)
        store.ask("And Rumours?")
        await settle(store)

        // Still on screen, since nothing the thread showed is taken back, but
        // no longer something to confirm.
        #expect(store.proposalPhase(for: offer) == .notDone)
        store.confirmProposal(offer)
        store.declineProposal(offer)
        await store.flushProposal()
        #expect(domain.performed.proposals.isEmpty)
        #expect(store.turns.first?.proposalOutcome == nil)
    }

    @Test func anOfferThatFailedSaysSoAndIsOfferedAgain() async throws {
        var domain = UIDomain()
        domain.performError = AskProposalFailure(line: "That isn't on the shelf any more.")
        let (store, turn) = try await offeringStore(domain: domain)

        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(store.proposalPhase(for: turn) == .failed("That isn't on the shelf any more.", canRetry: true))
        let first = try #require(store.proposalAnnouncement)

        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.proposals.count == 2)
        // The same line twice is two settlements, so VoiceOver hears both.
        let second = try #require(store.proposalAnnouncement)
        #expect(second.line == first.line)
        #expect(second != first)
    }

    @Test func aFailureNotWrittenForTheCardShowsNoneOfItsWords() async throws {
        var domain = UIDomain()
        domain.performError = CocoaError(.fileWriteNoPermission)
        let (store, turn) = try await offeringStore(domain: domain)
        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(store.turns.last?.proposalOutcome == .failed(nil))
        #expect(store.proposalAnnouncement?.line == AskAnnouncement.proposal(.failed(nil)))
    }

    @Test func whatCameOfAnOfferComesBackWithTheThread() async throws {
        let url = temporaryLocation("askkit-offer").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let (store, turn) = try await offeringStore(domain: domain, threadURL: url)
        store.confirmProposal(turn)
        await store.flushProposal()
        await store.flushPersistence()

        let reopened = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: url)
        await reopened.restoreIfNeeded()
        let restored = try #require(reopened.turns.last)
        #expect(restored.answer?.proposal == Self.lendBook)
        #expect(reopened.proposalPhase(for: restored) == .done("Marked The Peregrine as lent."))
    }

    /// A store that keeps its chats, whose one answer offers `lendBook`, and
    /// whose domain's perform waits for the test to release it: a host's
    /// perform that makes a network call, which the reader outruns with New
    /// Chat.
    private func slowOfferingStore(
        threadURL: URL, archiveDirectory: URL
    ) async throws -> (UIDomain, AskConversationStore<UIDomain>, AskTurn<UIRow>) {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        domain.performed.parks.withLock { $0 = true }
        let (store, turn) = try await offeringStore(domain: domain, threadURL: threadURL, archiveDirectory: archiveDirectory)
        return (domain, store, turn)
    }

    @Test func aProposalCarriedOutAfterItsChatEndedSaysWhatCameOfItWhenTheChatReopens() async throws {
        // Lost with the chat, the outcome would leave the filed card offering
        // the action again, and a second tap would do it twice.
        let threadURL = temporaryLocation("askkit-offer-filed").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-offer-filed")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (domain, store, turn) = try await slowOfferingStore(threadURL: threadURL, archiveDirectory: archiveDirectory)

        store.confirmProposal(turn)
        await domain.performed.isParked()
        store.startOver()
        await store.flushPersistence()
        domain.performed.release()
        await store.flushProposal()
        await store.flushPersistence()

        // Written into the chat's filing on disk, not only held in memory.
        let archive = AskThreadArchive<UIRow>(appDirectory: "unused", directory: archiveDirectory)
        let filed = try #require(await archive.summaries().first)
        guard case .thread(let onDisk, _) = await archive.entries(for: filed.id) else {
            Issue.record("the chat New Chat filed reads back")
            return
        }
        #expect(onDisk.last?.proposalOutcome == .confirmed("Marked The Peregrine as lent."))

        await store.openThread(filed)
        let reopened = try #require(store.turns.last)
        #expect(store.proposalPhase(for: reopened) == .done("Marked The Peregrine as lent."))
        store.confirmProposal(reopened)
        await store.flushProposal()
        #expect(domain.performed.proposals.count == 1)
    }

    @Test func aChatReopenedWhileItsProposalIsCarriedOutOffersNothingToConfirm() async throws {
        // Offered again, the card's tap would run a second perform beside the
        // first.
        let threadURL = temporaryLocation("askkit-offer-reopened").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-offer-reopened")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (domain, store, turn) = try await slowOfferingStore(threadURL: threadURL, archiveDirectory: archiveDirectory)

        store.confirmProposal(turn)
        await domain.performed.isParked()
        store.startOver()
        await store.flushPersistence()
        await store.openThread(try #require(store.history.first))
        let reopened = try #require(store.turns.last)
        #expect(store.proposalPhase(for: reopened) == .performing)
        store.confirmProposal(reopened)

        domain.performed.release()
        await store.flushProposal()
        await store.flushPersistence()
        #expect(domain.performed.proposals.count == 1)
        // What came of it lands on the turn read back, and is saved with it.
        #expect(store.proposalPhase(for: try #require(store.turns.last)) == .done("Marked The Peregrine as lent."))
        let relaunched = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.proposalPhase(for: try #require(relaunched.turns.last)) == .done("Marked The Peregrine as lent."))
    }

    @Test func aYesIsSavedBeforeTheAppIsAskedAndAfterAQuitItTakesNoTap() async throws {
        // An app quit while the domain works: the turn read back can't know
        // what came of the yes, and confirmed again it could be done twice.
        let threadURL = temporaryLocation("askkit-offer-quit").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-offer-quit")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (domain, store, turn) = try await slowOfferingStore(threadURL: threadURL, archiveDirectory: archiveDirectory)
        store.confirmProposal(turn)
        await domain.performed.isParked()
        await store.flushPersistence()
        guard case .thread(let saved, _) = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load() else {
            Issue.record("the thread was saved")
            return
        }
        #expect(saved.last?.proposalOutcome == .performing)

        let relaunched = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        await relaunched.restoreIfNeeded()
        let restored = try #require(relaunched.turns.last)
        #expect(relaunched.proposalPhase(for: restored) == .outcomeUnknown)
        relaunched.confirmProposal(restored)
        relaunched.declineProposal(restored)
        await relaunched.flushProposal()
        #expect(domain.performed.proposals.count == 1)
        #expect(relaunched.turns.last?.proposalOutcome == .performing)

        domain.performed.release()
        await store.flushProposal()
    }

    @Test func theDomainIsAskedOnlyOnceTheYesIsOnDisk() async throws {
        // Asked at once, beside a write still queued, a perform could land
        // first, and an app killed meanwhile would read the card back with no
        // yes on it and offer the action again.
        let threadURL = temporaryLocation("askkit-offer-yes-first").appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: threadURL) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let (store, turn) = try await offeringStore(domain: domain, threadURL: threadURL)
        await store.flushPersistence()
        domain.performed.watchedThread.withLock { $0 = threadURL }

        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.outcomesOnDiskAtEntry.withLock { $0 } == [.performing])
        #expect(store.proposalPhase(for: turn) == .done("Marked The Peregrine as lent."))
    }

    @Test func aYesTheDiskWontSaveIsNeverCarriedOut() async throws {
        // Carried out with the yes on disk nowhere, the action could be done
        // again by a card read back after a quit. So nothing is done, the card
        // says it couldn't be, and the reader can say yes again.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let (store, turn) = try await offeringStore(domain: domain, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.flushPersistence()
        try setMode(0o500, folder.folder)

        store.confirmProposal(turn, awaitingTheOutcome: true)
        #expect(store.proposalPhase(for: turn) == .performing, "the card took a second tap while the yes was saved")
        await store.flushProposal()
        #expect(domain.performed.proposals.isEmpty, "carried out with the yes saved nowhere")
        #expect(store.turns.last?.proposalOutcome == .failed(nil))
        #expect(store.proposalPhase(for: turn) == .failed(nil, canRetry: true))
        #expect(store.proposalAnnouncement?.line == AskAnnouncement.proposal(.failed(nil)))

        try setMode(0o755, folder.folder)
        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.proposals == [Self.lendBook])
        #expect(store.proposalPhase(for: turn) == .done("Marked The Peregrine as lent."))
    }

    @Test func aYesWhoseChatEndsBeforeItIsSavedIsNotCarriedOut() async throws {
        // A host's own New Chat in the same breath as the yes ends the chat
        // before the yes's write runs: the yes is never saved as the chat on
        // screen, so nothing is done, and the chat's filing says so and offers
        // the action again.
        let threadURL = temporaryLocation("askkit-offer-ended").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-offer-ended")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let (store, turn) = try await offeringStore(domain: domain, threadURL: threadURL, archiveDirectory: archiveDirectory)
        await store.flushPersistence()

        store.confirmProposal(turn)
        store.startOver()
        await store.flushProposal()
        await store.flushPersistence()
        #expect(domain.performed.proposals.isEmpty)

        await store.openThread(try #require(store.history.first))
        let reopened = try #require(store.turns.last)
        #expect(store.proposalPhase(for: reopened) == .failed(nil, canRetry: true))
        store.confirmProposal(reopened)
        await store.flushProposal()
        #expect(domain.performed.proposals == [Self.lendBook])
    }

    @Test func theDomainCarriesAProposalOutOffTheMainActor() async throws {
        // A plain `nonisolated async` perform runs where it is called from,
        // and a host's slow one on the main actor would hitch the screen.
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain)
        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.ranOnTheMainThread.withLock { $0 } == [false])
    }

    @Test func theCardsOwnYesWaitsOnTheOutcomeForTheFocusAndAQuestionDropsIt() async throws {
        // An outcome that lands after the reader asked something else would
        // pull their focus back to the card they left.
        let domain = UIDomain()
        domain.performed.parks.withLock { $0 = true }
        let (store, turn) = try await offeringStore(domain: domain)
        store.confirmProposal(turn, awaitingTheOutcome: true)
        #expect(store.proposalOutcomeFocus == turn.id)
        await domain.performed.isParked()
        store.ask("And Rumours?")
        #expect(store.proposalOutcomeFocus == nil)
        domain.performed.release()
        await store.flushProposal()
        await settle(store)
        #expect(store.proposalOutcomeFocus == nil)
    }

    @Test func theOutcomeTheCardWaitedOnIsTakenOnceAndAHostsOwnYesWaitsOnNothing() async throws {
        // Taken by the card's line, the request goes; a host's own control
        // confirming has no card waiting on it.
        let (store, turn) = try await offeringStore()
        store.declineProposal(turn, awaitingTheOutcome: true)
        #expect(store.proposalPhase(for: turn) == .declined)
        #expect(store.proposalOutcomeFocus == turn.id)
        store.proposalOutcomeFocused(UUID())
        #expect(store.proposalOutcomeFocus == turn.id)
        store.proposalOutcomeFocused(turn.id)
        #expect(store.proposalOutcomeFocus == nil)

        let (hosted, offer) = try await offeringStore()
        hosted.confirmProposal(offer)
        await hosted.flushProposal()
        #expect(hosted.proposalPhase(for: offer) == .done("Marked The Peregrine as lent."))
        #expect(hosted.proposalOutcomeFocus == nil)
    }

    @Test func aStoppedTurnOffersNothingToConfirm() async throws {
        // A proposal rides the finished answer, and the reader stopped this one
        // first: its text stays as its answer, and no card comes with it.
        let asker = ScriptedAsker(.init(
            events: [.tier(.privateCloud), .partial("The Peregrine is on your shelf and")],
            hangs: true
        ))
        let store = makeStore(asker: asker)
        store.ask("Can I lend The Peregrine to Sam?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.stop()

        let turn = try #require(store.turns.last)
        #expect(turn.answer != nil)
        #expect(store.proposalPhase(for: turn) == nil)
    }

    // MARK: - Earlier chats

    /// A store that keeps its chats, over private files, and an archive over
    /// the same folder to check it against.
    private func keepingStore(
        asker: ScriptedAsker, threadURL: URL, archiveDirectory: URL
    ) -> (AskConversationStore<UIDomain>, AskThreadArchive<UIRow>) {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let store = makeStore(domain: domain, asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        return (store, AskThreadArchive<UIRow>(appDirectory: "unused", directory: archiveDirectory))
    }

    /// A private folder holding the thread, with the archive in it, as an
    /// app's are: a thread set aside lands beside the thread.
    private func privateFolder() throws -> (folder: URL, thread: URL, archive: URL) {
        let folder = temporaryLocation("askkit-store-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appending(path: "ask-thread.json"), folder.appending(path: "threads", directoryHint: .isDirectory))
    }

    private func setAsideFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("ask-thread-unreadable-") && $0.hasSuffix(".json") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    private func earlierEntry(_ question: String, at seconds: TimeInterval = 1_000_000) -> AskThreadEntry<UIRow> {
        AskThreadEntry(
            question: question, text: "Rumours.", answer: .of("Rumours.", tiles: [UIRow("Rumours")]),
            tier: .privateCloud, askedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func newChatFilesTheChatItEnds() async {
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        store.ask("Which records do I own?")
        await settle(store)
        #expect(store.currentSummary?.title == "Which records do I own?")

        store.startOver()
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Which records do I own?"])
        #expect(await archive.summaries().count == 1)
        #expect(store.currentSummary == nil)
    }

    @Test func aChatTheDomainDoesNotKeepIsNeverFiled() async {
        let archiveDirectory = temporaryLocation("askkit-history")
        defer { try? FileManager.default.removeItem(at: archiveDirectory) }
        let asker = ScriptedAsker(.init(events: [.answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(asker: asker, archiveDirectory: archiveDirectory)
        #expect(!store.offersHistory)
        store.ask("Which records do I own?")
        await settle(store)
        #expect(store.currentSummary == nil)

        store.startOver()
        await store.flushPersistence()
        #expect(store.history.isEmpty)
        #expect(await AskThreadArchive<UIRow>(appDirectory: "unused", directory: archiveDirectory).summaries().isEmpty)
    }

    @Test func newChatMidAnswerFilesTheTurnInFlightToo() async throws {
        // New Chat settles the turn in flight before it files the chat, as
        // opening an earlier chat does, so the chat comes back whole.
        let threadURL = temporaryLocation("askkit-history-midanswer").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history-midanswer")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]),
            .init(events: [.tier(.privateCloud), .partial("Two from 1969")], hangs: true)
        ])
        let (store, _) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        store.ask("Which records do I own?")
        await settle(store)
        store.ask("Anything from 1969?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }

        store.startOver()
        await store.flushPersistence()
        let filed = try #require(store.history.first)
        await store.openThread(filed)
        #expect(store.turns.map(\.question) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.turns.last?.answer?.text == "Two from 1969")
        #expect(store.turns.last?.answer?.isTruncated == true)
    }

    @Test func theCaptionNamesWhoAnswersNextWhileAQuestionWaitsForAChatToOpen() async throws {
        // While an earlier chat comes in, the newest turn on screen belongs to
        // the chat being replaced, so its tier says nothing about the question
        // waiting to be asked.
        let threadURL = temporaryLocation("askkit-open-caption").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-caption")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Answer."))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        #expect(store.turns.last?.tier == .privateCloud)
        store.status.apply(.init(nextTier: .onDevice))
        asker.parksReset.withLock { $0 = true }

        let opening = Task { await store.openThread(earlier) }
        await asker.resetIsParked()
        store.ask("Which is the oldest?")
        #expect(store.isThinking)
        #expect(store.captionTier == .onDevice)
        asker.releaseReset()
        await opening.value
        await settle(store)
    }

    @Test func openingAnEarlierChatFilesTheOneOnScreenAndBringsItBack() async throws {
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road.", tiles: [UIRow("Abbey Road")]))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)

        await store.openThread(earlier)
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        // Its session is started over with the chat's recap, as a relaunch's is.
        #expect(asker.resets.withLock { $0 } == 1)
        #expect(asker.resumedTails.withLock { $0 }.last?.map(\.question) == ["Which records do I own?"])
        // The chat it replaced is on the list, and the one it opened is not.
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load().entries
        #expect(onDisk.map(\.question) == ["Which records do I own?"])
    }

    @Test func openingAnEarlierChatTakesTheDraftsScopeWithIt() async throws {
        let threadURL = temporaryLocation("askkit-history-scope").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history-scope")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours."))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.prefill("What should I play?", scope: "records")

        await store.openThread(earlier)
        #expect(store.draft.isEmpty)
        store.draft = "What should I play?"
        store.ask(store.draft)
        await settle(store)

        #expect(asker.scopes.withLock { $0 } == [nil])
    }

    @Test func openingAnEarlierChatWarmsItsNextQuestionOnceTheReaderTypes() async throws {
        // The reset that starts its session over takes the warm, and the
        // question asked next starts a fresh session — its recap goes after
        // the prefix a warm caches, so the warm serves it as it serves a first.
        // It is made when that question begins, not when the chat opens.
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker()
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.prewarm()

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(asker.lifecycle.withLock { $0 } == ["stop", "reset", "resume"])

        store.draft = "And the rest?"
        let expected = ["stop", "reset", "resume", "prewarm"]
        await eventually { asker.lifecycle.withLock { $0 } == expected }
        #expect(asker.lifecycle.withLock { $0 } == expected)
    }

    @Test func anEarlierChatGoneFromDiskLeavesTheList() async throws {
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        let summary = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.loadHistory()
        #expect(store.history.count == 1)

        try FileManager.default.removeItem(at: archiveDirectory.appending(path: "\(summary.id.uuidString).json"))
        await store.openThread(summary)
        #expect(store.history.isEmpty)
        #expect(store.turns.isEmpty)
    }

    @Test func anEarlierChatOpensOverAThreadThatWasSetAside() async throws {
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let unreadable = Data("not a thread".utf8)
        try unreadable.write(to: threadURL)
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        #expect(store.readFailed)

        let summary = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.openThread(summary)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        #expect(!store.showsUnreadableThreadNotice)
        #expect(try setAsideFiles(in: folder).map { try Data(contentsOf: $0) } == [unreadable])
    }

    @Test func aThreadThatCouldNotBeReadIsNotWrittenOverByAnEarlierChat() async throws {
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: threadURL.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).save([earlierEntry("On screen last time")])
        let written = try Data(contentsOf: threadURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: threadURL.path(percentEncoded: false))
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        #expect(store.readFailed)

        let summary = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.openThread(summary)
        await store.flushPersistence()
        #expect(store.turns.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: threadURL.path(percentEncoded: false))
        #expect(try Data(contentsOf: threadURL) == written)
    }

    @Test func openingAnEarlierChatBeforeTheThreadIsReadFilesTheThreadFirst() async throws {
        // A host opening a chat as the app launches, before the screen has
        // read the thread. Opened at once, the chat on screen would still be
        // empty, so the thread on disk would be written over without being
        // filed.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).save([earlierEntry("On screen last time", at: 2_000_000)])
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        #expect(store.history.map(\.title) == ["On screen last time"])
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load().entries
        #expect(onDisk.map(\.question) == ["Which records do I own?"])
    }

    @Test func newChatBeforeTheThreadIsReadFilesTheThreadRatherThanDroppingIt() async throws {
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).save([earlierEntry("On screen last time")])
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)

        store.startOver()
        await eventually { store.history.map(\.title) == ["On screen last time"] }
        await store.flushPersistence()
        #expect(store.turns.isEmpty)
        #expect(await archive.summaries().map(\.title) == ["On screen last time"])
        guard case .empty = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load() else {
            Issue.record("the chat New Chat ended is still the thread on disk")
            return
        }
    }

    @Test func deletingEveryChatBeforeTheThreadIsReadLeavesNothingToComeBack() async throws {
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).save([earlierEntry("On screen last time")])
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        _ = try #require(await archive.archive([earlierEntry("Which records do I own?")]))

        store.deleteAllThreads()
        await store.restoreIfNeeded()
        await eventually { store.hasRestored && store.turns.isEmpty && store.history.isEmpty }
        await store.flushPersistence()
        #expect(store.turns.isEmpty)
        #expect(await archive.summaries().isEmpty)
        guard case .empty = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load() else {
            Issue.record("a deleted chat came back as the thread")
            return
        }
    }

    @Test func openingAChatFromAFullHistoryKeepsEveryOtherChat() async throws {
        // The chat being opened leaves the list, so filing the chat on screen
        // has room without taking the oldest chat.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road."))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let cap = AskThreadArchive<UIRow>.maxThreads
        var filed: [AskThreadSummary] = []
        for index in 0..<cap {
            filed.append(try #require(await archive.archive([earlierEntry("q\(index)", at: 1_000_000 + Double(index) * 3_600)])))
        }
        store.ask("Anything from 1969?")
        await settle(store)

        await store.openThread(try #require(filed.last))
        await store.flushPersistence()
        let listed = await archive.summaries()
        #expect(listed.count == cap)
        #expect(listed.contains { $0.id == filed[0].id })
        #expect(listed.contains { $0.title == "Anything from 1969?" })
    }

    @Test func deletingEveryChatTakesAThreadSetAsideToo() async throws {
        // Every chat means the one this build couldn't read as well.
        let (folder, threadURL, archiveDirectory) = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not a thread".utf8).write(to: threadURL)
        let (store, _) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        #expect(setAsideFiles(in: folder).count == 1)

        store.deleteAllThreads()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder).isEmpty)
    }

    @Test func deletingAnEarlierChatForgetsIt() async throws {
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: ScriptedAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        let summary = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()
        #expect(store.history.map(\.id) == [summary.id])

        await store.deleteThread(summary)
        #expect(store.history.isEmpty)
        #expect(await archive.summaries().isEmpty)
    }

    /// Delete All Chats: the earlier chats go, and so does the one on screen —
    /// ended, and not filed on its way out the way New Chat would file it.
    @Test func deletingEveryChatForgetsTheEarlierOnesAndTheOneOnScreen() async throws {
        let threadURL = temporaryLocation("askkit-history-thread").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-history")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road.", tiles: [UIRow("Abbey Road")]))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        _ = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        await store.loadHistory()
        #expect(store.history.count == 1)
        #expect(store.currentSummary != nil)

        store.deleteAllThreads()
        #expect(store.turns.isEmpty)
        #expect(store.history.isEmpty)
        await store.flushPersistence()

        #expect(store.history.isEmpty)
        #expect(await archive.summaries().isEmpty)
        guard case .empty = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load() else {
            Issue.record("the chat on screen is still on disk")
            return
        }
    }

    @Test func aPerLaunchChatsAttachmentsGoWithTheLaunch() async throws {
        // The chat ended with the process before this one, and a transcript of
        // it has no business staying shareable from the settings card.
        let attachments = temporaryLocation("askkit-feedback-perlaunch")
        defer { try? FileManager.default.removeItem(at: attachments) }
        let left = AskFeedbackAttachments(appDirectory: "unused", directory: attachments)
        await left.save(Data("last launch".utf8), sentiment: .negative, at: Date(timeIntervalSince1970: 1_000_000))
        let store = makeStore(asker: ScriptedAsker(), attachmentsDirectory: attachments)

        await store.restoreIfNeeded()
        await store.flushFeedback()
        #expect(await left.urls().isEmpty)
    }

    @Test func aVerdictBeforeTheReadKeepsItsAttachmentAndLastLaunchsGo() async throws {
        // Queued ahead of the verdict's save, so the removal never takes the
        // attachment the reader has just made.
        let attachments = temporaryLocation("askkit-feedback-perlaunch")
        defer { try? FileManager.default.removeItem(at: attachments) }
        let left = AskFeedbackAttachments(appDirectory: "unused", directory: attachments)
        await left.save(Data("last launch".utf8), sentiment: .negative, at: Date(timeIntervalSince1970: 1_000_000))
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")], kind: AskQuestionKind.pick))
        ]))
        let store = makeStore(asker: asker, attachmentsDirectory: attachments)
        store.ask("q")
        await settle(store)

        store.rate(try #require(store.turns.last), .positive)
        await store.restoreIfNeeded()
        await store.flushFeedback()
        let kept = await left.urls()
        #expect(kept.count == 1)
        #expect(try kept.map { try Data(contentsOf: $0) } == [Data("attachment".utf8)])
    }

    @Test func aPrefilledQuestionWarmsNothingUntilTheReaderEditsIt() async {
        // A link can come from anywhere, and a warm on Private Cloud Compute
        // spends a request of the reader's quota though they sent nothing.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        await store.prewarm()
        store.prefill("What should I play tonight?")
        await letStrayWarmsLand()
        #expect(asker.prewarms.withLock { $0 } == 0)
        // The screen appearing over it, or the app coming back, warms nothing
        // either.
        await store.prewarm()
        await store.rewarm()
        #expect(asker.prewarms.withLock { $0 } == 0)

        store.draft += " Something calm"
        await eventually { asker.prewarms.withLock { $0 } == 1 }
        store.draft += "?"
        await letStrayWarmsLand()
        #expect(asker.prewarms.withLock { $0 } == 1, "one warm for the question, not one per keystroke")
    }

    @Test func oneWindowClosingKeepsTheWarmTheOtherIsUsing() async {
        // One store behind a screen in each of two windows.
        let asker = ScriptedAsker()
        let store = makeStore(asker: asker)
        let first = UUID()
        let second = UUID()
        await store.prewarm(for: first)
        await store.prewarm(for: second)

        await store.screenDisappeared(first)
        #expect(asker.forgets.withLock { $0 } == 0, "the other window's screen is still up")
        store.draft = "W"
        await eventually { asker.prewarms.withLock { $0 } == 1 }
        #expect(asker.prewarms.withLock { $0 } == 1)

        await store.screenDisappeared(second)
        #expect(asker.forgets.withLock { $0 } == 1)
    }

    @Test func aHandOffIsNeverPerformed() async throws {
        // The card opens the host's editor for a hand-off; a confirm that
        // reaches the store for one is ignored, never handed to `perform`.
        let domain = UIDomain()
        let (store, turn) = try await offeringStore(domain: domain, proposal: Self.addRecord)

        store.confirmProposal(turn)
        await store.flushProposal()
        #expect(domain.performed.proposals.isEmpty)
        #expect(store.turns.last?.proposalOutcome == nil)
        #expect(store.proposalPhase(for: turn) == .awaiting)
    }

    @Test func aSnapshotAfterTheAnswerChangesNothing() async {
        let asker = ScriptedAsker(.init(events: [
            .tier(.privateCloud), .partial("You own"), .answer(.of("You own three.")), .partial("stray words")
        ]))
        let store = makeStore(asker: asker)
        store.ask("What do I own?")
        await settle(store)
        #expect(store.turns.last?.text == "You own three.")
    }

    // MARK: - When the disk refuses
    //
    // A read-only folder stands in for a locked device or a full disk: the
    // thread store and the archive are actors over real files, and fail the
    // way they fail there. Every case ends with the chat on disk somewhere.

    private func setMode(_ mode: Int, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Every folder and file under `folder` writable again, so the scratch
    /// folder can be removed.
    private func makeWritable(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
            for name in names {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url.appending(path: name).path(percentEncoded: false)
                )
            }
        }
    }

    private func entriesOnDisk(_ url: URL) async -> [String] {
        await AskThreadStore<UIRow>(appDirectory: "unused", url: url).load().entries.map(\.question)
    }

    private func answeringAsker() -> ScriptedAsker {
        ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Answer."))]))
    }

    @Test func newChatThatCannotFileTheChatSetsItAsideForTheNextLaunch() async throws {
        // Filed nowhere and cleared, the chat would be gone. It is written as
        // the thread and set aside beside it, and the next launch files it.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, folder.archive)

        store.startOver()
        await store.flushPersistence()
        #expect(await archive.summaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)))
        let aside = setAsideFiles(in: folder.folder)
        #expect(aside.count == 1)
        let kept = try aside.map { try JSONDecoder().decode([AskThreadEntry<UIRow>].self, from: Data(contentsOf: $0)).map(\.question) }
        #expect(kept == [["Anything from 1969?"]])

        try setMode(0o755, folder.archive)
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.history.map(\.title) == ["Anything from 1969?"])
    }

    @Test func newChatThatCanNeitherFileNorMoveTheChatLeavesItInPlace() async throws {
        // Nothing can be written: the chat stays the thread, the next chat's
        // answers aren't written over it, and once the disk takes writes
        // again it is set aside for the next launch to file and the next chat
        // is saved.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        let written = try Data(contentsOf: folder.thread)
        try setMode(0o500, folder.folder)

        store.startOver()
        await store.flushPersistence()
        store.ask("Which is the oldest?")
        await settle(store)
        await store.flushPersistence()
        #expect(try Data(contentsOf: folder.thread) == written, "the only copy was written over")
        #expect(await archive.summaries().isEmpty)

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which is the oldest?"])
        #expect(setAsideFiles(in: folder.folder).count == 1)

        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.history.map(\.title) == ["Anything from 1969?"])
        #expect(relaunched.turns.map(\.question) == ["Which is the oldest?"])
    }

    @Test func anEarlierChatAskedForAsNewChatEndsOpensOnlyOnceNewChatHasSettled() async throws {
        // New Chat's writes run on the write queue, after the tap. A chat
        // opened behind it would find the thread's place free before those
        // writes held it for the chat they couldn't file or move, and open
        // over that chat's last copy.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        #expect(await archive.archive([earlierEntry("Anything from 1970?")]) != nil)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        let earlier = try #require(store.history.first)
        let written = try Data(contentsOf: folder.thread)
        try setMode(0o500, folder.archive)
        try setMode(0o500, folder.folder)

        store.startOver()
        await store.openThread(earlier)
        #expect(store.turns.isEmpty, "an earlier chat opened over a chat New Chat could neither file nor move")
        await store.flushPersistence()
        #expect(try Data(contentsOf: folder.thread) == written)
    }

    @Test func turnsAskedWhileAChatNewChatCouldNotFileHoldsThePlaceAreKeptAsAChatOfTheirOwn() async throws {
        // Written nowhere, they would go with an app quit before the place
        // came free, as the turns asked beside a thread that couldn't be read
        // don't.
        let folder = try privateFolder()
        let archiveDirectory = temporaryLocation("askkit-unfiled-archive")
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        defer {
            makeWritable(archiveDirectory, folder.folder)
            try? FileManager.default.removeItem(at: folder.folder)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, archiveDirectory)
        try setMode(0o500, folder.folder)
        store.startOver()
        await store.flushPersistence()

        try setMode(0o755, archiveDirectory)
        store.ask("Which is the oldest?")
        await settle(store)
        await store.flushPersistence()
        #expect(await archive.summaries().map(\.title) == ["Which is the oldest?"], "a turn was written nowhere")
        #expect(store.history.isEmpty, "the chat on screen is listed as an earlier one")

        // Once the place is free, they are the thread, and their filing goes.
        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which is the oldest?"])
        #expect(await archive.summaries().map(\.title) == ["Anything from 1969?"])
    }

    @Test func aPerLaunchChatsAttachmentsTheDiskKeptAreRemovedOnceTheyCanBe() async throws {
        // A `.perLaunch` domain keeps no thread, but its verdicts keep
        // attachments, and one a New Chat couldn't remove is owed like any
        // other.
        let attachments = temporaryLocation("askkit-owed-perlaunch")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer {
            makeWritable(attachments)
            try? FileManager.default.removeItem(at: attachments)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(asker: asker, attachmentsDirectory: attachments)
        let kept = AskFeedbackAttachments(appDirectory: "unused", directory: attachments)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        store.rate(try #require(store.turns.last), .positive)
        await store.flushFeedback()
        #expect(await kept.urls().count == 1)
        try setMode(0o500, attachments)
        store.startOver()
        await store.flushFeedback()
        #expect(await kept.urls().count == 1, "the folder refused the removal")

        try setMode(0o755, attachments)
        await store.refresh()
        await store.flushPersistence()
        #expect(await kept.urls().isEmpty, "a transcript outlived its chat")
    }

    @Test func newChatNeverDeletesAThreadThatCouldNotBeReadEvenWhenItWontMove() async throws {
        // The banner said it was kept. New Chat sets it aside, and where it
        // won't move it stays in place, written over by nothing.
        let folder = try privateFolder()
        let archiveDirectory = temporaryLocation("askkit-held-archive")
        defer {
            makeWritable(folder.folder)
            try? FileManager.default.removeItem(at: folder.folder)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        let written = try Data(contentsOf: folder.thread)
        try setMode(0o000, folder.thread)
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        #expect(store.readFailed)
        store.ask("Anything from 1969?")
        await settle(store)
        try setMode(0o500, folder.folder)

        store.startOver()
        await store.flushPersistence()
        store.ask("Which is the oldest?")
        await settle(store)
        await store.flushPersistence()
        // The next chat's turns are filed beside it too, off the list while
        // they are on screen.
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(Set(await archive.summaries().map(\.title)) == ["Anything from 1969?", "Which is the oldest?"])
        try setMode(0o755, folder.folder)
        try setMode(0o644, folder.thread)
        #expect(try Data(contentsOf: folder.thread) == written, "the thread that couldn't be read went")
    }

    @Test func anEarlierChatDoesNotOpenOverAChatThatCannotBeFiled() async throws {
        // Opened anyway, the chat on screen would be in no filing and under
        // the opened chat's save.
        let threadURL = temporaryLocation("askkit-open-unfiled").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-unfiled")
        defer {
            makeWritable(archiveDirectory)
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, archiveDirectory)

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Anything from 1969?"])
        #expect(await entriesOnDisk(threadURL) == ["Anything from 1969?"])
        #expect(await archive.summaries().map(\.title) == ["Which records do I own?"])
    }

    @Test func aTurnStoppedByAnOpenThatCouldNotFileTheChatIsSaved() async throws {
        // The open stops the turn in flight and then finds the chat on screen
        // can't be filed, so the chat stays; its stopped turn is saved as
        // Stop saves one, not left for the next write.
        let threadURL = temporaryLocation("askkit-open-stopped").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-stopped")
        defer {
            makeWritable(archiveDirectory)
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .answer(.of("Answer."))]),
            .init(events: [.tier(.privateCloud), .partial("The oldest is")], hangs: true)
        ])
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        store.ask("Which is the oldest?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        try setMode(0o500, archiveDirectory)

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Anything from 1969?", "Which is the oldest?"])
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load()
        guard case .thread(let entries, _) = onDisk else {
            Issue.record("the thread reads back")
            return
        }
        #expect(entries.map(\.question) == ["Anything from 1969?", "Which is the oldest?"])
        #expect(entries.last?.stopped == true)
        #expect(entries.last?.answer?.text == "The oldest is")
    }

    @Test func anEarlierChatThatCannotBeWrittenAsTheThreadKeepsItsFiling() async throws {
        // Its filing is then its only copy on disk: kept, and left off the
        // list while it is on screen. Once the thread can be written, it is.
        let folder = try privateFolder()
        let archiveDirectory = temporaryLocation("askkit-open-unsaved")
        defer {
            makeWritable(folder.folder)
            try? FileManager.default.removeItem(at: folder.folder)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, folder.folder)

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        #expect(Set(await archive.summaries().map(\.title)) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.history.map(\.title) == ["Anything from 1969?"])

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which records do I own?"])
    }

    @Test func anEarlierChatWithTurnsThatDidNotDecodeOpensAndKeepsItsFiling() async throws {
        // The filing is the only copy of the turns this build can't read, so
        // opening the chat never removes it.
        let threadURL = temporaryLocation("askkit-open-dropped").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-dropped")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        let file = archiveDirectory.appending(path: "\(earlier.id.uuidString).json")
        let good = try JSONEncoder().encode(earlierEntry("Which records do I own?"))
        let partial = Data("[".utf8) + good + Data(", {\"text\": \"a turn a newer build wrote\"}]".utf8)
        try partial.write(to: file)
        await store.restoreIfNeeded()

        await store.openThread(earlier)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        #expect(try Data(contentsOf: file) == partial)
        #expect(store.history.isEmpty, "the chat on screen is left off the list")
    }

    @Test func aThreadReadInPartOpensWithWhatDecodes() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let good = try JSONEncoder().encode(earlierEntry("On screen last time"))
        let partial = Data("[".utf8) + good + Data(", {\"text\": \"a turn a newer build wrote\"}]".utf8)
        try partial.write(to: folder.thread)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)

        await store.restoreIfNeeded()
        #expect(store.turns.map(\.question) == ["On screen last time"])
        #expect(!store.readFailed)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["On screen last time", "Anything from 1969?"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.folder.path(percentEncoded: false))
        let originals = names.filter { $0.hasPrefix("ask-thread-original-") }
        #expect(try originals.map { try Data(contentsOf: folder.folder.appending(path: $0)) } == [partial])
    }

    @Test func aThreadNoneOfWhoseTurnsDecodeIsSetAsideAndTheNextAnswerIsKept() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let unread = Data("[{\"text\": \"one\"}, {\"text\": \"two\"}]".utf8)
        try unread.write(to: folder.thread)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)

        await store.restoreIfNeeded()
        #expect(store.turns.isEmpty)
        #expect(store.readFailed)
        #expect(store.showsUnreadableThreadNotice)
        #expect(try setAsideFiles(in: folder.folder).map { try Data(contentsOf: $0) } == [unread])
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Anything from 1969?"])
    }

    @Test func aThreadTooLockedToReadComesBackAboveWhatWasAskedMeanwhile() async throws {
        // A host's intent sends before the screen shows, on a locked device:
        // the read fails, the question is answered, and nothing is saved over
        // the thread. Once it reads, its turns go above the new ones and both
        // are saved.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        try setMode(0o000, folder.thread)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)

        store.prefill("Anything from 1969?", send: true)
        await store.restoreIfNeeded()
        await settle(store)
        await store.flushPersistence()
        #expect(store.readFailed)
        #expect(store.turns.map(\.question) == ["Anything from 1969?"])

        try setMode(0o644, folder.thread)
        store.protectedDataBecameAvailable()
        await eventually { store.turns.count == 2 }
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["On screen last time", "Anything from 1969?"])
        #expect(!store.readFailed)
        #expect(await entriesOnDisk(folder.thread) == ["On screen last time", "Anything from 1969?"])
    }

    @Test func aThreadTooLockedToReadIsReadAgainAsTheScreenComesBack() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        try setMode(0o000, folder.thread)
        let asker = answeringAsker()
        let (store, _) = keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        await store.refresh()
        #expect(store.showsUnreadableThreadNotice)

        try setMode(0o644, folder.thread)
        await store.refresh()
        #expect(store.turns.map(\.question) == ["On screen last time"])
        #expect(!store.showsUnreadableThreadNotice)
        // Nothing asked meanwhile, so the engine is handed its tail as a
        // launch hands it.
        #expect(asker.resumedTails.withLock { $0 }.last?.map(\.question) == ["On screen last time"])
    }

    @Test func aSaveTheDiskRefusedIsMadeOnceItCan() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        try setMode(0o500, folder.folder)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread).isEmpty)

        try setMode(0o755, folder.folder)
        store.protectedDataBecameAvailable()
        await eventually { FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)) }
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Anything from 1969?"])
    }

    @Test func whatDeletingEveryChatCouldNotDeleteIsDeletedOnceItCan() async throws {
        // Left beside the thread, a set-aside file would be filed back with
        // the earlier chats on the next launch: deleted data coming back.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let aside = folder.folder.appending(path: "ask-thread-unreadable-\(UUID().uuidString).json")
        try Data("[{\"text\": \"a turn a newer build wrote\"}]".utf8).write(to: aside)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, folder.folder)

        store.deleteAllThreads()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder.folder).count == 1)

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder.folder).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)))
    }

    @Test func whatDeletingEveryChatOwesSparesAChatNewChatSetAsideSince() async throws {
        // The retry deletes what Delete All Chats couldn't, and nothing set
        // aside after it: a chat New Chat couldn't file waits beside the
        // thread for the next launch to file, and it is the reader's.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let deleted = folder.folder.appending(path: "ask-thread-unreadable-\(UUID().uuidString).json")
        try Data("[{\"text\": \"a turn a newer build wrote\"}]".utf8).write(to: deleted)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        try setMode(0o500, folder.folder)
        store.deleteAllThreads()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder.folder) == [deleted], "the folder refused the delete")

        // The folder takes writes again, and the archive doesn't: New Chat
        // writes the chat as the thread and sets it aside.
        try setMode(0o755, folder.folder)
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        try setMode(0o500, folder.archive)
        store.ask("Anything from 1969?")
        await settle(store)
        store.startOver()
        await store.flushPersistence()
        let kept = setAsideFiles(in: folder.folder).filter { $0 != deleted }
        #expect(kept.count == 1, "New Chat set the chat aside")

        await store.refresh()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder.folder) == kept, "the retry deleted the chat New Chat set aside")

        try setMode(0o755, folder.archive)
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.history.map(\.title) == ["Anything from 1969?"])
    }

    @Test func aThreadDeletingEveryChatCouldNotDeleteIsDeletedThoughNewChatComesFirst() async throws {
        // The reader said delete. A New Chat before the disk takes writes
        // again neither forgets that nor keeps the thread: it is deleted as
        // soon as it can be, and the next launch finds nothing.
        let folder = try privateFolder()
        let archiveDirectory = temporaryLocation("askkit-owed-archive")
        defer {
            makeWritable(folder.folder)
            try? FileManager.default.removeItem(at: folder.folder)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: archiveDirectory)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, folder.folder)

        store.deleteAllThreads()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which records do I own?"], "the folder refused the delete")
        store.startOver()
        await store.flushPersistence()

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)), "the deleted chat was kept")
        #expect(setAsideFiles(in: folder.folder).isEmpty, "the deleted chat was set aside, to be filed again")
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: archiveDirectory)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.turns.isEmpty)
        #expect(relaunched.history.isEmpty)
    }

    @Test func aThreadTooLockedToReadThatDeletingEveryChatCouldNotDeleteIsNeverReadBack() async throws {
        // New Chat can't move it, so holds it again; held until it could be
        // read, it would come back on screen once it could: the chat the
        // reader deleted.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        try setMode(0o000, folder.thread)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        #expect(store.showsUnreadableThreadNotice)
        try setMode(0o500, folder.folder)

        store.startOver()
        store.deleteAllThreads()
        await store.flushPersistence()
        try setMode(0o644, folder.thread)
        await store.refresh()
        await store.flushPersistence()
        #expect(store.turns.isEmpty, "the deleted chat was read back")

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)), "the deleted chat was kept")
        #expect(setAsideFiles(in: folder.folder).isEmpty)
    }

    @Test func aChatDeletingEveryChatCouldNotDeleteIsNeverSetAsideWhenNewChatCannotFile() async throws {
        // With the archive refusing too, New Chat would hold the thread's
        // place for a later write to set aside. The place still holds what
        // the reader deleted, which is deleted once it can be; the chat
        // asked since waits to be filed instead.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        await store.flushPersistence()
        try setMode(0o500, folder.archive)
        try setMode(0o500, folder.folder)

        store.deleteAllThreads()
        await store.flushPersistence()
        store.ask("Anything from 1969?")
        await settle(store)
        store.startOver()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which records do I own?"], "the folder refused every write")

        try setMode(0o755, folder.folder)
        try setMode(0o755, folder.archive)
        await store.refresh()
        await store.flushPersistence()
        #expect(setAsideFiles(in: folder.folder).isEmpty, "the deleted chat was set aside, to be filed again")
        #expect(await entriesOnDisk(folder.thread).isEmpty, "the deleted chat was kept")
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.turns.isEmpty)
        #expect(relaunched.history.map(\.title) == ["Anything from 1969?"])
    }

    @Test func newChatKeepsAChatWhoseEverySaveTheDiskRefused() async throws {
        // The folder refused the chat's first save, so the thread's place is
        // empty: held as the chat's last copy, it would hold nothing, and the
        // chat would be gone with the turns New Chat took off the screen.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        try setMode(0o500, folder.folder)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        store.startOver()
        await store.flushPersistence()
        #expect(await archive.summaries().isEmpty, "the folder refused the filing")

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(await archive.summaries().map(\.title) == ["Anything from 1969?"])
    }

    @Test func newChatKeepsAChatItCanFileNowhereWhileTheThreadItCouldNotReadHoldsThePlace() async throws {
        // The thread that couldn't be read won't move, so it keeps the place,
        // and the chat asked meanwhile can't be written there: it waits to be
        // filed rather than going with the screen's turns.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        let written = try Data(contentsOf: folder.thread)
        try setMode(0o000, folder.thread)
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        #expect(store.readFailed)
        try setMode(0o500, folder.folder)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        store.startOver()
        await store.flushPersistence()
        #expect(await archive.summaries().isEmpty, "the folder refused the filing")

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        try setMode(0o644, folder.thread)
        #expect(try Data(contentsOf: folder.thread) == written, "the thread that couldn't be read went")
    }

    /// A chat filed by New Chat that the folder wouldn't let go of as the
    /// thread: the archive's folder takes writes, and the thread's folder
    /// refuses the delete.
    private func newChatThatFilesAndCannotClear(
        _ folder: (folder: URL, thread: URL, archive: URL)
    ) async throws -> (AskConversationStore<UIDomain>, AskThreadArchive<UIRow>) {
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        await store.flushPersistence()
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        try setMode(0o500, folder.folder)

        store.startOver()
        await store.flushPersistence()
        #expect(await archive.summaries().map(\.title) == ["Which records do I own?"])
        #expect(await entriesOnDisk(folder.thread) == ["Which records do I own?"], "the folder refused the delete")
        return (store, archive)
    }

    @Test func aChatNewChatFiledButCouldNotDeleteAsTheThreadIsDeletedOnceItCan() async throws {
        // Left as the thread, the chat would come back on screen at the next
        // launch beside its own filing.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, _) = try await newChatThatFilesAndCannotClear(folder)

        try setMode(0o755, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: folder.thread.path(percentEncoded: false)))
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.turns.isEmpty)
        #expect(relaunched.history.map(\.title) == ["Which records do I own?"])
    }

    /// A filing of the chat on screen, listed beside it: a write interrupted
    /// between filing a chat and taking it off the screen can leave one, and
    /// so can a read of the thread that couldn't read the filing then.
    private func listAFilingOfTheChatOnScreen(
        _ entries: [AskThreadEntry<UIRow>], in archive: AskThreadArchive<UIRow>, for store: AskConversationStore<UIDomain>
    ) async throws -> AskThreadSummary {
        let filed = try #require(await archive.archive(entries))
        await store.loadHistory()
        #expect(store.history.map(\.id) == [filed.id])
        return filed
    }

    @Test func openingTheFilingOfTheChatOnScreenKeepsWhatWasAskedSince() async throws {
        // Opened from the list, the filing would be written over with the
        // chat on screen, the older filing shown and saved, and the filing
        // then removed: every turn asked since, gone.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        await store.flushPersistence()
        let filed = try await listAFilingOfTheChatOnScreen(store.turns.map(\.entry), in: archive, for: store)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        await store.openThread(filed)
        await store.flushPersistence()
        let whole = ["Which records do I own?", "Anything from 1969?"]
        #expect(store.turns.map(\.question) == whole)
        #expect(await entriesOnDisk(folder.thread) == whole)
        #expect(await archive.summaries().isEmpty)
        #expect(store.history.isEmpty)
    }

    @Test func openingTheFilingOfTheChatOnScreenTakesInWhatOnlyTheFilingHolds() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let asker = answeringAsker()
        let (store, archive) = keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        let first = earlierEntry("Which records do I own?")
        let onlyFiled = earlierEntry("Which are on vinyl?", at: 1_000_030)
        let onlyOnScreen = earlierEntry("Anything from 1969?", at: 1_000_060)
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([first, onlyOnScreen])
        await store.restoreIfNeeded()
        let opened = try await listAFilingOfTheChatOnScreen([first, onlyFiled], in: archive, for: store)
        store.draft = "And the oldest?"

        await store.openThread(opened)
        await store.flushPersistence()
        let merged = ["Which records do I own?", "Which are on vinyl?", "Anything from 1969?"]
        #expect(store.turns.map(\.question) == merged)
        #expect(await entriesOnDisk(folder.thread) == merged)
        #expect(await archive.summaries().isEmpty)
        #expect(store.history.isEmpty)
        // The chat goes on: it isn't started over, and the draft stays.
        #expect(asker.resets.withLock { $0 } == 0)
        #expect(store.draft == "And the oldest?")
    }

    /// A New Chat over a turn still streaming, whose filing took and whose
    /// delete didn't, and an app quit before the delete was tried again: the
    /// thread holds the chat as last saved, without the turn New Chat
    /// stopped, and the filing holds both. `triedAgain`, the turn streaming
    /// is Try Again's, and the thread holds the failure it replaced.
    private func newChatOverATurnInFlightThatFilesAndCannotClear(
        _ folder: (folder: URL, thread: URL, archive: URL), triedAgain: Bool = false
    ) async throws -> AskThreadArchive<UIRow> {
        let asker = ScriptedAsker()
        let streaming = ScriptedAsker.Script(events: [.tier(.privateCloud), .partial("Two from 1969")], hangs: true)
        asker.scripts(triedAgain ? [answering(), failing(), streaming] : [answering(), streaming])
        let (store, archive) = keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        await store.flushPersistence()
        store.ask("Anything from 1969?")
        if triedAgain {
            await settle(store)
            await store.flushPersistence()
            store.retry(try #require(store.turns.last))
        }
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        try setMode(0o500, folder.folder)

        store.startOver()
        await store.flushPersistence()
        let saved = triedAgain ? ["Which records do I own?", "Anything from 1969?"] : ["Which records do I own?"]
        #expect(await entriesOnDisk(folder.thread) == saved, "the folder refused the delete")
        #expect(await archive.summaries().map(\.turnCount) == [2])
        try setMode(0o755, folder.folder)
        return archive
    }

    /// The questions of every chat filed.
    private func filedChats(in archive: AskThreadArchive<UIRow>) async -> [[String]] {
        var chats: [[String]] = []
        for summary in await archive.summaries() {
            guard case .thread(let entries, _) = await archive.entries(for: summary.id) else { continue }
            chats.append(entries.map(\.question))
        }
        return chats
    }

    @Test func aRelaunchJoinsTheThreadWithTheFilingANewChatLeftOfIt() async throws {
        // Shown as the thread alone, the chat would be filed over its filing
        // by the next New Chat or the next chat opened, with only what the
        // thread holds: the turn New Chat stopped would go.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let archive = try await newChatOverATurnInFlightThatFilesAndCannotClear(folder)

        let (relaunched, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        let whole = ["Which records do I own?", "Anything from 1969?"]
        #expect(relaunched.turns.map(\.question) == whole)
        #expect(relaunched.turns.last?.text == "Two from 1969")
        #expect(relaunched.history.isEmpty)
        await relaunched.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == whole)
        #expect(await archive.summaries().isEmpty)
    }

    @Test func newChatAfterARelaunchOverAThreadAndItsFilingFilesTheWholeChat() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let archive = try await newChatOverATurnInFlightThatFilesAndCannotClear(folder)
        let (relaunched, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()

        relaunched.startOver()
        await relaunched.flushPersistence()
        #expect(await filedChats(in: archive) == [["Which records do I own?", "Anything from 1969?"]])
    }

    @Test func openingAnotherChatAfterARelaunchOverAThreadAndItsFilingFilesTheWholeChat() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let archive = try await newChatOverATurnInFlightThatFilesAndCannotClear(folder)
        let other = try #require(await archive.archive([earlierEntry("Which are on vinyl?", at: 500_000)]))
        let (relaunched, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()

        await relaunched.openThread(try #require(relaunched.history.first { $0.id == other.id }))
        await relaunched.flushPersistence()
        #expect(relaunched.turns.map(\.question) == ["Which are on vinyl?"])
        #expect(await filedChats(in: archive) == [["Which records do I own?", "Anything from 1969?"]])
    }

    @Test func aRelaunchAfterAnInterruptedOpenJoinsTheThreadWithTheFilingItLeft() async throws {
        // An open interrupted after the chat it opened was written as the
        // thread, and before its filing came off the list, leaves the chat in
        // both places for the next launch: on screen and listed beside it.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        let chat = [earlierEntry("Which records do I own?"), earlierEntry("Which are on vinyl?", at: 1_000_030)]
        _ = try #require(await archive.archive(chat))
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save(chat)

        await store.restoreIfNeeded()
        let questions = ["Which records do I own?", "Which are on vinyl?"]
        #expect(store.turns.map(\.question) == questions)
        #expect(store.history.isEmpty)
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == questions)
        #expect(await archive.summaries().isEmpty)
    }

    @Test func aRelaunchLeavesAFailedTurnTryAgainReplacedOutOfTheChat() async throws {
        // The thread was saved with the turn that failed, and Try Again's turn
        // is in the filing alone. Joined turn by turn, the failure would come
        // back as the newest turn, with Try Again on it again.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let archive = try await newChatOverATurnInFlightThatFilesAndCannotClear(folder, triedAgain: true)

        let (relaunched, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        let whole = ["Which records do I own?", "Anything from 1969?"]
        #expect(relaunched.turns.map(\.question) == whole)
        #expect(relaunched.turns.last?.failure == nil)
        #expect(relaunched.turns.last?.text == "Two from 1969")
        await relaunched.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == whole)
        #expect(await archive.summaries().isEmpty)
    }

    @Test func aRelaunchOverAThreadNewerThanItsFilingLeavesAFailedTurnTryAgainReplacedOutOfTheChat() async throws {
        // The other way about: a filing left behind a thread written since,
        // whose removal failed or some of whose turns didn't decode, holds the
        // failure Try Again replaced. Joined turn by turn, it would sit above
        // the turn asked again.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        let first = earlierEntry("Which records do I own?")
        let failed = AskThreadEntry<UIRow>(
            question: "Anything from 1969?", text: "", answer: nil, failureMessage: "Couldn't answer that.",
            failure: .couldNotAnswer, failureIsRetryable: true, tier: .privateCloud,
            askedAt: Date(timeIntervalSince1970: 1_000_060)
        )
        let askedAgain = earlierEntry("Anything from 1969?", at: 1_000_120)
        _ = try #require(await archive.archive([first, failed]))
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([first, askedAgain])

        await store.restoreIfNeeded()
        #expect(store.turns.map(\.question) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.turns.allSatisfy { $0.failure == nil })
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Which records do I own?", "Anything from 1969?"])
        #expect(await archive.summaries().isEmpty)
    }

    @Test func aTurnANewerQuestionOvertakesIsSavedWithWhatItHadSaid() async throws {
        // Stop saves the turn it stops; a newer question stops it too. Saved
        // only once the newer turn ends, it would be lost to an app killed
        // while that one streams.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .partial("Two from 1969")], hangs: true),
            .init(events: [.tier(.privateCloud), .partial("The oldest is")], hangs: true)
        ])
        let (store, _) = keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await yieldUntil { store.turns.last?.text.isEmpty == false }

        store.ask("Which is the oldest?")
        await store.flushPersistence()
        let saved = await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).load().entries
        #expect(saved.map(\.question) == ["Anything from 1969?"])
        #expect(saved.first?.answer?.text == "Two from 1969")
        #expect(saved.first?.answer?.isTruncated == true)
        store.stop(byReader: true)
        await store.flushPersistence()
    }

    @Test func turnsAskedWhileTheThreadCannotBeReadAreKeptAsAChatOfTheirOwn() async throws {
        // Nothing may be written over the thread that couldn't be read, so
        // the turns asked meanwhile go to the earlier chats, left off the list
        // while they are on screen. An app quit before New Chat keeps them.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        let written = try Data(contentsOf: folder.thread)
        try setMode(0o000, folder.thread)
        let (store, _) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        #expect(store.readFailed)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(store.history.isEmpty, "the chat on screen is listed beside itself")

        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.history.map(\.title) == ["Anything from 1969?"])
        try setMode(0o644, folder.thread)
        #expect(try Data(contentsOf: folder.thread) == written, "the thread that couldn't be read was written over")
    }

    @Test func turnsKeptBesideAThreadThatCouldNotBeReadLeaveTheListOnceItReads() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        try setMode(0o000, folder.thread)
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        try setMode(0o644, folder.thread)
        await store.refresh()
        await store.flushPersistence()
        let whole = ["On screen last time", "Anything from 1969?"]
        #expect(store.turns.map(\.question) == whole)
        #expect(await entriesOnDisk(folder.thread) == whole)
        #expect(await archive.summaries().isEmpty, "the turns asked meanwhile are in two places")
    }

    @Test func turnsKeptBesideAThreadThatCouldNotBeReadAreFiledOnceByNewChat() async throws {
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([earlierEntry("On screen last time")])
        try setMode(0o000, folder.thread)
        let (store, archive) = keepingStore(asker: answeringAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        store.ask("Which is the oldest?")
        await settle(store)
        await store.flushPersistence()

        store.startOver()
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(await archive.summaries().map(\.turnCount) == [2])
    }

    @Test func aRetriedRemovalOfAChatsAttachmentsSparesTheNextChats() async throws {
        // New Chat couldn't remove the chat's attachment. The retry removes
        // that one, and never the one a verdict in the next chat kept since.
        let folder = try privateFolder()
        let attachments = temporaryLocation("askkit-owed-feedback")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer {
            makeWritable(attachments)
            try? FileManager.default.removeItem(at: attachments)
            try? FileManager.default.removeItem(at: folder.folder)
        }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(
            domain: domain, asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive,
            attachmentsDirectory: attachments
        )
        let kept = AskFeedbackAttachments(appDirectory: "unused", directory: attachments)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        store.rate(try #require(store.turns.last), .positive)
        await store.flushFeedback()
        let first = await kept.urls().map(\.lastPathComponent)
        #expect(first.count == 1)
        try setMode(0o500, attachments)
        store.startOver()
        await store.flushFeedback()
        #expect(await kept.urls().map(\.lastPathComponent) == first, "the folder refused the removal")

        try setMode(0o755, attachments)
        store.ask("Anything from 1969?")
        await settle(store)
        store.rate(try #require(store.turns.last), .negative)
        await store.flushFeedback()
        let next = await kept.urls().map(\.lastPathComponent).filter { !first.contains($0) }
        #expect(next.count == 1)

        await store.refresh()
        await store.flushPersistence()
        #expect(await kept.urls().map(\.lastPathComponent) == next)
    }

    @Test func attachmentsOwedStayOwedWhenTheFolderCannotBeListed() async throws {
        // A New Chat that can't list the folder finds no attachment to
        // remove. What an earlier chat left owed is still owed, and goes once
        // the folder lets it.
        let folder = try privateFolder()
        let attachments = temporaryLocation("askkit-unlisted-feedback")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer {
            makeWritable(attachments)
            try? FileManager.default.removeItem(at: attachments)
            try? FileManager.default.removeItem(at: folder.folder)
        }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Rumours.", tiles: [UIRow("Rumours")]))]))
        let store = makeStore(
            domain: domain, asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive,
            attachmentsDirectory: attachments
        )
        let kept = AskFeedbackAttachments(appDirectory: "unused", directory: attachments)
        await store.restoreIfNeeded()
        store.ask("Which records do I own?")
        await settle(store)
        store.rate(try #require(store.turns.last), .positive)
        await store.flushFeedback()
        #expect(await kept.urls().count == 1)
        try setMode(0o500, attachments)
        store.startOver()
        await store.flushFeedback()
        // Writable and searchable, but not listable.
        try setMode(0o300, attachments)
        store.startOver()
        await store.flushFeedback()

        try setMode(0o755, attachments)
        await store.refresh()
        await store.flushPersistence()
        #expect(await kept.urls().isEmpty, "a transcript outlived its chat")
    }

    /// A full list of earlier chats, oldest first, an hour apart.
    private func fillHistory(_ archive: AskThreadArchive<UIRow>) async throws -> [AskThreadSummary] {
        var filed: [AskThreadSummary] = []
        for index in 0..<AskThreadArchive<UIRow>.maxThreads {
            filed.append(try #require(await archive.archive([earlierEntry("q\(index)", at: 1_000_000 + Double(index) * 3_600)])))
        }
        return filed
    }

    /// A thread saved last time that won't read on this launch, over a
    /// private folder, and a store over it with the thread held.
    private func storeOverAThreadThatWontRead(
        _ folder: (folder: URL, thread: URL, archive: URL), asker: ScriptedAsker, saved: [AskThreadEntry<UIRow>]? = nil
    ) async throws -> (AskConversationStore<UIDomain>, AskThreadArchive<UIRow>) {
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread)
            .save(saved ?? [earlierEntry("On screen last time", at: 9_000_000)])
        try setMode(0o000, folder.thread)
        return keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
    }

    private func failing() -> ScriptedAsker.Script {
        .init(events: [.tier(.privateCloud)], error: AskError.couldNotAnswer)
    }

    private func answering() -> ScriptedAsker.Script {
        .init(events: [.tier(.privateCloud), .answer(.of("Answer."))])
    }

    @Test func turnsKeptBesideAThreadThatCouldNotBeReadTakeNoChatsPlaceInAFullList() async throws {
        // Filed as a chat of their own, they would push the oldest chat out of
        // a full list, and leave it once the thread reads: a chat fewer, and
        // the oldest gone for good.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: answeringAsker())
        let filed = try await fillHistory(archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(store.history.count == AskThreadArchive<UIRow>.maxThreads)

        try setMode(0o644, folder.thread)
        await store.refresh()
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["On screen last time", "Anything from 1969?"])
        #expect(Set(await archive.summaries().map(\.id)) == Set(filed.map(\.id)))
    }

    @Test func aFirstTurnAskedAgainBesideAThreadThatCouldNotBeReadTakesNoChatsPlaceEither() async throws {
        // Asked again, the first turn is a turn asked at another moment, and
        // a chat anew to the archive: filed afresh each time, each filing
        // would take another chat's place.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let asker = ScriptedAsker()
        asker.scripts([failing(), failing(), answering()])
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: asker)
        let filed = try await fillHistory(archive)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        for _ in 0..<2 {
            store.retry(try #require(store.turns.last))
            await settle(store)
        }
        await store.flushPersistence()
        #expect(store.turns.last?.answer?.text == "Answer.")
        #expect(await archive.summaries().count == AskThreadArchive<UIRow>.maxThreads + 1, "a stale copy is filed")

        try setMode(0o644, folder.thread)
        await store.refresh()
        await store.flushPersistence()
        #expect(Set(await archive.summaries().map(\.id)) == Set(filed.map(\.id)))
    }

    @Test func aNewChatWhileATurnAskedAgainIsFiledKeepsTheChatItEndsOnceAndForGood() async throws {
        // New Chat lands while the turn asked again is being filed beside the
        // thread that couldn't be read. The chat it ends is listed once, and
        // the next chat's first save doesn't take it away.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let asker = ScriptedAsker()
        asker.scripts([failing(), answering(), answering()])
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: asker)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        store.retry(try #require(store.turns.last))
        // The turn's end queues its filing; one hop more and the filing is
        // waiting on the archive.
        await yieldUntil { !store.isThinking }
        await Task.yield()
        store.startOver()
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(await archive.summaries().count == 1)

        store.ask("Which is the oldest?")
        await settle(store)
        await store.flushPersistence()
        #expect(store.history.map(\.title) == ["Anything from 1969?"])
        #expect(await archive.summaries().count == 1)
    }

    @Test func aNewChatWhileAFirstTurnIsAskedAgainLeavesNoStaleCopyListed() async throws {
        // The failed first turn was filed beside the thread that couldn't be
        // read. Asked again and still answering, it is a chat anew, and New
        // Chat files that; the failed one's filing goes rather than stay
        // listed as a chat of its own.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let asker = ScriptedAsker()
        asker.scripts([failing(), .init(events: [.tier(.privateCloud), .partial("Two from 1969")], hangs: true)])
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: asker)
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        store.retry(try #require(store.turns.last))
        await yieldUntil { store.turns.last?.text.isEmpty == false }
        store.startOver()
        await store.flushPersistence()
        let listed = await archive.summaries()
        #expect(listed.count == 1)
        let only = try #require(listed.first)
        guard case .thread(let entries, _) = await archive.entries(for: only.id) else {
            Issue.record("the chat New Chat ended isn't filed")
            return
        }
        #expect(entries.map(\.answer?.text) == ["Two from 1969"])
    }

    @Test func aNewChatAfterAThreadReadsAgainFilesItOverItsOwnFiling() async throws {
        // The thread that couldn't be read was a chat already filed, and reads
        // now with the turns asked meanwhile under it. New Chat files it over
        // its own filing, not over the turns' filing beside it, so it isn't
        // listed twice.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let onScreen = earlierEntry("On screen last time", at: 9_000_000)
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: answeringAsker(), saved: [onScreen])
        let own = try #require(await archive.archive([onScreen]))
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()

        try setMode(0o644, folder.thread)
        // The retry alone, and New Chat in the same tick, so New Chat lands
        // before the join is written as the thread and its filing taken off
        // the list: `refresh()` reads the overview and the model's state
        // beside the retry, and the write can land while they finish.
        await store.retryWhatWaitsOnTheDisk()
        store.startOver()
        await store.flushPersistence()
        let listed = await archive.summaries()
        #expect(listed.map(\.id) == [own.id])
        #expect(listed.map(\.turnCount) == [2])
    }

    @Test func aRelaunchKeepsWhatOnlyTheFilingANewChatLeftSettled() async throws {
        // The reader confirmed the card's offer and rated the answer, and the
        // disk refused the saves of what came of the offer and of the rating.
        // New Chat filed the chat with them and couldn't delete the thread,
        // and the app quit. The thread's copy of the turn has only the yes:
        // shown as it is, the card would say nobody knows what came of it.
        let folder = try privateFolder()
        defer { makeWritable(folder.archive, folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let offering = ScriptedAsker(.init(events: [
            .tier(.privateCloud),
            .answer(AskAnswer(text: "The Peregrine is on your shelf.", proposal: Self.lendBook))
        ]))
        let store = makeStore(domain: domain, asker: offering, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        store.ask("Can I lend The Peregrine to Sam?")
        await settle(store)
        await store.flushPersistence()
        try FileManager.default.createDirectory(at: folder.archive, withIntermediateDirectories: true)
        // The yes is saved first, or nothing is carried out.
        domain.performed.parks.withLock { $0 = true }
        let turn = try #require(store.turns.last)
        store.confirmProposal(turn)
        await domain.performed.isParked()
        try setMode(0o500, folder.folder)
        domain.performed.release()
        await store.flushProposal()
        store.rate(turn, .positive)
        await store.flushFeedback()
        await store.flushPersistence()
        store.startOver()
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread) == ["Can I lend The Peregrine to Sam?"], "the folder refused the delete")
        try setMode(0o755, folder.folder)

        let relaunched = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        let joined = try #require(relaunched.turns.last)
        #expect(joined.proposalOutcome == .confirmed("Marked The Peregrine as lent."))
        #expect(joined.feedback == .positive)
        #expect(relaunched.proposalPhase(for: joined) == .done("Marked The Peregrine as lent."))
        await relaunched.flushPersistence()
        let saved = await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).load().entries
        #expect(saved.map(\.proposalOutcome) == [.confirmed("Marked The Peregrine as lent.")])
        #expect(saved.map(\.feedback) == [.positive])
    }

    @Test func openingTheFilingOfTheChatOnScreenKeepsWhatOnlyTheFilingSettled() async throws {
        // The screen's copy of the turn has neither the outcome nor the
        // verdict: kept as the screen's, the card would offer the action again.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let store = makeStore(domain: domain, asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        let archive = AskThreadArchive<UIRow>(appDirectory: "unused", directory: folder.archive)
        let offered = AskThreadEntry<UIRow>(
            question: "Can I lend The Peregrine to Sam?", text: "The Peregrine is on your shelf.",
            answer: AskAnswer(text: "The Peregrine is on your shelf.", proposal: Self.lendBook),
            tier: .privateCloud, askedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let settled = AskThreadEntry<UIRow>(
            question: offered.question, text: offered.text, answer: offered.answer, tier: offered.tier,
            askedAt: offered.askedAt, feedback: .positive, proposalOutcome: .confirmed("Marked The Peregrine as lent.")
        )
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).save([offered])
        await store.restoreIfNeeded()
        let shown = try #require(store.turns.last)
        #expect(store.proposalPhase(for: shown) == .awaiting)
        let filed = try await listAFilingOfTheChatOnScreen([settled], in: archive, for: store)

        await store.openThread(filed)
        await store.flushPersistence()
        let rejoined = try #require(store.turns.last)
        #expect(rejoined.proposalOutcome == .confirmed("Marked The Peregrine as lent."))
        #expect(rejoined.feedback == .positive)
        #expect(store.proposalPhase(for: rejoined) == .done("Marked The Peregrine as lent."))
        let saved = await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).load().entries
        #expect(saved.map(\.proposalOutcome) == [.confirmed("Marked The Peregrine as lent.")])
        #expect(saved.map(\.feedback) == [.positive])
    }

    @Test func aStoreWithNoFolderOwesNoChatItHasNowhereToKeep() async {
        // Built from a folder name that isn't one folder, it keeps nothing,
        // so every chat New Chat ended would wait in memory to be filed, for
        // the life of the process.
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let store = AskConversationStore(
            domain: domain, engine: answeringAsker(),
            thread: AskThreadStore<UIRow>(appDirectory: ""),
            archive: AskThreadArchive<UIRow>(appDirectory: ""),
            feedbackAttachments: AskFeedbackAttachments(appDirectory: ""),
            clock: { 0 }
        )
        await store.restoreIfNeeded()
        for question in ["Anything from 1969?", "Which is the oldest?"] {
            store.ask(question)
            await settle(store)
            store.startOver()
            await store.flushPersistence()
        }
        #expect(store.filingsOwed.isEmpty)
    }

    @Test func aQuestionAskedWhileAnEarlierChatIsAskedForIsAskedOnIt() async throws {
        // Asked after the tap on the earlier chat and before that chat is
        // read, the question waits for the change, as one asked during any
        // chat change does, and is asked on the chat that opens. Settled with
        // the chat on screen, it would vanish from the composer and the thread.
        let threadURL = temporaryLocation("askkit-open-asked").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-asked")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = answeringAsker()
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()
        // A New Chat still resetting the engine holds the open back, before it
        // reads the chat it opens.
        asker.parksReset.withLock { $0 = true }
        store.startOver()
        await asker.resetIsParked()
        let opening = Task { await store.openThread(earlier) }
        for _ in 0..<5 { await Task.yield() }
        store.draft = "Anything from 1969?"
        store.ask(store.draft)
        #expect(store.isThinking)
        asker.parksReset.withLock { $0 = false }
        asker.releaseReset()
        await opening.value
        await settle(store)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.turns.last?.answer?.text == "Answer.")
    }

    @Test func aQuestionAskedAsANewChatResetsIsAskedOnAnEarlierChatOpenedThen() async throws {
        // Asked while New Chat's reset holds questions back, and then the
        // reader opens an earlier chat: the question is no turn yet, of the
        // new chat or any, and settled as the chat changes it would vanish
        // from the composer and the thread.
        let threadURL = temporaryLocation("askkit-open-after-asked").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-after-asked")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = answeringAsker()
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()
        asker.parksReset.withLock { $0 = true }
        store.startOver()
        await asker.resetIsParked()
        store.ask("Anything from 1969?")
        #expect(store.isThinking)
        let opening = Task { await store.openThread(earlier) }
        for _ in 0..<5 { await Task.yield() }
        asker.parksReset.withLock { $0 = false }
        asker.releaseReset()
        await opening.value
        await settle(store)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which records do I own?", "Anything from 1969?"])
        #expect(store.turns.last?.answer?.text == "Answer.")
    }

    @Test func aChatOpenedWithNothingOnScreenToFileLeavesTheTurnsKeptBesideTheThreadListed() async throws {
        // The thread that couldn't be read went meanwhile, its place now
        // refusing writes, and the turn asked beside it failed. Asked again as
        // the reader opens an earlier chat, it waits for that chat, so there
        // is nothing on screen for the open to file. The turn's filing is an
        // ordinary one from then on, and listed: still marked as kept beside
        // the thread, the next New Chat would delete it.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        let asker = ScriptedAsker()
        asker.scripts([failing(), answering()])
        let (store, archive) = try await storeOverAThreadThatWontRead(folder, asker: asker)
        let earlier = try #require(await archive.archive([earlierEntry("Which are on vinyl?")]))
        await store.restoreIfNeeded()
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        try FileManager.default.removeItem(at: folder.thread)
        try setMode(0o500, folder.folder)
        await store.refresh()
        await store.flushPersistence()
        let failed = try #require(store.turns.last)
        #expect(failed.failure != nil)

        let opening = Task { await store.openThread(earlier) }
        await Task.yield()
        store.retry(failed)
        await opening.value
        await settle(store)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == ["Which are on vinyl?", "Anything from 1969?"])
        #expect(store.history.map(\.title) == ["Anything from 1969?"])

        store.startOver()
        await store.flushPersistence()
        #expect(Set(await filedChats(in: archive)) == [["Which are on vinyl?", "Anything from 1969?"], ["Anything from 1969?"]])
    }

    // MARK: - Asking as the chat changes
    //
    // On an engine whose `stop()` and `reset()` cancel the turn in flight, as
    // `AskEngine`'s do. A question asked the moment a chat ends has to reach
    // the engine after its reset, or the reset cancels it ("Answer cut short",
    // Try Again).

    /// A store that keeps its chats over a saved thread of one answered
    /// question, on an engine that cancels what is in flight when stopped or
    /// reset. Nothing read yet.
    private func cancellingStoreOverASavedThread(
        _ folder: (folder: URL, thread: URL, archive: URL)
    ) async -> (AskConversationStore<UIDomain>, AskThreadArchive<UIRow>, ScriptedAsker) {
        // At a moment of its own: chats that share a turn's moment are one
        // chat to the archive (`AskThreadSummary.isSameChat`).
        await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread)
            .save([earlierEntry("On screen last time", at: 2_000_000)])
        // Streamed over many snapshots, so the turn is still running when a
        // stop or a reset sent before it reaches the engine, as a model's is.
        let words = (1...40).map { AskTurnEvent<UIRow>.partial(String(repeating: "word ", count: $0)) }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud)] + words + [.answer(.of("Answer."))]))
        asker.cancelsTheTurnInFlight.withLock { $0 = true }
        let (store, archive) = keepingStore(asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        return (store, archive, asker)
    }

    /// The question asked after the chat changed, answered whole, alone on the
    /// thread and on disk.
    private func expectAnsweredAlone(
        _ question: String, in store: AskConversationStore<UIDomain>, threadURL: URL
    ) async {
        await settle(store)
        await store.flushPersistence()
        #expect(store.turns.map(\.question) == [question])
        #expect(store.turns.last?.answer?.text == "Answer.", "the question was cut short")
        #expect(store.turns.last?.failure == nil)
        #expect(!store.isThinking)
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load().entries
        #expect(onDisk.map(\.question) == [question])
    }

    @Test func aQuestionAskedRightAfterNewChatIsAnsweredOnTheNewChat() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, _) = await cancellingStoreOverASavedThread(folder)
        await store.restoreIfNeeded()

        store.startOver()
        store.ask("Anything from 1969?")

        await expectAnsweredAlone("Anything from 1969?", in: store, threadURL: folder.thread)
        #expect(await archive.summaries().map(\.title) == ["On screen last time"])
    }

    @Test func aQuestionStoppedWhileANewChatOpensComesBackWithItsScopeAndPhoto() async throws {
        // Waiting for the engine's reset, it has no turn on either chat.
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        asker.parksReset.withLock { $0 = true }
        store.startOver()
        await asker.resetIsParked()

        store.prefill("Which are on vinyl?", scope: "records")
        store.attachPhoto(onePixel(), label: "A shelf")
        store.ask(store.draft)
        #expect(store.isThinking)
        store.stop(byReader: true)
        #expect(!store.isThinking)
        #expect(store.draft == "Which are on vinyl?")
        #expect(store.pendingPhoto?.photo.label == "A shelf")

        asker.parksReset.withLock { $0 = false }
        asker.releaseReset()
        store.ask(store.draft)
        await eventually { asker.questions.withLock { $0 }.count == 2 }
        await settle(store)
        #expect(store.turns.map(\.question) == ["Which are on vinyl?"])
        #expect(asker.scopes.withLock { $0 }.last == "records")
        #expect(asker.imageLabels.withLock { $0 }.last == ["A shelf"])
    }

    @Test func aQuestionAskedRightAfterNewChatBeforeTheThreadIsReadIsAnsweredOnTheNewChat() async throws {
        // Before the read, New Chat and the question must run in the order
        // they were asked: woken in either order by the read, the question
        // first would end with the chat, and New Chat first would reset the
        // engine under the question.
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, _) = await cancellingStoreOverASavedThread(folder)

        store.startOver()
        store.ask("Anything from 1969?")
        await store.restoreIfNeeded()

        await expectAnsweredAlone("Anything from 1969?", in: store, threadURL: folder.thread)
        #expect(await archive.summaries().map(\.title) == ["On screen last time"])
    }

    @Test func aQuestionSentRightAfterDeletingEveryChatIsAnswered() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, _) = await cancellingStoreOverASavedThread(folder)
        _ = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()

        store.deleteAllThreads()
        store.prefill("Anything from 1969?", send: true)

        await expectAnsweredAlone("Anything from 1969?", in: store, threadURL: folder.thread)
        #expect(await archive.summaries().isEmpty)
    }

    @Test func aQuestionSentRightAfterDeletingEveryChatBeforeTheThreadIsReadIsAnswered() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, _) = await cancellingStoreOverASavedThread(folder)
        _ = try #require(await archive.archive([earlierEntry("Which records do I own?")]))

        store.deleteAllThreads()
        store.prefill("Anything from 1969?", send: true)
        await store.restoreIfNeeded()

        await expectAnsweredAlone("Anything from 1969?", in: store, threadURL: folder.thread)
        #expect(await archive.summaries().isEmpty)
        #expect(store.history.isEmpty)
    }

    @Test func aQuestionAskedRightAfterAnEarlierChatOpensIsAnsweredOnIt() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, _) = await cancellingStoreOverASavedThread(folder)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()

        let opening = Task { await store.openThread(earlier) }
        await eventually { store.turns.map(\.question) == ["Which records do I own?"] }
        store.ask("Which is the oldest?")
        await opening.value
        await settle(store)
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["Which records do I own?", "Which is the oldest?"])
        #expect(store.turns.last?.answer?.text == "Answer.", "the question was cut short")
    }

    /// Opening a second chat while the first is still on its way in: the
    /// first is filed when the second takes its place, and the chat both
    /// replaced is filed once.
    @Test func aSecondChatOpenedWhileTheFirstOpensFilesTheFirst() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, asker) = await cancellingStoreOverASavedThread(folder)
        let first = try #require(await archive.archive([earlierEntry("First chat", at: 1_000_000)]))
        let second = try #require(await archive.archive([earlierEntry("Second chat", at: 1_100_000)]))
        await store.restoreIfNeeded()
        asker.parksReset.withLock { $0 = true }

        let openingFirst = Task { await store.openThread(first) }
        await asker.resetIsParked()
        asker.parksReset.withLock { $0 = false }
        let openingSecond = Task { await store.openThread(second) }
        for _ in 0..<20 { await Task.yield() }
        asker.releaseReset()
        await openingFirst.value
        await openingSecond.value
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["Second chat"])
        #expect(Set(store.history.map(\.title)) == ["First chat", "On screen last time"])
        #expect(store.history.count == 2)
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).load().entries
        #expect(onDisk.map(\.question) == ["Second chat"])
    }

    @Test func deletingEveryChatWhileOneOpensBringsNothingBack() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, asker) = await cancellingStoreOverASavedThread(folder)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()
        asker.parksReset.withLock { $0 = true }

        let opening = Task { await store.openThread(earlier) }
        await asker.resetIsParked()
        asker.parksReset.withLock { $0 = false }
        store.deleteAllThreads()
        asker.releaseReset()
        await opening.value
        await eventually { asker.resets.withLock { $0 } >= 2 }
        await store.flushPersistence()

        #expect(store.turns.isEmpty)
        #expect(store.history.isEmpty)
        #expect(await archive.summaries().isEmpty)
        guard case .empty = await AskThreadStore<UIRow>(appDirectory: "unused", url: folder.thread).load() else {
            Issue.record("a deleted chat came back as the thread")
            return
        }
        // And a relaunch finds nothing either.
        let (relaunched, _) = keepingStore(asker: ScriptedAsker(), threadURL: folder.thread, archiveDirectory: folder.archive)
        await relaunched.restoreIfNeeded()
        #expect(relaunched.turns.isEmpty)
        #expect(relaunched.history.isEmpty)
    }

    @Test func newChatWhileAnEarlierChatOpensFilesItAndEndsIt() async throws {
        let folder = try privateFolder()
        defer { try? FileManager.default.removeItem(at: folder.folder) }
        let (store, archive, asker) = await cancellingStoreOverASavedThread(folder)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        await store.restoreIfNeeded()
        asker.parksReset.withLock { $0 = true }

        let opening = Task { await store.openThread(earlier) }
        await asker.resetIsParked()
        asker.parksReset.withLock { $0 = false }
        store.startOver()
        store.ask("Anything from 1969?")
        asker.releaseReset()
        await opening.value

        await expectAnsweredAlone("Anything from 1969?", in: store, threadURL: folder.thread)
        #expect(Set(await archive.summaries().map(\.title)) == ["Which records do I own?", "On screen last time"])
    }

    // MARK: - Try Again, Edit & Resend, and an earlier chat opening

    @Test func tryAgainLeavesTheDraftAlone() async {
        // Try Again asks the failed turn's question, not the composer's. Sent
        // back through the composer's path, a typed turn, which is every turn
        // read back from disk, would take a half-typed question with it.
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer),
            .init(events: [.answer(.of("Worked this time."))])
        ])
        let store = makeStore(asker: asker)
        store.ask("q")
        await settle(store)
        store.draft = "half typed"

        store.retry(store.turns[0])
        await settle(store)

        #expect(store.turns.map(\.question) == ["q"])
        #expect(store.turns.last?.answer?.text == "Worked this time.")
        #expect(store.draft == "half typed")
    }

    @Test func tryAgainActsOnlyOnTheNewestTurn() async {
        // On an older failure it would pull that turn out of the middle of the
        // thread and stop whatever is streaming below it.
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.onDevice)], error: AskError.couldNotAnswer),
            .init(events: [.answer(.of("Second."))])
        ])
        let store = makeStore(asker: asker)
        store.ask("first")
        await settle(store)
        store.ask("second")
        await settle(store)

        store.retry(store.turns[0])
        await settle(store)

        #expect(store.turns.map(\.question) == ["first", "second"])
        #expect(store.turns[0].failure != nil)
        #expect(store.turns[1].answer?.text == "Second.")
        #expect(asker.questions.withLock { $0 }.count == 2)
    }

    @Test func editingATurnAskedWithNoPhotoTakesTheWaitingOneOut() async throws {
        // The draft is the edited question now, and it went with no photo. A
        // photo left waiting for another question would stay, and go with it.
        let asker = ScriptedAsker(.init(events: [.answer(.of("Answer."))]))
        let store = makeStore(asker: asker)
        store.ask("Which is the oldest?")
        await settle(store)
        store.attachPhoto(onePixel(), label: "Navy blazer")

        store.edit(try #require(store.turns.last))

        #expect(store.draft == "Which is the oldest?")
        #expect(store.pendingPhoto == nil)
    }

    @Test func openingAnEarlierChatLeavesTheKeyboardDown() async throws {
        // The screen focuses the composer when the generation moves, which is
        // for a thread emptied for a new question. An earlier chat is opened
        // to be read, and on a phone the keyboard would come up over it.
        let threadURL = temporaryLocation("askkit-open-focus").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-focus")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Abbey Road."))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        let before = store.threadGeneration

        await store.openThread(earlier)

        #expect(store.turns.map(\.question) == ["Which records do I own?"])
        #expect(store.threadGeneration == before)
    }

    @Test func aQuestionSentWhileAnEarlierChatOpensIsAskedOnIt() async throws {
        // A send between the chat on screen settling and the chosen one taking
        // its place is asked on the chosen one. Sent to the chat being
        // replaced, it would be lost with it.
        let threadURL = temporaryLocation("askkit-open-send").appendingPathExtension("json")
        let archiveDirectory = temporaryLocation("askkit-open-send")
        defer {
            try? FileManager.default.removeItem(at: threadURL)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        let asker = ScriptedAsker(.init(events: [.tier(.privateCloud), .answer(.of("Answer."))]))
        let (store, archive) = keepingStore(asker: asker, threadURL: threadURL, archiveDirectory: archiveDirectory)
        let earlier = try #require(await archive.archive([earlierEntry("Which records do I own?")]))
        store.ask("Anything from 1969?")
        await settle(store)
        asker.parksReset.withLock { $0 = true }

        let opening = Task { await store.openThread(earlier) }
        await asker.resetIsParked()
        store.ask("Which is the oldest?")
        asker.releaseReset()
        await opening.value
        await settle(store)
        await store.flushPersistence()

        #expect(store.turns.map(\.question) == ["Which records do I own?", "Which is the oldest?"])
        #expect(store.turns.last?.answer?.text == "Answer.")
        #expect(!store.isThinking)
        // Asked of the engine once the chosen chat's recap was in it.
        #expect(asker.lifecycle.withLock { $0 }.suffix(2) == ["reset", "resume"])
        #expect(asker.questions.withLock { $0 }.map(\.0).last == "Which is the oldest?")
        let onDisk = await AskThreadStore<UIRow>(appDirectory: "unused", url: threadURL).load().entries
        #expect(onDisk.map(\.question) == ["Which records do I own?", "Which is the oldest?"])
    }

    @Test func theFirstScreenWaitsForTheFirstOverview() async {
        // Before it, every library reads as empty, and a cold launch would
        // open on the nothing-to-ask screen before the one it meant to show.
        let store = makeStore(asker: ScriptedAsker())
        #expect(!store.stage.firstScreenIsKnown)
        await store.refresh()
        #expect(store.stage.firstScreenIsKnown)
    }

    @Test func aDeviceThatCannotServeNeverOpensOnTheReadyScreen() async {
        // The overview reads at once and the probe takes its time. Known on
        // the overview alone, the stage would show the ready screen and its
        // starters, then swap to can't-serve once the probe came back.
        let asker = ScriptedAsker()
        asker.refreshSnapshot.withLock { $0 = .init(nextTier: nil, unavailability: .deviceNotEligible) }
        asker.parksRefresh.withLock { $0 = true }
        let store = makeStore(asker: asker)

        let refreshing = Task { await store.refresh() }
        await asker.refreshIsParked()
        // Read beside the probe, off the main actor.
        await eventually { store.hasReadOverview }
        #expect(store.hasReadOverview)
        #expect(!store.stage.firstScreenIsKnown)
        asker.releaseRefresh()
        await refreshing.value
        #expect(store.stage.firstScreenIsKnown)
        #expect(store.stage.phase == .cannotServe(.deviceNotEligible))
        #expect(store.composerIsDisabled)
    }

    @Test func aMirrorItsSeamHasPublishedToNeedsNoRefreshToReturn() async {
        // What the seam said before is the model's state: the first screen
        // shows on it while a new probe runs.
        let asker = ScriptedAsker()
        asker.parksRefresh.withLock { $0 = true }
        let store = makeStore(asker: asker)
        store.status.apply(.init(nextTier: .privateCloud))

        let refreshing = Task { await store.refresh() }
        await asker.refreshIsParked()
        await eventually { store.hasReadOverview }
        #expect(store.stage.firstScreenIsKnown)
        #expect(store.stage.phase == .ready)
        asker.releaseRefresh()
        await refreshing.value
    }

    @Test func aDeviceThatCannotServeSaysSoWhileTheOverviewIsStillOut() async {
        // The reason outranks the library, so a host's overview that takes
        // its time, or never returns, has nothing to hold back.
        let domain = UIDomain()
        domain.overviewHook.parks.withLock { $0 = true }
        let asker = ScriptedAsker()
        asker.refreshSnapshot.withLock { $0 = .init(nextTier: nil, unavailability: .deviceNotEligible) }
        let store = makeStore(domain: domain, asker: asker)

        let refreshing = Task { await store.refresh() }
        await domain.overviewHook.isParked()
        await eventually { store.stage.firstScreenIsKnown }
        #expect(store.stage.firstScreenIsKnown)
        #expect(store.stage.phase == .cannotServe(.deviceNotEligible))
        #expect(!store.hasReadOverview)
        domain.overviewHook.release()
        await refreshing.value
    }

    @Test func aSlowOverviewHoldsBackNeitherTheModelsStateNorWhatTheDiskRefused() async throws {
        // On the Mac, the refresh is the only retry of a refused save.
        let folder = try privateFolder()
        defer { makeWritable(folder.folder); try? FileManager.default.removeItem(at: folder.folder) }
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = answeringAsker()
        let store = makeStore(domain: domain, asker: asker, threadURL: folder.thread, archiveDirectory: folder.archive)
        await store.restoreIfNeeded()
        try setMode(0o500, folder.folder)
        store.ask("Anything from 1969?")
        await settle(store)
        await store.flushPersistence()
        #expect(await entriesOnDisk(folder.thread).isEmpty, "the folder refused the save")
        try setMode(0o755, folder.folder)

        domain.overviewHook.parks.withLock { $0 = true }
        let refreshing = Task { await store.refresh() }
        await domain.overviewHook.isParked()
        let deadline = ContinuousClock().now + .seconds(storeWaitDeadline)
        while await entriesOnDisk(folder.thread).isEmpty, ContinuousClock().now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await entriesOnDisk(folder.thread) == ["Anything from 1969?"])
        #expect(store.hasRefreshedStatus)
        #expect(asker.refreshes.withLock { $0 } == 1)
        #expect(!store.hasReadOverview)
        domain.overviewHook.release()
        await refreshing.value
        #expect(store.hasReadOverview)
    }

    /// Whether a refresh begun in the background has come back.
    nonisolated private final class Returned: Sendable {
        private let flag = Mutex(false)
        var value: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }

    /// A refresh begun in the background, and what says when it is back.
    private func refreshInTheBackground(_ store: AskConversationStore<UIDomain>) -> Returned {
        let returned = Returned()
        Task {
            await store.refresh()
            returned.set()
        }
        return returned
    }

    @Test func anOverviewPastTheDeadlineKeepsTheOneBefore() async {
        // Abandoned, as the engine abandons a hook past the turn's deadline,
        // and the library the store last read stands.
        let domain = UIDomain()
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        await store.refresh()
        #expect(store.overview.total == 3)

        // Short only now: the first read has no clock to race.
        domain.overviewHook.deadline.withLock { $0 = .milliseconds(200) }
        domain.overviewHook.parks.withLock { $0 = true }
        let returned = refreshInTheBackground(store)
        await eventually { returned.value }
        #expect(returned.value, "the refresh came back past the deadline")
        #expect(store.overview.total == 3)
        #expect(store.starters.count == 3)
        domain.overviewHook.release()
    }

    @Test func aFirstOverviewPastTheDeadlineOpensOnTheReadyScreen() async {
        // Waiting on it for good, the screen would stay blank over the
        // composer. A library never read can't be called empty, so the
        // screen it opens on is the ready one, not nothing to ask about.
        let domain = UIDomain()
        domain.overviewHook.deadline.withLock { $0 = .milliseconds(200) }
        domain.overviewHook.parks.withLock { $0 = true }
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        let returned = refreshInTheBackground(store)
        await eventually { returned.value }
        #expect(store.stage.firstScreenIsKnown)
        #expect(store.stage.phase == .ready)
        #expect(!store.hasReadOverview)
        domain.overviewHook.release()
    }

    @Test func theOverviewIsReadOffTheMainActor() async {
        // A count over a large store, written as a plain nonisolated async
        // function, would otherwise hitch every return to the foreground.
        let domain = UIDomain()
        let store = makeStore(domain: domain, asker: ScriptedAsker())
        await store.refresh()
        #expect(domain.overviewHook.ranOnTheMainThread.withLock { $0 } == [false])
    }

    @Test func aThreadIsKnownBeforeTheOverviewIsRead() {
        // The flag holds back the first screen and nothing else: a thread read
        // back from disk shows at once, and its stage does not change again
        // when the overview arrives.
        let stage = AskStage.of(
            turnIDs: [UUID()], lastHasText: true, lastIsComplete: true, isThinking: false,
            overview: .empty, unavailability: nil, policy: .ownedLibrary, overviewIsRead: false
        )
        #expect(stage.phase == .thread)
        #expect(stage.firstScreenIsKnown)
    }
}

/// The pairing the thread's rows are built from.
///
/// It exists because the obvious alternative crashes. A `ForEach` that
/// enumerates the turns and then reaches back into `turns[index - 1]` from
/// inside the row builder reads the array *live*, and New Chat empties it
/// while rows are still mounted: `Fatal error: Index out of range`, on every
/// New Chat. A pair is a value; it cannot go out of date.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskThreadPairingTests {

    private func store(_ questions: [String]) async -> AskConversationStore<UIDomain> {
        let asker = ScriptedAsker(.init(events: [.answer(AskAnswer(text: "a", matches: [UIRow("r")]))]))
        let store = makeStore(asker: asker)
        for question in questions {
            store.ask(question)
            await settle(store)
        }
        return store
    }

    @Test func eachTurnIsPairedWithTheOneBeforeIt() async {
        let store = await store(["one", "two", "three"])
        let paired = store.pairedTurns
        #expect(paired.count == 3)
        #expect(paired[0].previous == nil)
        #expect(paired[1].previous?.question == "one")
        #expect(paired[2].previous?.question == "two")
    }

    /// The crash, as a value test: a pairing taken before the thread is emptied
    /// is still readable afterwards, because it holds turns rather than indices.
    @Test func aPairingSurvivesTheThreadBeingEmptied() async {
        let store = await store(["one", "two"])
        let paired = store.pairedTurns
        store.startOver()
        #expect(store.turns.isEmpty)
        #expect(store.pairedTurns.isEmpty)
        // The captured pairing is untouched — no index reaches back into the
        // emptied array.
        #expect(paired.count == 2)
        #expect(paired[1].previous?.question == "one")
    }

    @Test func anEmptyThreadPairsToNothing() {
        #expect(makeStore(asker: ScriptedAsker()).pairedTurns.isEmpty)
    }
}

#endif
