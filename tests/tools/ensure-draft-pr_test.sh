#!/usr/bin/env bash
# Table test for tools/ensure-draft-pr.sh: the
# branch/PR/base decision tree -- whether the branch reaches the remote,
# whether a PR already exists for it, who decides the target repository, and
# only then how the base is resolved.
#
# The script reads facts, git and origin; it opens no PR and reads none, and
# through the real sibling it reads the default branch from the remote's HEAD.
# Every row asserts 0 gh calls.
#
# git is not stubbed. The ordering guard #205 asks for is about a real `git
# push` landing on a real remote before anything is asked, and a git stub
# would only encode the test author's belief about that ordering, not git's
# actual behaviour.
#
# The sibling ./resolve-pr-base.sh runs for real in every row but the two at
# the end, which stub it to pin how this script answers a sibling that aborts
# or answers out of contract. #205 left that boundary out; yowcow/dude#648
# owns it.
#
# Every row runs from inside its own work repository, never from the scripts
# directory: the SUT finds its sibling through dirname -- "$0", so a row run
# from the scripts directory would pass even against a cwd-relative call to
# the sibling.
#
# RED verification (see tests/README.md). The tree has to be copied with its
# shape intact (`cp -R tools`): in every row that reaches the real sibling the
# SUT resolves it through dirname "$0", so a flat copy answers there regardless
# of this file's own mutation. The two stubbed rows at the end are the
# exception -- they copy the SUT into a tools/ tree that already holds every
# sibling, so a flat copy is enough for those too.
#   tmp="$(mktemp -d)"
#   cp -R tools "$tmp/tools"
#   git show e4395c8^:tools/ensure-draft-pr.sh >"$tmp/tools/mut.sh"
#   SUT="$tmp/tools/mut.sh" tests/run.sh tests/tools/ensure-draft-pr_test.sh
#
#   Against that pre-fix script only the two stubbed rows and their stderr
#   tally are red: `not ok 3/59`.
#
# The branch's PR, the fork question and the prerequisite's PR all arrive as
# facts, in one `--facts` file a row writes. The facts' own self-checks are
# tools/facts.sh's; what is under test here is which facts this script asks
# for, in which order, and what it decides from them.
#
# Limitations:
#   - `STOP fetch-failed` from the sibling is unreachable through this SUT:
#     step 1 has just seen the branch on the remote (or pushed it there), so
#     the sibling's fetch of it cannot fail without the branch disappearing
#     mid-run. Not fixturable offline.
#   - `STOP trailer-read-failed` from the sibling has no row: through the real
#     sibling it needs `git log` to fail after the fetches that created the two
#     refs it names, and the stubbed rows at the end answer
#     `STOP base-resolve-failed` before any pass-through, so neither shape
#     reaches it.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/ensure-draft-pr.sh}"

