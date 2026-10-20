#!/usr/bin/env bash
# Table test for tools/resolve-pr-base.sh: how far the
# Base-Branch trailer scan reaches, and the one line it prints for each answer.
#
# git is not stubbed. The defect this file exists to pin is a *range* defect --
# the scan walking past the branch point into shared history (#171) -- and a
# git stub would encode the test author's belief about that range rather than
# git's behaviour. Each row that drives the real reader builds a real bare
# repository to play the remote and a real work repository whose `origin`
# points at it, both under $HARNESS_TMP and both offline. Those work
# repositories hold no commits at all: the SUT reads the branch tip as
# FETCH_HEAD and never checks anything out. The rows at the end of this file
# stub the reader, the default-branch lookup and the fetch instead, and build
# no repository.
#
# The scan's range is the whole point, so the fixtures differ in exactly one
# axis: whether the Base-Branch trailer sits on the task branch's own commits
# or on a commit the task branch merely inherits from the default branch.
#
# `STOP trailer-read-failed` has a row: the stubbed-reader rows at the end of
# this file, which also pin the answers outside the reader's contract. The
# reader's own guard is covered by tests/tools/read-base-trailer_test.sh's
# `trailer-read-fails` row.
#
# The prerequisite's PR comes as facts (prereq_facts below) and, in every row
# but the three stubbed ones at the end, the default branch from the remote's
# own HEAD (resolve-default-branch.sh); every row asserts 0 gh calls.
#
# RED verification (see tests/README.md) -- the trailer scan used to walk to
# root, so a branch that recorded nothing picked up whatever Base-Branch it
# inherited from shared history and handed that branch back as --base (#171):
#   tmp="$(mktemp -d)"
#   git show bb8d8b8^:skills/pr-to-ready/scripts/resolve-pr-base.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/tools/resolve-pr-base_test.sh
#
#   A copy of the *current* script needs the whole tools/ tree beside it
#   (`cp -R tools "$tmp/tools"`, then `SUT="$tmp/tools/<copy>.sh"`): on every
#   row that reaches a real sibling it resolves that sibling through dirname
#   "$0", so a lone copy answers STOP ask-default-branch (or fails outright)
#   there and the failures say nothing about the mutation. The three stubbed
#   rows at the end are the exception -- they copy the SUT into a tools/ tree
#   that already holds every sibling, so a lone copy is enough for those. The
#   bb8d8b8^ version above predates the extractions and needs no sibling.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/resolve-pr-base.sh}"

failed=0
total=0

# build_remote <name> <main-trailer> <feature-trailer>... -- prints the path of
# a new bare repo holding `main` (one commit) and `feature` (one commit per
# feature-trailer, branched off main), its HEAD on `main`. Each trailer argument
# is a branch name, or `-` for a commit carrying no trailer at all.
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
  git_repo_bare_head "$bare" main
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

