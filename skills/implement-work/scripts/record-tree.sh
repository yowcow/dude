#!/usr/bin/env bash
# Record the tree a completion-gate phase just saw, so check-tree-records.sh
# can refuse a Hand off whose tree that phase did not see last. Overwrites the
# phase's previous record and prints the tree hash it recorded.
# Conventions: references/script-conventions.md.
#
# The tree is the working tree's content -- uncommitted edits and non-ignored
# untracked files included -- not HEAD's. In the first round the execution
# method's changes are still uncommitted when Verify runs; recording HEAD
# would leave every first-round record stale once step 4 commits that very
# content, forcing a round the gate's table does not ask for.
#
# It is hashed through a throwaway copy of the index. `git add -A` on the real
# index would stage everything, and step 4 would then commit whatever was
# lying in the tree -- the files it must account for first -- with nothing in
# `git status` to show they had been swept in. A copy rather than a fresh
# `read-tree HEAD` keeps the stat cache, so unchanged files are not rehashed.
#
# The record lives in this worktree's own git dir (--absolute-git-dir, not the
# common dir): outside the tree, so neither check-clean.sh nor a commit sees
# it, and a sibling worktree's records never answer for this one. The path is
# shared with check-tree-records.sh.
# Usage: record-tree.sh verify|simplify|review
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 verify|simplify|review" >&2
  exit 2
fi

case "$1" in
  verify | simplify | review) ;;
  *)
    echo "Usage: $0 verify|simplify|review" >&2
    exit 2
    ;;
esac

RECORD_DIR="$(git rev-parse --absolute-git-dir)/dude-completion-gate"
INDEX="$(git rev-parse --git-path index)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$INDEX" "${TMP}/index"
GIT_INDEX_FILE="${TMP}/index" git add -A
TREE="$(GIT_INDEX_FILE="${TMP}/index" git write-tree)"

mkdir -p "$RECORD_DIR"
printf '%s\n' "$TREE" >"${RECORD_DIR}/$1"
printf '%s\n' "$TREE"
