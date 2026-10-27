#!/bin/bash
# List every deprecated SDK API a build references — including the soft
# deprecations (`deprecated: 100000`) that the compiler never warns about.
#
# It crosses the build's index store (every symbol reference, with file:line:col)
# with symbol graphs extracted from the installed SDKs (every declaration's
# availability). Besides the modules the code imports by name, it reads
# graphs for:
# - the modules code reaches only through a re-export;
# - watchOS, because a host's shared package can build AskCore for the watch;
# - Testing, XCTest and XCUIAutomation, which live in each platform's Developer
#   folder rather than its SDK, so a test file's calls into its framework are
#   checked too.
#
# Written in bash rather than zsh, so scripts/check-shell.sh reads it.
#
# usage: soft-deprecations.sh <derived-data> <source-root> [exclude-substring ...]
#   derived-data  DerivedData of a Debug `xcodebuild build` (it holds Index.noindex/DataStore;
#                 build everything into the same -derivedDataPath to cover every platform)
#   source-root   only references in files under this path are reported
#   exclude       path substrings to skip; default /SourcePackages/ /Intermediates.noindex/
#
# Symbol graphs are cached per platform in $SG_DIR (default: ${TMPDIR}askkit-softdep/symbolgraphs,
# outside the repo, about 4 GB);
# modules come from the `import`s under source-root plus a baseline, and missing ones are extracted
# on demand (~2 min for SwiftUI on first use).
#
# A module an SDK doesn't have (AppKit for iOS, AskKit's own) is cached as skipped, by the one error
# that says so. Any other extraction failure, a crash or a full disk, isn't cached: it is retried on
# the next run, and this one prints its report and exits 3, since a module without a graph is
# checked against nothing and its deprecations go missing from the report.
#
# Reading the report: a row deprecated on only one platform matters only where that code compiles
# (check its #if). Rows at column 1 in files you didn't expect are usually macro expansions
# (e.g. @Generable), which you can't change.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
dd=${1:?derived-data}
root=${2:?source-root}
shift 2
root=$(cd "$root" && pwd -P)/
# No shared fallback such as /private/var/tmp: the cache is trusted, so it has to be this user's.
if [ -z "${SG_DIR:-}" ]; then
  tmp=${TMPDIR:?set TMPDIR or SG_DIR}
  SG_DIR=${tmp%/}/askkit-softdep/symbolgraphs
fi
store=$dd/Index.noindex/DataStore
[ -d "$store" ] || { echo "no index store at $store" >&2; exit 1; }

# The test frameworks, extracted with the platform's Developer search paths by
# `extract` below and kept out of the SDK list.
test_mods=(Testing XCTest XCUIAutomation)

found=(Swift _Concurrency _StringProcessing Foundation Dispatch SwiftUI SwiftUICore CoreFoundation)
# Modules no file imports by name but whose symbols the code calls through a
# re-export (RealityKit -> RealityFoundation, CoreLocation -> _LocationEssentials,
# AVFoundation -> CoreMedia, PhotosUI -> Photos, SwiftUI -> Symbols and
# DeveloperToolsSupport, Foundation -> ObjectiveC). Without them every symbol
# reached that way has no graph to be checked against: about 2,000 a platform
# in one host app's build.
found+=(RealityFoundation _LocationEssentials CoreMedia Photos Symbols DeveloperToolsSupport ObjectiveC)
# [A-Za-z0-9_] because a module name can hold digits: a pattern without them reads
# `import SQLite3` as `SQLite`, which no SDK has.
while IFS= read -r m; do
  found+=("$m")
done < <(cd "$root" && git ls-files -z '*.swift' | xargs -0 grep -hE '^\s*(@preconcurrency |@_implementationOnly |@testable |public |internal |package )?import [A-Za-z_][A-Za-z0-9_]*' 2>/dev/null \
  | sed -E 's/.*import ([A-Za-z_][A-Za-z0-9_]*).*/\1/')

mods=()
while IFS= read -r m; do
  case " ${test_mods[*]} " in
    *" $m "*) ;;
    *) mods+=("$m") ;;
  esac
done < <(printf '%s\n' "${found[@]}" | sort -u)

