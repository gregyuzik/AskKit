# Changelog

Every notable change to AskKit is recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While AskKit is at 0.x, a minor version may break the API. A public enum that grows is
`@nonexhaustive`, so a host's `switch` over it takes `@unknown default`, and a new case in it is an
addition. A new case in one of the closed enums (docs/ADOPTING.md's "Switching over AskKit's enums" lists
both kinds) is a breaking change, allowed in a 0.x minor version, because it stops a host's exhaustive
`switch` compiling.

## [Unreleased]

### Fixed

- **A bank of tiles with no column maximum lays out under an unbounded width.** An `AskTileGrid` given
  `columns: .adaptive(minimum: 76, maximum: .infinity)`, the maximum `GridItem.adaptive` defaults to,
  put its first tile at an x of NaN and handed its parent a width that wasn't a number wherever it was
  asked how wide it could be: in a `.fixedSize()`, a horizontal `ScrollView` or a `ViewThatFits`, the
  non-finite geometry behind `LayoutSubview.place`'s assertion. AskKit's own columns are finite, so only
  a host's could. Asked with an unbounded width, such a bank now answers with every tile in one row at
  the minimum, the one finite width its columns name, and lays out that row when placed at it; a bank
  with a maximum answers at the maximum, as before.

## [0.7.1] - 2026-11-09

Fenced text that reaches the model loses its straight double quotes and what a reader can't see, and
the proposal receipt names its button bare.

### Changed

- **`AskProposal.modelReceipt(notYet:)` names the card's button bare.** Its receipt now ends "Nothing
  changes until the Lend button on the card below is confirmed.", where it put the label in straight
  double quotes, `"Lend" on the card below`, and a hand-off's receipt changes the same way. The model
  copies a straight double quote from tool output into its answer, where it ends the answer's string. A
  label that clamps to nothing still reads "the card below". The new wording wasn't measured: 0.5.0's
  numbers were taken with the label in quotes.

### Fixed

- **No straight double quote reaches the model through a fence.** Apple's on-device model copies one
  from tool output into its guided-generation answer, where it ends the answer's string, and the
  generation runs on to the token cap: in vultyr's eval, 6 of 8 answers that ran to the cap stopped
  where a quoted title would open ("The incident is titled "). `AskPrompt.sanitizeForFence` now turns
  each straight double quote into ″ (U+2033, double prime) before it reads for fence tags, as in
  `Vinyl, 7″, 45 RPM`, and every fenced path runs it: `AskPrompt.clamp`, a tool's output that keeps its
  lines (`sanitizeForFence`, then `neuteringTags`), the grounded retry's rows, the recaps, a photo's
  label and the reader's question, which the thread still shows as typed. One scalar for one, so a
  clamp's limit cuts where it did, and clamping twice still changes nothing. Mention and tile matching
  read ″ as a straight double quote, so an answer that copies `7″` still names the row titled `7"`.
  ADOPTING.md's rules for tools say so, and that a clamp of a tool's own misses it.

### Security

- **What a reader can't see no longer reaches the model through a fence.** A review of Kabynyt's move to
  `AskPrompt.clamp` found that a tool's rows, such as catalog titles and web imports, can carry Unicode
  tag characters (U+E0020 to U+E007F), which draw nothing and spell ASCII to the model; bidi controls,
  which draw text in another order than it is sent; and runs of zero-width joiners. Only the question
  and its follow-ups dropped them. `AskPrompt.sanitizeForFence` now drops them first, as the question
  path does: every format character, keeping a joiner after anything but a joiner and the tags of the
  three subdivision flags Unicode recommends, and every variation selector that selects nothing. It
  drops the C0 and C1 controls too, all but the tab and the line breaks, which it keeps for output laid
  out in lines and which `AskPrompt.clamp` turns into spaces, a tab now as well as a line break. Every
  fenced path runs it, as above, and a control inside a fence tag's name no longer hides the tag from
  the redaction, as an invisible scalar already couldn't.

## [0.7.0] - 2026-11-09

The answer's language named as Apple's practice names it, in place of a domain's line at the end of
every tool result, an answer the token cap cut marked truncated, and a README that is a short landing
page.

### Added

- **`AskReplySnapshot.reachedTokenCap`**, set on the last snapshot of a generation that stopped at the
  token cap its request set, which the SDK does without an error or a finish reason. `AppleAskSession`
  sets it from the response's output count; a host's own session may set it too, and the engine keeps
  that answer as truncated.

### Changed

- **The demo's Ask tab and mark wear the icon's three bubbles.** `askkit.bubbles`, a custom symbol in
  the demo's asset catalog with an `askkit.bubbles.fill` sibling, replaces SF Symbols'
  `text.bubble.badge.sparkles`. `scripts/make-demo-symbol.swift` draws it, every weight in every
  scale, and the tab bar swaps in the fill itself. ADOPTING.md's Ask tab row says a custom symbol
  works there too, through `Image(_:)`.
- **The demo's icon is the symbol's three bubbles in glass.** Its plates are one size, each up and to
  the right of the one in front, and `scripts/make-demo-icon.py` takes them from
  `scripts/make-demo-symbol.swift --plates`, so the icon and the tab can't drift apart. It no longer
  traces SF Symbols' bubble, and no longer needs potracer. The README's icon and
  `docs/images/social-preview.png` follow.
