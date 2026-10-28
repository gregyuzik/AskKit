#!/bin/bash
# List every deprecated SDK API AskKit's own code references, including the soft
# deprecations the compiler never warns about: `API_TO_BE_DEPRECATED` in headers,
# `deprecated: 100000` in Swift interfaces. It builds everything with indexing on
# into one DerivedData, then crosses the index store's references with the
# availability entries in the SDKs' symbol graphs; the three files in
# scripts/soft-deprecation-check/ do the crossing.
#
# Soft here means deprecated at a version above the SDK's own (27): SDK 27 spells
# that 100000, 10000 or 1000, and the compiler warns about none of them.
#
# What it builds, Debug, into one DerivedData: what the push gate builds (the
# package for each destination `scripts/ci.sh destinations` lists, the demo's
# three apps and its UI-test bundle), plus the package's test targets for macOS,
# the one platform `swift test` runs them on.
#
# usage: scripts/soft-deprecation-check.sh [--reuse] [--keep] [--strict] [--out FILE]
#   --reuse     skip the builds and read the index a --keep run left behind
#   --keep      keep the scratch DerivedData for a later --reuse
#   --strict    exit 1 when the report holds a soft deprecation on any of the
#               five platforms
#   --out FILE  where the report goes; default
#               ${TMPDIR}askkit-softdep/soft-deprecations.txt
#
# Everything it writes lives in ${TMPDIR}askkit-softdep/, outside the repo: DD/
# is the DerivedData (removed at the end unless --keep); symbolgraphs/ is the
# per-platform symbol-graph cache (kept, ~4 GB), which the first run extracts
# in a few minutes; logs/ holds the build logs.
#
# Reading the report: .claude/references/soft-deprecations.md.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
# TMPDIR, the user's own, and no shared fallback: this deletes under the path
# and trusts the symbol-graph cache it finds there.
tmpdir=${TMPDIR:?set TMPDIR}
work="${tmpdir%/}/askkit-softdep"
dd="$work/DD"
sg="$work/symbolgraphs"

reuse=0
keep=0
strict=0
out="$work/soft-deprecations.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --reuse) reuse=1; shift ;;
    --keep) keep=1; shift ;;
    --strict) strict=1; shift ;;
    --out) out=${2:?--out needs a path}; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "soft-deprecation-check: unknown argument $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$work/logs" "$(dirname "$out")"

# name|action|scheme|destination. A `demo-` name builds the demo project; the
# rest build the package's own SwiftPM scheme. The package's destinations are
# ci.sh's one list, read rather than copied, so a destination the push gate and
# CI build is indexed here too. The demo's four schemes are ci.sh's `step_demo`,
# repeated.
destinations=$("$repo/scripts/ci.sh" destinations)
[ -n "$destinations" ] || {
  echo "soft-deprecation-check: scripts/ci.sh destinations listed nothing" >&2
  exit 1
}
builds=()
while IFS= read -r destination; do
  builds+=("package-$(printf %s "$destination" | tr -c 'A-Za-z0-9' '-')|build|AskKit-Package|$destination")
done <<<"$destinations"
builds+=(
  "package-tests|build-for-testing|AskKit-Package|platform=macOS,arch=arm64"
  "demo-ios|build|AskKitDemo_iOS|generic/platform=iOS Simulator"
  "demo-macos|build|AskKitDemo_macOS|generic/platform=macOS"
  "demo-visionos|build|AskKitDemo_visionOS|generic/platform=visionOS Simulator"
  "demo-uitests|build|AskKitDemoUITests|generic/platform=iOS Simulator"
)

if [ "$reuse" -eq 1 ]; then
  [ -d "$dd/Index.noindex/DataStore" ] || {
    echo "soft-deprecation-check: --reuse but no index at $dd (run once with --keep)" >&2
    exit 1
  }
