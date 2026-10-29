import AskCore
import CoreGraphics
import Foundation
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
import SwiftUI
#endif

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// The compile contract, enforced by compiling.
///
/// AskCore's public API states its isolation explicitly, so a consumer that
/// does *not* share the package's approachable posture, such as a host that
/// leaves `NonisolatedNonsendingByDefault` off, still compiles against it
/// (`Package.swift`, AGENTS.md).
///
/// Every other target in the package builds under that posture, and so does
/// the demo, so without this one an AskCore change could pass every check here
/// and fail only in a host's build.
///
/// **This target deliberately has no `swiftSettings` at all.** Nonisolated
/// default isolation, none of the upcoming features. That is the whole point:
/// the assertions below are the compiler's, and they only mean something
/// because this file is built under a posture the rest of the package is not.
/// If a future edit gives this target settings, it stops testing anything.
///
/// **And it imports AskKit as a consumer does, without `@testable`.** A line
/// that compiles only with the package's internals in view proves nothing
/// about an app that sees the public API alone, and a consumer builds a
/// domain, an engine, a store and a screen, which is what
/// `aConsumerBuildsAnEngineAStoreAndAScreenWithoutThePosture` does. The SPI a
/// host's own tests reach for is `CrossPostureSPITests.swift`'s, a file of its
/// own because an SPI import reaches only the file that spells it.
///
/// The AskUI half sits behind AskUI's own platform gate, or it would break
/// the tvOS and watchOS builds.
///
/// **What it catches, measured.** AskCore already calls much of its own API
/// from nonisolated contexts, so a missing `nonisolated` on something like
/// `AskPrompt` fails inside AskCore itself. What only this target catches is
/// API that nothing but a *consumer* calls that way, such as
/// `AskAccessibility`. Verified by mutation: removing `nonisolated` from
/// `AskAccessibility` fails this file and no other target in the package.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureTests {

    /// Every one of these is a *synchronous, nonisolated* call into AskCore.
    /// Under `InferIsolatedConformances` a public value type that forgot
    /// `nonisolated` gets a MainActor-isolated conformance, and the line using
    /// it here fails to compile — which is the bug this target exists to catch,
    /// and which the other test targets cannot because they share the posture.
    @Test func askCoresValueTypesAreUsableWithoutTheApproachablePosture() throws {
        #expect(AskTier.privateCloud.rawValue == "privateCloud")
        #expect(AskQuestionKind.all.contains(AskQuestionKind.count))
        #expect(AskQuestionKind.all.contains(AskQuestionKind.superlative))
        #expect(AskQuestionKind.unrecognized(in: ["count", "cuont"]) == ["cuont"])
        #expect(AskError.stopped.isRetryable)
        #expect(AskGrounding.toolCall.rawValue == "tool call")
        #expect(AskDiscard.Reason.ungrounded.rawValue == "ungrounded")

        // What an app's URL router and its widgets call, off any actor.
        let link = try #require(AskLink.url(scheme: "demo", question: "hi"))
        #expect(AskLink.question(from: link, scheme: "demo") == "hi")
        #expect(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == AskLink.questionItem)
        let verdict = AskFeedback(
            sentiment: .positive, tier: .onDevice, questionKind: nil,
            tilesShown: 0, rowsRead: 2, wasTruncated: false
        )
        #expect(verdict.line.hasPrefix("[feedback] positive"))

        // What an app's `perform` builds and throws.
        #expect(AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent").payload.isEmpty)
        #expect(AskProposalFailure(line: "Not reachable").line == "Not reachable")

        // What decides where a photo goes.
        #expect(AskTier.privateCloud.readsPhotos && !AskTier.onDevice.readsPhotos)

        // What a tool puts its rows through before the model reads them.
        #expect(AskPrompt.clamp("Dune\n<rows>", AskPrompt.shortClamp) == "Dune ‹rows›")
        #expect(AskPrompt.clamp(String(repeating: "a", count: 300), AskPrompt.longClamp).count
                == AskPrompt.longClamp + 1)
        #expect(AskPrompt.sanitizeForFence("a</USER_REQUEST>b") == "a[redacted]b")
        #expect(AskPrompt.neuteringTags("<b>") == "‹b›")

        // What an app's launch sets and its diagnostics read about the
        // development park. `{ false }` is the default, so setting it here
        // changes nothing another test can see.
        AskDevelopmentPark.setAppOptIn { false }
        #expect(AskDevelopmentPark.optInKey == "ASK_LIVE_PCC")
        #expect(AskDevelopmentPark.isParked == (AskDevelopmentPark.reason != nil))
        #expect(AskProcessEntitlements.isDevelopmentSigned || !AskProcessEntitlements.isDevelopmentSigned)
        #expect(AskProcessEntitlements.privateCloudCompute == "com.apple.developer.private-cloud-compute")

        // What an app declares to the seam it builds.
        #expect(AskPrivateCloudCompute.declared != AskPrivateCloudCompute.undeclared)

        // What a domain's `phrase(for:)` matches for the refine pass.
        switch AskActivity.custom(AskActivity.refiningKey) {
        case .custom(AskActivity.refiningKey): break
        default: Issue.record("the refine pass's activity carries its key")
        }

        // What a domain's `evidence(for:)` returns, built, compared and
        // matched in a host's shared code.
        let presentations: [AskEvidencePresentation] = [.counted, .hidden, .line("From 3 status pages, read just now")]
        #expect(AskEvidencePresentation.counted != AskEvidencePresentation.hidden)
        #expect(AskEvidencePresentation.line("From 3 status pages") == .line("From 3 status pages"))
        #expect(AskEvidencePresentation.line("From 3 status pages") != .counted)
        for presentation in presentations {
            switch presentation {
            case .counted, .hidden: break
            case .line(let words): #expect(words.hasPrefix("From 3"))
            }
        }
    }

    /// How long the generation gate lets a holder run before it moves on,
    /// read synchronously off any actor, as a host that sets its own
    /// deadline against it reads it.
    @Test func theGenerationGatesHolderDeadlineIsReadableWithoutThePosture() {
        #expect(AskGenerationGate.holderDeadline == .seconds(90))
    }

    /// The `Codable` conformances specifically: these are what a consumer's
    /// off-main decode touches, and a MainActor-isolated `Codable` is the exact
    /// failure AGENTS.md describes — it compiles inside this package and
    /// refuses in a consumer without the posture.
    @Test func askCoresCodableConformancesDecodeOffTheMainActor() throws {
        let encoded = try JSONEncoder().encode(AskError.quotaReached(resetDate: nil))
        #expect(try JSONDecoder().decode(AskError.self, from: encoded) == .quotaReached(resetDate: nil))

        let tier = try JSONEncoder().encode(AskTier.onDevice)
        #expect(try JSONDecoder().decode(AskTier.self, from: tier) == .onDevice)

        let why = try JSONEncoder().encode(AskUnavailability.modelNotReady)
        #expect(try JSONDecoder().decode(AskUnavailability.self, from: why) == .modelNotReady)
        #expect(try JSONDecoder().decode(AskUnavailability.self, from: Data(#""fromALaterBuild""#.utf8)) == .unknown)

        // The verdict the thread file carries.
        let sentiment = try JSONEncoder().encode(AskFeedback.Sentiment.negative)
        #expect(try JSONDecoder().decode(AskFeedback.Sentiment.self, from: sentiment) == .negative)

        // The list of earlier chats, which the archive decodes off the main actor.
        let summary = AskThreadSummary(
            id: UUID(), title: "hi", startedAt: nil,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0), turnCount: 1
        )
        let filed = try JSONEncoder().encode(summary)
        #expect(try JSONDecoder().decode(AskThreadSummary.self, from: filed) == summary)

        // What an answer offers to do, and what came of it, as the thread file
        // keeps them.
        let proposal = AskProposal(title: "Mark The Peregrine as lent", actionLabel: "Mark as lent")
        let offered = try JSONEncoder().encode(proposal)
        #expect(try JSONDecoder().decode(AskProposal.self, from: offered) == proposal)
        let outcome = try JSONEncoder().encode(AskProposalOutcome.confirmed("Marked The Peregrine as lent."))
        #expect(try JSONDecoder().decode(AskProposalOutcome.self, from: outcome) == .confirmed("Marked The Peregrine as lent."))
        let performing = try JSONEncoder().encode(AskProposalOutcome.performing)
        #expect(try JSONDecoder().decode(AskProposalOutcome.self, from: performing) == .performing)

        // A refine pass resolves its tiles as the engine does: an exact title.
        let rows = [CrossPostureRow(id: "Alien"), CrossPostureRow(id: "Aliens")]
        #expect(AskAnswer<CrossPostureRow>.tiles(named: ["Aliens"], text: "Aliens.", matches: rows) == [rows[1]])

        // The photo a question was asked with, as the thread file keeps it.
        let photo = AskQuestionPhoto(label: "Blue record sleeve", reference: "asset-1")
        let kept = try JSONEncoder().encode(photo)
        #expect(try JSONDecoder().decode(AskQuestionPhoto.self, from: kept) == photo)
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    /// AskUI's own nonisolated surface: the identifiers exist so one UI-test
    /// recipe drives every host, and an XCUITest method is nonisolated.
    @Test func askUIsIdentifiersAreReadableFromANonisolatedContext() {
        #expect(AskAccessibility.root == "ask.root")
        #expect(AskAccessibility.retry == "ask.retry")
        #expect(AskAccessibility.attach == "ask.attach")
        #expect(AskAccessibility.slotField == "ask.slot.field")
        #expect(AskAccessibility.slotSend == "ask.slot.send")
        #expect(AskAccessibility.anotherPick == "ask.anotherPick")
        #expect(AskAccessibility.basis == "ask.basis")
        #expect(AskAccessibility.feedbackPositive == "ask.feedback.positive")
        #expect(AskAccessibility.pendingPhoto == "ask.photo.pending")
        #expect(AskAccessibility.removePhoto == "ask.photo.remove")
        #expect(AskAccessibility.questionPhoto == "ask.question.photo")
        #expect(AskAccessibility.photoUnread == "ask.photo.unread")
        #expect(AskAccessibility.newChat == AskAccessibility.clear)
        #expect(AskAccessibility.historyClose == "ask.history.close")
        #expect(AskAccessibility.historyRow == "ask.history.row")
        #expect(AskAccessibility.historyDelete == "ask.history.delete")
        #expect(AskAccessibility.historyDeleteAllConfirm == "ask.history.deleteAll.confirm")
        #expect(AskAccessibility.field == "ask.field")
        #expect(AskAccessibility.questionCopy == "ask.question.copy")
        #expect(AskAccessibility.questionCopyAnswer == "ask.question.copyAnswer")
        #expect(AskAccessibility.questionEdit == "ask.question.edit")
        #expect(AskAccessibility.questionAskAgain == "ask.question.askAgain")
        #expect(AskAccessibility.evidence == "ask.evidence")
        #expect(AskAccessibility.declineSuggestion == "ask.chip.decline")
        #expect(AskAccessibility.tryAsking == "ask.tryAsking")
        #expect(AskAccessibility.nothingAction == "ask.nothingAction")
        #expect(AskAccessibility.quotaShowOptions == "ask.quota.showOptions")
        #expect(AskAccessibility.privateCloudShowOptions == "ask.privateCloud.showOptions")
        #expect(AskAccessibility.privateCloudRunEval == "ask.privateCloud.runEval")
        #expect(AskAccessibility.privateCloudShareResults == "ask.privateCloud.shareResults")
        #expect(AskAccessibility.privateCloudShareFeedback == "ask.privateCloud.shareFeedback")
        #expect(AskAccessibility.thinking == "ask.thinking")
        #expect(AskAccessibility.results == "ask.results")
        #expect(AskAccessibility.jumpToLatest == "ask.jumpToLatest")
        #expect(AskAccessibility.coaching == "ask.coaching")
        #expect(AskAccessibility.feedbackNegative == "ask.feedback.negative")
        #expect(AskAccessibility.historyList == "ask.history.list")
        #expect(AskAccessibility.historyCurrent == "ask.history.current")
        #expect(AskAccessibility.historyDeleteAll == "ask.history.deleteAll")
        #expect(AskAccessibility.historyPane == "ask.history.pane")
        #expect(AskAccessibility.proposalConfirm == "ask.proposal.confirm")
        #expect(AskAccessibility.proposalDecline == "ask.proposal.decline")
        #expect(AskAccessibility.proposalOutcome == "ask.proposal.outcome")
    }

    /// Two turns compared off any actor, as a host's own view builder or a
    /// diff of its own compares them. `AskTurn` is a `nonisolated` value, and
    /// its `==` is the thread's skip contract: spelled without `nonisolated`,
    /// the conformance is main-actor isolated and this fails to compile.
    @Test func twoTurnsAreComparedWithoutThePosture() {
        let turn = AskTurn<CrossPosturePlainRow>(question: "What do I own?", origin: .typed)
        let copy = turn
        #expect(turn == copy)
        #expect(turn != AskTurn<CrossPosturePlainRow>(question: "What do I own?", origin: .typed))
    }

    /// What the screen and the card read, compared and switched over off any
    /// actor: the stage and its phase, a proposal's phase and the settings
    /// card's state.
    @Test func theScreensValuesAreReadWithoutThePosture() {
        let phase = AskStage.Phase.cannotServe(.deviceNotEligible)
        #expect(phase != .ready)
        #expect(phase == .cannotServe(.deviceNotEligible))
        #expect(AskStage.Phase.nothingToAskAbout != .ready)
        #expect(AskProposalPhase.awaiting.takesATap)
        #expect(!AskProposalPhase.done(nil).takesATap)
        #expect(AskProposalPhase.failed(nil, canRetry: true) != .notDone)
        #expect(!AskProposalPhase.outcomeUnknown.takesATap)
        #expect(!AskProposalPhase.handedOff(nil).takesATap && !AskProposalPhase.declined.takesATap)
        let state = AskPrivateCloudState.of(quotaReached: false, quotaApproaching: false, unavailability: .notEntitled)
        #expect(state == .notEntitled)
        #expect(!state.isServing)
        #expect(!state.message().isEmpty)
        // Every other state the card can be in, worked out as it works them out.
        let states = [
            AskPrivateCloudState.of(quotaReached: false, quotaApproaching: true, unavailability: nil),
            .of(quotaReached: true, quotaApproaching: false, unavailability: nil),
            .of(quotaReached: false, quotaApproaching: false, unavailability: .offline),
            .of(quotaReached: false, quotaApproaching: false, unavailability: .languageNotSupported),
            .of(quotaReached: false, quotaApproaching: false, unavailability: .systemNotReady)
        ]
        #expect(states == [.approachingLimit, .limitReached, .offline, .languageNotSupported, .unavailable])
        #expect(states.map(\.isServing) == [true, false, false, false, false])
    }

    /// The mirror's own flag for having heard from its seam, read where the
    /// mirror lives.
    @MainActor
    @Test func aMirrorSaysWhetherItsSeamHasPublished() {
        let status = AskModelStatus()
        #expect(!status.hasHeardFromSeam)
        status.apply(.init(nextTier: .onDevice))
        #expect(status.hasHeardFromSeam)
    }

    /// Which bank a chip came from, compared, hashed and read off any actor.
    @Test func aChipsKindIsUsableFromANonisolatedContext() {
        let kind = AskChipRow.Kind.followUp
        #expect(kind != .starter)
        #expect(kind.rawValue == "followUp")
        #expect(AskChipRow.Kind(rawValue: "starter") == .starter)
        #expect(Set([kind, .starter, .followUp]).count == 2)
    }

    /// The button before the composer's field, the photo button and a chip
    /// that isn't a question, as a host without the posture holds them. Each
    /// is built on the main actor, where its initializer and its action are
    /// isolated. That isolation makes each `Sendable`, so the host keeps it in
    /// a value of its own off that actor, and runs its action back on it.
    @Test func anAccessoryAndAChipActionAreHeldOffTheMainActor() async {
        let setup = await MainActor.run {
            let taps = CrossPostureTaps()
            return CrossPostureAskSetup(
                taps: taps,
                scan: AskComposerAccessory(
                    systemImage: "barcode.viewfinder", label: Text(verbatim: "Scan"), identifier: "host.scan"
                ) { taps.names.append("scan") },
                photo: .photo { taps.names.append("photo") },
                another: AskChipRow.Action(
                    title: Text(verbatim: "Another pick"), systemImage: "dice",
                    hint: Text(verbatim: "Asks for a different pick"), identifier: "host.another"
                ) { taps.names.append("another") }
            )
        }
        let tapped = await MainActor.run {
            setup.scan.action()
            setup.photo.action()
            setup.another.perform()
            return setup.taps.names
        }
        #expect(tapped == ["scan", "photo", "another"])
        let identifiers = await MainActor.run {
            [setup.scan.identifier, setup.photo.identifier, setup.another.identifier]
        }
        #expect(identifiers == ["host.scan", AskAccessibility.attach, "host.another"])
        let glyphs = await MainActor.run {
            [setup.scan.systemImage, setup.photo.systemImage, setup.another.systemImage]
        }
        #expect(glyphs == ["barcode.viewfinder", "photo", "dice"])
    }

    /// A spectrum, built, compared, hashed and read off any actor, as a host
    /// keeps one in a value or a setting of its own. `AskSpectrum` is a
    /// `nonisolated` value: spelled without it, its `Hashable` conformance and
    /// `aurora` are main-actor isolated, and this fails to compile.
    @Test func aSpectrumIsBuiltAndComparedWithoutThePosture() {
        let mine = AskSpectrum([.red, .orange, .pink])
        #expect(mine == AskSpectrum([.red, .orange, .pink]))
        #expect(mine != .aurora)
        #expect(mine.colors.count == 3)
        #expect(AskSpectrum.aurora.colors.count == 5)
        #expect(Set([mine, .aurora, AskSpectrum([.red, .orange, .pink])]).count == 2)
    }

    /// The composer, built on the main actor, where its initializer is
    /// isolated, and handed back off it: that isolation makes it `Sendable`.
    @Test func aComposerIsBuiltOnTheMainActorAndHeldOffIt() async {
        _ = await MainActor.run {
            AskComposer(
                draft: .constant("How many?"), isFocused: FocusState<Bool>().projectedValue,
                placeholder: "Ask about your rows", accent: .blue, isThinking: false,
                onSend: {}, onStop: {}, accessory: .photo {}
            )
        }
    }
    #endif
}

