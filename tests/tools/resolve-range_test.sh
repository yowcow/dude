#!/usr/bin/env bash
# Table test for tools/resolve-range.sh: which of its
# two input shapes -- a PR number, or none -- the script resolves a reviewed
# range from, and the exact line it prints for each answer.
#
# git is not stubbed. The range is the thing under test, and a git stub would
# encode the test author's belief about what a range should be rather than
# git's own behaviour -- exactly the failure mode tests/tools'
# resolve-pr-base_test.sh documents for the same reason. Each row that reaches
# the no-PR path with the real reader therefore builds a real bare repository
# to play the remote and a real work repository cloned from it, both under
# $HARNESS_TMP and both offline. The seven rows at the end stub the reader,
# the default-branch lookup, the fetch and facts.sh in a copy of tools/, and
# build no repository.
#
# The PR shape reads the PR record's base oid as a fact (pr_facts below), so
# its rows make no `gh` call at all; the gh call count is 0 throughout.
#
# The no-argument shape reads the prerequisite's PR as facts (prereq_facts
# below), so its trailer rows make no `gh pr list` call; the rows without a
# trailer pass no facts, which is what shows that path asks for nothing. Its
# default branch is the remote's own HEAD (resolve-default-branch.sh) in every
# row but the seven stubbed ones at the end; no row stubs `gh`.
#
# RED verification (see tests/README.md). The reader guard this file's last
# rows pin is RED the ordinary way -- the recipe and the measured count are in
# the reader-boundary record below. The other guards named in the script's own
# header were removed instead, one at a time, in a copy under `mktemp -d` --
# never inside the repository, where lint.sh would select it by shebang -- and
# this file re-run against it as `SUT=<copy> tests/run.sh <this file>`. Records
# 1, 3, 5 and 7 replace a guard in a sibling (read-base-trailer.sh or
# resolve-default-branch.sh); records 2, 4, 6, 8 and 9 replace one in this
# script (the MERGED fetch spec, emit_range, the OPEN fetch spec, the bounded
# scan's `^<tip>` argument, the NO-TRAILER merge-base). Every mutant is applied
# inside a copy of the tools/ tree regardless, because every row that reaches
# the script's body reaches a sibling through `dirname "$0"` first: a lone copy
# of this script answers `STOP ask-default-branch` (or `STOP repo-lookup-
# failed`) instead, which pins nothing about the mutation. The stubbed rows at
# the end build that tree themselves, so for them a lone copy of the SUT is
# enough. Nine were removed and are bound below; the one that is only partly
# observable is recorded as such, rather than counted as covered. What each
# mutant actually produced, measured:
#
#   1. The trailer read guarded as well as captured. This guard lives in
#      tools/read-base-trailer.sh, so the mutant is applied there, in a copy
#      of the tools/ tree. Appending `|| true` to the `git log` inside the
#      `if ! TRAILER_LOG=...` test failed `trailer-read-fails` alone: want
#      `STOP trailer-read-failed`, got `STOP merge-base-failed`. That is the
#      widening this file exists to pin -- a read that failed, taken for a
#      trailer that was absent, sends the range to the default branch.
#   2. The MERGED boundary being the prerequisite's own head
#      (the PREREQ_PR fetch spec). Replacing
#      `FETCH_SPEC="refs/pull/${PREREQ_PR}/head"` with
#      `FETCH_SPEC="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")"`
#      in a copy of the tools/ tree (the call resolves through `dirname "$0"`)
#      failed `prereq-merged-uses-the-pr-head` and `merged-pull-ref-absent`
#      on stdout, and the second assertion of the first row,
#      `merged-base-is-not-the-default-branch`, flagged that the range then
#      started at the default branch tip -- the widening this guard exists to
#      prevent.
#   3. A count of zero PRs being "no prerequisite PR". This guard lives in
#      read-base-trailer.sh, so the mutant is applied there, in the same
#      tree copy as record 1. Deleting the `[ "$COUNT" -eq 0 ]` block failed
#      `prereq-has-no-pr` alone: want `STOP no-prereq-pr`, got a `NEED` for the
#      PR record the empty list never named.
#   4. Both shapes answering through emit_range. Replacing its body with an
#      unconditional `echo "RANGE $1..$2"` failed both EMPTY rows --
#      `pr-shape-empty-when-head-is-the-base` and
#      `no-trailer-empty-when-head-is-the-default-tip`.
#   5. The default branch being read rather than guessed. That read lives in
#      the shared tools/resolve-default-branch.sh this script reaches by its
#      no-argument shape, so the mutant is a copy of the tools/ tree with that
#      script's whole body replaced by `printf 'main\n'`. It failed nineteen
#      rows on stdout -- every row that reaches the default branch except
#      `default-fetch-fails`, whose fixture remote already lacks a `main`
#      branch and whose stdout already expects `STOP default-fetch-failed`.
#      This is why build_remote's default branch is called `trunk`: with the
#      conventional name, this mutant passes every row.
#   6. OPEN fetching the branch the trailer recorded (the OPEN arm).
#      Replacing `FETCH_SPEC="${RECORDED}"` with the MERGED path's
#      `refs/pull/${PREREQ_PR}/head` failed `prereq-open-uses-its-branch` and
#      two others. This is why `refs/pull/9/head` is a decoy under
#      `with-dep`: pointed at dep's own commit, this mutant passes.
#   7. The trailer scan keeping the newest trailer. This guard lives in
#      read-base-trailer.sh (`awk 'NF{print;exit}'`), so the mutant is applied
#      there, in the same tree copy as records 1 and 3. Replacing it with
#      `awk 'NF{l=$0}END{print l}'` holds the last non-empty line -- the
#      oldest, since the log is newest-first -- and failed ten rows, among them
#      `newest-trailer-shadows-older`, which answered `STOP fact-mismatch`
#      rather than the range: the facts name `dep`, the oldest trailer names
#      `older-base`. `older-base` is also a ref on the fixture remote, so a
#      mutant that fetched it would not stop at `STOP fetch-failed`.
#   8. The trailer scan stopping at the default tip.
#      build_remote's `trunk` advances one commit past `older-base` recording
#      `Base-Branch: older-base`, so `plain`'s only trailer is the poisoned
#      trunk history below its own tip. Removing `^${TIP_SHA}` from the
#      read-base-trailer.sh call failed `trunk-history-trailer-is-ignored` on
#      stdout (want `RANGE <trunk>..<plain>`), and with it `stale-symref-is-ignored`,
#      `no-trailer-uses-the-remote-head` and
#      `no-trailer-empty-when-head-is-the-default-tip`, which also record
#      nothing of their own.
#   9. The NO-TRAILER merge-base guard. Leaving `BASE_SHA="$(git merge-base
#      "${TIP_SHA}" HEAD)"` bare, so `set -e` aborts on git's exit 1 instead of
#      printing the STOP, failed `merge-base-fails-without-a-trailer` alone:
#      want `STOP merge-base-failed`, got exit 1 with empty stdout. Its PREREQ
#      twin was already bound by `merge-base-fails-on-unrelated-history`, whose
#      branch records a trailer; without this row the trailerless copy of the
#      same guard could be deleted unnoticed.
#
#   The `[repo]` fallback's two `exit 1`s are recorded rather than bound here,
#   and for neither is the reason "no row could bind it". The
#   `git remote get-url origin` read: what no row can separate is the read
#   failing and falling through -- URL is then empty, so url_dir and owner
#   are empty too and the next guard answers the same exit 1 with the same
#   empty stdout. A row can separate a mutant that drops the read altogether,
#   where `set -e` relays git's status 2 (measured) instead of this guard's 1.
#   The empty owner segment is bindable and left unbound because this issue's
#   scope is the two test files above: an origin URL whose directory part has
#   no segment (a bare `/`, or `/repo.git`) leaves url_dir empty, so the
#   mutant derives the relative remote `acme/parent.git`, and a bare repo
#   planted at that path inside the work tree, HEAD on `trunk`, makes it
#   answer `trunk` with exit 0 where the guard answers exit 1 with empty
#   stdout. Such a row belongs in tests/tools/resolve-default-branch_test.sh;
#   recorded here as a gap, not as an impossible case.
#
#   The reader-boundary rows at the end of this file are RED through SUT= the
#   ordinary way, not by removing a guard: point it at the pre-fix script
#   (`git show 9738174^:tools/resolve-range.sh`) dropped into a copy of tools/
#   that holds every sibling -- the same tree records 1-3 and 5-8 need -- and
#   only those four rows and their two stderr tallies fail: `not ok 6/39`,
#   measured before the facts-capture rows existed. The three facts-capture
#   rows at the end were RED the same way, against the `master` of the time in
#   a full tools/ tree: `not ok 3/42`. Neither figure is today's file:
#   `9738174^` predates the facts capture, so it fails those rows too --
#   measured `not ok 9/43` -- while today's `master` carries the capture and
#   passes `ok 43/43`.
#   Measured: the aborted reader exits 1 with empty stdout, and the answers
#   its `case` does not name reach the fetch line with FETCH_SPEC unset, which
#   answers STOP fetch-failed, with bash's `FETCH_SPEC: unbound variable`
#   diagnostic on stderr beside it.
#
# Partly covered, and measured to be no more coverable than this: reading
# FETCH_HEAD rather than a remote-tracking ref.
# Replacing `git merge-base FETCH_HEAD HEAD` with
# `git merge-base "origin/${FETCH_SPEC}" HEAD` failed exactly one row,
# `prereq-merged-uses-the-pr-head` -- `refs/pull/<n>/head` lies outside every
# clone's fetch refspec, so there is no tracking ref to read and the mutant
# cannot resolve a base at all. The branch-name half of that guard is not
# observable from a range: measured on git 2.43, `git fetch origin -- <branch>`
# opportunistically updates `refs/remotes/origin/<branch>` as well, so once the
# fetch has run the tracking ref and FETCH_HEAD name the same commit and no
# assertion can separate them.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/resolve-range.sh}"

