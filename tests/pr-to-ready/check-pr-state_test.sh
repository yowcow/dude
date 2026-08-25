#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/check-pr-state.sh: the three
# values of `mergeable`, the bounded re-read that `UNKNOWN` triggers, and the
# local fallback that runs when the re-read never resolves.
#
# The fallback rows do not stub git. They build a real repository whose
# `origin` is a local bare repo, and the bare repo's *path* is what carries the
# identity the script compares: .../acme/widgets.git reduces to `acme/widgets`.
# That is what lets one mechanism produce both "origin is this PR's repository"
# and "origin is some other repository" with no network in either.
#
# Limitation: the SUT extracts fields with `gh --jq`, and the fake `gh` does not
# run jq -- it returns the post-jq bytes a case scripted. A defect in the --jq
# expression itself is therefore invisible here.
#
# RED verification (see tests/README.md) -- the origin-mismatch row must fail
# against the pre-fix script, which computed a confident answer from whatever
# repository the working tree happened to point at (#172):
#   tmp="$(mktemp -d)"
#   git show a548e36^:skills/pr-to-ready/scripts/check-pr-state.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/check-pr-state_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/check-pr-state.sh}"

stub_sleep_instant

OWNER=acme
REPO=widgets
PR=7
FIRST_JQ='"\(.baseRefName) \(.headRefName) \(.mergeable)"'

failed=0
total=0

# stub_first <repo> <mergeable> [<base-ref>]  -- the opening `gh pr view`
stub_first() {
  local repo="$1" mergeable="$2" base="${3:-main}"
  printf '%s feature %s\n' "$base" "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${repo}" \
      --json baseRefName,headRefName,mergeable --jq "$FIRST_JQ"
}

# stub_reread <repo> <mergeable> -- every re-read answers the same
stub_reread() {
  local repo="$1" mergeable="$2"
  printf '%s\n' "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${repo}" \
      --json mergeable --jq .mergeable
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

# Build once: a bare repo that IS acme/widgets, a second that is not, and a
# third whose two branches edit the same line. `main` and `feature` in the
# first pair touch different files, so a merge of the two is clean.
BARE_MATCH="$(git_repo_bare "$OWNER" "$REPO")"
SEED="$(git_repo_scratch seed)"
git_repo_init "$SEED" main
git_repo_commit "$SEED" README.md 'common\n' 'base'
git_repo_checkout "$SEED" feature main
git_repo_commit "$SEED" FEATURE.md 'feature\n' 'add feature file'
git_repo_checkout "$SEED" main
git_repo_commit "$SEED" MAIN.md 'main\n' 'add main file'
git_repo_push "$SEED" "$BARE_MATCH" main feature

BARE_OTHER="$(git_repo_bare other repo)"
git_repo_push "$SEED" "$BARE_OTHER" main feature

BARE_CONFLICT="$(git_repo_bare "$OWNER" conflicting)"
CSEED="$(git_repo_scratch cseed)"
git_repo_init "$CSEED" main
git_repo_commit "$CSEED" README.md 'common\n' 'base'
git_repo_checkout "$CSEED" feature main
git_repo_commit "$CSEED" README.md 'feature side\n' 'feature edits the shared line'
git_repo_checkout "$CSEED" main
git_repo_commit "$CSEED" README.md 'main side\n' 'main edits the shared line'
git_repo_push "$CSEED" "$BARE_CONFLICT" main feature

# work_with_origin <name> <url|-> -- a work repo whose origin is <url>, or with
# no origin at all when given `-`; prints its path.
work_with_origin() {
  local dir
  dir="$(git_repo_scratch "$1")"
  git_repo_init "$dir" main
  if [ "$2" != '-' ]; then
    git_repo_remote "$dir" origin "$2"
  fi
  printf '%s\n' "$dir"
}

# ---- rows that never reach git -------------------------------------------

total=$((total + 1))
stub_dir_new
stub_first "$REPO" MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'mergeable-base-ok' 0 'BASE-OK main MERGEABLE\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" CONFLICTING
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'conflicting-base-ok' 0 'BASE-OK main CONFLICTING\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" MERGEABLE develop
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'base-drift-reports-current-base' 0 'BASE-DRIFT develop MERGEABLE\n' 1

total=$((total + 1))
stub_dir_new
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json baseRefName,headRefName,mergeable --jq "$FIRST_JQ"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'first-read-fails' 0 'STOP pr-read-failed\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json mergeable --jq .mergeable
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 're-read-fails' 0 'STOP pr-read-failed\n' 2

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'unknown-then-resolves-on-re-read' 0 'BASE-OK main MERGEABLE\n' 2

total=$((total + 1))
stub_dir_new
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR"
assert_row 'too-few-args' 1 '' 0

total=$((total + 1))
stub_dir_new
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main extra
assert_row 'too-many-args' 1 '' 0

# ---- rows that exhaust the re-read and fall back to local git -------------
#
# Six gh calls each: the opening read plus MERGEABLE_RETRY_MAX=5 re-reads, and
# five sleeps between them. Asserting both is what pins the bound; the sleeps
# are instant, so the row costs no wall clock.

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" UNKNOWN
W="$(work_with_origin origin-match "$BARE_MATCH")"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
cd "$REPO_ROOT"
assert_row 'origin-matches-falls-back-to-local-merge' 0 'BASE-OK main MERGEABLE\n' 6

total=$((total + 1))
if ! check_eq 'origin-matches: sleeps' '5' "$(sleep_call_count)"; then failed=$((failed + 1)); fi

total=$((total + 1))
stub_dir_new
stub_first conflicting UNKNOWN
stub_reread conflicting UNKNOWN
W="$(work_with_origin origin-match-conflict "$BARE_CONFLICT")"
cd "$W"
run_sut bash "$SUT" "$OWNER" conflicting "$PR" main
cd "$REPO_ROOT"
assert_row 'origin-matches-conflicting-trees' 0 'BASE-OK main CONFLICTING\n' 6

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" UNKNOWN
W="$(work_with_origin origin-mismatch "$BARE_OTHER")"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
cd "$REPO_ROOT"
assert_row 'origin-is-another-repository-stays-unknown' 0 'BASE-OK main UNKNOWN\n' 6

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" UNKNOWN
W="$(work_with_origin origin-absent -)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
cd "$REPO_ROOT"
assert_row 'origin-unreadable-stays-unknown' 0 'BASE-OK main UNKNOWN\n' 6

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN nosuchbase
stub_reread "$REPO" UNKNOWN
W="$(work_with_origin fetch-fails "$BARE_MATCH")"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" nosuchbase
cd "$REPO_ROOT"
assert_row 'base-ref-missing-on-remote-stays-unknown' 0 'BASE-OK nosuchbase UNKNOWN\n' 6

harness_exit "$failed" "$total"