#if os(iOS) || os(macOS) || os(visionOS)
/// A host's own main-actor state, which its buttons' actions change.
@MainActor private final class CrossPostureTaps {
    var names: [String] = []
}

/// A `Sendable` value of a host's own, holding the buttons it hands the Ask
/// screen. It compiles only while each of them is `Sendable`, which
/// `nonisolated` on either type would end: each holds a closure that isn't.
private struct CrossPostureAskSetup: Sendable {
    let taps: CrossPostureTaps
    let scan: AskComposerAccessory
    let photo: AskComposerAccessory
    let another: AskChipRow.Action
}
#endif

/// A row as a consumer without the posture declares one, for the API that
/// builds on every platform: `CrossPostureRow` sits behind the Foundation
/// Models platform gate with the domain it serves.
private struct CrossPosturePlainRow: AskRow {
    let id: String
    var displayTitle: String { id }
}

extension CrossPostureTests {
    /// What a stream yields to a host's own store, compared and switched over
    /// off any actor.
    @Test func aTurnsEventsAreComparedWithoutThePosture() {
        let row = CrossPosturePlainRow(id: "Dune")
        let events: [AskTurnEvent<CrossPosturePlainRow>] = [
            .tier(.privateCloud), .activity(.searching(scope: nil)), .activityEnded, .rowsRead([row]),
            .restarted(.onDevice), .tier(.onDevice), .summarized, .partial("Two."), .refining,
            .answer(AskAnswer(text: "Two.", matches: [row], tiles: [row]))
        ]
        #expect(events.first == .tier(.privateCloud))
        #expect(events.filter { if case .tier = $0 { true } else { false } }.count == 2)
        guard case .answer(let answer) = events.last else {
            Issue.record("the last event is the answer")
            return
        }
        #expect(answer.tiles == [row])
    }