failed=0
total=0

# build_remote <name> <with-dep|no-dep> -- prints the path of a new bare repo.
#
# The default branch here is called `trunk`, never `main`, and that is the
# point rather than a flourish: the script's header promises it never guesses
# a branch name, and a fixture whose default branch carries the conventional
# name cannot tell a lookup from a guess -- an implementation that skipped
# reading the remote's HEAD and hard-coded `main` would produce the expected
# range. With `trunk`, only the lookup can answer it. Every bare repo's HEAD
# is pointed at `trunk` (git_repo_bare leaves it on an unborn `master`).
#
# The branches. `trunk` carries the one base commit; `older-base` is cut from
# it immediately after, a decoy that exists only so a scan reading the stack
# oldest-first prints a wrong *range* rather than failing to fetch a ref that
# was never there. Then `dep` (off trunk, one commit, no trailer -- a
# prerequisite branch of its own); `task` (off dep, TWO commits, the older
# recording `Base-Branch: older-base` and the newer `Base-Branch: dep`, so a
# scan reading the stack in the wrong order picks a different answer); and
# back at trunk, `plain` (one commit, no trailer) and `fresh` (no commit of
# its own, so it sits exactly on trunk's tip). Trunk itself advances one commit
# past `older-base` recording `Base-Branch: older-base`: the bounded scan
# `HEAD ^trunk-tip` excludes it, while an unbounded scan finds it instead. Every branch points at a fixed
# commit, so the order they are cut in matters only to how this reads.
#
# Two pushes. The branch list omits `dep` alone when the second argument is
# `no-dep` -- `task` is always pushed, and pushing it carries dep's commit
# object along as part of task's own history, so the commit stays reachable
# while the branch ref is gone. That is precisely the state a merged
# prerequisite leaves behind: the branch deleted, the commits still there.
#
# The second push is `refs/pull/9/head`, and which commit it names differs by
# mode on purpose. Under `no-dep` it is `dep` -- what a MERGED prerequisite's
# own head survives as once the branch is deleted. Under `with-dep` it is
# `plain`, a commit that is *not* an ancestor of `task`, so it is a decoy: the
# OPEN rows must fetch the recorded branch, and pointing both refs at one
# commit would let an implementation that fetched the pull ref instead pass
# the OPEN assertions exactly.
build_remote() {
  local name="$1" depmode="$2" bare seed branches pull9
  bare="$(git_repo_bare acme "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" trunk
  git_repo_commit "$seed" README.md 'base\n' "$(commit_msg 'base commit' -)"
  git_repo_checkout "$seed" older-base trunk
  git_repo_checkout "$seed" trunk
  git_repo_commit "$seed" TRUNK-POISON.md 'poison\n' "$(commit_msg 'trunk poison' older-base)"
  git_repo_checkout "$seed" dep trunk
  git_repo_commit "$seed" DEP.md 'dep\n' "$(commit_msg 'dep commit' -)"
  git_repo_checkout "$seed" task dep
  git_repo_commit "$seed" T1.md 'task one\n' "$(commit_msg 'task commit 1' older-base)"
  git_repo_commit "$seed" T2.md 'task two\n' "$(commit_msg 'task commit 2' dep)"
  git_repo_checkout "$seed" trunk
  git_repo_checkout "$seed" plain trunk
  git_repo_commit "$seed" PLAIN.md 'plain\n' "$(commit_msg 'plain commit' -)"
  git_repo_checkout "$seed" fresh trunk
  if [ "$depmode" = with-dep ]; then
    branches='trunk dep task plain fresh older-base'
    pull9='plain:refs/pull/9/head'
  else
    branches='trunk task plain fresh older-base'
    pull9='dep:refs/pull/9/head'
  fi
  # shellcheck disable=SC2086
  git_repo_push "$seed" "$bare" $branches
  git_repo_push "$seed" "$bare" "$pull9"
  git_repo_bare_head "$bare" trunk
  printf '%s\n' "$bare"
}

