#!/bin/bash
# The checks, tests and builds a change to AskKit has to pass, defined once.
# CI (.github/workflows/ci.yml) runs one step per job, and the push gate
# (scripts/git-hooks/pre-push) runs them in order, cheapest first, so the two
# gates can't drift apart.
#
# usage: scripts/ci.sh [step]
#   checks        shellcheck, actionlint and zizmor, swiftlint, both String
#                 Catalog checks, README's samples against ReadmeDomain.swift and
#                 ReadmeAssistantDomain.swift, and the project file's
#   test          `swift test`, cold, with a minimum pass count and a warning check
#   api           the public API against the newest release tag, less the
#                 breaks .github/api-breakage-allowlist.txt lists
#   test-ios      the package's tests on an iPhone 18 Pro simulator
#   ui-smoke [T]  the demo's UI tests on an iPhone 18 Pro simulator, or only
#                 test T, such as AskScreenSmokeTests/<test>
#   build DEST    the package for one xcodebuild destination
#   builds        the package for all eight destinations
#   destinations  those eight, one per line: CI's build matrix and
#                 scripts/soft-deprecation-check.sh read them
#   demo          the demo's three apps and its UI-test bundle
#   all           checks, test, api, builds and demo: what the push gate runs,
#                 and the default. CI runs each of them as a job.
#
# Needs Xcode 27.2 or later and Python 3, plus
# `brew install swiftlint shellcheck actionlint zizmor`.
#
# Logs, the cold builds' scratch and DerivedData go under $ASKKIT_CI_WORK: by
# default $RUNNER_TEMP/askkit-ci on CI and ${TMPDIR}askkit-ci elsewhere. A step
# that fails names the log to read.
set -euo pipefail

cd "$(dirname "$0")/.."

# SwiftPM checks out dependencies through git, and a GIT_DIR inherited from a
# git hook, which exports one, breaks every checkout before anything compiles.
# The symptom is a pass count of zero, not a checkout error.
unset GIT_DIR GIT_WORK_TREE

say() { echo "ci: $*" >&2; }
fail() { say "$*"; exit 1; }

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# The five platforms on the simulator or the Mac, then the iOS, visionOS and
# watchOS devices. Everything before the device legs builds only the simulator
# side of a `targetEnvironment(simulator)` check, and the device side is what
# every shipping app and every archive compiles. The watchOS leg builds arm64
# alone: at a deployment target of 27 Xcode drops arm64_32, the 32-bit-`Int`
# slice, from `ARCHS_STANDARD`.
#
# The one list: the push gate builds it, and CI's build matrix and
# scripts/soft-deprecation-check.sh read it from `ci.sh destinations`, so a
# destination added here is built by all three.
destinations=(
  "generic/platform=iOS Simulator"
  "generic/platform=macOS"
  "generic/platform=visionOS Simulator"
  "generic/platform=tvOS Simulator"
  "generic/platform=watchOS Simulator"
  "generic/platform=iOS"
  "generic/platform=visionOS"
  "generic/platform=watchOS"
)

# Answered before anything below, which wants a work directory: CI asks for the
# destinations from a Linux runner with no Xcode.
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  destinations)
    [ "$#" -le 1 ] || fail "usage: scripts/ci.sh destinations"
    printf '%s\n' "${destinations[@]}"; exit 0 ;;
esac

if [ -n "${ASKKIT_CI_WORK:-}" ]; then
  work=$ASKKIT_CI_WORK
elif [ -n "${RUNNER_TEMP:-}" ]; then
  work="$RUNNER_TEMP/askkit-ci"
else
  work="${TMPDIR:?set TMPDIR or ASKKIT_CI_WORK}"
  work="${work%/}/askkit-ci"
