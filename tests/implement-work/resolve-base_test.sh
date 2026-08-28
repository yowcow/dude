#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/resolve-base.sh: which base it
# names for each shape of the issue's native `blockedBy` relation, and -- for
# every answer that names one -- that the branch was really fetched.
#
# git is not stubbed. Which ref a fetch updates is git's own behaviour, so a
# git stub would encode the test author's belief about that rather than git's
# behaviour.
#
# The `BASE X` line is printed whether or not the fetch happened, so the
# stdout assertions carry nothing about it and the check_tracking assertions
# carry all of it.
#
# The remote every row shares holds three branches: `main` and `feature` with
# two commits each, and `decoy` with one. `decoy` is what the work repository
# checks out, and each row plants both tracking refs one commit behind. A row
# that expects a fetch therefore asserts the ref MOVED to the tip, and a row
# that expects none asserts it stayed behind -- which also distinguishes
# "fetched the default branch" from "fetched the prerequisite's head" in the
# two rows that could otherwise be told apart only by their stdout.
#
# Limitation: `resolve_default_branch`'s gh call is stubbed with
# gh_stub_response, so the `--jq .defaultBranchRef.name` expression itself is
# not executed. The two `gh issue view` calls carry no --jq, so the SUT's own
# jq -- the counting this file's `two-prerequisites` and `several-prs` rows
# exist for -- does run.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; each variant below is one mutation of a guard the SUT's own
# header names, and the rows it must fail are named:
#   - blockedBy counted -> checked for emptiness: two-prerequisites-stop
#   - closedByPullRequestsReferences counted with `length` -> checked for
#     emptiness: prerequisite-has-several-prs
#   - the non-empty check dropped: default-branch-api-answers-empty
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/resolve-base.sh}"

PR_JQ='"\(.headRefName) \(.state)"'

failed=0
total=0

# build_remote <name> -- prints the path of a bare repo holding `main` and
# `feature` with two commits each and `decoy` with one. The second commit on
# main and on feature is what a fetch has to bring in: every work repository
# below plants its tracking refs at the first.
build_remote() {
  local bare seed
  bare="$(git_repo_bare acme "$1")"
  seed="$(git_repo_scratch "seed-$1")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'root\n' 'root commit'
  git_repo_checkout "$seed" feature main
  git_repo_commit "$seed" F.md 'feature one\n' 'feature commit 1'
  git_repo_commit "$seed" F.md 'feature two\n' 'feature commit 2'
  git_repo_checkout "$seed" main
  git_repo_commit "$seed" M.md 'main two\n' 'main commit 2'
  git_repo_checkout "$seed" decoy main
  git_repo_commit "$seed" D.md 'decoy\n' 'decoy commit'
  git_repo_push "$seed" "$bare" main feature decoy
  printf '%s\n' "$bare"
}

# work_repo <name> <bare> [<origin-head>] -- prints the path of a work repo
# cloned from <bare> with `decoy` checked out, its origin/main and
# origin/feature planted one commit behind the remote, and
# refs/remotes/origin/HEAD pointed at <origin-head> when one is given.
work_repo() {
  local dir
  dir="$(git_repo_clone "$1" "$2" decoy)"
  stale_ref "$dir" "$2" main
  stale_ref "$dir" "$2" feature
  if [ "$#" -ge 3 ]; then
    git_repo_origin_head "$dir" "$3"
  fi
  printf '%s\n' "$dir"
}

# stale_ref <work> <bare> <branch> -- plant refs/remotes/origin/<branch> at the
# remote's <branch>~1, i.e. one commit behind. "Behind" rather than "absent" on
# purpose: absence would also be reported by a `git fetch` that failed, while a
# ref sitting at the older commit is what an earlier fetch leaves behind.
stale_ref() {
  local sha
  sha="$(git -C "$2" rev-parse "refs/heads/$3~1")"
  git -C "$1" update-ref "refs/remotes/origin/$3" "$sha"
}

# check_tracking <label> <work> <bare> <branch> <tip|stale|absent>
# Called only indirectly, through check_row's positional dispatch.
# shellcheck disable=SC2317
check_tracking() {
  local got want
  got="$(git -C "$2" rev-parse --verify -q "refs/remotes/origin/$4" || printf 'absent')"
  case "$5" in
    tip) want="$(git -C "$3" rev-parse "refs/heads/$4")" ;;
    stale) want="$(git -C "$3" rev-parse "refs/heads/$4~1")" ;;
    absent) want=absent ;;
    *)
      printf 'check_tracking: unknown expectation %s\n' "$5"
      return 1
      ;;
  esac
  check_eq "$1" "$want" "$got"
}

# stub_blocked <issue> <exit-status> -- `gh issue view <issue> --json blockedBy`
stub_blocked() {
  gh_stub_response '*' "$2" issue view "$1" --json blockedBy
}