# bare_sha <bare-repo> <rev> -- the sha <rev> resolves to in <bare-repo>. Any
# rev, not just a branch: the MERGED rows need `refs/pull/9/head`, which is
# the one boundary in this file that is deliberately not a branch at all.
bare_sha() {
  git -C "$1" rev-parse "$2"
}

# work_repo <name> <origin-url> <checkout-branch> <origin-head|-> -- prints
# the path of a work repository cloned for real from <origin-url> with
# <checkout-branch> checked out, so HEAD holds real commits the way any clone
# of one of build_remote's branches would. refs/remotes/origin/HEAD is set to
# <origin-head> unless that is `-`, which leaves what the clone wrote itself:
# the bare repo's HEAD names `trunk`, so a real clone points
# refs/remotes/origin/HEAD at it.
work_repo() {
  local dir
  dir="$(git_repo_clone "$1" "$2" "$3")"
  if [ "$4" != '-' ]; then
    git_repo_origin_head "$dir" "$4"
  fi
  printf '%s\n' "$dir"
}

# pr_facts <pr> <base-sha> [<repo>] -- prints a facts path: the PR record's
# base oid, read for the one PR in the one repository the script asked about.
pr_facts() {
  facts_file <<EOF
repo=${3:-acme/prremote}
pr.number=$1
pr.base.sha=$2
EOF
}

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

