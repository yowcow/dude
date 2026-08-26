#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/ensure-draft-pr.sh: the
# branch/PR/base decision tree -- whether the branch reaches the remote,
# whether a PR already exists for it, and only then how the base is resolved.
#
# git is not stubbed. The ordering guard #205 asks for is about a real `git
# push` landing on a real remote before a real `git fetch` reads it back, and
# a git stub would only encode the test author's belief about that ordering,
# not git's actual behaviour.
#
# The sibling ./resolve-pr-base.sh is not stubbed either -- #205's scope says
# so -- and the rows that pass a STOP straight through are only meaningful if
# that text really came from the sibling rather than from a fixture standing
# in for it.
#
# Every row runs from inside its own work repository, never from the scripts
# directory: the SUT finds its sibling through dirname "${BASH_SOURCE[0]}", so
# a row run from the scripts directory would pass even against a cwd-relative
# call to the sibling -- one of the guards the SUT's own header names.
#
# fixture() below sets refs/remotes/origin/HEAD by hand after cloning, purely
# for realism -- git_repo_bare leaves the bare repo's HEAD on
# refs/heads/master, a branch these fixtures never create, so a real clone of
# it records no refs/remotes/origin/HEAD at all, and a real one would. The
# sibling's default-branch resolution never reads this symref, so no row's
# answer depends on the call; see fixture()'s own comment for why it stays.
#
# RED verification (see tests/README.md):
#   tmp="$(mktemp -d)"
#   cp skills/pr-to-ready/scripts/resolve-pr-base.sh "$tmp/"
#   cp skills/pr-to-ready/scripts/ensure-draft-pr.sh "$tmp/mut.sh"
#   # apply exactly one edit to "$tmp/mut.sh"
#   SUT="$tmp/mut.sh" tests/run.sh tests/pr-to-ready/ensure-draft-pr_test.sh
#
# Limitations:
#   - `STOP fetch-failed` from the sibling is unreachable through this SUT:
#     step 1 has just seen the branch on the remote (or pushed it there), so
#     the sibling's fetch of it cannot fail without the branch disappearing
#     mid-run. Not fixturable offline.
#   - `STOP trailer-read-failed` from the sibling has no fixture, for the
#     reason resolve-pr-base_test.sh records: both refs `git log` names were
#     just created by the fetches that preceded it.
#   - The SUT's `error: unexpected output from resolve-pr-base.sh` arm is
#     unreachable while the real sibling is used: the sibling prints only
#     `BASE …`/`STOP …` on exit 0. Reaching it would need the sibling stubbed,
#     which #205 puts out of scope.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/ensure-draft-pr.sh}"

# The two --jq filters the SUT and its sibling pass, spelled here exactly as
# they appear in those scripts: the stub matches an argv on its exact bytes.
LIST_JQ='.[] | "\(.number) \(.isDraft)"'
STATE_JQ='.[] | "\(.number) \(.state)"'

TITLE='tests: a title'
BODY_FILE="${HARNESS_TMP}/body.md"
printf 'a body\n' >"$BODY_FILE"

failed=0
total=0

