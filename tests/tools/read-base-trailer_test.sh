#!/usr/bin/env bash
# Table test for tools/read-base-trailer.sh: which trailer the scan takes from
# the revs it was given, and the one line it prints for each answer the
# prerequisite's facts can give. It reads facts and git only: every row
# asserts 0 gh calls, and stubs none.
#
# git is not stubbed. Which commits the scan reaches is the point -- the revs
# arrive from the caller and go straight to `git log` -- and a git stub would
# encode the test author's belief about that range rather than git's own
# behaviour, the same reason tests/tools/resolve-pr-base_test.sh gives.
#
# RED verification (see tests/README.md): against the pre-port script
# (`git show master:tools/read-base-trailer.sh`) the `--facts` rows fail
# because `--facts` goes to `git log` as a rev (STOP trailer-read-failed), and
# the no-facts trailer rows fail on an unstubbed `gh pr list` (not ok 20/23).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/read-base-trailer.sh}"

failed=0
total=0

# rounds <owner:branch> <total> [<pr> [<state> [<head> [<owner>]]]] -- prints a facts path
rounds() {
  {
    printf 'repo=acme/widgets\nprereq.head=%s\nprereq.head-pr.total=%s\n' "$1" "$2"
    if [ "$#" -ge 3 ]; then printf 'prereq.head-pr=%s\n' "$3"; fi
    if [ "$#" -ge 4 ]; then
      printf 'pr.number=%s\npr.state=%s\npr.head.ref=%s\npr.head.owner=%s\n' "$3" "$4" "${5-${1#*:}}" "${6-${1%%:*}}"
    fi
  } | facts_file
}

# build_repo <name> <trunk-trailer> <task-trailer>... -- prints the path of a
# repository whose `trunk` holds one commit and whose `task` branch (checked
# out) holds one commit per task-trailer. Each trailer argument is a branch
# name, or `-` for a commit carrying no trailer at all. The origin URL is
# only there to pin facts to a repository: nothing here fetches.
build_repo() {
  local name="$1" trunk_trailer="$2"
  shift 2
  local dir t i=0
  dir="$(git_repo_scratch "$name")"
  git_repo_init "$dir" trunk
  git_repo_remote "$dir" origin 'https://github.com/Acme/Widgets.git'
  git_repo_commit "$dir" README.md 'base\n' "$(commit_msg 'base commit' "$trunk_trailer")"
  git_repo_checkout "$dir" task trunk
  for t in "$@"; do
    i=$((i + 1))
    git_repo_commit "$dir" "T${i}.md" "task ${i}\n" "$(commit_msg "task commit ${i}" "$t")"
  done
  printf '%s\n' "$dir"
}

# ---- no trailer at all ---------------------------------------------------
#
# Nothing to look up, so the answer is NO-TRAILER and no fact is asked for.
# The caller settles this row itself -- it is one of the three rows where the
# two readers disagree -- which is why this script does not resolve a default
# branch of its own.

row_start
W="$(build_repo plain - -)"
run_in "$W" HEAD
assert_row 'no-trailer' 0 'NO-TRAILER\n' 0

# ---- the revs are the caller's, not this script's ------------------------
#
# `trunk`'s commit carries a trailer that `task` merely inherits. Handed HEAD
# alone the scan reaches it; handed the caller's exclusion it must not. Facts
# for the inherited branch are given in both rows, so a script ignoring its
# arguments fails as `PREREQ ancestor-base 9 OPEN` -- the defect -- rather than
# as a NEED, which would name the mechanism instead.

row_start
W="$(build_repo ancestor ancestor-base -)"
run_in "$W" --facts "$(rounds acme:ancestor-base 1 9 OPEN)" HEAD '^trunk'
assert_row 'excluded-revs-are-not-scanned' 0 'NO-TRAILER\n' 0

row_start
run_in "$W" --facts "$(rounds acme:ancestor-base 1 9 OPEN)" HEAD
assert_row 'included-revs-are-scanned' 0 'PREREQ ancestor-base 9 OPEN\n' 0

# ---- the first non-empty line wins --------------------------------------
#
# Two commits on one stack recording different branches. The log is
# newest-first, so the newer trailer has to win: without facts the NEED names
# the newer branch, and with its facts the answer is its PR.

row_start
W="$(build_repo shadow - older-base newer-base)"
run_in "$W" HEAD
assert_row 'newest-trailer-shadows-older' 0 'NEED repo=acme/widgets prereq.head=acme:newer-base prereq.head-pr\n' 0

row_start
run_in "$W" --facts "$(rounds acme:newer-base 1 9 OPEN)" HEAD
assert_row 'newest-trailer-wins-with-facts' 0 'PREREQ newer-base 9 OPEN\n' 0

# ---- the two states the callers still branch on -------------------------
#
# OPEN and MERGED are handed back with the number and the branch name, because
# the two callers need different fields of them: `pr-to-ready` takes the
# branch, `review-code` builds `refs/pull/<n>/head` out of the number.

DEP="$(build_repo dep - dep)"

row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 OPEN)" HEAD
assert_row 'prereq-open' 0 'PREREQ dep 9 OPEN\n' 0