# ---- the PR-number shape: the PR's own endpoints, fetched --------------
#
# `prremote` plays the base repository. The work clone is taken while trunk
# sits on its one commit, and only afterwards does the PR head appear
# (as `refs/pull/7/head` alone, no branch) and trunk advance past the fork
# point -- so the clone holds neither the head nor the base's current tip,
# which is what a reviewer's checkout of somebody else's PR looks like.
PRREMOTE="$(git_repo_bare acme prremote)"
PRSEED="$(git_repo_scratch prseed)"
git_repo_init "$PRSEED" trunk
git_repo_commit "$PRSEED" README.md 'base\n' "$(commit_msg 'base commit' -)"
git_repo_push "$PRSEED" "$PRREMOTE" trunk
FORK_SHA="$(git -C "$PRSEED" rev-parse HEAD)"
PRWORK="$(git_repo_clone prwork "$PRREMOTE" trunk)"
git_repo_checkout "$PRSEED" pr trunk
git_repo_commit "$PRSEED" PR.md 'pr\n' "$(commit_msg 'pr commit' -)"
PRHEAD_SHA="$(git -C "$PRSEED" rev-parse HEAD)"
git_repo_push "$PRSEED" "$PRREMOTE" pr:refs/pull/7/head
git_repo_push "$PRSEED" "$PRREMOTE" "${FORK_SHA}:refs/pull/10/head"
git_repo_checkout "$PRSEED" trunk
git_repo_commit "$PRSEED" LATER.md 'later\n' "$(commit_msg 'base moved on' -)"
MOVED_SHA="$(git -C "$PRSEED" rev-parse HEAD)"
git_repo_push "$PRSEED" "$PRREMOTE" trunk
PRUNREL="$(git_repo_scratch prunrel)"
git_repo_init "$PRUNREL" other
git_repo_commit "$PRUNREL" O.md 'other\n' "$(commit_msg 'unrelated root' -)"
git_repo_push "$PRUNREL" "$PRREMOTE" other:refs/pull/9/head

row_start
run_in "$PRWORK" 7
assert_row 'pr-shape-without-facts-asks' 0 'NEED repo=acme/prremote pr.number=7 pr.base.sha\n' 0

