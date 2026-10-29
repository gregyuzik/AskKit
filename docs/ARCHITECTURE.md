# AskKit architecture

AskKit gives an app of any kind an Ask screen over a language model. A reader asks in their own words
and gets a short answer: from the app's own data, through the tools the app gives the model, or from the
model alone where the app allows it. A tool can also propose an action, which the app carries out only
once the reader confirms it. Apple's Foundation Models write the answer: Private Cloud Compute when it
can serve, the on-device model when it can't. AskKit is the part every such app would otherwise write
for itself: model routing, grounding, keeping a conversation going, error handling and the screen.

This document is for a developer who adopts AskKit or changes it. It describes behavior and the reasons
for it; the doc comments describe the API. Where this document and the code disagree, the code is right.

1. [The package](#1-the-package)
2. [The life of a turn](#2-the-life-of-a-turn)
3. [The engine](#3-the-engine)
4. [The screen](#4-the-screen)
5. [The house rules](#5-the-house-rules)
6. [Rejected designs](#6-rejected-designs)
7. [Glossary](#7-glossary)

## 1. The package

| Target | What it holds |
|---|---|
| `AskCore` | The engine, the model seam, triage, persistence and the evaluation harness. No UI. |
| `AskUI` | The Ask screen, the conversation store that drives it, and a settings card. Depends on `AskCore`. |
| `AskCoreTests`, `AskUITests` | Swift Testing suites. |
| `AskCrossPostureTests` | Calls the public API, and in a file of its own the SPI, from a target with no concurrency settings. |
| `AskReadmeApproachableTests` | README.md's two samples, `AskCrossPostureTests`' `ReadmeDomain.swift` and `ReadmeAssistantDomain.swift` through symlinks, built and run again under the package's posture, whose main-actor default isolation and `NonisolatedNonsendingByDefault` a host on Xcode's app template has too. |

Both libraries compile for iOS, macOS, visionOS, tvOS and watchOS 27.2, because a host's shared package
may link them on every platform the host ships. Ask itself shows on iOS, macOS and visionOS, the only
platforms AskUI's views compile for. AskCore's Foundation Models half is compiled out on tvOS, and
anything naming `SystemLanguageModel` on watchOS too, which has the framework but no on-device model.
The rest of AskCore builds on all five, so a widget can build an Ask link (`AskLink`) on a platform that
never shows Ask. `.claude/references/platform-gates.md` has the gates, file by file.

**Concurrency posture.** Every target but `AskCrossPostureTests` builds with main-actor default
isolation, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility` and
`ExistentialAny`. A host needn't share that posture, so AskCore's public API spells out its isolation:
value types, protocols and extensions are `nonisolated`, the stateful parts are actors, and the
screen's state is `@MainActor`. `AskCrossPostureTests` has no settings at all, on purpose: it fails to
compile when public API it calls has picked up a main-actor conformance, which no target sharing the
posture can catch (`.claude/references/concurrency.md`).

**Public, SPI and internal.** A host builds its Ask from the public API:
- the domain and its values, the seam, the engine, the store and the screen;
- the views a host draws in the screen's builders (`AskTileGrid` in `AskTileColumns`, `AskAnswerCard`,
  `askArrival`), and those drawn where it has none (`AskDefaultMark`, `AskDefaultTiles`);
- what a tool calls: `AskToolContext.withToolCall(_:_:)`, `AskCollector`, `AskActivityRelay.report(_:)`
  and `AskPrompt`'s clamps;
- what a refine pass calls to clean the follow-ups it writes the engine's way:
  `AskAnswer.cleanedFollowUps(_:)`;
- for a host with more of its own, `AppleAskSession` and `AskTriage.retryAfter(from:)` for a seam over
  its own model router, and `AskAsking` for an engine of its own behind the store.

The pieces `AskScreen` assembles from (the composer, the first screens, the chip rows, the quota
banner, the toolbar's buttons and the jump pill) stay public too, so a host that draws one keeps it.
SPI, marked `@_spi(AskKitInternal)`, is what AskKit drives itself and a host reaches only from its own
tests or a live evaluation, such as `AskCollector.beginTurn()` and `AskPrompt.promptText`, and the
stand-in a preview, the demo or a UI test arranges the screen around (`AskSimulatedFold`). A file that
calls one spells its import `@_spi(AskKitInternal) import AskCore` (or `AskUI`), and only that file
sees it: neither a plain `import` elsewhere in the module nor `@testable import` does. An SPI
declaration keeps its `nonisolated` spelling. Everything else is internal, or `package` where AskUI
alone reads it of AskCore, and AskKit has no third-party dependencies.

**The demo.** `Demo/` is a small library, thirty books, records, tools and clothes behind one search tool
(`DemoDomain`), and, under `-askAssistant`, an assistant with no rows in its place
(`DemoAssistantDomain`), which converts units with one tool, proposes reminders with another and answers
anything else from the model alone. It is built as an iOS, macOS and visionOS app from
`Demo/AskKitDemo.xcodeproj`, with a UI-test bundle. It holds no Private Cloud Compute entitlement and
declares none to its seam, and it is parked besides, so it always answers on device
([Entitlements](#entitlements), [the development park](#the-development-park)).

### What a host supplies

An `AskDomain` is the only type AskKit needs from a host, and three of its members are required:
`brand`, an `AskBrand` holding the host's own copy, the Application Support folder and the log subsystem
every AskKit logger writes under; `makeTools(_:)`, the tools a session offers the model, which may read
the host's data, work something out or propose an action; and
`instructions(tier:isConversation:answerLanguage:)`.

A domain over the reader's own rows gives four more. Its associated types are `Row`, an `AskRow`
(`Codable`, `Sendable`, `Identifiable` and `Equatable`, with a `displayTitle` the model sees in tool
output and writes back when it picks tiles), and `SearchArguments`, the `@Generable` arguments the
grounded retry's planner fills in; `overview()` says what the reader has, by scope; and
`search(_:context:)` is the grounded retry's search through the tool's own code. A domain that names
its own `SearchArguments` has to write `search(_:context:)`, since its default exists only for
`AskNoSearchArguments`.

**Which answers are kept** is the domain's `grounding`, one `AskGroundingPolicy` for its life
([house rule 2](#5-the-house-rules)):
- `.retrieval`, the default: an answer that read nothing is never shown, and a first one gets the
  grounded retry, which is what `SearchArguments` and `search(_:context:)` are for;
- `.toolCall`: the same without the retry, for a domain whose every question is a lookup or an action,
  so its search is never asked;
- `.notRequired`: an answer nothing grounded is kept, and says so, for a domain whose answers needn't
  rest on the reader's data. It records it (`AskAnswer.grounding`), and its evidence line reads "Not
  from this app's data" unless the domain words the line itself.

The default `firstScreenPolicy` follows it: `.ownedLibrary`, which reads an empty overview as nothing to
ask about, under `.retrieval`, and `.openSubject`, the ready first screen with nothing counted, under
the other two.

**A domain whose tools read no rows** names neither type: `Row` is then `AskNoRow`, a stand-in nothing
needs to record, and `SearchArguments` is `AskNoSearchArguments`, which has no fields. Its `overview()`
defaults to `.empty`, and its brand may leave out `nothingToAskCopy`. Under `.retrieval` it sets
`firstScreenPolicy` to `.openSubject`, and it still has the grounded retry: a first answer that calls no
tool asks no planner, since there is nothing to choose, and goes to `search(_:context:)`, whose default
fails the turn as ungrounded. The engine logs such a domain once, as it is built. Under `.toolCall` that
answer fails at once, and under `.notRequired` it is kept.

**What the model writes** is the domain's `replyShape`, one `AskReplyShape` for its life. `.full`, the
default, is `AskReply`: the answer, what kind of question it was, which rows to show as tiles, and the
follow-ups. `.prose` is `AskProseReply`, the answer and the follow-ups alone, for a domain whose answers
never show tiles, such as one without rows: its model spends no window on a kind or a tile choice
([Tiers and the seam](#tiers-and-the-seam)), and invents no tile titles, and its answers show no tiles
whatever rows are behind them.

The rest have defaults, which `AskDomain`'s doc comments give one by one: the prompt's lines and
prefix, starters, the referent, persistence, the question kinds, the deadline, photos, the grounding
policy, the reply shape, the first-screen policy, budgets per tier, the wait row's phrases, the basis and evidence lines, proposals, deterministic
answers and a refine pass. Two are traps: `promptPrefix` must stay byte-stable, because a warm session
caches it, and `promptLines(question:overview:)` is asked only when a question starts a fresh session.

The host wires them together:
- It builds one `AppleModelSeam` (`AppleModelSeam.make(privateCloudCompute:)`, declaring whether the
  app holds the Private Cloud Compute entitlement), one `AskEngine(domain:seam:)` and one
  `AskConversationStore(domain:engine:)`.
- It holds the store for the life of the app, not in a view. A Mac `NavigationSplitView` rebuilds its
  detail on every sidebar change, so a store owned by a view loses the thread, and any turn in flight.
- It shows `AskScreen` with its own mark and tiles, or AskKit's where it has none.
  `AskScreen(store:)` takes the store and the screen's options, and the modifiers (`mark(_:)`,
  `tiles(_:)`, `evidenceDisclosure(_:)`, `answerFooter(_:)`) set the host's views one at a time.
- Where a tile or a hand-off opens, it conforms a class of its own to `AskItemRouter` or
  `AskDraftRouter`, set as `askItemOpener` or `askDraftOpener`.
- On the Mac, it adds `AskCommands` to its scene's `.commands`: New Chat, Send and Stop in the File
  menu, and the newest turn's Copy, Copy answer, Edit & Resend and Ask again.

`Demo/AskKitDemo/App.swift` is the shape to copy.

## 2. The life of a turn

The store runs step 1, the engine (`AskEngine`, an actor) steps 2 to 10, the store and screen step 11.

1. **Asked.** A question starts from the reader typing, tapping a starter or a follow-up, or the host
   prefilling the composer (`AskConversationStore.prefill`). A deep link (`AskLink`) only ever prefills:
   a URL can come from anywhere, so it never sends, and its question loses what draws nothing (tag
   characters, the other invisible format characters, bidi controls) and its line breaks, so the reader
   sends only what the composer showed them. The store appends a turn and calls `ask`, which
   returns an `AsyncThrowingStream` of `AskTurnEvent`s; dropping it cancels the turn.
2. **One turn at a time.** A new question cancels the turn in flight and waits for it to finish: a second
   question is always the newer intent, and two generations on one session throw. Each question takes a
   number before it waits, and one overtaken meanwhile, by a newer question or by the end of its chat,
   stands down rather than cancel the turn the newer question installed. A one-shot `.standalone` turn,
   such as an intent answered through `answerOnce(_:)`, is exempt.
3. **One deadline.** The turn gets one deadline, `turnDeadline` (45 s by default), counted from the
   question. Everything it waits on before its answer shares it: the domain's hooks
   (`deterministicAnswer(for:)`, `overview()`, `promptLines(question:overview:)` and the refine pass),
   the read of the tiers' states, the session builds and the session's own reads (its tool calls, its
   usage and its window), every generation, the grounded retry's planner and search, and a hand-down. A
   hook or a read still running when it passes is abandoned, so one that never returns can't hold the
   turn, or every question after it. An on-device generation the deadline abandons still holds the
   generation gate until it returns, within the holder's 90 s ([the generation
   gate](#the-deadline-and-the-generation-gate)), and the next on-device question waits there inside its
   own deadline.
4. **The question.** It loses what draws nothing, as a link's does, then is trimmed and clamped to 500
   characters, none longer than 16 Unicode scalars, and an empty question fails at once. If the domain
   can answer without a model (`deterministicAnswer(for:)`: small talk, or a starter where nothing can
   serve), that is the whole turn.
5. **The tier.** The engine reads every tier's state once (`AskModelSeam.tierStates()`). A tier is
   servable when it is available, speaks the answer language, has quota left and isn't cooling down
   after a failure. Private Cloud Compute is listed first, so it serves whenever it can. With nothing
   servable, a Private Cloud Compute held off only by its cooldown takes the turn all the same, since
   the outage that cooled it was a turn's error, which Try Again retries ([house rule
   1](#5-the-house-rules)). One whose quota is spent is the turn's too, and asked nothing: the turn fails
   at once as `AskError.quotaReached`, with the reset date the mirror holds, since until then every
   request would fail the same way and spend one. Otherwise the turn fails with the reason
   (`AskError.modelUnavailable`). The first event is `.tier`, the spent tier's included.
6. **The session.**
   - **Continuing.** The question continues the thread's kept conversation when that conversation is on
     this tier, under the domain's turn limit, not flagged for a fresh session and not due to roll over.
     The prompt is then a line for each photo, the scope line, "Another pick"'s steer when rerolling,
     the referent ("The answer you just gave was about these: …") when the last answer named rows, and
     the fenced question. The domain's `promptLines` aren't sent again.
   - **Fresh.** Otherwise the question starts a fresh session: a prewarmed one on the same tier under
     300 s old, or one built now. The prompt is the domain's `promptPrefix`, a recap when the thread has
     a tail (reported as `.summarized`), the domain's `promptLines`, the scope line, the steer when
     rerolling, a line for each photo, and the question fenced in `<user_request>`.
7. **Streaming.** The model streams an `AskReply`, whose fields come in a load-bearing order: `answer`
   first, so the prose can stream; `questionKind` before the tile choice it drives; then
   `showsEveryMatch` and `tiles`; and `followUps` last. Under `.prose` it streams an `AskProseReply`,
   the same `answer` and `followUps` with nothing between them.
   - The domain's tools run as the model calls them. Each call's work runs in
     `AskToolContext.withToolCall(_:_:)`, which notes the call with the session's `AskCollector`,
     finishes it however the work ends, and only then hands the phrase the work returns to
     `AskActivityRelay`, in the order `AskToolContext` gives. Inside it, a tool that reads rows records
     them in the collector, and one that proposes an action records the proposal. The wait row shows
     the reports (`.activity`) and counts the rows (`.rowsRead`), where there are any.
   - Prose reaches the screen as `.partial` events, and only prose the turn will keep. Under
     `.retrieval` and `.toolCall` that is once the turn is grounded: the model called a tool, the app
     searched for it (the grounded retry), or, on a follow-up, the turn read rows or the prose names a
     row the thread has already read, so prose that could be discarded is never drawn. Under
     `.notRequired`, which discards nothing for want of grounding, it is from the first token.
8. **The grounding verdict.** Grounded is judged by that one test under every policy, and what becomes
   of a stream that ends ungrounded is the domain's `grounding`:
   - **`.retrieval`**, the default. On a fresh session it gets the grounded retry: the stream reports
     `.restarted` on the same tier, the model fills in the domain's `SearchArguments` with no tools on
     offer, so its only possible reply is a search, the app runs `AskDomain.search`, and the question is
     asked again with the rows fenced in `<tool_result>` as data. `AskNoSearchArguments` has nothing to
     fill in, so no planner is asked, and the search runs with no arguments. The conversation counts as
     retrieved by the app from then on. An ungrounded follow-up on a kept conversation fails with
     coaching.
   - **`.toolCall`**: the same without the retry, so an ungrounded first answer fails with coaching at
     once, with no planner and no second generation.
   - **`.notRequired`**: it is kept. No turn fails as ungrounded.

   The answer records what grounded it: a tool call, the app's search, the thread's rows on a follow-up,
   or nothing (`AskAnswer.grounding`).
9. **The answer.** The reply becomes an `AskAnswer`. Its prose loses headings and bullets, its question
   kind is normalized to the domain's vocabulary, and its follow-ups are cleaned: made plain text, their
   Markdown read as the screen reads the prose's and what draws nothing dropped as from a link's question,
   since a chip shows its text as it is and a tap asks it, then kept only as one line of at most 80
   characters, without repeats, two at most. Its tiles are rows
   the turn or the thread read, so an answer over none has none. They are at most 24 rows, none for a
   count, a total or a yes-or-no, and otherwise chosen in this order:
   1. when the model says the answer is every match (`showsEveryMatch`), the rows this turn read; a
      follow-up that read nothing has no set to show whole, so it never gets this;
   2. the rows the model's titles resolve to, in its order: exact before near, this turn's rows before
      the thread's, and of the near ones the row sharing the most of the title;
   3. when none resolve, the rows its prose names, among this turn's rows (the thread's, when it read
      none).

   Under `.prose` the model chose nothing, so the kind is `other` and there are no tiles, not even the
   rows the prose names.

   An answer with tiles gets the domain's basis line, if it writes one, and a proposal or payload a
   tool recorded rides along. A domain's refine pass then runs on the same session, within the
   deadline: the stream reports `.refining` when the pass first asks the model, and the store records
   it as the turn's activity (`AskActivity.refiningKey`). A failure or a timeout keeps the first
   answer, and a refined one is cleaned and cut the same way, and keeps the first answer's payload,
   proposal and grounding where it brings none of its own. The stream ends with `.answer`, and
   nothing follows it: the mirror's refresh runs beside the turn, not inside it.
10. **Failures.** Any failure is triaged into an `AskError`, never shown as the SDK's text
    ([Triage](#triage)), and a Private Cloud Compute outage is handed down once ([The
    hand-down](#the-hand-down)). If the deadline passes while prose the policy keeps is on screen, that
    prose becomes the answer, flagged as truncated, keeping the model's tiles and basis line only when the
    model had begun its follow-ups, which it writes after them. Otherwise the turn fails.
11. **Reveal and persistence.** The store applies each event to its `AskTurn`, and the screen draws the
    prose in as it arrives (the reveal), then the answer's other pieces in waves. On `.restarted` the
    store clears what the thrown-away attempt left (`AskTurnEvent.restarted`, house rule 5), so a Stop
    before the new attempt's first words keeps nothing, and the turn says the reader stopped it. When
    the turn ends, VoiceOver hears the ending, and the store writes the thread if the domain keeps it.

## 3. The engine

### Tiers and the seam

`AskTier` has two cases: `.privateCloud`, the larger model and the only one that reads photos, with a
32,768-token window and a daily quota, and `.onDevice`, with an 8,192-token window. A session reads its
window at runtime.

`AskModelSeam` is the one owner of the process's model facts: which tiers can serve and why not,
building sessions, the cooldown after a transport failure, quota holds, the generation gate, and the
mirror (`AskModelStatus`) that the screen reads. `AppleModelSeam` implements it on Foundation Models, and
tests use scripted sessions; the engine never names `LanguageModelSession`.

**One seam per process.** A host that already routes its own model calls bridges them to this
protocol, or the process runs two cooldowns and two generation gates against one on-device model; a
second `AppleModelSeam` alive in the process is logged as a fault. The router's sessions reach the
engine wrapped in `AppleAskSession`, whose `noteFailure` hands the router each raw failure, and
`AskTriage.retryAfter(from:)` reads a quota's or a rate limit's reset off it. A router that answers a
request for one tier with another's session says so in the box (`AskSessionBox.tier`): the engine runs
the turn on the box's tier, its generation gate, reasoning level, caption and photos included, triages
what that session's generations throw as that tier's, and logs the swap. So an on-device session
answering for Private Cloud Compute is sent no photo, and what it throws cools nothing.

`AppleModelSeam` is the only place the Private Cloud Compute model is constructed, and it sends it
nothing unless the host declared the entitlement, the build doesn't prove it absent and the process isn't
parked. It reads availability in one place, serving a transient answer from cache for 60 s ("available"
and "device not eligible" are final for the process), and learns it is offline from `NWPathMonitor`,
which reads as connected until it has reported. It asks the tiers about the app's language, the main
bundle's first preferred localization, not the system's: an app that doesn't ship the system's language
runs in another, and a tier that couldn't write the system's would take Ask down. English skips Private
Cloud Compute's locale probe; a probe that throws or runs past its bound is remembered as no answer for
60 s, and the tier is read as speaking the language, which is named to the model only once a probe
confirmed it. The on-device model's answer about the language is kept until its availability changes,
except a no given while the model wasn't available, as while its assets download, which is asked again.
The locale probe and the context-window read are each shared by overlapping callers, kept once answered,
and bounded at 3 s, so a stalled network can't hold the turn.

After a failure, a transport failure cools Private Cloud Compute for 60 s, a rate limit that names its
reset cools it until then, and a spent quota holds it until the day's reset; no hold is ever shortened,
and none runs past a day, whatever date the tier gave. The holds and the availability cache run on the
monotonic clock, so a change to the device's clock moves none of them.
Sessions are built off the main actor, with on-device replies capped at 1,024 tokens and the grounded
retry's plan at 256. `AskSession.usage()` is the newest response's usage, not the session's running total
([rollover](#continuation-tail-referent-recap-rollover)), and tool calls are counted off the transcript.

**The reply's shape.** The engine streams every generation through `AskSession`'s shaped stream, in the
domain's `replyShape`, the same on every turn of a session, since a follow-up isn't sent the schema
again. `AppleAskSession` streams `AskReply` for `.full` and `AskProseReply` for `.prose`: two static
`@Generable` schemas, whose `answer` and `followUps` guides are one text. A session built outside AskKit
that doesn't write the shaped stream gets a default that streams the full reply for either shape, and of
a prose turn the engine reads only the answer and the follow-ups, so its answers are the same, without
the saving. Counted by the on-device model (`SystemLanguageModel.tokenCount(for:)`), `AskReply`'s schema
is 704 tokens and `AskProseReply`'s 192, so a prose session's first turn has 512 more of the 8,192.

### Entitlements

A Private Cloud Compute request from a process without `com.apple.developer.private-cloud-compute` is not
an error but a fatal trap ("Missing entitlement"), and reading the model's availability proves nothing,
since an unentitled process reads `.available`. So the host declares the entitlement: `AppleModelSeam`
takes `privateCloudCompute: .declared` or `.undeclared`, in its initializer and in `make`, with no
default, so a host that forgets fails to compile rather than quietly answering on device or trapping.
Where the seam won't send, the tier reads `.notEntitled`, and the seam logs why, once.

`AskProcessEntitlements` reads what the running build carries, never the project's entitlements file:
exactly on macOS (its own `SecTask`) and in a simulator build (the `__TEXT,__entitlements` section), and
on a device from the embedded provisioning profile, which proves the key absent when it doesn't grant
it. App Store and TestFlight distribution strip the profile, so a shipped build has only the declaration
to go on. An exact read of absent outranks a declaration; where nothing can be read the declaration
decides, so a host that declares an entitlement its app doesn't hold traps on its first request. An
undeclared entitlement is never used, whatever the build carries.

### The development park

The daily Private Cloud Compute quota is per iCloud account, and every development run spends the
developer's own. So `AskDevelopmentPark` keeps development builds off the tier, checking in order for:
1. a test host (XCTest's environment keys);
2. a `swift test` runner (`swiftpm-testing-helper` or `xctest`, known by name);
3. a Debug build;
4. a simulator, in any configuration;
5. a development-signed binary (`get-task-allow`).

A parked process sends Private Cloud Compute nothing: no session, prewarm, locale probe or context-size
read. The tier reads `.notEntitled`, which the settings card words as "isn't enabled in this build",
and the seam logs why, once. TestFlight and App Store builds are never parked. A run opts back in with
`ASK_LIVE_PCC=1` in the environment, the launch argument `-ASK_LIVE_PCC YES`, or the host's own flag
through `AskDevelopmentPark.setAppOptIn(_:)`. The launch argument is read from the argument domain
alone ([Rejected designs](#6-rejected-designs) says why).

### Private Cloud Compute's context gate

A request from a process outside an app's context, such as a command-line tool or a test runner, fails
every time, within milliseconds, with `LanguageModelError` −1 wrapping `ModelManagerError 1001`: not rate
limiting, and not cured by the entitlement. `AskTriage` knows it by its domain and code, walking every
error underneath (the one and the several, four levels down and sixteen errors at most), and reads it as
the tier being unreachable, on Private Cloud Compute alone: on device the same error is an ordinary
fault, since the gate stands in front of the other tier. `.claude/references/pcc.md` explains how to
measure Private Cloud Compute despite it.

### The hand-down

A failure is a tier outage (`askIsTierOutage`) when it triages to `.privateCloudUnreachable` (a network
failure, the service unavailable, a rate limit, a timeout, being offline, or the context gate) or to
`.quotaReached`. An outage on Private Cloud Compute hands the turn down once, to the next servable tier:
- **Only an unreachable tier cools.** A spent quota is no network fault, and the tier's state already
  says it is spent until its reset, so a quota hand-down cools nothing. The cooldown and the mirror's
  refresh run beside the turn, in one task so the cooldown lands first: both can wait on the tier that
  just went out, and a turn waiting on them would hold back the very answer the hand-down is for. The
  tier caption names the fallback from the stream's `.tier` event, so it doesn't wait on the mirror.
- **The question starts a new conversation.** A session is bound to its model, so the conversation can't
  move with the turn: the question is asked on the fallback as the first of a new conversation, carrying
  the thread's tail, so a handed-down follow-up or "Another pick" still has the last exchanges.

With nothing to hand down to, the outage is the turn's error, and Try Again retries it: on Private Cloud
Compute, which takes the turn though it is cooling, since nothing else can, while a spent quota is asked
nothing until its reset, and the turn fails at once as the quota (§2, step 5). **Nor with no time to
answer:** a turn that has drawn prose hands down only while at least 10 s of its deadline are left
(`AskEngine.restartFloor`), since a fallback with less is likelier to draw nothing than something, and
the reader would lose the prose for an empty turn. Below that the outage is the turn's error, rendered
under the prose, and the tier still cools. A turn that has drawn nothing hands down however little is
left. The 10 s is bounded by measurements (Private Cloud Compute's first word at 5 to 20 s, an on-device
answer at about 13 s whole), not one itself. Nothing is handed down twice. A refusal, an overflowing
context or an ungrounded answer is never handed down, since the other model would reach the same verdict,
only later. Nor is a failure of the host's own search (`AskDomain.search`): it fails the turn as
`.model(tag:)` and cools nothing, since a host's network error isn't Private Cloud Compute's.

### Continuation: tail, referent, recap, rollover

**Tail and referent.** A kept conversation remembers its **tail**: the last three exchanges, each a
question, its answer and the titles of the rows it showed. An exchange enters it when a model answered it
and the reader saw prose of it, which the thread keeps as its answer: a finished answer, one the deadline
cut, and one the reader stopped after its first words, whose prose and the rows it had read are the
answer the store keeps. An answer the domain gave without a model doesn't, nor a turn that failed or
was stopped before it drew anything. The engine and the store read it by one rule
(`AskContinuation.entersTail(tier:prose:)`), so a follow-up after a Stop has the same recap whether the
app relaunched in between or not. The titles carry meaning from turn to turn,
so the newest exchange's are widened with the answer's referent, as the store widens a thread read back
from disk: a count or a yes-or-no shows no tiles, and the rows its prose named are the only titles it
has. After each answer, `referent(from:)` names the rows it was about, and the next follow-up's prompt
names them, so "those" or "it" resolves against them. "Another pick" adds a steer naming the rows the
last answer chose ("Do not choose these again"), and runs at temperature 0.8 rather than 0.4.

**The recap.** A kept conversation ends when it rolls over, when a turn on it fails, is stopped or is
abandoned by the deadline, when a turn is handed down, and when the app relaunches. The next question
then starts a fresh session that opens with a **recap**: "Already discussed:" with up to twelve titles,
newest first, including exchanges too old to quote, then the last exchanges, fenced as
`<previous_question>` and `<previous_answer>`:

| | Exchanges | Question | Answer |
|---|---|---|---|
| Private Cloud Compute | 3 | 200 characters | 1,200 characters |
| On device | 2 | 200 characters | 400 characters |

On New Chat the engine drops the conversation, the warm session and the tail, a question waiting for the
old chat's turn stands down, and a turn from the old chat writes nothing into the new one. A thread
restored from disk hands the engine its last three exchanges by the same rule as the tail's.

**Rollover.** A kept conversation rolls over into a fresh session with a recap when it reaches the
domain's turn limit (8 on Private Cloud Compute and 3 on device by default), when the last response used
75% of the window, or, on device, when the last response plus a 1,800-token reserve for the next turn
would pass 85% of it. A session that reports no window size or no usage rolls over on the turn limit
alone. A follow-up that overflows the window is asked again at once, once, on a fresh session with a
recap, and the stream reports `.restarted` on the same tier, its prose thrown away, unless it had drawn
prose with less than the hand-down's 10 s of the deadline left: then the overflow is the turn's error,
under the prose, and the next question starts the fresh session.

The on-device numbers are measured. A session's fixed cost is about 3,560 of its 8,192 tokens before any
tool runs: instructions 612, ten tools 1,898, the reply schema 704 (192 for the prose one) and a first
prompt about 350. Three measured turns ended at 4,272, 5,061 and 5,908 tokens, and replies ran 130 to
300 tokens, under the 1,024 cap. The same turn takes under 6% of Private Cloud Compute's window.

**Why the newest response's usage.** The session's own counter is a running total, since each request's
input is the whole transcript so far. Measured on device, four short turns read 70, 160, 270 and 400
input tokens while the transcript counted 72, 92, 112 and 132: set against the window, the running
total rolled conversations over long before they filled.

### The deadline and the generation gate

`AskDeadline` races work against a wall clock, and when the deadline wins it abandons the work rather
than wait for it to notice cancellation: the work under these budgets, a model call that hangs or a
host's hook that never returns, is exactly the work that can't notice. An abandoned Private Cloud Compute
generation keeps spending quota until it finishes on Apple's side, and its session is never continued.

`AskGenerationGate.shared` serializes on-device generation across the process, first in, first out,
because overlapping on-device generations race inside the framework and can trip an internal trap.
Private Cloud Compute passes straight through, a waiter whose task is cancelled leaves the queue, a
holder past 90 s is presumed wedged and passed over, and the gate isn't re-entrant. A holder lets the
next generation in only once the generations it started have returned too: an `AppleAskSession` stream
generates in a task of its own, which a stopped or abandoned turn lets go of while `streamResponse` is
still unwinding, so the gate waits for that task, within the holder's 90 s
(`AskGenerationProducers`).

**One gate per process.** A host that generates on device outside Ask goes through
`AskGenerationGate.shared` too, `AppleModelSeam`'s default. A gate built of its own
(`AskGenerationGate(logSubsystem:)`) serializes only what runs through it, so a generation there can
run beside one at `shared`. A host never builds one to log the gate under its brand's subsystem: at
`shared` too, an `AppleModelSeam`'s generation presumed wedged is logged under the seam's
`logSubsystem`, beside its other lines (category `gate`, at error level). A host's own generation
through `AskGenerationGate.run` is logged under the gate's subsystem, which at `shared` is the app's
bundle identifier.

### Triage

`AskTriage` turns each failure into an `AskError`, by the tier whose session raised it, or the tier
asked for where no session was built yet:

| Error | `AskError` |
|---|---|
| An `AskError`, bare or inside a tool's `ToolCallError` | itself |
| A cancellation, bare or inside a `ToolCallError` | `.stopped` |
| Private Cloud Compute's quota limit | `.quotaReached(resetDate:)` |
| On Private Cloud Compute: a network failure, the service unavailable, a rate limit, a timeout, a lost connection, or the context gate | `.privateCloudUnreachable` |
| A missing on-device model asset | `.modelUnavailable(.modelNotReady)` |
| An unsupported language | `.modelUnavailable(.languageNotSupported)` |
| A guardrail violation or a refusal | `.refused` |
| An exceeded context | `.contextTooLarge` |
| A timeout on device, or concurrent requests | `.couldNotAnswer` |
| A rate limit on device | `.model(tag:)` |

Anything else becomes `.model(tag:)`. The tag is the error's case name, read by reflection, or its
domain and code where it has no name, never the SDK's message, which can quote the reader's data; a
tool's failure is tagged by what the tool threw, inside `ToolCallError(…)`, and no tag runs past 60
characters. A session or an engine without photo support fails a question that carries a photo with
`.photosNotSupported`, which isn't retryable and isn't a tier outage, rather than answer as though it
had seen the photo. `AskError`'s lines live in AskCore's catalog: a failed turn stores its case beside
its sentence, the line is rendered again from the case in the reader's current language, and a case
that no longer decodes falls back to the stored sentence. A reason no tier could serve that this build has
no case for decodes as `AskUnavailability.unknown`, and reads as its line.

### Prompts and fences

AskKit fences what it composes, in five tags held in one list that `AskPrompt`'s sanitizer reads:
`user_request`, `rows`, `previous_question`, `previous_answer` and `tool_result`.
- **The question** is clamped to 500 characters, none longer than 16 Unicode scalars (the clamp counts
  characters, and one character can stack any number of combining marks), redacted, neutered and fenced
  in `<user_request>`. Thread titles are clamped to 60 characters, flattened, redacted and neutered,
  and so is a photo's label, fenced in `<rows>` as the titles in a recap are.
- **Redacting** (`AskPrompt.sanitizeForFence(_:)`) turns each of AskKit's fence tags, opening or closing,
  into `[redacted]` in any spelling that compatibility decomposition (NFKD) maps to the tag once marks
  are dropped: any case, whitespace or attributes; a combining mark or a format character beside a
  bracket or inside the name; punctuation after the name; the fullwidth, small and negated brackets
  (`＜ ＞`, `﹤ ﹥`, `≮ ≯`); and letter forms such as mathematical, circled, ligature and precomposed
  letters. Every other bracket stays. That is the whole of its reading: a letter of another script that
  only looks Latin (Cyrillic `о`) and a slash that only looks like one (`⁄`, `∕`) normalize to no
  ASCII, so a tag spelled with one stays as written.
- **Neutering** (`AskPrompt.neuteringTags(_:)`) swaps ASCII angle brackets for `‹ ›`, so no tag can be
  spelled with them.

**Tool output is untrusted.** What a tool returns reaches the model as it stands. Rows it returns are the
reader's own data, so it shows at most `context.rowLimit` of them, and every field it returns, a row's or
not, goes through `AskPrompt.clamp(_:_:)`, with `shortClamp` (60) or `longClamp` (220), as the demo's
`DemoSearch.render` does. `clamp` swaps the angle brackets and flattens, then redacts, caps each
character's scalars and trims until a pass changes nothing; past the limit it cuts and does the same
again, until what is left fits, and drops a last character that would join the "…" it adds. So clamping
twice changes nothing. A tool whose line breaks carry its layout can't clamp, and redacts with
`sanitizeForFence(_:)` as well as neutering: the bracket swap alone leaves a tag in other brackets, with
its name in ASCII or in letters that normalize to it. Tool output takes no fence of its own and uses none
of AskKit's tag names: in the grounded retry the engine fences the search's output in `<tool_result>` and
redacts every AskKit tag inside, a wrapper's included.

The domain's `promptLines(question:overview:)` and `refine` are handed the reader's question clamped,
not redacted, so a line that quotes it is the host's to clamp. The rendered answer loses every link and
image URL the markdown parse produced: the model writes a link's label and its destination, so a link
would be a hidden tap target inside trusted app chrome.

### Persistence and history

A domain whose `persistence` is `.thread` (the default) keeps the thread in
`Application Support/<appDirectory>/ask-thread.json`, through `AskThreadStore`:
- **Cap.** At most 50 turns are kept, oldest dropped.
- **Writes.** They are atomic and excluded from backup, and a write whose file the system won't
  exclude counts as failed. They use complete file protection except on a Mac, natively, as a Mac
  Catalyst build or as an iPhone or iPad app there, where they keep the system's default class,
  `CompleteUntilFirstUserAuthentication`. On macOS 27.2 complete protection fails every write while
  the Mac is locked, sandboxed or not, and the Mac build has no moment to try a refused write again,
  as iOS has when protected data comes back, so every turn written then would be lost
  (`AskStoredFile`). They happen off the main actor after each turn. No file past 64 MiB is written or
  read. Every write and delete says whether it took, and a caller whose write didn't keeps every other
  copy of what it was writing.
- **Decoding.** Every entry decodes field by field with defaults, and a load salvages what it can entry
  by entry. A row that no longer decodes costs its answer that row, never the turn, and the read logs
  how many went.
- **Never written over.** The store writes back only the turns it was handed, so a thread read in part
  is first kept whole beside the thread as `ask-thread-original-<id>.json`, and a launch that reads all
  of it puts the rest back into its chat. If the original can't be kept, the thread is unreadable
  rather than cut down by the next save.
- **An unreadable file** is one that is not a thread, none of whose turns decode, or one past 64 MiB. It
  reads as unreadable, never as empty, which would look like a fresh install and let the next answer
  write a one-turn thread over it. It is set aside beside the thread as
  `ask-thread-unreadable-<id>.json`, never overwritten, and the screen says so. A launch that can read it
  files it with the earlier chats.
- **A file that couldn't be read at all**, as on a locked device, stays in place, and nothing is written
  over it until it reads. It is read again as protected data comes back and as the screen does, and its
  turns go above any asked meanwhile. Until then New Chat sets it aside and Delete All Chats deletes it,
  and the turns asked meanwhile are kept in a provisional filing: off the list while on screen, counted
  by no cap and taken for no chat's earlier filing, it goes once they are written as the thread.

New Chat files the finished turns into `AskThreadArchive`:
- one file per chat under `threads/`, plus an index;
- at most 50 chats, the oldest going first, never the chat just filed;
- the chat files are the record, and every read of the index adds any chat file it doesn't name;
- a filing it can't read whole is never replaced: the chat is filed beside it;
- New Chat and an open file the chat on screen in one write, which takes a provisional filing's place.

The History button lists these chats, can open one, and can delete one or all.

**One chat in two places is joined.** A New Chat whose clear failed, or an open cut short, leaves the
chat both in the thread and in a filing. A thread read at launch or read again is joined with a filing
of the same chat, and so is the chat on screen when that filing is opened: every turn either copy holds,
in the order asked, but a failed turn the other copy asked again, and each turn both hold keeps what
either settled, such as a proposal's outcome or a verdict (a perform still out counts as further than a
failure, which may be the attempt before the reader confirmed again). The join is written as the thread, and the
filing goes once that write took and every one of its turns decoded.

**The only copy is never what gets deleted.**
- New Chat clears the thread only once the chat is filed, and a clear that fails then is owed, as Delete
  All Chats' deletes are. If the archive refuses the chat (a locked device, a full disk), it is written
  as the thread and set aside, for the next launch to file; where it can't be set aside, the thread stays
  as the chat's last copy and nothing is written over it until it can be moved aside, so an unfiled chat
  also blocks opening an earlier one, and the turns asked meanwhile go into a provisional filing, as
  beside a thread that couldn't be read. A chat it can write nowhere waits in memory to be filed.
- Opening an earlier chat files the one on screen first, and does nothing if that fails. The chat it
  opens comes off the list only once it is written as the thread and every one of its turns decoded;
  otherwise its filing stays.
- A save the disk refuses is tried again as protected data comes back and as the screen does.
- Delete All Chats outranks that rule: what the reader deletes is deleted. What the disk won't delete
  is owed and tried again, and a New Chat deletes it too. The archive keeps a chat whose file won't go
  off the list, and tries again. What is owed lives in memory: a thread or a set-aside file that never
  goes comes back on a later launch, the thread as the chat on screen and the file filed with the
  earlier chats.
  - **The retry deletes by name.** It removes the set-aside files that were there when Delete All Chats
    ran and no other, so a chat a later New Chat set aside (the reader's chat, waiting for a launch to
    file it) is spared. A folder that won't list owes every file that was in it, never none: the retry
    lists it again, and spares those set aside since.
  - **Nothing owed outlives the process.** A marker saying what is owed would have to outlive the
    failure that blocked the write, and a marker file in the same folder fails under the same lock,
    permission or full disk. Kept anywhere else, such as the host's defaults, it would be storage of
    AskKit's own outside its folder, which AskKit doesn't keep. So a chat waiting in memory to be filed
    is lost to an app quit first.

`.perLaunch` keeps the thread for the process only, and removes the feedback attachments the launch
before left.

### Proposals

A tool may offer to do something rather than just read (`AskProposal`): the model proposes, the reader
confirms, the app performs. The tool records the proposal with the collector and returns
`AskProposal.modelReceipt`, which tells the model nothing has happened yet. The answer carries it to a
card under it, in the host's words, never the model's words about it: written from the row it acts on,
or, with no row behind it, such as a reminder, showing what it will keep as it will keep it, the model's
reading of the request clamped inside the host's own words. The button's label is the host's alone. Only
the reader's tap reaches `AskDomain.perform(_:)`. A `.handOff` proposal opens the host's own editor
instead, through the `askDraftOpener` environment value, an `AskDraftOpenAction` over the host's
`AskDraftRouter`: its tool returns `AskProposal.handOffReceipt`, `perform` is never called, and with no
opener the card's action is disabled. (A hand-off has nothing to do with the hand-down between tiers.) A
standalone turn has no card to confirm on, so a domain leaves proposing tools out of it.

A proposal is carried out at most once for each yes. The reader's yes is saved with the turn
(`AskProposalOutcome.performing`), and `perform` is called only once that write has landed. A yes the
disk refuses, or whose chat ends before it is saved (New Chat, Delete All Chats or an earlier chat
opening at the same moment), is not carried out, and the card says it couldn't be done, as it does for a
perform that failed, offering the action again on the newest turn. A thread kept for the process only
saves nothing first, since no relaunch reads it back. `perform` runs off the main actor, and nothing
waits for it: New Chat and an earlier chat opening go ahead while it runs, so a hook that never returns
holds up no chat. What came of it is written onto the turn wherever the turn is when `perform` returns:
on screen, read back in its chat opened again (which shows the card carrying it out until then), or in
the filing of a chat that has ended. A turn is known there by its question and when it was asked, as a
join knows one, since a turn read back gets an identity of its own. A card read back with the yes still
out where nothing in the process is carrying it out, as after an app quit, takes no tap and draws the
proposal alone: what came of it is unknown, and confirmed again it could be done twice. So does one whose
outcome this build can't decode, such as a case a later AskKit wrote.

### Evaluation and diagnostics

`AskEval` runs `AskScenario`s through a real engine and reports each `AskOutcome`. A scenario's
expectations are shapes, never prose: the question kinds, titles the answer should name, no tiles, a
proposal, whether something grounded it (`expectsGrounding`: true for a question a tool should answer,
false for one a `.notRequired` domain should answer from the conversation alone). An outcome's `invented` lists the expected titles the prose names but the turn never read; it
sees only the titles the scenario lists. Each scenario resets its engine, so an evaluation needs an
engine of its own beside the thread's, though it can share the seam: whether a conversation is kept is
each engine's own to say (`AskAsking.hasKeptConversation`), so an evaluation's resets never hide the
thread's follow-up chips. Scenarios run one after another, and `table(_:)` ends with "N/M grounded,
clean and as expected."

`AskEval` is compiled into every build and isn't gated itself. `AskPrivateCloudCard` shows a diagnostics
row that runs it when the host passes `onRunEval` and diagnostics are on (`showsDiagnostics`, by default
`AskDiagnostics.isEnabled`): a Debug build, a TestFlight build on iOS or visionOS, or the host's
`enabledByApp`, which a Mac release build needs because the TestFlight check reads false there. So a
signed build can measure Private Cloud Compute from the host's settings.

The same switch turns on the feedback thumbs under answers. A thumbs-up or thumbs-down on the latest turn
of a kept conversation saves the session's feedback attachment locally (`AskFeedbackAttachments`, at most
10, the newest kept), only while the switch is on, a host's own `rate(_:_:)` included. It leaves the
device only by an explicit share, and it goes with the chat it came from: at New Chat, at Delete All
Chats, when an earlier chat opens in its place, and at a `.perLaunch` domain's next launch.

## 4. The screen

### The store

`AskConversationStore` is the screen's state: `@Observable`, `@MainActor`, and one per app; a second
alive over the same thread is logged as a fault. It turns engine events into `AskTurn`s, owns the draft,
and persists, restores and archives the thread.
- **Re-asking.** Try Again re-asks the newest failed turn only, and leaves the draft alone. A turn that
  failed before drawing anything gives its place to the re-ask; one that drew prose keeps it, and the
  question is asked again below it. It isn't offered while a question waits to be asked, which is newer
  though it has no turn yet. Ask again asks the question again over the thread as it stands, as a new
  turn. Another pick rerolls a pick. Edit & Resend puts a question back in the composer.
- **Stopping.** A stopped turn keeps its prose as its answer. A stop the reader asked for before the
  first word says so ("You stopped this answer") and offers Try Again, since `AskError.stopped`'s own
  line ("Couldn't answer that just now") would say the app failed; any other stop, such as a host's,
  shows that line. A question stopped while it waited to be asked has no turn to keep it, and goes back
  to the composer with its scope and its photo, unless the reader has begun another there.
- **Order.** New Chat, Delete All Chats, an earlier chat opening and Stop's word to the engine go through
  one queue, and a question asked meanwhile waits for the last of them. Asked at once, it could land
  before the engine's `stop()` or `reset()`, or land on the chat being replaced. A question still waiting
  when an earlier chat opens is asked on the chat that opens.
- **The warm session.** The store warms the engine only once the reader's own question has begun, on
  the draft's empty-to-non-empty edge: typed, or put back by Edit & Resend or by a Stop before it was
  asked. A prefill isn't that edge,
  since a link can come from anywhere, but the reader's first edit of it is. Opening the screen warms
  nothing, because a Private Cloud Compute warm spends a request of the reader's daily quota. The
  engine holds a prewarm to the domain's turn deadline and drops a warm that lands once the last screen
  has gone; one window closing doesn't release the warm another's questions will take.
- **Shape.** It publishes the thread's shape apart from its contents, so a streaming answer re-renders
  one row and not the screen. Measured, that took one turn from 44 screen bodies to 5.

### Stage

`AskStage` is the one animation key a turn can reach. It changes only when the thread's shape does: a
turn appears, the last turn gets its first words, a turn completes, the wait row comes or goes, or the
screen swaps between a first screen and the thread. Layout animates on it with `AskStage.animation`,
`.snappy(duration: 0.28)`, none under Reduce Motion, one constant so that what one change of Stage moves
moves on one curve, even the face in a host's slot, which is outside the screen's transaction. Its
`phase` picks the screen:

| Phase | Shows |
|---|---|
| `thread` | The thread has turns. |
| `ready` | Nothing asked yet, and something to ask about. |
| `nothingToAskAbout` | Nothing to ask about yet. |
| `cannotServe(reason)` | No tier can serve. This outranks an empty library. |

No first screen shows until the domain's overview has been read and so has the model's state (the
mirror has heard from its seam, or the engine's first refresh has returned), so a cold launch never
flashes "nothing to ask about", nor offers starters on a device that can't serve, while a probe runs.
The store reads the two at once, beside its retry of what the disk refused, and the overview, a host's
hook, gets the domain's `turnDeadline` and is read off the main actor. A device that can't serve shows
so once the model's state is read, since that outranks the library, and an overview still out at the
deadline is abandoned: the one read before it stands, and a first one opens the screen as on a library
nothing is known of, the ready screen, never "nothing to ask about".

The keyboard drives the two other keys, and neither ever changes on a stream. One is **making room**:
the ready first screen closes up for the keyboard, over the keyboard's own 0.38 s, its sentence and
scope caveat going and its gaps closing from 16 to 10 pt, through extra-large text and never in compact
height. In a window shorter than 860 pt, such as iPhone Duo's outer display, the mark and the headline
go too, and the space under the column keeps its making-room 12 pt with the keyboard down, since the
whole space would tip the column into scrolling (`AskFirstScreenArrangement`). The other is **the
composer rising out of the slot**, over the keyboard.

### The first screens

`AskFirstScreen` has three variants:
- **Ready.** The lit mark, the headline, a sentence, the scope caveat, "Try asking" with the starters
  (up to three on iOS, eight on macOS and visionOS), and the disclosure of what leaves the device.
- **Nothing to ask about.** The unlit mark, the host's copy and an optional action. Only for a host
  whose policy needs owned rows (`AskFirstScreenPolicy.needsOwnedRows`) and whose brand has the copy
  (`AskBrand.nothingToAskCopy`): with none, an empty library shows the ready screen, and the engine logs
  the mismatch as it is built.
- **Can't serve.** The unlit mark, dimmed, and the reason. The starters stay only when the host can
  answer them without a model (`AskFirstScreenPolicy.answersWithoutModel`).

On iOS, a first screen with starters to put beside its copy lays out side by side in compact height, or
in a regular-width window too short for the stack, but never at the accessibility sizes. On a phone on
its side over a host's slot the column lets its sentence go and offers two starters
(`AskFirstScreenArrangement.trimsOverSlot`).

On visionOS every target is at least 60 pt tall (`AskGrowth.touchTarget`), the starters' chips
included, and the column is always stacked. So in visionOS's default 1280 × 720 window the demo's six
starters end the column under the composer, and the column scrolls; a host's full bank of eight did so
before the chips grew. Side by side in a short window there, as on iOS, would need measuring at that
window first.

### The thread, the reveal and the waves

The thread is a lazy stack of turns. Each turn shows, in order:
1. a date line above the thread's first turn and wherever the day changed, and the recap's hairline;
2. the question;
3. the wait row, until the turn has words;
4. the prose;
5. the tiles, with the basis line under them;
6. the evidence line, "From N items" unless the domain words it otherwise, with the feedback thumbs
   where diagnostics are on;
7. a note when the answer was cut short, or the failure with Try Again and coaching;
8. the host's disclosure and footer, and a proposal's card;
9. on the last turn, the follow-ups, led by "Another pick" when the domain says the answer can be
   rerolled (`isRerollable`; no kind can be by default).

Tiles draw from `answer.tiles`, the rows the model chose, and only once it has chosen them. The rows the
tools read along the way (`AskTurn.rowsRead`) never become tiles on their own: they show only as counts,
the wait row's "N read" and the evidence line's "From N items".

**The evidence line's words are the domain's, and what it opens onto is AskKit's.**
`AskDomain.evidence(for:)` returns an `AskEvidencePresentation` for each answer:
- `.counted`, the default: "From N items", with the domain's `evidenceScope(from:)` when it names one,
  and no line for an answer with no rows behind it;
- `.line`, the domain's own resolved words ("From 3 status pages, read just now"), drawn with no rows
  behind them too;
- `.hidden`: no line.

Under `.counted`, an answer whose grounding is `AskGrounding.nothing`, which only a `.notRequired` domain
records, reads "Not from this app's data" in place of a count. A domain's `.line` or `.hidden` wins over
it. An answer with no grounding recorded (a stopped turn, an answer the domain gave without a model, a
thread saved before answers recorded it) is counted as before: unknown is not a claim. The line opens
onto the rows behind the answer, whichever words it reads, where there are some and the host draws them
(`evidenceDisclosure(_:)`). The ungrounded line never opens: an ungrounded follow-up carries the
thread's rows as its matches, and they aren't what it stood on.

**A finished turn draws again only when what it shows changes.** Each row compares the values it draws
from, and SwiftUI can't compare the host's builders, which are closures, so a value a builder captures
reaches the turns on screen only when the host names it too (`AskScreen.buildersDepend(on:)`).

**The reveal** draws prose in as it streams. `AskArrivals` splits the text into chunks by what each
snapshot added, and `AskRevealRenderer`, a `TextRenderer`, sweeps each chunk up out of a blur in
reading order, glyph by glyph in the order of the characters they draw, which is right to left in
Hebrew and Arabic, with a caret. The sweep takes 5 ms a character, at least 80 ms and at most 0.5 s
a chunk: measured, the on-device model streamed 162 characters over 819 ms, so ink never trails text a
slower tier would have shown later anyway. A chunk settles after 0.33 s, or up to 0.75 s for a long one,
and chunks older than 0.8 s merge, since unmerged a 1,584-character answer in 317 snapshots ended at 285
chunks. The reveal only paints, never holding text back, and under Reduce Motion it is a flat fade.

**Waves.** Once the answer lands, what it brings besides words arrives in waves: the tiles, then the
lines and cards beneath them, then the follow-ups when the stream ends. Each piece comes up out of the
same blur 50 ms after the one before it, without moving a frame, and the last starts within 600 ms
(`askArrival`). Only the answer that just ended arrives like this, within 2 s of ending: a restored
thread, an older turn and a row the lazy stack rebuilt draw at rest. A picture that lands after its view
is drawn, such as a photo still decoding, crosses its placeholder the same way (`AskPictureArrival`).

### The follow, the foot and the pill

`AskScrollFollow` decides every scroll:
- **The foot.** A new question lands at the foot of the thread, and the thread follows its own foot as
  the answer grows. The follow holds only while the reader is at the foot (within 80 pt of the last
  turn's end, a latch only the reader scrolling up clears), and only for the thread's own growth: a card
  the reader opens in a settled answer grows in place, and the thread stays put.
- **The pill.** "Jump to latest" appears when the newest text is out of view: past the follow boundary
  while an answer streams or new text is below, and after 400 pt of scrolling away on a settled thread.
- **Resizes.** A resize is never the reader's doing (a turned phone, a dragged window, iPhone Duo moving
  between its displays), so a reader at the foot when one starts is at the foot when it ends. A turned
  phone can report an offset that reads as a drag, and taken for one it left a reader 645 pt above the
  foot.
- **The motion.** A new question's scroll, the follow and the pill's jump share one curve, ease-out over
  0.25 s, with no travel under Reduce Motion; a resize's scroll is instant, the resize being the motion.
- **The keyboard.** `scrollDismissesKeyboard(.immediately)` puts it away as a drag begins, except on
  visionOS, and sending a question drops it.

### The composer and the keyboard

`AskComposer` sits in the screen's bottom bar (`safeAreaBar(edge: .bottom)`): a glass capsule tinted with
the host's accent, growing from one to four lines. The host's hint wraps the same way, and sizes the
field while the draft is empty, so at the accessibility sizes it shows whole, up to four lines. As it
grows its corners keep the radius they have at one line, centred on the circles at the bottom of the row,
so the circles stay as far inside the edge at four lines as at one: a capsule four lines tall, with ends
57 pt round, ran them out over its rim.

**Keys.** The software keyboard's Return inserts a newline, and the arrow sends. A hardware Return sends,
Shift-Return inserts a newline, and a Return with nothing to send, or with a turn in flight, types
nothing; a held Return's repeats are handled as the press is, so it sends once. A hardware Return while
an input method is composing, typing Japanese, Chinese or Korean, goes to the input method to confirm
its conversion and sends nothing, whatever the draft, the turn or Shift: the draft holds the marked
text too (measured on the iOS 27.2 simulator), so a Return that sent there would send the reading
unconverted. That holds on the Mac, and on iOS in `AskScreen`. SwiftUI shows no field's marked text, so
the composer asks UIKit and AppKit as the Return comes in (`AskMarkedText`): on iOS, the first responder
in the screen's window (`AskScreenWindow`); on the Mac, the active input context's client. On visionOS,
and on iOS for a composer a host draws outside `AskScreen`, which has no window to ask, nothing is
asked and a Return is routed as above. Not yet watched with an input method on a device. ⌘Return
sends, ⌘. stops, and ⇧⌘N is New Chat; ⌘Return is the circle's keyboard shortcut, which that check
doesn't see. On the Mac, `AskCommands` in the host's `.commands` puts New Chat, Send and Stop in the
File menu, acting on the composer in the focused window, and after them the newest turn's Copy, Copy
answer, Edit & Resend and Ask again, the items of its question's menu (`AskQuestionBubble`). Those
four act on the newest turn of the focused window's thread, which its screen hands up
(`AskNewestTurnCommand`), and have no shortcuts: ⌘C is the system's Copy.

**The circle** at the trailing end of the field changes with the state:

| State | Shows | VoiceOver says |
|---|---|---|
| A turn in flight | stop | Cancel |
| The field focused and empty | a chevron that puts the keyboard away | Dismiss keyboard |
| The field unfocused and empty | an arrow that focuses the field | Write a question |
| Something to send | an arrow | Send |

**The accessory button.** One button may sit before the field, a photo or a scan
(`AskComposerAccessory`). There is only ever one: two on a phone leave room for a word and a half.

**The spectrum.** A host may hand the screen a run of colors (`AskSpectrum`, such as `.aurora`), and
two things wear it in place of the accent: the send circle, filled with a gradient of it corner to
corner, on the face in a host's slot too; and the reveal's caret, in the same gradient over a soft glow
of itself. The composer's glass, the question bubbles, the wait row's shimmer and every tint keep the
accent. With no spectrum the screen is as it was, and under Increase Contrast the circle and the caret
take the accent. The composer draws no colored outline: the Glass Rod was one, and it went
([Rejected designs](#6-rejected-designs)).

**The slot.** A host with a tab bar can rest the composer's face in the tab view's bottom accessory, the
slot (`askComposerSlot`), wherever the tab bar runs along the bottom on iOS. That is what the Ask screen
hears inside its tab (`tabBarPlacement`), not the width: iPhone Duo's inner display and a Pro Max on its
side are regular width with the bar along the bottom, and under an iPad's top tab bar the composer stays
in the screen's own bar.
- The slot can't take typing, so it holds the face: the draft on one line, the accessory button and the
  send. A tap on the face raises the screen's own composer over the keyboard, and with no keyboard on
  screen the composer comes up all the same, with the slot emptied for it.
- The face is in the slot from the Ask tab's first frame, and switching tabs never animates it. An item
  pushed over the thread takes it out, and the screen reports the push itself, so a host never tracks
  its own pushes. A keyboard put away stays away, back on the tab or back from a pushed item.
- **A window has a slot of its own.** One store stands behind a screen in each of an app's windows, so
  what the face draws and when it shows is held in each window's slot, written by the screen under it
  and never on the store (`AskComposerSlot`'s environment entries list what). A window's face draws its
  own screen's accent, opens its own screen's picker, raises its own screen's composer and hides only
  under it, and a tap on it asks that screen through the slot, never through the store. A window newly
  opened draws the app's accent, with no accessory button, until its screen appears; after that it
  follows the screen's accent and accessory button as they change.

**A host's request for the composer.** `prefill(_:scope:send:)` without sending, and `focusComposer()`,
put the reader in the composer of one window, the one they are in; every window shows the store's draft.
- The store holds the request as a token (`composerFocusRequest`) that the screen in each window hears,
  and the first whose window appears active (`appearsActive`) claims it (`claimComposerFocus(_:)`,
  which succeeds once). Taken in every window, it would leave each one the reader isn't in with a
  focused field and a Done whose tap brings the keyboard back.
- The window the reader taps comes to the front after the tap's action has run. With two windows of the
  demo side by side on an iPad mini simulator (iOS 27.2), Surprise me tapped in the window at the back
  prefilled 94 ms after the touch began, while the other window still appeared active and took the
  request; the windows traded their active appearance 470 ms after the prefill, the one losing it 22 ms
  before the other gained it. So a screen whose window stops appearing active within 1 s of its take,
  its field still focused, hands the request on (`AskHostFocusHandOver`), and the screen now in front
  claims it. On the Mac, `appearsActive` is the key window, which a click makes key before its action
  runs, so a hand-on there is rare. With no window in front, the request waits for one.
- New Chat and Delete All Chats focus the composer in the window that asked and no other
  (`threadEndOrigin`). A host's own `startOver()` or `deleteAllThreads()` focuses it in every window, as
  `AskCommands(store:)` does.

**Done.** On iOS, a Done button (the `keyboard.chevron.compact.down` symbol, labelled "Done") leads the
navigation bar while the field is focused, so a reader with a half-typed draft can put the keyboard
away. Tapping the thread does the same, except on the Mac.

### The toolbar

- **The tier caption** names the tier that is answering or will answer next: the navigation subtitle,
  iPhone Duo's bar strip included, or leading the bar on visionOS and where a top tab bar hides the
  title. "Private Cloud Compute" is a name and isn't translated; "On device" is. Its line is always
  reserved, so a caption appearing mid-turn moves nothing. Leading an iPad's bar, it stops growing at the
  largest size short of the accessibility sizes, as the bar's own items do, and a long press shows it
  larger (the Large Content Viewer).
- **New Chat** is pinned trailing, a high-priority primary action on the Mac. **History** sits beside it
  for a domain that keeps its thread, except beside iPhone Duo's fold, where the chats are on screen.
  **Done** shows on iOS while the reader types, and is the last of the screen's items to overflow; in
  iPhone Duo's bar strip, which the keyboard shortens, History goes while the reader types
  (`AskHistoryItem`).
- **The navigation bar** minimizes on iOS only as the reader scrolls down, never while Done shows or an
  item is pushed (`askItemIsPushed`), and never for a scroll the screen makes itself, whose offset can't
  say whose scroll moved it (`AskNavigationBarMinimization`).
- **The quota banner** over the thread says when Private Cloud Compute has spent its daily quota and
  when it resets: a reset later today as its time, one on a later day as its day and time, and one
  already past not at all, in the words the settings card uses too. "Show options" opens Apple's route
  to a higher limit when there is one. At the accessibility sizes the banners over the thread, this one
  and the unreadable chat's, take at most half the screen's height, and scroll in it
  (`AskScreenBanners`).
- **`AskPrivateCloudCard`**, a settings card made from the store alone, says where answers come from and
  why. It is derived from the mirror, never probed itself, and says nothing about the tier until the
  mirror has heard from its seam: an unpublished mirror reads as a tier serving. It has no toggle.

### Accessibility

- **Every terminal state is announced** at high priority (`AskAnnouncement`), once however many windows
  show the store: an answer, one cut short by the deadline, one the reader stopped ("You stopped this
  answer", the line it shows), a failure, and an answer to a question asked with a photo that no model
  saw ("Answer ready. It read your words only."). A failure waits a beat, about a second, since its line
  may take VoiceOver's focus from the wait row and be read there: it is announced only if no line has
  claimed it by then (`AskUnclaimedEnding`), so it is heard once either way.
- **VoiceOver's focus follows what the reader did.** The control they tapped often goes as they tap it,
  and the element that should have the focus is often not in the accessibility tree yet, where a focus
  set goes nowhere. So the screen leaves a request (`AskVoiceOverTarget`, `AskWaitRowFocus`) that the
  element it names takes once it is there; a question asked drops a request still waiting.
  - New Chat and Delete All Chats send it to the first screen's headline in the window that asked, a
    host's own `startOver()` or `deleteAllThreads()` to every window's, and to the field where none
    shows.
  - A turn begun from a control that goes as it starts (a starter, a chip, Another pick, Try Again)
    sends it to the new turn's wait row, Try Again under prose a failed turn keeps to the wait row of
    the question asked below it; a question typed in the field leaves it with the reader.
  - A wait row that has it as it goes hands it to what replaces it (`AskWaitRowHandoff`): the prose at
    its first word or, for a turn that ended before one, the failure line. The other way too: when a
    hand-down or a rollover takes away the prose VoiceOver was on, the wait row that comes back takes
    the focus, and hands it on again at the new attempt's first word.
  - Opening an earlier chat moves no focus. In the pane beside iPhone Duo's fold the reader stays on
    the row they tapped, which becomes the open chat; from the sheet the focus goes back to the
    History button. VoiceOver hears "Opening “…”", the chat's title, from either.
  - Edit & Resend sends it to the field, and so does a tap on the face in a host's slot, held until the
    composer comes up over the face, which goes out of VoiceOver's way under it.
  - The card moves it to its outcome line after the reader's own yes or not now, once that line is in the
    tree, and VoiceOver reads the outcome there; where the focus hasn't landed on the line a beat after
    the outcome came, the screen announces it instead. A hand-off moves nothing and announces nothing,
    since the host's editor takes the focus. That request is the store's (`proposalOutcomeFocus`), not
    the card's, so a question asked while the app works drops it, and a card the thread rebuilt
    meanwhile still takes it. The store still publishes `proposalAnnouncement`, which the screen speaks
    for nothing else, for a host whose own control confirms or declines a proposal.
- **Identifiers.** Every control has an `ask.*` identifier (`AskAccessibility`), so one UI-test recipe
  drives every host, the history sheet's search field excepted, since `searchable` takes none.
- **A bare button says for itself what a system control says on its own** (`AskBareButton.swift`), each
  where its platform asks for it.
  - It lights as the reader looks at it on visionOS or points at it on an iPad, in the shape the reader
    sees rather than its frame's rectangle (`askHoverEffect(in:)`): the composer's circles and the
    face's, the chips' outlines, the pill, the pending photo's Remove, the thumbs, the evidence line,
    the default tiles' corners, and the chats pane's rows and trash. None lights while it is disabled,
    and nothing does on the Mac, which has no hover effect. Not yet looked at on the visionOS simulator
    or under an iPad's pointer.
  - On the Mac every glyph alone shows a help tag, in the words VoiceOver reads for it (`askHelp(_:)`):
    the send circle, the accessory button, the pending photo's Remove, the thumbs and the chats pane's
    trash. Only there, since `.help` is also the accessibility hint, and on iOS and visionOS VoiceOver
    would read each label twice. The evidence line takes none: its words say what it does, and a help
    would replace its hint.
  - Under Button Shapes (`accessibilityShowBorders`), a glyph alone wears a 1 pt ring in its own style,
    so it is still read against the ground its 3:1 was chosen on: the accessory button and the face's,
    the thumbs and the pane's trash. Words alone are underlined: the evidence line and the face's line
    (`AskBareButtonShape`). A button that shows a shape already, such as the send circle's fill, the
    chips' capsules or the pill's glass, wears nothing more. The ring and the underline come and go by
    opacity and `underline(_:)`'s flag, never a conditional modifier, so the setting changing keeps
    the button the same element under VoiceOver's focus.
- **Dynamic Type.** The mark scales with it, and a control's frame grows by what its glyph grows, not in
  proportion to the text (`AskGrowth`): in proportion, the composer's two circles left a 402 pt phone's
  field about 70 pt at the largest.
- **Contrast.** Text and glyphs on glass are held to a contrast bar against an estimated ground, 4.5:1
  for text and 3:1 for a glyph (`AskGlassForeground`): secondary only where it clears the bar, else
  primary. Where primary itself falls short, the glass gives way and the words stay hierarchical: on a
  light accent in dark mode the composer's capsule wears less than half of it, 0.43 of yellow and 0.45 of
  mint, where white words keep 4.5:1 (`AskComposer.tint(for:isLight:)`), worked out on the accent as the
  screen resolves it, its High Contrast variant included. The question bubble is no glass but a fill of
  the accent at 60% on the content layer, its ground worked out flat over the screen, and its words
  primary, or black on a light accent in dark mode, where white falls under 4.5:1 and black does better:
  white is 3.29:1 on yellow there and black 6.38:1 (`AskOnFill`). On the host's accent, a glyph is the
  system's white, as its own prominent buttons draw it, and black only where white falls under 3:1 and
  black does better (`AskOnAccent`). Words on a button filled with the accent, the confirmation card's
  Confirm and the nothing-to-ask action, are held to text's 4.5:1, so they are black on the system blue
  (5.97:1, where white is 3.52:1), on #007AFF and on the system red, and white on a dark accent
  (`AskOnAccentLabel`); the button wears the accent they were judged on. On visionOS, whose prominent
  button is a platter with no fill of the accent, the label is the style's own. The send circle is filled
  with the accent flat, not its `Color.gradient`, whose lighter top would leave white short of what it
  was judged on (`AskSendFill`). On a host's spectrum the send circle's glyph follows a glyph's rule
  against the lightest color the circle is filled with, since no point between two stops is lighter than
  the lighter of them (`AskSendGlyph`); `.aurora`'s circle runs from its blue to its violet, where white
  holds 3.81:1, because its cyan (1.65:1), coral (2.39:1) and magenta (3.05:1) leave white no margin. The
  confirmation card's "Not now", Try Again, and "Show options" on the settings card and the quota banner
  are `.primary` on their style's ground (`.tint(.primary)`), where the accent fell under 4.5:1; the
  banner's is semibold, so it still stands apart from its sentence. Deemphasized text on an opaque ground
  (`askDeemphasizedText`) is the secondary hue at 76% in light mode, 5.31:1 on white where `.secondary`
  is 3.44:1, `.secondary` in dark mode, which the audit passes, and `.primary` under Increase Contrast.
  The audit's contrast check runs in a call of its own, because combined with `.dynamicType` and another
  check it fails text in both appearances at any strength; the demo's UI suite audits the screen, the
  card, the nothing-to-ask button and the empty composer so, light and dark, and the first screen, an
  answer with its tiles, a failure with Try Again and the card by every other check in a second call.
- **Copying.** The question's Copy and Copy answer, from its menu or the Mac's menu bar, stay on the
  device, since either can quote the reader's own data: on iOS and visionOS `.localOnly`, expiring
  after 120 s, and on the Mac `prepareForNewContents(with: .currentHostOnly)`, which has no expiry.
  Text selected and copied with the system's own Copy goes wherever any copy goes.

### Platforms and sizes

Lay out by size class and measured size, never by idiom or orientation: iPhone Duo is `.phone` on both of
its displays, and its inner display ignores orientation. Every build is against an SDK of 27.2 or later,
since that is AskKit's floor, so the Duo draws the screen edge to edge and, on its side, puts the bars
in the bar strip at the side of the display.

**iPhone Duo's fold** is read with `reservedRegions(kind: .division, options:
.includeInactive)`, which finds it lying flat as well as bent. Flat is the region being inactive and
bent its being active, never its size: the simulator reports 40 pt lying flat where Apple's guide has
none (`AskFold.arranged`). The screen arranges itself around it (`AskFoldArrangement`, whose doc
comments and the types they name carry each case and its measurements):
- **Held like a book**, the fold runs top to bottom. The reader's chats take the leading pane
  (`AskChatsPane`) and the conversation the trailing one, each as wide as its side, so the conversation
  lays out at compact width, as it does closed; the toolbar drops History, and the composer stays in the
  conversation's pane rather than in a host's slot. The open chat's mark is a wash of the accent, about
  1.2:1, so its title is heavier too, carries a check under Differentiate Without Color and under Bold
  Text, and is heard as selected. Every row is one button, the open chat's disabled, and a row stays
  the same element for as long as it lists the same chat, so the row the reader taps is the row that
  opens. Before the reader has a chat, a first screen with two halves takes both panes, what only
  informs leading and what to ask trailing (`AskFirstScreenArrangement.takesBothPanes`). The system
  reports the fold a frame late at launch, so where one is on its way the screen stands in two even panes
  (`AskFoldArrangement.awaitingFold(width:)`), and nothing waits on a clock. The panes keep to the width
  they are offered (`AskFoldPanes`), since a stack grown to hold a conversation wider than its side would
  be centered and rebuild the screen without end.
- **With no room for two panes**, beside a host's sidebar or for a domain that keeps no chats, the
  conversation keeps to the trailing side of a bend, and flat it takes the whole width.
- **Upright**, the fold runs across, and only the first screens move (`AskFoldSplit`): one with two
  halves parts at the fold, what only informs above and what to ask below, and one with none keeps
  clear of a bend. There is no arrangement while the keyboard is up, nor at the accessibility sizes.
- **The conversation is one view in every arrangement.** Only the leading pane comes and goes, so
  opening or closing the device keeps the thread's scroll position and the composer's focus.

visionOS has no Liquid Glass API, not even the `Glass` type, so AskUI speaks `AskGlass` and answers with
`.glassBackgroundEffect()` there, set to `.implicit`. Every Ask surface sits in a window, which is glass
already, so a surface takes a fill, and glass of its own only out of a window, in a volume. Never put
glass on glass, and never imitate glass with a `Material`: real glass follows the reader's transparency
setting, and a hand-rolled blur doesn't.

## 5. The house rules

Code comments cite these by number ("house rule 4"), so the numbers are fixed.

1. **Private Cloud Compute answers every turn it can, and the on-device model answers the rest. The
   reader gets no switch.** The tier is chosen once a turn, from one read of every tier's state; an
   outage on Private Cloud Compute (unreachable, offline, rate-limited, timed out, over quota, or stopped
   by its context gate) hands the turn down once; with nowhere to hand it, it is the turn's error, which
   Try Again retries, though a spent quota is asked nothing until its reset. Refusals, overflows and
   ungrounded answers are never handed down, and the caption names the tier answering.

   *Why:* the larger model answers better and reads photos, so it should serve whenever it can. A toggle
   would be a second, contradictory answer to a question the engine decides on every turn, and a reader
   shouldn't be handed an error while a model on their own device could answer.
2. **By default, an answer with no retrieval behind it is never shown.** Grounded is judged one way:
   the model called a tool, the app searched for it, or, on a follow-up, the turn read rows or its prose
   names a row the thread has read. What becomes of a turn that isn't is the domain's grounding policy,
   one for its life (`AskDomain.grounding`):
   - **`.retrieval`**, the default: prose reaches the screen only once the turn is grounded. An
     ungrounded answer on a fresh session gets the grounded retry, and an ungrounded follow-up on a kept
     conversation fails, with coaching.
   - **`.toolCall`**: the same without the retry, so an ungrounded first answer fails at once, with
     coaching.
   - **`.notRequired`**: prose draws from the first token, and every answer is kept, recording what
     grounded it, or that nothing did (`AskAnswer.grounding`).

   A guardrail verdict is final under every policy: a refusal shows as one, never retried.

   *Why:* an answer about the reader's own things that didn't read them is invented, and reads exactly
   like a real one. So `.retrieval` is the default, and the policy for a domain over the reader's data,
   and `.toolCall` keeps the same guard for a domain whose tools answer every question worth answering,
   with no search to plan. A domain whose answers needn't rest on the reader's data, such as an
   assistant whose tools convert or act, would under either policy fail every answer its model gives
   from the conversation alone, "thanks" included. `.notRequired` keeps those, and its guard is
   attribution: an answer nothing grounded records so (`AskGrounding.nothing`), and AskKit says so under
   it, "Not from this app's data" where the evidence line would count what it read. A domain rewords
   that line (`AskEvidencePresentation.line`), or leaves it out where it attributes its answers another
   way (`.hidden`), through `AskDomain.evidence(for:)`. The policy is the domain's and never the
   question's: chosen from the question's words, it would be a host's word list deciding what is kept
   after generation (rule 7), and what grounds a turn is the session's tools, fixed for its life
   (rule 6).
3. **Instructions are the host's and short. Everything the reader or a tool wrote is data.** A domain's
   instructions run to a few sentences: measured on Private Cloud Compute, three sentences grounded 3 of
   3 runs, where about 1,100 words grounded 0 of 3. Mappings, such as which word means which category,
   live in `@Guide`s and tool descriptions, where the model reads them as it uses them. The reader's
   words are clamped, redacted, neutered and fenced. Tool output is untrusted: the engine fences, redacts
   and neuters the rows the grounded retry searches, and a host's tools clamp and neuter theirs, field
   by field through `AskPrompt.clamp`, in no fence of their own. The answer is stripped of links before
   it is rendered ([Prompts and fences](#prompts-and-fences)).

   *Why:* long instructions drown the one instruction that matters, such as to search before
   answering, and text the host didn't write must never be able to speak as the host.
4. **Nothing animates on tokens or tool payloads.** Layout's only animation keys are `AskStage` and the
   keyboard's two, though a reader's tap may animate its own change, as New Chat takes the thread away as
   one piece. Glass that comes and goes (the jump pill, the two banners and the photo chip) animates on
   its own show flag, on `AskStage.animation` in its own glass group, and moves no other frame. The
   reveal paints ink over text already laid out and never holds text back. What an answer brings besides
   words arrives once, without moving a frame: tiles only through `AskTileGrid`, a late picture only
   through `AskPictureArrival`, everything else through `askArrival`. The wait row shows the turn's real
   tool events, never an invented delay, and a new phrase there is the one thing a tool event animates: a
   0.2 s cross-fade in a row that reserves both its lines from its first frame.

   *Why:* a stream produces about thirty snapshots a second, and a layout animation keyed to any of them
   re-runs the whole thread thirty times a second while the reader is trying to read it.
5. **Nothing shown is taken back.** A failure renders beneath whatever prose the turn had drawn, a
   stopped turn keeps its text as its answer, and the deadline truncates an answer rather than wiping it.
   Tiles appear only once chosen, never as tiles of everything read, and a turn from a chat that has
   ended writes nothing into the next one. *The one exception:* a hand-down or a rollover asks the
   question again from the start and clears the prose already drawn, grounded or not, since kept it would
   be swapped out under the reader's eyes at the new attempt's first words, and a Stop before them would
   keep half an answer from an attempt that was thrown away (`AskTurnEvent.restarted`). It takes prose
   back only with time left for those first words (`AskEngine.restartFloor`); with less, the failure
   renders beneath the prose instead. The grounded
   retry reports `.restarted` too, but it runs only under `.retrieval`, where ungrounded prose is never
   drawn, so it takes nothing back.

   *Why:* text that changes or vanishes while someone reads it teaches them to trust nothing on screen.
6. **A session's tool set is fixed for its life, and a warm session only ever starts a conversation.**
   Tools are built once per session, so anything that changes per turn reaches them through a stable
   object, as the wait row's listener is swapped inside `AskActivityRelay`. The reply's shape is the
   domain's for its life (`AskDomain.replyShape`), so it never changes under a session either. A prewarmed session is taken
   only by a question that starts a fresh session on the same tier, and none is built beside a kept
   conversation.

   *Why:* the session caches its prefix (instructions, tool definitions, the reply schema,
   `promptPrefix`), and changing any of it throws the cache away.
7. **Every user-facing string ships in all 25 languages, and the model's question kind decides.** Every
   string AskKit shows carries English and all 24 translations before it is pushed, except
   `AskPrivateCloudCard`'s diagnostics rows, developer copy shown only where diagnostics are on, in
   English `Text(verbatim:)`: "Ask eval" is a term of art, and translating it would be false precision.
   Whether an answer shows tiles is decided by the `questionKind` the model returned; a host's English
   keyword lists may steer the prompt before generation, but decide nothing after it.

   *Why:* a rule written as an English word list silently stops working in the other 24 languages.
8. **Reduce Motion has an answer in every animation, VoiceOver hears every terminal state, and Dynamic
   Type scales the marks.**

   *Why:* a reader who can't watch the reveal, can't see the screen or reads at a large size is owed the
   same answer, the same ending and the same controls.

## 6. Rejected designs

Each of these is the obvious thing to try, and each was ruled out for the reason given.

- **Pinning the newest question to the top of the screen, with space held open below it for the answer.**
  Sized from the turn's measured height, the space hung on a measurement that arrives one layout pass
  late, so the question was clamped back down; held on the turn's own row, it changed the layout above
  the question mid-animation on a device, so the thread moved twice for one question. It is anchored at
  its foot instead.
- **`.defaultScrollAnchor(.bottom, for: .sizeChanges)` as the follow.** Instrumented, it never moved the
  thread: an answer grew the content from 713 to 1,039 pt, and the offset didn't change. Whether the
  anchor's dynamic `nil`/`.bottom` value never re-registers, or the `.alignment` anchor outranks it,
  wasn't established. The follow is an explicit `scrollTo` on the foot; reproduce that before reinstating
  it.
- **Measuring the first screen's column to choose its scroll anchors.** The scroll geometry
  (`containerSize` minus `contentInsets`) swung from 618 to 414 to 466 pt and settled on the content's
  own height, since the scroll view sizes to its content. A `GeometryReader` around the scroll view gave
  a steady 670 pt, keyboard up or down, but defeated the scroll view's keyboard avoidance, so a clipped
  disclosure became an unreachable one. Left alone, the scroll view insets itself correctly, and three
  `defaultScrollAnchor`s tell it which end to show for each kind of change.
- **`scrollDismissesKeyboard(.interactively)`.** Twice it left the keyboard stopped half-way down, focus
  still on and nothing able to raise it again, in a state that survived relaunching the app and
  rebooting the simulator and cleared only when the simulator was erased; one of the two was New Chat
  building the first screen already scrolled to its end under a raised keyboard. The same flows under
  `.immediately` on a fresh simulator didn't stick. The cause wasn't established.
- **A `.hard` top scroll edge effect on the iOS thread.** Apple's guidance names a style only where the
  automatic one doesn't suit, and a thread passing under a navigation bar is what SDK 27's automatic
  style is made for. Side by side on SDK 27, `.hard` ghosts a little less at rest as an accent-colored
  question passes behind the bar, and is no more opaque in motion; the bar's brightness is its glass
  sampling the content under it, which no style changes. The question bubble was glass then, so the bar
  was glass sampling glass, which glass can't do. It is a fill of the accent now (`AskQuestionBubble`),
  since glass belongs to the navigation layer and a question is content, and the bar samples it as it
  samples any content.
- **`.submitLabel(.send)` on the composer.** On a vertical-axis field the software keyboard's Return
  never fires `onSubmit`, so a key labelled "send" inserts a newline.
- **A text view of AskKit's own for the composer's field (`UIViewRepresentable`,
  `NSViewRepresentable`), to see an input method's marked text.** It would see it, and give up what
  SwiftUI's `TextField` gives the composer: the hint on the field's first baseline
  (`AskComposerFieldStack`); the focus binding, which SwiftUI clears as the field resigns
  (`AskKeyboard`), and VoiceOver's (`@AccessibilityFocusState`); the growth from one line to four; the
  words' hierarchical style on glass (`AskGlassForeground`); the field's VoiceOver and Voice Control
  labels and its `ask.field` identifier. And it would be two text views, UIKit's and AppKit's. The
  composer asks UIKit and AppKit for the marked text as a Return comes in instead (`AskMarkedText`).
- **The keyboard toolbar (`placement: .keyboard`) for Done.** On SDK 27 it is a floating capsule in the
  composer's band, and it lands on top of the send button.
- **A turning conic gradient for the spectrum's glow**, a ring of its colors blurred behind the
  composer. It read as a loading wheel. It moved by angle, so on a capsule about seven times as wide as
  tall it raced round the ends and crawled along the sides. And blur was its only softness, so on white
  it smudged.
- **Edge Light, a glow in the composer's rim lit only while a turn was in flight**: a crisp line of the
  colors with a close bloom and a wide one, behind the glass, that ran round from the send circle at the
  send and drew back into the rim at the end. On white its first cut was too faint to read as a border.
- **The Glass Rod, a clear glass tube of the spectrum's colors round the composer's rim**, in 0.1.0. One
  Metal shader cast each point across the rim into a tube about 6 pt across, with a prism fringe, a
  highlight and a soft glow past it, the colors placed by length round the rim; it stood still at rest,
  to mark the field as the place to type, and drifted while a turn was in flight. A colored outline
  round the field was too distracting, and the composer was better without it. It went, and with it
  AskUI's only Metal shader and the Metal Toolchain every build needed for it. The composer is plain
  glass in the accent's tint, and the spectrum stays on the send circle and the caret.
- **A view builder for the accessory button.** It would add a sixth type parameter to an `AskScreen`
  that already spells five, across the modifiers that set its views, and every host with no accessory
  button would pay for it in its declarations. The button is always the same shape, a bare glyph on the
  composer's glass, so `AskComposerAccessory` takes the glyph, the words and the action as a value.
- **A closure for the openers** (`AskItemOpenAction { id in … }`). A closure never compares equal, so
  each one written to `askItemOpener` redrew every bank of tiles in the thread, and a struct wrapping
  one compares no better. The host conforms a class to `AskItemRouter` or `AskDraftRouter`, and the
  action holds it, equal while it is the same object.
- **A pacing buffer for the reveal**, releasing characters at a steady rate to smooth a bursty stream.
  It delays the tail of every burst, so the reader waits for text that has already arrived. The reveal
  draws text where and when it arrives instead, and within a chunk the ink crosses the words at 5 ms a
  character (`AskArrivals.staggerPerCharacter`), the rate the on-device model was measured writing at.
- **An `AttributedStringKey` to stamp the reveal's chunks.** It fails silently: every run reaches the
  renderer unstamped, the finished answer looks perfect, and the drawing-in is simply gone, and a
  self-keyed attribute fails the same way. `Text.customAttribute` on each piece carries a stamp into
  `Text.Layout`, the pieces joined by string interpolation, a `"%@%@"` key set not to translate (joined
  by the deprecated `+`, they keep their stamps too). Measured on SDK 27;
  `AskRevealRenderTests.theStampReachesTheLayout` catches a regression.
- **A per-domain reply schema (`DynamicGenerationSchema`).** It would give each host its own question
  kinds, at the cost of typed `PartiallyGenerated` streaming. `AskReply`'s vocabulary is static instead:
  eleven kinds drawn from real hosts, which each domain narrows. A domain whose answers never show tiles
  chooses a second schema that is just as static, `AskProseReply` (`AskDomain.replyShape`): two shapes
  fixed when AskKit compiles, each streamed typed, never one built for a domain.
- **`LocalizedStringResource?` as the return type of `AskDomain.phrase(for:)`.** It would hand the
  lookup to AskKit, and break every conformance, for a hazard one doc line closes: a domain in a Swift
  package resolves with `bundle: #bundle`, since a bare `String(localized:)` there searches the host
  app's main bundle and silently returns the key in every language but English. `basis(for:)`,
  `perform(_:)` and `evidence(for:)`'s `.line` return resolved lines for the same reason.
- **The session's running token total for rollover.** See
  [Continuation](#continuation-tail-referent-recap-rollover).
- **`UserDefaults.standard.bool(forKey:)` for the park's launch argument.** It also reads a value an
  earlier run persisted, so a flag left in a simulator's defaults would unpark every later run on it.
  `AskDevelopmentPark` reads the argument domain alone.

## 7. Glossary

Each term below has one meaning in AskKit's docs and comments. A comment using one otherwise is a bug.

- **bank**: a set of chips laid out together, the first screen's starters on glass in a container of
  their own and the thread's follow-ups and coaching on fills (`AskChipRow`), or the tiles under an
  answer (`AskTileGrid`). Each tile is the host's view; the bank is AskKit's.
- **bar strip**: iPhone Duo's vertical bar column, where the system lays out the tab bar and the
  navigation bar's items along a side of the display (`AskBarStripReader`). The keyboard shortens it,
  and it reports `.bottomBar` as the tab bar's placement.
- **bare button**: a button that draws its label and nothing behind it: a glyph on glass, a line of
  caption text, or a chip whose capsule is laid outside the button. It says for itself what a system
  control says on its own (`AskBareButton.swift`, [Accessibility](#accessibility)).
- **chunk**: a stretch of an answer's prose that arrived in one snapshot (`AskRevealChunk`), drawn in as
  a unit.
- **coaching**: the two starters offered under a refused or ungrounded failure, as a way forward.
- **cover**, **covered**: an item the host pushes over the Ask screen covers it, and takes the face out
  of the slot (`AskComposerSlotCover`); switching tabs doesn't cover it.
- **domain**: the host's `AskDomain`: the tools a session offers the model, its instructions, its copy,
  and which answers are kept. A domain over the reader's own rows names its `Row`; one without rows
  takes the stand-in, `AskNoRow`.
- **evidence line**: the line under an answer saying what it stood on (`AskEvidenceLine`): AskKit's
  count of the rows it read, the domain's own words, or "Not from this app's data" for an answer
  nothing grounded (`AskDomain.evidence(for:)`).
- **face**: the composer's one-line stand-in in the slot: the draft, the accessory button and the send. A
  tap raises the screen's own composer.
- **first screen**: what the screen shows before the thread has a turn (`AskFirstScreen`). It comes in
  three variants: ready, nothing to ask about, and can't serve.
- **follow**: the thread scrolling to keep its foot in view as the last turn grows (`AskScrollFollow`),
  only while the reader is at the foot and the growth is the thread's own.
- **foot**: the end of the last turn. It isn't the end of the content, since a 12 pt spacer sits below
  it; a reader within 80 pt of it is at the foot.
- **grounded**: a turn whose model called a tool, whose app searched for it, or, on a follow-up, that
  read rows or whose prose names a row the thread has read. One test under every grounding policy.
- **grounded retry**: the app searching for a model whose answer on a fresh session read nothing, then
  asking again with the rows fenced as data (§2, step 8). Only under `.retrieval`.
- **grounding policy**: which answers the engine keeps, by what grounded them (`AskGroundingPolicy`):
  `.retrieval`, `.toolCall` or `.notRequired`, one per domain for its life (house rule 2).
- **hand-down**: a turn moved once from Private Cloud Compute to the on-device model after an outage,
  as the first question of a new conversation that carries the tail ([The hand-down](#the-hand-down)).
- **ink**: what the reveal paints: glyphs that are already laid out, brought up from a blur
  (`AskRevealRenderer`).
- **making room**: the ready first screen closing up for the keyboard, over the keyboard's own 0.38 s.
- **mark**: the host's glyph (`mark(_:)`, or `AskDefaultMark`), lit on the ready first screen and in the
  wait row, unlit on the other two first screens.
- **mirror**: `AskModelStatus`, the main-actor copy of the seam's state that the screen reads: the next
  tier, why nothing can serve, and the quota. Until the seam publishes to it (`hasHeardFromSeam`) it
  knows nothing, though it reads as a tier serving.
- **park**: `AskDevelopmentPark`, which keeps development builds off Private Cloud Compute and the
  developer's quota.
- **pane**: one side of iPhone Duo's fold where the screen splits there (`AskFoldPanes`): the leading
  pane, which is the chats pane once the reader has a chat, or the conversation pane, trailing.
- **pill**: the "Jump to latest" button (`AskJumpToLatestPill`).
- **proposal**: an action a tool offers (`AskProposal`), which the app carries out, or hands to its own
  editor, only once the reader confirms the card under the answer.
- **reader**: the person using the host app, so that "user" never has to mean the developer.
- **recap**: the fenced summary a fresh session starts with, the titles discussed and the last exchanges
  (`AskContinuation.recap`), marked in the thread by "Earlier in this chat is summarized".
- **referent**: the titles of the rows an answer was about (`AskDomain.referent(from:)`). The next
  follow-up's "those" or "it" resolves against them.
- **reply shape**: which of two static schemas a domain's turns ask the model to write
  (`AskReplyShape`): `.full`, `AskReply`, or `.prose`, `AskProseReply`, its answer and follow-ups alone,
  whose answers show no tiles. One per domain for its life.
- **rests**, **raised**: the composer's two states under a host's slot: at rest, hidden, while the face
  stands in for it (`askComposerRests`), and raised over the keyboard, or held up where none came.
- **reveal**: the drawing-in of an answer's prose as it streams, chunk by chunk (`AskRevealRenderer`,
  `AskArrivals`).
- **rollover**: a kept conversation replaced by a fresh session with a recap, at its turn limit or a full
  window.
- **seam**: `AskModelSeam`, the one owner of the process's model facts. `AppleModelSeam` implements it on
  Foundation Models.
- **settle**: a turn settles when it ends, with an answer, a failure or a stop; a chunk, once drawn
  (`AskArrivals.settle(forLength:)`).
- **spectrum**: a host's run of colors (`AskSpectrum`) that the send circle and the caret wear in place of
  the accent.
- **Stage**: `AskStage`, the one animation key a turn can reach.
- **steer**: a prompt line that nudges the model without being the question: the domain's per-turn
  lines, a scope line, or "Another pick"'s list of what not to choose again (`AskOrigin.reroll`).
- **tail**: the thread's last three exchanges, each an `AskThreadTail`: a question, its answer and the
  titles of the rows it showed. It outlives the session it was built on, and a relaunch.
- **tier**: which model serves a turn (`AskTier`): `.privateCloud` or `.onDevice`, chosen as the turn
  starts.

### Words kept to one meaning

- **slot**: only the tab bar's bottom accessory that holds the face (`askComposerSlot`).
- **accessory button**: only the one button before the composer's field (`AskComposerAccessory`).
- **wave**: only a group of an answer's pieces that come up in reading order from one start, 50 ms apart
  (`askArrival`): the tiles, the lines and cards beneath them, or the follow-ups.
- **fold**: only iPhone Duo's hinge. The bars **minimize**, the SDK's word.
- **overflow menu**: the toolbar's menu for items that don't fit.
- **bottom edge**: the bottom of the viewport.
- **merge**: in prose, only what settled chunks do in the reveal. Two copies of one chat made one are
  **joined** ([Persistence and history](#persistence-and-history)). Identifiers keep the word
  (`AskThreadArchive.merge`, `AskThreadEntry.merging`, `AskCollector.mergePayload`).
- **gate**: always named: the generation gate (`AskGenerationGate`), Private Cloud Compute's context
  gate, the push gate (`scripts/git-hooks/pre-push`), or a platform gate (an `#if` condition).
