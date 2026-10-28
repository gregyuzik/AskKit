# Changelog

Every notable change to AskKit is recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While AskKit is at 0.x, a minor version may break the API. A new case in a public enum is a breaking
change, allowed in a 0.x minor version, because it stops a host's exhaustive `switch` compiling.

## [Unreleased]

Fixes across the engine, the stored chats and the screen, many of them for VoiceOver and the
accessibility sizes. Two change what a host sees: `AskDomain.perform(_:)` runs off the main actor, and
the confirmation card's Confirm and the nothing-to-ask button are black on the system blue and red.
The public API is unchanged.

### Changed

- **`AskDomain.perform(_:)` runs off the main actor.** The store calls it from a `@concurrent`
  function, as it reads `overview()`, so a `nonisolated` perform no longer runs on the main actor in a
  host built with `NonisolatedNonsendingByDefault`, and `photoThumbnail(for:)` is read the same way.
  A perform that touches main-actor state hops there itself.
- **Confirm and the nothing-to-ask button hold their words to 4.5:1 on the accent**, text's bar rather
  than a glyph's 3:1. On the system blue, #007AFF and the system red they are black, where white was
  3.2 to 4.0:1, and a dark accent keeps white. On visionOS the label is the bordered style's own.
- **Logging.** `AskOSLogSink` logs routing at notice, where it was info, and the domain mistakes the
  engine finds as it is built are faults.
- **`AskAsking.recordFeedback`'s `isLatestTurn` is false while diagnostics are off**, and
  `declinedStarters` no longer holds declined follow-ups.
- **The push gate fails when fewer than 1,350 package tests run**, where it was 600, and `ci.sh
  test-ios` when fewer than 1,320 pass, so an over-tight `#if` can no longer compile out most of
  AskUI's tests unnoticed.

### Fixed

- **The engine and the seam.**
  - When Private Cloud Compute is held off only by its cooldown or a spent quota and nothing below
    can serve, Try Again asks it again, instead of failing with the on-device model's reason and no
    Try Again, and New Chat no longer shows the can't-serve screen for it.
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
    the native Mac build always has.
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
    follows the answer and offers Jump to latest. Putting the keyboard away resigns only in the
    screen's own window, so it can't take another window's keyboard.
  - The composer's hint wraps to as many lines as the field grows to, four at most, and the capsule
    grows to hold it, so it no longer ends in an ellipsis at the accessibility sizes. The capsule's
    tint is worked out on the accent as the screen resolves it, its High Contrast variant included.
  - At the accessibility sizes the quota and unreadable-chat banners scroll within half the screen
    rather than pushing the thread off it, and the pending photo's glass materializes as it comes and
    goes.
  - The quota's reset names its day: a reset later today as its time, one on a later day as its
    weekday, date and time, and one already past not at all, in the same words on the card and the
    banner.
  - The evaluation row runs once per tap: scrolled away and back, or under a page pushed and popped,
    it no longer starts over and spends Private Cloud Compute's quota again. A chat's "when" in the
    list of chats stays current while it's on screen.
  - The thread's follow-up and coaching chips and Try Again are fills rather than glass, so they read
    cleanly under the glass bar. The nothing-to-ask button is tinted with the color its label is judged
    on, so a host's `.tint` around the screen can't put the label on a fill it wasn't checked against.
- **Accessibility.**
  - VoiceOver stays on the turn when Private Cloud Compute hands down or the conversation rolls over,
    and Try Again under prose a failed turn keeps takes it to the wait row of the question asked below.
    A failure or a proposal's outcome is claimed as heard only once VoiceOver's focus reaches its line.
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
- **Scripts.** `scripts/normalize-catalogs.py` writes a catalog whole or not at all, so an interrupted
  run no longer leaves it truncated.
- **The documentation.** `AskBrand.logSubsystem` and `AskGenerationGate` no longer suggest building a
  generation gate to log under the brand's subsystem, which split the process's one gate:
  `AskGenerationGate.shared` is the gate a host's generations and its seam wait at. The README and
  `docs/ARCHITECTURE.md` say what this release changed, among them that a proposal runs at most once
  for each yes, and that `starters(overview:window:)`'s `window` is a maximum.
- **README and demo.** README.md's sample search lists the whole shelf when no word of the question
  matches, so "How many books do I own?" counts the books instead of calling the shelf empty. It
  matches whole words, ignores one-letter ones and treats digits as words, so "Le Guin" no longer finds
  "Alexander" and "1984" finds *1984*. The demo records only the rows it shows the model, so an
  answer's tiles and the count under it are rows the model read. Its own screens draw secondary text at
  AskKit's contrast, and its sheets close with the system's localized close button.

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

[Unreleased]: https://github.com/gregyuzik/AskKit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/gregyuzik/AskKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gregyuzik/AskKit/releases/tag/v0.1.0
