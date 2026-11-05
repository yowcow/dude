#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/resolve-since.sh: whether a later
# review round narrows to the commits since the viewer's last review, from the
# `viewer.review.commit` fact and the commit graph alone.
#
# git is real (see ../lib/gitrepo.sh) and gh is never called: every row asserts
# 0 gh calls.
#
# RED record (see tests/README.md): against no script, every row fails
# (`tests/run.sh tests/review-pr/resolve-since_test.sh`: not ok 12/12).
# Mutations, each run as `SUT=<copy under mktemp -d> tests/run.sh <this file>`:
# deleting the base-ancestor guard (step 4) fails 'base merged after the review
# asks' (not ok 1/12); making the rewritten guard ignore exit 128 fails 'review
# commit absent from the clone' (not ok 1/12).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/resolve-since.sh}"

failed=0
total=0

ACME_WIDGETS="$(git_repo_bare acme widgets)"
WORK="$(git_repo_scratch widgets-work)"
git_repo_init "$WORK" main
git_repo_remote "$WORK" origin "$ACME_WIDGETS"

sha() { git -C "$WORK" rev-parse "$1"; }

git_repo_commit "$WORK" f.txt 'b0\n' B0
B0="$(sha HEAD)"
git_repo_checkout "$WORK" topic "$B0"
git_repo_commit "$WORK" f.txt 'c1\n' C1
C1="$(sha HEAD)"
git_repo_commit "$WORK" f.txt 'c2\n' C2
C2="$(sha HEAD)"
git_repo_commit "$WORK" f.txt 'c3\n' C3
C3="$(sha HEAD)"
git_repo_checkout "$WORK" main
git_repo_commit "$WORK" g.txt 'b1\n' B1
B1="$(sha HEAD)"
git_repo_checkout "$WORK" topic2 "$C1"
git_repo_merge "$WORK" main
M="$(sha HEAD)"
git_repo_commit "$WORK" f.txt 'c4\n' C4
C4="$(sha HEAD)"
git_repo_checkout "$WORK" other "$B0"
git_repo_commit "$WORK" h.txt 'x\n' X
X="$(sha HEAD)"
GONE=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef

# facts <pr> <total> <commit>...
facts() {
  local pr="$1" n="$2" c
  shift 2
  {
    printf 'repo=acme/widgets\npr.number=%s\n' "$pr"
    for c in "$@"; do printf 'viewer.review.commit=%s\n' "$c"; done
    printf 'viewer.review.commit.total=%s\n' "$n"
  } | facts_file
}

row_start
run_in "$WORK" 12 "$B0" "$C3"
assert_row 'no facts asks for them' 0 'NEED repo=acme/widgets pr.number=12 viewer.review.commit\n' 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 0)"
assert_row 'no earlier review keeps the whole range' 0 'WHOLE\n' 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 1 "$C1")"
assert_row 'one review narrows to its commit' 0 "SINCE ${C1}\n" 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 2 "$C1" "$C2")"
assert_row 'newest of two reviews bounds the range' 0 "SINCE ${C2}\n" 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 1 "$C3")"
assert_row 'review at head is unchanged' 0 'UNCHANGED\n' 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 1 "$X")"
assert_row "review commit off the head's history" 0 'STOP ask-since-rewritten\n' 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 12 1 "$GONE")"
assert_row 'review commit absent from the clone' 0 'STOP ask-since-rewritten\n' 0

row_start
run_in "$WORK" 12 "$B1" "$C4" --facts "$(facts 12 1 "$C1")"
assert_row 'base merged after the review asks' 0 'STOP ask-since-base-merged\n' 0

row_start
run_in "$WORK" 12 "$B1" "$C4" --facts "$(facts 12 1 "$M")"
assert_row 'base merged before the review still narrows' 0 "SINCE ${M}\n" 0

row_start
run_in "$WORK" 12 "$B0" "$C3" --facts "$(facts 13 1 "$C1")"
assert_row 'facts for another PR stop' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$WORK"
assert_row 'no argument' 2 '' 0

row_start
run_in "$WORK" abc "$B0" "$C3"
assert_row 'non-numeric PR' 2 '' 0

harness_exit "$failed" "$total"