fi
work=${work%/}
# `test` deletes a directory under this path, so it has to be absolute and at
# least two levels deep: an empty or mistyped variable can't aim that at
# something this script doesn't own.
case "$work" in
  /?*/?*) ;;
  *) fail "ASKKIT_CI_WORK has to be an absolute path two levels deep or more, not '$work'" ;;
esac
derived="$work/derived"
logs="$work/logs"
mkdir -p "$logs"

# Runs a command with its output in a log. On CI the output streams too, since
# the job's console is the only place anyone reads it. Elsewhere it stays in the
# log, so the gate prints only what failed.
logged() { # log command...
  local log=$1
  shift
  if [ -n "${CI:-}" ]; then
    "$@" 2>&1 | tee "$log"
  else
    "$@" >"$log" 2>&1
  fi
}

# Zero warnings, counted by path rather than by diagnostic tag. Not by `[#Tag]`
# suffix, because an untagged warning isn't always the toolchain's: "string
# interpolation produces a debug description for an optional value" carries no
# tag, and it is the `\(error)` class AskKit's rule against describing an error
# exists to catch. Matching what points at AskKit keeps the toolchain's noise
# out without excusing a family of real warnings.
#
# A warning is AskKit's when its line names any of these:
# - a file under Sources/, Tests/ or Demo/, of any kind: a String Catalog, the
#   demo's asset catalog and Info.plist, and the demo's project are spelled by
#   path as a Swift file is;
# - Package.swift;
# - a macro's expansion buffer (`@__swiftmacro_…`), which sits in a temporary
#   directory but is always one of AskKit's own declarations expanded, since
#   nothing else is compiled here;
# - one of AskKit's targets, `(in target '…' from project 'AskKit')` or
#   `'AskKitDemo'`, the way the build system names a warning about a target's
#   settings rather than a file;
# - the package by its SwiftPM identity, the checkout's directory name in lower
#   case, the way SwiftPM names a warning about the manifest ("found 1 file(s)
#   which are unhandled"), whose paths follow on lines of their own.
# What's left names no file or target of AskKit's: a linker or tool line, the
# toolchain's own.
#
# The compiler reports a warning only for a file it compiles, so an incremental
# build shows the warnings of the files that changed, not of the tree. CI's
# builds are cold. The push gate's keep their DerivedData between pushes, so
# there a warning in an untouched file stays hidden until something recompiles
# it.
package_identity=$(basename "$(pwd -P)" | tr '[:upper:]' '[:lower:]')
warnings_in() { # log
  { grep -E 'warning: ' "$1" || true; } | awk -v package="warning: '$package_identity': " '
    /(^|[^[:alnum:]_.-])(Sources|Tests|Demo)\// || /(^|[^[:alnum:]_.-])Package\.swift/ ||
    /@__swiftmacro_/ || /\(in target .* from project .AskKit(Demo)?.\)/ ||
    index($0, package)'
}

no_warnings() { # log what
  local found
  found=$(warnings_in "$1")
  [ -z "$found" ] && return 0
  say "$(printf '%s\n' "$found" | wc -l | tr -d ' ') warning(s) $2 — $1"
  printf '%s\n' "$found" >&2
  return 1
}

# The UDID of an available simulator with this name: one on the runtime that
# matches the selected Xcode's SDK first, a booted one next. By UDID, because
# xcodebuild refuses a `name=` destination that two simulators share, and by
# SDK, because an image can carry newer runtimes than the selected Xcode runs.
simulator() { # name
  local sdk
  sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
  xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
name, sdk = sys.argv[1], sys.argv[2].split(".")[:2]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    version = re.findall(r"\d+", runtime.rsplit(".", 1)[-1])[:2]
    found += [(version != sdk, d["state"] != "Booted", d["udid"]) for d in devices if d["name"] == name]
if not found:
    sys.exit("ci: no available simulator named " + name)
print(min(found)[2])' "$1" "$sdk"
}