    /// What a domain's refine pass cleans the follow-ups it writes with, off
    /// any actor, to tell whether the revision's survive before it chooses
    /// between them and the first answer's.
    @Test func aRefinePassCleansItsFollowUpsWithoutThePosture() {
        typealias Answer = AskAnswer<CrossPosturePlainRow>
        let first = Answer(text: "Two.", followUps: ["Which is oldest?"])
        let revised = Answer.cleanedFollowUps(["", "One\nTwo", "  "])
        #expect((revised.isEmpty ? first.followUps : revised) == ["Which is oldest?"])
        #expect(Answer.cleanedFollowUps(
            ["  What else?  ", "what else?", "One\nTwo", "", "And after that?", "A third?"]
        ) == ["What else?", "And after that?"])
        #expect(Answer.maxFollowUps == 2 && Answer.maxFollowUpLength == 80)
    }

    /// What the thread file holds, encoded and decoded off the main actor as
    /// a host's own archive would, and what a read of it says.
    @Test func aThreadEntryAndItsReadAreUsableWithoutThePosture() throws {
        let row = CrossPosturePlainRow(id: "Dune")
        let entry = AskThreadEntry(
            question: "How many?", text: "Two.", answer: AskAnswer(text: "Two.", matches: [row]),
            tier: .onDevice, feedback: .positive
        )
        let kept = try JSONEncoder().encode([entry])
        let read = try JSONDecoder().decode([AskThreadEntry<CrossPosturePlainRow>].self, from: kept)
        #expect(read == [entry])
        // Read by its case, the only public way: no thread and a thread that
        // couldn't be read are not an empty one.
        let reads: [AskThreadRead<CrossPosturePlainRow>] = [.thread(read, dropped: 0), .empty, .unreadable]
        let entries = reads.map { read -> [AskThreadEntry<CrossPosturePlainRow>]? in
            if case .thread(let entries, dropped: 0) = read { return entries }
            return nil
        }
        #expect(entries == [[entry], nil, nil])
    }

    /// A deadline raced from a host's own nonisolated code, as it might bound
    /// a lookup of its own.
    @Test func aDeadlineIsRacedWithoutThePosture() async throws {
        #expect(try await AskDeadline.run(seconds: 5) { 42 } == 42)
        #expect(try await AskDeadline.run(.seconds(5)) { "done" } == "done")
    }

    /// What a domain declares about its first screen, its thread and its
    /// proposals, compared and decoded off any actor.
    @Test func aDomainsPoliciesAreUsableWithoutThePosture() throws {
        let policy = AskFirstScreenPolicy(answersWithoutModel: true, needsOwnedRows: false)
        #expect(policy != .ownedLibrary)
        #expect(AskFirstScreenPolicy.ownedLibrary == AskFirstScreenPolicy())
        #expect(policy.answersWithoutModel && !policy.needsOwnedRows)

        let persistence = try JSONEncoder().encode(AskPersistence.perLaunch)
        #expect(try JSONDecoder().decode(AskPersistence.self, from: persistence) == .perLaunch)
        #expect(AskPersistence.thread.rawValue == "thread")

        let kind = try JSONEncoder().encode(AskProposalKind.handOff)
        #expect(try JSONDecoder().decode(AskProposalKind.self, from: kind) == .handOff)
        #expect(AskProposal(kind: .handOff, title: "Draft a note", actionLabel: "Open").kind == .handOff)
    }

    /// The default sink, built and written to from a host's own nonisolated
    /// code: every line it logs.
    @Test func theDefaultSinkLogsWithoutThePosture() {
        let sink = AskOSLogSink(subsystem: "askkit.crossposture")
        sink.turn(AskTurnStats(tier: .onDevice))
        sink.routing("heard off any actor")
        sink.discard(AskDiscard(tier: .onDevice, reason: .empty, text: ""))
        sink.feedback(AskFeedback(
            sentiment: .negative, tier: .onDevice, questionKind: nil,
            tilesShown: 0, rowsRead: 0, wasTruncated: false
        ))
    }

    /// What a seam of a host's own publishes, built and compared off any
    /// actor before it hops to the mirror.
    @Test func aMirrorSnapshotIsBuiltWithoutThePosture() {
        #expect(AskModelStatus.Snapshot() == AskModelStatus.Snapshot(nextTier: nil))
        #expect(AskModelStatus.Snapshot(nextTier: .onDevice) != AskModelStatus.Snapshot())
    }
}

// MARK: - The rest of the public API, named

