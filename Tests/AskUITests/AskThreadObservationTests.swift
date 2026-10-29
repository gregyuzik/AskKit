#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import Foundation
import Observation
import SwiftUI
import Testing

@testable import AskUI

/// Counts how often what `reads` reads is published, arming again after each.
@MainActor
private final class ObservationTally {
    private(set) var heard = 0
    private let reads: @MainActor () -> Void

    init(_ reads: @escaping @MainActor () -> Void) {
        self.reads = reads
        arm()
    }

    private func arm() {
        withObservationTracking { reads() } onChange: { [weak self] in
            Task { @MainActor in
                self?.heard += 1
                self?.arm()
            }
        }
    }
}

/// What the screen's chrome reads of the thread, and how often it hears it.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskThreadShapeTests {

    private func streamed(words: Int) -> [AskTurnEvent<UIRow>] {
        var events: [AskTurnEvent<UIRow>] = [.tier(.privateCloud)]
        var text = ""
        for index in 1...words {
            text += "word\(index) "
            events.append(.partial(text))
        }
        events.append(.answer(.of(text, tiles: [UIRow("Rumours")])))
        return events
    }

    /// **The chrome hears a turn arrive, write and end, not each word.**
    /// `stage`, `captionTier`, `hasTurns` and `lastTurnID` read the thread's
    /// shape rather than `turns`: derived from `turns`, reading any of them
    /// would be reading every snapshot, and the screen that reads all four
    /// would run its whole body once a token.
    @Test func theChromesReadsAreHeardAHandfulOfTimesATurnNotPerSnapshot() async {
        let asker = ScriptedAsker(.init(events: streamed(words: 30)))
        let store = makeStore(asker: asker)
        await store.restoreIfNeeded()
        let tally = ObservationTally {
            _ = store.stage
            _ = store.captionTier
            _ = store.hasTurns
            _ = store.lastTurnID
        }
        store.ask("What do I own?")
        await settle(store)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.turns.last?.text.isEmpty == false, "the turn streamed")
        #expect(tally.heard > 0)
        #expect(tally.heard <= 8, "thirty snapshots, and heard \(tally.heard) times")
    }

    /// **Nothing `AskScreen.body` reads of the store hears each snapshot.**
    /// Each read the screen's body makes, tallied on its own so a failure
    /// names the one that observes `turns`: the chats it lists
    /// (`currentSummary`, `history`, the `hasChats` they make), the notice
    /// over an unreadable thread, the stage and what is read beside it. Any
    /// of them reading `turns` would run the whole screen's body once a
    /// token, which `ThreadShape` exists to prevent. `currentSummary` sums
    /// the thread's turns up, so it reads the shape's `ended` instead.
    @Test func nothingTheScreensBodyReadsHearsEachSnapshot() async {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let asker = ScriptedAsker(.init(events: streamed(words: 30)))
        let store = makeStore(domain: domain, asker: asker)
        await store.restoreIfNeeded()
        await store.refresh()
        let reads: [(String, @MainActor () -> Void)] = [
            ("stage", { _ = store.stage }),
            ("captionTier", { _ = store.captionTier }),
            ("hasTurns", { _ = store.hasTurns }),
            ("lastTurnID", { _ = store.lastTurnID }),
            ("currentSummary", { _ = store.currentSummary }),
            ("hasChats", { _ = store.currentSummary != nil || !store.history.isEmpty }),
            ("history", { _ = store.history }),
            ("hasRestored", { _ = store.hasRestored }),
            ("offersHistory", { _ = store.offersHistory }),
            ("showsUnreadableThreadNotice", { _ = store.showsUnreadableThreadNotice }),
            ("composerIsDisabled", { _ = store.composerIsDisabled }),
            ("threadGeneration", { _ = store.threadGeneration }),
            ("isThinking", { _ = store.isThinking }),
            ("lastTerminalTurn", { _ = store.lastTerminalTurn }),
            ("proposalAnnouncement", { _ = store.proposalAnnouncement }),
            ("composerFocusRequest", { _ = store.composerFocusRequest }),
            ("availableStarters", { _ = store.availableStarters }),
            ("pendingPhoto", { _ = store.pendingPhoto }),
            ("status", {
                _ = store.status.quotaReached
                _ = store.status.resetDate
                _ = store.status.hasLimitIncreaseSuggestion
                _ = store.status.nextTier
            })
        ]
        let tallies = reads.map { name, read in (name, ObservationTally(read)) }
        store.ask("What do I own?")
        await settle(store)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.turns.last?.text.isEmpty == false, "the turn streamed")
        for (name, tally) in tallies {
            #expect(tally.heard <= 8, "\(name) heard \(tally.heard) times over thirty snapshots")
        }
    }

    /// The notice over an unreadable thread reads the thread only while the
    /// read has failed, so it is tallied over a thread that couldn't be read.
    @Test func theUnreadableThreadsNoticeHearsATurnArriveNotEachSnapshot() async throws {
        var domain = UIDomain()
        domain.persistenceMode = .thread
        let url = temporaryLocation("askkit-notice").appendingPathExtension("json")
        try Data("[[[ not a thread".utf8).write(to: url)
        let asker = ScriptedAsker(.init(events: streamed(words: 30)))
        let store = makeStore(domain: domain, asker: asker, threadURL: url)
        await store.restoreIfNeeded()
        #expect(store.showsUnreadableThreadNotice)
        let tally = ObservationTally { _ = store.showsUnreadableThreadNotice }

        store.ask("What do I own?")
        await settle(store)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(!store.showsUnreadableThreadNotice)
        #expect(tally.heard <= 8, "heard \(tally.heard) times over thirty snapshots")
    }

    /// The stage read from the shape is the stage read from the thread, at
    /// every point a turn passes through.
    @Test func theShapesStageIsTheThreadsStage() async {
        let asker = ScriptedAsker()
        asker.scripts([
            .init(events: [.tier(.privateCloud), .partial("You own")], hangs: true),
            .init(events: streamed(words: 3))
        ])
        let store = makeStore(asker: asker)
        await store.restoreIfNeeded()

        func matchesTheThread() -> Bool {
            store.stage == AskStage.of(
                turns: store.turns, isThinking: store.isThinking,
                overview: store.overview, unavailability: store.unavailability,
                hasNothingToAskCopy: store.brand.nothingToAskCopy != nil, overviewIsRead: store.hasReadOverview,
                statusIsRead: store.statusIsRead
            )
        }

        #expect(matchesTheThread(), "empty")
        store.ask("What do I own?")
        #expect(matchesTheThread(), "asked")
        await eventually { store.turns.last?.text == "You own" }
        #expect(matchesTheThread(), "writing")
        store.stop()
        #expect(matchesTheThread(), "stopped")
        store.ask("And the rest?")
        await settle(store)
        #expect(matchesTheThread(), "answered")
        #expect(store.hasTurns)
        #expect(store.lastTurnID == store.turns.last?.id)

        store.startOver()
        #expect(matchesTheThread(), "New Chat")
        #expect(!store.hasTurns)
        #expect(store.lastTurnID == nil)
    }
}

