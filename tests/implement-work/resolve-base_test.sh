#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/resolve-base.sh: which base it
# names for each shape of the issue's prerequisite line (`Blocked-By: #N`) and
# of the facts about the PR that closes that prerequisite, and -- for every
# answer that names one -- that the branch was really fetched.
#
# The script reads no issue or PR itself: issue-backed rows hand it a fact
# fixture (facts_file). The shared tools/resolve-default-branch.sh reads the
# remote's HEAD, so the file stubs nothing; every row asserts 0 gh calls.
#
# There is no row for a default branch absent on the remote: a HEAD naming an
# absent branch is unborn and prints nothing, so ls-remote answers no default
# rather than a branch the fetch then fails on. The fetch-failure exit is still
# covered by `open head absent on remote`, which goes through the same `base`
# function.
#
# git is not stubbed. Which ref a fetch updates is git's own behaviour, so a
# git stub would encode the test author's belief about that rather than git's
# behaviour. The `BASE X` line is printed whether or not the fetch happened,
# so the check_tracking assertions carry the fetch.
#
# The remote every row shares holds three branches: `main` and `feature` with
# two commits each, and `decoy` with one. `decoy` is what the work repository
# checks out, and each row plants both tracking refs one commit behind. A row
# that expects a fetch asserts the ref MOVED to the tip, and a row that
# expects none asserts it stayed behind.
#
# RED verification (see tests/README.md): against the pre-port script
# (`git show f10c2ec:skills/implement-work/scripts/resolve-base.sh`) the
# no-facts row fails on an unstubbed `gh issue view`, and every `--facts` row
# fails on the old script's exit-2 usage error. Mutants, laid out as
# skills/implement-work/scripts/resolve-base.sh beside a copy of tools/ under
# a temp root (the script reaches tools/ through SCRIPT_DIR, so a lone copy
# fails every row for that reason instead): testing the closing PRs for
# emptiness instead of counting them fails 'prerequisite has two prs';
# dropping the `prereq.number=` pin fails 'prerequisite read as another issue'.
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

failed=0
total=0

# build_remote <name> -- prints the path of a bare repo holding `main` and
# `feature` with two commits each and `decoy` with one.
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
  git_repo_bare_head "$bare" main
  printf '%s\n' "$bare"
}

# work_repo <name> <bare> [<origin-head>] -- a clone of <bare> on `decoy`,
# origin/main and origin/feature planted one commit behind.
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

# stale_ref <work> <bare> <branch> -- refs/remotes/origin/<branch> at <branch>~1
stale_ref() {
  local sha
  sha="$(git -C "$2" rev-parse "refs/heads/$3~1")"
  git -C "$1" update-ref "refs/remotes/origin/$3" "$sha"
}

# check_tracking <label> <work> <bare> <branch> <tip|stale|absent>
# shellcheck disable=SC2317 # invoked indirectly, as `tally check_tracking ...`
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

# body <text> -- prints the path of an issue-body file holding <text> (printf '%b')
body() {
  local f
  f="$(mktemp "${HARNESS_TMP}/body.XXXXXX")"
  printf '%b' "$1" >"$f"
  printf '%s\n' "$f"
}

REMOTE="$(build_remote base)"
REPO=acme/base
LINE='Blocked-By: #77\n'
CHILD_BODY='- **前提：** #77（item 1）に stack する。\n\n親の設計：https://example.invalid/1\n\nBlocked-By: #77\n'

# round1 <body-path> [<issue> [<repo>]] -- the issue's facts
round1() {
  facts_file <<EOF
repo=${3:-$REPO}
issue.number=${2:-203}
issue.body-file=$1
EOF
}

# round2 <prereq> <total> [<pr>...] -- round 1 for a one-line body, plus the
# prerequisite's closing PRs. The loop is guarded on $# because an empty "$@"
# is an unbound-variable error under set -u before bash 4.4.
round2() {
  local p="$1" t="$2" n
  shift 2
  {
    printf 'repo=%s\nissue.number=203\nissue.body-file=%s\nprereq.number=%s\n' \
      "$REPO" "$(body "$LINE")" "$p"
    if [ "$#" -gt 0 ]; then
      for n in "$@"; do printf 'prereq.closing-pr=%s\n' "$n"; done
    fi
    printf 'prereq.closing-pr.total=%s\n' "$t"
  } | facts_file
}

