/// What a streamed turn emits, in order: the tier it runs on, what it is doing
/// as it does it, the rows it reads as it reads them, prose as it is written,
/// then the finished answer.
nonisolated public enum AskTurnEvent<Row: AskRow>: Sendable, Equatable {
    /// The tier this turn runs on, chosen once at its start, and again for
    /// the tier a hand-down moves it to, or for the tier a host's session
    /// runs on where that isn't the one asked for (`AskSessionBox.tier`).
    ///
    /// A Private Cloud Compute whose quota is spent, with no tier below that
    /// can serve, is yielded too: the turn is its, and fails at once as
    /// `AskError.quotaReached`, having asked it nothing.
    case tier(AskTier)
    /// What the turn is doing right now.
    case activity(AskActivity)
    /// Every tool the turn called has returned, so the wait row goes back to
    /// "Thinking…" rather than holding the last tool's phrase while the model
    /// composes.
    ///
    /// Raised by the collector's in-flight count reaching zero and by nothing
    /// else: a relay report raises no idle signal of its own. So a tool's
    /// relay report has to come after its call has finished, as
    /// `AskToolContext.withToolCall(_:_:)` makes it, or this event clears it
    /// at once: `AskToolContext` states the rule.
    case activityEnded
    /// The answer so far. **Only ever yielded for prose the turn will keep**,
    /// so there is never anything to take back. Under a policy that requires
    /// grounding (`AskGroundingPolicy.retrieval`, the default, or `.toolCall`),
    /// that is once the turn is grounded, a follow-up as much as a first
    /// turn: it draws from its first tool call, or from the first snapshot
    /// that names a row the thread has read, which is the same test the
    /// finished answer is kept or discarded by. Under `.notRequired`, which
    /// keeps answers nothing grounded, it is from the first token.
    case partial(String)
    /// Every row this turn's lookups have read so far
    /// (`AskCollector.turnRows`), sent each time the set grows. The wait row
    /// counts them, and a turn the reader stops keeps them as its `matches`.
    /// They aren't the answer's tiles, which only the model chooses.
    case rowsRead([Row])
    /// The turn threw away what it had and started over on `tier`: the app
    /// searching for a model that wouldn't (the grounded retry), the tier
    /// below taking over from one that went out (a hand-down), or a follow-up
    /// that outgrew its conversation's window asked again on a fresh session
    /// (a rollover). A listener clears any prose already on screen, and the
    /// rows the thrown-away attempt had read.
    ///
    /// **The one place drawn prose is taken back.** The grounded retry
    /// follows an attempt that drew nothing: it runs only under
    /// `AskGroundingPolicy.retrieval`, where ungrounded prose never reaches
    /// the screen. A hand-down or a rollover follows one that may have drawn
    /// prose, grounded or not, and it goes too: the question is asked again
    /// from the start, and its answer replaces the turn's whole prose
    /// snapshot by snapshot, so kept, the old prose would only be swapped out
    /// at the new attempt's first words, and a Stop before them would keep
    /// half an answer from an attempt that was thrown away.
    case restarted(AskTier)
    /// The turn started a fresh session with a recap of the thread. That
    /// happens whenever the thread has something to recap and no kept
    /// conversation goes on with it, as after a rollover, a turn that failed,
    /// was stopped or was cut short, a hand-down or a change of tier, or in a
    /// thread read back after a relaunch or opened from the history. AskUI
    /// draws a hairline saying so above the turn
    /// (`AskThreadEntry.summarizedBefore`), rather than recapping in silence.
    case summarized
    /// The domain's refine pass is asking the model again about the answer it
    /// already has, such as a look at photos of the rows it chose
    /// (`AskDomain.refine`). Sent when the pass first asks, and never after
    /// the answer: a pass that only reorders what it has asks nothing and
    /// isn't announced. The prose on screen stays; a failure, or a pass the
    /// turn's deadline ends, keeps the first answer.
    ///
    /// The store records it as the turn's `activity`, under
    /// `AskActivity.refiningKey`, and the default screen draws nothing for
    /// it: its wait row reads `activity` only until the first words, and the
    /// pass runs after them. A host that shows it reads `AskTurn.activity`.
    case refining
    /// The answer the turn ends with: a model's answer, finished or cut short
    /// by the deadline (`AskAnswer.isTruncated`), grounded unless the domain's
    /// policy keeps answers nothing grounded (`AskAnswer.grounding` says
    /// which), or one the domain gave without a model
    /// (`AskDomain.deterministicAnswer(for:)`).
    case answer(AskAnswer<Row>)
}
