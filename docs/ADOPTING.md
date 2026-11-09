# Adopting AskKit

The README's [Adopt](../README.md#adopt) gets an app answering. This page has the rest: every option,
and what AskKit expects of a host. The doc comments describe each API, and
[ARCHITECTURE.md](ARCHITECTURE.md) how it all works. Besides the domain and the screen, a host can use
`AskEval` (scenarios run through a real engine), `AskLink` (a deep link that prefills the composer and
never sends), `AskProposal`, `AskPrompt`'s clamps and `AskEngine.answerOnce(_:)` (one answer outside the
thread, for a Siri intent).

## Install

A target that needs only the engine, or a type such as `AskLink`, takes `AskCore` alone. The module
names are generic, so check that nothing else in your build is called `AskCore` or `AskUI`. AskKit has no
dependencies of its own. A shared package that also builds for tvOS or watchOS adds `.tvOS("27.2")` and
`.watchOS("27.2")`; an app's project sets its deployment target itself.

### Platforms

Both products build for iOS, macOS, visionOS, tvOS and watchOS, so a shared package can depend on them,
but Ask shows only on iOS, macOS and visionOS. On tvOS, AskCore compiles out its Foundation Models half
(`AskDomain` and the engine), and on watchOS also whatever names `SystemLanguageModel`, such as
`AppleModelSeam`; `AppleAskSession` names nothing the watch lacks, and builds there. A target that builds
for tvOS wraps its domain in `#if canImport(FoundationModels) && !os(tvOS)`, as the README's samples do.

### Enhanced Security

A target with Enhanced Security on (`ENABLE_ENHANCED_SECURITY`) builds an arm64e slice for a device and
the Mac, and Xcode builds a package arm64e only when the workspace asks it to: unasked, the slice can't
find AskCore and AskUI, and the build fails. Set `iOSPackagesShouldBuildARM64e`,
`macOSPackagesShouldBuildARM64e` and `visionOSPackagesShouldBuildARM64e` to `YES` in
`WorkspaceSettings.xcsettings`, under your project's `project.xcworkspace/xcshareddata/` or your
workspace's `xcshareddata/`, as the demo does ([DEMO-PROJECT.md](DEMO-PROJECT.md)).

### Versions

At 0.x a minor version may break the API. `from:` takes any release below 1.0.0, and
`.upToNextMinor(from:)` holds you to one minor version.

### Switching over AskKit's enums

An enum that grows is open (`@nonexhaustive`): a `switch` over one needs `@unknown default`, where a case
a later version adds then goes instead of breaking your build. The open ones are `AskError`,
`AskUnavailability`, `AskTier`, `AskActivity`, `AskTurnEvent`, `AskReasoningLevel`, `AskGrounding`,
`AskDiscard.Reason`, `AskRetryAfter`, `AskProposalKind`, `AskProposalOutcome` and `AskOutcome.Miss`, and
in AskUI `AskOrigin`, `AskStage.Phase`, `AskProposalPhase` and `AskPrivateCloudState`.

The rest are closed, sets fixed by what they are, which a `switch` covers case by case: `AskTurnMode`,
`AskOutcome.Failure`, `AskGroundingPolicy`, `AskReplyShape`, `AskEvidencePresentation`,
`AskPersistence`, `AskPrivateCloudCompute`, `AskFeedback.Sentiment`, `AskChipRow.Kind` and
`AskArrival.Kind`. A new case in a closed one is a breaking change, allowed in a 0.x minor version.

## The domain

`brand`, `makeTools(_:)` and `instructions(…)` have no default. The two associated types, `overview()`
and `search(_:context:)` have defaults that suit only a domain whose tools read no rows, so a domain over
your data gives all seven:

