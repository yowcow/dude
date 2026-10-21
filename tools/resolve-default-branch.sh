#!/usr/bin/env bash
# Print a repository's default branch by its bare name on stdout, or exit 1
# having printed nothing.
#
# Called as a subprocess by skills/implement-work/scripts/resolve-base.sh,
# tools/resolve-pr-base.sh and tools/resolve-range.sh, and named by
# pr-to-ready's Step 2-1, which resolves it once and passes the answer to every
# listing of the Claude workflow runs: it is one answer several skills need, and
# the spec it implements lives in
# skills/implement-work/references/base-branch.md, "## Resolving the default
# branch".
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
# host and transport the fork uses.
#
# The exit status and the `ref:` line are read together: a failing ls-remote
# prints nothing useful, and a remote whose HEAD is unborn or detached exits 0
# with no `ref:` line -- an empty answer a caller would fetch as
# `git fetch origin -- ''`.
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
    if ! URL="$(git remote get-url origin 2>/dev/null)"; then
      exit 1
    fi
    url_dir="${URL%/*}"
    owner="${url_dir##*/}"
    owner="${owner##*:}"
    if [ -z "$owner" ]; then
      exit 1
    fi
    REMOTE="${url_dir%"$owner"}${WANT}.git"
  fi
fi

if ! OUT="$(git ls-remote --symref -- "$REMOTE" HEAD 2>/dev/null)"; then
  exit 1
fi
REF="$(awk -F'\t' '$2 == "HEAD" && $1 ~ /^ref: refs\/heads\// { sub(/^ref: refs\/heads\//, "", $1); print $1; exit }' <<<"$OUT")"
if [ -z "$REF" ]; then
  exit 1
fi
printf '%s\n' "$REF"