/// The comparison the question bubble is skipped on, as `AskTurnEqualityTests`
/// pins the row's.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskEquatableQuestionBubbleTests {

    private func bubble(
        question: String = "What do I own?",
        hasAnswerText: Bool = false,
        onCopyAnswer: @escaping () -> Void = {}
    ) -> AskEquatableQuestionBubble {
        AskEquatableQuestionBubble(
            question: question, accent: .blue, morph: nil, photo: nil, photoImage: nil,
            photoThumbnail: { _ in nil }, hasAnswerText: hasAnswerText,
            onCopy: {}, onCopyAnswer: onCopyAnswer, onEdit: {}, onAskAgain: {}
        )
    }

    /// Two snapshots of one answer build the bubble with new closures, and it
    /// must compare equal across them or it is formed again every snapshot. The
    /// answer's first words change what its menu offers, so they must not.
    @Test func aSnapshotIsNoChangeAndTheFirstWordsAre() {
        #expect(bubble(hasAnswerText: true, onCopyAnswer: {}) == bubble(hasAnswerText: true, onCopyAnswer: {}))
        #expect(bubble(hasAnswerText: false) != bubble(hasAnswerText: true))
        #expect(bubble(question: "What do I own?") != bubble(question: "What else?"))
    }

    /// Every stored property there is, so that adding one fails here rather than
    /// quietly joining the ones the comparison leaves out: the closures, which
    /// hold nothing that changes (the type's own note), and the thumbnail loader,
    /// which asks the domain.
    @Test func everyStoredPropertyIsAccountedFor() {
        let found = Set(Mirror(reflecting: bubble()).children.compactMap(\.label))

        #expect(found == [
            "question", "accent", "morph", "photo", "photoImage", "photoThumbnail",
            "hasAnswerText", "onCopy", "onCopyAnswer", "onEdit", "onAskAgain"
        ])
    }
}

#endif