failed=0
total=0

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
# The remote's HEAD is pointed at `main` before the clone: git_repo_bare leaves
# it on an unborn `master`, which is what the sibling reads as the default
# branch, and a clone of it would record no refs/remotes/origin/HEAD.
fixture() {
  local name="$1" branch="$2" where="$3" trailer="${4:--}" bare seed work
  bare="$(git_repo_bare acme "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'base\n' 'base commit'
  git_repo_push "$seed" "$bare" main
  git_repo_bare_head "$bare" main
  work="$(git_repo_clone "work-${name}" "$bare" main)"
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

# own <name> <total> [<pr>...] -- target/head/list lines for branch `feature` in acme/<name>
own() {
  local name="$1" t="$2"
  shift 2
  printf 'target=acme/%s\nhead=acme:feature\nhead.open-pr.total=%s\n' "$name" "$t"
  for n in "$@"; do printf 'head.open-pr=%s\n' "$n"; done
}

# record <pr> <draft> [<head> [<base>]] -- that PR's record lines; its head
# owner is acme unless HEAD_OWNER says otherwise
record() {
  printf 'pr.number=%s\npr.head.ref=%s\npr.head.owner=%s\npr.draft=%s\npr.url=https://example.invalid/pull/%s\n' "$1" "${3:-feature}" "${HEAD_OWNER:-acme}" "$2" "$1"
  if [ "$#" -ge 4 ]; then printf 'pr.base.ref=%s\n' "$4"; fi
}

# fork <name> <total> [<isFork>...] -- origin's isFork list: `total` is the count of repository records the read returned
fork() {
  local n="$1" t="$2"
  shift 2
  printf 'repo=acme/%s\nrepo.fork.total=%s\n' "$n" "$t"
  for v in "$@"; do printf 'repo.fork=%s\n' "$v"; done
}

# one_repo_fork <isFork> -- the fork list when a row's file already holds a `repo=` line (from prereq_facts)
one_repo_fork() { printf 'repo.fork.total=1\nrepo.fork=%s\n' "$1"; }

# prereq_facts <repo> <owner:branch> <total> [<pr> [<state> [<head> [<owner>]]]] -- the
# prerequisite lookup's facts as lines on stdout (pipe into facts_file, or
# concatenate with other lines first).
prereq_facts() {
  printf 'repo=%s\nprereq.head=%s\nprereq.head-pr.total=%s\n' "$1" "$2" "$3"
  if [ "$#" -ge 4 ]; then
    printf 'prereq.head-pr=%s\n' "$4"
  fi
  if [ "$#" -ge 5 ]; then
    printf 'pr.number=%s\npr.state=%s\npr.head.ref=%s\npr.head.owner=%s\n' "$4" "$5" "${6-${2#*:}}" "${7-${2%%:*}}"
  fi
}

# parent_bare <default> -- acme/parent as a bare repo holding `main` and
# `trunk`, HEAD on <default>. Origin's sibling path, so a row that names
# acme/parent without adding a remote reaches it there.
parent_bare() {
  local bare seed
  bare="$(git_repo_bare acme parent)"
  seed="$(git_repo_scratch seed-parent)"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'base\n' 'base commit'
  git_repo_checkout "$seed" trunk main
  git_repo_push "$seed" "$bare" main trunk
  git_repo_bare_head "$bare" "$1"
  printf '%s\n' "$bare"
}

remote_has_branch() {
  if git -C "$1" show-ref --verify --quiet "refs/heads/$2"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# ---- step 1: is the branch on the remote at all? -------------------------
#
# Step 1 runs before anything else -- before any fact is asked for. The rows
# pass no facts, so the ones that get past it answer with the first NEED.
# `push-failure-stops` is the only row that installs a rejecting hook: it
# needs a push attempt to fail. `a-branch-already-on-the-remote-is-not-pushed-
# again` needs the opposite -- a push attempt that would actually transmit if
# it happened -- so it instead puts the work repo one commit ahead of the
# remote and reads the remote's tip directly; see that row's own comment for
# why a hook cannot observe this case.

row_start
fixture nowhere-b feature nowhere
run_in "$FIXTURE_WORK" feature
assert_row 'branch-nowhere-stops' 0 'STOP branch-nowhere\n' 0

row_start
fixture lsr feature remote
git_repo_remote "$FIXTURE_WORK" origin "${HARNESS_TMP}/repos/no-such-remote.git"
run_in "$FIXTURE_WORK" feature
assert_row 'ls-remote-failure-is-not-an-absent-branch' 0 'STOP ls-remote-failed\n' 0

row_start
fixture pushfail feature local
git_repo_deny_push "$FIXTURE_BARE"
run_in "$FIXTURE_WORK" feature
assert_row 'push-failure-stops' 0 'STOP push-failed\n' 0

row_start
fixture order feature local
run_in "$FIXTURE_WORK" feature
assert_row 'local-only-branch-is-pushed-before-anything-is-asked' 0 'NEED target=acme/order head=acme:feature head.open-pr\n' 0
tally check_eq 'ordering-row-landed-on-the-remote' yes "$(remote_has_branch "$FIXTURE_BARE" feature)"

# A rejecting hook cannot be used to prove this row's point: `fixture ...
# remote` leaves the work repo's branch byte-identical to the remote's copy,
# and re-pushing an identical ref is a no-op -- git prints "Everything
# up-to-date" and the push never reaches `pre-receive` at all (measured). So
# the work repo is put one commit ahead of the remote instead, which makes a
# redundant push something that would really transmit, and the remote's tip
# is captured before the SUT runs and compared against it afterward -- a
# direct check that no push reached the remote, rather than one that depends
# on a hook the redundant case cannot trigger.
row_start
fixture nopush feature remote
git_repo_commit "$FIXTURE_WORK" T2.md 'ahead\n' 'a commit the remote does not have'
NOPUSH_TIP="$(git -C "$FIXTURE_BARE" rev-parse "refs/heads/feature")"
run_in "$FIXTURE_WORK" feature --facts "$({ own nopush 1 12; record 12 true; } | facts_file)"
assert_row 'a-branch-already-on-the-remote-is-not-pushed-again' 0 'PR 12 found draft=true url=https://example.invalid/pull/12\n' 0
tally check_eq 'no-redundant-push-moved-the-remote' "$NOPUSH_TIP" "$(git -C "$FIXTURE_BARE" rev-parse "refs/heads/feature")"

row_start
fixture othercheckout feature local
git_repo_checkout "$FIXTURE_WORK" main
run_in "$FIXTURE_WORK" feature
assert_row 'the-named-branch-is-pushed-not-the-checked-out-one' 0 'NEED target=acme/othercheckout head=acme:feature head.open-pr\n' 0
tally check_eq 'named-branch-landed-not-the-checked-out-one' yes "$(remote_has_branch "$FIXTURE_BARE" feature)"

# ---- step 2: the branch's own PR -----------------------------------------

row_start
fixture exists-draft feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own exists-draft 1 12; record 12 true; } | facts_file)"
assert_row 'existing-draft-pr-is-reported' 0 'PR 12 found draft=true url=https://example.invalid/pull/12\n' 0