step_checks() {
  # Shellcheck first: a gate with a broken conditional doesn't error, it stops
  # gating.
  ./scripts/check-shell.sh
  workflows
  command -v swiftlint >/dev/null 2>&1 || fail "swiftlint isn't installed (brew install swiftlint)"
  # `.swiftlint.yml` disables the size and judgment rules this codebase breaks
  # on purpose, so a clean tree prints nothing and any output is a new
  # violation.
  say "swiftlint --strict"
  swiftlint lint --strict --quiet || fail "swiftlint found violations"
  # A host's own catalog checks never see a package's catalogs, so this is the
  # only thing between AskKit's strings and shipping English to every other
  # locale.
  say "String Catalog completeness"
  python3 -I scripts/check-catalog-completeness.py || fail "the String Catalogs are missing translations"
  # Xcode rewrites a whole catalog in its own serialization when it exports or
  # edits one, and says nothing. That turns a small change into a diff nobody
  # reads, which is where a translation regression hides. Checked rather than
  # fixed, so the step fails loudly instead of rewriting the tree.
  say "String Catalog shape"
  python3 -I scripts/normalize-catalogs.py --check ||
    fail "the String Catalogs aren't in the committed shape: python3 scripts/normalize-catalogs.py restores it"
  # README.md's Adopt section shows ReadmeDomain.swift and
  # ReadmeAssistantDomain.swift, which the package's tests compile and run. An
  # adopter copies the README's code, so what it shows has to be the code that
  # builds, and nothing else compares the two.
  say "README samples"
  python3 -I scripts/check-readme-sample.py ||
    fail "README.md's Adopt code isn't Tests/AskCrossPostureTests/ReadmeDomain.swift and ReadmeAssistantDomain.swift word for word (above)"
  project_files
}

# The workflows, the setup action and Dependabot's config: they decide what CI
# proves, and a pull request's code runs inside them. actionlint checks the
# workflows' syntax and expressions, and ShellCheck's their `run:` scripts.
# zizmor looks for the ways a pull request reaches further than it should: an
# expression spliced into a script, a token left in the checkout, an action
# not pinned to a commit, a write to an environment file, a Dependabot update
# with no cooldown. Offline, so it reads only the files, the push gate's run
# needs no token, and both gates read the same thing.
workflows() {
  command -v actionlint >/dev/null 2>&1 || fail "actionlint isn't installed (brew install actionlint)"
  command -v zizmor >/dev/null 2>&1 || fail "zizmor isn't installed (brew install zizmor)"
  say "actionlint"
  actionlint -config-file .github/actionlint.yaml || fail "actionlint found problems in the workflows (above)"
  say "zizmor"
  zizmor --offline --no-progress --config .github/zizmor.yml .github ||
    fail "zizmor found problems in .github (above): fix them, or ignore one with a reason, as .github/zizmor.yml and the setup action do"
}

# The demo's project is Xcode 27.2's JSON project file, committed, and edited in
# Xcode, by Apple's tools or by hand. Xcode refuses a bundle that holds a
# project.pbxproj beside it ("has multiple project definition files"), which
# `xcodegen generate` would write. The formatter catches a typo'd or duplicate
# key and a comment, which Xcode's next save would drop; loading the project
# catches a dangling reference; neither catches both. A tree with no tracked
# project.xcproj fails too, since the loop would otherwise check nothing.
#
# A file the formatter would rewrite fails with the formatter's diff, since
# `--update` alone isn't a safe fix: a merge that kept both sides of a
# project.xcproj conflict leaves a duplicate key, and the formatter keeps one
# side and drops the other (a lost package or target) without a word. A line
# the diff removes is what it would drop.
project_files() {
  local f p checked=0
  say "the project file"
  while IFS= read -r -d '' f; do
    p=${f%/project.xcproj}
    [ ! -e "$p/project.pbxproj" ] ||
      fail "$p: a project.pbxproj sits beside project.xcproj (a stray xcodegen?), and Xcode refuses the bundle"
    if ! xcrun xcprojformatter --input "$p" | cmp -s - "$f"; then
      xcrun xcprojformatter --input "$p" | diff -u "$f" - >&2 || true
      fail "$p: not in Xcode's canonical form (diff above). Lines may move, but a removed line is a key the formatter drops: a typo, or a merge that kept both sides of a conflict. Fix that by hand, then xcrun xcprojformatter --update $p"
    fi
    xcrun xcodeproj target list -P "$p" >/dev/null || fail "$p: Xcode can't load it"
    checked=$((checked + 1))
  done < <(git ls-files -z '*.xcodeproj/project.xcproj')
  [ "$checked" -gt 0 ] || fail "no tracked project.xcproj to check"
}

