#!/bin/bash
# Releases AskKit: a signed tag on origin/main and the GitHub release made from
# it, once CI has passed on that commit and CHANGELOG.md says what's in it.
#
# usage: scripts/release.sh [--dry-run] VERSION    (such as 0.2.0, with no v)
#
# The tag is the release: SwiftPM resolves a host's dependency by tag. So it is
# made and signed here, with your git signing key, and pushed before the
# release. `gh release create` given a tag that doesn't exist yet makes one on
# GitHub, unsigned, which is how v0.1.0 went out; `--verify-tag` refuses to.
# The protect-release-tags ruleset won't let a v* tag move or go, the
# release-tag-creation ruleset lets only an admin push a new one, and releases
# are immutable, so a release that went out wrong stays out: everything that
# can be checked first is. Once it's out, `gh release verify` checks GitHub's
# attestation of it.
#
# It tags origin/main as fetched, whatever is checked out here, once:
# - CHANGELOG.md there has a `## [VERSION] - YYYY-MM-DD` section, which becomes
#   the release notes, a link for it, and an Unreleased link from the new tag;
# - SECURITY.md there lists VERSION's minor as supported;
# - the tag exists neither here nor on origin;
# - `CI passed` has passed on that commit. A push that changed only docs runs
#   no CI, so for one of those it starts a run (`gh workflow run`) and waits.
# --dry-run does all of that, CI included, and tags nothing.
#
# Afterwards the API allowlist is emptied in a pull request, since the new tag
# is `ci.sh api`'s baseline and the breaks it lists were against the old one.
# It says so when the list has any.
#
# Needs gh, signed in, and git with a signing key: for an SSH key,
# gpg.format ssh, user.signingkey, and gpg.ssh.allowedSignersFile listing the
# key, which `git tag -v` checks the signature against.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { echo "release: $*" >&2; }
fail() { say "$*"; exit 1; }

dry=0
case "${1:-}" in
  -n|--dry-run) dry=1; shift ;;
esac
[ "$#" -eq 1 ] || fail "usage: scripts/release.sh [--dry-run] VERSION, such as 0.2.0"
version=$1
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "'$version' isn't MAJOR.MINOR.PATCH, with no v"
tag="v$version"
minor=${version%.*}

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) ||
  fail "gh can't read the repository (gh auth status)"
git fetch -q origin main --tags
sha=$(git rev-parse --verify "origin/main^{commit}")
short=$(git rev-parse --short "$sha")
say "$tag from origin/main at $short"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  fail "$tag exists here already"
fi
status=0
git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null || status=$?
case "$status" in
  0) fail "$tag exists on origin already" ;;
  2) ;;
  *) fail "git ls-remote couldn't list origin's tags (exit $status)" ;;
esac

# The section's heading, matched whole, with the version's dots taken literally.
changelog=$(git show "$sha:CHANGELOG.md")
heading=$(printf '%s\n' "$changelog" |
  grep -E "^## \[${version//./\\.}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\$" || true)
[ -n "$heading" ] ||
  fail "CHANGELOG.md on origin/main has no '## [$version] - YYYY-MM-DD' section: move Unreleased's entries under one, in a pull request"
printf '%s\n' "$changelog" | grep -qF "[$version]: https://github.com/$repo/" ||
  fail "CHANGELOG.md has no link for [$version] at its foot"
printf '%s\n' "$changelog" | grep -qF "[Unreleased]: https://github.com/$repo/compare/$tag...HEAD" ||
  fail "CHANGELOG.md's [Unreleased] link doesn't compare from $tag"
