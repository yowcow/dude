#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/resolve-pr-base.sh: how far the
# Base-Branch trailer scan reaches, and the one line it prints for each answer.
#
# git is not stubbed. The defect this file exists to pin is a *range* defect --
# the scan walking past the branch point into shared history (#171) -- and a
# git stub would encode the test author's belief about that range rather than
# git's behaviour. Each row therefore builds a real bare repository to play the
# remote and a real work repository whose `origin` points at it, both under
# $HARNESS_TMP and both offline. The work repository holds no commits at all:
# the SUT reads the branch tip as FETCH_HEAD and never checks anything out.
#
# The scan's range is the whole point, so the fixtures differ in exactly one
# axis: whether the Base-Branch trailer sits on the task branch's own commits
# or on a commit the task branch merely inherits from the default branch.
#
# Limitation: `STOP trailer-read-failed` has no row. It needs `git log` itself
# to fail after both fetches have succeeded, and both refs it names are the
# ones those fetches just created -- there is no fixture that leaves them
# unreadable without also breaking the fetch that precedes it.
#
# Limitation: the SUT extracts fields with `gh --jq`, and the fake `gh` does not
# run jq -- it returns the post-jq bytes a case scripted. A defect in the --jq
# expression itself is therefore invisible here.
#
# RED verification (see tests/README.md) -- the trailer scan used to walk to
# root, so a branch that recorded nothing picked up whatever Base-Branch it
# inherited from shared history and handed that branch back as --base (#171):
#   tmp="$(mktemp -d)"
#   git show bb8d8b8^:skills/pr-to-ready/scripts/resolve-pr-base.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/resolve-pr-base_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/resolve-pr-base.sh}"

PR_JQ='.[] | "\(.number) \(.state)"'

failed=0
total=0

