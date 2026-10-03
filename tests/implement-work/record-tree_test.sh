#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/record-tree.sh: the tree hash
# it prints for a phase, and that recording leaves the real index alone.
#
# git is not stubbed. What is under test is which content git puts in a tree
# built from the working tree, and a stub would encode the test author's
# belief about that rather than git's behaviour. Each row builds a real
# throwaway repository under $HARNESS_TMP.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# The expected tree is the one committing everything produces. That is the
# property the completion gate relies on: a record taken over round 1's
# still-uncommitted work must equal HEAD^{tree} once step 4 commits it.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; each deliberately broken variant below is one defect wide,
# and the rows it must fail are named:
#   - record `git rev-parse HEAD^{tree}` instead of the working tree:
#     `records-the-working-tree`
#   - run `git add -A` against the real index instead of a copy:
#     `records-the-working-tree: real index untouched`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/record-tree.sh}"

failed=0
total=0

# ---- the working tree is recorded, not HEAD ----------------------------
#
# One of each kind of pending content: a modified tracked file, a staged new
# file, an untracked file, and an ignored file that must stay out.

row_start
W="$(git_repo_scratch content)"
git_repo_init "$W" main
git_repo_commit "$W" .gitignore 'ignored.txt\n' 'ignore'
git_repo_commit "$W" tracked.txt 'committed\n' 'c1'
printf 'edited\n' >"${W}/tracked.txt"
printf 'staged\n' >"${W}/staged.txt"
git -C "$W" add -- staged.txt
printf 'untracked\n' >"${W}/untracked.txt"
printf 'ignored\n' >"${W}/ignored.txt"
BEFORE="$(git -C "$W" status --porcelain)"
run_in "$W" verify
tally check_eq 'records-the-working-tree: real index untouched' \
  "$BEFORE" "$(git -C "$W" status --porcelain)"
git -C "$W" add -A
git -C "$W" commit -q -m 'commit everything'
assert_row 'records-the-working-tree' 0 "$(git -C "$W" rev-parse 'HEAD^{tree}')\n" 0

# ---- argument validation -----------------------------------------------

row_start
W="$(git_repo_scratch args)"
git_repo_init "$W" main
git_repo_commit "$W" tracked.txt 'committed\n' 'c1'
run_in "$W" deploy
assert_row 'unknown-phase' 2 '' 0

row_start
run_in "$W"
assert_row 'no-phase' 2 '' 0

row_start
run_in "$W" verify review
assert_row 'two-phases' 2 '' 0

harness_exit "$failed" "$total"
