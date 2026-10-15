#!/usr/bin/env bash
# Print a repository's default branch by its bare name on stdout, or exit 1
# having printed nothing.
#
# Called as a subprocess by skills/implement-work/scripts/resolve-base.sh,
# tools/resolve-pr-base.sh, tools/resolve-range.sh and
# skills/pr-to-ready/scripts/watch-claude-review.sh -- and by no SKILL.md:
# it is one answer several skills need, and the spec it implements lives in
# skills/implement-work/references/base-branch.md, "## Resolving the default
# branch". Without this paragraph the next reader takes the absent caller for
# an oversight.
#
# The answer is the remote's own HEAD, read live with `git ls-remote
# --symref`. refs/remotes/origin/HEAD is deliberately not read: a clone sets
# it once and never refreshes it, so after the repository renames its default
# branch it keeps naming the old one, and every base-resolving caller would
# decide a base from it with nothing reporting the mistake.
#
# With [repo], the remote read is the configured one whose URL reduces to
# that repository (origin-repo.sh); else origin's URL with its last two
# segments replaced by that repository, which reaches a fork's parent on the
# host and transport the fork uses. One that answers no HEAD there is exit 1,
# and the caller asks a person.
#
# The exit status and the `ref:` line are read together: a failing ls-remote
# prints nothing useful, and a remote whose HEAD is unborn or detached exits 0
# with no `ref:` line -- an empty answer a caller would fetch as
# `git fetch origin -- ''`.
#
# The STOP each caller prints on exit 1 is its own output contract
# (script-conventions.md, STOP contract).
#
# Usage: resolve-default-branch.sh [repo]
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [repo]" >&2
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

REMOTE=origin
if [ -n "${1:-}" ]; then
  WANT="$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')"
  REMOTE=''
  while IFS= read -r r; do
    if [ "$(bash "${SCRIPT_DIR}/origin-repo.sh" "$r" 2>/dev/null)" = "$WANT" ]; then
      REMOTE="$r"
      break
    fi
  done < <(git remote 2>/dev/null)
  if [ -z "$REMOTE" ]; then
    # origin-only checkout (a fork asking for its parent): the inverse of
    # origin-repo.sh's reduction -- swap origin's last two path segments.
    if ! URL="$(git remote get-url origin 2>/dev/null)"; then
      exit 1
    fi
    u="${URL%/*}"
    o="${u##*/}"
    o="${o##*:}"
    if [ -z "$o" ]; then
      exit 1
    fi
    REMOTE="${u%"$o"}${WANT}.git"
  fi
fi

if ! OUT="$(git ls-remote --symref "$REMOTE" HEAD 2>/dev/null)"; then
  exit 1
fi
REF="$(awk -F'\t' '$2 == "HEAD" && $1 ~ /^ref: refs\/heads\// { sub(/^ref: refs\/heads\//, "", $1); print $1; exit }' <<<"$OUT")"
if [ -z "$REF" ]; then
  exit 1
fi
printf '%s\n' "$REF"