# stub_prereq_prs <issue> <exit-status> -- the prerequisite's closing PRs
stub_prereq_prs() {
  gh_stub_response '*' "$2" issue view "$1" --json closedByPullRequestsReferences
}

# stub_pr_view <pr> <exit-status> -- raw, so the SUT's own --jq runs
stub_pr_view() {
  gh_stub_raw_response '*' "$2" pr view "$1" --json headRefName,state --jq "$PR_JQ"
}

# stub_default_branch <exit-status> -- the `gh repo view` rung of the
# default-branch ladder, body already filtered
stub_default_branch() {
  gh_stub_response '*' "$1" repo view --json defaultBranchRef --jq .defaultBranchRef.name
}

# blocked_json <count> <number>... -- the shape `gh issue view --json blockedBy`
# returns: {nodes, totalCount}. totalCount is passed separately from the nodes
# because that is the field the SUT counts.
# The loops below are guarded on `$#` rather than iterating `"$@"` directly:
# under `set -u` an empty `"$@"` is an unbound-variable error in bash before
# 4.4, and the `blocked_json 0` / `prs_json` calls are exactly that case.
blocked_json() {
  local count="$1" sep='' out='' n
  shift
  if [ "$#" -gt 0 ]; then
    for n in "$@"; do
      out="${out}${sep}{\"number\":${n}}"
      sep=','
    done
  fi
  printf '{"blockedBy":{"nodes":[%s],"totalCount":%s}}\n' "$out" "$count"
}

# prs_json <number>... -- closedByPullRequestsReferences is a plain array here,
# which is why the SUT counts it with `length` and not with a totalCount field.
prs_json() {
  local sep='' out='' n
  if [ "$#" -gt 0 ]; then
    for n in "$@"; do
      out="${out}${sep}{\"number\":${n}}"
      sep=','
    done
  fi
  printf '{"closedByPullRequestsReferences":[%s]}\n' "$out"
}

# run_in <work> <argv...> -- the SUT reads cwd's repository, so every row runs
# from inside its own work repository and returns to the repository root.
run_in() {
  local w="$1"
  shift
  cd "$w"
  run_sut bash "$SUT" "$@"
  cd "$REPO_ROOT"
}

# assert_row <name> <want-exit> <want-stdout> <want-gh-calls>
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" want_calls="$4" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# check_row <label> -- fold an extra assertion into the row count
check_row() {
  total=$((total + 1))
  if ! "${@:2}"; then
    failed=$((failed + 1))
  fi
}

REMOTE="$(build_remote base)"

# ---- arguments ----------------------------------------------------------
#
# The row runs from a work repository that could have answered, so a failure
# here is the guard's and not the fixture's. Two arguments, not three: the
# guard is `-gt 1`, and the boundary is what a row has to sit on.

total=$((total + 1))
stub_dir_new
W="$(work_repo args-extra "$REMOTE" main)"
run_in "$W" 203 extra
assert_row 'too-many-arguments' 1 '' 0
check_row x check_tracking 'too-many-arguments: origin/main' "$W" "$REMOTE" main stale

total=$((total + 1))
if ! grep -q 'Usage:' "$SUT_STDERR"; then
  printf 'FAIL too-many-arguments: stderr carries no usage line:\n%s\n' \
    "$(head -c 400 "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# ---- no argument at all -------------------------------------------------
#
# A task with no issue behind it has no relation to read, which has to land on
# the same answer as a count of 0 -- and reach `gh issue view` not at all. The
# point is not that `gh` is called zero times -- the default-branch ladder's
# own `gh repo view` call runs on this row too -- but that the single `gh`
# call is that one and `gh issue view` is never among them: an implementation
# that asked about an empty issue number would be answered by the stub as a
# violation, since the argv-exact-match stub has no case for an empty number.

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
W="$(work_repo no-arg "$REMOTE" main)"
run_in "$W"
assert_row 'no-argument-uses-default-branch' 0 'BASE main\n' 1
check_row x check_tracking 'no-argument: origin/main fetched' "$W" "$REMOTE" main tip
check_row x check_tracking 'no-argument: origin/feature untouched' "$W" "$REMOTE" feature stale

# ---- blockedBy: 0 -------------------------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 0 | stub_blocked 203 0
printf 'main\n' | stub_default_branch 0
W="$(work_repo blocked-none "$REMOTE" main)"
run_in "$W" 203
assert_row 'no-prerequisite-uses-default-branch' 0 'BASE main\n' 2
check_row x check_tracking 'no-prerequisite: origin/main fetched' "$W" "$REMOTE" main tip

