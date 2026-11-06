# Contributing to AskKit

This page says what a change to AskKit has to pass, and how to check it before you open a pull request.
Bugs and feature requests go in issues, which have a form each, and a security problem goes through the
private form in [SECURITY.md](SECURITY.md). Everyone taking part follows the
[code of conduct](CODE_OF_CONDUCT.md). Before you change how the engine or the screen behaves, read the
house rules and the rejected designs in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): comments cite the
eight rules by number, and a change that breaks one says why. [AGENTS.md](AGENTS.md) has the rules in
brief, for a coding agent.

## Toolchain

- **Xcode 27.2 or later** on an Apple silicon Mac, Swift 6.4.2, and a deployment target of 27.2
  everywhere.
- **SwiftLint, ShellCheck, actionlint and zizmor**: `brew install swiftlint shellcheck actionlint zizmor`.
  `scripts/ci.sh checks` fails without them; `ASKKIT_SKIP_SHELLCHECK=1` skips ShellCheck, saying so, and
  CI runs it anyway. CI pins SwiftLint 0.65.1, ShellCheck 0.11.0, actionlint 1.7.12 and zizmor 1.31.1
  (`.github/actions/setup/action.yml`): when a check passes for you and fails there, compare versions
  first.
- **Python 3**, for the String Catalog checks.
- **An iPhone 18 Pro simulator**, which the iOS tests and the UI smoke suite look for by name. To make one:
  `xcrun simctl create "iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2`
  (`xcrun simctl list runtimes` names the installed runtimes).

## The checks

`scripts/ci.sh` defines every check, test and build once, and CI and the optional push gate run its
steps:

| Command | What it runs |
|---|---|
| `scripts/ci.sh checks` | ShellCheck, actionlint, zizmor over `.github/` (offline), `swiftlint lint --strict`, both String Catalog checks, README.md's Adopt code against its sample files (below), and the demo's project file: no `project.pbxproj` beside it, as `xcrun xcprojformatter` writes it, and loadable by `xcrun xcodeproj`. |
| `scripts/ci.sh test` | `swift test`, cold. It fails when fewer than 1,640 tests run, skipped ones included, since `swift test` exits 0 when an over-tight `#if` compiles a suite out. A pull request that grows the suite well past that raises it. |
| `scripts/ci.sh api` | `swift package diagnose-api-breaking-changes` against the newest `v*` tag in the branch's history, over the macOS build's public and `package` API, in about 30 seconds. It fails on anything removed, renamed or changed, a new enum case included, unless `.github/api-breakage-allowlist.txt` lists it (below). It can't see a public declaration made `package`, or a change of isolation alone. |
| `scripts/ci.sh builds` | The `AskKit-Package` scheme for eight generic destinations: iOS, macOS, visionOS, tvOS and watchOS on the simulator or the Mac, then the iOS, visionOS and watchOS devices. `scripts/ci.sh build DESTINATION` builds one, and `scripts/ci.sh destinations` lists them for CI's matrix. |
| `scripts/ci.sh demo` | The demo's three apps and its UI-test bundle. |
| `scripts/ci.sh all` | `checks`, `test`, `api`, `builds` and `demo`: the default, and what the push gate runs. |
| `scripts/ci.sh test-ios` | The package's tests on an iPhone 18 Pro simulator, failing under 1,580 passes: lower than `test`'s floor, since some of AskUI's tests compile for the Mac alone and a skipped test doesn't count here. A local run. |
| `scripts/ci.sh ui-smoke [TEST]` | The demo's UI tests on that simulator, or only `TEST`, such as `AskScreenSmokeTests/<test>`; `scripts/ui-smoke.sh` runs the same. A local run. |

While you work, `swift test` and `swiftlint lint` are the quick ones. No test asks a real model: the
engine and the store run against scripted sessions. Any warning that names a file under `Sources/`,
`Tests/` or `Demo/`, `Package.swift`, a macro's expansion or one of AskKit's targets fails the tests,
builds and demo. Logs and DerivedData go under `$ASKKIT_CI_WORK` (`${TMPDIR}askkit-ci` by default), and a
failing step names its log.

Three runs stay local: `test-ios` after a change to an `os(iOS)` leg (a hosted runner draws views too
slowly for the suite's deadlines), `ui-smoke` after a change to the screen (CI builds it without running
it; it takes about 12 minutes), and `scripts/soft-deprecation-check.sh`, which lists the soft-deprecated
SDK APIs AskKit calls, since the compiler never warns about them (its first run extracts about 4 GB of
symbol graphs).

## CI and the push gate

CI (`.github/workflows/ci.yml`) runs `checks`, `test`, `api`, `builds` and `demo`, a job each, on every
pull request and push to `main`, weekly on `main` and on demand (`gh workflow run ci.yml`), on the
image's newest Xcode release or release candidate at 27.2 or later. On a runner whose macOS is under the
package's floor, `test` builds the tests without running them, and says so. A change only to `docs/`,
`.claude/`, `LICENSE`, the GitHub templates and `CODEOWNERS`, or root Markdown other than `README.md`,
skips the jobs, and `CI passed`, the check `main` requires, still reports. `main` also needs CodeQL,
over the workflows and the Python scripts, to report no new high-severity alert.

The push gate is optional: `git config core.hooksPath scripts/git-hooks` makes
`scripts/git-hooks/pre-push` run `scripts/ci.sh all` before every push. It refuses while a file a step
reads has uncommitted changes, or while an untracked file sits where SwiftPM or the demo would compile
it, ignored or not (hidden files, `xcuserdata/` and `Demo/Local.xcconfig` excepted). It proves the
checkout, so push a branch from a checkout of it. Keep the hook at mode 100755: git ignores one that
isn't executable.