row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 7 "$FORK_SHA")"
assert_row 'pr-shape-fetches-the-missing-head' 0 "RANGE ${FORK_SHA}..${PRHEAD_SHA}\n" 0

# The record's base oid here is the base branch's *current* tip, which the
# clone has never fetched and which is not an ancestor of the head. Taken as
# the range's left end it would show LATER.md as a deletion by the PR.
row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 7 "$MOVED_SHA")"
assert_row 'pr-shape-base-moved-on-uses-merge-base' 0 "RANGE ${FORK_SHA}..${PRHEAD_SHA}\n" 0

row_start
run_in "$PRWORK" 10 --facts "$(pr_facts 10 "$FORK_SHA")"
assert_row 'pr-shape-empty-when-head-is-the-base' 0 'EMPTY\n' 0

row_start
run_in "$PRWORK" 8 --facts "$(pr_facts 8 "$FORK_SHA")"
assert_row 'pr-shape-head-fetch-fails' 0 'STOP fetch-failed\n' 0

row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 7 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)"
assert_row 'pr-shape-base-fetch-fails' 0 'STOP fetch-failed\n' 0

row_start
run_in "$PRWORK" 9 --facts "$(pr_facts 9 "$FORK_SHA")"
assert_row 'pr-shape-merge-base-fails' 0 'STOP merge-base-failed\n' 0

row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 7 '')"
assert_row 'pr-base-unread' 0 'STOP fact-missing\n' 0

# A base oid read off another PR would pair this PR's head with that PR's
# base, a plausible range for the wrong change.
row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 8 "$FORK_SHA")"
assert_row 'pr-read-as-another-pr' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$PRWORK" 7 --facts "$(pr_facts 7 "$FORK_SHA" upstream/prremote)"
assert_row 'pr-read-in-another-repo' 0 'STOP fact-mismatch\n' 0

row_start
NOREPO_FAIL="$(git_repo_scratch pr-shape-no-origin)"
run_in "$NOREPO_FAIL" 7 --facts "$(pr_facts 7 "$FORK_SHA")"
assert_row 'pr-shape-no-origin' 0 'STOP repo-lookup-failed\n' 0

row_start
NOREPO="$(git_repo_scratch pr-shape-norepo)"
run_in "$NOREPO" 42 extra
assert_row 'too-many-arguments' 2 '' 0

row_start
run_in "$PRWORK" 7 --facts
assert_row 'pr-shape-facts-flag-without-file' 2 '' 0

REMOTE="$(build_remote ranged with-dep)"
TRUNK_SHA="$(bare_sha "$REMOTE" trunk)"
PLAIN_SHA="$(bare_sha "$REMOTE" plain)"

# ---- no trailer recorded: the default branch ----------------------------
#
# `plain` carries no Base-Branch trailer anywhere in its history, so each of
# these rows exercises the default-branch read and nothing else. The first
# plants a stale refs/remotes/origin/HEAD symref naming `task` -- the wrong
# branch -- while the remote's HEAD names `trunk`, the right one, then asserts
# the range comes from `trunk`: the symref is never consulted, so a stale
# answer sitting in it cannot steer the range even when it disagrees with the
# remote.

row_start
W="$(work_repo dflt-stale-symref "$REMOTE" plain task)"
run_in "$W"
assert_row 'stale-symref-is-ignored' 0 "RANGE ${TRUNK_SHA}..${PLAIN_SHA}\n" 0

row_start
W="$(work_repo dflt-head "$REMOTE" plain -)"
run_in "$W"
assert_row 'no-trailer-uses-the-remote-head' 0 "RANGE ${TRUNK_SHA}..${PLAIN_SHA}\n" 0

row_start
W="$(work_repo trunk-trailer-ignored "$REMOTE" plain -)"
run_in "$W"
assert_row 'trunk-history-trailer-is-ignored' 0 "RANGE ${TRUNK_SHA}..${PLAIN_SHA}\n" 0

row_start
W="$(work_repo dflt-unreachable "$REMOTE" plain -)"
git -C "$W" remote set-url origin "${HARNESS_TMP}/remotes/acme/nosuch.git"
run_in "$W"
assert_row 'default-branch-lookup-fails' 0 'STOP ask-default-branch\n' 0

row_start
W="$(work_repo dflt-unborn "$REMOTE" plain -)"
git -C "$W" remote set-url origin "$(git_repo_bare acme unborn)"
run_in "$W"
assert_row 'remote-head-unborn' 0 'STOP ask-default-branch\n' 0