# commit_msg <subject> <base-branch|-> -- the trailer goes in a paragraph of
# its own, which is where git's trailer parser looks.
commit_msg() {
  if [ "$2" = '-' ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n\nBase-Branch: %s\n' "$1" "$2"
  fi
}

# fixture <name> <branch> <where> [<trailer>] -- sets FIXTURE_WORK to the work
# repo's path and FIXTURE_BARE to its remote's. It prints nothing, and it must
# be called as a plain statement: `W="$(fixture ...)"` would run it in a
# subshell, both assignments would be discarded, and the first read of either
# would abort the whole file under `set -u`. A row needs both paths, and
# globals are the only way to carry two values back -- which is why this does
# not follow resolve-pr-base_test.sh's single-value `W="$(work_repo ...)"`.
#
# <where> is the axis every row in this file turns on:
#   remote  -- <branch> exists locally and on origin
#   local   -- <branch> exists in the work repo only, so step 1 must push it
#   nowhere -- <branch> exists in neither
#
# The work repo is a real clone rather than init + remote add, so it has the
# remote-tracking refs, the upstream and the fetch refspec a real checkout has.
#
# refs/remotes/origin/HEAD is then set by hand: git_repo_bare leaves the bare
# repo's HEAD on refs/heads/master, a branch these fixtures never create, so
# the clone finds no advertised HEAD to record and the symref would otherwise
# be absent. Measured -- `git symbolic-ref --short refs/remotes/origin/HEAD`
# fails with "is not a symbolic ref" without this call.
#
# The sibling's default-branch resolution no longer reads this symref at all,
# so this call is not load-bearing for any row's answer -- yet it stays. It
# reproduces the state a real clone has, and leaving it planted while every
# row's answer is unaffected is itself the evidence that the rung reading it
# is really gone: if a rung consulting this symref were reintroduced, every
# row that reaches base resolution would stop calling `gh repo view`, the `gh
# calls` count each row asserts would come back wrong, and this table would
# catch it. A fixture with the symref removed could not catch that
# regression -- it would answer the same whether or not such a rung existed.
fixture() {
  local name="$1" branch="$2" where="$3" trailer="${4:--}" bare seed work
  bare="$(git_repo_bare acme "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'base\n' 'base commit'
  git_repo_push "$seed" "$bare" main
  work="$(git_repo_clone "work-${name}" "$bare" main)"
  git_repo_origin_head "$work" main
  if [ "$where" != nowhere ]; then
    git_repo_checkout "$work" "$branch" main
    git_repo_commit "$work" T.md 'task\n' "$(commit_msg 'task commit' "$trailer")"
    if [ "$where" = remote ]; then
      git_repo_push "$work" origin "refs/heads/${branch}:refs/heads/${branch}"
    fi
  fi
  FIXTURE_BARE="$bare"
  FIXTURE_WORK="$work"
}

# The step-2 and step-5 lookups share one argv, so a row that needs them to
# answer differently addresses them by call index.
#
# Raw, not filtered: the body is the JSON gh received, and the stub applies
# the SUT's own --jq to it. That is what puts `.[]` under test -- a fixture
# pre-reduced to "<number> <isDraft>" lines would decide the very answer the
# row is checking, and `.[0]` would then be indistinguishable from `.[]`.
stub_pr_list() {
  gh_stub_raw_response "$1" "$3" pr list --head "$2" --json number,isDraft --jq "$LIST_JQ"
}

# The failing spelling. A failing gh prints no body for --jq to reduce, so the
# entry states "nothing on stdout" directly instead of handing the raw arm a
# body it would not filter anyway.
stub_pr_list_filtered() {
  gh_stub_response "$1" "$3" pr list --head "$2" --json number,isDraft --jq "$LIST_JQ"
}

stub_pr_create() {
  gh_stub_response "$1" "$4" pr create --draft --head "$2" --base "$3" \
    --title "$TITLE" --body-file "$BODY_FILE"
}

# The sibling's prerequisite-PR lookup: `gh pr list --head <trailer-branch>
# --state all`, raw like stub_pr_list -- the state comparison it feeds
# (OPEN/MERGED/CLOSED/other) is what step 3's rows put under test, so a
# pre-reduced fixture would decide the very answer they check.
stub_prereq_list() {
  gh_stub_raw_response "$1" "$3" pr list --head "$2" --state all --json number,state --jq "$STATE_JQ"
}

# The sibling's default-branch rung, reached unconditionally every time base
# resolution runs: `gh repo view --json defaultBranchRef --jq
# .defaultBranchRef.name`.
stub_default_branch() {
  gh_stub_response "$1" "$2" repo view --json defaultBranchRef --jq .defaultBranchRef.name
}

# stamp_push_order <bare> -- a pre-receive hook that records the gh stub's call
# count at the instant the push reaches the remote, and then allows it.
#
# This is what makes "the push runs before any base resolution" an assertion
# about call *order* rather than only about the outcome. Measured: a hook
# inherits the pushing process's exported environment, so $GH_STUB_DIR is
# readable from inside it.
stamp_push_order() {
  local hook="$1/hooks/pre-receive"
  mkdir -p "$1/hooks"
  cat >"$hook" <<'PUSH_HOOK'
#!/usr/bin/env bash
cat "${GH_STUB_DIR}/count" >"${GH_STUB_DIR}/push_at_call"
exit 0
PUSH_HOOK
  chmod +x "$hook"
}

# push_order_stamp -- the count that hook recorded, or `no-push` when no push
# ever reached the remote. The two are different failures and must not read
# alike: a version that resolves the base first never reaches the push at all,
# because the sibling's fetch of an unpushed branch stops it first.
push_order_stamp() {
  if [ -f "${GH_STUB_DIR}/push_at_call" ]; then
    cat "${GH_STUB_DIR}/push_at_call"
  else
    printf 'no-push'
  fi
}

remote_has_branch() {
  if git -C "$1" show-ref --verify --quiet "refs/heads/$2"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# run_in <work-dir> <args...> -- every row runs from inside its own work repo,
# never from the scripts directory: the SUT reads cwd's origin, and it finds
# its sibling through dirname "${BASH_SOURCE[0]}", so a row run from the
# scripts directory would pass even against a cwd-relative sibling call.
run_in() {
  local dir="$1"
  shift
  cd "$dir"
  run_sut bash "$SUT" "$@"
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

# ---- step 1: is the branch on the remote at all? -------------------------
#
# Step 1 runs before anything else -- before any PR lookup and before any base
# resolution. `push-failure-stops` is the only row that installs a rejecting
# hook: it needs a push attempt to fail. `a-branch-already-on-the-remote-is-
# not-pushed-again` needs the opposite -- a push attempt that would actually
# transmit if it happened -- so it instead puts the work repo one commit ahead
# of the remote and reads the remote's tip directly; see that row's own
# comment for why a hook cannot observe this case.

total=$((total + 1))
stub_dir_new
fixture nowhere-b feature nowhere
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'branch-nowhere-stops' 0 'STOP branch-nowhere\n' 0

total=$((total + 1))
stub_dir_new
fixture lsr feature remote
git_repo_remote "$FIXTURE_WORK" origin "${HARNESS_TMP}/repos/no-such-remote.git"
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'ls-remote-failure-is-not-an-absent-branch' 0 'STOP ls-remote-failed\n' 0

total=$((total + 1))
stub_dir_new
fixture pushfail feature local
git_repo_deny_push "$FIXTURE_BARE"
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'push-failure-stops' 0 'STOP push-failed\n' 0

total=$((total + 1))
stub_dir_new
fixture order feature local
stamp_push_order "$FIXTURE_BARE"
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
printf '[{"number":7,"isDraft":true}]\n' | stub_pr_list 4 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'local-only-branch-is-pushed-before-the-base-is-resolved' 0 'PR 7 created draft=true base=main\n' 4

total=$((total + 1))
if ! check_eq 'push-precedes-every-gh-call' 0 "$(push_order_stamp)"; then
  failed=$((failed + 1))
fi

total=$((total + 1))
if ! check_eq 'ordering-row-landed-on-the-remote' yes "$(remote_has_branch "$FIXTURE_BARE" feature)"; then
  failed=$((failed + 1))
fi

# A rejecting hook cannot be used to prove this row's point: `fixture ...
# remote` leaves the work repo's branch byte-identical to the remote's copy,
# and re-pushing an identical ref is a no-op -- git prints "Everything
# up-to-date" and the push never reaches `pre-receive` at all (measured). So
# the work repo is put one commit ahead of the remote instead, which makes a
# redundant push something that would really transmit, and the remote's tip
# is captured before the SUT runs and compared against it afterward -- a
# direct check that no push reached the remote, rather than one that depends
# on a hook the redundant case cannot trigger.
total=$((total + 1))
stub_dir_new
fixture nopush feature remote
git_repo_commit "$FIXTURE_WORK" T2.md 'ahead\n' 'a commit the remote does not have'
NOPUSH_TIP="$(git -C "$FIXTURE_BARE" rev-parse "refs/heads/feature")"
printf '[{"number":12,"isDraft":true}]\n' | stub_pr_list 1 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'a-branch-already-on-the-remote-is-not-pushed-again' 0 'PR 12 found draft=true\n' 1

total=$((total + 1))
if ! check_eq 'no-redundant-push-moved-the-remote' "$NOPUSH_TIP" "$(git -C "$FIXTURE_BARE" rev-parse "refs/heads/feature")"; then
  failed=$((failed + 1))
fi

total=$((total + 1))
stub_dir_new
fixture othercheckout feature local
git_repo_checkout "$FIXTURE_WORK" main
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
printf '[{"number":7,"isDraft":true}]\n' | stub_pr_list 4 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'the-named-branch-is-pushed-not-the-checked-out-one' 0 'PR 7 created draft=true base=main\n' 4

total=$((total + 1))
if ! check_eq 'named-branch-landed-not-the-checked-out-one' yes "$(remote_has_branch "$FIXTURE_BARE" feature)"; then
  failed=$((failed + 1))
fi

# ---- step 2: does a PR already exist? ------------------------------------

total=$((total + 1))
stub_dir_new
fixture exists-draft feature remote
printf '[{"number":12,"isDraft":true}]\n' | stub_pr_list 1 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'existing-draft-pr-is-reported' 0 'PR 12 found draft=true\n' 1

total=$((total + 1))
stub_dir_new
fixture exists-ready feature remote
printf '[{"number":12,"isDraft":false}]\n' | stub_pr_list 1 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'existing-ready-pr-is-reported' 0 'PR 12 found draft=false\n' 1

total=$((total + 1))
stub_dir_new
fixture lookupfail feature remote
: | stub_pr_list_filtered 1 feature 1
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'lookup-failure-is-not-an-absent-pr' 0 'STOP pr-lookup-failed\n' 1

total=$((total + 1))
stub_dir_new
fixture multi feature remote
printf '[{"number":12,"isDraft":true},{"number":13,"isDraft":false}]\n' | stub_pr_list 1 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'several-prs-for-one-branch-stop' 0 'STOP ask-multiple-prs\n' 1

total=$((total + 1))
stub_dir_new
fixture numeric 1234 remote
printf '[{"number":12,"isDraft":true}]\n' | stub_pr_list 1 1234 0
run_in "$FIXTURE_WORK" 1234 "$TITLE" "$BODY_FILE"
assert_row 'a-numeric-branch-name-is-a-head-not-a-pr-number' 0 'PR 12 found draft=true\n' 1

total=$((total + 1))
stub_dir_new
fixture nobase feature remote
printf '[{"number":12,"isDraft":true}]\n' | stub_pr_list 1 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'an-existing-pr-needs-no-base' 0 'PR 12 found draft=true\n' 1

total=$((total + 1))
stub_dir_new
fixture create feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf '[]' | gh_stub_raw_response 1 0 pr list --head feature --json number,isDraft \
  --jq '.[0] | "\(.number) \(.isDraft)"'
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
printf '[{"number":7,"isDraft":true}]\n' | stub_pr_list 4 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'an-empty-list-is-no-pr-and-the-pr-is-created' 0 'PR 7 created draft=true base=main\n' 4

# ---- step 3: the base, resolved by the real sibling ----------------------
#
# ensure-draft-pr.sh does not take a base as an argument: once it has decided
# a PR must be created, it asks its sibling resolve-pr-base.sh for one --
# reached the same way, through dirname "${BASH_SOURCE[0]}" -- and passes the
# answer straight through unchanged. The sibling is not stubbed, so these rows
# drive its own decision tree through fixtures and gh stubs; the text each row
# expects on stdout is the sibling's own text, printed unchanged by the SUT.
# #205 puts an exhaustive test of the sibling out of scope -- #186 owns that
# -- so what is under test here is only that each answer arrives, and that no
# PR is created when the answer is a stop. The gh-calls count is what proves
# the second half: no stop row below registers a `pr create` argv, so a
# version that created one anyway would fail both as an unstubbed argv and on
# the count.
#
# Every fixture below is `fixture <name> feature remote [<trailer>]`, and
# every row stubs call 1 -- the SUT's own branch lookup -- as an empty list,
# so control always reaches the sibling. The sibling's own default-branch
# lookup is unconditional, so it is always call 2; its remaining gh calls, if
# any, follow starting at call 3.

total=$((total + 1))
stub_dir_new
fixture default-unknown feature remote
printf '[]\n' | stub_pr_list 1 feature 0
: | stub_default_branch 2 1
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'base-stop-default-branch-unknown' 0 'STOP ask-default-branch\n' 2

total=$((total + 1))
stub_dir_new
fixture default-absent feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf 'nosuch\n' | stub_default_branch 2 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'base-stop-default-branch-named-but-absent' 0 'STOP default-fetch-failed\n' 2

total=$((total + 1))
stub_dir_new
fixture prereq-lookup-failed feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
: | gh_stub_response 3 1 pr list --head dep --state all --json number,state --jq "$STATE_JQ"
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'base-stop-prerequisite-lookup-failed' 0 'STOP prereq-lookup-failed\n' 3

total=$((total + 1))
stub_dir_new
fixture prereq-none feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[]\n' | stub_prereq_list 3 dep 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'base-stop-prerequisite-has-no-pr' 0 'STOP no-prereq-pr\n' 3

total=$((total + 1))
stub_dir_new
fixture prereq-several feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[{"number":9,"state":"OPEN"},{"number":8,"state":"CLOSED"}]\n' | stub_prereq_list 3 dep 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
# Prints the same slug, STOP ask-multiple-prs, as Task 2's
# several-prs-for-one-branch-stop -- both are intended, and deliberately not
# redundant: one comes from the SUT's own branch lookup, the other from the
# sibling's prerequisite lookup, and they are told apart by gh call count (1
# there, 3 here).
assert_row 'base-stop-prerequisite-has-several-prs' 0 'STOP ask-multiple-prs\n' 3

total=$((total + 1))
stub_dir_new
fixture prereq-abandoned feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[{"number":9,"state":"CLOSED"}]\n' | stub_prereq_list 3 dep 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'base-stop-prerequisite-abandoned' 0 'STOP abandoned-prerequisite\n' 3

total=$((total + 1))
stub_dir_new
fixture prereq-unrecognised feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[{"number":9,"state":"DRAFT"}]\n' | stub_prereq_list 3 dep 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
# The sibling exits 1 having printed nothing on stdout, and the SUT's
# RESOLVED="$(...)" dies with it under set -e -- this is the SUT's one
# non-STOP failure exit, and the fault is the sibling's, not the SUT's, so
# this asserts exit 1 with empty stdout rather than a slug.
assert_row 'an-unrecognised-prerequisite-state-kills-the-run' 1 '' 3

total=$((total + 1))
if ! grep -q "unexpected PR state 'DRAFT'" "$SUT_STDERR"; then
  printf 'FAIL an-unrecognised-prerequisite-state-kills-the-run: stderr does not name the state:\n%s\n' \
    "$(head -c 400 "$SUT_STDERR")"
  failed=$((failed + 1))
fi

total=$((total + 1))
stub_dir_new
fixture prereq-open feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[{"number":9,"state":"OPEN"}]\n' | stub_prereq_list 3 dep 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 4 feature dep 0
printf '[{"number":7,"isDraft":true}]\n' | stub_pr_list 5 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'an-open-prerequisite-becomes-the-base' 0 'PR 7 created draft=true base=dep\n' 5

total=$((total + 1))
stub_dir_new
fixture prereq-merged feature remote dep
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf '[{"number":9,"state":"MERGED"}]\n' | stub_prereq_list 3 dep 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 4 feature main 0
printf '[{"number":7,"isDraft":true}]\n' | stub_pr_list 5 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'a-merged-prerequisite-falls-back-to-the-default-branch' 0 'PR 7 created draft=true base=main\n' 5

# ---- steps 4-5: create, then read the record back -----------------------
#
# `gh pr create` exiting 0 is not the PR record saying so, so step 5 reads the
# record back with the same lookup step 2 uses. These four rows are the four
# things that readback can find. `pr-not-created` and `pr-readback-failed` are
# separate slugs on purpose: "the record is not there" and "I could not ask"
# are exactly the confusion this whole suite exists to catch.
#
# Every fixture below is `fixture <name> feature remote`, no trailer, so the
# base resolves to `main`. Call 1 is the SUT's own PR-existence lookup, call 2
# the sibling's default-branch lookup, call 3 the create, call 4 the readback.

total=$((total + 1))
stub_dir_new
fixture create-fail feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
: | stub_pr_create 3 feature main 1
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'create-failure-stops' 0 'STOP pr-create-failed\n' 3

total=$((total + 1))
stub_dir_new
fixture not-created feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
printf '[]\n' | stub_pr_list 4 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'a-record-that-does-not-read-back-stops' 0 'STOP pr-not-created\n' 4

total=$((total + 1))
stub_dir_new
fixture readback-fail feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
: | stub_pr_list_filtered 4 feature 1
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'readback-failure-is-not-a-missing-record' 0 'STOP pr-readback-failed\n' 4

total=$((total + 1))
stub_dir_new
fixture several-after-create feature remote
printf '[]\n' | stub_pr_list 1 feature 0
printf 'main\n' | stub_default_branch 2 0
printf 'https://example.invalid/pull/7\n' | stub_pr_create 3 feature main 0
printf '[{"number":7,"isDraft":true},{"number":8,"isDraft":true}]\n' | stub_pr_list 4 feature 0
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE"
assert_row 'several-prs-after-create-stop' 0 'STOP ask-multiple-prs-after-create\n' 4

# ---- argument validation -------------------------------------------------
#
# Each row builds its own fixture and calls stub_dir_new of its own, like
# every other row in this file: gh_call_count reads ${GH_STUB_DIR}/count, and
# only stub_dir_new resets it, so without a reset the first of these rows
# would read the calls the previous row's fixture left behind and fail `want
# gh calls: 0` against a perfectly correct SUT. Each row runs from a work repo
# that could have answered, so a failure here is the guard's and not the
# fixture's -- the same reasoning resolve-pr-base_test.sh records for its own
# two.

total=$((total + 1))
stub_dir_new
fixture args-none feature remote
run_in "$FIXTURE_WORK"
assert_row 'no-arguments' 1 '' 0

total=$((total + 1))
stub_dir_new
fixture args-two feature remote
run_in "$FIXTURE_WORK" feature "$TITLE"
assert_row 'two-arguments' 1 '' 0

total=$((total + 1))
stub_dir_new
fixture args-four feature remote
run_in "$FIXTURE_WORK" feature "$TITLE" "$BODY_FILE" extra
assert_row 'four-arguments' 1 '' 0

harness_exit "$failed" "$total"
