# Contributing to AskKit

[README.md](README.md) says how an app adopts AskKit. This page says what a change to AskKit has to pass, and how to check it before you open a pull request.

Bugs and feature requests go in issues, which have a form each; a security problem goes through the private form [SECURITY.md](SECURITY.md) describes. Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md). Before you change how the engine or the screen behaves, read the house rules and the rejected designs in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): comments cite the eight rules by number, and a change that breaks one says why. [AGENTS.md](AGENTS.md) has these rules in brief, for a coding agent.

## Toolchain

- **Xcode 27.2 or later**, on a Mac with Apple silicon. Swift 6.4, and every deployment target is 27.2.
- **SwiftLint and ShellCheck**: `brew install swiftlint shellcheck`. `scripts/ci.sh checks` fails without either; `ASKKIT_SKIP_SHELLCHECK=1` skips ShellCheck, and says so, where you can't install it, and CI runs it all the same. CI pins SwiftLint 0.65.1 and ShellCheck 0.11.0 (`.github/actions/setup/action.yml`): when a check passes for you and fails there, compare versions first.
- **Python 3**, for the String Catalog checks.
- **An iPhone 18 Pro simulator**, for the iOS tests and the UI smoke suite, which look for it by name. With none, make one on the iOS runtime of the selected Xcode: `xcrun simctl create "iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2` (`xcrun simctl list runtimes` names the runtimes installed).

## The checks

`scripts/ci.sh` defines every check, test and build once. CI and the optional push gate run its steps:

| Command | What it runs |
|---|---|
| `scripts/ci.sh checks` | ShellCheck, `swiftlint lint --strict`, both String Catalog checks, README.md's Adopt code against `ReadmeDomain.swift` and `ReadmeAssistantDomain.swift` (below), and the demo project's: no `project.pbxproj` beside its `project.xcproj`, the file as `xcrun xcprojformatter` writes it, and loadable by `xcrun xcodeproj`. |
| `scripts/ci.sh test` | `swift test`, cold. It fails when fewer than 600 tests run, a skipped one included, since `swift test` exits 0 when an over-tight `#if` compiles the suite out. |
| `scripts/ci.sh builds` | The `AskKit-Package` scheme for all eight destinations, each generic: iOS, macOS, visionOS, tvOS and watchOS on the simulator or the Mac, then the iOS, visionOS and watchOS devices. `scripts/ci.sh build DESTINATION` builds one, and `scripts/ci.sh destinations` lists them for CI's matrix. |
| `scripts/ci.sh demo` | The demo's three apps and its UI-test bundle. |
| `scripts/ci.sh all` | `checks`, `test`, `builds` and `demo`: the default, and what the push gate runs. |
| `scripts/ci.sh test-ios` | The package's tests on an iPhone 18 Pro simulator, with the same minimum, counted there as tests passed. A local run. |
| `scripts/ci.sh ui-smoke [TEST]` | The demo's UI tests on an iPhone 18 Pro simulator, found as `test-ios` finds it, or only `TEST`, such as `AskScreenSmokeTests/<test>`. `scripts/ui-smoke.sh` runs the same. A local run. |

While you work, `swift test` and `swiftlint lint` are the quick ones. A warning that points at AskKit fails `test`, `test-ios`, every build and `demo`: one naming a file under `Sources/`, `Tests/` or `Demo/` of any kind (catalogs, assets and plists as well as Swift), `Package.swift`, a macro's expansion buffer, or one of AskKit's targets. Logs, result bundles, the cold test's scratch and DerivedData go under `$ASKKIT_CI_WORK` (`${TMPDIR}askkit-ci` unless you set it), and a step that fails names the log to read.

Three runs stay local, and are yours to make when a change calls for them: `test-ios` after a change to an `os(iOS)` leg, since a hosted runner's virtual Mac draws views too slowly for the suite's deadlines; `ui-smoke` after a change to the screen, since CI builds that suite and doesn't run it (it takes about 12 minutes, and holds the simulator until it ends); and `scripts/soft-deprecation-check.sh`, which lists the soft-deprecated SDK APIs AskKit calls, which the compiler never warns about (its first run extracts about 4 GB of symbol graphs).

## CI and the push gate