/// Public members nothing above names, each called the way a host calls it.
/// A member this target never calls can lose the isolation it spells with
/// nothing here to notice (AGENTS.md), so each one a host reaches for off any
/// actor gets a line.
extension CrossPostureTests {
    /// What a host's own sink reads of a turn before it logs it its own way:
    /// every field, and the two lines AskKit's sink builds from them.
    @Test func aTurnsStatsAreReadWithoutThePosture() {
        var stats = AskTurnStats(tier: .onDevice)
        stats.snapshots = 4
        stats.growths = 2
        stats.characters = 40
        stats.toolCalls = 1
        stats.rowsRead = 3
        stats.msToFirstTool = 120
        stats.msToFirstWord = 300
        stats.msToLastWord = 900
        stats.msTotal = 1_000
        stats.grounding = .appRetrieved
        stats.retried = true
        #expect(stats.meanDelta == 20)
        #expect(stats.streamLine == "[stream] onDevice snapshots=4 growths=2 firstWord=300ms proseSpan=600ms "
            + "chars=40 meanDelta=20 firstTool=120ms tools=1 rows=3 grounding=app retrieved retried total=1000ms")
        #expect(stats.usageLine == nil)
        stats.inputTokens = 120
        stats.outputTokens = 30
        #expect(stats.usageLine == "[usage] onDevice input=120 cached=– output=30 reasoning=–")
        #expect(AskDiscard.Reason.deadlineWithNothingToKeep.rawValue == "deadline with nothing to keep")
    }

    /// What a seam of a host's own says of each tier, and the rest of what
    /// it publishes, built and read off any actor.
    @Test func aTiersStateIsReadWithoutThePosture() {
        let cooled = AskTierState(tier: .privateCloud, isAvailable: true, speaksLanguage: true, isCooled: true)
        #expect(cooled.isCooled && !cooled.isServable)
        #expect(AskTierState(tier: .onDevice, isAvailable: true, speaksLanguage: true).isServable)
        var snapshot = AskModelStatus.Snapshot(hasLimitIncreaseSuggestion: true, privateCloudUnavailability: .offline)
        #expect(snapshot.hasLimitIncreaseSuggestion && snapshot.privateCloudUnavailability == .offline)
        snapshot.privateCloudUnavailability = nil
        #expect(snapshot != AskModelStatus.Snapshot(hasLimitIncreaseSuggestion: true, privateCloudUnavailability: .offline))
    }

    /// What a host's diagnostics read on the main actor, where the mirror and
    /// the app's switch live: what the seam last published, and whether the
    /// app turned diagnostics on.
    @MainActor
    @Test func aMirrorsPrivateCloudFieldsAreReadWhereItLives() {
        let status = AskModelStatus()
        status.apply(.init(nextTier: .onDevice, hasLimitIncreaseSuggestion: true, privateCloudUnavailability: .notEntitled))
        #expect(status.hasLimitIncreaseSuggestion)
        #expect(status.privateCloudUnavailability == .notEntitled)
        #expect(AskDiagnostics.enabledByApp || !AskDiagnostics.enabledByApp)
        #expect(AskDiagnostics.isDebugBuild || !AskDiagnostics.isDebugBuild)
    }

    /// What an answer says about itself, read off any actor, as a host's own
    /// footer reads the answer it is handed: whether it was cut short, the
    /// rows its prose names, and the bounds on its tiles.
    @Test func anAnswersOwnReadingsAreMadeWithoutThePosture() {
        let rows = [CrossPosturePlainRow(id: "Dune"), CrossPosturePlainRow(id: "Emma")]
        let answer = AskAnswer(text: "Dune is the longer one.", matches: rows, isTruncated: true)
        #expect(answer.isTruncated)
        #expect(answer.mentioned == [rows[0]])
        #expect(AskAnswer<CrossPosturePlainRow>.maxTiles == 24)
        #expect(AskAnswer<CrossPosturePlainRow>.wholeWordBelow == 4)
    }

    /// What a domain's overview and brand say, built and read off any actor.
    @Test func anOverviewsOrderAndABrandsActionAreReadWithoutThePosture() {
        let overview = AskOverview(
            scopes: [AskOverview.Scope(id: "albums", name: "Albums", count: 2), AskOverview.Scope(id: "books", name: "Books", count: 5)],
            total: 7
        )
        #expect(overview.byCount.map(\.id) == ["books", "albums"])
        let brand = AskBrand(
            title: "Ask", shortLabel: "Ask", appDirectory: "AskKitCrossPosture",
            logSubsystem: "askkit.crossposture", help: "Ask about your rows.",
            firstScreenHeadline: "Ask", firstScreenSentence: "Ask about your rows.",
            nothingToAskCopy: "Nothing to ask about yet.", nothingToAskActionLabel: "Add a row",
            disclosureSentence: "Answers come from your rows.", scopeCaveat: "Only your rows."
        )
        #expect(brand.nothingToAskActionLabel == "Add a row")
    }

    /// A proposal's detail, the bound on its payload and the lines the model
    /// reads once it has proposed, off any actor, and the two outcomes the
    /// tests above don't keep, as the thread file keeps them.
    @Test func aProposalsDetailAndReceiptsAreReadWithoutThePosture() throws {
        let proposal = AskProposal(title: "Lend The Peregrine", detail: "To Sam, until June", actionLabel: "Lend")
        #expect(proposal.detail == "To Sam, until June")
        #expect(AskProposal.maxPayloadBytes == 4_096)
        #expect(AskProposal.modelReceipt.hasPrefix("Proposed, not done"))
        #expect(AskProposal.handOffReceipt.hasPrefix("Proposed, not done"))
        for outcome in [AskProposalOutcome.handedOff("Opened the form."), .declined] {
            let kept = try JSONEncoder().encode(outcome)
            #expect(try JSONDecoder().decode(AskProposalOutcome.self, from: kept) == outcome)
        }
    }

    /// The line under every failure, read off any actor as a host's own
    /// screen or Siri intent says it.
    @Test func everyErrorsLineIsReadWithoutThePosture() {
        let errors: [AskError] = [
            .modelUnavailable(.offline), .couldNotAnswer, .ungrounded, .refused, .privateCloudUnreachable,
            .contextTooLarge, .photosNotSupported, .quotaReached(resetDate: nil), .stopped
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        #expect(AskError.modelUnavailable(.offline).errorDescription == AskError.unavailableMessage(.offline))
        #expect(AskUnavailability.allCases.allSatisfy { !AskError.unavailableMessage($0).isEmpty })
        let reasons: [AskUnavailability] = [.appleIntelligenceOff, .systemNotReady, .languageNotSupported, .offline]
        #expect(Set(reasons.map(\.rawValue)).count == 4)
    }

    /// One entry's failure, date and photo fields, read off any actor as a
    /// host's own archive reads the thread file.
    @Test func aThreadEntrysOtherFieldsAreReadWithoutThePosture() {
        let asked = Date(timeIntervalSinceReferenceDate: 0)
        let entry = AskThreadEntry<CrossPosturePlainRow>(
            question: "What is this?", text: "", answer: nil,
            failureMessage: "Couldn't answer that just now.", failure: .couldNotAnswer, failureIsRetryable: true,
            askedAt: asked, summarizedBefore: true, proposalOutcome: .declined,
            photo: AskQuestionPhoto(label: "A record sleeve", reference: "asset-1"), answerSawPhoto: true
        )
        #expect(entry.failureMessage == "Couldn't answer that just now." && entry.failureIsRetryable)
        #expect(entry.askedAt == asked && entry.summarizedBefore)
        #expect(entry.proposalOutcome == .declined && entry.answerSawPhoto)
    }

    /// What bounds the thread, the archive and the feedback attachments, and
    /// what each reads where nothing has been written, asked off any actor.
    /// Under a folder nobody creates, as the store's are above.
    @Test func theStoresBoundsAndFirstReadsAreUsableWithoutThePosture() async {
        #expect(AskThreadStore<CrossPosturePlainRow>.maxPersistedTurns == 50)
        #expect(AskThreadArchive<CrossPosturePlainRow>.maxThreads == 50)
        #expect(AskFeedbackAttachments.maxKept == 10)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "AskKitCrossPosture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let thread = AskThreadStore<CrossPosturePlainRow>(
            appDirectory: "AskKitCrossPosture", url: folder.appending(path: "thread.json"),
            logSubsystem: "askkit.crossposture"
        )
        guard case .empty = await thread.load() else {
            Issue.record("a thread never written reads as none")
            return
        }
        let archive = AskThreadArchive<CrossPosturePlainRow>(
            appDirectory: "AskKitCrossPosture", directory: folder.appending(path: "threads"),
            logSubsystem: "askkit.crossposture"
        )
        #expect(await archive.summaries().isEmpty)
        let attachments = AskFeedbackAttachments(
            appDirectory: "AskKitCrossPosture", directory: folder.appending(path: "feedback"),
            logSubsystem: "askkit.crossposture"
        )
        #expect(await attachments.urls().isEmpty)
    }

    /// A host's own on-device generation, through the one gate the process
    /// shares, from its own nonisolated code.
    @Test func aHostsOwnGenerationWaitsAtTheSharedGateWithoutThePosture() async throws {
        #expect(try await AskGenerationGate.run { 42 } == 42)
        #expect(try await AskGenerationGate.run(deadline: .seconds(5)) { "done" } == "done")
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
/// AskUI's `nonisolated` values a host's own views and announcements read: a
/// turn and its failure, what VoiceOver is told, how a piece arrives and the
/// layout's measures.
extension CrossPostureTests {
    fileprivate typealias PlainTurn = AskTurn<CrossPosturePlainRow>

    /// What VoiceOver is told as a turn ends and as a proposal comes to
    /// something, worked out off any actor, as a host's own view announcing
    /// it would.
    @Test func whatVoiceOverIsToldIsWorkedOutWithoutThePosture() {
        #expect(AskAnnouncement.terminal(for: PlainTurn?.none) == nil)
        #expect(AskAnnouncement.terminal(for: PlainTurn(question: "How many?", origin: .typed)) == nil)
        let failed = PlainTurn(entry: AskThreadEntry(
            question: "How many?", text: "", answer: nil, failureMessage: "Not now.", failureIsRetryable: true
        ))
        #expect(AskAnnouncement.terminal(for: failed) == "Not now.")
        let answered = PlainTurn(entry: AskThreadEntry(question: "How many?", text: "Two.", answer: AskAnswer(text: "Two.")))
        #expect(AskAnnouncement.terminal(for: answered)?.isEmpty == false)

        #expect(AskAnnouncement.proposal(.confirmed("Lent.")) == "Lent.")
        #expect(AskAnnouncement.proposal(.handedOff("Opened the form.")) == "Opened the form.")
        #expect(AskAnnouncement.proposal(.failed("Not reachable")) == "Not reachable")
        #expect(AskAnnouncement.proposal(.declined)?.isEmpty == false)
        #expect(AskAnnouncement.proposal(.performing) == nil)

        // Each announcement is one of its own, so the same line twice is
        // spoken twice.
        let lent = AskProposalAnnouncement(line: "Lent.")
        #expect(lent == lent && lent.line == "Lent.")
        #expect(lent != AskProposalAnnouncement(line: "Lent."))
    }

    /// A turn's failure, built, compared and read off any actor, as a host's
    /// own view builder reads the turn it is handed.
    @Test func aTurnsFailureIsBuiltAndReadWithoutThePosture() {
        let coaching = [AskStarter(text: "How many books do I own?")]
        let failure = PlainTurn.Failure(message: "Not now.", retryable: false, error: .refused, coaching: coaching)
        #expect(failure == PlainTurn.Failure(message: "Not now.", retryable: false, error: .refused, coaching: coaching))
        #expect(!failure.retryable && failure.error == .refused && failure.coaching == coaching)
        #expect(failure != PlainTurn.Failure(message: "Not now.", retryable: true))
    }

    /// What a host's view builder reads of the turn it is handed beyond its
    /// question, off any actor: when it was asked, whether it has ended or
    /// written anything, and what came of its photo and its proposal.
    @Test func aTurnsStateIsReadWithoutThePosture() {
        let asked = Date(timeIntervalSinceReferenceDate: 0)
        let photo = AskQuestionPhoto(label: "A record sleeve", reference: "asset-1")
        let fresh = PlainTurn(question: "What is this?", origin: .typed, askedAt: asked, photo: photo)
        #expect(fresh.askedAt == asked && fresh.photoImage == nil)
        #expect(!fresh.isComplete && !fresh.hasContent && !fresh.answeredWithoutPhoto)
        #expect(!fresh.isPerformingProposal && !fresh.summarizedBefore && fresh.proposalOutcome == nil)

        let read = PlainTurn(entry: AskThreadEntry(
            question: "What is this?", text: "A record.", answer: AskAnswer(text: "A record."),
            summarizedBefore: true, proposalOutcome: .declined, photo: photo
        ))
        #expect(read.isComplete && read.hasContent && read.summarizedBefore)
        #expect(read.proposalOutcome == .declined)
        #expect(!read.answerSawPhoto && read.answeredWithoutPhoto)
    }

    /// How a host's own piece under an answer comes up, and the measures it
    /// lays its own views out to, compared and worked out off any actor.
    @Test func theArrivalsKindsAndTheLayoutsMeasuresAreReadWithoutThePosture() {
        #expect(AskArrival.Kind.line != .piece)
        #expect(AskLayout.readingWidth == 680)
        #if os(macOS) || os(visionOS)
        #expect(AskLayout.starterBank == 8)
        #else
        #expect(AskLayout.starterBank == 3)
        #endif
        #expect(AskLayout.tileColumns(for: 1) == .adaptive(minimum: 150, maximum: 160, spacing: 8))
        #expect(AskLayout.tileColumns(for: 2, tallestAspect: 0.5, spacing: 10) == .adaptive(minimum: 65, maximum: 70, spacing: 10))
        #expect(AskLayout.tileColumns(for: 7).fit(in: 366).count == 4)
    }

    /// The pieces a host mounts on their own rather than through the screen,
    /// and the modifiers it puts on views of its own, built on the main actor,
    /// where each is isolated.
    @MainActor
    @Test func theScreensOtherPiecesAreBuiltWithoutThePosture() {
        _ = AskHistoryButton {}
        _ = AskNewChatButton(isEnabled: true) {}
        _ = AskJumpToLatestPill {}
        _ = AskQuotaBanner(resetDate: nil, canRequestMore: true) {}
        let brand = AskBrand(
            title: "Ask", shortLabel: "Ask", appDirectory: "AskKitCrossPosture",
            logSubsystem: "askkit.crossposture", help: "Ask about your rows.",
            firstScreenHeadline: "Ask", firstScreenSentence: "Ask about your rows.",
            disclosureSentence: "Answers come from your rows.", scopeCaveat: "Only your rows."
        )
        _ = AskFirstScreen(
            phase: .ready, brand: brand, starters: [AskStarter(text: "How many?")],
            onStarter: { _ in }, mark: { AskDefaultMark(isLit: $0) }
        )
        _ = AskPictureArrival(Optional("Kind of Blue")) { Text(verbatim: $0) } placeholder: { Color.gray }
        _ = Text(verbatim: "A tile of the host's own").askArrival(1, as: .line).askReadingColumn().askTierCaption(.onDevice)
        _ = EmptyView().modifier(AskTierCaption(tier: nil)).environment(\.askItemIsPushed, true)
        #expect(AskTierCaption.name(nil) == nil)
        #expect(AskTierCaption.name(.privateCloud) == "Private Cloud Compute")
    }
}
#endif

#if canImport(FoundationModels) && !os(tvOS)
/// A row and an envelope as a consumer without the posture declares them:
/// plain types, nonisolated by this target's default.
private struct CrossPostureRow: AskRow {
    let id: String
    var displayTitle: String { id }
}

private struct CrossPostureEnvelope: Codable, Sendable {
    var parts: [String]
}

/// What the model fills in to call the one tool, and what the grounded retry
/// plans with.
@Generable
private struct CrossPostureSearchArguments: Sendable {
    @Guide(description: "Words from the question")
    var query: String
}

/// A tool as a consumer without the posture writes one: a plain `call`, with
/// no `@concurrent`. Here a nonisolated `async` function already runs off
/// every actor, so the annotation the package's own tools need is a no-op.
private struct CrossPostureSearchTool: Tool {
    let name = "search"
    let description = "Search the rows by words from the question."
    let context: AskToolContext<CrossPostureRow>

    func call(arguments: CrossPostureSearchArguments) async throws -> String {
        await context.withToolCall(.searching(scope: nil)) { collector in
            await collector.record(rows: [CrossPostureRow(id: arguments.query)])
            return (arguments.query, report: .reading(shown: 1, total: 1, scope: nil))
        }
    }
}

/// The smallest domain a consumer can write: the members `AskDomain` has no
/// default for, plus `promptLines`. Everything else is the protocol's
/// default.
private struct CrossPostureDomain: AskDomain {
    let brand = AskBrand(
        title: "Ask", shortLabel: "Ask", appDirectory: "AskKitCrossPosture",
        logSubsystem: "askkit.crossposture", help: "Ask about your rows.",
        firstScreenHeadline: "Ask", firstScreenSentence: "Ask about your rows.",
        nothingToAskCopy: "Nothing to ask about yet.",
        disclosureSentence: "Answers come from your rows.", scopeCaveat: "Only your rows."
    )

    func overview() async -> AskOverview {
        AskOverview(scopes: [AskOverview.Scope(id: "rows", name: "Rows", count: 1)], total: 1)
    }

    func makeTools(_ context: AskToolContext<CrossPostureRow>) -> [any Tool] {
        [CrossPostureSearchTool(context: context)]
    }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        "Answer from the rows."
    }

    func promptLines(question: String, overview: AskOverview) async -> [String] {
        [question]
    }

    func search(_ arguments: CrossPostureSearchArguments, context: AskToolContext<CrossPostureRow>) async throws -> String {
        try await CrossPostureSearchTool(context: context).call(arguments: arguments)
    }
}