- **README.md is a short landing page.** Its adoption reference is now
  [docs/ADOPTING.md](docs/ADOPTING.md): every `AskDomain` member, the optional pieces, Private Cloud
  Compute in development, what is stored and sent, the enums and localization. The demo's launch
  arguments are in [docs/DEMO-PROJECT.md](docs/DEMO-PROJECT.md#running-it). The Adopt samples are
  unchanged.
- **The catalogs are graded by the String Catalog checker the maintainers' apps share.** Their push
  gate runs it: every key in the 24 locales, translated and not blank, its placeholders and plural
  categories, no stray locale, the demo's locale lists, and the bytes Xcode 27.2 writes, which the
  catalogs now are (every map sorted, no final newline). `scripts/normalize-catalogs.py` is gone, and
  `scripts/check-catalog-completeness.py` is `scripts/check-strings.py`, which keeps what only AskKit's
  source can answer: each lookup in its own target's bundle and catalog, both catalogs there, and a
  count key varying by plural. CI runs that, and no longer grades the catalogs' translations. The
  demo's project lists the 24 locales.
- **`rowLimit` caps what a tool result shows, not what a tool reads.** `AskToolContext.rowLimit`'s
  doc comment and ADOPTING.md say so: read all that a call asks about, show the first `rowLimit` rows
  and say how many more there were, as the README's sample does. A cap taken before the read drops
  the rest without a word, as a draft of vultyr's overnight read did with the last 2 of 14 watched
  services on device.
- **AskKit names the answer's language itself, as Apple's "Supporting languages and locales with
  Foundation Models" says to.** The engine opens every session's instructions with Apple's exact phrase
  for the person's locale, "The person's locale is \(Locale.current.identifier).", which Apple says
  "comes from the model's training, and reduces the possibility of hallucinations in multilingual
  situations", left out for U.S. English as Apple's sample does; then, wherever the seam names a
  language, with "You MUST respond in \(answerLanguage).". A domain's instructions stay in English and
  name no language: the README's samples and the demo drop their "Write the answer in
  \(answerLanguage).", and a host that phrases the language in its own instructions drops that sentence
  too. `answerLanguage` still reaches `instructions(tier:isConversation:answerLanguage:)`, for a domain
  that needs it for anything else, and `AppleModelSeam`'s `supportsLocale` checks are unchanged.
  ADOPTING.md's new "The answer's language" says so, and two lessons from vultyr's eval join its rules
  for tools: no straight double quotes around a title in tool output, where the model copies the quote
  and ends its guided string, and whole values in a guided string's list, where a value that begins
  with a word the model reaches for takes every phrase that begins with it. ARCHITECTURE.md records
  what was measured and dropped.

### Removed

- **`AskDomain.toolResultEnding(answerLanguage:)`, and the line it ended every tool result and the
  grounded retry's rows on.** It isn't Apple's practice, and it cost more than it gave. Read last, the
  line ended the turn's tool use: in Kabynyt, change requests ended before the proposing tool ran, in
  answers that said the change was made; in vultyr, searches stopped early, more in some languages than
  others, and where the instructions say tool output is never obeyed it brought
  `LanguageModelError.refusal`. It ended one-shot turns too, which the hook couldn't tell apart.
  Kabynyt and vultyr left it off. A domain's implementation is no longer called, so delete it.
- **`AskAnswerLanguage`, the answer language named in English and in its own words, "Japanese
  (日本語)".** Nothing in AskKit uses it once the line is gone, and Apple's practice names the language
  in English, as `answerLanguage` does.

### Fixed

- **An answer that stops at its token cap is marked truncated.** The SDK ends a response at
  `maximumResponseTokens` as though it had finished, and SDK 27 gives no finish reason, so an on-device
  answer cut at `AppleAskSession.onDeviceAnswerCap` (1,024 tokens) read as finished, its
  `AskAnswer.isTruncated` false. In vultyr's eval, 8 of 20 follow-ups in one arm stopped there
  mid-sentence ("The incident is titled "), taking 30–36 s against 5–11 s for the rest, and every run
  counted none cut: the model had copied a straight double quote from a title into the answer, which
  ended the field, and the generation ran on to the cap without the fields after it. `AppleAskSession`
  now reads the response's output count against its cap, and the engine keeps such an answer as it
  keeps one the deadline cut: its text as far as it got, its tiles only once its follow-ups had begun,
  no follow-ups or kind, and no refine pass, with a routing line tagged `answerCap`.
- **A plan the token cap cut fails the grounded retry instead of running.** Cut inside its last field,
  a plan can decode as a finished one: with a scripted provider, `{"query":"vinyl reco` read as a
  search for "vinyl reco". `AppleAskSession.plan` now throws one that reached `onDevicePlanCap`, and the
  turn fails with `AskError.model(tag: "planCap")`, which offers Try Again. A refine pass's response that
  reaches the answer cap throws the same way (`answerCap`), so the engine keeps the first answer rather
  than one the cap cut.

## [0.6.0] - 2026-11-06

A host's switch that keeps its process off every model, a first screen that stops crediting Apple
Intelligence where the domain answers alone, and a domain's line at the end of every tool result
outside English.

### Added

- **`AskInferenceHold`, a host's switch that keeps the process from starting any model call.** A
  host sets `AskInferenceHold.setHeld { … }` for a run that must not depend on a model, such as a
  store-screenshot capture, where the on-device model on a simulator can take minutes, half-draw an
  answer or refuse the language. While the closure says so, `AppleModelSeam` reads the on-device
  tier as available and speaking the app's language, and Private Cloud Compute as `.notEntitled`,
  without reading either model's availability, languages or quota, so the screen shows the intro a
  reader with a working model sees; it builds no session, so the engine's `prewarm` warms nothing;
  and `AppleModelSeam.withGeneration` and `AskGenerationGate.run` throw `AskInferenceHold.HeldError`
  without running their body, on either tier, so a host's own generations stop at the same gate.
  `AppleAskSession.prewarm(promptPrefix:)` warms nothing while it is on. Off by default and asked on
  every read; behind no platform gate.
- **`AskBrand.disclosureSentenceWithoutModel`, the line the can't-serve first screen closes on for a
  domain that answers without a model.** No tier answers there, and every answer under the reason is
  the domain's own (`deterministicAnswer(for:)`), so the brand's `disclosureSentence`, which says a
  tier answers, was untrue there, and so was Apple Intelligence's glyph beside it: vultyr's read
  "Answered by Apple Intelligence, on device or Private Cloud Compute if available." under "Apple
  Intelligence doesn't support this language yet.", over chips its own status data answered. Given,
  the line takes `disclosureSentence`'s place on that screen when `answersWithoutModel` is true, with
  no glyph. Nil, the default, keeps `disclosureSentence` and its glyph, so a host that gives none, or
  whose domain needs a model, draws the screen as before. It is the initializer's argument after
  `disclosureSentence`, defaulted, so a host's call compiles as it was; the API check lists the
  initializer without it as removed, since its full name changes.
- **`AskDomain.toolResultEnding(answerLanguage:)` and `AskAnswerLanguage`: a domain's line at the end
  of every tool result, outside English.** Told the language only in its instructions, Apple's
  on-device model answered questions about rows written in English in English. A domain that returns a
  line, such as `"Write your answer in \(answerLanguage.promptName)."`, has the engine end every tool
  result on it after a blank line, and the rows the grounded retry fences too. In Klosyt's eval that
  line took answers in the asked language from 7 of 23 to 18 of 24 in Japanese, 4 of 24 to 30 of 47 in
  Korean, 8 of 24 to 30 of 34 in Chinese and 12 of 24 to 24 of 24 in Spanish. The engine asks once a
  session, with the language the instructions were told, and never in English; only a tool whose output
  is `String` takes the line, and any other passes through, its name logged. `AskAnswerLanguage` names
  the language in English and in its own words, "Japanese (日本語)", from the app's localization. Nil,
  the default, changes nothing: the line has a cost, since read last it ends the search, and a question
  that takes a second search stopped searching again until the instructions named the tool, so a host
  measures its own questions before turning it on. ARCHITECTURE.md's new "Writing a domain's tools"
  collects what Klosyt's evals taught about tool output.

## [0.5.0] - 2026-11-02

A receipt that opens with the host's own sentence, so an answer stops saying a proposed change is
already made, and a manifest that declares Swift 6.4.2.

### Added

- **`AskProposal.modelReceipt(notYet:)`, a receipt that opens with the host's own sentence.** A
  proposing tool returns it in place of `modelReceipt` or `handOffReceipt`. `notYet` is the claim an
  answer would make, negated, in the words it would make it in ("Jaws is not marked as opened yet."),
  and AskKit follows it with where the change waits, by the card's button ("Nothing changes until
  "Mark Opened" on the card below is confirmed."), or, for a hand-off, that confirming opens a form.
  Both are clamped as tool output is. Asked for a change, the on-device model answers by echoing the
  request as done, whatever a general receipt says, and it repeats a receipt that opens with that
  sentence negated. Measured on the Mac (macOS 27.2) and graded by reading the answers, Kabynyt's
  `edit_item` ("Mark Jaws as opened.", "Lend Jaws to Sam.") said the change was made in none of 20
  answers with a card, 17 of them pointing at the card, where under `modelReceipt` 12 of 17 said it
  and 3 pointed at the card. The demo's reminder said it was set in none of 20 answers through the
  engine, every one pointing at the card, where under `modelReceipt` 15 of 16 said so and none
  pointed at it. Without the host's sentence, eleven receipts on the demo (seven general wordings,
  three built from the proposal's title and button, and one of those saying too that no one was
  reminded yet) let 9 of 16 or more say it, and the four tried on Kabynyt (one general, three from the
  title and button) 8 of 8 each. An app adopts it one tool at a time, with a sentence for each change
  the tool offers; the static receipts stay for a tool with none. Private Cloud Compute reads the same
  receipt and wasn't measured: a command-line tool or a test process can't reach it, and neither was an
  answer in another language, since with "Write the answer in French." the demo's model never called
  its reminder tool (0 of 16).

