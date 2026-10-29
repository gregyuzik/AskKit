# AskKit

`AskCore` is the engine and `AskUI` the Ask screen; a host supplies its own `AskDomain`. How it works,
the house rules and the glossary: `docs/ARCHITECTURE.md`. What a change has to pass: `CONTRIBUTING.md`.
Deeper notes: `.claude/references/`.

- **Five platforms**, each at a deployment target of 27.2, so an API of 27.2 or earlier takes no
  `#available`. Compile for all five, though Ask shows only on iOS, macOS and visionOS. A host's
  shared package links AskCore on tvOS and watchOS too, so a wrong platform gate breaks the host; the
  push gate builds all five. Foundation Models files take `#if canImport(FoundationModels) && !os(tvOS)`,
  plus `&& !os(watchOS)` around `SystemLanguageModel` and `LanguageModelSession.ToolCallError`
  (`platform-gates.md`).
- **`nonisolated` public API.** Spell every public value type, protocol and extension in AskCore
  `nonisolated`. Otherwise `InferIsolatedConformances` gives it a main-actor conformance that a host
  without AskKit's posture can't use. A host's "call to main actor-isolated … in a synchronous
  nonisolated context" is an AskCore bug. Only `AskCrossPostureTests` catches it (no `swiftSettings`, on
  purpose), and only for API it calls, so add new public API there (`concurrency.md`).
- **`@concurrent`.** The package defaults to the main actor, so tool bodies and file I/O need
  `@concurrent`, or they run on it.
- **Private Cloud Compute's context gate.** A process outside an app's context, such as a command-line
  tool or a test runner, gets an instant `LanguageModelError` −1 (`ModelManagerError 1001`): the context
  gate, not rate limiting and not the entitlement. `swift test` and development builds are parked off
  the tier anyway. Measure it from a signed build launched with `ASK_LIVE_PCC=1` (`pcc.md`).
- **Errors and warnings.** Never interpolate a Foundation Models error (`\(error)`) into user-facing
  text; log `AskTriage.tag(for:)`, never the error. The push gate fails on any `warning:` that names a
  file under `Sources/`, `Tests/` or `Demo/` (catalogs, plists and assets as well as Swift),
  `Package.swift`, a macro's expansion buffer or one of AskKit's targets, untagged ones included.
- **Imports and `unsafe`.** Under `InternalImportsByDefault` an `import` is internal: a module a
  public or `@inlinable` signature names takes `public import`, one only a `package` signature names
  `package import`, and either one left where nothing needs it is a warning, on each platform that
  compiles the file. Strict memory safety makes an unmarked unsafe construct a warning too: mark it
  `unsafe` with a line on why it is sound, or use a safe API (`AnyTransition(.opacity)`, not
  `AnyTransition.opacity`, which SwiftUI declares `nonisolated(unsafe)`).
- **Soft deprecations** (`deprecated: 100000`) never warn, so the push gate can't see them.
  `scripts/soft-deprecation-check.sh` lists every one AskKit calls (`soft-deprecations.md`).
- **Strings.** Package strings need `bundle: #bundle`, or lookups fall through to the host's bundle.
  Every user-facing string ships in 25 languages; `scripts/check-catalog-completeness.py` is the only
  guard. Edit a catalog as TRANSLATION.md's "Editing a catalog" says, and run
  `python3 scripts/normalize-catalogs.py` after.
- **Tool output.** A tool clamps each field with `AskPrompt.clamp` and returns its lines bare: no fence
  of its own and none of AskKit's fence tag names (`AskPrompt.fenceTags`). AskKit fences what it
  composes, and redacts a tag it finds there.
- **The README's samples.** `Tests/AskCrossPostureTests/ReadmeDomain.swift` and
  `ReadmeAssistantDomain.swift` are README.md's Adopt code word for word: `scripts/ci.sh checks` runs
  `scripts/check-readme-sample.py`, which fails with a diff when a Swift block there isn't a run of
  one file's lines, and fails when a file has no block. Change them together.
  `Tests/AskReadmeApproachableTests` holds symlinks to both, so they build and run again under the
  package's posture; edit the files, never the links.
