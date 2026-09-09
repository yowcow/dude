#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/read-base-trailer.sh: which
# trailer the scan takes from the revs it was given, and the one line it
# prints for each answer the prerequisite lookup can give.
#
# git is not stubbed. Which commits the scan reaches is the point -- the revs
# arrive from the caller and go straight to `git log` -- and a git stub would
# encode the test author's belief about that range rather than git's own
# behaviour, the same reason tests/pr-to-ready/resolve-pr-base_test.sh gives.
# Each row builds a real repository under $HARNESS_TMP. No remote and no
# fetch: this script reads whatever revs it is handed and nothing else.
#
# `gh` is stubbed raw rather than filtered, because the `--jq` filter is one of
# the guards under test: `.[]` rather than `.[0]` is what makes an empty list
# yield zero lines instead of one interpolated `null null`, and a pre-filtered
# fixture would decide that instead of testing it.
#
# Limitation: a mutation confined to the --jq filter's *text* changes the argv,
# so the stub reports an unstubbed call rather than running the mutated filter
# -- such a defect is invisible here, exactly as in resolve-range_test.sh.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version to point SUT= at. Each guard the script's own header names
# was mutated in a copy under `mktemp -d` -- never inside the repository, where
# lint.sh would select it by shebang -- and this file re-run against it as
# `SUT=<copy> tests/run.sh tests/implement-work/read-base-trailer_test.sh`.
# What each mutant produced, measured:
#
#   1. The exit-status half of the guarded read. Replacing the guard with
#      `TRAILER_LOG="$(git log "$@" --format='...' 2>/dev/null || true)"` -- no
#      `if ! ... then` -- makes a failed read silent instead of stopping.
#      Failed rows: trailer-read-fails (want "STOP trailer-read-failed", got
#      "NO-TRAILER"). The script now reads a failed `git log` as an absent
#      trailer because the silent assignment with `|| true` suppresses the
#      exit status.
#
#   2. The loop's break. Deleting `break` makes the loop keep scanning and
#      record the *oldest* trailer on the stack instead of the newest.
#      Failed rows: newest-trailer-shadows-older (want "PREREQ newer-base 9
#      OPEN", got "PREREQ older-base 8 OPEN").
#
#   3. The caller's revision range. Replacing `git log "$@"` with `git log
#      HEAD` makes the script read the whole branch instead of only the caller's
#      excluded range. Failed rows: excluded-revs-are-not-scanned (want
#      "NO-TRAILER", got "PREREQ ancestor-base 9 OPEN").
#
#   4. The empty-list check. Deleting the `[ "$LINE_COUNT" -eq 0 ]` block
#      makes the script fall through when PR_LOOKUP is empty, reaching the
#      STATE extraction on an empty string and then the case statement with no
#      match. Failed rows: prereq-has-no-pr (want exit 0 with "STOP
#      no-prereq-pr", got exit 1 with stderr "error: unexpected PR state ''
#      for 'dep'").
#
#   5. The multi-PR check. Deleting the `[ "$LINE_COUNT" -ge 2 ]` block makes
#      the script try to extract STATE from a multi-line PR_LOOKUP with
#      `${PR_LOOKUP##* }`, which gives only the last line's state (CLOSED).
#      Failed rows: prereq-has-several-prs (want exit 0 with "STOP
#      ask-multiple-prs", got "STOP abandoned-prerequisite").
#
#   6. The exit-status half of the PR lookup guard. Replacing the guard with
#      `PR_LOOKUP="$(gh ... 2>/dev/null || true)"` -- no `if ! ... then` --
#      makes a failed lookup silent instead of stopping. Failed rows:
#      prereq-lookup-fails (want "STOP prereq-lookup-failed", got "STOP
#      no-prereq-pr"). A failing `gh` command prints nothing, reads as an
#      empty list, and the script answers "no-prereq-pr" instead.
#
#   7. The CLOSED state branch. Deleting the `CLOSED)` case makes the script
#      reach the error path instead of answering STOP abandoned-prerequisite.
#      Failed rows: prereq-closed (want exit 0 with "STOP abandoned-prerequisite",
#      got exit 1 with stderr "error: unexpected PR state 'CLOSED' for 'dep'").
#
#   8. The argument-count guard. Deleting the `[ "$#" -eq 0 ]` guard makes the
#      script pass no arguments to `git log`, which defaults to HEAD and scans
#      the current branch instead of requiring caller-supplied revs. Failed
#      rows: no-revs (want exit 1 with no stdout, got exit 0 with output
#      "STOP prereq-lookup-failed", and gh was called once when it should not).
#
# Not coverable here: the `--jq '.[] | "\(.number) \(.state)"'` filter. The
# fake `gh` stubs the whole invocation by argv, and changing the filter text
# changes the argv, so the stub reports an unstubbed call rather than running
# the mutated filter. Detecting this mutation would require a smarter stub or
# a real gh invocation.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/read-base-trailer.sh}"