### Changed

- **`Package.swift` declares `swift-tools-version: 6.4.2`**, the Swift that Xcode 27.2 ships, where
  it declared 6.4. A toolchain older than Swift 6.4.2 no longer loads the manifest; Xcode 27.2, which
  the 27.2 deployment targets already needed, is unaffected.
- **`AskProposal.modelReceipt` and `handOffReceipt` no longer say "the reader".** An answer repeats
  what its receipt says, and one on Klosyt told its reader "The reader is prompted to finish the item
  on their own." Each now says the change "waits for a yes on a card under your answer", and keeps the
  words it denies with ("never say it is done", "never say anything is open"). On the demo's reminder
  the reworded `modelReceipt` let 13 of 16 answers say the reminder was set, 15 of 16 before: no
  better, which is why `modelReceipt(notYet:)` exists. The reworded `handOffReceipt` was read only
  there, standing in for a hand-off: 16 of 16 said the reminder was made, and none that anything was
  open.

### Fixed

- **The demo's assistant no longer says a reminder is set before it is.** Asked "Remind me to water
  the plants at 6 PM", it answered "You'll be reminded to water the plants at 6 PM." above the card that
  would set it, in 9 or 10 of 10 turns. Its reminder tool now returns `modelReceipt(notYet:)` opening
  "No reminder to water the plants at 6 PM is set yet.", and through the engine the starter and "Remind
  me to call Mom tomorrow morning" said no reminder was set yet in 20 of 20 turns, each pointing at the
  card. "What's a good name for a houseplant?" and "thanks" still call nothing, and "thanks" after a
  reminder is still "You're welcome."
- **The demo's assistant calls its tools on the on-device model.** Asked "Remind me to water the
  plants at 6 PM", it answered in prose with no card to confirm, and "Not from this app's data" under
  it; asked "How many kilometers is 10 miles?" as a chat's first question, it worked the answer out
  from memory. Its prompt opened "Answer a question asked of an assistant.", which kept the model
  from calling the converter, and its reminder tool's description offered the reminder, which the
  model did in prose instead. It now has no prompt prefix, and the reminder tool's description says
  what it does: "Set a reminder for the user, …". Measured on the Mac, the reminder starter now
  proposes the reminder 10 times in 10, where it did 0 times in 10, and the conversion is called 10
  times in 10, where it was 0 times in 10. No API changes.
- **The demo's assistant converts "What is 100 degrees Fahrenheit in Celsius?" with its converter.**
  Its instructions said to call `convert_units` "to convert an amount between units", and the
  on-device model took a question asking what an amount is in another unit as one to answer from
  memory: "What is 100 degrees Fahrenheit in Celsius?", "What is 10 miles in kilometers?" and "What
  is 5 pounds in kilograms?" called it 0 times in 6 each. The line now names that question too and
  says never to work a conversion out by hand, and the three call it 10 times in 10 through the
  engine, the starter and the reminder as before, with "What's a good name for a houseplant?" and
  "thanks" still calling nothing. "Convert 2 cups to milliliters" is still mostly answered from
  memory (1 in 8, 0 in 8 before). No API changes.

## [0.4.0] - 2026-11-01

Three TipKit tips on the Ask screen, the empty composer one line tall again on iOS and visionOS, and a
demo that hosts both of its domains.

### Added

- Three tips on the Ask screen, shown through the host's TipKit: the menu on a question (Copy, Copy
  answer, Edit & Resend and Ask again), "Don't suggest this" on a starter, and deleting one chat, each
  worded for touch, Apple Vision Pro or the Mac's shortcut menu, in all 25 languages. AskKit never calls
  `Tips.configure`, so a host that doesn't configure TipKit sees none, and one that hides its tips for
  captures with `Tips.hideAllTipsForTesting()` hides these with them. One shows at a time, only while
  its surface is on screen with nothing over it, and goes once the reader has done what it says or
  closed it. No API changes.

### Changed

- **The demo hosts both of its domains**, the library and the assistant, and the reader switches
  between them in the app: a menu in the bar on iOS and iPadOS, the title's menu on visionOS, and
  on the Mac a pop-up in the toolbar and the View menu (⌘1 and ⌘2). The demo opens on the domain it was
  left on, the library the first time. Each domain keeps its own thread and chats, both engines share
  one model seam, and a switch keeps the other domain's turn going. `-askAssistant` still opens on the
  assistant. No API changes.
- **The assistant's bar holds the settings and the domain switch, as the library's does**, with its
  title centred. The bell that listed the reminders the reader added is gone: they are a Reminders
  section of the settings card. "Ask the Assistant" is the assistant's title again, measured centred
  and whole on an iPhone 18 Pro both at rest and while typing. docs/DEMO-PROJECT.md gives the recipes
  for imaging the iPhone screen and the Apple Vision Pro window, beside the Mac window's. No API changes.

### Fixed

- **The empty composer is one line tall again on iOS, iPadOS and visionOS**, with the host's hint on
  that line between the accessory button and the send, where the draft's first line goes. Since 0.3.0
  every host there drew it two lines tall: the hint was set on the field's first text baseline, and
  UIKit's text field, empty, reports that baseline at its top, so the hint sat a whole line above the
  field's, and the capsule was 64 points tall on an iPhone where one line is 48. 0.3.1's one-line hint
  didn't cure it. The hint now goes on the field's first baseline where the field reports one, as the
  Mac's does, and where a typed line's baseline would be where it reports none
  (`AskComposerHintLayout`). The Mac was never affected. No API changes.
- A question's menu (Copy, Copy answer, Edit & Resend and Ask again) opens from anywhere on the
  question. Its words were selectable, and the selection competed for the same press: on the Mac the
  text took a right-click or a Control-click for its own menu of Cut, Copy, Paste and Font, so only
  the few points of padding round the words reached the question's, and on an iPad a long press on
  the words could select one and show the system's Copy, Look Up and Translate instead. A question's
  words are no longer selectable; the menu's Copy copies the whole question.