# round3 <state> [<head> [<pr>]] -- one closing PR, 55, and its record
round3() {
  facts_file <<EOF
repo=${REPO}
issue.number=203
issue.body-file=$(body "$LINE")
prereq.number=77
prereq.closing-pr=55
prereq.closing-pr.total=1
pr.number=${3:-55}
pr.state=$1
pr.head.ref=${2-feature}
EOF
}

# ---- arguments ----------------------------------------------------------

W="$(work_repo args "$REMOTE" main)"

row_start
run_in "$W" 203 extra
assert_row 'two arguments' 2 '' 0
total=$((total + 1))
if ! grep -q 'Usage:' "$SUT_STDERR"; then
  printf 'FAIL two arguments: stderr carries no usage line\n'
  failed=$((failed + 1))
fi

row_start
run_in "$W" 203 --facts
assert_row '--facts without a file' 2 '' 0

row_start
run_in "$W" 203 --state x
assert_row 'unknown option' 2 '' 0

row_start
run_in "$W" abc
assert_row 'non-numeric issue' 2 '' 0
tally check_tracking 'arguments: origin/main untouched' "$W" "$REMOTE" main stale

# ---- no issue: the default branch, no facts asked for -------------------

row_start
W="$(work_repo no-arg "$REMOTE" main)"
run_in "$W"
assert_row 'no argument uses the default branch' 0 'BASE main\n' 0
tally check_tracking 'no argument: origin/main fetched' "$W" "$REMOTE" main tip
tally check_tracking 'no argument: origin/feature untouched' "$W" "$REMOTE" feature stale

# ---- round 1: the issue's body -------------------------------------------

row_start
W="$(work_repo no-facts "$REMOTE" main)"
run_in "$W" 203
assert_row 'issue without facts: NEED pins repo and issue' 0 \
  'NEED repo=acme/base issue.number=203 issue.body-file\n' 0
tally check_tracking 'no facts: no fetch' "$W" "$REMOTE" main stale

row_start
W="$(work_repo line-none "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body 'purpose\n\nno prerequisite\n')")"
assert_row 'no prerequisite line uses the default branch' 0 'BASE main\n' 0
tally check_tracking 'no line: origin/main fetched' "$W" "$REMOTE" main tip

row_start
W="$(work_repo line-one "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body "$CHILD_BODY")")"
assert_row 'one prerequisite line asks for its closing prs' 0 \
  'NEED prereq.number=77 prereq.closing-pr\n' 0
tally check_tracking 'one line: no fetch yet' "$W" "$REMOTE" main stale

row_start
W="$(work_repo line-two "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body 'Blocked-By: #77\nBlocked-By: #78\n')")"
assert_row 'two prerequisite lines stop' 0 'STOP ask-multiple-prereqs\n' 0
tally check_tracking 'two lines: no fetch' "$W" "$REMOTE" main stale

row_start
W="$(work_repo line-bad "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body 'Blocked-by #77\n')")"
assert_row 'malformed prerequisite line stops' 0 'STOP prereq-line-malformed\n' 0
tally check_tracking 'malformed: no fetch' "$W" "$REMOTE" main stale

row_start
W="$(work_repo body-gone "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "${HARNESS_TMP}/nosuch")"
assert_row 'body file unreadable' 0 'STOP body-unreadable\n' 0

row_start
W="$(work_repo wrong-issue "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body "$LINE")" 204)"
assert_row 'another issue read' 0 'STOP fact-mismatch\n' 0

row_start
W="$(work_repo wrong-repo "$REMOTE" main)"
run_in "$W" 203 --facts "$(round1 "$(body "$LINE")" 203 upstream/base)"
assert_row 'issue read in another repo' 0 'STOP fact-mismatch\n' 0

row_start
W="$(round1 "$(body "$LINE")")"
NOORIGIN="$(git_repo_scratch noorigin)"
git_repo_init "$NOORIGIN" main
run_in "$NOORIGIN" 203 --facts "$W"
assert_row 'no origin' 0 'STOP repo-lookup-failed\n' 0

# ---- round 2: the prerequisite's closing PRs -----------------------------

row_start
W="$(work_repo prs-none "$REMOTE" main)"
run_in "$W" 203 --facts "$(round2 77 0)"
assert_row 'prerequisite has no pr' 0 'STOP not-implemented\n' 0

row_start
W="$(work_repo prs-two "$REMOTE" main)"
run_in "$W" 203 --facts "$(round2 77 2 55 66)"
assert_row 'prerequisite has two prs' 0 'STOP ask-multiple-prs\n' 0
tally check_tracking 'two prs: no fetch' "$W" "$REMOTE" main stale