row_start
fixture exists-ready feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own exists-ready 1 12; record 12 false; } | facts_file)"
assert_row 'existing-ready-pr-is-reported' 0 'PR 12 found draft=false url=https://example.invalid/pull/12\n' 0

row_start
fixture one-pr feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own one-pr 1 12 | facts_file)"
assert_row 'one-pr-asks-for-its-record' 0 'NEED pr.number=12 pr.head.ref=feature pr.head.owner=acme pr.draft pr.url\n' 0

row_start
fixture list-unread feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own list-unread '' | facts_file)"
assert_row 'list-unreadable-is-not-an-absent-pr' 0 'STOP fact-missing\n' 0

row_start
fixture list-short feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own list-short 3 12 | facts_file)"
assert_row 'list-cut-short' 0 'STOP fact-count\n' 0

row_start
fixture multi feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own multi 2 12 13 | facts_file)"
assert_row 'several-prs-for-one-branch-stop' 0 'STOP ask-multiple-prs\n' 0

row_start
fixture head-ignored feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own head-ignored 1 12; record 12 true other; } | facts_file)"
assert_row 'head-filter-ignored-stops' 0 'STOP fact-mismatch\n' 0

# the same branch name under another owner is a different head
row_start
fixture owner-ignored feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own owner-ignored 1 12; HEAD_OWNER=other-fork record 12 true; } | facts_file)"
assert_row 'same-named-head-from-another-owner-stops' 0 'STOP fact-mismatch\n' 0

row_start
fixture owner-ignored-created feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$({ own owner-ignored-created 1 7; HEAD_OWNER=other-fork record 7 true feature main; } | facts_file)"
assert_row 'created-from-another-owner-stops' 0 'STOP fact-mismatch\n' 0

row_start
fixture numeric 1234 remote
run_in "$FIXTURE_WORK" 1234
assert_row 'a-numeric-branch-name-is-pinned-as-a-head' 0 'NEED target=acme/numeric head=acme:1234 head.open-pr\n' 0

row_start
fixture other-repo feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own other-repo 1 12 | sed 's|^target=.*|target=upstream/other-repo|' | facts_file)"
assert_row 'pr-read-in-another-repo' 0 'STOP fact-mismatch\n' 0

# ---- step 2b: who decides the target repository --------------------------
#
# A fork whose branch already has a PR reports the PR, never STOP
# ask-base-repo -- the step-2 rows above prove it by carrying no fork fact at
# all.

row_start
fixture fork-origin feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own fork-origin 0; fork fork-origin 1 true; } | facts_file)"
assert_row 'origin-only-fork-without-base-repo-stops' 0 'STOP ask-base-repo\n' 0

row_start
fixture fork-absent feature remote
run_in "$FIXTURE_WORK" feature --facts "$(own fork-absent 0 | facts_file)"
assert_row 'fork-fact-absent-asks-not-assumes' 0 'NEED repo=acme/fork-absent repo.fork\n' 0

row_start
fixture fork-unread feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own fork-unread 0; fork fork-unread ''; } | facts_file)"
assert_row 'fork-fact-unread-stops' 0 'STOP fact-missing\n' 0

