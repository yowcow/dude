#!/usr/bin/env bash
# Report whether the working tree is clean, by output rather than exit status:
# `git status --porcelain` exits 0 either way, so branching on its exit code
# would hand a dirty tree to the completion gate as clean, and uncommitted
# edits would vanish with the worktree.
# Usage: check-clean.sh
set -euo pipefail

# The flag overrides `status.showUntrackedFiles=no`, under which a tree holding
# only untracked files reads as clean.
STATUS="$(git status --porcelain --untracked-files=normal)"

if [ -z "$STATUS" ]; then
  exit 0
fi

printf '%s\n' "$STATUS"
exit 1
