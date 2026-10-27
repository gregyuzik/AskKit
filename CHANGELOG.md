# Changelog

Every notable change to AskKit is recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While AskKit is at 0.x, a minor version may break the API. A new case in a public enum is a breaking
change, allowed in a 0.x minor version, because it stops a host's exhaustive `switch` compiling.

## [Unreleased]

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

[Unreleased]: https://github.com/gregyuzik/AskKit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gregyuzik/AskKit/releases/tag/v0.1.0