/// `CrossPostureDomain`, taking photos, so a store's composer can hold one.
private struct CrossPosturePhotoDomain: AskDomain {
    private let base = CrossPostureDomain()
    var brand: AskBrand { base.brand }
    var acceptsPhotoAttachments: Bool { true }

    func overview() async -> AskOverview { await base.overview() }

    func makeTools(_ context: AskToolContext<CrossPostureRow>) -> [any Tool] { base.makeTools(context) }

    func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String {
        base.instructions(tier: tier, isConversation: isConversation, answerLanguage: answerLanguage)
    }

    func promptLines(question: String, overview: AskOverview) async -> [String] {
        await base.promptLines(question: question, overview: overview)
    }

    func search(_ arguments: CrossPostureSearchArguments, context: AskToolContext<CrossPostureRow>) async throws -> String {
        try await base.search(arguments, context: context)
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
/// One pixel, for a photo whose pixels nothing looks at.
private func crossPosturePixel() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(alpha: .premultipliedLast)
    )
    guard let image = context?.makeImage() else { preconditionFailure("a one-pixel bitmap always makes an image") }
    return image
}
#endif

/// A sink that bridges none of the lines: every method is defaulted.
private struct CrossPostureQuietSink: AskLogSink {}

/// A session with only the members `AskSession` has no default for.
private struct CrossPostureSession: AskSession {
    func stream(
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?,
        includeSchemaInPrompt: Bool
    ) -> AsyncThrowingStream<AskReplySnapshot, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func plan<Arguments: Generable & Sendable>(
        _ type: Arguments.Type,
        instructions: String,
        prompt: String
    ) async throws -> Arguments {
        throw CancellationError()
    }