# `swift test` exits 0 when no tests run, and most of the suite sits behind
# platform conditions that platform work edits, so one over-tightened `#if`
# could compile out most of the coverage and still pass. Hence the minimum, on
# the tests that ran, a skipped one included. And a warning in a test file shows
# up only in this output, so it is scanned.
#
# Cold, on a scratch path of its own, every time, for the incremental-build
# reason `warnings_in` gives. It takes about 20 seconds while the package has no
# dependencies.
#
# A CI runner image can carry an Xcode newer than its macOS. There the test
# bundles build for the package's macOS floor and then can't load ("built for
# macOS 27.2 which is newer than running OS"), so on GitHub Actions alone, on a
# macOS under the floor, the tests are built and their warnings scanned but not
# run, and the job says so in a warning. The push gate runs them. Anywhere else
# an old macOS fails as it always did.
step_test() {
  local scratch="$work/coldtest" log="$logs/swift-test.log" ran skipped floor host
  rm -rf "$scratch"
  floor=$(sed -nE 's/.*\.macOS\("([0-9.]+)"\).*/\1/p' Package.swift | head -n 1)
  host=$(sw_vers -productVersion)
  if [ "${GITHUB_ACTIONS:-}" = true ] && [ -n "$floor" ] && [ "$host" != "$floor" ] &&
    [ "$(printf '%s\n%s\n' "$host" "$floor" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$host" ]; then
    say "swift build --build-tests (cold): this runner's macOS $host is under the package's macOS $floor, where the tests can't load"
    if ! logged "$log" swift build --build-tests --scratch-path "$scratch"; then
      say "the package tests didn't build — $log"
      { grep -E 'error:' "$log" || true; } | head -20 >&2
      exit 1
    fi
    no_warnings "$log" "from swift build --build-tests" || exit 1
    echo "::warning title=Package tests built, not run::This runner's macOS $host is under AskKit's macOS $floor floor, so the test bundles can't load. The push gate runs them; CI does once the runner image reaches macOS $floor."
    return 0
  fi
  say "swift test (cold)"
  if ! logged "$log" swift test --scratch-path "$scratch"; then
    say "the package tests failed — $log"
    { grep -E 'recorded an issue|error:' "$log" || true; } | head -20 >&2
    exit 1
  fi
  # The tests the test targets' runs report, summed, must reach 1,350. The
  # count is of tests run, a skipped one included, so it is the count of what
  # compiled in: 1,417 when the minimum was set (AskCoreTests 730, AskUITests
  # 629, AskCrossPostureTests 58). The 67 between them leave room for a
  # deliberate deletion, and fail a run that lost more: a big file's
  # over-tight `#if` (AskConversationStoreTests holds 226), or the platform
  # line every AskUI test file opens with, edited across them. A smaller file
  # can still go unnoticed, and so can all of AskCrossPostureTests (1,359
  # would pass). Raise the minimum as the suite grows, or the widening gap
  # lets more of the suite go missing unnoticed.
  ran=$(sed -nE 's/.*Test run with ([0-9]+) tests.*/\1/p' "$log" | awk '{ s += $1 } END { print s + 0 }')
  if [ "$ran" -lt 1350 ]; then
    say "only $ran tests ran (minimum 1,350), so part of the suite likely didn't compile in — $log"
    exit 1
  fi
  # The tests that race the wall clock stand down while the Mac is under load
  # (`racesTheClock`, AskEngineTests.swift), and are in the count above all the
  # same. Said here, so a run that left them out isn't read as one that ran them.
  skipped=$(grep -c 'skipped: "The Mac is under load' "$log" || true)
  if [ "$skipped" -eq 0 ]; then
    say "$ran tests run"
  else
    say "$ran tests run, $skipped of them skipped: they race the wall clock, and the Mac is under load"
  fi
  no_warnings "$log" "from swift test" || exit 1
}