- **The demo.** `Demo/AskKitDemo.xcodeproj` is committed, its project file in Xcode 27.2's JSON
  format (`project.xcproj`). Edit it in Xcode, with `xcrun xcodeproj` or in `Demo/Signing.xcconfig`;
  how, and why its settings are what they are: `docs/DEMO-PROJECT.md`.
- **Simulators.** In hand-run `xcodebuild`, pick simulators by UDID: two devices with one name make
  `name=` ambiguous.
- **Two gates, one set of steps.** CI (`.github/workflows/ci.yml`) runs on every PR and push to main
  (a change only to docs other than `README.md` skips its jobs; `CI passed`, the one check main
  requires, still reports on a pull request), weekly on main and on `gh workflow run ci.yml`; main
  also takes a PR only once CodeQL reports no new high alert. It runs on the image's newest Xcode
  release or release candidate, 27.2 or later (a beta, with a warning, only when neither exists),
  and fails at setup with none, or on a runner that isn't GitHub-hosted. On a runner whose macOS is under the package's floor, `ci.sh test` builds the
  tests without running them, with a warning. It runs `scripts/ci.sh`'s steps one job each, and `scripts/git-hooks/pre-push`
  runs them in order; both scripts stay mode `100755`, since a hook dispatcher skips a non-executable
  hook silently. The push gate refuses an untracked file under `Sources/`, `Tests/` or `Demo/` or at
  `Package.swift`, which SwiftPM would compile into the tree it proves.
  - `scripts/ci.sh checks` runs the cheap ones by hand: shellcheck, actionlint and zizmor (offline,
    over `.github/`; ignore a finding inline with its reason, as the setup action does), `swiftlint
    lint` (`trailing_comma` is on, `Package.swift` included), both catalog checks, the README
    sample's check and the demo project file's checks. Repo settings allow GitHub-owned actions only,
    pinned to a commit.
  - `scripts/ci.sh api` runs `swift package diagnose-api-breaking-changes` against the newest `v*`
    tag in HEAD's history (CI's job checks out with `fetch-depth: 0` for it), on the macOS build's
    public API, in about 30 seconds, and fails on a removal, a rename, a changed signature or a new
    enum case. A break you mean goes in `.github/api-breakage-allowlist.txt` in the same PR, each
    line the check printed as it stands (`API breakage: …`), with its CHANGELOG entry; the list is
    emptied after each release. Comments there start with `//`: the digester runs the file through
    the C preprocessor, and a `#` line empties the list, so the step refuses one. The push gate runs
    it after `test`, and counts the allowlist as part of the tree.
  - `scripts/ci.sh test-ios` and `scripts/ci.sh ui-smoke [TEST]` run in neither: run them by hand
    after changing an `os(iOS)` leg or the screen. CI's virtual Mac draws views too slowly for the
    suite's deadlines.
  - A test that passes only while work beats a deadline on the wall clock takes `.racesTheClock`
    (`AskEngineTests.swift`). It is skipped while the load average is past two a core, and
    `ci.sh test` says how many were.
- **Releases.** `scripts/release.sh VERSION` only (CONTRIBUTING.md's Releases): it signs the tag
  and pushes it before `gh release create --verify-tag`. A `v*` tag and its release can't change
  once out.
- **The house rules.** Read ARCHITECTURE.md's eight house rules before changing engine or screen
  behaviour. Comments cite them by number.
- **iPhone Duo.** Lay out by size class and measured size, never by idiom or orientation. The 27.2
  floor means every build is against an SDK of 27.2 or later, so the Duo draws the screen edge to edge
  and, on its side, puts the bars in a strip at the side of the display (ARCHITECTURE.md's bar strip).
  The fold code's gotchas, how to test on a Duo simulator and what's still open: `iphone-duo.md`.