    func toolCallCount() async -> Int { 0 }

    func respond<Content: Generable & Sendable>(
        _ type: Content.Type,
        images: [AskImageAttachment],
        prompt: String,
        temperature: Double,
        reasoningLevel: AskReasoningLevel?
    ) async throws -> Content {
        throw CancellationError()
    }
}

/// A seam with only the members `AskModelSeam` has no default for, serving
/// the device's tier with a session that has no model behind it.
private struct CrossPostureSeam: AskModelSeam {
    let status: AskModelStatus

    func tierStates() async -> [AskTierState] {
        [AskTierState(tier: .onDevice, isAvailable: true, speaksLanguage: true)]
    }

    func makeSession(tier: AskTier, tools: [any Tool], instructions: String) async throws -> AskSessionBox? {
        AskSessionBox(session: CrossPostureSession(), tier: tier)
    }

    func noteTransportFailure(on tier: AskTier) async {}

    /// The requirement as the protocol spells it, `nonisolated(nonsending)`
    /// included: copied as written, it conforms in a target without the
    /// feature that makes that the default.
    func withGeneration<T: Sendable>(
        onDevice: Bool,
        _ body: nonisolated(nonsending) @Sendable () async throws -> T
    ) async throws -> T {
        try await body()
    }

    func refreshStatus() async {}
}

extension CrossPostureTests {
    /// A tool's payload merge, written the way a tool writes it: from a
    /// nonisolated async context, over its own envelope, capturing what it
    /// read. The merge's closure crosses into the collector, so its shape is
    /// only proven by a caller that does not share the package's isolation.
    @Test func aToolMergesIntoTheTurnsPayloadWithoutThePosture() async throws {
        let collector = AskCollector<CrossPostureRow>()
        let read = "decades"
        let kept = await collector.mergePayload(as: CrossPostureEnvelope.self) { envelope in
            envelope = CrossPostureEnvelope(parts: (envelope?.parts ?? []) + [read])
        }
        #expect(kept)
        let data = try #require(await collector.turnPayload)
        #expect(try JSONDecoder().decode(CrossPostureEnvelope.self, from: data).parts == ["decades"])
    }

    /// What a host's own eval test builds and reads, synchronously and off any
    /// actor: a scenario, and an outcome's `isGood` and each miss's line.
    @Test func anOutcomesMissesAreReadableWithoutThePosture() {
        let scenario = AskScenario(id: "lend", question: "Can I lend The Peregrine to Sam?", expectsProposal: true)
        var outcome = AskOutcome(id: scenario.id)
        outcome.misses = [.noProposal]
        #expect(scenario.expectsProposal == true)
        #expect(!outcome.isGood)
        #expect(outcome.misses.map(\.line) == ["NO CARD, expected one"])
    }

    /// What an engine of a host's own is handed to resume a saved thread
    /// (`AskAsking.resume(from:)`), built and compared off any actor.
    @Test func aThreadTailIsUsableWithoutThePosture() {
        let tail = AskThreadTail(question: "How many?", answer: "Two.", rowTitles: ["Dune"])
        #expect(tail == AskThreadTail(question: "How many?", answer: "Two.", rowTitles: ["Dune"]))
        #expect(tail.rowTitles == ["Dune"])
    }

    /// What the protocols default, heard by a consumer that writes none of
    /// it: a domain, a sink, a seam and a session with only what has no
    /// default, and an engine warming a session over them.
    @MainActor
    @Test func theDefaultsServeAConsumerThatWritesNone() async {
        let domain = CrossPostureDomain()
        #expect(domain.promptPrefix.isEmpty)
        #expect(!domain.searchPlanInstructions.isEmpty)
        #expect(domain.starters(overview: await domain.overview(), window: 4).isEmpty)
        let dune = CrossPostureRow(id: "Dune")
        let arrival = CrossPostureRow(id: "Arrival")
        #expect(domain.referent(from: AskAnswer(text: "Arrival.", matches: [dune, arrival], tiles: [dune])) == ["Dune"])
        #expect(domain.referent(from: AskAnswer(text: "Try Arrival.", matches: [dune, arrival])) == ["Arrival"])

        let sink = CrossPostureQuietSink()
        sink.turn(AskTurnStats(tier: .onDevice))
        sink.routing("heard by nobody")
        sink.discard(AskDiscard(tier: .onDevice, reason: .empty, text: ""))

        let seam = CrossPostureSeam(status: AskModelStatus())
        await seam.showLimitIncrease()
        #expect(await seam.answerLanguage(for: .onDevice) == nil)

        let session = CrossPostureSession()
        #expect(await session.usage() == nil)
        #expect(await session.contextSize() == nil)
        await session.prewarm(promptPrefix: domain.promptPrefix)
        #expect(await session.feedbackAttachment(sentiment: .positive) == nil)

        let engine = AskEngine(domain: domain, seam: seam, log: sink)
        await engine.prewarm()
        await engine.reset()
    }

    /// A domain that names its types only in its own members' signatures, as
    /// `CrossPostureDomain` does, keeps them: the defaults `AskNoRow` and
    /// `AskNoSearchArguments` don't win over what its `makeTools` and
    /// `search` say, and its own search is the one the protocol calls.
    @Test func aDomainsOwnTypesOutrankTheDefaults() async throws {
        #expect(CrossPostureDomain.Row.self == CrossPostureRow.self)
        #expect(CrossPostureDomain.SearchArguments.self == CrossPostureSearchArguments.self)
        func searched<Domain: AskDomain>(_ domain: Domain, _ arguments: Domain.SearchArguments) async throws -> String {
            try await domain.search(arguments, context: AskToolContext(
                collector: AskCollector<Domain.Row>(), relay: AskActivityRelay(),
                rowLimit: 12, tier: .onDevice, isConversation: true
            ))
        }
        #expect(try await searched(CrossPostureDomain(), CrossPostureSearchArguments(query: "peregrine")) == "peregrine")
    }

    /// When a failure says the tier can be tried again, read off any actor by
    /// a host whose own router hears its sessions' failures.
    @Test func aRetryAfterIsReadableWithoutThePosture() {
        #expect(AskTriage.retryAfter(from: CancellationError()) == nil)
        let reset = Date(timeIntervalSinceReferenceDate: 0)
        let retry = AskRetryAfter(date: reset, isQuota: true)
        #expect(retry.date == reset && retry.isQuota)
    }