# ---- blockedBy: 2 or more ----------------------------------------------
#
# The counting guard's row. `.blockedBy.totalCount` is read rather than
# "are there any", because emptiness cannot tell one prerequisite from three
# and this row is where the two answers differ.
#
# Both downstream calls are stubbed even though a correct SUT makes neither:
# without them a mutation that counted emptiness would fail as "an argv no
# case stubbed", which names the mechanism rather than the defect, while with
# them it fails as `BASE feature` against `STOP ask-multiple-prereqs` -- the
# defect itself. The `gh calls` assertion is what holds the two entries to
# being unused.

total=$((total + 1))
stub_dir_new
blocked_json 2 77 88 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"OPEN"}\n' | stub_pr_view 55 0
W="$(work_repo blocked-two "$REMOTE" main)"
run_in "$W" 203
assert_row 'two-prerequisites-stop' 0 'STOP ask-multiple-prereqs\n' 1
check_row x check_tracking 'two-prerequisites: no fetch' "$W" "$REMOTE" main stale

# ---- the blockedBy lookup itself fails ---------------------------------
#
# "Could not ask" must not be answered as "there is none". The SUT has no STOP
# for it: the command substitution fails under `set -e` and gh's status
# propagates, which is the loud direction. The row exists to pin that it is not
# `BASE main`.

total=$((total + 1))
stub_dir_new
printf 'gh: HTTP 502\n' | stub_blocked 203 1
W="$(work_repo blocked-fails "$REMOTE" main)"
run_in "$W" 203
assert_row 'blockedBy-lookup-fails-loudly' 1 '' 1
check_row x check_tracking 'blockedBy-lookup-fails: no fetch' "$W" "$REMOTE" main stale

# ---- the prerequisite has no PR ----------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json | stub_prereq_prs 77 0
W="$(work_repo prs-none "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-has-no-pr' 0 'STOP not-implemented\n' 2
check_row x check_tracking 'prerequisite-has-no-pr: no fetch' "$W" "$REMOTE" main stale

# ---- the prerequisite has two PRs --------------------------------------
#
# The second counting guard's row: closedByPullRequestsReferences comes back as
# a plain array, so it is counted with `length`. The `pr view` entry is stubbed
# and unused for the same reason as the two-prerequisites row -- a mutation
# that counted emptiness then fails as `BASE feature` against
# `STOP ask-multiple-prs` rather than as an unstubbed argv.

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 66 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"OPEN"}\n' | stub_pr_view 55 0
W="$(work_repo prs-two "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-has-several-prs' 0 'STOP ask-multiple-prs\n' 2
check_row x check_tracking 'prerequisite-has-several-prs: no fetch' "$W" "$REMOTE" main stale

# ---- the PR lookup itself fails ----------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
printf 'gh: HTTP 502\n' | stub_prereq_prs 77 1
W="$(work_repo prs-fails "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-pr-lookup-fails-loudly' 1 '' 2
check_row x check_tracking 'prerequisite-pr-lookup-fails: no fetch' "$W" "$REMOTE" main stale

# ---- PR state: OPEN ----------------------------------------------------
#
# The prerequisite's head is the base, and it is really fetched: origin/feature
# has to move to the remote's tip. origin/main staying behind is the other half
# of the answer -- it is what distinguishes this row from the MERGED one below
# by something other than its stdout.

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"OPEN"}\n' | stub_pr_view 55 0
W="$(work_repo state-open "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-open-uses-its-head' 0 'BASE feature\n' 3
check_row x check_tracking 'open: origin/feature fetched' "$W" "$REMOTE" feature tip
check_row x check_tracking 'open: origin/main untouched' "$W" "$REMOTE" main stale

# ---- PR state: MERGED --------------------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"MERGED"}\n' | stub_pr_view 55 0
printf 'main\n' | stub_default_branch 0
W="$(work_repo state-merged "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-merged-uses-the-default-branch' 0 'BASE main\n' 4
check_row x check_tracking 'merged: origin/main fetched' "$W" "$REMOTE" main tip
check_row x check_tracking 'merged: origin/feature untouched' "$W" "$REMOTE" feature stale

# ---- PR state: CLOSED --------------------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"CLOSED"}\n' | stub_pr_view 55 0
W="$(work_repo state-closed "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-closed-stops' 0 'STOP abandoned-prerequisite\n' 3
check_row x check_tracking 'closed: no fetch' "$W" "$REMOTE" main stale

# ---- PR state: something else -----------------------------------------
#
# An unrecognised state is the one answer that is neither BASE nor STOP: the
# SUT refuses to guess and exits 1. The stderr assertion names the state,
# because "exit 1 with nothing readable" would leave the caller no way to tell
# this apart from the two lookup failures above.

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"DRAFT"}\n' | stub_pr_view 55 0
W="$(work_repo state-unknown "$REMOTE" main)"
run_in "$W" 203
assert_row 'prerequisite-state-unrecognised' 1 '' 3
check_row x check_tracking 'unrecognised: no fetch' "$W" "$REMOTE" main stale

