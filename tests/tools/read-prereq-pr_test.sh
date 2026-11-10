#!/usr/bin/env bash
# Table test for tools/read-prereq-pr.sh: the one line it prints for each shape
# of an issue's prerequisite line (`Blocked-By: #N`) and of the facts about the
# PR that closes that prerequisite. It reads facts only: every row asserts 0 gh
# calls, and only the three facts-capture rows at the end stub a sibling
# (facts.sh). git is not stubbed; the repository only pins facts to origin.
#
# RED verification (see tests/README.md): before the script exists every row
# fails, the script being absent.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/read-prereq-pr.sh}"

failed=0
total=0

# body <text> -- prints the path of an issue-body file holding <text> (printf '%b')
body() {
  local f
  f="$(mktemp "${HARNESS_TMP}/body.XXXXXX")"
  printf '%b' "$1" >"$f"
  printf '%s\n' "$f"
}

W="$(git_repo_scratch work)"
git_repo_init "$W" main
git_repo_remote "$W" origin 'https://github.com/Acme/Widgets.git'

REPO=acme/widgets
LINE='Blocked-By: #77\n'

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

# round3 <state> [<head> [<pr> [<owner>]]] -- one closing PR, 55, and its record
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
pr.head.owner=${4:-acme}
EOF
}

# ---- arguments ----------------------------------------------------------

row_start
run_in "$W"
assert_row 'no-issue-is-no-prereq' 0 'NO-PREREQ\n' 0

row_start
run_in "$W" abc
assert_row 'non-numeric-issue' 2 '' 0

row_start
run_in "$W" 0
assert_row 'zero-issue' 2 '' 0

row_start
run_in "$W" --facts
assert_row 'facts-flag-without-file' 2 '' 0

row_start
run_in "$W" 203 204
assert_row 'two-issues' 2 '' 0

# ---- round 1: the issue's body -------------------------------------------

row_start
run_in "$W" 203
assert_row 'issue-without-facts-asks' 0 \
  'NEED repo=acme/widgets issue.number=203 issue.body-file\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body 'purpose\n\nno prerequisite\n')")" 203
assert_row 'no-prereq-line-is-no-prereq' 0 'NO-PREREQ\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body "$LINE")")" 203
assert_row 'one-line-asks-for-closing-prs' 0 \
  'NEED prereq.number=77 prereq.closing-pr\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body 'Blocked-By: #77\nBlocked-By: #78\n')")" 203
assert_row 'two-lines-stop' 0 'STOP ask-multiple-prereqs\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body 'Blocked-by #77\n')")" 203
assert_row 'malformed-line-stops' 0 'STOP prereq-line-malformed\n' 0

row_start
run_in "$W" --facts "$(round1 "${HARNESS_TMP}/nosuch")" 203
assert_row 'body-unreadable' 0 'STOP body-unreadable\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body "$LINE")" 204)" 203
assert_row 'another-issue-read' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$W" --facts "$(round1 "$(body "$LINE")" 203 upstream/widgets)" 203
assert_row 'issue-read-in-another-repo' 0 'STOP fact-mismatch\n' 0

row_start
NOORIGIN="$(git_repo_scratch noorigin)"
git_repo_init "$NOORIGIN" main
run_in "$NOORIGIN" --facts "$(round1 "$(body "$LINE")")" 203
assert_row 'no-origin' 0 'STOP repo-lookup-failed\n' 0

# ---- round 2: the prerequisite's closing PRs -----------------------------

row_start
run_in "$W" --facts "$(round2 77 0)" 203
assert_row 'no-closing-pr' 0 'STOP not-implemented\n' 0

row_start
run_in "$W" --facts "$(round2 77 2 55 66)" 203
assert_row 'two-closing-prs' 0 'STOP ask-multiple-prs\n' 0

row_start
run_in "$W" --facts "$(round2 77 2 55)" 203
assert_row 'closing-prs-cut-short' 0 'STOP fact-count\n' 0

row_start
run_in "$W" --facts "$(round2 78 1 55)" 203
assert_row 'prereq-read-as-another-issue' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$W" --facts "$(round2 77 1 55)" 203
assert_row 'one-closing-pr-asks-for-its-record' 0 \
  'NEED pr.number=55 pr.state pr.head.ref pr.head.owner=acme\n' 0

# ---- round 3: the PR's state -----------------------------------------------

row_start
run_in "$W" --facts "$(round3 OPEN)" 203
assert_row 'prereq-open' 0 'PREREQ feature 55 OPEN\n' 0

row_start
run_in "$W" --facts "$(round3 MERGED)" 203
assert_row 'prereq-merged' 0 'PREREQ feature 55 MERGED\n' 0

row_start
run_in "$W" --facts "$(round3 CLOSED)" 203
assert_row 'prereq-closed' 0 'STOP abandoned-prerequisite\n' 0

row_start
run_in "$W" --facts "$(round3 closed)" 203
assert_row 'state-unrecognised' 0 'STOP fact-enum\n' 0

row_start
run_in "$W" --facts "$(round3 OPEN feature 56)" 203
assert_row 'pr-read-as-another-pr' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$W" --facts "$(round3 OPEN feature 55 other-fork)" 203
assert_row 'head-owned-by-another-repo' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$W" --facts "$(round3 OPEN '')" 203
assert_row 'head-unreadable' 0 'STOP fact-missing\n' 0

# ---- facts.sh that stops instead of answering ---------------------------
#
# The self-check and every read are captured, so an exit that is not relayed
# becomes empty stdout and a non-zero status. The copy's facts.sh is replaced
# for these three rows only.
CONTRACT="${HARNESS_TMP}/facts-contract"
mkdir -p "$CONTRACT"
cp -R "${REPO_ROOT}/tools" "${CONTRACT}/tools"
cp "$SUT" "${CONTRACT}/tools/read-prereq-pr.sh"
facts_stub() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/tools/facts.sh"; }

# run_contract <work-dir> <argv...> -- run_in, for the copy's script.
run_contract() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "${CONTRACT}/tools/read-prereq-pr.sh" "$@"
  cd "$REPO_ROOT" || exit 1
}

row_start
facts_stub 'exit 1'
run_contract "$W" --facts "$(facts_file </dev/null)" 203
assert_row 'facts-check-abort-is-reported' 0 'STOP facts-read-failed\n' 0

row_start
facts_stub 'echo WHAT'
run_contract "$W" --facts "$(facts_file </dev/null)" 203
assert_row 'facts-check-answer-malformed-is-reported' 0 'STOP facts-answer-malformed\n' 0

row_start
facts_stub 'case "$1" in check) echo OK ;; *) exit 1 ;; esac'
run_contract "$W" --facts "$(facts_file </dev/null)" 203
assert_row 'facts-get-abort-is-reported' 0 'STOP facts-read-failed\n' 0

harness_exit "$failed" "$total"