## Strings

Every user-facing string ships in 25 languages, from two String Catalogs:
`Sources/AskUI/Resources/Localizable.xcstrings` and `Sources/AskCore/Resources/Localizable.xcstrings`.

- A new key needs a translated unit in all 24 other locales, none left in `needs_review` or empty, or
  `"shouldTranslate": false` for a string that isn't for translation, such as "Private Cloud Compute".
- A lookup in the package takes `bundle: #bundle`, or it falls through to the host's bundle and shows the
  key. `Text(verbatim:)` is for anything that isn't words.
- `python3 scripts/check-catalog-completeness.py` checks the locales, plurals and placeholders, and
  `python3 scripts/normalize-catalogs.py` puts a catalog back in Xcode's serialization before you commit.
  [TRANSLATION.md](TRANSLATION.md) has the rules and each locale's register.

If you can't write all 24 translations, add the English key and say so in the pull request: the
maintainer fills in the rest before merging, and `scripts/ci.sh checks` fails until then.

## Code

- **Concurrency.** AskKit builds with main-actor default isolation and `NonisolatedNonsendingByDefault`,
  and a host needn't. So every public value type, protocol and extension in AskCore is spelled
  `nonisolated`, new public API is called from `Tests/AskCrossPostureTests` (a target with no
  `swiftSettings`, on purpose), and a tool body or file I/O is `@concurrent`.
- **Platforms.** Compile for all five. A Foundation Models file takes
  `#if canImport(FoundationModels) && !os(tvOS)`, with `&& !os(watchOS)` around `SystemLanguageModel`,
  `LanguageModelSession.ToolCallError` and `GenerationError`, and an AskUI view file
  `#if os(iOS) || os(macOS) || os(visionOS)`.
- **No trailing commas** (SwiftLint's `trailing_comma`, `Package.swift` included), and **Swift Testing**
  for the package's tests. A change in behaviour comes with a test that fails without it.
- **Comments keep what the code can't say:** the invariant, the failure it prevents, the measurement
  behind a number, not its history. A change fixes the comments and docs it makes untrue, and uses the
  glossary's terms in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Never interpolate a Foundation Models error into text the reader sees**: log `AskTriage.tag(for:)`.
- **README.md's Adopt code is `Tests/AskCrossPostureTests/ReadmeDomain.swift` and
  `ReadmeAssistantDomain.swift`,** word for word. `python3 -I scripts/check-readme-sample.py`, in
  `scripts/ci.sh checks`, fails with a diff when a Swift block in the Adopt section isn't a run of one
  file's lines, and when a file has no block there, so change them together.
  `Tests/AskReadmeApproachableTests` links to both and builds and runs them again, under the package's own
  settings but strict memory safety, whose main-actor default isolation a host on Xcode's app template has
  too.

## Pull requests

- Branch from `main`, one topic to a pull request. Pull requests are squash-merged, so write the title as
  a sentence saying what is true after the change, and put the reasons in the description, which becomes
  the squash commit's message. `main` takes signed commits only; GitHub signs the squash commit itself, so
  your branch's commits needn't be.
- Say so when a change breaks the API, which a 0.x minor version may do ([CHANGELOG.md](CHANGELOG.md)).
  `scripts/ci.sh api` makes a break deliberate rather than forbidding it:
  - A break you mean goes in `.github/api-breakage-allowlist.txt` in the pull request that makes it, each
    line as the check printed it (`API breakage: …`), with its CHANGELOG entry. A break the check can't
    print, a public declaration made `package` or a change of isolation, gets its entry all the same.
  - A public enum that will grow is `@nonexhaustive`, with a doc paragraph saying it is open, so a host's
    `switch` over it ends in `@unknown default` and a new case is an addition. One whose cases are fixed
    by what it is stays closed, and a new case in it is a break ([docs/ADOPTING.md](docs/ADOPTING.md#switching-over-askkits-enums)
    lists both). The check lists a new case in either kind, so it goes in the allowlist either way,
    under `### Added` for an open enum.
  - The list is emptied after each release, whose tag becomes the new baseline. A comment there starts
    with `//`: the digester reads the file through the C preprocessor, which takes a `#` line for a
    directive and empties the whole list, so the check refuses one.
- Change the demo's project in Xcode, or as [docs/DEMO-PROJECT.md](docs/DEMO-PROJECT.md) describes. Don't
  commit a `Demo/Local.xcconfig`, `xcuserdata/` or logs.
- A contribution is made under the repository's MIT license ([LICENSE](LICENSE)).

## Releases

The maintainer cuts a release with `scripts/release.sh VERSION`, such as `0.2.0`; `--dry-run` checks
everything without tagging.
1. **In a pull request first:** move CHANGELOG.md's Unreleased entries under
   `## [VERSION] - YYYY-MM-DD`, add its link at the foot and point the Unreleased link at the new tag,
   list the new minor version in SECURITY.md's table, and move README.md's `from:` versions and the bug
   form's version to it.
2. **The script** tags `origin/main` once those are there and `CI passed` has passed on that commit,
   starting a run and waiting for it when a docs-only push got none. It signs the tag with your git
   signing key, pushes it, and makes the GitHub release with `gh release create --verify-tag`, its notes
   the CHANGELOG section. If origin refuses the tag, the script deletes it locally too, so a second run
   starts clean.
3. **Afterwards**, in a pull request of its own, empty `.github/api-breakage-allowlist.txt`, keeping its
   comments: the new tag is the API check's baseline.

A release can't change once it's out: rulesets refuse to move or delete a `v*` tag and let only an admin
push one, and releases are immutable, each with GitHub's attestation, which the script checks with
`gh release verify`.