# The section's body, up to the next version's heading or the links at the
# foot, without the blank lines at either end.
notes=$(printf '%s\n' "$changelog" | awk -v h="$heading" '
  $0 == h { on = 1; next }
  on && (/^## \[/ || /^\[[^]]+\]: /) { exit }
  on { line[++n] = $0 }
  END {
    first = 1; while (first <= n && line[first] ~ /^[[:space:]]*$/) first++
    last = n; while (last >= first && line[last] ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print line[i]
  }')
[ -n "$notes" ] || fail "CHANGELOG.md's [$version] section is empty"

git show "$sha:SECURITY.md" | grep -qE "^\| ${minor//./\\.} \| Yes \|" ||
  fail "SECURITY.md's table doesn't list $minor as supported"

# The count of `CI passed` runs on the commit that succeeded.
ci_passed() {
  gh api "repos/$repo/commits/$sha/check-runs?check_name=CI%20passed" \
    --jq '[.check_runs[] | select(.conclusion == "success")] | length'
}
# The newest CI run on the commit that hasn't finished, if any.
ci_running() { # [event]
  gh run list --workflow ci.yml --commit "$sha" ${1:+--event "$1"} --json databaseId,status \
    --jq '[.[] | select(.status != "completed")][0].databaseId // empty'
}
passed=$(ci_passed) || fail "gh couldn't read $short's checks"
if [ "$passed" -eq 0 ]; then
  run=$(ci_running) || fail "gh couldn't list $short's CI runs"
  if [ -z "$run" ]; then
    say "no CI passed on $short: running CI on main"
    gh workflow run ci.yml --ref main
    for _ in $(seq 1 30); do
      sleep 4
      run=$(ci_running workflow_dispatch) || true
      [ -z "$run" ] || break
    done
    [ -n "$run" ] ||
      fail "the run on $short didn't start in two minutes: main may have moved on (gh run list --workflow ci.yml)"
  fi
  say "waiting for CI run $run"
  gh run watch "$run" --interval 30 --exit-status >/dev/null ||
    fail "CI failed on $short: gh run view $run --log-failed"
  passed=$(ci_passed) || fail "gh couldn't read $short's checks"
  [ "$passed" -gt 0 ] || fail "run $run finished, but no CI passed check passed on $short"
fi
say "CI passed on $short"

if [ "$dry" = 1 ]; then
  say "dry run: $tag would tag $short, with these notes:"
  printf '%s\n' "$notes" >&2
  exit 0
fi

git tag -s "$tag" -m "AskKit $version" "$sha" ||
  fail "git couldn't sign $tag: a signing key is needed (user.signingkey, and gpg.format ssh for an SSH key)"
if ! git tag -v "$tag" >/dev/null 2>&1; then
  git tag -d "$tag" >/dev/null
  fail "$tag's signature doesn't verify here (an SSH key has to be in gpg.ssh.allowedSignersFile), so the tag is deleted, unpushed"
fi
# A push the hooks or the release-tag rulesets refuse leaves the tag here only,
# where a second run would stop at "exists here already", so it goes.
if ! git push origin "refs/tags/$tag"; then
  git tag -d "$tag" >/dev/null
  fail "origin refused $tag (above), so the tag is deleted here too, unpushed: fix that and run this again"
fi

notes_file=$(mktemp -t askkit-release.XXXXXX)
trap 'rm -f "$notes_file"' EXIT
printf '%s\n' "$notes" >"$notes_file"
gh release create "$tag" --verify-tag --title "AskKit $version" --notes-file "$notes_file" ||
  fail "$tag is pushed but has no release: gh release create $tag --verify-tag --title 'AskKit $version' --notes-file <the CHANGELOG section>"

# An immutable release carries GitHub's attestation of its tag, which
# `gh release verify` checks, as an adopter can. It is made with the release,
# and may take a moment to appear. Its absence is said, not fatal: the release
# is out either way.
verified=0
for _ in 1 2 3 4 5 6; do
  if gh release verify "$tag" >/dev/null 2>&1; then verified=1; break; fi
  sleep 5
done
if [ "$verified" = 1 ]; then
  say "gh release verify $tag: the release's attestation checks out"
else
  say "warning: gh release verify $tag found no attestation: check that releases are immutable (Settings, General, Releases)"
fi

if git show "$sha:.github/api-breakage-allowlist.txt" | grep -q '^API breakage: '; then
  say "next: empty .github/api-breakage-allowlist.txt, keeping its comments, in a pull request: $tag is the API check's baseline now"
fi
say "$tag is out"