# build_selected <name> <default> -- a remote at acme/<name> whose default
# branch is <default>: build_remote's `main`, plus a `trunk` branch beside it,
# HEAD on <default> (`main` or `trunk`).
build_selected() {
  local bare
  bare="$(build_remote "$1" - -)"
  git -C "$bare" branch trunk main
  git_repo_bare_head "$bare" "$2"
  printf '%s\n' "$bare"
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
# A remote carrying a `trunk` branch beside `main`: the selected-repo row
# below needs a default that exists on origin (the selection only names it;
# the fetch still reads it from origin) yet differs from every other row's
# `main` -- a same-named answer would pass even if the selection never
# reached the selected repository's HEAD.
REMOTE_TRUNK="$(build_selected trunkremote main)"

# ---- the default-branch ladder, with no trailer to find ------------------
#
# The symref names `feature`, a branch that exists on the remote and is the
# wrong answer, while the remote's HEAD names `main`. That pairing is the hazard the
# rung was removed for: a symref left over from before a rename keeps naming a
# branch that is still there, so it resolves and nothing reports the mistake. A
# symref pointed at an absent branch would fail loudly on the fetch instead, and
# would leave that case untested.

row_start
W="$(work_repo dflt-stale-symref "$REMOTE_PLAIN" feature)"
run_in "$W" feature
assert_row 'stale-symref-is-ignored' 0 'BASE main\n' 0

row_start
W="$(work_repo dflt-head "$REMOTE_PLAIN" -)"
run_in "$W" feature
assert_row 'no-trailer-uses-the-remote-head' 0 'BASE main\n' 0

row_start
W="$(work_repo selected-repo "$REMOTE_TRUNK" main)"
git_repo_remote "$W" upstream "$(build_selected selected trunk)"
run_in "$W" feature acme/selected
assert_row 'selected-repo-names-the-default' 0 'BASE trunk\n' 0

# No remote added: the selected repository is read at origin's sibling path.
row_start
build_selected selected trunk >/dev/null
W="$(work_repo selected-sibling "$REMOTE_TRUNK" main)"
run_in "$W" feature acme/selected
assert_row 'selected-repo-read-at-origins-sibling' 0 'BASE trunk\n' 0

row_start
W="$(work_repo selected-unreachable "$REMOTE_TRUNK" main)"
run_in "$W" feature acme/elsewhere
assert_row 'selected-repo-unreachable' 0 'STOP ask-default-branch\n' 0

row_start
W="$(work_repo dflt-unreachable "${HARNESS_TMP}/remotes/acme/nosuch.git" -)"
run_in "$W" feature
assert_row 'default-branch-lookup-fails' 0 'STOP ask-default-branch\n' 0

row_start
W="$(work_repo dflt-unborn "$(git_repo_bare acme unborn)" -)"
run_in "$W" feature
assert_row 'remote-head-unborn' 0 'STOP ask-default-branch\n' 0

# ---- the trailer the task branch only inherits ---------------------------
#
# `main`'s commit carries `Base-Branch: ancestor-base` and `feature` records
# nothing, so the answer is the default branch and nothing is asked for: a
# scan reaching the inherited trailer would answer NEED instead. The default
# branch is read from the remote's HEAD, no `gh` call.

row_start
W="$(work_repo ancestor "$REMOTE_ANCESTOR" main)"
run_in "$W" feature
assert_row 'ancestor-trailer-is-out-of-scope' 0 'BASE main\n' 0

# ---- a trailer the task branch recorded itself --------------------------
#
# Without facts the NEED names the newer branch, so a scan reading the stack
# oldest-first fails as `older-base` rather than as a missing stub; with the
# newer branch's facts the answer is its PR.

row_start
W="$(work_repo shadow "$REMOTE_SHADOW" main)"
run_in "$W" feature
assert_row 'newest-trailer-shadows-older' 0 'NEED repo=acme/shadow prereq.head=acme:newer-base prereq.head-pr\n' 0

row_start
W="$(work_repo shadow-facts "$REMOTE_SHADOW" main)"
run_in "$W" feature --facts "$(prereq_facts acme/shadow acme:newer-base 1 9 OPEN | facts_file)"
assert_row 'newest-trailer-wins-with-facts' 0 'BASE newer-base\n' 0

row_start
W="$(work_repo prereq-open "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep 1 9 OPEN | facts_file)"
assert_row 'prerequisite-open-keeps-its-branch' 0 'BASE dep\n' 0

row_start
W="$(work_repo prereq-merged "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep 1 9 MERGED | facts_file)"
assert_row 'prerequisite-merged-falls-back-to-default' 0 'BASE main\n' 0

row_start
W="$(work_repo prereq-closed "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep 1 9 CLOSED | facts_file)"
assert_row 'prerequisite-closed-stops' 0 'STOP abandoned-prerequisite\n' 0

row_start
W="$(work_repo prereq-none "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep 0 | facts_file)"
assert_row 'prerequisite-has-no-pr' 0 'STOP no-prereq-pr\n' 0

# Changed answer: was prereq-lookup-failed, when the `gh` call failed.
row_start
W="$(work_repo prereq-unreadable "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep '' | facts_file)"
assert_row 'prerequisite-lookup-unread' 0 'STOP fact-missing\n' 0