# A repository search that missed the fork reports total 0, written as read.
row_start
fixture fork-none feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own fork-none 0; fork fork-none 0; } | facts_file)"
assert_row 'fork-search-found-nothing-stops' 0 'STOP fork-unread\n' 0

row_start
fixture fork-enum feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own fork-enum 0; fork fork-enum 1 yes; } | facts_file)"
assert_row 'fork-fact-out-of-enum-stops' 0 'STOP fact-enum\n' 0

row_start
fixture remote-w feature remote
git_repo_remote "$FIXTURE_WORK" upstream 'https://github.com/acme-upstream/remote-w.git'
run_in "$FIXTURE_WORK" feature --facts "$(own remote-w 0 | facts_file)"
assert_row 'another-remote-without-base-repo-stops' 0 'STOP ask-base-repo\n' 0

# A given base repository skips the fork question: the file carries no
# `repo.fork` line and no trailer exists.
row_start
fixture base-eq feature remote
run_in "$FIXTURE_WORK" feature acme/base-eq --facts "$(own base-eq 0 | facts_file)"
assert_row 'base-repo-equal-to-origin-is-unqualified' 0 'CREATE repo=acme/base-eq head=feature base=main\n' 0

row_start
fixture base-case feature remote
run_in "$FIXTURE_WORK" feature ACME/BASE-CASE --facts "$(own base-case 0 | facts_file)"
assert_row 'base-repo-is-lower-cased' 0 'CREATE repo=acme/base-case head=feature base=main\n' 0

# The one parent-target row that adds the remote. The bare is also origin's
# sibling path, so it does not tell the two rungs apart:
# resolve-default-branch_test.sh `repo-arg-selects-its-remote` pins the match.
row_start
fixture parent-q feature remote
git_repo_remote "$FIXTURE_WORK" upstream "$(parent_bare main)"
run_in "$FIXTURE_WORK" feature acme/parent --facts "$(own parent 0 | facts_file)"
assert_row 'parent-target-qualifies-the-head' 0 'CREATE repo=acme/parent head=acme:feature base=main\n' 0

# The second call after `origin-only-fork-without-base-repo-stops`: no
# `upstream` remote, so the parent's default branch is read at origin's sibling
# path.
row_start
fixture fork-parent feature remote
parent_bare main >/dev/null
run_in "$FIXTURE_WORK" feature acme/parent --facts "$(own parent 0 | facts_file)"
assert_row 'origin-only-fork-parent-chosen-creates' 0 'CREATE repo=acme/parent head=acme:feature base=main\n' 0

row_start
fixture parent-gone feature remote
run_in "$FIXTURE_WORK" feature acme/nosuch --facts "$(own nosuch 0 | facts_file)"
assert_row 'parent-unreachable-stops' 0 'STOP ask-default-branch\n' 0

# The parent's default (`trunk`) is one origin does not have, so the default
# fetch is what fails.
row_start
fixture parent-trunk feature remote
parent_bare trunk >/dev/null
run_in "$FIXTURE_WORK" feature acme/parent --facts "$(own parent 0 | facts_file)"
assert_row 'parent-default-absent-on-origin' 0 'STOP default-fetch-failed\n' 0

row_start
fixture parent-found feature remote
run_in "$FIXTURE_WORK" feature acme/parent --facts "$({ own parent 1 12; record 12 true; } | facts_file)"
assert_row 'parent-target-existing-pr-is-reported' 0 'PR 12 found draft=true url=https://example.invalid/pull/12\n' 0

# ---- step 3: the base, resolved by the real sibling ----------------------
#
# ensure-draft-pr.sh does not take a base as an argument: once it has decided
# a PR must be created, it asks its sibling resolve-pr-base.sh for one --
# reached the same way, through dirname -- "$0" -- and passes the
# answer straight through unchanged. The sibling is not stubbed, so these rows
# drive its own decision tree through fixtures, a facts file and the remote's
# HEAD; the text each row expects on stdout is the sibling's
# own text. #205 puts an exhaustive test of the sibling out of scope -- #186
# owns that -- so what is under test here is only that each answer arrives and
# that no CREATE is printed when the answer is a stop.
#
# Every fixture below is `fixture <name> feature remote [<trailer>]`, and
# every row's file says no PR and "not a fork", so control always reaches the
# sibling.

