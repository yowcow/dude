#!/usr/bin/env bash
# Table test for tools/resolve-pr-base.sh: the base read from the issue's
# `Blocked-By: #N` line (via tools/read-prereq-pr.sh), and the one line it
# prints for each answer.
#
# git is not stubbed. Each row that drives the real reader builds a real bare
# repository to play the remote and a real work repository whose `origin`
# points at it, both under $HARNESS_TMP and both offline. Those work
# repositories hold no commits at all: the SUT only fetches the task branch
# and never checks anything out. The rows at the end of this file stub the
# reader, the default-branch lookup and the fetch instead, and build no
# repository.
#
# The task branch's commits never decide the base: the regression rows pin
# that a commit with no readable Base-Branch trailer (none at all, or one in
# a paragraph git does not read as a trailer, the #845 shape) still gets the
# issue's prerequisite, and a readable trailer is ignored.
#
# `STOP prereq-read-failed` has a row: the stubbed-reader rows at the end of
# this file, which also pin the answers outside the reader's contract. The
# reader's own tests are tests/tools/read-prereq-pr_test.sh.
#
# The issue and the prerequisite's PR come as facts (issue_facts below) and,
# in every row but the four stubbed ones at the end, the default branch from
# the remote's own HEAD (resolve-default-branch.sh); every row asserts 0 gh
# calls.
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
#   there and the failures say nothing about the mutation. The four stubbed
#   rows at the end are the exception -- they copy the SUT into a tools/ tree
#   that already holds every sibling, so a lone copy is enough for those. The
#   bb8d8b8^ version above predates the extractions and needs no sibling.
#
#   RED for the move from the trailer to the issue (#847), both against the
#   script as of origin/master, placed in a copy of tools/ (`cp -R tools
#   "$tmp/tools"`, then `git show origin/master:tools/resolve-pr-base.sh
#   >"$tmp/tools/old.sh"`):
#   - `SUT="$tmp/tools/old.sh"`: the old script does not know `--issue`, so it
#     is a usage error on every row that passes it: `not ok 15/33`.
#   - `SUT="$tmp/tools/wrap.sh"`, a wrapper that drops `--issue <n>` and calls
#     old.sh, so the rows fail for the behaviour and not the usage error: the
#     regression rows answer `BASE main` (the old script reads no trailer
#     there and falls back to the default) instead of `BASE dep`, and
#     `readable-trailer-is-ignored` answers `NEED prereq.head=acme:stale-base
#     prereq.head-pr` instead of `BASE main`: `not ok 16/33` (the four stubbed reader rows and
#     their two tallies fail too, as the wrapper is not copied beside old.sh).
#
#   The reader-boundary rows at the end of this file are RED the ordinary way:
#   point SUT= at the pre-fix script
#   (`git show 8410c39^:tools/resolve-pr-base.sh`) dropped into a copy of
#   tools/ that holds every sibling, and only those four rows and their two
#   stderr tallies fail: `not ok 6/29`.
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

# body <text> -- prints the path of an issue-body file holding <text> (printf '%b')
body() {
  local f
  f="$(mktemp "${HARNESS_TMP}/body.XXXXXX")"
  printf '%b' "$1" >"$f"
  printf '%s\n' "$f"
}

LINE='Blocked-By: #77\n'

# issue_facts <repo> <body-text> -- the issue's facts, on stdout
issue_facts() {
  printf 'repo=%s\nissue.number=203\nissue.body-file=%s\n' "$1" "$(body "$2")"
}

# prereq_facts <repo> <total> [<pr> [<state> [<head>]]] -- the facts of an
# issue carrying LINE and its prerequisite #77's closing PRs, on stdout
# (pipe into facts_file).
prereq_facts() {
  issue_facts "$1" "$LINE"
  printf 'prereq.number=77\nprereq.closing-pr.total=%s\n' "$2"
  if [ "$#" -ge 3 ]; then
    printf 'prereq.closing-pr=%s\n' "$3"
  fi
  if [ "$#" -ge 4 ]; then
    printf 'pr.number=%s\npr.state=%s\npr.head.ref=%s\n' "$3" "$4" "${5-dep}"
  fi
}

# build_msg_remote <name> <message> -- a remote like build_remote's, whose one
# feature commit carries <message> verbatim.
build_msg_remote() {
  local name="$1" bare seed
  bare="$(git_repo_bare acme "$name")"
  seed="$(git_repo_scratch "seed-${name}")"
  git_repo_init "$seed" main
  git_repo_commit "$seed" README.md 'base\n' 'base commit'
  git_repo_checkout "$seed" feature main
  git_repo_commit "$seed" F1.md 'feature 1\n' "$2"
  git_repo_push "$seed" "$bare" main feature
  git_repo_bare_head "$bare" main
  printf '%s\n' "$bare"
}

# `feature` records nothing; `main` records nothing either.
REMOTE_PLAIN="$(build_remote plain - -)"
# `feature`'s commit has `Base-Branch:` in a paragraph of its own followed by
# `Co-Authored-By:` (the #845 shape), which git does not read as a trailer.
REMOTE_SEPARATE="$(build_msg_remote separate "$(printf 'subject\n\nBase-Branch: dep\n\nCo-Authored-By: A <a@example.invalid>\n')")"
# `feature` carries a readable trailer naming a branch the issue does not.
REMOTE_STALE="$(build_remote stale - stale-base)"
# A remote carrying a `trunk` branch beside `main`: the selected-repo row
# below needs a default that exists on origin (the selection only names it;
# the fetch still reads it from origin) yet differs from every other row's
# `main` -- a same-named answer would pass even if the selection never
# reached the selected repository's HEAD.
REMOTE_TRUNK="$(build_selected trunkremote main)"

