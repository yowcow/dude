#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/retarget-pr.sh: the two gates it
# gets its correctness from, every STOP it can report, and the two-run sequence
# a failed push leaves behind.
#
# This is the first script in the suite that *writes* to a remote, so every row
# runs against its own throwaway bare repository and the push is real. What
# keeps it off the network is not that the URLs happen to be local: gitrepo.sh
# exports GIT_ALLOW_PROTOCOL=file, so git refuses https, ssh and git:// at the
# transport layer before opening a socket. harness_test.sh asserts that.
#
# Each row builds its own remote rather than sharing one. The script pushes, so
# a shared remote would let one row's merge satisfy the next row's ancestor
# check -- and the ancestor check is the thing under test.
#
# Rows that must NOT edit the PR deliberately register no `gh pr edit` stub. If
# the script edited anyway, the fake `gh` would record a violation and
# check_no_violations fails the row -- a stronger statement than a call count,
# which only says "no more than expected happened".
#
# Limitation: the SUT reads `gh` output through --jq and the fake `gh` does not
# run jq, so it returns the post-jq bytes each row scripted. A defect in the
# --jq expression itself is invisible here.
#
# RED verification (see tests/README.md) -- against the script as it was
# before the second gate existed, the base-matching rows must fail, because it
# returned BASE-OK from a matching pointer alone and never noticed the push
# that had not happened (#170):
#   tmp="$(mktemp -d)"
#   git show 80376f3^:skills/pr-to-ready/scripts/retarget-pr.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/retarget-pr_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/retarget-pr.sh}"

OWNER=acme
REPO=widgets
PR=7

failed=0
total=0

# --- gh stubs --------------------------------------------------------------

# stub_view <base-ref-name>   the opening `gh pr view`
stub_view() {
  printf '%s\n' "$1" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${REPO}" \
      --json baseRefName --jq .baseRefName
}

stub_view_fails() {
  : | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
    --json baseRefName --jq .baseRefName
}

# stub_edit <base> <exit-status>   the retarget itself
stub_edit() {
  : | gh_stub_response '*' "$2" pr edit "$PR" -R "${OWNER}/${REPO}" --base "$1"
}

# --- assertions ------------------------------------------------------------

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

# check_one <label> <want> <got>   a standalone check that keeps the tally
check_one() {
  total=$((total + 1))
  if ! check_eq "$1" "$2" "$3"; then failed=$((failed + 1)); fi
}

bare_sha() {
  git -C "$1" rev-parse "refs/heads/$2"
}

# check_contains <label> <repo> <committish> <sha>  -- <sha> is in its history
check_contains() {
  local label="$1" repo="$2" ref="$3" sha="$4" status=0
  git -C "$repo" merge-base --is-ancestor "$sha" "$ref" 2>/dev/null || status=$?
  check_one "$label" '0' "$status"
}

# --- topology --------------------------------------------------------------

# build_remote <name> <mode> -> prints the path of a bare repo carrying `main`
# (the base being retargeted onto) and `feature` (the PR branch).
#
#   clean     main and feature touch different files, so the merge succeeds
#   conflict  both rewrite the same line of README.md, so the merge conflicts
#   merged    as `clean`, but feature on the remote already contains main's
#             tip -- the state in which both gates hold
build_remote() {
  local name="$1" mode="$2" bare seed
  bare="$(git_repo_bare "$OWNER" "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'common\n' 'the commit both branches share'
  git_repo_checkout "$seed" feature main
  if [ "$mode" = conflict ]; then
    git_repo_commit "$seed" README.md 'feature side\n' 'feature rewrites the shared line'
  else
    git_repo_commit "$seed" FEATURE.md 'feature\n' 'add the feature file'
  fi
  git_repo_checkout "$seed" main
  if [ "$mode" = conflict ]; then
    git_repo_commit "$seed" README.md 'main side\n' 'main rewrites the shared line'
  else
    git_repo_commit "$seed" MAIN.md 'main\n' 'advance main past the fork point'
  fi
  if [ "$mode" = merged ]; then
    git_repo_checkout "$seed" feature
    git_repo_merge "$seed" main
  fi
  git_repo_push "$seed" "$bare" main feature
  printf '%s\n' "$bare"
}

# A directory that is not a git repository at all. The rows that stop before
# git runs use it, so that a regression which reached git anyway would fail
# loudly here instead of quietly operating on the real checkout.
NOT_A_REPO="$(git_repo_scratch not-a-repo)"

