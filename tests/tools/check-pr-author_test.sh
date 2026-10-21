#!/usr/bin/env bash
# Table test for tools/check-pr-author.sh: whether the PR's author is the user
# the agent's GitHub means acts as. review-code stops on OTHER, so both
# answers, the NEED that asks for the facts, and each way a read can be wrong
# get a row. The script reads facts and origin only:
# every row asserts 0 gh calls, and only the three facts-capture rows at the
# end stub a sibling (facts.sh).
#
# RED verification (see tests/README.md): against the pre-port script
# (`git show master:tools/check-pr-author.sh`) the no-facts row fails on an
# unstubbed `gh api user` call, and every `--facts` row fails on the old
# script's exit-2 usage error; the four usage rows pass (not ok 9/13).
# Mutants measured in a copy under `mktemp -d` (siblings beside it): inverting the comparison fails 'own pr' and "someone else's
# pr"; dropping `pr.number=` from the check fails 'pr number mismatch' and
# 'no facts: NEED pins repo and pr'.
#
# The three facts-capture rows at the end are RED against `master`'s script in
# a full tools/ tree: `not ok 3/16`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/check-pr-author.sh}"

failed=0
total=0

WORK="$(git_repo_scratch work)"
git_repo_init "$WORK" main
git_repo_remote "$WORK" origin 'https://github.com/Acme/Widgets.git'

# facts <author> <viewer> [<pr-number> [<repo>]]  prints a fixture's path
facts() {
  facts_file <<EOF
repo=${4:-acme/widgets}
pr.number=${3:-12}
pr.author.login=$1
viewer.login=$2
EOF
}

row_start
run_in "$WORK" 12
assert_row 'no facts: NEED pins repo and pr' 0 'NEED repo=acme/widgets pr.number=12 pr.author.login viewer.login\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts me me)"
assert_row 'own pr' 0 'SELF\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts alice me)"
assert_row "someone else's pr" 0 'OTHER\n' 0

row_start
F="$(facts_file <<'EOF'
repo=acme/widgets
pr.number=12
viewer.login=me
EOF
)"
run_in "$WORK" 12 --facts "$F"
assert_row 'author not yet read' 0 'NEED pr.author.login\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts alice '')"
assert_row 'viewer login unreadable' 0 'STOP fact-missing\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts null me)"
assert_row 'author login written as null' 0 'STOP fact-missing\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts alice me 13)"
assert_row 'pr number mismatch' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$WORK" 12 --facts "$(facts alice me 12 upstream/widgets)"
assert_row 'pr read in another repo' 0 'STOP fact-mismatch\n' 0

NOORIGIN="$(git_repo_scratch noorigin)"
git_repo_init "$NOORIGIN" main
row_start
run_in "$NOORIGIN" 12 --facts "$(facts me me)"
assert_row 'no origin' 0 'STOP repo-lookup-failed\n' 0

row_start
run_in "$WORK" abc
assert_row 'non-numeric pr' 2 '' 0

row_start
run_in "$WORK"
assert_row 'no argument' 2 '' 0

row_start
run_in "$WORK" 12 --facts
assert_row '--facts without a file' 2 '' 0

row_start
run_in "$WORK" 12 --state x
assert_row 'unknown option' 2 '' 0

# ---- facts.sh that stops instead of answering ---------------------------
#
# The self-check and both reads are captured, so an exit that is not relayed
# becomes empty stdout and a non-zero status. The copy's facts.sh is replaced
# for these three rows only.
CONTRACT="${HARNESS_TMP}/tools-contract"
cp -R "${REPO_ROOT}/tools" "$CONTRACT"
cp "$SUT" "${CONTRACT}/check-pr-author.sh"
facts_stub() { printf '#!/usr/bin/env bash\n%s\n' "$1" >"${CONTRACT}/facts.sh"; }

# run_contract <work-dir> <argv...> -- run_in, for the copy's script.
run_contract() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "${CONTRACT}/check-pr-author.sh" "$@"
  cd "$REPO_ROOT" || exit 1
}

row_start
facts_stub 'exit 1'
run_contract "$WORK" 12 --facts "$(facts_file </dev/null)"
assert_row 'facts-check-abort-is-reported' 0 'STOP facts-read-failed\n' 0

row_start
facts_stub 'echo WHAT'
run_contract "$WORK" 12 --facts "$(facts_file </dev/null)"
assert_row 'facts-check-answer-malformed-is-reported' 0 'STOP facts-answer-malformed\n' 0

row_start
facts_stub 'case "$1" in check) echo OK ;; *) exit 1 ;; esac'
run_contract "$WORK" 12 --facts "$(facts_file </dev/null)"
assert_row 'facts-get-abort-is-reported' 0 'STOP facts-read-failed\n' 0

harness_exit "$failed" "$total"