# ---- the default-branch ladder, with no issue to read -------------------
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
assert_row 'no-issue-uses-the-remote-head' 0 'BASE main\n' 0

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

# ---- no prerequisite to read ---------------------------------------------
#
# Without --issue the reader is not asked for the issue's facts at all, so
# nothing NEEDs and no gh runs.

row_start
W="$(work_repo no-issue "$REMOTE_PLAIN" main)"
run_in "$W" feature
assert_row 'no-issue-is-default' 0 'BASE main\n' 0

row_start
W="$(work_repo no-prereq-line "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$(issue_facts acme/plain 'nothing blocking\n' | facts_file)"
assert_row 'no-prereq-line-is-default' 0 'BASE main\n' 0

row_start
W="$(work_repo issue-no-facts "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203
assert_row 'issue-without-facts-asks' 0 'NEED repo=acme/plain issue.number=203 issue.body-file\n' 0

# ---- the base comes from the issue, never the commits --------------------
#
# Both commit shapes leave no Base-Branch trailer git can read; the answer is
# the issue's prerequisite head either way.

row_start
W="$(work_repo regress-plain "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$(prereq_facts acme/plain 1 55 OPEN | facts_file)"
assert_row 'regression-open-prereq-no-trailer' 0 'BASE dep\n' 0

row_start
W="$(work_repo regress-separate "$REMOTE_SEPARATE" main)"
tally check_eq 'regression-separate-paragraph: git reads no trailer' '' \
  "$(git -C "$REMOTE_SEPARATE" log -1 --format='%(trailers:key=Base-Branch)' feature)"
run_in "$W" feature --issue 203 --facts "$(prereq_facts acme/separate 1 55 OPEN | facts_file)"
assert_row 'regression-open-prereq-trailer-in-separate-paragraph' 0 'BASE dep\n' 0

row_start
W="$(work_repo stale-trailer "$REMOTE_STALE" main)"
run_in "$W" feature --issue 203 --facts "$(issue_facts acme/stale 'nothing blocking\n' | facts_file)"
assert_row 'readable-trailer-is-ignored' 0 'BASE main\n' 0

row_start
W="$(work_repo prereq-merged "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$(prereq_facts acme/plain 1 55 MERGED | facts_file)"
assert_row 'merged-prereq-answers-default' 0 'BASE main\n' 0

row_start
W="$(work_repo prereq-closed "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$(prereq_facts acme/plain 1 55 CLOSED | facts_file)"
assert_row 'closed-stops' 0 'STOP abandoned-prerequisite\n' 0

row_start
W="$(work_repo prereq-none "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$(prereq_facts acme/plain 0 | facts_file)"
assert_row 'no-closing-pr' 0 'STOP not-implemented\n' 0

row_start
W="$(work_repo prereq-multiple "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 203 --facts "$({ prereq_facts acme/plain 2 55; printf 'prereq.closing-pr=56\n'; } | facts_file)"
assert_row 'several-closing-prs' 0 'STOP ask-multiple-prs\n' 0

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

row_start
W="$(work_repo args-issue-bare "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue
assert_row 'issue-flag-without-value' 2 '' 0

row_start
W="$(work_repo args-issue-text "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue abc
assert_row 'issue-non-numeric' 2 '' 0

row_start
W="$(work_repo args-issue-zero "$REMOTE_PLAIN" main)"
run_in "$W" feature --issue 0
assert_row 'issue-zero' 2 '' 0

# ---- the reader's answers this caller cannot act on ----------------------
#
# The real reader prints NO-PREREQ, PREREQ with OPEN or MERGED, NEED or STOP,
# and a state outside OPEN/MERGED/CLOSED stops earlier as STOP fact-enum, while
# CLOSED stops as STOP abandoned-prerequisite. So these rows
# stub it: a copy of tools/ with this file's subject dropped in and
# read-prereq-pr.sh replaced. What they pin is the boundary -- whatever the
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

# reader <body> -- the copy's read-prereq-pr.sh becomes a script of <body>.
reader() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/read-prereq-pr.sh"; }

row_start
reader 'exit 1'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-abort-is-reported' 0 'STOP prereq-read-failed\n' 0

row_start
reader 'echo WHAT'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-unknown-kind-is-reported' 0 'STOP prereq-answer-malformed\n' 0
tally check_eq 'reader-unknown-kind: stderr' \
  'unrecognised answer from read-prereq-pr.sh: WHAT' "$(cat "$SUT_STDERR")"

row_start
reader 'echo "PREREQ feature 9 DRAFT"'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-unknown-state-is-reported' 0 'STOP prereq-answer-malformed\n' 0
tally check_eq 'reader-unknown-state: stderr' \
  'unrecognised prerequisite state: DRAFT' "$(cat "$SUT_STDERR")"

row_start
reader 'true'
run_sut bash "${CONTRACT}/resolve-pr-base.sh" feature
assert_row 'reader-empty-answer-is-reported' 0 'STOP prereq-answer-malformed\n' 0

harness_exit "$failed" "$total"