row_start
fixture prereq-ask feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-ask 0; fork prereq-ask 1 false; } | facts_file)"
assert_row 'base-resolution-asks-for-the-prerequisite' 0 'NEED prereq.head=acme:dep prereq.head-pr\n' 0

row_start
fixture prereq-open feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-open 0; one_repo_fork false; prereq_facts acme/prereq-open acme:dep 1 9 OPEN; } | facts_file)"
assert_row 'an-open-prerequisite-becomes-the-base' 0 'CREATE repo=acme/prereq-open head=feature base=dep\n' 0

row_start
fixture prereq-merged feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-merged 0; one_repo_fork false; prereq_facts acme/prereq-merged acme:dep 1 9 MERGED; } | facts_file)"
assert_row 'a-merged-prerequisite-falls-back-to-the-default-branch' 0 'CREATE repo=acme/prereq-merged head=feature base=main\n' 0

row_start
fixture prereq-abandoned feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-abandoned 0; one_repo_fork false; prereq_facts acme/prereq-abandoned acme:dep 1 9 CLOSED; } | facts_file)"
assert_row 'base-stop-prerequisite-abandoned' 0 'STOP abandoned-prerequisite\n' 0

row_start
fixture prereq-none feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-none 0; one_repo_fork false; prereq_facts acme/prereq-none acme:dep 0; } | facts_file)"
assert_row 'base-stop-prerequisite-has-no-pr' 0 'STOP no-prereq-pr\n' 0

row_start
fixture prereq-several feature remote dep
run_in "$FIXTURE_WORK" feature --facts "$({ own prereq-several 0; one_repo_fork false; prereq_facts acme/prereq-several acme:dep 2 9; printf 'prereq.head-pr=8\n'; } | facts_file)"
# Prints the same slug, STOP ask-multiple-prs, as several-prs-for-one-branch-
# stop -- both are intended, and deliberately not redundant: one comes from
# the SUT's own branch list, the other from the sibling's prerequisite facts.
assert_row 'base-stop-prerequisite-has-several-prs' 0 'STOP ask-multiple-prs\n' 0

row_start
fixture default-unknown feature remote
git_repo_bare_head "$FIXTURE_BARE" nosuch
run_in "$FIXTURE_WORK" feature --facts "$({ own default-unknown 0; fork default-unknown 1 false; } | facts_file)"
assert_row 'base-stop-default-branch-unknown' 0 'STOP ask-default-branch\n' 0

row_start
fixture empty-list feature remote
run_in "$FIXTURE_WORK" feature --facts "$({ own empty-list 0; fork empty-list 1 false; } | facts_file)"
assert_row 'an-empty-list-is-no-pr-and-the-base-is-resolved' 0 'CREATE repo=acme/empty-list head=feature base=main\n' 0

# ---- the read-back after the agent's own create --------------------------
#
# The agent opens the PR; a second call with --created <base> and facts read
# afresh finds it again.

row_start
fixture created feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$({ own created 1 7; record 7 true feature main; } | facts_file)"
assert_row 'created-pr-reads-back' 0 'PR 7 created draft=true base=main url=https://example.invalid/pull/7\n' 0

row_start
fixture created-ask feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$(own created-ask 1 7 | facts_file)"
assert_row 'read-back-asks-for-the-record' 0 'NEED pr.number=7 pr.head.ref=feature pr.head.owner=acme pr.base.ref=main pr.draft pr.url\n' 0

row_start
fixture not-created feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$(own not-created 0 | facts_file)"
assert_row 'a-record-that-does-not-read-back-stops' 0 'STOP pr-not-created\n' 0

row_start
fixture several-after-create feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$(own several-after-create 2 7 8 | facts_file)"
assert_row 'several-prs-after-create-stop' 0 'STOP ask-multiple-prs-after-create\n' 0

# Was pr-readback-failed.
row_start
fixture readback-unread feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$(own readback-unread '' | facts_file)"
assert_row 'read-back-unreadable-is-not-a-missing-record' 0 'STOP fact-missing\n' 0

row_start
fixture other-base feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$({ own other-base 1 7; record 7 true feature dep; } | facts_file)"
assert_row 'created-on-another-base-stops' 0 'STOP fact-mismatch\n' 0

row_start
fixture other-head feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$({ own other-head 1 7; record 7 true decoy main; } | facts_file)"
assert_row 'created-from-another-head-stops' 0 'STOP fact-mismatch\n' 0