    /// Whether an engine keeps a conversation, read off any actor as a host's
    /// own store or test reads it: none after a reset, and one once a thread's
    /// tail is resumed.
    @Test func anEngineSaysWhetherItKeepsAConversationWithoutThePosture() async {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: CrossPostureDomain(), seam: CrossPostureSeam(status: status), log: CrossPostureQuietSink())
        await engine.reset()
        #expect(await !engine.hasKeptConversation)
        await engine.resume(from: [AskThreadTail(question: "How many?", answer: "Two.", rowTitles: ["Dune"])])
        #expect(await engine.hasKeptConversation)
    }

    /// The domain's own search, run as the grounded retry runs it: through a
    /// context a consumer can build, from a nonisolated caller. What it read
    /// lands in the collector, and the finish in its `defer` is counted.
    @Test func aConsumersToolRecordsWhatItReadWithoutThePosture() async throws {
        let collector = AskCollector<CrossPostureRow>()
        let context = AskToolContext(
            collector: collector, relay: AskActivityRelay(),
            rowLimit: 12, tier: .onDevice, isConversation: true
        )
        let reply = try await CrossPostureDomain().search(
            CrossPostureSearchArguments(query: "peregrine"), context: context
        )
        #expect(reply == "peregrine")
        #expect(await collector.rows == [CrossPostureRow(id: "peregrine")])
        #expect(await collector.toolCallCount == 1)
    }

    /// What a host's own session reports and streams, and where a question
    /// came from, built and compared off any actor.
    @Test func aSessionsValuesAreUsableWithoutThePosture() throws {
        let usage = AskUsage(inputTokens: 120, cachedTokens: 100, outputTokens: 30)
        #expect(usage != AskUsage())
        #expect(usage.reasoningTokens == nil)

        let snapshot = AskReplySnapshot(answer: "Two.", questionKind: "count")
        #expect(snapshot == AskReplySnapshot(answer: "Two.", questionKind: "count"))
        #expect(snapshot.tiles == nil)

        let origin = try JSONEncoder().encode(AskOrigin.reroll)
        #expect(try JSONDecoder().decode(AskOrigin.self, from: origin) == .reroll)
        #expect(AskOrigin.standalone.rawValue == "standalone")
        #expect(AskOrigin.prefilled.rawValue == "prefilled")

        // The levels a host's own session maps onto its model's.
        let levels: [AskReasoningLevel] = [.light, .moderate, .deep]
        #expect(levels.map(\.rawValue) == ["light", "moderate", "deep"])
    }

    /// The reply the model fills in, as a host's own session builds it from
    /// generated content, and its schema, read off any actor.
    @Test func aReplyIsBuiltFromGeneratedContentWithoutThePosture() throws {
        _ = AskReply.generationSchema
        let reply = try AskReply(GeneratedContent(properties: [
            "answer": "Two.", "questionKind": "count", "showsEveryMatch": false,
            "tiles": [String](), "followUps": ["Which is older?", "What else?"]
        ]))
        #expect(reply.answer == "Two.")
        #expect(reply.questionKind == "count")
        #expect(reply.followUps.count == 2)
    }

    /// An evaluation's table and its misses, read off any actor, as a host's
    /// own eval test reads them.
    @Test func anEvaluationsTableIsReadWithoutThePosture() {
        var outcome = AskOutcome(id: "count")
        outcome.misses = [.kind(expected: ["count"], got: "lookup"), .tiles(3)]
        #expect(outcome.misses.first == .kind(expected: ["count"], got: "lookup"))
        #expect(outcome.misses.map(\.line) == ["KIND lookup, expected count", "3 TILES, expected none"])
        let table = AskEval<CrossPostureDomain>.table([outcome])
        #expect(table.hasSuffix("0/1 grounded, clean and as expected."))
    }

    /// An evaluation built over an engine of its own, as a host's settings
    /// build one.
    @MainActor
    @Test func anEvaluationIsBuiltWithoutThePosture() {
        let engine = AskEngine(domain: CrossPostureDomain(), seam: CrossPostureSeam(status: AskModelStatus()))
        _ = AskEval(engine: engine)
    }
}

extension CrossPostureTests {
    /// The rest of what `AskDomain` defaults, heard off any actor by a
    /// consumer that writes none of it.
    @Test func theDomainsOtherDefaultsServeAConsumerThatWritesNone() async {
        let domain = CrossPostureDomain()
        #expect(domain.turnDeadline == .seconds(45))
        #expect(domain.questionKinds == AskQuestionKind.default)
        #expect(domain.maxTurns(for: .privateCloud) == 8 && domain.maxTurns(for: .onDevice) == 3)
        #expect(domain.scopeLine(for: "albums") == nil)
        #expect(domain.rerollableKinds.isEmpty)
        let answer = AskAnswer(text: "Dune.", matches: [CrossPostureRow(id: "Dune")], questionKind: AskQuestionKind.pick)
        #expect(!domain.isRerollable(answer, question: "Pick one for tonight"))
        #expect(domain.evidenceScope(from: answer) == nil)
        #expect(!domain.implementsDeterministicAnswer)
        #expect(await domain.deterministicAnswer(for: "How many?") == nil)
        #expect(await domain.photoThumbnail(for: AskQuestionPhoto(label: "A record sleeve", reference: "asset-1")) == nil)
    }

    /// What an engine answers a caller outside the thread, such as a Siri
    /// intent, and what the store asks of it as the screen goes and a verdict
    /// comes in, asked off any actor. The question is empty, so it throws
    /// before any tier is asked.
    @Test func anEnginesOtherCallsAreMadeWithoutThePosture() async {
        let status = await MainActor.run { AskModelStatus() }
        let engine = AskEngine(domain: CrossPostureDomain(), seam: CrossPostureSeam(status: status), log: CrossPostureQuietSink())
        await #expect(throws: AskError.couldNotAnswer) { try await engine.answerOnce("  ") }
        await engine.forgetWarmIfEmpty()
        let verdict = AskFeedback(
            sentiment: .negative, tier: .onDevice, questionKind: nil,
            tilesShown: 0, rowsRead: 0, wasTruncated: false
        )
        #expect(await engine.recordFeedback(verdict, isLatestTurn: true) == nil)
        let events: [AskEngine<CrossPostureDomain>.Event] = [.summarized, .refining]
        #expect(events.first == .summarized)
    }

    /// A scenario's expectations and every field of its outcome, as a host's
    /// own eval test sets and reads them, off any actor.
    @Test func aScenariosExpectationsAndAnOutcomesFieldsAreReadWithoutThePosture() {
        let scenario = AskScenario(
            id: "count", question: "How many?", expectedKinds: [AskQuestionKind.count],
            expectedTitles: ["Dune"], expectsNoTiles: true
        )
        #expect(scenario.expectedKinds == ["count"] && scenario.expectedTitles == ["Dune"] && scenario.expectsNoTiles)
        var outcome = AskOutcome(id: scenario.id)
        outcome.toolCalls = 2
        outcome.milliseconds = 1_400
        outcome.restarts = 1
        outcome.isUngrounded = true
        outcome.invented = ["Emma"]
        outcome.proposed = true
        outcome.misses = [.unexpectedProposal]
        #expect(!outcome.isGood)
        #expect(outcome.toolCalls == 2 && outcome.milliseconds == 1_400 && outcome.restarts == 1)
        #expect(outcome.isUngrounded && outcome.invented == ["Emma"] && outcome.proposed)
        #expect(outcome.misses.map(\.line) == ["CARD, expected none"])
    }

    /// The question kinds a domain lists in `questionKinds` and matches in
    /// `rerollableKinds`, read off any actor.
    @Test func everyQuestionKindIsReadWithoutThePosture() {
        let kinds = [
            AskQuestionKind.totalValue, AskQuestionKind.everyMatch, AskQuestionKind.yesNo,
            AskQuestionKind.wear, AskQuestionKind.pairing, AskQuestionKind.suggestion
        ]
        #expect(Set(kinds).count == 6)
        #expect(Set(kinds).isSubset(of: AskQuestionKind.all))
        #expect(AskQuestionKind.showNoTiles == [AskQuestionKind.count, AskQuestionKind.totalValue, AskQuestionKind.yesNo])
    }

    /// A failure a host's own router hears from its sessions, triaged off any
    /// actor: AskKit's own errors as they are, and a stop as one.
    @Test func aHostsOwnFailureIsTriagedWithoutThePosture() {
        #expect(AskTriage.askError(from: AskError.refused, tier: .onDevice) == .refused)
        #expect(AskTriage.askError(from: CancellationError(), tier: .privateCloud) == .stopped)
    }

    /// What bounds a collector, and the rows and proposal it holds for the
    /// turn, read by a host's own tool or test.
    @Test func aCollectorsBoundsAndReadingsAreReadWithoutThePosture() async {
        #expect(AskCollector<CrossPostureRow>.maxTurnRows == 80)
        #expect(AskCollector<CrossPostureRow>.maxThreadRows == 200)
        #expect(AskCollector<CrossPostureRow>.maxPayloadBytes == 16_384)
        let collector = AskCollector<CrossPostureRow>()
        await collector.record(rows: [CrossPostureRow(id: "Dune")])
        #expect(await collector.groundingRows == [CrossPostureRow(id: "Dune")])
        #expect(await collector.turnProposal == nil)
    }
}

