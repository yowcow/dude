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

# run_in <work-dir> <argv...> -- the SUT reads cwd's repository, so every row
# runs from inside its own repository and returns to the repository root.
run_in() {
  local w="$1"
  shift
  cd "$w"
  run_sut bash "$SUT" "$@"
  cd "$REPO_ROOT"
}

# assert_row <name> <want-exit> <want-stdout>
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if ! check_eq "${name}: gh calls" 0 "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# ---- a clean working tree ----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_repo clean)"
run_in "$W"
assert_row 'clean-tree' 0 ''

# ---- a modified tracked file -------------------------------------------
#
# The first of the four rows the header's mutation must fail. `git status
# --porcelain` exits 0 here, so a script branching on that exit status reports
# a dirty tree as clean, and the completion gate hands off a branch that omits
# these edits.

total=$((total + 1))
stub_dir_new
W="$(build_repo modified)"
printf 'edited\n' >"${W}/tracked.txt"
run_in "$W"
assert_row 'modified-tracked-file' 1 ' M tracked.txt\n'

# ---- an untracked file -------------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_repo untracked)"
printf 'new\n' >"${W}/new.txt"
run_in "$W"
assert_row 'untracked-file' 1 '?? new.txt\n'

# ---- staged only, nothing left in the working tree ---------------------
#
# Two shapes, because the porcelain columns differ and only one of them is
# reachable from the untracked row above: a staged modification of a tracked
# file (`M ` -- index column set, worktree column clear) and a staged addition
# of a file that is not in HEAD (`A `, which is what `?? ` becomes once added).

total=$((total + 1))
stub_dir_new
W="$(build_repo stagedmod)"
printf 'edited\n' >"${W}/tracked.txt"
git -C "$W" add -- tracked.txt
run_in "$W"
assert_row 'staged-modification' 1 'M  tracked.txt\n'

total=$((total + 1))
stub_dir_new
W="$(build_repo stagedadd)"
printf 'new\n' >"${W}/added.txt"
git -C "$W" add -- added.txt
run_in "$W"
assert_row 'staged-addition' 1 'A  added.txt\n'

# ---- argument validation -----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_repo argsone)"
run_in "$W" extra
assert_row 'one-argument' 1 ''

harness_exit "$failed" "$total"