total=$((total + 1))
if ! grep -q "unexpected PR state 'DRAFT' for PR 55" "$SUT_STDERR"; then
  printf 'FAIL prerequisite-state-unrecognised: stderr names neither the state nor the PR:\n%s\n' \
    "$(head -c 400 "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# ---- the pr view itself fails ------------------------------------------

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf 'gh: HTTP 502\n' | stub_pr_view 55 1
W="$(work_repo pr-view-fails "$REMOTE" main)"
run_in "$W" 203
assert_row 'pr-view-fails-loudly' 1 '' 3
check_row x check_tracking 'pr-view-fails: no fetch' "$W" "$REMOTE" main stale

# ---- the default-branch ladder ----------------------------------------
#
# Two-rung ladder: the GitHub API, then give up. Every row here runs with no
# argument, so the issue lookups stay out of the picture and the gh call
# count is the ladder's own.
#
# The first row plants a stale refs/remotes/origin/HEAD symref naming `main`
# -- the wrong branch -- and stubs the API to answer `feature`, the right
# one, then asserts the base comes from `feature`: the symref is never
# consulted, so a stale answer sitting in it cannot steer the base even when
# it disagrees with the API.

total=$((total + 1))
stub_dir_new
printf 'feature\n' | stub_default_branch 0
W="$(work_repo ladder-stale-symref "$REMOTE" main)"
run_in "$W"
assert_row 'stale-symref-is-ignored' 0 'BASE feature\n' 1
check_row x check_tracking 'stale symref: origin/feature fetched' "$W" "$REMOTE" feature tip
check_row x check_tracking 'stale symref: origin/main untouched' "$W" "$REMOTE" main stale

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
W="$(work_repo ladder-api "$REMOTE")"
run_in "$W"
assert_row 'default-branch-from-api' 0 'BASE main\n' 1
check_row x check_tracking 'api rung: origin/main fetched' "$W" "$REMOTE" main tip

# An API answer that is empty is not a branch name. Without the non-empty
# check the SUT would print `BASE ` and fetch nothing under that name -- a
# guessed answer where the ladder is meant to give up.

total=$((total + 1))
stub_dir_new
: | stub_default_branch 0
W="$(work_repo ladder-api-empty "$REMOTE")"
run_in "$W"
assert_row 'default-branch-api-answers-empty' 0 'STOP ask-default-branch\n' 1
check_row x check_tracking 'api empty: no fetch' "$W" "$REMOTE" main stale

total=$((total + 1))
stub_dir_new
printf 'gh: HTTP 502\n' | stub_default_branch 1
W="$(work_repo ladder-api-fails "$REMOTE")"
run_in "$W"
assert_row 'default-branch-lookup-fails' 0 'STOP ask-default-branch\n' 1
check_row x check_tracking 'api fails: no fetch' "$W" "$REMOTE" main stale

# The MERGED path resolves the default branch through the same ladder, so it
# reaches the same STOP. The row exists because that ladder call sits behind
# two issue lookups there, and a version that only handled the count-0 path
# would answer this one differently.

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"feature","state":"MERGED"}\n' | stub_pr_view 55 0
printf 'gh: HTTP 502\n' | stub_default_branch 1
W="$(work_repo merged-no-default "$REMOTE")"
run_in "$W" 203
assert_row 'merged-with-no-resolvable-default' 0 'STOP ask-default-branch\n' 4
check_row x check_tracking 'merged, no default: no fetch' "$W" "$REMOTE" main stale

# ---- fetches that fail -------------------------------------------------
#
# The API answered a name the remote does not have, which is how a row builds
# "the default branch is named but absent from the remote". fetch_ref has no
# handling for it, so git's 128 propagates under `set -e` and nothing is
# printed -- the loud direction, and the row pins that it is not `BASE nosuch`.

total=$((total + 1))
stub_dir_new
printf 'nosuch\n' | stub_default_branch 0
W="$(work_repo default-absent "$REMOTE")"
run_in "$W"
assert_row 'default-branch-absent-on-remote' 128 '' 1

total=$((total + 1))
stub_dir_new
blocked_json 1 77 | stub_blocked 203 0
prs_json 55 | stub_prereq_prs 77 0
printf '{"headRefName":"nosuch","state":"OPEN"}\n' | stub_pr_view 55 0
W="$(work_repo head-absent "$REMOTE" main)"
run_in "$W" 203
assert_row 'open-head-absent-on-remote' 128 '' 3
check_row x check_tracking 'open head absent: origin/main untouched' "$W" "$REMOTE" main stale

harness_exit "$failed" "$total"
