#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/check-clean.sh: the exit
# status and the stdout it prints for each state of the working tree.
#
# git is not stubbed. The behaviour under test is git's own -- `git status
# --porcelain` exits 0 whether or not anything is pending, which is the whole
# reason the script reports by output -- and a stub would encode the test
# author's belief about that instead. Each row therefore builds a real
# throwaway repository under $HARNESS_TMP and runs the script from inside it.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; the deliberately broken variant below is one defect wide --
# the guard the header names, removed:
#   - branch on `git status --porcelain`'s exit status instead of its output:
#     `modified-tracked-file`, `untracked-file`, `staged-modification`,
#     `staged-addition`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/check-clean.sh}"

failed=0
total=0

# build_repo <name> -- a repository on branch `main` with one committed file,
# `tracked.txt`, and a clean working tree. Prints its path.
build_repo() {
  local w
  w="$(git_repo_scratch "$1")"
  git_repo_init "$w" main
  git_repo_commit "$w" tracked.txt 'committed\n' 'c1'
  printf '%s\n' "$w"
}

# ---- a clean working tree ----------------------------------------------

row_start
W="$(build_repo clean)"
run_in "$W"
assert_row 'clean-tree' 0 '' 0

# ---- a modified tracked file -------------------------------------------
#
# The first of the four rows the header's mutation must fail. `git status
# --porcelain` exits 0 here, so a script branching on that exit status reports
# a dirty tree as clean, and the completion gate hands off a branch that omits
# these edits.

row_start
W="$(build_repo modified)"
printf 'edited\n' >"${W}/tracked.txt"
run_in "$W"
assert_row 'modified-tracked-file' 1 ' M tracked.txt\n' 0

# ---- an untracked file -------------------------------------------------

row_start
W="$(build_repo untracked)"
printf 'new\n' >"${W}/new.txt"
run_in "$W"
assert_row 'untracked-file' 1 '?? new.txt\n' 0

# ---- staged only, nothing left in the working tree ---------------------
#
# Two shapes, because the porcelain columns differ and only one of them is
# reachable from the untracked row above: a staged modification of a tracked
# file (`M ` -- index column set, worktree column clear) and a staged addition
# of a file that is not in HEAD (`A `, which is what `?? ` becomes once added).

row_start
W="$(build_repo stagedmod)"
printf 'edited\n' >"${W}/tracked.txt"
git -C "$W" add -- tracked.txt
run_in "$W"
assert_row 'staged-modification' 1 'M  tracked.txt\n' 0

row_start
W="$(build_repo stagedadd)"
printf 'new\n' >"${W}/added.txt"
git -C "$W" add -- added.txt
run_in "$W"
assert_row 'staged-addition' 1 'A  added.txt\n' 0

harness_exit "$failed" "$total"
