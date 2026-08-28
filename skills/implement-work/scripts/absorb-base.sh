#!/usr/bin/env bash
# Absorb the base branch into the task branch, so what the completion gate
# verifies is the tree that will be merged rather than the base snapshot the
# branch was cut from. Answers in one line; never aborts, so a conflict is
# left in the tree for the caller to resolve in place.
# Usage: absorb-base.sh <branch> <base>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <branch> <base>" >&2
  exit 1
fi

BRANCH="$1"
BASE="$2"

# Everything below is repo-root-relative -- the paths printed for a conflict,
# and the merge itself -- so the script works from the top level rather than
# from wherever it was invoked.
cd "$(git rev-parse --show-toplevel)"

# The guard is on the branch the caller *believes* it is on, not merely on
# "some branch". Run from a sibling worktree carrying another task's branch,
# an unguarded merge would absorb the base there and still print MERGED: the
# caller reads its own branch as updated, that branch never gets the base, and
# the gate's last verify therefore runs against the pre-merge tree.
if ! CURRENT="$(git symbolic-ref --quiet --short HEAD)"; then
  echo "STOP detached-head"
  exit 0
fi

if [ "$CURRENT" != "$BRANCH" ]; then
  echo "STOP wrong-branch"
  exit 0
fi

# `git merge` refuses a dirty tree only when the dirty path is one it would
# have to overwrite. A dirty path the incoming merge never touches does not
# stop it: measured on git 2.43, the merge exits 0, commits, and leaves the
# modification uncommitted in the tree. So without this guard the answer is
# `MERGED <sha>` over a tree that also carries someone's uncommitted edit --
# the completion gate then verifies that tree and hands it on as the committed
# state, and the edit vanishes with the worktree.
if [ -n "$(git status --porcelain)" ]; then
  echo "STOP dirty-tree"
  exit 0
fi

# This script does its own fetch and reads the ref that fetch wrote; it must
# not trust a tip some earlier fetch left behind. `git fetch` rewrites
# FETCH_HEAD on every call, and within one round of the completion gate
# `review-code`'s own range resolution fetches too -- so an inherited
# FETCH_HEAD names whichever ref was fetched last, and merging that absorbs
# some other branch entirely while still printing MERGED. A
# refs/remotes/origin/<base> left by an earlier round is the same defect one
# step quieter: it is stale, so the base's newer commits are absent and the
# answer is UP-TO-DATE for a base that has moved.
if ! git fetch origin "${BASE}" >&2; then
  echo "STOP base-fetch-failed"
  exit 0
fi

BASE_SHA="$(git rev-parse "refs/remotes/origin/${BASE}")"

# The pre-check is what lets the completion gate terminate. `git merge` exits
# 0 for a base already contained in the branch, so without it every round
# reports MERGED, the gate's "nothing changed" exit is never reachable, and
# the loop spins until its round ceiling hands the user a decision about a
# branch nothing was wrong with.
set +e
git merge-base --is-ancestor "$BASE_SHA" HEAD
ancestor_status=$?
set -e

if [ "$ancestor_status" -eq 0 ]; then
  echo "UP-TO-DATE"
  exit 0
fi

# --is-ancestor answers "no" with exit 1 and reports a real failure -- an
# unreadable object, say -- with something else. Reading those the same way
# would merge on the strength of a question git never answered.
if [ "$ancestor_status" -ne 1 ]; then
  echo "error: git merge-base --is-ancestor failed (exit ${ancestor_status})" >&2
  exit "$ancestor_status"
fi

# The sha is merged rather than the ref, so what lands is exactly what the
# fetch above resolved. `-m` only names it readably in the log; git records
# the same `# Conflicts:` block in MERGE_MSG either way (measured), which is
# what commit-merge.sh reads.
set +e
git merge -m "Merge origin/${BASE} into ${BRANCH}" "$BASE_SHA" >&2
merge_status=$?
set -e

if [ "$merge_status" -eq 0 ]; then
  echo "MERGED ${BASE_SHA}"
  exit 0
fi

# A failed merge is a conflict only when it left unmerged paths behind, and
# neither the exit status nor MERGE_HEAD can stand in for that. Measured on
# git 2.43: unrelated histories exit 128 with no MERGE_HEAD and nothing
# unmerged, while a merge stopped by a failing commit-msg hook exits 1 *with*
# MERGE_HEAD and still nothing unmerged. Reading either as a conflict sends
# the caller to resolve a tree that holds no conflict, and commit-merge.sh
# then sees no unmerged path and commits that empty resolution as though the
# base had been absorbed.
UNMERGED="$(git diff --name-only --diff-filter=U)"

if [ -z "$UNMERGED" ]; then
  echo "STOP merge-failed"
  exit 0
fi

# One line, so the paths are space-joined. A path containing a space would be
# read as two, which fails loudly at the next `open` rather than quietly.
printf 'CONFLICTED %s\n' "$(printf '%s' "$UNMERGED" | tr '\n' ' ')"
