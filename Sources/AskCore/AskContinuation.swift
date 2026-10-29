#if canImport(FoundationModels) && !os(tvOS)

import Foundation

/// One exchange the thread has already had, kept so a session that has to
/// start over can be told what came before it. A host hands an engine the
/// saved thread's newest ones through `AskEngine.resume(from:)`, as AskUI's
/// store does.
///
/// **The row titles are the load-bearing part.** A recap of prose alone leaves
/// "is it still on loan?" and "which of those is on vinyl?" with nothing to
/// resolve *it* and *those* against, and almost every follow-up takes that
/// shape. The tiles the turn put on screen are exactly that list, already
/// collected.
nonisolated public struct AskThreadTail: Sendable, Equatable {
    /// The question, as the model was asked it.
    public let question: String
    /// The answer's prose.
    public let answer: String
    /// The titles of the rows the answer showed as tiles, which a recap lists
    /// as already discussed. The newest exchange's are widened to the
    /// domain's referent as well, by AskUI for a thread read back from disk
    /// and by the engine for its own (`AskConversation.recapTail`).
    public let rowTitles: [String]

    /// An exchange: a question, its answer and the titles of the rows it
    /// showed.
    public init(question: String, answer: String, rowTitles: [String]) {
        self.question = question
        self.answer = answer
        self.rowTitles = rowTitles
    }
}

/// One open thread: the tier it runs on, the session its turns append to, the
/// collector each turn records into, and what has been said.
nonisolated struct AskConversation<Row: AskRow>: Sendable {
    let tier: AskTier
    let box: AskSessionBox
    let collector: AskCollector<Row>
    /// The relay THIS session's tools were built around. It can't be minted per
    /// turn: the tool set is fixed for the session's life, so a fresh relay is
    /// one no tool holds and a follow-up's wait row goes silent.
    let relay: AskActivityRelay
    var turns: Int
    /// Newest last, capped at `AskContinuation.recapDepth`. Each exchange
    /// holds its tiles' titles; `recapTail` widens the newest.
    var tail: [AskThreadTail]
    /// The app searched for the model on this conversation, so it is grounded
    /// for as long as the conversation lives.
    ///
    /// For its whole life, not one turn: the rows the app found sit in this
    /// session's transcript, and its model has already answered once without
    /// searching. A follow-up it answers from those rows, calling no tool and
    /// naming no row the thread has read, would otherwise be discarded as
    /// ungrounded.
    var appRetrieved: Bool
    /// A turn on this session failed, or the deadline gave up on a generation
    /// that may still be writing on it, so its transcript can't be trusted:
    /// the next question starts fresh with the recap rather than building on it.
    var needsFreshSession: Bool
    /// What the last answer was about, as the DOMAIN reads it: tiles for one
    /// domain, tiles or else the rows its prose names for another. A
    /// follow-up's "those" resolves against exactly this list, so it is stored
    /// rather than re-derived from the tail, where the engine records only the
    /// tiles' titles.
    var lastReferent: [String]

    init(
        tier: AskTier,
        box: AskSessionBox,
        collector: AskCollector<Row>,
        relay: AskActivityRelay,
        turns: Int = 0,
        tail: [AskThreadTail] = [],
        appRetrieved: Bool = false,
        needsFreshSession: Bool = false,
        lastReferent: [String] = []
    ) {
        self.tier = tier
        self.box = box
        self.collector = collector
        self.relay = relay
        self.turns = turns
        self.tail = tail
        self.appRetrieved = appRetrieved
        self.needsFreshSession = needsFreshSession
        self.lastReferent = lastReferent
    }

    mutating func remember(_ entry: AskThreadTail) {
        tail.append(entry)
        if tail.count > AskContinuation.recapDepth {
            tail.removeFirst(tail.count - AskContinuation.recapDepth)
        }
    }

    /// The tail as a recap, or a hand-down, is told it: the newest exchange's
    /// titles widened with the last answer's referent, the way AskUI's store
    /// widens the newest exchange of a thread read back from disk. A count or
    /// a yes-or-no shows no tiles, and the rows its prose named are the only
    /// titles it has: kept to the tiles, the recap after a stop, a rollover
    /// or a hand-down would name none of them, where the same thread after a
    /// relaunch names them all.
    var recapTail: [AskThreadTail] {
        guard let newest = tail.last else { return tail }
        return tail.dropLast() + [AskThreadTail(
            question: newest.question, answer: newest.answer,
            rowTitles: AskContinuation.widened(newest.rowTitles, with: lastReferent)
        )]
    }
}