- On the Mac, the chats sheet opens tall enough to show its chats. It took the size its list asked
  for, which is no height at all, and opened 470 by 158 points with nothing between its bars.

## [0.3.1] - 2026-10-29

The composer's hint no longer makes an empty field two lines tall.

### Changed

- The composer's hint takes one line, ending in an ellipsis when it is longer than the field is wide,
  so an empty field is always one line tall; only a draft grows the capsule. A hint that wrapped held
  the capsule two lines tall on an iPhone before the reader had typed a word. VoiceOver still reads the
  hint whole. Keep a host's hint short enough to show whole.

## [0.3.0] - 2026-10-29

The public API's shape, and fixes across the engine, the stored chats and the screen, many of them for
VoiceOver and the accessibility sizes, and for a reader on gaze, a pointer or a hardware keyboard.

This version breaks the public API, on purpose. Each value has one type (question kinds, lengths of
time, payloads), a value can no longer say two things at once, names say what they are, the enums that
grow are open, and what only AskKit can drive safely, the stored chats' reads and writes and the
generation gate, is no longer a host's to call. "Updating from 0.2" is the list a host works through.
Three more changes a host sees: `AskDomain.perform(_:)` runs off the main actor, the confirmation
card's Confirm and the nothing-to-ask button are black on the system blue and red, and `AskCommands`
puts the newest turn's Copy, Copy answer, Edit & Resend and Ask again in the Mac's File menu.

### Updating from 0.2

Work down the list, building as you go: the compiler finds all but the last step for you.

1. **Names.** `AskAsking` is `AskAnswering`, and its `ask` requirements take `mode:` where they took
   `origin:`. `engine.ask(q, origin: …)` is `engine.ask(q, mode: …)`: `.conversation`, the default,
   where you passed `.typed`, `.starter`, `.followUp` or `.prefilled`, and `.reroll` or `.standalone`
   as before. `AskTurn.Failure.retryable` is `isRetryable`. `AskTurnStats`' `msToFirstTool`,
   `msToFirstWord`, `msToLastWord` and `msTotal` are `timeToFirstTool`, `timeToFirstWord`,
   `timeToLastWord` and `duration`, and `AskOutcome.milliseconds` is `duration`.
2. **`@unknown default`.** End every `switch` of yours over an open enum, `AskError`, `AskTier` and
   `AskTurnEvent` among them (README.md's "Switching over AskKit's enums" lists them), with
   `@unknown default`.
3. **Typed kinds and lengths of time.** `questionKinds` is `[AskQuestionKind]` and `rerollableKinds`
   `Set<AskQuestionKind>`, and a kind is a static member: `AskScenario(expectedKinds: [.count])`,
   `AskAnswer(questionKind: .pick)`. A length of time is a `Duration`: `AskDeadline.run(.seconds(5))`
   where you wrote `run(seconds: 5)`.
4. **Typed payloads, and `try`.** Drop your `JSONEncoder` and hand AskKit the value:
   `try collector.record(payload: value)`, `try AskProposal(…, payload: value)`,
   `try AskAnswer(…, payload: value)` and `try answer.replacing(payload: value)`.
   `mergePayload(as:_:)` takes `try` too, and `deterministicAnswer(for:)` is `async throws`, so write
   `try` there, not `try?`.
5. **The first screen.** Delete `firstScreenPolicy` and `implementsDeterministicAnswer`, and set
   `answersWithoutModel` to true where either said your domain answers without a model. Keep
   `nothingToAskCopy` only if an empty overview should show the nothing-to-ask screen: its presence is
   the policy. Move the button's label out of `AskBrand(nothingToAskActionLabel:)` and its closure out
   of `AskScreen(onNothingAction:)`, into one
   `AskScreen(store: store, nothingToAskAction: AskNothingToAskAction("Add Your First Item") { … })`.
6. **The store, the evaluation and the seam.** Build the store with `AskConversationStore(engine:)`
   and the evaluation with `AskEval(domain:seam:log:)`. Delete every `gate:` argument and any
   `AskGenerationGate` you built: your own on-device generations go through `AskGenerationGate.run`.
   Call `AskThreadStore`, `AskThreadArchive` and `AskFeedbackAttachments` for nothing but their
   initializers and caps, and list the chats with the store's `history`.
7. **States that can't contradict themselves.** Build `AskTierState` with `unavailability:` for a down
   tier, and no `isAvailable:`. Switch over `AskRetryAfter` (`.rateLimited(until:)`,
   `.quotaReached(resetDate:)`), read `outcome.failure?.isUngrounded`, unwrap
   `AskPrivateCloudState.of(_:)`. A `showsDiagnostics: AskDiagnostics.isEnabled` can go: nil, the
   card's default now, follows the switch as the card draws.
8. **What else went.** Read `AskDiagnostics.isTestFlight` on the main actor, and import AskUI where
   you name `AskOrigin`. Drop `AskBrand(shortLabel:)`, `AskStarter(bank:)` and
   `AskFeedbackAttachments.removeAll()`, and store `AskPersistence` and `AskGroundingPolicy` by
   `rawValue`, since neither is `Codable`.
9. **What runs differently**, with no compile error: `store.ask(q, origin: .reroll)` runs as Another
   pick, an empty overview with no `nothingToAskCopy` shows the ready screen, and a
   `deterministicAnswer(for:)` that throws fails the turn.

### Added

- **`AskError.requestNotSupported`**, for a request the model answering can't take: a capability it
  lacks (tool calling, guided generation, reasoning), a generation guide it doesn't support, or prompt
  content it can't process. These were `LanguageModelError`'s three `unsupported…` cases, which fell
  to the retryable `.model(tag:)`. It offers no Try Again and no coaching, is never handed down to the
  other tier, and reads "Couldn't answer that. The model doesn't support what this app asks of it." in
  all 25 languages. Where the photo is what the model can't take (`unsupportedCapability` for
  `vision`, or unsupported content that carries the picture), the turn fails with
  `.photosNotSupported`.
- **`AskConversationStore(engine:)`**, which reads the engine's domain (`AskEngine.domain`, now
  public), so the store can't draw, keep and perform by a second copy of the domain that differs from
  the one the engine answers by. `AskConversationStore(domain:engine:)` is for an `AskAnswering`
  engine of a host's own, which carries no domain.
- **`AskPrompt.fenceTags` and `AskEngine.restartFloor` are public**, read-only: the tag names a tool's
  output must not use, and the 10 s of its deadline a turn that has drawn prose needs left to be asked
  again from the start (house rule 5).
- **`AppleAskSession` builds on watchOS**, so a host's own router can wrap its sessions in it there.
  `AppleModelSeam` is still compiled out on watchOS.

### Changed