| Member | What you give it |
|---|---|
| `Row` | An `AskRow`: `Codable`, `Sendable`, `Identifiable` and `Equatable`, with a `displayTitle` the model reads in tool output and writes back when it picks tiles. Rows are written into the thread file, so a field you add later needs a default when it decodes. |
| `SearchArguments` | A `@Generable` type, your tool's arguments, so that when the model won't call the tool, the app's own search chooses them as the model would have. |
| `brand` | An `AskBrand`: your copy, the Application Support folder the thread is kept in, and the log subsystem every AskKit logger writes under. `help`, the field's placeholder, is drawn on one line and cut off where it is wider than the field, so keep it to a few words. |
| `overview()` | What the reader has to ask about: scopes and counts. |
| `makeTools(_:)` | The tools a session offers the model, built around the `AskToolContext` it is handed. |
| `instructions(tier:isConversation:answerLanguage:)` | The session's instructions: yours, short and in English. AskKit opens them with Apple's sentences for the locale and the language, so they name no language ([The answer's language](#the-answers-language)). |
| `search(_:context:)` | The search the app runs when the model won't call a tool, through the tool's own code. |

### The rules for tools

**A tool is built once per session, and reports every call.** It keeps `context` and nothing per turn.
It runs each call's work in `context.withToolCall(_:_:)`, which notes the call with the collector,
finishes it however the work ends, and only then hands the work's phrase to the relay, since the finish
clears a phrase reported before it. It records every row it shows the model with `record(rows:)`: an
answer's tiles resolve only against recorded rows.

**A tool's output is the reader's data, and AskKit fences it.** Put every field through `AskPrompt.clamp`,
show at most `context.rowLimit` rows, and return the lines bare: no fence of your own, which the grounded
retry would redact, and none of AskKit's tag names (`user_request`, `rows`, `previous_question`,
`previous_answer` and `tool_result`). `clamp` swaps angle brackets for lookalikes, flattens newlines,
holds each character to 16 Unicode scalars and redacts a fence tag in any spelling NFKD maps to it, then
cuts to the limit, so clamping twice changes nothing; its doc comment has the spellings. For output whose
line breaks carry its layout, use `AskPrompt.sanitizeForFence`, then `AskPrompt.neuteringTags`, which
does the bracket swap alone.

**No straight double quotes around a title or a name.** The model copies the quote into its answer,
where it ends the guided-generation string the answer is written in. In vultyr's eval, 6 of 8 answers
that ran to the token cap stopped right where a quoted title would open ("The incident is titled "), and
the rest of the generation ran on to the cap. In Japanese the model closed a string with 」 instead, and
ran away the same way. Leave titles and names bare, as the README's sample does. `AskPrompt.clamp` turns
a straight double quote inside a field into ″, so data such as a 7" record can't end the answer's
string. Clamp every field with it, as the rule above says: a clamp of the tool's own misses this.

**A guided string's list of values takes whole values.** A value that begins with a word the model
reaches for captures the whole phrase: once the model writes the word, the list leaves it one value to
finish with. With vultyr's `since` limited to "overnight", "this morning" and "today", "this week" came
out as "this morning" in every language. Taking out the value that began with "this" moved the misread
to the nearest other value, and a longer list brought back a misread that had been fixed. Give the model
a whole value for each thing it can mean, or take an integer, such as a number of days.

**`context.rowLimit` caps what a result shows, not what a tool reads.** Read all that the call asks
about, show the first `rowLimit` rows in the order that matters, and say how many more there were, as
the README's sample does with `found`. Capped before the read, the rest go unread and unsaid, and the
model answers as if they held nothing.

**The search is written once.** `search(_:context:)` runs the tool's own code, so the grounded retry reads
and records the rows the tool would have.

### Isolation and instructions

AskKit builds with main-actor default isolation and `NonisolatedNonsendingByDefault`. In a target that
does too, mark the types AskKit uses off the main actor `nonisolated`, as the samples do (a `Codable`
payload you record needs it, or its conformance is main-actor isolated), and mark a tool's `call`
`@concurrent`, since an `async` function that isn't runs on its caller's actor. A target with neither
setting needs neither keyword: AskKit's public API is `nonisolated` throughout.

Keep `instructions` to a few sentences that name only tools the session holds. Put mappings, such as
which word means which category, in `@Guide`s and tool descriptions, where the model reads them as it
uses them. ARCHITECTURE.md's [Writing a domain's tools](ARCHITECTURE.md#writing-a-domains-tools) has what
was measured on Apple's model.

### The answer's language

AskKit follows Apple's practice in [Supporting languages and locales with Foundation
Models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models).
Write your instructions, tool descriptions and `@Guide`s in English, and name no language in them: the
engine opens every session's instructions with Apple's sentences. The first is the person's locale in
Apple's exact phrase, "The person's locale is ja_JP.", which Apple says "comes from the model's
training, and reduces the possibility of hallucinations in multilingual situations"; as in Apple's
sample, it reads `Locale.current` and is left out for U.S. English. The second, "You MUST respond in
Japanese.", comes wherever the seam names a language, since the model otherwise answers in the language
of its inputs. `AppleModelSeam` names one only once the tier's `supportsLocale(_:)` says it writes it.
Where that says no, or can't say, it names none, and the answer is written in English, with neither
sentence for a locale in another language. A request that still throws
`LanguageModelError.unsupportedLanguageOrLocale` fails the turn as `.modelUnavailable(.languageNotSupported)`.
`answerLanguage` still reaches `instructions(…)`, for a domain that needs the language for anything else.