# `fresh` sits exactly on trunk's tip, so the merge-base *is* HEAD -- the empty
# range, reached through the no-argument shape. Its counterpart for the PR
# shape is `pr-shape-empty-when-head-is-the-base` above; both spellings have to
# collapse to EMPTY, since a caller handed `RANGE <sha>..<sha>` would dispatch
# a reviewer over an empty diff and read the no-findings back as a clean
# review.
row_start
W="$(work_repo empty-nopr "$REMOTE" fresh trunk)"
run_in "$W"
assert_row 'no-trailer-empty-when-head-is-the-default-tip' 0 'EMPTY\n' 0

DEP_SHA="$(bare_sha "$REMOTE" dep)"
TASK_SHA="$(bare_sha "$REMOTE" task)"

# ---- a trailer the branch recorded itself -------------------------------

row_start
W="$(work_repo prereq-open "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 1 9 OPEN | facts_file)"
assert_row 'prereq-open-uses-its-branch' 0 "RANGE ${DEP_SHA}..${TASK_SHA}\n" 0

# `task` records `older-base` on its first commit and `dep` on its second, so
# the two orders of reading the stack disagree about the answer. The facts name
# `dep`, so an oldest-first scan asks about `older-base` and stops on the
# pinned head (`STOP fact-mismatch`) instead of printing the range.
row_start
W="$(work_repo shadow "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 1 9 OPEN | facts_file)"
assert_row 'newest-trailer-shadows-older' 0 "RANGE ${DEP_SHA}..${TASK_SHA}\n" 0

# ---- MERGED: the boundary is the prerequisite's own head ----------------
#
# This remote is built `no-dep`: branch `dep` never reached it, which is what
# a merged prerequisite leaves behind once its branch is deleted. Its commits
# are still reachable through `task`'s history, and its head still has a name
# -- `refs/pull/9/head` -- which is the only thing left to bound the range
# with. So an implementation fetching the recorded branch name reaches
# `STOP fetch-failed` here, and one falling back to the default branch prints
# a wider range that sweeps the prerequisite's whole diff into the review.
REMOTE_MERGED="$(build_remote merged no-dep)"
PULL9_SHA="$(bare_sha "$REMOTE_MERGED" refs/pull/9/head)"
MERGED_TASK_SHA="$(bare_sha "$REMOTE_MERGED" task)"
MERGED_TRUNK_SHA="$(bare_sha "$REMOTE_MERGED" trunk)"

row_start
W="$(work_repo prereq-merged "$REMOTE_MERGED" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/merged acme:dep 1 9 MERGED | facts_file)"
assert_row 'prereq-merged-uses-the-pr-head' 0 "RANGE ${PULL9_SHA}..${MERGED_TASK_SHA}\n" 0

# The measurement the row above is for, asserted on that same run: the base
# must not be the default branch's tip. The first branch is not decoration --
# "the base is not trunk's tip" proves nothing if the fixture made them the
# same commit, and that is exactly the accident a later edit to build_remote
# could introduce.
total=$((total + 1))
if [ "$PULL9_SHA" = "$MERGED_TRUNK_SHA" ]; then
  printf 'FAIL merged-base-is-not-the-default-branch: the fixture cannot discriminate -- refs/pull/9/head and trunk are the same commit\n'
  failed=$((failed + 1))
elif grep -q "RANGE ${MERGED_TRUNK_SHA}" "$SUT_STDOUT"; then
  printf 'FAIL merged-base-is-not-the-default-branch: the range starts at the default branch tip %s\n' "$MERGED_TRUNK_SHA"
  failed=$((failed + 1))
fi

# ---- the remaining prerequisite states ---------------------------------
#
# Each stops before any fetch, so the fixture's branches are irrelevant to
# them; what is under test is that four different "cannot proceed" causes
# stay four different answers rather than collapsing into one.

row_start
W="$(work_repo prereq-closed "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 1 9 CLOSED | facts_file)"
assert_row 'prereq-closed-stops' 0 'STOP abandoned-prerequisite\n' 0

row_start
W="$(work_repo prereq-none "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 0 | facts_file)"
assert_row 'prereq-has-no-pr' 0 'STOP no-prereq-pr\n' 0

