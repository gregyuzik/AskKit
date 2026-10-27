#!/bin/bash
# Shellcheck every sh/bash script this repo tracks: the push gate
# (scripts/git-hooks/pre-push) and every tracked `*.sh`.
#
# A gate with a broken conditional does not error — it just stops gating, and
# every host that pins this package inherits what it lets through. So
# `scripts/ci.sh checks` runs this first, in CI and in the push gate.
#
# zsh scripts are skipped by shebang, not failed: shellcheck supports
# sh/bash/dash/ksh only. Any that get skipped are named rather than passed
# over silently. Without shellcheck installed it fails, as a missing swiftlint
# fails `ci.sh checks`: passing would report a check it never ran as passed,
# and the push gate would let out a finding CI then fails on.
# ASKKIT_SKIP_SHELLCHECK=1 skips it on purpose, and says so; CI can't skip it.
#
# Paths are read NUL-delimited, so one with a space or a newline is checked
# whole rather than split into names that don't exist and skipped. Bash for
# that: POSIX sh's `read` can't split on NUL.
#
# Standalone: ./scripts/check-shell.sh
set -u

cd "$(git rev-parse --show-toplevel)" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then
        echo "check-shell: shellcheck not installed, and CI can't skip it" >&2
        exit 1
    fi
    if [ "${ASKKIT_SKIP_SHELLCHECK:-}" = 1 ]; then
        echo "check-shell: shellcheck not installed — skipped, since ASKKIT_SKIP_SHELLCHECK=1" >&2
        exit 0
    fi
    echo "check-shell: shellcheck isn't installed (brew install shellcheck);" >&2
    echo "             ASKKIT_SKIP_SHELLCHECK=1 skips it here, and CI still runs it" >&2
    exit 1
fi

fail=0
checked=0
skipped=()

while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    case "$(head -1 "$f")" in
        *zsh*) skipped+=("$f"); continue ;;
    esac
    checked=$((checked + 1))
    shellcheck -x -S style "$f" || fail=1
done < <(git ls-files -z '*.sh'; printf '%s\0' scripts/git-hooks/pre-push)

if [ "${#skipped[@]}" -gt 0 ]; then
    echo "check-shell: skipped (zsh, unsupported by shellcheck): ${skipped[*]}" >&2
fi

if [ "$fail" -ne 0 ]; then
    echo "check-shell: FAILED — fix the findings above, or add a" >&2
    echo "             '# shellcheck disable=SCxxxx' with a reason comment" >&2
    echo "             at the point of use if the finding does not apply." >&2
    exit 1
fi

echo "check-shell: $checked shell files clean" >&2