- **The public enums that grow are open (`@nonexhaustive`)**: `AskError`, `AskUnavailability`,
  `AskTier`, `AskActivity`, `AskTurnEvent`, `AskReasoningLevel`, `AskGrounding`, `AskDiscard.Reason`,
  `AskRetryAfter`, `AskProposalKind`, `AskProposalOutcome`, `AskOutcome.Miss`, `AskOrigin`,
  `AskStage.Phase`, `AskProposalPhase` and `AskPrivateCloudState`. A host's `switch` over one needs
  `@unknown default`, or it doesn't compile, and a case a later version adds lands there instead of
  breaking the build. The closed ones, `AskTurnMode`, `AskOutcome.Failure`, `AskGroundingPolicy`,
  `AskReplyShape`, `AskEvidencePresentation`, `AskPersistence`, `AskPrivateCloudCompute`,
  `AskFeedback.Sentiment`, `AskChipRow.Kind` and `AskArrival.Kind`, are still switched over case by
  case.
- **Question kinds are a type, `AskQuestionKind`**, so a domain can't misspell one. A kind is a static
  member (`.count`, `.pick`, …), not a `String`: a typo such as `"cuont"` made the model's correct
  count read as `other`, and show tiles. `AskDomain.questionKinds` is `[AskQuestionKind]` and
  `rerollableKinds` `Set<AskQuestionKind>`, and `AskAnswer`, `AskFeedback`, `AskScenario`,
  `AskOutcome` and `AskOutcome.Miss` carry kinds too. `AskQuestionKind(rawValue:)` never fails, and a
  kind is stored as its bare word, so saved chats read back unchanged. The model is offered the same
  eleven words, and the `[feedback]` line and the evaluation's table print them as before.
- **The engine runs a turn in a mode, and the store keeps where its question came from.**
  `AskEngine.ask` takes `mode: AskTurnMode` (`.conversation`, the default; `.reroll`, with Another
  pick's steer at temperature 0.8; `.standalone`, a one-shot that neither reads nor replaces the kept
  conversation) in place of `origin:`. `AskOrigin` moves from AskCore to AskUI with the same name, and
  says only where a question came from: `.typed`, `.starter`, `.followUp`, `.prefilled` or `.reroll`,
  with no `.standalone`, raw value or `Codable`. `AskTurn.origin`, `AskTurn`'s initializer and
  `AskConversationStore.ask(_:origin:)` take AskUI's, and a target that imports AskCore alone no
  longer has the type.
- **The store asks every origin as itself.** `store.ask(q, origin: .reroll)` runs as Another pick,
  hotter and steered away from the last answer's picks, where it was asked as a typed question, and
  leaves the composer's draft, photo and scope where they are.
- **`AskAsking` is `AskAnswering`**, since the conformer answers and the store asks, and its `ask`
  requirements take `mode: AskTurnMode`. `AskTurn.Failure.retryable` is `isRetryable`, its
  initializer's label included, as `AskError.isRetryable` already says it; a thread file's
  `failureIsRetryable` key is unchanged.
- **An evaluation builds its own engine**: `AskEval(domain:seam:log:)`, in place of
  `AskEval(engine:)`. Handed the thread's engine, the evaluation reset it before its first scenario,
  dropping the reader's conversation and warm session and leaving the store's `hasKeptConversation`
  stale. It can share the thread's domain and seam.
- **A payload is your own value, which AskKit encodes as JSON.** `AskCollector.record(payload:)`,
  `AskProposal(…, payload:)`, `AskAnswer(…, payload:)` and `AskAnswer.replacing(payload:)` take your
  value (`some Encodable & Sendable`, or `some Encodable` for a proposal), where they took `Data`, and
  throw the encoder's `EncodingError` for a value that doesn't encode, such as a NaN, and for a
  `Data`, which is a payload already encoded. An oversize payload still makes `record(payload:)`
  return `false`, which a tool can tell the model. `mergePayload(as:_:)` throws for a result that
  doesn't encode, where it returned `false`. A proposal or an answer with no payload takes the
  initializer without one, which doesn't throw. Payloads in chat files 0.2.0 wrote still read back.
- **`AskDomain.deterministicAnswer(for:)` is `async throws`.** A throw fails the turn and asks no
  model: an `AskError` thrown is the turn's own, a `CancellationError` is a stop, and anything else is
  logged by its tag and fails the turn as `AskError.model(tag:)`, which Try Again retries. No tier is
  read, cooled or handed down.
- **A first screen's copy is its policy.** An empty overview shows the nothing-to-ask screen only when
  the brand gives `nothingToAskCopy`, and the ready screen otherwise, whatever the overview counts.
  `AskFirstScreenPolicy` and `AskDomain.firstScreenPolicy` are gone. A domain that doesn't retrieve
  and gives the copy is logged as a mistake when the engine is built, since its default overview is
  always empty; the engine logs five mistakes, where it logged seven.
- **The nothing-to-ask button is one value**: `AskScreen(store:nothingToAskAction:)` takes an
  `AskNothingToAskAction("Add Your First Item") { … }`, its label and what it does together, and the
  screen draws the button exactly when it has one. `AskBrand.nothingToAskActionLabel`,
  `AskScreen(onNothingAction:)` and `AskFirstScreen(policy:onNothingAction:)` are gone;
  `AskFirstScreen` takes `answersWithoutModel:` and `nothingToAskAction:`.
- **A domain says it answers without a model in one word**, `AskDomain.answersWithoutModel`, false by
  default, which keeps the starters and a live composer under the can't-serve screen's reason. It
  replaces `implementsDeterministicAnswer` and the policy's `answersWithoutModel`.
- **Every length of time is a `Duration`.** `AskTurnStats`' `msToFirstTool`, `msToFirstWord`,
  `msToLastWord` and `msTotal` are `timeToFirstTool`, `timeToFirstWord` and `timeToLastWord`, which
  are optional, and `duration`; `AskOutcome.milliseconds` is `duration`; `AppleModelSeam`'s
  `reprobeInterval` and `transportCooldown` are `.seconds(60)`. `AskTurnStats`' `==` compares the
  durations themselves. The `[stream]` line and the evaluation's table print what they did, in whole
  milliseconds under the same headers.
- **A tier's state, a retry-after reading and an evaluation's failure can't contradict themselves.**
  `AskTierState` is available unless it gives a reason: its initializer drops `isAvailable:`, and
  `isAvailable` reads `unavailability == nil`, so a host's own seam passes `unavailability:` for a
  tier that is down. `AskRetryAfter` is an enum, `.rateLimited(until:)` or
  `.quotaReached(resetDate:)`, in place of `date` and `isQuota`. `AskOutcome.failure` is an
  `AskOutcome.Failure`, `.error(AskError)`, `.untyped(tag:)` or `.noAnswer`, whose `description` is
  the text the table printed, and `AskOutcome.isUngrounded` is `failure?.isUngrounded`.