# The one failure worth caching: the module isn't in this SDK and search paths, which holds until
# the compiler, and so the SDKs, change, and a change empties the cache.
not_here() { # err-file module
  grep -qF "Couldn't load module '$2' in the current SDK and search paths" "$1"
}

failed=()
extract() { # platform-sdk target subdir
  local sdk platform out m
  sdk=$(xcrun --sdk "$1" --show-sdk-path)
  platform=$(xcrun --sdk "$1" --show-sdk-platform-path)
  out=$SG_DIR/$3
  mkdir -p "$out"
  local all=("${mods[@]}")
  for m in "${mods[@]}"; do
    if [ -d "$sdk/System/Library/Frameworks/_${m}_SwiftUI.framework" ]; then
      all+=("_${m}_SwiftUI")
    fi
  done
  # A `.skip` an earlier version cached for any failure at all is retried unless it says the module
  # isn't here.
  for m in "${all[@]}"; do
    if [ -e "$out/$m.symbols.json" ]; then continue; fi
    if [ -e "$out/$m.skip" ] && not_here "$out/$m.skip" "$m"; then continue; fi
    rm -f "$out/$m.skip"
    if xcrun swift-symbolgraph-extract -module-name "$m" -target "$2" -sdk "$sdk" -output-dir "$out" \
         -minimum-access-level public -skip-inherited-docs >/dev/null 2>"$out/$m.err"; then
      rm -f "$out/$m.err"
    elif not_here "$out/$m.err" "$m"; then
      mv "$out/$m.err" "$out/$m.skip"   # not an SDK module here (your own, a package)
    else
      failed+=("$3/$m")
      echo "soft-deprecations: extracting $m for $3 failed, and is retried next run: $out/$m.err" >&2
    fi
  done
  # A cache seeded from a sibling checker's can hold `.skip` for these, written
  # without the Developer search paths, so they keep a marker of their own.
  for m in "${test_mods[@]}"; do
    if [ -e "$out/$m.symbols.json" ]; then continue; fi
    if [ -e "$out/$m.testskip" ] && not_here "$out/$m.testskip" "$m"; then continue; fi
    rm -f "$out/$m.testskip"
    if xcrun swift-symbolgraph-extract -module-name "$m" -target "$2" -sdk "$sdk" \
         -F "$platform/Developer/Library/Frameworks" -I "$platform/Developer/usr/lib" \
         -output-dir "$out" -minimum-access-level public -skip-inherited-docs >/dev/null 2>"$out/$m.err"; then
      rm -f "$out/$m.err"
    elif not_here "$out/$m.err" "$m"; then
      mv "$out/$m.err" "$out/$m.testskip"
    else
      failed+=("$3/$m")
      echo "soft-deprecations: extracting $m for $3 failed, and is retried next run: $out/$m.err" >&2
    fi
  done
}
extract iphonesimulator arm64-apple-ios27.0-simulator ios
extract macosx arm64-apple-macos27.0 mac
extract appletvsimulator arm64-apple-tvos27.0-simulator tv
extract xrsimulator arm64-apple-xros27.0-simulator xr
extract watchsimulator arm64-apple-watchos27.0-simulator watch

# Named, so a module that is skipped everywhere it should be read (SwiftUI, say) shows here
# rather than as a quiet absence from the report.
skips=$(cd "$SG_DIR" && grep -rlF --include='*.skip' --include='*.testskip' "Couldn't load module" . |
  sed -E 's|^\./||; s|\.(test)?skip$||' | sort || true)
echo "soft-deprecations: $(printf '%s' "$skips" | grep -c . || true) module graphs skipped, not in that SDK:" \
  "$(printf '%s' "$skips" | tr '\n' ' ')" >&2

refs=$(mktemp -t refs)
trap 'rm -f "$refs"' EXIT
python3 "$here/idxrefs.py" "$store" "$root" "$@" > "$refs"
python3 "$here/deprefs.py" "$refs" "$SG_DIR"

if [ "${#failed[@]}" -gt 0 ]; then
  echo "soft-deprecations: ${#failed[@]} module graph(s) failed to extract, so the report misses their deprecations: ${failed[*]}" >&2
  exit 3
fi