# The public API of AskCore and AskUI against the newest release, so a change to
# what a host compiles against fails here rather than in the host's next bump.
# `swift package diagnose-api-breaking-changes` builds the release tag in a
# checkout of its own and builds the working tree, dumps each library module's
# public API, and fails on what was removed, renamed or changed, not on what was
# added.
#
# AskKit is at 0.x, where a minor release may break the API (CHANGELOG.md), so
# the check makes a break deliberate rather than forbidden: an intended one is
# listed in the allowlist in the pull request that makes it, with its CHANGELOG
# entry, and the list is emptied after each release, whose tag becomes the new
# baseline.
#
# The baseline is the newest `v*` tag in HEAD's history, so the history and the
# tags have to be there: CI checks out with fetch-depth 0.
#
# The digester builds for this Mac, so it compares the API the macOS build
# declares. A public declaration only another platform compiles isn't compared:
# today that is `askComposerSlot`'s iOS pair alone, whose signatures the Mac's
# do-nothing pair repeats.
#
# Its warnings aren't scanned: `test` scans the working tree's, and the
# baseline's belong to a released tree built with a newer Xcode, so they aren't
# this change's to fix. Cold, because the digester keeps the baseline it dumped
# for a tag in its scratch and reuses it, and one an older Xcode dumped isn't
# the next one's to compare with. It takes about 30 seconds.
step_api() {
  local allowlist=.github/api-breakage-allowlist.txt scratch="$work/api" log="$logs/api.log"
  local bad baseline breaks
  [ -f "$allowlist" ] ||
    fail "$allowlist is missing: the API check reads it, and it stays, with only its comments, while no break is intended"
  # The digester runs the list through the C preprocessor before reading it, and
  # when that fails, as it does on a `#` line it takes for a directive, it reads
  # the list as empty and reports every break listed there. A line it reads has
  # to be a whole message, `API breakage: ` included, or it matches nothing.
  bad=$(grep -nvE '^[[:space:]]*($|//|API breakage: )' "$allowlist" || true)
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" >&2
    fail "$allowlist: a line has to be blank, a // comment, or a whole 'API breakage: …' message as this check prints it (above)"
  fi
  baseline=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null) ||
    fail "no release tag (v*) in HEAD's history to compare the API with: fetch the tags (git fetch --tags), and the history, which a shallow clone lacks (on CI, fetch-depth: 0)"
  rm -rf "$scratch"
  say "public API against $baseline"
  if logged "$log" swift package --scratch-path "$scratch" diagnose-api-breaking-changes "$baseline" \
      --breakage-allowlist-path "$PWD/$allowlist"; then
    return 0
  fi
  # The summary's lines, `  💔 API breakage: …`, without the indent and the
  # emoji: the message as the allowlist takes it.
  breaks=$(sed -nE 's/^[[:space:]]+([^[:space:]]+ )?(API breakage: .*)$/\2/p' "$log")
  if [ -z "$breaks" ]; then
    say "the API check failed before it compared anything — $log"
    { grep -E 'error:' "$log" || true; } | head -20 >&2
    exit 1
  fi
  say "the public API breaks against $baseline — $log"
  printf '%s\n' "$breaks" | sed 's/^/  /' >&2
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    printf '%s\n' "$breaks" | sed -e 's/%/%25/g' -e "s/^/::error title=API break against $baseline::/"
  fi
  fail "a break you intend: add each line above, as it stands, to $allowlist, and give the break a CHANGELOG entry. Otherwise put the API back."
}