- **The thread store, the archive and the feedback attachments read and write for the store alone.**
  Their reads and writes, `load()`, `save(_:)`, `clear()`, `summaries()`, `entries(for:)`,
  `archive(_:at:)`, `remove(_:)`, `removeAll()`, `save(_:sentiment:at:)` and `urls()`, are `package`:
  the rules that make them safe live in `AskConversationStore`, and a host's own `clear()` could
  delete the only copy of a chat the store held. A host builds the three only to hand them to the
  store, to keep their files in a folder of its own, and reads their caps. It lists the chats through
  the store's `history`, and shares the feedback attachments from `AskPrivateCloudCard`'s diagnostics
  row. What a read of the thread returns, `AskThreadRead`, is `package` too: nothing public returns
  it. A widget that reads the chats from an App Group folder decodes `threads/<id>.json` as
  `[AskThreadEntry<Row>]`. `ci.sh api` prints no break for these, since it counts `package` as API.
- **`AskDiagnostics.isTestFlight` reads StoreKit's app transaction**: true for one StoreKit verified
  as signed in the sandbox, read once a process off the main actor. A Mac TestFlight build turns
  diagnostics on as an iOS one does, so it no longer needs `enabledByApp`. The flag is `@MainActor`,
  where it was a nonisolated `static let`, and observable: false until StoreKit answers, and in a
  Debug build, which never asks. A host reads it on the main actor. A build under App Review most
  likely reads true too; nothing public in 27.2 tells the two apart on every platform.
- **`AskPrivateCloudState.of(_:)` returns nil until the mirror has heard from its seam**, where it
  returned `.serving`, so a host's own settings row can't claim Private Cloud Compute on a build that
  has none.
- **`AskPrivateCloudCard(showsDiagnostics:)` takes a `Bool?`, nil by default**, which reads
  `AskDiagnostics.isEnabled` as the card draws, so the rows appear once StoreKit says this is a
  TestFlight build. A host that passed `AskDiagnostics.isEnabled` leaves the argument out.
- **AskKit builds with Swift 7's `InternalImportsByDefault` and `ImmutableWeakCaptures`, and its own
  code with strict memory safety.** A module is imported `public` only where AskKit's public API names
  it, and nothing is re-exported, so a host's code changes only if it used a member of a module AskKit
  imports without importing that module itself, which `MemberImportVisibility` already refuses. Reduce
  Motion's fades are spelled `AnyTransition(.opacity)`, the same fade.
- **`AskDomain.perform(_:)` runs off the main actor.** The store calls it from a `@concurrent`
  function, as it reads `overview()`, so a `nonisolated` perform no longer runs on the main actor in a
  host built with `NonisolatedNonsendingByDefault`, and `photoThumbnail(for:)` is read the same way. A
  perform that touches main-actor state hops there itself.
- **Confirm and the nothing-to-ask button hold their words to 4.5:1 on the accent**, text's bar rather
  than a glyph's 3:1. On the system blue, #007AFF and the system red they are black, where white was
  3.2 to 4.0:1, and a dark accent keeps white. On visionOS the label is the bordered style's own.
- **`AskCommands` adds the newest turn's Copy, Copy answer, Edit & Resend and Ask again** to the Mac's
  File menu, after Stop: the items of a question's own menu, acting on the newest turn of the focused
  window's thread, with no shortcuts. They are enabled while the thread has a turn, and Copy answer
  once that turn's answer has words.
- **Logging.** `AskOSLogSink` logs routing at notice, where it was info, and the domain mistakes the
  engine finds as it is built are faults.
- **`AskAnswering.recordFeedback`'s `isLatestTurn` is false while diagnostics are off**, and
  `declinedStarters` no longer holds declined follow-ups.
- **An `AskComposer` a host draws outside `AskScreen` puts its keyboard away from the chevron by
  writing its focus binding**, rather than resigning the key window's first responder.
- **The push gate fails when fewer than 1,640 package tests run**, where it was 600, and
  `ci.sh test-ios` when fewer than 1,580 pass, so an over-tight `#if` can no longer compile out a big
  test file unnoticed, such as AskConversationStoreTests' 236 or AskEngineTests' 228.
- **README.md's two Adopt samples are built and run under the package's posture too**, in
  `AskReadmeApproachableTests`, as well as under none in `AskCrossPostureTests`: a host on Xcode's app
  template, with main-actor default isolation and `NonisolatedNonsendingByDefault`, copies code proven
  under its own settings. The cross-posture tests call the public API they hadn't named.
- **The demo builds with Enhanced Security on**: pointer authentication, which adds an arm64e slice on
  a device and the Mac, and the hardened-process entitlements, which take effect in a signed build.
  README's Install tells a host that turns Enhanced Security on to set `iOSPackagesShouldBuildARM64e`,
  `macOSPackagesShouldBuildARM64e` and `visionOSPackagesShouldBuildARM64e` in its workspace settings;
  without them the arm64e slice can't find AskCore and AskUI, and the build fails.

### Removed

- **A generation gate of a host's own.** `AskGenerationGate.init(logSubsystem:)` is gone, and so is
  `gate:` on `AskGenerationGate.run`, `AppleModelSeam.init(status:privateCloudCompute:logSubsystem:)`
  and `AppleModelSeam.make(privateCloudCompute:logSubsystem:)`, and `AskGenerationGate.shared` is no
  longer public: no public API takes a gate, and the gate has no member a host could call. Every
  on-device generation in the process, Ask's and the host's own through `AskGenerationGate.run`, waits
  at the one gate, so none can run beside another. A seam's generation the gate presumes wedged is
  still logged under the seam's `logSubsystem`.
- **`AskDeadline.run(seconds:_:)`.** `run(_:_:)` takes a `Duration`, so `run(seconds: 5)` is
  `run(.seconds(5))`, and the NaN and infinity cases went with the `TimeInterval`. A deadline past
  about 68 years still sets no timer.
- **`AskBrand.shortLabel`** and its initializer's argument, which AskKit never read, and
  **`AskStarter.bank`** and its initializer's argument, which nothing read.
- **`Codable` on `AskPersistence` and `AskGroundingPolicy`**, which nothing encodes: store a
  `rawValue`.
- **`AskFeedbackAttachments.removeAll()`.** The store removes the attachments with their chat.

### Fixed

- **The engine and the seam.**
  - When Private Cloud Compute is held off only by its cooldown and nothing below can serve, Try Again
    asks it again, instead of failing with the on-device model's reason and no Try Again. When its
    day's quota is spent and nothing below can serve, a question fails at once with the quota's line
    and the reset the banner shows, and spends no request; Try Again asks once the quota resets. Either
    way New Chat no longer shows the can't-serve screen for it.
  - A timeout on Private Cloud Compute is an outage: the turn is handed down and the tier cools.
  - A session a host's router answers with on another tier decides the turn's photos and the triage
    of its failures, so an on-device session answering for Private Cloud Compute is sent no photo and
    cools nothing. The grounded retry asks no planner for a domain whose `SearchArguments` is
    `AskNoSearchArguments`.
  - A follow-up no longer starts drawing on a title under four characters that ends the partial, so it
    no longer fails as ungrounded under prose already on screen.
  - An answer a domain gives without a model, and a refined one, are held to the collector's limits.
    The session's tool count, usage and window, and the prewarm's own warm, are read inside the turn's
    deadline.
  - A stopped or timed-out turn holds the generation gate until its on-device generation has returned,
    the refine pass's included, so the next generation can't start beside one still unwinding.
  - An on-device generation of `AppleModelSeam`'s that the generation gate presumes wedged is logged
    under the seam's `logSubsystem`, beside its other lines. A host's own generation through
    `AskGenerationGate.run` is logged under the app's bundle identifier, as before.
  - `AppleModelSeam`'s cooldowns, quota hold and availability cache run on the monotonic clock, and
    hold a reset date a day at most. An on-device language read made while the model was still
    downloading is read again, and overlapping status refreshes can't publish an older reading over
    a newer one.
  - `AskTriage` reads an `AskError` as itself and a cancellation as `.stopped`, bare or inside a
    `ToolCallError`. An `AskEval` run that ends with neither an answer nor an error reads "no answer".