CI (`.github/workflows/ci.yml`) runs `checks`, `test`, `builds` (as a matrix) and `demo`, one job each, on every pull request and push to `main`, on the runner image's newest Xcode release or release candidate that is 27.2 or later, and on a beta, with a warning, only when neither exists. On a runner whose macOS is under the package's floor, where the test bundles can't load, `test` builds the tests and scans their warnings without running them, and says so in a warning. It skips a change that touches only `docs/`, `.claude/`, `LICENSE`, the issue and pull-request templates and `CODEOWNERS`, or the root's Markdown files other than `README.md`, whose Adopt code the checks compare with `ReadmeDomain.swift` and `ReadmeAssistantDomain.swift`. `main` takes a pull request only once `CI passed` does: that job waits for the others and passes when each passed or skipped itself, so a docs-only pull request still gets the check it needs.

The push gate is optional: `git config core.hooksPath scripts/git-hooks` makes `scripts/git-hooks/pre-push` run `scripts/ci.sh all` before every push. It refuses to run while a file one of its steps reads has uncommitted changes (anything a compiler reaches, and `README.md`, the hook itself and any shell script), or while an untracked file sits where SwiftPM or the demo's project would compile it, ignored or not: only hidden files such as `.DS_Store`, `xcuserdata/` and `Demo/Local.xcconfig` are let through. It proves what is checked out, so push a branch from a checkout of it: `git push origin other-branch` proves the current branch, not `other-branch`. Git ignores a hook that isn't executable, so keep `scripts/git-hooks/pre-push` at mode 100755.

## Strings

Every user-facing string ships in 25 languages, from two String Catalogs: `Sources/AskUI/Resources/Localizable.xcstrings` and `Sources/AskCore/Resources/Localizable.xcstrings`.

- A new key needs a translated unit in all 24 other locales, none left in `needs_review` or empty, or `"shouldTranslate": false` for a string that isn't for translation, such as "Private Cloud Compute".
- A lookup in the package takes `bundle: #bundle`, or it falls through to the host's bundle and shows the key. `Text(verbatim:)` is for anything that isn't words.
- `python3 scripts/check-catalog-completeness.py` checks the locales, plurals and placeholders, and `python3 scripts/normalize-catalogs.py` puts a catalog back in Xcode's serialization before you commit. [TRANSLATION.md](TRANSLATION.md) has the rules and each locale's register.

If you can't write all 24 translations, add the English key and say so in the pull request: the maintainer fills in the rest before merging, and `scripts/ci.sh checks` fails until then.

## Code

- **Concurrency.** AskKit builds with main-actor default isolation and `NonisolatedNonsendingByDefault`, and a host needn't. So every public value type, protocol and extension in AskCore is spelled `nonisolated`, new public API is called from `Tests/AskCrossPostureTests` (a target with no `swiftSettings`, on purpose), and a tool body or file I/O is `@concurrent`.
- **Platforms.** Compile for all five. A Foundation Models file takes `#if canImport(FoundationModels) && !os(tvOS)`, with `&& !os(watchOS)` around `SystemLanguageModel`, and an AskUI view file `#if os(iOS) || os(macOS) || os(visionOS)`.
- **No trailing commas** (SwiftLint's `trailing_comma`, `Package.swift` included), and **Swift Testing** for the package's tests. A change in behaviour comes with a test that fails without it.
- **Comments keep what the code can't say:** the invariant, the failure it prevents, the measurement behind a number. Not its history. A change fixes the comments and docs it makes untrue, and uses the glossary's terms in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Never interpolate a Foundation Models error into text the reader sees**: log `AskTriage.tag(for:)` instead.
- **`Tests/AskCrossPostureTests/ReadmeDomain.swift` and `ReadmeAssistantDomain.swift` are the code README.md shows,** word for word: `scripts/ci.sh checks` runs `python3 -I scripts/check-readme-sample.py`, which fails with a diff when a Swift block in README's Adopt section isn't a run of one file's lines, and fails when a file has no block there. Change them together.

## Pull requests

- Branch from `main`, one topic to a pull request. Pull requests are squash-merged, so write the title as a sentence that says what is true after the change, and put the reasons in the description.
- Say so when a change breaks the API. AskKit is at 0.x, and a new case in a public enum is a breaking change, allowed in a minor version ([CHANGELOG.md](CHANGELOG.md)).
- Change the demo's project in Xcode, or as [docs/DEMO-PROJECT.md](docs/DEMO-PROJECT.md) describes. Don't commit a `Demo/Local.xcconfig`, `xcuserdata/` or logs.
- A contribution is made under the repository's MIT license ([LICENSE](LICENSE)).