row_start
W="$(work_repo prereq-multiple "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$({ prereq_facts acme/dep acme:dep 2 9; printf 'prereq.head-pr=8\n'; } | facts_file)"
assert_row 'prerequisite-has-several-prs' 0 'STOP ask-multiple-prs\n' 0

# Changed answer: was exit 1 with an empty stdout.
row_start
W="$(work_repo prereq-unknown-state "$REMOTE_DEP" main)"
run_in "$W" feature --facts "$(prereq_facts acme/dep acme:dep 1 9 DRAFT | facts_file)"
assert_row 'prerequisite-state-unrecognised' 0 'STOP fact-enum\n' 0

# ---- fetches that fail --------------------------------------------------
#
# The two failures carry different slugs on purpose: a missing default branch
# and a missing task branch want different answers from the person the caller
# stops for.
#
# The first row's selected repository names a default (`trunk`) that origin
# does not have, so the default branch's own fetch is what fails. The second
# row's default is a real branch, so that fetch succeeds and it is the task
# branch's fetch that fails instead.

row_start
build_selected selabsent trunk >/dev/null
W="$(work_repo default-absent "$REMOTE_PLAIN" -)"
run_in "$W" feature acme/selabsent
assert_row 'default-branch-absent-on-remote' 0 'STOP default-fetch-failed\n' 0

row_start
W="$(work_repo branch-absent "$REMOTE_PLAIN" main)"
run_in "$W" nosuchbranch
assert_row 'task-branch-absent-on-remote' 0 'STOP fetch-failed\n' 0

# ---- argument validation ------------------------------------------------
#
# Both rows run from a work repository that could have answered, so a failure
# here is the guard's, not the fixture's.

row_start
W="$(work_repo args-none "$REMOTE_PLAIN" main)"
run_in "$W"
assert_row 'no-argument' 2 '' 0

row_start
W="$(work_repo args-two-valid "$REMOTE_PLAIN" -)"
git_repo_remote "$W" upstream "$(build_selected selected main)"
run_in "$W" feature acme/selected
assert_row 'two-arguments-names-the-repo' 0 'BASE main\n' 0

row_start
W="$(work_repo args-three "$REMOTE_PLAIN" main)"
run_in "$W" feature extra another
assert_row 'three-arguments' 2 '' 0

row_start
W="$(work_repo args-facts-bare "$REMOTE_PLAIN" main)"
run_in "$W" feature --facts
assert_row 'facts-flag-without-file' 2 '' 0

# ---- the reader's answers this caller cannot act on ----------------------
#
# The real reader prints NO-TRAILER, PREREQ with OPEN or MERGED, NEED or STOP,
# and a state outside OPEN/MERGED/CLOSED stops earlier as STOP fact-enum, while
# CLOSED stops as STOP abandoned-prerequisite. So these rows
# stub it: a copy of tools/ with this file's subject dropped in and
# read-base-trailer.sh replaced. What they pin is the boundary -- whatever the
# reader answers, this script prints one line and exits 0. Measured before the
# guard: a reader exiting 1 made this script exit 1 with empty stdout; an
# unknown KIND or STATE exited 0 with empty stdout.
#
# The default-branch lookup and the fetch keep their own rows above.
CONTRACT="${HARNESS_TMP}/tools-contract"
cp -R "${REPO_ROOT}/tools" "$CONTRACT"
cp "$SUT" "${CONTRACT}/resolve-pr-base.sh"
printf '#!/usr/bin/env bash\necho main\n' >"${CONTRACT}/resolve-default-branch.sh"
printf '#!/usr/bin/env bash\necho 1111111111111111111111111111111111111111\n' >"${CONTRACT}/fetch-to-sha.sh"

# reader <body> -- the copy's read-base-trailer.sh becomes a script of <body>.
reader() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/read-base-trailer.sh"; }

row_start
reader 'exit 1'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-abort-is-reported' 0 'STOP trailer-read-failed\n' 0

row_start
reader 'echo WHAT'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-unknown-kind-is-reported' 0 'STOP trailer-answer-malformed\n' 0

row_start
reader 'echo "PREREQ feature 9 DRAFT"'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-unknown-state-is-reported' 0 'STOP trailer-answer-malformed\n' 0

harness_exit "$failed" "$total"