### Optional members

Everything else has a default, and each member's doc comment says what it does. The ones you will reach
for first:

| Member | Default | What it is for |
|---|---|---|
| `starters(overview:window:)` | none | The first screen's questions, and the coaching under a refused or ungrounded answer. `window` is the most that show at once: three on iOS, eight on macOS and visionOS, fewer where the screen is short. |
| `grounding` | `.retrieval` | Which answers are kept: those grounded in your data, with the grounded retry (`.retrieval`); those a tool call grounded (`.toolCall`); or every answer, recording what grounded it (`.notRequired`). |
| `evidence(for:)` | `.counted` | The line under an answer: AskKit's count of the rows it read, your own words (`.line`), or none. |
| `replyShape` | `.full` | The answer, its question kind, its tiles and the follow-ups (`.full`), or the answer and follow-ups alone (`.prose`). On the device the prose schema costs 192 tokens of the window, the full one 704. |
| `promptLines(question:overview:)` | none | Lines such as today's date, sent when a question starts a fresh session. |
| `promptPrefix` | empty | Fixed words that open every prompt. Keep them byte-stable: a warm session caches them. |
| `phrase(for:)`, `basis(for:)`, `evidenceScope(from:)` | none | The wait row's words for a tool event, a factual line under an answer's tiles, and the part of your data the evidence line names. |
| `perform(_:)` | throws | Carries out a proposal the reader confirmed. |
| `deterministicAnswer(for:)`, `answersWithoutModel` | none, false | An answer with no model, such as small talk, whose payload is your own type and whose throw fails the turn, and whether such answers cover your starters. If they do, a device where nothing can serve keeps the starters and the composer under its reason, and closes on your brand's `disclosureSentenceWithoutModel` in place of `disclosureSentence`, where you give one. |
| `turnDeadline` | 45 seconds | How long one turn may run, counted from the question. |
| `rowLimit(for:)`, `maxTurns(for:)` | 40 and 8 on Private Cloud Compute, 12 and 3 on the device | The rows a tool result may show, and the turns a session carries before it rolls over. |

### A domain without rows

A domain whose tools work something out or act names neither associated type (its `Row` is `AskNoRow`
and its `SearchArguments` `AskNoSearchArguments`) and leaves `overview()` and `search(_:context:)` to
their defaults. Its `grounding` decides what becomes of an answer no tool grounded: under `.notRequired`
it is kept, and the line under it says it isn't from the app's data. With no rows to show, it asks for
`.prose` replies. A proposing tool works as it does over rows, and `evidence(for:)` words the line under
an answer a tool grounded, which AskKit's count of rows leaves out when the tool read none. The demo's
assistant does both.

## The seam, the store and the screen

**The seam.** `AppleModelSeam` owns what the process knows about its models: which tier can serve, the
cooldown after a failure, the quota and the generation gate. Build one for the process, and one
`AskEngine(domain:seam:)` per thread. `privateCloudCompute:` has no default: `.declared` only if your
entitlements file holds the Private Cloud Compute entitlement, `.undeclared` otherwise.

A host that already routes its own model calls can bridge its router to `AskModelSeam` instead, wrapping
each session in `AppleAskSession`, so Ask and its other features share one cooldown and one generation
gate. That gate is the process's one, where the seam's on-device generations wait: run your own through
`AskGenerationGate.run`, which waits there too. The seam logs a generation it presumes wedged under its
`logSubsystem:`; pass your brand's, so its lines sit with the engine's.

**The store.** `AskConversationStore` holds the turns, the turn in flight and the draft. Make one for the
life of the app, outside any view: a Mac `NavigationSplitView` rebuilds its detail on every sidebar
change, so a store owned by a view would lose the thread, and a turn in flight with it. Making the store
reads nothing; the screen reads the saved thread as it appears.