row_start
W="$(work_repo prs-short "$REMOTE" main)"
run_in "$W" 203 --facts "$(round2 77 2 55)"
assert_row 'closing prs cut short' 0 'STOP fact-count\n' 0

row_start
W="$(work_repo prs-other "$REMOTE" main)"
run_in "$W" 203 --facts "$(round2 78 1 55)"
assert_row 'prerequisite read as another issue' 0 'STOP fact-mismatch\n' 0

row_start
W="$(work_repo prs-one "$REMOTE" main)"
run_in "$W" 203 --facts "$(round2 77 1 55)"
assert_row 'one closing pr asks for its record' 0 'NEED pr.number=55 pr.state pr.head.ref\n' 0

# ---- round 3: the PR's state -----------------------------------------------

row_start
W="$(work_repo state-open "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 OPEN)"
assert_row 'prerequisite open uses its head' 0 'BASE feature\n' 0
tally check_tracking 'open: origin/feature fetched' "$W" "$REMOTE" feature tip
tally check_tracking 'open: origin/main untouched' "$W" "$REMOTE" main stale

row_start
W="$(work_repo state-merged "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 MERGED)"
assert_row 'prerequisite merged uses the default branch' 0 'BASE main\n' 0
tally check_tracking 'merged: origin/main fetched' "$W" "$REMOTE" main tip
tally check_tracking 'merged: origin/feature untouched' "$W" "$REMOTE" feature stale

row_start
W="$(work_repo state-closed "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 CLOSED)"
assert_row 'prerequisite closed stops' 0 'STOP abandoned-prerequisite\n' 0
tally check_tracking 'closed: no fetch' "$W" "$REMOTE" main stale

# A record that reports `closed` plus a merged flag, written as read: the
# enum stops it rather than letting it fall to either branch.
row_start
W="$(work_repo state-lower "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 closed)"
assert_row 'state written lower-case' 0 'STOP fact-enum\n' 0
tally check_tracking 'lower-case state: no fetch' "$W" "$REMOTE" main stale

row_start
W="$(work_repo pr-other "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 OPEN feature 56)"
assert_row 'pr read as another pr' 0 'STOP fact-mismatch\n' 0

row_start
W="$(work_repo head-empty "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 OPEN '')"
assert_row 'head unreadable' 0 'STOP fact-missing\n' 0

# The remote's HEAD names a branch it lacks, which ls-remote reports as no
# default at all. Not origin re-pointed: the issue path pins `repo=` to
# origin-repo.sh's answer before round 3, so a URL ending acme/nosuch.git stops
# with `fact-mismatch` against round3's `repo=acme/base`.
row_start
git_repo_bare_head "$REMOTE" nosuch
W="$(work_repo merged-no-default "$REMOTE")"
run_in "$W" 203 --facts "$(round3 MERGED)"
assert_row 'merged with no resolvable default' 0 'STOP ask-default-branch\n' 0
tally check_tracking 'merged, no default: no fetch' "$W" "$REMOTE" main stale
git_repo_bare_head "$REMOTE" main

# ---- the default branch (shared tool, reached with no issue) --------------

row_start
git_repo_bare_head "$REMOTE" feature
W="$(work_repo ladder-stale-symref "$REMOTE" main)"
run_in "$W"
assert_row 'stale symref is ignored' 0 'BASE feature\n' 0
tally check_tracking 'stale symref: origin/feature fetched' "$W" "$REMOTE" feature tip
git_repo_bare_head "$REMOTE" main

row_start
git_repo_bare_head "$REMOTE" nosuch
W="$(work_repo ladder-unborn "$REMOTE")"
run_in "$W"
assert_row 'remote head unborn' 0 'STOP ask-default-branch\n' 0
git_repo_bare_head "$REMOTE" main

row_start
W="$(work_repo ladder-unreachable "$REMOTE")"
git -C "$W" remote set-url origin "${HARNESS_TMP}/remotes/acme/nosuch.git"
run_in "$W"
assert_row 'default branch lookup fails' 0 'STOP ask-default-branch\n' 0

# ---- fetches that fail ----------------------------------------------------

row_start
W="$(work_repo head-absent "$REMOTE" main)"
run_in "$W" 203 --facts "$(round3 OPEN nosuch)"
assert_row 'open head absent on remote' 1 '' 0
tally check_tracking 'open head absent: origin/main untouched' "$W" "$REMOTE" main stale

harness_exit "$failed" "$total"