# The package's tests on the iOS simulator, where every `os(iOS)` leg that
# `swift test` on the Mac never compiles runs. A local run: not in the push
# gate, since a simulator holds one test run at a time and the gate builds
# instead, and not in CI, whose virtual Mac draws views too slowly for the
# suite's deadlines.
#
# The minimum is lower than `step_test`'s, and counts tests passed, read from the
# result bundle, since `-quiet` keeps the per-test lines out of the log. The
# simulator compiles 1,382 of the Mac's 1,417, since 35 in AskUITests compile
# for the Mac alone, and a result bundle from a tree two tests smaller passed
# 1,380: AskCoreTests 728, AskUITests 594, AskCrossPostureTests 58. The twelve
# tests that race the wall clock count as skipped, not passed, while the Mac is
# under load, so 1,320 leaves room for them and for a deliberate deletion.
# Raise it with `step_test`'s.
#
# The bundle keeps each failure, so a failure collects no sysdiagnose: on a CI
# runner that took ten minutes and timed out.
step_test_ios() {
  local sim log="$logs/test-ios.log" results="$work/test-ios.xcresult" passes
  sim=$(simulator "iPhone 18 Pro")
  rm -rf "$results"
  say "AskKit-Package tests on iPhone 18 Pro ($sim)"
  if ! logged "$log" xcodebuild test -scheme AskKit-Package -destination "id=$sim" \
      -derivedDataPath "$derived" -resultBundlePath "$results" -collect-test-diagnostics never \
      -quiet EXCLUDED_ARCHS=x86_64; then
    say "the iOS tests failed — $log"
    { grep -E 'recorded an issue|error:' "$log" || true; } | head -20 >&2
    exit 1
  fi
  passes=$(xcrun xcresulttool get test-results summary --path "$results" --compact |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("passedTests", 0))')
  if [ "$passes" -lt 1320 ]; then
    say "only $passes tests passed on iOS (minimum 1,320), so part of the suite likely didn't compile in — $results"
    exit 1
  fi
  say "$passes tests passed on iOS"
  no_warnings "$log" "testing on iOS" || exit 1
}

# The demo's UI smoke suite on the iOS simulator, which scripts/ui-smoke.sh
# runs. A local run: the push gate and CI build the bundle and don't run it,
# since a simulator UI test would be the flakiest part of a gate every change
# passes. `-project` is spelled out because from the repo root xcodebuild
# otherwise resolves against `Package.swift`, which has no such scheme. Its
# DerivedData and settings are `demo_build`'s, so it starts from what `demo`
# built rather than from a cold DerivedData of Xcode's own.
#
# An argument names one test, `AskScreenSmokeTests/<test>`.
step_ui_smoke() { # [test]
  local sim log="$logs/ui-smoke.log" results="$work/ui-smoke.xcresult" only=()
  sim=$(simulator "iPhone 18 Pro")
  [ -z "${1:-}" ] || only=("-only-testing:AskKitDemoUITests/$1")
  # xcodebuild refuses a result bundle path that already exists.
  rm -rf "$results"
  say "AskKitDemoUITests on iPhone 18 Pro ($sim) — $log"
  if ! logged "$log" xcodebuild test -project Demo/AskKitDemo.xcodeproj -scheme AskKitDemoUITests \
      -destination "platform=iOS Simulator,id=$sim" -derivedDataPath "$derived" \
      -resultBundlePath "$results" ${only[@]+"${only[@]}"} \
      CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64; then
    say "the UI smoke suite failed — $log"
    { grep -E 'error:|Test Case .* failed|XCTAssert' "$log" || true; } | head -20 >&2
    exit 1
  fi
  grep -E 'Test Case .* (passed|failed)' "$log" || true
}