row_start
W="$(work_repo prereq-multiple "$REMOTE" task trunk)"
run_in "$W" --facts "$({ prereq_facts acme/ranged acme:dep 2 9; printf 'prereq.head-pr=8\n'; } | facts_file)"
assert_row 'prereq-has-several-prs' 0 'STOP ask-multiple-prs\n' 0

# Changed answer: was prereq-lookup-fails / STOP prereq-lookup-failed, when the
# `gh` call failed.
row_start
W="$(work_repo prereq-unreadable "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep '' | facts_file)"
assert_row 'prereq-lookup-unread' 0 'STOP fact-missing\n' 0

# Changed answer: was exit 1 with an empty stdout.
row_start
W="$(work_repo prereq-unknown-state "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 1 9 DRAFT | facts_file)"
assert_row 'prereq-state-unrecognised' 0 'STOP fact-enum\n' 0

row_start
W="$(work_repo trailer-asks "$REMOTE" task trunk)"
run_in "$W"
assert_row 'trailer-without-facts-asks' 0 'NEED repo=acme/ranged prereq.head=acme:dep prereq.head-pr\n' 0

# ---- the three git failures the script converts into STOP ---------------
#
# The row this file exists for. A work repository with no commits at all
# makes `git log HEAD` exit 128 (measured on git 2.43: "fatal: ambiguous
# argument 'HEAD'"), which is the trailer read *failing* rather than the
# trailer being absent -- two causes that must not collapse, because "absent"
# sends the range to the default branch. refs/remotes/origin/HEAD is pointed
# at `trunk` for realism only -- the default-branch lookup never reads it, so it
# has no bearing on this row's answer. Fetch-first means the default resolve
# and fetch pass and the scan fails, so this row asserts that STOP order.
row_start
W="$(git_repo_scratch trailer-unreadable)"
git_repo_init "$W" task
git_repo_remote "$W" origin "$REMOTE"
git_repo_origin_head "$W" trunk
run_in "$W"
assert_row 'trailer-read-fails' 0 'STOP trailer-read-failed\n' 0

# Two fetches can fail, and they carry distinct slugs from different rungs.
# The first row's remote names a default it will not serve: `ls-remote
# --symref` still reports `trunk` as HEAD, but the fetch of `trunk` fails
# (hideRefs; measured on git 2.43, protocol v2 and v0), so the *default* fetch
# behind it is what fails (vs the prereq `fetch-failed`). It needs a remote of
# its own, since the shared $REMOTE must stay fetchable.
row_start
B="$(build_remote fetchdflt no-dep)"
W="$(work_repo fetch-dflt "$B" plain -)"
git -C "$B" config uploadpack.hideRefs refs/heads/trunk
run_in "$W"
assert_row 'default-fetch-fails' 0 'STOP default-fetch-failed\n' 0

# The second is the MERGED rung: `refs/pull/77/head` exists on no fixture
# remote, so the spec that fails is the one the MERGED path builds itself.
row_start
W="$(work_repo fetch-pull "$REMOTE" task trunk)"
run_in "$W" --facts "$(prereq_facts acme/ranged acme:dep 1 77 MERGED | facts_file)"
assert_row 'merged-pull-ref-absent' 0 'STOP fetch-failed\n' 0

# Unrelated roots, the spelling absorb-base_test.sh uses: two repositories
# that share no history, so the fetch succeeds and `git merge-base` is what
# fails -- exit 1 printing nothing (measured), which is indistinguishable
# from an answer unless the exit status is read.
row_start
LONELY="$(git_repo_bare acme lonely)"
LSEED="$(git_repo_scratch lonely-seed)"
git_repo_init "$LSEED" unrelated
git_repo_commit "$LSEED" only.txt 'unrelated\n' "$(commit_msg 'unrelated root' -)"
git_repo_push "$LSEED" "$LONELY" unrelated
git_repo_bare_head "$LONELY" unrelated
W="$(git_repo_scratch lonely-work)"
git_repo_init "$W" task
git_repo_commit "$W" task.txt 'task\n' "$(commit_msg 'task root' unrelated)"
git_repo_remote "$W" origin "$LONELY"
run_in "$W" --facts "$(prereq_facts acme/lonely acme:unrelated 1 9 OPEN | facts_file)"
assert_row 'merge-base-fails-on-unrelated-history' 0 'STOP merge-base-failed\n' 0