#if os(iOS) || os(macOS) || os(visionOS)
extension CrossPostureTests {
    /// What a host whose own router builds its sessions wraps each one in.
    /// Built and read, never asked: a question here would reach a real model.
    @Test func aHostsOwnSessionIsWrappedWithoutThePosture() async {
        let session = AppleAskSession(
            session: LanguageModelSession(model: SystemLanguageModel.default, instructions: "Answer."),
            contextSize: nil,
            answerCap: AppleAskSession.onDeviceAnswerCap,
            planCap: AppleAskSession.onDevicePlanCap,
            noteFailure: { error in _ = AskTriage.retryAfter(from: error) },
            makePlanner: { instructions in
                LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            }
        )
        #expect(await session.usage() == nil)
        #expect(await session.contextSize() == nil)
        #expect(await session.toolCallCount() == 0)
        _ = AskSessionBox(session: session, tier: .onDevice)
    }

    /// What an app's Ask tab builds, in the order it builds it: the engine over
    /// Apple's seam, the store over the engine, the screen over the store.
    /// Built, not asked: a question here would reach a real model.
    ///
    /// The store is handed its three files under a folder nobody creates, so
    /// nothing it might write lands in Application Support.
    @MainActor
    @Test func aConsumerBuildsAnEngineAStoreAndAScreenWithoutThePosture() {
        let domain = CrossPostureDomain()
        // Both ways an app builds the seam, each with the declaration it must
        // make. Undeclared: this process holds no Private Cloud Compute. The
        // second logs where the domain's own lines go, a generation presumed
        // wedged included.
        _ = AppleModelSeam(status: AskModelStatus(), privateCloudCompute: .undeclared)
        let engine = AskEngine(domain: domain, seam: AppleModelSeam.make(
            privateCloudCompute: .undeclared,
            logSubsystem: domain.brand.logSubsystem
        ))
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "AskKitCrossPosture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directory = domain.brand.appDirectory
        let store = AskConversationStore(
            domain: domain,
            engine: engine,
            thread: AskThreadStore(
                appDirectory: directory, url: folder.appending(path: "thread.json"),
                logSubsystem: domain.brand.logSubsystem
            ),
            archive: AskThreadArchive(
                appDirectory: directory, directory: folder.appending(path: "threads"),
                logSubsystem: domain.brand.logSubsystem
            ),
            feedbackAttachments: AskFeedbackAttachments(
                appDirectory: directory, directory: folder.appending(path: "feedback"),
                logSubsystem: domain.brand.logSubsystem
            )
        )
        // The tiles and the card under an answer, as a host draws them: its
        // own tile in AskKit's bank, its own view in AskKit's card, each
        // reading the turn it is handed.
        let columns = AskTileColumns.adaptive(minimum: 96, maximum: 128, spacing: 10)
        _ = AskScreen(store: store, accent: .blue, spectrum: .aurora)
            .mark { _ in EmptyView() }
            .tiles { turn, rows in
                AskTileGrid(rows, columns: columns, spacing: 10) { row, _ in
                    Text(verbatim: "\(turn.question): \(row.displayTitle)")
                }
            }
            .answerFooter { turn in
                if let answer = turn.answer, answer.payload != nil {
                    AskAnswerCard { Text(verbatim: answer.text) }
                }
            }
        #expect(store.brand.appDirectory == "AskKitCrossPosture")
        #expect(AskAnswerCard<EmptyView>.minimumRadius == 16)

        // The screen with none of the host's views, then each view builder set
        // by its modifier, and a value the builders capture named for the rows
        // to compare. A spectrum of the host's own colors too.
        _ = AskScreen(store: store)
        _ = AskScreen(store: store, spectrum: AskSpectrum([.mint, .teal, .indigo]))
        let isBuilding = false
        _ = AskScreen(store: store)
            .mark { AskDefaultMark(isLit: $0) }
            .tiles { turn, rows, open in
                AskTileGrid(rows, columns: columns, spacing: 10) { row, _ in
                    Button(turn.question) { open?(row.id) }
                        .disabled(open == nil || isBuilding)
                }
            }
            .evidenceDisclosure { turn in Text(verbatim: "\(turn.question)") }
            .answerFooter { _ in AskDefaultTiles(rows: [CrossPostureRow(id: "one")]) }
            .buildersDepend(on: isBuilding)
        // The rest of what a host mounts around it, each from the store.
        _ = AskPrivateCloudCard(store: store)
        _ = EmptyView().askComposerSlot(store, isEnabled: true)
        // A host's own secondary text, in the screen's contrast.
        _ = Text(verbatim: "").askDeemphasizedText()
        // Whether a host's own chips have a conversation to refer to.
        #expect(!store.hasKeptConversation)
        // A Stop of the host's own, the reader's when they tapped it.
        store.stop(byReader: true)
        #if os(macOS)
        _ = AskCommands(store: store)
        #endif
    }

    /// The stage a store reports and the photo waiting in its composer, read
    /// on the main actor and handed to code off it: both are `nonisolated`
    /// `Sendable` values.
    @Test func aStagesAndAPendingPhotosValuesAreReadOffTheMainActor() async {
        let (stage, pending) = await MainActor.run { () -> (AskStage, AskPendingPhoto?) in
            let domain = CrossPosturePhotoDomain()
            let engine = AskEngine(domain: domain, seam: CrossPostureSeam(status: AskModelStatus()))
            let store = AskConversationStore(domain: domain, engine: engine)
            store.attachPhoto(crossPosturePixel(), label: "A record sleeve")
            return (store.stage, store.pendingPhoto)
        }
        #expect(stage.turns.isEmpty)
        #expect(stage == stage)
        #expect(!stage.firstScreenIsKnown)
        #expect(!stage.lastHasText && !stage.lastIsComplete)
        #expect(pending?.photo.label == "A record sleeve")
        #expect(pending?.image.width == 1)
    }

    /// The columns a host lays its own bank out in, worked out off any actor.
    @Test func aBanksColumnsAreWorkedOutFromANonisolatedContext() {
        let fit = AskTileColumns.adaptive(minimum: 100, maximum: 200, spacing: 10).fit(in: 330)
        #expect(fit.count == 3)
        #expect(abs(fit.width - 310.0 / 3) < 0.001)
    }

    /// An engine of a host's own behind the store, written with only what
    /// `AskAsking` requires, and asked off any actor, as the store asks it,
    /// whether it keeps a conversation.
    @Test func anEngineOfAHostsOwnSaysWhetherItKeepsAConversationWithoutThePosture() async {
        let status = await MainActor.run { AskModelStatus() }
        let asker: any AskAsking<CrossPostureRow> = CrossPostureAsker(status: status, keeps: true)
        #expect(await asker.hasKeptConversation)
    }

    /// How long Apple's seam serves a probe from cache and holds a tier after
    /// a transport failure, read off any actor by a host's own diagnostics.
    @Test func theSeamsIntervalsAreReadWithoutThePosture() {
        #expect(AppleModelSeam.reprobeInterval == 60)
        #expect(AppleModelSeam.transportCooldown == 60)
    }

    /// What `AskAsking` defaults, asked off any actor of an engine of a
    /// host's own that writes none of it, as the store asks it: a question
    /// with a photo fails as one no model here takes, a scope goes as the
    /// question would without it, and the rest do nothing.
    @Test func whatAskAskingDefaultsServesAnEngineOfAHostsOwn() async throws {
        let status = await MainActor.run { AskModelStatus() }
        let asker = CrossPostureAsker(status: status, keeps: false)
        await asker.forgetWarmIfEmpty()
        await asker.showLimitIncrease()
        await asker.resume(from: [])
        let verdict = AskFeedback(
            sentiment: .positive, tier: .onDevice, questionKind: nil,
            tilesShown: 0, rowsRead: 0, wasTruncated: false
        )
        #expect(await asker.recordFeedback(verdict, isLatestTurn: true) == nil)
        let photo = AskImageAttachment(label: "A record sleeve", image: crossPosturePixel())
        await #expect(throws: AskError.photosNotSupported) {
            for try await _ in asker.ask("What is this?", origin: .typed, images: [photo]) {}
        }
        for try await _ in asker.ask("How many?", origin: .prefilled, images: [], scope: "albums") {}
    }
}

/// An engine of a host's own with only the members `AskAsking` has no
/// default for, as a scripted one for previews is.
private struct CrossPostureAsker: AskAsking {
    let status: AskModelStatus
    let keeps: Bool

    func ask(_ question: String, origin: AskOrigin) -> AsyncThrowingStream<AskTurnEvent<CrossPostureRow>, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}
    func reset() async {}
    func prewarm() async {}
    func refreshStatus() async {}

    var hasKeptConversation: Bool { keeps }
}
#endif
#endif