# EXCLUDED_ARCHS on the command line, because `AskKit-Package` is SwiftPM's
# generated scheme, with no project build settings to carry it. Without it each
# simulator build also compiles an x86_64 slice that nothing here runs: the
# simulators on Apple silicon are arm64. Subtracting the arch rather than
# pinning ARCHS=arm64 stays right if ARCHS_STANDARD changes.
step_build() { # destination
  local log
  log="$logs/package-$(printf %s "$1" | tr -c 'A-Za-z0-9' '-').log"
  say "AskKit-Package ($1)"
  if ! logged "$log" xcodebuild build -scheme AskKit-Package -destination "$1" \
      -derivedDataPath "$derived" -quiet CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64; then
    say "AskKit-Package failed for $1 — $log"
    return 1
  fi
  no_warnings "$log" "building for $1"
}

step_builds() {
  local destination failed=0
  for destination in "${destinations[@]}"; do
    step_build "$destination" || failed=1
  done
  [ "$failed" = 0 ] || fail "at least one platform failed to build cleanly"
}

# The demo is the one app here built on AskUI's public API, for each of AskUI's
# three platforms, so it is the earliest sign that a host's integration has
# broken. Its warnings are scanned like the package's, since the project doesn't
# make them errors (docs/DEMO-PROJECT.md). Generic destinations need no
# simulator. `-project` is spelled out because from the repo root xcodebuild
# otherwise resolves against `Package.swift`.
#
# The UI smoke suite is built and not run: a simulator UI test would be the
# flakiest part of a gate every change passes. scripts/ui-smoke.sh runs it.
#
# scripts/soft-deprecation-check.sh builds these four too, from a list of its
# own: a scheme added here goes there as well.
step_demo() {
  local failed=0
  demo_build AskKitDemo_iOS "generic/platform=iOS Simulator" || failed=1
  demo_build AskKitDemo_macOS "generic/platform=macOS" || failed=1
  demo_build AskKitDemo_visionOS "generic/platform=visionOS Simulator" || failed=1
  demo_build AskKitDemoUITests "generic/platform=iOS Simulator" || failed=1
  [ "$failed" = 0 ] || fail "the demo failed to build cleanly"
}

demo_build() { # scheme destination
  local log="$logs/demo-$1.log"
  say "$1 ($2)"
  if ! logged "$log" xcodebuild build -project Demo/AskKitDemo.xcodeproj -scheme "$1" \
      -destination "$2" -derivedDataPath "$derived" -quiet \
      CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64; then
    say "$1 failed — $log"
    return 1
  fi
  no_warnings "$log" "building $1"
}

# A step refuses an argument it doesn't take, rather than running without it:
# `scripts/ci.sh test ios` fails instead of running the Mac's tests.
step=${1:-all}
case "$step" in
  checks|test|api|test-ios|builds|demo|all)
    [ "$#" -le 1 ] || fail "usage: scripts/ci.sh $step" ;;
  ui-smoke)
    [ "$#" -le 2 ] || fail "usage: scripts/ci.sh ui-smoke [TEST]" ;;
  build)
    if [ "$#" -ne 2 ] || [ -z "$2" ]; then fail "usage: scripts/ci.sh build DESTINATION"; fi ;;
esac
case "$step" in
  checks) step_checks ;;
  test) step_test ;;
  api) step_api ;;
  test-ios) step_test_ios ;;
  ui-smoke) step_ui_smoke "${2:-}" ;;
  build) step_build "$2" || exit 1 ;;
  builds) step_builds ;;
  demo) step_demo ;;
  all) step_checks; step_test; step_api; step_builds; step_demo ;;
  *) say "unknown step '$step'"; usage >&2; exit 2 ;;
esac
say "$step: ok"