# An unrelated remote again (`LONELY`, from the row above), reached the other
# way: the branch records no trailer at all and the run passes no facts, so it
# takes the NO-TRAILER path, whose base is the default branch's tip. Nothing
# else in its answer would show that git declined to answer.
row_start
W="$(git_repo_scratch lonely-work-no-trailer)"
git_repo_init "$W" task
git_repo_commit "$W" task.txt 'task\n' "$(commit_msg 'task root' -)"
git_repo_remote "$W" origin "$LONELY"
run_in "$W"
assert_row 'merge-base-fails-without-a-trailer' 0 'STOP merge-base-failed\n' 0

# ---- the reader's answers this caller cannot act on ----------------------
#
# Same boundary as tests/tools/resolve-pr-base_test.sh's closing rows, and the
# same fixture: a copy of tools/ with this file's subject dropped in and
# read-base-trailer.sh replaced. The real reader cannot produce these answers
# (a state outside OPEN/MERGED/CLOSED stops earlier as STOP fact-enum, and
# CLOSED stops as STOP abandoned-prerequisite), so the reader
# is stubbed. Measured before the fix: a reader exiting 1 made this script exit
# 1 with empty stdout; an unknown KIND or STATE answered STOP fetch-failed
# while the script was in fact reading an unset FETCH_SPEC -- with bash's
# `FETCH_SPEC: unbound variable` diagnostic on stderr beside it -- a person
# sent to re-run a fetch that was never attempted.
CONTRACT="${HARNESS_TMP}/tools-contract"
cp -R "${REPO_ROOT}/tools" "$CONTRACT"
cp "$SUT" "${CONTRACT}/resolve-range.sh"
printf '#!/usr/bin/env bash\necho trunk\n' >"${CONTRACT}/resolve-default-branch.sh"
printf '#!/usr/bin/env bash\necho 1111111111111111111111111111111111111111\n' >"${CONTRACT}/fetch-to-sha.sh"

# reader <body> -- the copy's read-base-trailer.sh becomes a script of <body>.
reader() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/read-base-trailer.sh"; }

row_start
reader 'exit 1'
run_sut bash "${CONTRACT}/resolve-range.sh"
assert_row 'reader-abort-is-reported' 0 'STOP trailer-read-failed\n' 0

row_start
reader 'echo WHAT'
run_sut bash "${CONTRACT}/resolve-range.sh"
assert_row 'reader-unknown-kind-is-reported' 0 'STOP trailer-answer-malformed\n' 0
tally check_eq 'reader-unknown-kind: stderr' \
  'unrecognised answer from read-base-trailer.sh: WHAT' "$(cat "$SUT_STDERR")"

row_start
reader 'echo "PREREQ task 9 DRAFT"'
run_sut bash "${CONTRACT}/resolve-range.sh"
assert_row 'reader-unknown-state-is-reported' 0 'STOP trailer-answer-malformed\n' 0
tally check_eq 'reader-unknown-state: stderr' \
  'unrecognised prerequisite state: DRAFT' "$(cat "$SUT_STDERR")"

row_start
reader 'true'
run_sut bash "${CONTRACT}/resolve-range.sh"
assert_row 'reader-empty-answer-is-reported' 0 'STOP trailer-answer-malformed\n' 0

# ---- facts.sh that stops instead of answering ---------------------------
#
# Both the self-check and the read are captured, so an exit that is not
# relayed becomes empty stdout and a non-zero status. The PR shape is used
# because its first fact read is the one under test; the copy's facts.sh is
# replaced for these three rows only.
facts_stub() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/facts.sh"; }

# run_contract <work-dir> <argv...> -- run_in, for the copy's script.
run_contract() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "${CONTRACT}/resolve-range.sh" "$@"
  cd "$REPO_ROOT" || exit 1
}

row_start
facts_stub 'exit 1'
run_contract "$PRWORK" 7 --facts "$(facts_file </dev/null)"
assert_row 'facts-check-abort-is-reported' 0 'STOP facts-read-failed\n' 0

row_start
facts_stub 'echo WHAT'
run_contract "$PRWORK" 7 --facts "$(facts_file </dev/null)"
assert_row 'facts-check-answer-malformed-is-reported' 0 'STOP facts-answer-malformed\n' 0

row_start
facts_stub 'case "$1" in check) echo OK ;; *) exit 1 ;; esac'
run_contract "$PRWORK" 7 --facts "$(facts_file </dev/null)"
assert_row 'facts-get-abort-is-reported' 0 'STOP facts-read-failed\n' 0

harness_exit "$failed" "$total"