**The screen.** `AskScreen` sets no title of its own: show it in a `NavigationStack` titled with
`store.brand.title`, where its toolbar's New Chat, History (for a domain that keeps its thread) and tier
caption can render. Its options are `accent:`, `spectrum:`, `nothingToAskAction:`, `onAttach:` and
`composerAccessory:`, which takes the photo button's place and leaves `onAttach:` unused. Modifiers are
the only way to replace AskKit's mark and tiles with your views, in any order: `mark(_:)`, `tiles(_:)`,
`evidenceDisclosure(_:)` and `answerFooter(_:)`. A `tiles` builder is handed the rows; the turn and the
rows; or the turn, the rows and an `open` closure, nil where nothing opens. Return an `AskTileGrid`, so
the tiles arrive one at a time. A value a builder captures reaches answers already on screen only through
`buildersDepend(on:)`.

An empty overview shows the nothing-to-ask screen only when your brand gives `nothingToAskCopy`, with a
button only when you pass `nothingToAskAction:` (an `AskNothingToAskAction`: its label and what it
does). On iPhone Duo's inner display the screen arranges itself around the fold, with nothing to wire.

## Optional pieces

| Piece | How | Notes |
|---|---|---|
| Tiles that open a row | A class conformed to `AskItemRouter` (`func open(_ id: Book.ID)`), and `.environment(\.askItemOpener, AskItemOpenAction(router))` above the screen | The router's `open(_:)` types the id: one for another id type opens nothing, and AskKit logs that once per id type. With no opener, tiles are inert. Keep the router in `@State` or on an object the app holds: two actions on one router are equal, so building the action in a body redraws nothing, and a new router redraws every bank of tiles. |
| A page pushed over the screen | `.environment(\.askItemIsPushed, pushedID != nil)` on the screen | The screen holds its navigation bar open while it's true: a page pushed while the bar is minimized hangs the app. |
| Actions the model proposes | A tool records an `AskProposal`, and you implement `AskDomain.perform(_:)` | The payload is your own `Encodable` value, stored as JSON and read with `payload(as:)`; `try AskProposal(…, payload:)` throws only for a value JSON can't hold, such as a NaN or a `Data`. Only the reader's tap on the answer's card reaches `perform`, off the main actor and once AskKit has saved the yes, so it runs at most once per yes. One that throws can be confirmed again, so make a part-way failure safe to rerun. To open your own editor instead, conform a class to `AskDraftRouter` (`func open(_ proposal: AskProposal)`) and set `askDraftOpener` to `AskDraftOpenAction(router)`, kept as the tile opener's router is; `perform` is then never called. Leave a proposing tool out where `context.isConversation` is false. |
| A photo or a scan | `acceptsPhotoAttachments`, `AskScreen(store:onAttach:)` and `store.attachPhoto(_:label:reference:)`, or `AskScreen(store:composerAccessory:)` | The composer has one accessory button: yours (`AskComposerAccessory`), which wins when you pass both, or the photo button. Only Private Cloud Compute reads photos; on the device the question runs on its words, and the thread says so. |
| A spectrum look | `AskScreen(store:spectrum:)` with `.aurora`, or `AskSpectrum([…])` of your colors | The send circle and the reveal's caret take a gradient of the colors, on the slot's face too; the rest keeps `accent`. The send glyph is white, or black where white falls under 3:1 on the lightest color. Increase Contrast puts the accent back. |
| The Ask tab's glyph | An SF Symbol such as `Image(systemName: "text.bubble.badge.sparkles")`, or a custom symbol through `Image(_:)`, as the tab's `Label` icon | In one color like the bar's other items; AskKit ships none, and the bar swaps in the `.fill` variant itself, a custom symbol's `.fill` sibling included. The demo wears `askkit.bubbles`, a custom symbol in its asset catalog; `Image(systemName:)` finds only SF Symbols. With `.symbolRenderingMode(.palette)` (sparkles first, bubble second) the bar draws the colors as given and doesn't mark the selection, so pass a fixed selected color, resolved for the color scheme: in a tab item's palette, `.tint` and `Color.accentColor` come out system blue, `.primary` black on a dark bar, and a gradient its first color. |
| The tab bar slot (iOS) | `.askComposerSlot(store, isEnabled:)` on the `TabView` that holds Ask, with `.tabBarMinimizeBehavior(.onScrollDown)` | The composer's face rides in the tab view's bottom accessory, beside the minimized tab bar. It does nothing on macOS and visionOS, so a shared host needs no `#if`. |
| The Mac menu | `.commands { AskCommands(store: ask.store) }` on the scene, or `AskCommands(isEnabled: ask.store.hasTurns) { … }` when your New Chat does more than start over | New Chat (⇧⌘N), Send (⌘Return) and Stop (⌘.) in the File menu, for the focused window's composer, then Copy, Copy answer, Edit & Resend and Ask again, with no shortcuts, for its newest turn. macOS only: wrap it in `#if os(macOS)` in a scene shared with iOS or visionOS, as the demo's `App.swift` does. |
| Entry points | `store.prefill(_:scope:send:)` and `store.focusComposer()` | `prefill` puts a question in the composer and the reader in front of it. `AskLink` builds and reads `<scheme>://ask?q=…` links, and a link only ever prefills. `scope` is your id for where the question came from, and `scopeLine(for:)` tells the prompt what it means. |
| The settings card | `AskPrivateCloudCard(store: ask.store)` in your settings | Where answers come from, and why, with no toggle. `AskPrivateCloudCard(store:onRunEval:)` adds a row that runs your evaluation where diagnostics are on: a Debug build, a TestFlight build (the Mac's too) once StoreKit has said so (`AskDiagnostics.isTestFlight`), or wherever you set `AskDiagnostics.enabledByApp`. A build under App Review most likely reads as TestFlight, so pass `showsDiagnostics:` to keep the rows from a reviewer. |
| The tips | `try Tips.configure()` in your `App.init`, after `Tips.hideAllTipsForTesting()` for screenshot and UI-test launches | AskKit never configures TipKit: an app that does gets AskUI's three tips beside its own, at its own `displayFrequency`, and one that doesn't sees none. They teach the menu on a question (on iOS the only way a touch reaches Copy answer), "Don't suggest this" on a starter, and deleting one chat. A tip shows only while its surface is on screen and uncovered, and goes once the reader has done what it says or closed it. |
| Siri and UI tests | `.appEntityIdentifier(…)` on each tile your `AskTileGrid` draws; `AskAccessibility` | An annotation per tile lets Siri resolve "this" to the item the reader means (`AskDefaultTiles` carries none). Every control has an `ask.*` identifier, so one UI-test recipe drives every host. |

## Private Cloud Compute

The tier needs the managed entitlement `com.apple.developer.private-cloud-compute`, which Apple grants to
eligible developers on request ([Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/));
your declaration of it, `AskPrivateCloudCompute.declared`; a network connection; and some of the reader's
daily quota. Without the entitlement, every question goes to the on-device model.

**A development build never reaches it by default.** Two checks stand in the way:
- **The entitlement.** A request from a process without it is a fatal trap, not an error, so the seam
  sends one only when you declared it and the running build doesn't prove it absent. The Mac and the
  simulator read their entitlements exactly; on a device, a provisioning profile without it proves it
  absent. TestFlight and App Store builds carry no profile, so your declaration is all there is: declare
  it only when your entitlements file grants it.
- **The development park.** The daily quota belongs to the iCloud account, and every development run
  would spend the developer's own, so `AskDevelopmentPark` keeps off the tier a test host or `swift test`
  run, a Debug build, a simulator, and a binary signed for development (`get-task-allow`: a Profile run,
  or a Release build installed by hand). A parked process sends the tier nothing, not even a prewarm,
  and its caption says "On device". **TestFlight and App Store builds are never parked.**

To measure the tier in a development run, opt in from a build signed with the entitlement:
`ASK_LIVE_PCC=1` in the environment (`yes` and `true` work too), the launch argument `-ASK_LIVE_PCC YES`,
or your own closure passed to `AskDevelopmentPark.setAppOptIn(_:)`. The opt-in lifts the park and
nothing else. A process outside an app's context, such as a command-line tool, fails every request at
once with `LanguageModelError` −1 (`ModelManagerError 1001`), which AskKit reads as the tier being
unreachable. ARCHITECTURE.md's "Entitlements" and "The development park" give the order of the checks.

**The daily quota.** Once the reader's quota is spent, the seam holds the tier until the reset, the turn
that hit it is handed down to the on-device model, and a banner says when the quota comes back. Where the
on-device model can't serve either, a question fails at once with the quota's line, asking the tier
nothing. Opening the screen warms no session, since a warm session there spends a request: AskKit warms
one once the reader starts a question, by typing it or editing one a link left in the composer.

**Holding every model call.** For a run that must not depend on a model, such as a store-screenshot
capture, pass a closure to `AskInferenceHold.setHeld(_:)`. While it says so, the seam reads the on-device
model as available and speaking the app's language without asking it, builds no session and runs no
generation, and `AskGenerationGate.run` throws `AskInferenceHold.HeldError` for your own generations: the
screen shows the intro a reader with a working model sees, in any language and on any simulator.

## What is stored, and where

The engine writes nothing to disk. AskUI's store keeps the thread, through AskCore's `AskThreadStore` and
`AskThreadArchive`; a host that takes AskCore alone keeps it in storage of its own.

With `persistence` at its default, `.thread`, the store keeps these under
`Application Support/<appDirectory>/`, your `AskBrand.appDirectory`. That must be one folder name: not
empty, not `.` or `..`, with no `/`; with any other, the stores read and write nothing and AskKit logs a
fault. An unsandboxed Mac app's Application Support is shared by every app the user runs, so take a name
no other app would, such as your bundle identifier: Delete All Chats deletes every chat file in the
folder, whichever app wrote it.

| Path | Holds |
|---|---|
| `ask-thread.json` | The chat on screen, its newest 50 turns: each question, the prose, the answer with the rows behind it (your `Row` values, encoded), any failure, the model that answered, when it was asked, and the reader's thumbs. A photo is kept as its label and your reference, never its pixels. |
| `threads/` | The earlier chats, at most 50, in the same format: `index.json` and one `<id>.json` each. |
| `feedback/` | Feedback attachments, at most 10, only where diagnostics are on and the reader rated an answer. They leave the device only when the reader shares them from the settings card. |
| `ask-thread-unreadable-<id>.json`, `ask-thread-original-<id>.json` | A thread this build couldn't decode, or read only in part, set aside whole until a launch that reads it puts it back. |

A turn is written when it ends, never while it streams. Writes are atomic, off the main actor, excluded
from backup, and under complete file protection except on a Mac, whether the app runs there natively, as
a Mac Catalyst build or as an iPhone or iPad app. There they keep the system's default class, readable
from the first unlock until restart, because on macOS 27.2 complete protection fails every write while
the Mac is locked. `persistence: .perLaunch` keeps the thread for the process only.

**What a turn sends to Private Cloud Compute.** On the device, nothing leaves it. On Private Cloud
Compute a turn sends your instructions, your tools' definitions and AskKit's reply schema; the prompt
(when a session starts fresh, your `promptPrefix`, a recap of the thread's last exchanges and your
`promptLines`; on a follow-up, the titles the last answer named; a scope line for a question asked from
one part of your app; and the question, clamped to 500 characters and fenced); what your tools return;
the grounded retry's request and rows, when the model won't search; and a photo with your label, when
the question has one. AskKit makes no network requests of its own, other than watching whether the
device is online. Tell the reader what leaves the device in
[`AskBrand.disclosureSentence`](../Sources/AskCore/AskBrand.swift).

**The privacy manifest.** `AskCore`'s resource bundle carries a
[`PrivacyInfo.xcprivacy`](../Sources/AskCore/Resources/PrivacyInfo.xcprivacy), so your app's privacy
report includes AskKit's part with nothing more from you. It declares the two required-reason APIs
AskCore calls: user defaults (`CA92.1`), read only for the launch's own arguments (`ASK_LIVE_PCC`), and
the file timestamp (`C617.1`), a chat file's modification date inside your app's container. It declares
no tracking, no tracking domains and no collected data: AskKit sends nothing to its developer or any
third party. `AskUI` calls none of these APIs and carries no manifest.

## Localization

The screen ships in 25 languages, `en ar cs da de es es-MX fr he id it ja ko nb nl pl pt-BR ru sv th tr uk
vi zh-Hans zh-Hant`, from two String Catalogs: AskUI's for the screen, AskCore's for the error lines.

Your copy is yours to localize: AskKit shows your `AskBrand`'s strings, your starters and what your
domain returns, such as `phrase(for:)` and `basis(for:)`, as you give them. Resolve each from your own
catalog with `String(localized:)`; in a Swift package, `String(localized: "…", bundle: #bundle)`, since
a bare call searches the app's main bundle and returns the key.

AskKit's languages appear only where your app declares them. An app with no catalog of its own supports
only its development language, so AskKit shows that one whatever the reader's. Declare yours with String
Catalogs or `CFBundleLocalizations` in your Info.plist, as the demo does. [TRANSLATION.md](../TRANSLATION.md)
has each locale's rules.