- **The stored chats.**
  - A proposal is carried out only once the reader's yes is on disk. A yes the disk refuses, or whose
    chat ends before it is saved, isn't carried out, and the card says it couldn't be done. An outcome
    a later AskKit wrote reads back as a perform nothing has answered, so its card takes no tap rather
    than offering the action again.
  - An iPhone or iPad app on a Mac and a Mac Catalyst build write without complete file protection, as
    the native Mac build always has, so a chat on a Mac keeps the system's default class,
    CompleteUntilFirstUserAuthentication. On macOS 27.2 complete protection fails every write while
    the Mac is locked, sandboxed or not, and the native Mac build has no moment to try a refused write
    again, so every turn written then would be lost; SECURITY.md and the README say so.
  - A folder or chat index that won't list no longer counts as empty, so Delete All Chats keeps owing
    what it couldn't delete. An earlier chat no longer opens over a chat New Chat couldn't file, and
    the turns asked while such a chat holds the thread's place are kept.
  - File errors are logged by domain and code, rows that no longer decode are counted in the log, and
    no file past 64 MiB is read or written. A per-launch domain retries the feedback attachments it
    couldn't delete.
- **The screen.**
  - Try Again keeps the prose a failed turn had drawn and asks again below it, and doesn't show while a
    question waits to be asked. A question stopped before it was asked goes back to the composer. A
    follow-up and a starter with matching words and id no longer hide each other.
  - A screen built while an answer is streaming, in a second window or a rebuilt split view's detail,
    follows the answer and offers Jump to latest. Putting the keyboard away, as a question starts, from
    Done, the composer's chevron or a tap on the thread, resigns only in the screen's own window, so it
    can't take another window's keyboard, and AskKit no longer reaches for `UIApplication.shared` to
    put it away.
  - The composer's hint wraps to as many lines as the field grows to, four at most, and the capsule
    grows to hold it, so it no longer ends in an ellipsis at the accessibility sizes. The capsule's
    tint is worked out on the accent as the screen resolves it, its High Contrast variant included.
  - At the accessibility sizes the quota and unreadable-chat banners scroll within half the screen
    rather than pushing the thread off it, and the pending photo's glass materializes as it comes and
    goes.
  - The quota's reset names its day: a reset later today as its time, one on a later day as its
    weekday, date and time, and one already past not at all, in the same words on the card and the
    banner.
  - A hardware Return while an input method is composing, typing Japanese, Chinese or Korean, goes to
    the input method to confirm its conversion and sends nothing, on the Mac and on iOS in
    `AskScreen`. The composer could take that Return before the input method had it, as a send or as
    nothing to send, and on iOS, whose draft holds the reading being converted, the send was the
    question unconverted. On visionOS, and on iOS in a composer a host draws outside `AskScreen`, a
    Return is routed as before.
  - The evaluation row runs once per tap: scrolled away and back, or under a page pushed and popped,
    it no longer starts over and spends Private Cloud Compute's quota again. A chat's "when" in the
    list of chats stays current while it's on screen.
  - The thread's follow-up and coaching chips and Try Again are fills rather than glass, so they read
    cleanly under the glass bar. The nothing-to-ask button wears the accent the host handed
    `AskScreen`, not the app's, as the tint its label is judged on, so a host's `.tint` around the
    screen can't put the label on a fill it wasn't checked against.
- **Accessibility.**
  - VoiceOver stays on the turn when Private Cloud Compute hands down or the conversation rolls over,
    and Try Again under prose a failed turn keeps takes it to the wait row of the question asked below.
    A failure, or a proposal's outcome the reader waited on, is heard once: read where VoiceOver's focus
    lands on its line, or announced about a second after it lands where the focus never reached it,
    rather than announced and then read.
  - Opening an earlier chat from the pane beside iPhone Duo's fold keeps VoiceOver on the row tapped,
    which becomes the open chat, and VoiceOver says which chat is opening, from the pane and from the
    sheet. The open chat's check shows under Bold Text too.
  - "Show options" reads at 4.5:1: `.primary` on the settings card and the quota banner, where the
    accent fell short, and semibold on the banner, so it still stands apart from its sentence.
  - The tier caption leading an iPad's bar stops growing at the largest size short of the accessibility
    sizes, and shows the Large Content Viewer past it. Try Again and the confirmation card's buttons
    wrap at the accessibility sizes, and the first screens hide the host's mark from VoiceOver
    themselves.
  - The photo above a question and the pending photo keep their colors under Smart Invert, the pending
    photo's Remove button holds 3:1, and the wait row's separator is translated.
  - On visionOS and under an iPad's pointer, every bare button lights in its own shape as the reader
    looks at it or points at it: the composer's circles and the face's, the chips, the thumbs, the
    evidence line, the pill, the pending photo's Remove, the default tiles, and the chats pane's rows
    and trash. None lights while it is disabled.
  - On the Mac, every glyph-only button shows its label as a help tag.
  - Under Button Shapes, a bare glyph wears a ring in its own color, and a bare line of words is
    underlined: the accessory button and the face's, the thumbs and the chats pane's trash take the
    ring, and the evidence line and the face's line the underline.
- **Scripts.** `scripts/normalize-catalogs.py` writes a catalog whole or not at all, so an interrupted
  run no longer leaves it truncated.
- **The documentation.** The README and `docs/ARCHITECTURE.md` say what this release changed, among
  them that a proposal runs at most once for each yes, and that `starters(overview:window:)`'s
  `window` is a maximum.
- **README and demo.** README.md's sample search lists the whole shelf when no word of the question
  matches, so "How many books do I own?" counts the books instead of calling the shelf empty. It
  matches whole words, ignores one-letter ones and treats digits as words, so "Le Guin" no longer finds
  "Alexander" and "1984" finds *1984*. The demo records only the rows it shows the model, so an
  answer's tiles and the count under it are rows the model read. Its own screens draw secondary text at
  AskKit's contrast, and its sheets close with the system's localized close button. The demo's iOS app
  supports all four orientations on iPad, so its device build no longer warns that every orientation
  must be supported unless the app requires full screen; it stays resizable, with no
  `UIRequiresFullScreen`.

### Security