row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 MERGED)" HEAD
assert_row 'prereq-merged' 0 'PREREQ dep 9 MERGED\n' 0

# ---- the three answers both callers share -------------------------------
#
# These are base-branch.md's stop cases: both readers print these bytes
# identically, which is why they live here rather than in either caller. The
# slugs are the callers' output contract and are passed straight through.

row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 CLOSED)" HEAD
assert_row 'prereq-closed' 0 'STOP abandoned-prerequisite\n' 0

row_start
run_in "$DEP" --facts "$(rounds acme:dep 0)" HEAD
assert_row 'prereq-has-no-pr' 0 'STOP no-prereq-pr\n' 0

row_start
F="$(rounds acme:dep 2 9)"
printf 'prereq.head-pr=8\n' >>"$F"
run_in "$DEP" --facts "$F" HEAD
assert_row 'prereq-has-several-prs' 0 'STOP ask-multiple-prs\n' 0

# ---- the read failing is not the trailer being absent -------------------
#
# The row this file carries for both callers. A repository with no commits at
# all makes `git log HEAD` exit 128 (measured on git 2.43: "fatal: ambiguous
# argument 'HEAD'"), which is the read failing rather than the trailer being
# missing -- and the two must not collapse, because "absent" sends both
# callers to the default branch. Neither caller's own test file can fixture
# this: resolve-pr-base_test.sh's refs are the ones its two fetches just
# created, so there is no way to leave them unreadable without breaking the
# fetch first.
row_start
W="$(git_repo_scratch trailer-unreadable)"
git_repo_init "$W" task
run_in "$W" HEAD
assert_row 'trailer-read-fails' 0 'STOP trailer-read-failed\n' 0

# ---- argument validation -------------------------------------------------
#
# The row runs from a repository that could have answered, so a failure here
# is the guard's and not the fixture's. No revs means the caller passed
# nothing; `git log` with no rev would default to HEAD and answer for a range
# nobody asked about.
row_start
run_in "$DEP"
assert_row 'no-revs' 2 '' 0

# ---- changed answers -----------------------------------------------------
#
# A list that was never read is a missing fact, where the old script's failed
# `gh` call was `prereq-lookup-failed`.
row_start
F="$(rounds acme:dep '')"
run_in "$DEP" --facts "$F" HEAD
assert_row 'prereq-lookup-unread' 0 'STOP fact-missing\n' 0

# A state outside the three is an enum stop; the old script exited 1 with
# nothing on stdout.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 DRAFT)" HEAD
assert_row 'prereq-state-unrecognised' 0 'STOP fact-enum\n' 0

# ---- the NEED rounds and the self-checks ---------------------------------

row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9)" HEAD
assert_row 'one-pr-asks-for-its-record' 0 'NEED pr.number=9 pr.state pr.head.ref=dep pr.head.owner=acme\n' 0

# One element of a list that reports three is a truncated page, not the list.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 3 9)" HEAD
assert_row 'prereq-list-cut-short' 0 'STOP fact-count\n' 0

row_start
F="$(rounds acme:dep 1 9 OPEN)"
sed -i 's|^repo=.*|repo=upstream/widgets|' "$F"
run_in "$DEP" --facts "$F" HEAD
assert_row 'prereq-read-in-another-repo' 0 'STOP fact-mismatch\n' 0

# a head filter the means ignored returns an unrelated PR, whose record's
# head is not the recorded branch.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 OPEN other)" HEAD
assert_row 'head-filter-ignored-stops' 0 'STOP fact-mismatch\n' 0

# the same branch name under another owner is a different head: the filter
# the means ignored can return it, and only the owner tells it apart.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 OPEN dep other-fork)" HEAD
assert_row 'same-named-head-from-another-owner-stops' 0 'STOP fact-mismatch\n' 0

# state comes from the record only, and a lower-case copy is not in the set.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 closed)" HEAD
assert_row 'merged-read-off-a-list-lower-case' 0 'STOP fact-enum\n' 0

# a list reports a merged PR as not merged; copied as `CLOSED` it stops as
# abandoned rather than becoming a base, and the catalogue forbids reading
# state off a list.
row_start
run_in "$DEP" --facts "$(rounds acme:dep 1 9 CLOSED)" HEAD
assert_row 'merged-read-off-a-list-stops' 0 'STOP abandoned-prerequisite\n' 0

row_start
W="$(build_repo slashed - deps/x)"
run_in "$W" --facts "$(rounds acme:deps/x 1 9 OPEN)" HEAD
assert_row 'slash-in-recorded-branch' 0 'PREREQ deps/x 9 OPEN\n' 0

# Facts pin the repository, so a trailer with no origin to pin to stops.
row_start
W="$(build_repo no-origin - dep)"
git -C "$W" remote remove origin
run_in "$W" HEAD
assert_row 'no-origin-with-a-trailer' 0 'STOP repo-lookup-failed\n' 0

row_start
run_in "$DEP" --facts
assert_row 'facts-flag-without-file' 2 '' 0

harness_exit "$failed" "$total"
