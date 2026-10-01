#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/check-tree-records.sh: the one
# line it answers for each state of the records and the working tree.
#
# git is not stubbed, and neither is the recorder: every fixture records with
# the real record-tree.sh, so the two scripts' shared record path cannot drift
# without the all-good row failing. Each row builds a real throwaway
# repository under $HARNESS_TMP.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; each deliberately broken variant below is one defect wide,
# and the rows it must fail are named:
#   - compare the records only to each other, not to HEAD^{tree}:
#     `base-merge-after-records`
#   - compare only the verify record to HEAD^{tree}:
#     `verify-at-new-tree-others-at-old`
#   - drop the clean-tree check: `dirty-tree`
#   - probe with `git status --porcelain -uno`, which skips untracked files:
#     `untracked-file`
#   - check STALE before DIRTY: `dirty-tree-records-over-the-edit`
#   - store under `git rev-parse --git-common-dir` instead of the worktree's
#     own git dir (in both scripts): `records-are-per-worktree`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/check-tree-records.sh}"
RECORD="${REPO_ROOT}/skills/implement-work/scripts/record-tree.sh"

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

# record <work-dir> <phase>... -- run the real recorder there, once per phase.
# A failing record aborts the file under set -e, loudly.
record() {
  local dir="$1" phase
  shift
  for phase in "$@"; do
    (cd "$dir" && bash "$RECORD" "$phase" >/dev/null)
  done
}

# head_tree <work-dir>
head_tree() {
  git -C "$1" rev-parse 'HEAD^{tree}'
}

# ---- all three recorded at HEAD's tree, clean --------------------------

row_start
W="$(build_repo allgood)"
record "$W" verify simplify review
run_in "$W"
assert_row 'all-records-match-head' 0 "OK $(head_tree "$W")\n" 0

# ---- a later round re-records over the earlier one ---------------------

row_start
W="$(build_repo rerecord)"
record "$W" verify simplify review
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
record "$W" verify simplify review
run_in "$W"
assert_row 're-recorded-after-a-change' 0 "OK $(head_tree "$W")\n" 0

# ---- no record at all: the gate never ran (0eecc044) -------------------

row_start
W="$(build_repo norecords)"
run_in "$W"
assert_row 'no-records' 0 'MISSING verify simplify review\n' 0

# ---- review stopped short of clean, so it recorded nothing -------------

row_start
W="$(build_repo noreview)"
record "$W" verify simplify
run_in "$W"
assert_row 'review-not-recorded' 0 'MISSING review\n' 0

# ---- Verify re-ran on the new tree, Simplify and Review did not (54e56aff)

row_start
W="$(build_repo skipped)"
record "$W" simplify review
git_repo_commit "$W" tracked.txt 'review fix\n' 'c2'
record "$W" verify
run_in "$W"
assert_row 'verify-at-new-tree-others-at-old' 0 'STALE simplify review\n' 0

# ---- a base merge commit lands after all three records (absorb MERGED) --
#
# The three records still agree with each other, so only the comparison with
# HEAD^{tree} can catch this.

row_start
W="$(build_repo merged)"
git_repo_checkout "$W" base main
git_repo_commit "$W" base.txt 'from base\n' 'base moves'
git_repo_checkout "$W" main
git_repo_commit "$W" task.txt 'task\n' 'task work'
record "$W" verify simplify review
git_repo_merge "$W" base
run_in "$W"
assert_row 'base-merge-after-records' 0 'STALE verify simplify review\n' 0

# ---- uncommitted edit after the records --------------------------------

row_start
W="$(build_repo dirty)"
record "$W" verify simplify review
printf 'uncommitted\n' >"${W}/tracked.txt"
run_in "$W"
assert_row 'dirty-tree' 0 'DIRTY\n' 0
tally check_eq 'dirty-tree: pending paths on stderr' ' M tracked.txt' "$(cat "$SUT_STDERR")"

# ---- untracked, non-ignored file after the records ---------------------

row_start
W="$(build_repo untracked)"
record "$W" verify simplify review
printf 'new\n' >"${W}/new.txt"
run_in "$W"
assert_row 'untracked-file' 0 'DIRTY\n' 0
tally check_eq 'untracked-file: pending paths on stderr' '?? new.txt' "$(cat "$SUT_STDERR")"

# ---- records taken over an uncommitted edit: DIRTY, not STALE ----------
#
# The records differ from HEAD^{tree} here, so a checker that tests STALE
# before DIRTY answers STALE.

row_start
W="$(build_repo dirty-over-edit)"
printf 'uncommitted\n' >"${W}/tracked.txt"
record "$W" verify simplify review
run_in "$W"
assert_row 'dirty-tree-records-over-the-edit' 0 'DIRTY\n' 0

# ---- records belong to the worktree that made them ---------------------

row_start
W="$(build_repo perworktree)"
record "$W" verify simplify review
L="$(git_repo_scratch perworktree-linked)"
git -C "$W" worktree add -q --detach "$L"
run_in "$L"
assert_row 'records-are-per-worktree' 0 'MISSING verify simplify review\n' 0

# ---- argument validation -----------------------------------------------

row_start
W="$(build_repo args)"
run_in "$W" extra
assert_row 'one-argument' 2 '' 0

harness_exit "$failed" "$total"
