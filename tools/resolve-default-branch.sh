#!/usr/bin/env bash
# Print a repository's default branch by its bare name on stdout, or exit 1
# having printed nothing. Shared by resolve-base.sh, resolve-pr-base.sh and
# resolve-range.sh, and named by pr-to-ready's Step 2-1: do not delete as
# unreferenced. Spec: skills/implement-work/references/base-branch.md,
# "## Resolving the default branch".
#
# The answer is the remote's own HEAD, read live with `git ls-remote --symref`:
# refs/remotes/origin/HEAD goes stale after a default-branch rename and would
# resolve every base from the old name with nothing reporting it. A failing
# ls-remote and a HEAD with no `ref:` line both yield no answer. With [repo],
# the read reaches that repository on the fork's host and transport.
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