/// The rules a conversation continues, rolls over or is dropped by.
///
/// Pure and static so every one of them is testable without a model: the
/// engine holds the state, and this decides what to do with it.
nonisolated package enum AskContinuation {
    /// How many exchanges the tail holds. Three is what the widest recap can
    /// afford.
    package static let recapDepth = 3

    /// Whether an exchange enters the tail: a model answered it (`tier`), and
    /// the reader saw prose of it, which the thread keeps as its answer. That
    /// is a finished answer, one the deadline cut, and one the reader stopped
    /// after its first words. An answer the domain gave without a model
    /// doesn't enter, nor does a turn that failed, or one stopped before it
    /// drew anything.
    ///
    /// **One rule for the engine and the store.** The engine keeps its own
    /// tail by it, a stopped exchange included, and AskUI's store reads a
    /// restored thread's tail by it (`tail(from:referent:)`), so a follow-up
    /// after a Stop is asked over the same recap whether the app relaunched
    /// in between or not.
    static func entersTail(tier: AskTier?, prose: String) -> Bool {
        tier != nil && !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The newest exchange's row titles widened with what the answer was
    /// about (`AskDomain.referent(from:)`), each once, in that order. A count
    /// or a yes-or-no shows no tiles, and the rows its prose named are the
    /// only titles it has: kept to the tiles, its recap would name none.
    static func widened(_ titles: [String], with referent: [String]) -> [String] {
        var widened = titles
        for title in referent where !widened.contains(title) {
            widened.append(title)
        }
        return widened
    }

    /// What a thread read back from disk said, as the engine is told it
    /// (`AskEngine.resume(from:)`): its last `recapDepth` exchanges that
    /// enter the tail (`entersTail(tier:prose:)`), newest last, each its
    /// question, its answer's prose and its tiles' titles, the newest's
    /// widened with `referent` of its answer, as the engine keeps its own.
    package static func tail<Row: AskRow>(
        from entries: [AskThreadEntry<Row>],
        referent: (AskAnswer<Row>) -> [String]
    ) -> [AskThreadTail] {
        let answered = Array(
            entries
                .compactMap { entry -> (question: String, answer: AskAnswer<Row>)? in
                    guard let answer = entry.answer, entersTail(tier: entry.tier, prose: answer.text) else { return nil }
                    return (entry.question, answer)
                }
                .suffix(recapDepth)
        )
        return answered.enumerated().map { index, exchange in
            let titles = exchange.answer.tiles.map(\.displayTitle)
            return AskThreadTail(
                question: exchange.question, answer: exchange.answer.text,
                rowTitles: index == answered.count - 1 ? widened(titles, with: referent(exchange.answer)) : titles
            )
        }
    }

    /// `tail` with `exchange` as its newest, its titles widened with
    /// `referent`, held to `recapDepth`: a stopped exchange joining a tail
    /// with no kept conversation to remember it.
    static func appending(_ exchange: AskThreadTail, widenedWith referent: [String], to tail: [AskThreadTail]) -> [AskThreadTail] {
        let newest = AskThreadTail(
            question: exchange.question, answer: exchange.answer,
            rowTitles: widened(exchange.rowTitles, with: referent)
        )
        return Array((tail + [newest]).suffix(recapDepth))
    }

    /// Roll a session over before the next turn would pass this share of the
    /// window, rather than waiting for the overflow.
    ///
    /// **Proactive, because the reactive path costs a whole turn.** An overflow
    /// mid-generation throws away everything the model has written, and the
    /// re-ask starts from nothing.
    static let rolloverFraction = 0.75

    /// Whether a kept conversation may carry this question.
    ///
    /// Three conditions, and the tier is the interesting one: the kept tier
    /// must still be the FIRST servable tier, not merely servable. A thread
    /// kept on the device moves back to Private Cloud Compute, with a recap,
    /// on the better model, the moment Private Cloud Compute is back.
    static func shouldContinue(
        keptTier: AskTier,
        servable: [AskTier],
        turns: Int,
        maxTurns: Int,
        needsFreshSession: Bool
    ) -> Bool {
        guard !needsFreshSession else { return false }
        guard servable.first == keptTier else { return false }
        return turns < maxTurns
    }

    /// The prompt a follow-up sends: the question, and the titles the last
    /// answer was about, so "which of those…" has a list behind it rather
    /// than an inference.
    ///
    /// At most twelve titles, the count `onDeviceTurnReserve` allows for. They
    /// are fenced and clamped like any other untrusted text: they came from the
    /// app's own data, but the model wrote the answer they were chosen for.
    static func followUpPrompt(question: String, referentTitles: [String]) -> String {
        var text = ""
        if !referentTitles.isEmpty {
            let list = referentTitles
                .prefix(12)
                .map { AskPrompt.sanitizeForFence(AskPrompt.clamp($0, AskPrompt.shortClamp)) }
                .joined(separator: ", ")
            text += "The answer you just gave was about these: <rows>\(list)</rows>\n"
            text += "A word like \"those\", \"it\" or \"them\" in the next question refers to them.\n"
        }
        text += AskPrompt.fencedQuestion(question)
        return text
    }

    /// The steer "Another pick" sends ahead of the question: the reader wants
    /// something other than what the last answer chose, named so the model can
    /// avoid it rather than guess at it.
    ///
    /// Fenced and clamped like every title a prompt carries: the app's own
    /// data, chosen by a model.
    static func rerollSteer(excluding titles: [String]) -> String {
        guard !titles.isEmpty else {
            return "The reader wants a different pick from the one you just gave. Choose another.\n"
        }
        let list = titles
            .prefix(12)
            .map { AskPrompt.sanitizeForFence(AskPrompt.clamp($0, AskPrompt.shortClamp)) }
            .joined(separator: ", ")
        return "The reader wants a different pick. Do not choose these again: <rows>\(list)</rows>\n"
    }

    /// What a fresh session is told about the thread it is joining: the titles
    /// already discussed, then the last exchanges.
    ///
    /// Not just the last answer: without the reader's questions and the things
    /// under discussion, a thread loses the plot, and on device a rollover
    /// comes every third turn.
    ///
    /// **The row line comes first and on its own**, because it is what a
    /// follow-up actually needs. The budgets are per tier, and they keep a
    /// rollover cheap rather than rare: on device, a session kept longer only
    /// reaches the edge of its window sooner, and an overflow costs the whole
    /// turn.
    static func recap(from tail: [AskThreadTail], tier: AskTier) -> String? {
        guard !tail.isEmpty else { return nil }
        let depth: Int
        let questionLimit: Int
        let answerLimit: Int
        switch tier {
        case .privateCloud: (depth, questionLimit, answerLimit) = (recapDepth, 200, 1200)
        case .onDevice: (depth, questionLimit, answerLimit) = (2, 200, 400)
        }
        let kept = tail.suffix(depth)

        // Every row the thread has been about, newest first, deduped —
        // including ones from exchanges too old to quote, because the title is
        // the referent even when the prose around it is gone.
        var seen = Set<String>()
        let titles = tail.reversed().flatMap(\.rowTitles).filter { seen.insert($0).inserted }

        var text = "Earlier in this conversation.\n"
        if !titles.isEmpty {
            text += "Already discussed: <rows>"
                + titles.prefix(12)
                    .map { AskPrompt.sanitizeForFence(AskPrompt.clamp($0, AskPrompt.shortClamp)) }
                    .joined(separator: ", ")
                + "</rows>\n"
        }
        for entry in kept {
            // The question as the reader saw it, as the engine asks it: a
            // thread read back from disk carries the one they sent, with any
            // tag characters or bidi controls a paste brought along.
            text += "<previous_question>"
                + AskPrompt.sanitizeForFence(AskPrompt.clamp(AskPrompt.droppingInvisibles(entry.question), questionLimit))
                + "</previous_question><previous_answer>"
                + AskPrompt.sanitizeForFence(AskPrompt.clamp(entry.answer, answerLimit))
                + "</previous_answer>\n"
        }
        return text
    }

    /// Whether the next turn should roll the session over before sending.
    ///
    /// Nil `contextSize` or nil `usedTokens` means the tier couldn't say, and
    /// the turn count is the only budget left, which is what `maxTurns` is for.
    static func shouldRollOver(usedTokens: Int?, contextSize: Int?) -> Bool {
        guard let usedTokens, let contextSize, contextSize > 0 else { return false }
        return Double(usedTokens) >= Double(contextSize) * rolloverFraction
    }

    // MARK: - The device's window

    /// The share of the on-device window a turn may END at. The last 15% is
    /// headroom for an answer longer than the ones measured.
    static let onDeviceCeiling = 0.85

    /// What one more on-device follow-up adds at its worst, in tokens: the
    /// follow-up prompt (~220 with twelve referent titles and a clamped
    /// question), two tool calls and their results (~1,200 when one of them
    /// is a twelve-row listing), and the reply (~150–300).
    ///
    /// **Why the 75% rule isn't enough on device.** Measured on a domain with
    /// ten tools: a session's fixed cost is ~3,560 of the 8,192 tokens before
    /// any tool runs (instructions 612, ten tools 1,898, `AskReply`'s schema
    /// 704, or `AskProseReply`'s 192, the first prompt ~350), and three turns
    /// ended at 4,272, 5,061 and 5,908. A turn that starts at 74% passes the
    /// 75% rule and can end past the window, and an overflow throws away
    /// everything the turn wrote.
    /// Private Cloud Compute's 32K window absorbs the same turn in under 6%, so
    /// its rule is the 75% alone.
    static let onDeviceTurnReserve = 1_800

    /// The longest on-device answer, in tokens: a guard against a runaway, not
    /// a length rule. Measured replies are 130–300 tokens; the SDK stops a
    /// response at the cap without throwing, which on a runaway is better than
    /// the overflow it would otherwise reach.
    static let onDeviceAnswerCap = 1_024

    /// The longest on-device planner reply, in tokens. The planner writes a
    /// handful of search arguments.
    static let onDevicePlanCap = 256

    /// Whether the next turn should roll the session over before sending, by
    /// the tier's own window.
    ///
    /// Private Cloud Compute rolls over at three quarters of its window. On
    /// the device the same rule stands, and a session also rolls over when one
    /// more worst-case turn (`onDeviceTurnReserve`) would end past
    /// `onDeviceCeiling`: an early, cheap rollover beats an overflow that costs
    /// the whole turn.
    static func shouldRollOver(usedTokens: Int?, contextSize: Int?, tier: AskTier) -> Bool {
        guard shouldRollOver(usedTokens: usedTokens, contextSize: contextSize) == false else { return true }
        guard tier == .onDevice, let usedTokens, let contextSize, contextSize > 0 else { return false }
        return Double(usedTokens + onDeviceTurnReserve) > Double(contextSize) * onDeviceCeiling
    }
}

#endif