PR_LIST_JQ='.[] | "\(.number) \(.state)"'

failed=0
total=0

# stub_pr_list <head-branch> <exit-status> -- the prerequisite lookup, raw body
# on stdin.
stub_pr_list() {
  gh_stub_raw_response '*' "$2" pr list --head "$1" --state all --json number,state --jq "$PR_LIST_JQ"
}

# build_repo <name> <trunk-trailer> <task-trailer>... -- prints the path of a
# repository whose `trunk` holds one commit and whose `task` branch (checked
# out) holds one commit per task-trailer. Each trailer argument is a branch
# name, or `-` for a commit carrying no trailer at all. No remote: nothing
# here fetches.
build_repo() {
  local name="$1" trunk_trailer="$2"
  shift 2
  local dir t i=0
  dir="$(git_repo_scratch "$name")"
  git_repo_init "$dir" trunk
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
# Nothing to look up, so the answer is NO-TRAILER and `gh` is never reached.
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
# alone the scan reaches it; handed the caller's exclusion it must not. Both
# rows run on the same fixture, and the lookup for the inherited branch is
# stubbed so that a script ignoring its arguments fails as
# `PREREQ ancestor-base 9 OPEN` -- the defect -- rather than as an argv no
# case stubbed, which would name the mechanism instead.

row_start
W="$(build_repo ancestor ancestor-base -)"
printf '[{"number":9,"state":"OPEN"}]\n' | stub_pr_list ancestor-base 0
run_in "$W" HEAD '^trunk'
assert_row 'excluded-revs-are-not-scanned' 0 'NO-TRAILER\n' 0

row_start
printf '[{"number":9,"state":"OPEN"}]\n' | stub_pr_list ancestor-base 0
run_in "$W" HEAD
assert_row 'included-revs-are-scanned' 0 'PREREQ ancestor-base 9 OPEN\n' 1

# ---- the first non-empty line wins --------------------------------------
#
# Two commits on one stack recording different branches. The log is
# newest-first, so the newer trailer has to win. `older-base`'s lookup is
# stubbed for the same reason as above: a scan reading the stack oldest-first
# then fails on the answer rather than on an unstubbed argv. The call count is
# what holds the second entry to being unused.

row_start
W="$(build_repo shadow - older-base newer-base)"
printf '[{"number":9,"state":"OPEN"}]\n' | stub_pr_list newer-base 0
printf '[{"number":8,"state":"OPEN"}]\n' | stub_pr_list older-base 0
run_in "$W" HEAD
assert_row 'newest-trailer-shadows-older' 0 'PREREQ newer-base 9 OPEN\n' 1

# ---- the two states the callers still branch on -------------------------
#
# OPEN and MERGED are handed back with the number and the branch name, because
# the two callers need different fields of them: `pr-to-ready` takes the
# branch, `review-code` builds `refs/pull/<n>/head` out of the number.

DEP="$(build_repo dep - dep)"

row_start
printf '[{"number":9,"state":"OPEN"}]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-open' 0 'PREREQ dep 9 OPEN\n' 1

row_start
printf '[{"number":9,"state":"MERGED"}]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-merged' 0 'PREREQ dep 9 MERGED\n' 1

# ---- the three answers both callers share -------------------------------
#
# These are base-branch.md's stop rows: both readers print these bytes
# identically, which is why they live here rather than in either caller. The
# slugs are the callers' output contract and are passed straight through.

row_start
printf '[{"number":9,"state":"CLOSED"}]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-closed' 0 'STOP abandoned-prerequisite\n' 1

row_start
printf '[]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-has-no-pr' 0 'STOP no-prereq-pr\n' 1

row_start
printf '[{"number":9,"state":"OPEN"},{"number":8,"state":"CLOSED"}]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-has-several-prs' 0 'STOP ask-multiple-prs\n' 1

# A non-zero exit prints nothing and looks exactly like an empty list, so the
# two must not collapse: "couldn't tell" is not "no match".
row_start
: | stub_pr_list dep 1
run_in "$DEP" HEAD
assert_row 'prereq-lookup-fails' 0 'STOP prereq-lookup-failed\n' 1

row_start
printf '[{"number":9,"state":"DRAFT"}]\n' | stub_pr_list dep 0
run_in "$DEP" HEAD
assert_row 'prereq-state-unrecognised' 1 '' 1

total=$((total + 1))
if ! grep -q "unexpected PR state 'DRAFT'" "$SUT_STDERR"; then
  printf 'FAIL prereq-state-unrecognised: stderr does not name the state:\n%s\n' \
    "$(head -c 400 "$SUT_STDERR")"
  failed=$((failed + 1))
fi

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
assert_row 'no-revs' 1 '' 0

harness_exit "$failed" "$total"