# --- argument validation: nothing is read, nothing is called ----------------

total=$((total + 1))
stub_dir_new
cd "$NOT_A_REPO"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature
cd "$REPO_ROOT"
assert_row 'too-few-args' 1 '' 0

total=$((total + 1))
stub_dir_new
cd "$NOT_A_REPO"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main extra
cd "$REPO_ROOT"
assert_row 'too-many-args' 1 '' 0

# --- the PR cannot be read --------------------------------------------------

total=$((total + 1))
stub_dir_new
stub_view_fails
cd "$NOT_A_REPO"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'pr-read-failed' 0 'STOP pr-read-failed\n' 1

# --- the PR points somewhere else: the full retarget path -------------------

total=$((total + 1))
stub_dir_new
stub_view develop
stub_edit main 0
BARE="$(build_remote retarget clean)"
MAIN_SHA="$(bare_sha "$BARE" main)"
W="$(git_repo_clone retarget "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'base-drift-retargets-merges-and-pushes' 0 'RETARGETED develop main\n' 2
check_contains 'base-drift: the remote branch now carries the new base' \
  "$BARE" refs/heads/feature "$MAIN_SHA"

# The base does not exist on the remote, so the very first fetch fails. It
# fails *before* any mutation: the call count proves `gh pr edit` never ran.
total=$((total + 1))
stub_dir_new
stub_view develop
BARE="$(build_remote fetchfail clean)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone fetchfail "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature nosuchbase
cd "$REPO_ROOT"
assert_row 'base-missing-on-the-remote' 0 'STOP fetch-failed\n' 1
check_one 'fetch-failed: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"

# The merge needs the branch's own checkout, and this one is on another branch.
total=$((total + 1))
stub_dir_new
stub_view develop
BARE="$(build_remote checkoutreq clean)"
W="$(git_repo_clone checkoutreq "$BARE" main)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'wrong-branch-checked-out' 0 'STOP checkout-required\n' 1

total=$((total + 1))
stub_dir_new
stub_view develop
BARE="$(build_remote dirty clean)"
W="$(git_repo_clone dirty "$BARE" feature)"
printf 'uncommitted\n' >>"${W}/README.md"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'dirty-worktree' 0 'STOP dirty-worktree\n' 1

total=$((total + 1))
stub_dir_new
stub_view develop
stub_edit main 1
BARE="$(build_remote editfail clean)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone editfail "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'gh-pr-edit-fails' 0 'STOP retarget-failed\n' 2
check_one 'retarget-failed: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"

# A conflict stops for a person. What matters beyond the token is that the
# working tree is left usable: the abort has to have run, or the next run
# reports dirty-worktree forever and a person has to clean up by hand.
# Resolution itself is out of scope (#111) and is not attempted here.
total=$((total + 1))
stub_dir_new
stub_view develop
stub_edit main 0
BARE="$(build_remote conflict conflict)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone conflict "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'merge-conflict-aborts-and-stops' 0 'STOP merge-conflict\n' 2
check_one 'merge-conflict: the merge was aborted' \
  'no' "$([ -f "${W}/.git/MERGE_HEAD" ] && echo yes || echo no)"
check_one 'merge-conflict: the working tree is clean again' \
  '' "$(git -C "$W" status --porcelain)"
check_one 'merge-conflict: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"

# The merge lands locally and the push does not. This is the state the next
# row group has to resume from, and the one #170 mis-read.
total=$((total + 1))
stub_dir_new
stub_view develop
stub_edit main 0
BARE="$(build_remote pushfail clean)"
MAIN_SHA="$(bare_sha "$BARE" main)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone pushfail "$BARE" feature)"
git_repo_deny_push "$BARE"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'push-fails' 0 'STOP push-failed\n' 2
check_one 'push-failed: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"
check_contains 'push-failed: the merge did land locally' \
  "$W" HEAD "$MAIN_SHA"

# --- the PR already points at <base>: the second gate decides ---------------