# commit_msg <subject> <base-branch|-> -- a commit message, carrying a
# Base-Branch trailer unless the second argument is `-`. The trailer goes in a
# paragraph of its own because that is where git's trailer parser looks.
commit_msg() {
  if [ "$2" = '-' ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n\nBase-Branch: %s\n' "$1" "$2"
  fi
}

# build_remote <name> <main-trailer> <feature-trailer>... -- prints the path of
# a new bare repo holding `main` (one commit) and `feature` (one commit per
# feature-trailer, branched off main). Each trailer argument is a branch name,
# or `-` for a commit carrying no trailer at all.
build_remote() {
  local name="$1" main_trailer="$2"
  shift 2
  local bare seed t i=0
  bare="$(git_repo_bare acme "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'base\n' "$(commit_msg 'base commit' "$main_trailer")"
  git_repo_checkout "$seed" feature main
  for t in "$@"; do
    i=$((i + 1))
    git_repo_commit "$seed" "F${i}.md" "feature ${i}\n" "$(commit_msg "feature commit ${i}" "$t")"
  done
  git_repo_push "$seed" "$bare" main feature
  printf '%s\n' "$bare"
}

# work_repo <name> <origin-url> <origin-head|-> -- prints the path of a fresh
# work repository with no commits, whose origin is <origin-url>, and whose
# refs/remotes/origin/HEAD points at <origin-head> unless that is `-`.
work_repo() {
  local dir
  dir="$(git_repo_scratch "$1")"
  git_repo_init "$dir" main
  git_repo_remote "$dir" origin "$2"
  if [ "$3" != '-' ]; then
    git_repo_origin_head "$dir" "$3"
  fi
  printf '%s\n' "$dir"
}

# stub_default_branch <exit-status> -- the `gh repo view` rung, body on stdin
stub_default_branch() {
  gh_stub_response '*' "$1" repo view --json defaultBranchRef --jq .defaultBranchRef.name
}

# stub_pr_list <head-branch> <exit-status> -- the prerequisite lookup, body on
# stdin. Each line is "<number> <state>", which is what the SUT's --jq emits.
stub_pr_list() {
  gh_stub_response '*' "$2" pr list --head "$1" --state all --json number,state --jq "$PR_JQ"
}

# run_in <work-dir> <branch> -- the SUT reads cwd's origin, so every row runs
# from inside its own work repository and returns to the repository root.
run_in() {
  cd "$1"
  run_sut bash "$SUT" "$2"
  cd "$REPO_ROOT"
}

# assert_row <name> <want-exit> <want-stdout> [<want-gh-calls>]
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" want_calls="${4:-}" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if [ -n "$want_calls" ] && ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# `feature` records nothing; `main` records nothing either.
REMOTE_PLAIN="$(build_remote plain - -)"
# `main`'s single commit carries a trailer that the task branch merely
# inherits -- the shape that used to escape the scan's range (#171).
REMOTE_ANCESTOR="$(build_remote ancestor ancestor-base -)"
# `feature` records a prerequisite branch of its own.
REMOTE_DEP="$(build_remote dep - dep)"
# Two commits on one stack, the newer one recording a different branch: the
# newer trailer has to win.
REMOTE_SHADOW="$(build_remote shadow - older-base newer-base)"

# ---- the default-branch ladder, with no trailer to find ------------------

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
W="$(work_repo dflt-stale-symref "$REMOTE_PLAIN" stale)"
run_in "$W" feature
assert_row 'stale-symref-is-ignored' 0 'BASE main\n' 1

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
W="$(work_repo dflt-gh "$REMOTE_PLAIN" -)"
run_in "$W" feature
assert_row 'no-trailer-gh-names-default' 0 'BASE main\n' 1

total=$((total + 1))
stub_dir_new
: | stub_default_branch 1
W="$(work_repo dflt-gh-fails "$REMOTE_PLAIN" -)"
run_in "$W" feature
assert_row 'default-branch-lookup-fails' 0 'STOP ask-default-branch\n' 1

total=$((total + 1))
stub_dir_new
: | stub_default_branch 0
W="$(work_repo dflt-gh-empty "$REMOTE_PLAIN" -)"
run_in "$W" feature
assert_row 'default-branch-lookup-empty' 0 'STOP ask-default-branch\n' 1

# ---- the trailer the task branch only inherits ---------------------------
#
# `main`'s commit carries `Base-Branch: ancestor-base` and `feature` records
# nothing, so the answer is the default branch. The prerequisite lookup for
# `ancestor-base` is stubbed even though a correct SUT never makes it: without
# the entry the pre-fix script fails as "an argv no case stubbed", which names
# the mechanism rather than the defect, while with it the row fails as
# `BASE ancestor-base` against `BASE main` -- the range defect itself. The
# `gh calls` assertion is what holds the entry to being unused.

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 OPEN\n' | stub_pr_list ancestor-base 0
W="$(work_repo ancestor "$REMOTE_ANCESTOR" main)"
run_in "$W" feature
assert_row 'ancestor-trailer-is-out-of-scope' 0 'BASE main\n' 1

# ---- a trailer the task branch recorded itself --------------------------
#
# Both branches' lookups are stubbed, so a scan reading the stack oldest-first
# fails as `BASE older-base` against `BASE newer-base` rather than as an argv
# no case stubbed. The `gh calls` assertion holds the unused entry to being
# unused: a correct scan asks about `newer-base` and nothing else.

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 OPEN\n' | stub_pr_list newer-base 0
printf '8 OPEN\n' | stub_pr_list older-base 0
W="$(work_repo shadow "$REMOTE_SHADOW" main)"
run_in "$W" feature
assert_row 'newest-trailer-shadows-older' 0 'BASE newer-base\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 OPEN\n' | stub_pr_list dep 0
W="$(work_repo prereq-open "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-open-keeps-its-branch' 0 'BASE dep\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 MERGED\n' | stub_pr_list dep 0
W="$(work_repo prereq-merged "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-merged-falls-back-to-default' 0 'BASE main\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 CLOSED\n' | stub_pr_list dep 0
W="$(work_repo prereq-closed "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-closed-stops' 0 'STOP abandoned-prerequisite\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
: | stub_pr_list dep 0
W="$(work_repo prereq-none "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-has-no-pr' 0 'STOP no-prereq-pr\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
: | stub_pr_list dep 1
W="$(work_repo prereq-unreadable "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-lookup-fails' 0 'STOP prereq-lookup-failed\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 OPEN\n8 CLOSED\n' | stub_pr_list dep 0
W="$(work_repo prereq-multiple "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-has-several-prs' 0 'STOP ask-multiple-prs\n' 2

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
printf '9 DRAFT\n' | stub_pr_list dep 0
W="$(work_repo prereq-unknown-state "$REMOTE_DEP" main)"
run_in "$W" feature
assert_row 'prerequisite-state-unrecognised' 1 '' 2

total=$((total + 1))
if ! grep -q "unexpected PR state 'DRAFT'" "$SUT_STDERR"; then
  printf 'FAIL prerequisite-state-unrecognised: stderr does not name the state:\n%s\n' \
    "$(head -c 400 "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# ---- fetches that fail --------------------------------------------------
#
# The two failures carry different slugs on purpose: a missing default branch
# and a missing task branch want different answers from the person the caller
# stops for. Both rows reach `gh` exactly once, for the default-branch lookup
# that now precedes every fetch.
#
# The first row's API answer names a branch the remote does not have, so the
# default branch's own fetch is what fails. The second row's API answer names
# a real branch, so that fetch succeeds and it is the task branch's fetch that
# fails instead.

total=$((total + 1))
stub_dir_new
printf 'nosuch\n' | stub_default_branch 0
W="$(work_repo default-absent "$REMOTE_PLAIN" -)"
run_in "$W" feature
assert_row 'default-branch-absent-on-remote' 0 'STOP default-fetch-failed\n' 1

total=$((total + 1))
stub_dir_new
printf 'main\n' | stub_default_branch 0
W="$(work_repo branch-absent "$REMOTE_PLAIN" main)"
run_in "$W" nosuchbranch
assert_row 'task-branch-absent-on-remote' 0 'STOP fetch-failed\n' 1

# ---- argument validation ------------------------------------------------
#
# Both rows run from a work repository that could have answered, so a failure
# here is the guard's, not the fixture's.

total=$((total + 1))
stub_dir_new
W="$(work_repo args-none "$REMOTE_PLAIN" main)"
cd "$W"
run_sut bash "$SUT"
cd "$REPO_ROOT"
assert_row 'no-argument' 1 '' 0

total=$((total + 1))
stub_dir_new
W="$(work_repo args-extra "$REMOTE_PLAIN" main)"
cd "$W"
run_sut bash "$SUT" feature extra
cd "$REPO_ROOT"
assert_row 'too-many-arguments' 1 '' 0

harness_exit "$failed" "$total"