- **What reaches the prompt.** Every question, and each question a restored thread's recap quotes,
  drops the characters the reader can't see (tag characters, bidi controls and the other invisible
  format characters) before it is clamped. `AskPrompt.clamp` and the question's clamp are idempotent:
  a character the 16-scalar cap cuts no longer joins the character after it or the "…", so clamping a
  field again changes nothing. A photo's label reaches the prompt clamped, redacted and fenced in
  `<rows>`, as titles do.
- **Backups.** A write whose file the system won't exclude from backup fails, and is tried again,
  rather than leaving a chat in a backup.
- **CI.** The setup action fails on a runner that isn't GitHub-hosted, so a change that sends
  pull requests' code to a self-hosted runner shows on its first run.

## [0.2.0] - 2026-10-28

A privacy manifest for AskCore, and a plainer composer that no longer needs Xcode's Metal Toolchain to
build. The public API is unchanged.

### Added

- **A privacy manifest for AskCore.** `AskCore`'s resource bundle carries a `PrivacyInfo.xcprivacy`, so
  an app that embeds AskKit gets a complete privacy report. It declares the two required-reason APIs
  AskCore calls: user defaults for `CA92.1`, read only for the launch's own arguments (`ASK_LIVE_PCC`),
  and the file timestamp for `C617.1`, the modification date of a chat file in the app's own container.
  It declares no tracking and no collected data: AskKit sends nothing to its developer or any third
  party. AskUI calls none of these APIs, and carries no manifest.

### Removed

- **The Glass Rod round the composer.** The spectrum look's clear glass tube of colors round the
  composer's rim, there at rest and drifting while a turn was in flight, was too distracting, and the
  composer was better without it: it is plain glass again, in the accent's tint. A spectrum tints the
  send circle and the streaming caret, on the slot's face too, and nothing else. With the rod went
  AskUI's only Metal shader, so building AskKit no longer needs Xcode's Metal Toolchain.

## [0.1.0] - 2026-10-27

The first public release: a complete Ask screen over Apple's Foundation Models, for any kind of app. A
reader asks in their own words and gets a short answer, from the app's data, through the tools the app
gives the model, or from the model alone where the app allows it. The app implements one protocol,
`AskDomain`, and AskKit supplies the engine (`AskCore`) and the SwiftUI screen (`AskUI`).

It needs Xcode 27.2 or later on a Mac with Apple silicon, Swift 6.4, and Xcode's Metal Toolchain
component (`xcodebuild -downloadComponent MetalToolchain`), since AskUI compiles a Metal shader. Every
platform's deployment target is 27.2. The on-device model needs Apple Intelligence on the reader's
device, and Private Cloud Compute, which is optional, needs Apple's managed entitlement.

### Added

- **`AskCore`, the engine**, with no UI. A domain gives it a brand, tools and instructions; one over the
  app's own rows adds its row type, its search's arguments, an overview and a search, and one whose
  tools read no rows leaves those to their defaults.
  - Private Cloud Compute answers when it can serve and the on-device model when it can't, behind one
    model seam (`AskModelSeam`, which `AppleModelSeam` implements). When Private Cloud Compute goes out
    mid-turn, the turn is handed down once to the on-device model. The seam sends Private Cloud Compute
    nothing unless the host declares the entitlement, and keeps a development build off it unless the
    run opts in (`ASK_LIVE_PCC=1`), so the developer's own daily quota isn't spent.
  - Grounding is the domain's policy (`AskGroundingPolicy`). `.retrieval`, the default, keeps only
    answers grounded in the app's data, and when a first answer read nothing it runs the app's own
    search and asks again (the grounded retry). `.toolCall` keeps answers a tool call grounded, and
    `.notRequired` keeps every answer. Each answer records what grounded it (`AskAnswer.grounding`).
  - Actions the model proposes (`AskProposal`), which the reader confirms on a card before the domain's
    `perform(_:)` carries them out, or which open the app's own editor.
  - The line under an answer is the domain's (`AskDomain.evidence(for:)`): AskKit's count of the rows
    it read, the domain's own words, or no line. An answer nothing grounded says it isn't from the
    app's data.
  - A reply with no tiles, for a domain whose answers never show any (`AskReplyShape.prose`): on the
    device its schema costs 192 tokens of the window where the full reply's costs 704.
  - A conversation that carries from turn to turn, one deadline over the whole turn (the domain's
    hooks, every generation, the grounded retry and the hand-down), and every failure triaged into an
    `AskError` with a line for the reader.
  - Tool calls through `AskToolContext.withToolCall(_:_:)`, fields through `AskPrompt.clamp`, and what
    AskKit composes fenced, with its fence tags redacted in any spelling that compatibility
    decomposition (NFKD) maps to the tag once marks are dropped.
  - `AskLink`, a deep link that prefills the composer and never sends; `AskEngine.answerOnce(_:)`, one
    answer outside the thread, for a Siri intent; and `AskEval`, which runs scenarios through a real
    engine.
- **`AskUI`, the Ask screen** for iOS, macOS and visionOS, and the `AskConversationStore` that drives
  it, which keeps the thread and the earlier chats on disk, where no failed write or interrupted change
  drops a chat.
  - The first screen with the app's starters; the thread, with the wait row, the prose as it streams,
    the app's tiles, the evidence line, the confirmation card and follow-up chips; chat history; the
    composer in the tab bar slot on iOS; menu commands on the Mac (`AskCommands`); and
    `AskPrivateCloudCard` for the app's settings.
  - A host sets its own views with modifiers on `AskScreen(store:)`, and opens a tile's row or a
    hand-off's editor through a class of its own conformed to `AskItemRouter` or `AskDraftRouter`.
  - **The spectrum look**, opt-in: `AskScreen(store:spectrum:)` takes an `AskSpectrum`, such as
    `.aurora`. Its colors light the Glass Rod, a clear glass tube round the composer's rim drawn by a
    Metal shader, there at rest and drifting while a turn is in flight, and the send circle and the
    streaming caret take a gradient of them. Increase Contrast puts the accent back and drops the rod,
    and Reduce Motion holds its colors still.
  - On iPhone Duo's inner display the screen arranges itself around the fold.
- **Strings in 25 languages**, in two String Catalogs, with a check that fails a missing locale, plural
  or placeholder.
- **Five platforms.** Both libraries compile for iOS, macOS, visionOS, tvOS and watchOS, so a host's
  shared package can link them on every platform it ships. The screen shows on iOS, macOS and visionOS.
- **A demo app** for iOS, macOS and visionOS: a library of thirty items behind one search tool, or,
  with `-askAssistant`, an assistant with no rows of its own that converts units and proposes
  reminders. A launch argument sets up each state of the screen, and `-askScriptedAnswer` answers
  without a model.

[Unreleased]: https://github.com/gregyuzik/AskKit/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/gregyuzik/AskKit/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/gregyuzik/AskKit/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/gregyuzik/AskKit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/gregyuzik/AskKit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/gregyuzik/AskKit/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/gregyuzik/AskKit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gregyuzik/AskKit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gregyuzik/AskKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gregyuzik/AskKit/releases/tag/v0.1.0
