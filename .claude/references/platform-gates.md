# Platform gates

AskKit compiles for iOS, macOS, visionOS, tvOS and watchOS. Ask shows only on the first three, but a
host's shared package may build AskCore for tvOS and watchOS as well. A wrong platform gate breaks that
host's build, not AskKit's, so the push gate builds the package for all five.

## The platform gates

- **Foundation Models files** take `#if canImport(FoundationModels) && !os(tvOS)`. Add `&& !os(watchOS)`
  around anything naming `SystemLanguageModel`, since the watch has the framework but no on-device
  model, or `LanguageModelSession.ToolCallError` or `GenerationError`, which the SDK marks unavailable
  there. Settle a symbol by the watchOS SDK's `FoundationModels.swiftinterface`, not by guess.
- **AskUI view files** take `#if os(iOS) || os(macOS) || os(visionOS)`.

## AskCore files

**Inside the Foundation Models platform gate:**
- `AskDomain`, because it names `Tool` and `Generable`, and `AskToolContext`;
- `AskEngine`, `AskReply` and `AskModelSeam`;
- `AskCollector`, `AskContinuation`, `AskTriage` and `AskEval`;
- `AskSession`/`AskSessionBox` and `AskGatedSession`. These are easy to miss because they read like
  plain values;
- `AppleAskSession`, in a file of its own: everything it names is available on watchOS, so a host's
  router can wrap its sessions in it there.

`AppleModelSeam` carries the stricter platform gate, with `&& !os(watchOS)`, and so does everything else
in its file. Inside `AskTriage`, the `SystemLanguageModel.Error` branch and both reads of a
`ToolCallError` (what a tool threw, in `askError(from:tier:)` and `tag(for:)`) sit in
`#if !os(watchOS)`s of their own.

**Ungated:**
- `AskTier`, `AskRow`, `AskAnswer`, `AskMarkdown`, `AskError` and `AskTurnEvent`;
- `AskThreadStore`, `AskThreadArchive` and `AskFeedbackAttachments`;
- `AskProposal`, `AskQuestionPhoto`, `AskLink` and `AskBrand`;
- `AskDeadline`, `AskGenerationGate`, `AskLogSink`, `AskPrompt` and `AskActivity`;
- `AskGroundingPolicy`, `AskEvidencePresentation`, `AskModelStatus`, `AskDiagnostics` and
  `AskDevelopmentPark`.

**`AskProcessEntitlements` is a third shape.** It has no Foundation Models platform gate, but `#if`s of
its own:
- `os(macOS)` for `import Security` and the `SecTask` reads;
- `targetEnvironment(simulator)` for `import MachO` and the section read.

Don't "tidy" it into either list.

## AskUI's exceptions

- `AskArrivals`, the reveal's arithmetic, is ungated and imports Foundation and AskCore: its parse and
  bold marks are `AskMarkdown`'s, an ungated `package` piece of AskCore.
- `AskHostFocus` is ungated and imports Foundation alone.
- `AskWindowHeight` is `#if os(iOS)`.
- `AskCommands` is `#if os(macOS)`.
