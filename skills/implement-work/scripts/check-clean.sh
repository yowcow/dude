#!/usr/bin/env bash
# Report whether the working tree is clean, by output rather than exit
# status: `git status --porcelain` exits 0 whether or not anything is
# pending, so branching on its exit code directly would read a dirty tree as
# clean and let the completion gate hand off a branch that omits uncommitted
# edits — edits that then vanish with the worktree, unrecoverable and
# invisible in the diff, with no trace of what was lost.
# Usage: check-clean.sh
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 1
fi

STATUS="$(git status --porcelain)"

if [ -z "$STATUS" ]; then
  exit 0
fi

printf '%s\n' "$STATUS"
exit 1