else
  # A fresh DerivedData each time: a stale unit from a deleted file or an
  # earlier checkout would report references the tree no longer has.
  rm -rf "$dd"
  for entry in "${builds[@]}"; do
    IFS='|' read -r name action scheme destination <<<"$entry"
    case "$name" in
      demo-*) where=(-project "$repo/Demo/AskKitDemo.xcodeproj") ;;
      *) where=() ;;
    esac
    log="$work/logs/build-$name.log"
    echo "soft-deprecation-check: $action $scheme ($destination) — log: $log" >&2
    # EXCLUDED_ARCHS=x86_64 for the reason the push gate gives: every simulator
    # here is Apple silicon, and the SwiftPM scheme has no project settings to
    # carry it.
    if ! (cd "$repo" && xcodebuild "$action" \
        ${where[@]+"${where[@]}"} \
        -scheme "$scheme" \
        -destination "$destination" \
        -configuration Debug \
        -derivedDataPath "$dd" \
        COMPILER_INDEX_STORE_ENABLE=YES \
        CODE_SIGNING_ALLOWED=NO \
        EXCLUDED_ARCHS=x86_64 \
        >"$log" 2>&1); then
      echo "soft-deprecation-check: $name failed to build; see $log" >&2
      grep -m 5 ' error: ' "$log" >&2 || true
      exit 1
    fi
  done
fi

# A graph records the compiler that wrote it, and only a cache from this
# compiler (so this Xcode's SDKs) is reused; an older one is dropped and
# re-extracted.
compiler=$(xcrun swift --version 2>&1 | grep -o 'Apple Swift version [^)]*)' || true)
written_by_this_compiler() { # graph file
  [ -n "$compiler" ] && [ -f "$1" ] && head -c 400 "$1" | grep -qF "$compiler"
}
if [ -d "$sg" ] && [ -f "$sg/ios/Swift.symbols.json" ] &&
    ! written_by_this_compiler "$sg/ios/Swift.symbols.json"; then
  echo "soft-deprecation-check: symbol graphs predate $compiler; re-extracting" >&2
  rm -rf "$sg"
fi

echo "soft-deprecation-check: crossing the index with the SDK symbol graphs" >&2
# Exit 3 is a report written with a module graph missing; anything else is no
# report at all.
crossed=0
SG_DIR="$sg" "$repo/scripts/soft-deprecation-check/soft-deprecations.sh" \
  "$dd" "$repo" "$repo/.build/" "$repo/tmp/" /Intermediates.noindex/ /SourcePackages/ >"$out" ||
  crossed=$?
if [ "$crossed" -ne 0 ] && [ "$crossed" -ne 3 ]; then
  echo "soft-deprecation-check: crossing the index failed, so there is no report" >&2
  exit 1
fi

[ "$keep" -eq 1 ] || rm -rf "$dd"

# deprefs.py prints a deprecation as `   deprecated <domain> <version>` (`*` when
# unconditional). A version above the SDK's is soft: 100000, 10000 and 1000 all
# occur in SDK 27 (CGBitmapInfo.alphaInfoMask is 10000), with or without a `.0`.
sdk_major=$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)
symbols=$(grep -c '^## ' "$out" || true)
soft=$(awk -v sdk="$sdk_major" '
  /^## / { s = 0 }
  /^   deprecated (iOS|macOS|tvOS|visionOS|watchOS) [0-9]/ {
    split($3, v, ".")
    if (v[1] + 0 > sdk && !s) { n++; s = 1 }
  }
  END { print n + 0 }' "$out")
skipped=$(grep -rlF --include='*.skip' --include='*.testskip' "Couldn't load module" "$sg" | grep -c . || true)
echo "soft-deprecation-check: $symbols deprecated symbols referenced, $soft soft-deprecated on iOS, macOS, tvOS, visionOS or watchOS; $skipped module graphs skipped as not in their SDK; report: $out" >&2

if [ "$crossed" -eq 3 ]; then
  echo "soft-deprecation-check: incomplete: a module graph failed to extract (above), so its deprecations are missing; run it again" >&2
  exit 1
fi
if [ "$strict" -eq 1 ] && [ "$soft" -gt 0 ]; then
  exit 1
fi
