#!/usr/bin/env bash
# Table test for skills/review-code/scripts/check-pr-author.sh: whether the PR's
# author is the user gh is logged in as. review-pr stops on SELF and
# review-code stops on OTHER, so the two answers and the failed lookup each get
# a row. The SUT reads no git state, so rows run with run_sut from anywhere.
#
# RED verification (see tests/README.md): inverting the comparison fails both
# 'own pr' and 'someone else's pr'; reading a failed author lookup as an empty
# author (`|| true`) makes 'author lookup fails' answer OTHER instead of STOP.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-code/scripts/check-pr-author.sh}"

failed=0
total=0

# stub_viewer <exit-status>          body on stdin
stub_viewer() {
  gh_stub_response '*' "$1" api user --jq .login
}

# stub_author <pr> <exit-status>     body on stdin
stub_author() {
  gh_stub_response '*' "$2" pr view --json author --jq .author.login -- "$1"
}

row_start
printf 'me\n' | stub_viewer 0
printf 'me\n' | stub_author 12 0
run_sut bash "$SUT" 12
assert_row 'own pr' 0 'SELF\n' 2

row_start
printf 'me\n' | stub_viewer 0
printf 'alice\n' | stub_author 12 0
run_sut bash "$SUT" 12
assert_row "someone else's pr" 0 'OTHER\n' 2

row_start
: | stub_viewer 1
printf 'alice\n' | stub_author 12 0
run_sut bash "$SUT" 12
assert_row 'viewer lookup fails' 0 'STOP pr-lookup-failed\n' 1

row_start
printf 'me\n' | stub_viewer 0
: | stub_author 12 1
run_sut bash "$SUT" 12
assert_row 'author lookup fails' 0 'STOP pr-lookup-failed\n' 2

row_start
run_sut bash "$SUT" abc
assert_row 'non-numeric pr' 2 '' 0

row_start
run_sut bash "$SUT"
assert_row 'no argument' 2 '' 0

harness_exit "$failed" "$total"