# The file from the create path still says there is no PR: reading back from
# it is "not created", never the earlier answer replayed.
row_start
fixture stale feature remote
run_in "$FIXTURE_WORK" feature --created main --facts "$({ own stale 0; fork stale 1 false; } | facts_file)"
assert_row 'stale-file-on-read-back-stops' 0 'STOP pr-not-created\n' 0

row_start
fixture parent-rb feature remote
run_in "$FIXTURE_WORK" feature acme/parent --created main --facts "$({ own parent 1 7; record 7 true feature main; } | facts_file)"
assert_row 'parent-target-read-back' 0 'PR 7 created draft=true base=main url=https://example.invalid/pull/7\n' 0

# ---- argument validation -------------------------------------------------
#
# Each row builds its own fixture and calls row_start of its own, like
# every other row in this file: gh_call_count reads ${GH_STUB_DIR}/count, and
# only stub_dir_new resets it, so without a reset the first of these rows
# would read the calls the previous row's fixture left behind and fail `want
# gh calls: 0` against a perfectly correct SUT. Each row runs from a work repo
# that could have answered, so a failure here is the guard's and not the
# fixture's.

row_start
fixture args-none feature remote
run_in "$FIXTURE_WORK"
assert_row 'no-arguments' 2 '' 0

# The old <branch> <title> <body-file> form is now a usage error.
row_start
fixture args-three feature remote
run_in "$FIXTURE_WORK" feature 'a title' body.md
assert_row 'three-positionals' 2 '' 0

row_start
fixture args-facts feature remote
run_in "$FIXTURE_WORK" feature --facts
assert_row 'facts-flag-without-file' 2 '' 0

row_start
fixture args-created feature remote
run_in "$FIXTURE_WORK" feature --created
assert_row 'created-flag-without-base' 2 '' 0

row_start
fixture args-unknown feature remote
run_in "$FIXTURE_WORK" feature --base main
assert_row 'unknown-option' 2 '' 0

row_start
NO_ORIGIN="$(git_repo_scratch no-origin)"
git_repo_init "$NO_ORIGIN" main
run_in "$NO_ORIGIN" feature
assert_row 'no-origin' 0 'STOP repo-lookup-failed\n' 0

# ---- a base sibling that does not answer --------------------------------
#
# The real sibling prints only BASE/NEED/STOP on exit 0, which is why the
# step-3 rows above run it for real (#205 left the sibling unstubbed). These
# two rows pin the other side of that boundary in a copy of tools/: a sibling
# that aborts, and one that answers out of contract. Measured before the fix:
# exit 1 with empty stdout, and exit 1 with the error line on stderr -- no
# STOP either way, so the orchestrator saw "aborted", never "stopped".
#
#   These two rows are RED the ordinary way: point SUT= at the pre-fix script
#   (`git show e4395c8^:tools/ensure-draft-pr.sh`) dropped into a copy of
#   tools/ that holds every sibling, and only those two rows and the one
#   stderr tally fail: `not ok 3/59`.
CONTRACT="${HARNESS_TMP}/tools-contract"
cp -R "${REPO_ROOT}/tools" "$CONTRACT"
cp "$SUT" "${CONTRACT}/ensure-draft-pr.sh"

# sibling <body> -- the copy's resolve-pr-base.sh becomes a script of <body>.
sibling() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/resolve-pr-base.sh"; }

# run_contract <work-dir> <argv...> -- run_in, for the copy's script.
run_contract() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "${CONTRACT}/ensure-draft-pr.sh" "$@"
  cd "$REPO_ROOT" || exit 1
}

row_start
fixture sibling-abort feature remote
sibling 'exit 1'
run_contract "$FIXTURE_WORK" feature --facts "$({ own sibling-abort 0; fork sibling-abort 1 false; } | facts_file)"
assert_row 'base-sibling-abort-is-reported' 0 'STOP base-resolve-failed\n' 0

row_start
fixture sibling-garbage feature remote
sibling 'echo WHAT'
run_contract "$FIXTURE_WORK" feature --facts "$({ own sibling-garbage 0; fork sibling-garbage 1 false; } | facts_file)"
assert_row 'base-sibling-garbage-is-reported' 0 'STOP base-resolve-failed\n' 0
tally check_eq 'base-sibling-garbage: stderr' \
  'unexpected output from resolve-pr-base.sh: WHAT' "$(cat "$SUT_STDERR")"

harness_exit "$failed" "$total"