# Both gates hold. The completion condition here is a negative one -- that
# nothing which changes the remote or the working tree runs -- so it is
# asserted from three directions: no `gh pr edit` stub is registered, so an
# edit would be a violation; the remote branch's sha is unchanged, so no push
# happened; and the local HEAD is unchanged with a clean tree, so no merge did.
total=$((total + 1))
stub_dir_new
stub_view main
BARE="$(build_remote bothgates merged)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone bothgates "$BARE" feature)"
LOCAL_BEFORE="$(git -C "$W" rev-parse HEAD)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'both-gates-hold' 0 'BASE-OK main\n' 1
check_one 'both-gates-hold: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"
check_one 'both-gates-hold: the local branch did not move' \
  "$LOCAL_BEFORE" "$(git -C "$W" rev-parse HEAD)"
check_one 'both-gates-hold: the working tree was not touched' \
  '' "$(git -C "$W" status --porcelain)"

# The pointer matches but the base is not in the remote branch: stage 1 is
# done and stage 2 is not, so the run resumes at the merge. No `gh pr edit`
# stub is registered -- editing the base to what it already is would be the
# one mutation with nothing to do, and a call would be a violation.
#
# This is the row #170 is about. Against 80376f3^ it reports BASE-OK main and
# pushes nothing, so both this assertion and the next one fail.
total=$((total + 1))
stub_dir_new
stub_view main
BARE="$(build_remote resume clean)"
MAIN_SHA="$(bare_sha "$BARE" main)"
W="$(git_repo_clone resume "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'pointer-matches-but-remote-lacks-the-base' 0 'RETARGETED main main\n' 1
check_contains 'resume: the remote branch now carries the base' \
  "$BARE" refs/heads/feature "$MAIN_SHA"

# The second gate needs the branch's remote tip, and this branch has never
# been pushed. A missing tip is not "the base is not in it": the run stops.
total=$((total + 1))
stub_dir_new
stub_view main
BARE="$(build_remote branchfetch clean)"
W="$(git_repo_clone branchfetch "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" nosuchbranch main
cd "$REPO_ROOT"
assert_row 'branch-missing-on-the-remote' 0 'STOP branch-fetch-failed\n' 1

# The ancestor check fails for a reason of its own rather than returning
# either verdict: the base ref resolves to a blob, so `git merge-base
# --is-ancestor` exits 128. Reading that as either verdict would report
# BASE-OK over an unmerged base, or push a merge nobody asked for.
total=$((total + 1))
stub_dir_new
stub_view blobref
BARE="$(build_remote blobref clean)"
git_repo_blob_ref "$BARE" blobref 'not a commit\n'
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone blobref "$BARE" feature)"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature blobref
cd "$REPO_ROOT"
assert_row 'ancestor-check-errors' 0 'STOP ancestor-check-failed\n' 1
check_one 'ancestor-check-failed: the remote branch did not move' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"

# --- a failed push, then a re-run: #170 end to end --------------------------
#
# Every other row builds the state it wants directly. This one lets the script
# produce it: run 1 retargets, merges, and fails at the push, so the second run
# starts from a real half-finished retarget rather than a test author's idea of
# one -- in the same checkout, as a person re-running the command would.
#
# Against 80376f3^, run 2 sees a matching pointer, prints BASE-OK main, and
# pushes nothing: the caller then reads run 1's green CI as this retarget's
# verification, which is the whole of #170.

BARE="$(build_remote resumeseq clean)"
MAIN_SHA="$(bare_sha "$BARE" main)"
FEATURE_BEFORE="$(bare_sha "$BARE" feature)"
W="$(git_repo_clone resumeseq "$BARE" feature)"

# run 1: the remote refuses the push, so stage 1 lands and stage 2 does not.
total=$((total + 1))
stub_dir_new
stub_view develop
stub_edit main 0
git_repo_deny_push "$BARE"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'resume-sequence: run 1 stops at the push' 0 'STOP push-failed\n' 2
check_one 'resume-sequence: run 1 moved nothing on the remote' \
  "$FEATURE_BEFORE" "$(bare_sha "$BARE" feature)"

# run 2: GitHub now reports the new base, so the first gate holds -- and the
# remote branch still lacks it, which is the only thing left to notice. No
# `gh pr edit` stub: the base is already right, so an edit would be a
# violation.
total=$((total + 1))
stub_dir_new
stub_view main
git_repo_allow_push "$BARE"
cd "$W"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" feature main
cd "$REPO_ROOT"
assert_row 'resume-sequence: run 2 finishes the push' 0 'RETARGETED main main\n' 1
check_contains 'resume-sequence: the remote branch finally carries the base' \
  "$BARE" refs/heads/feature "$MAIN_SHA"

harness_exit "$failed" "$total"
