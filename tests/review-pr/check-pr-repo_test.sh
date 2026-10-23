#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/check-pr-repo.sh: the repository a
# PR reference names has to be this checkout's origin, or the run stops before
# any range is resolved. A checkout that pushes to the reviewer's own fork
# passes: only the base repository is compared.
#
# git only: the script calls no gh; every row asserts 0 gh calls. git is not
# stubbed: the SUT reads origin through tools/origin-repo.sh, and a real
# repository whose origin path ends in acme/widgets.git presents that identity
# offline (see ../lib/gitrepo.sh).
#
# RED verification (see tests/README.md): against the pre-port script every row
# fails but four (`SUT=<old> tests/run.sh ...`, not ok 7/11): the rows that reach
# gh fail on an unstubbed `gh repo view`, and 'url naming another repository',
# 'no origin', 'unparseable reference' and 'no argument' pass because the old
# script answered them before gh. Dropping the origin comparison makes 'url
# naming another repository' answer a PR line. Against a script that keeps its
# own copy of the normalization, 'a changed shared helper reaches this caller'
# fails by answering that PR line, and every other row stays green.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/check-pr-repo.sh}"

failed=0
total=0

ACME_WIDGETS="$(git_repo_bare acme widgets)"

WIDGETS="$(git_repo_scratch widgets-work)"
git_repo_init "$WIDGETS" main
git_repo_remote "$WIDGETS" origin "$ACME_WIDGETS"

# Fetches acme/widgets, pushes to the reviewer's fork. Set repo-locally:
# ../lib/gitrepo.sh cuts the global config out.
PUSHFORK="$(git_repo_scratch pushfork-work)"
git_repo_init "$PUSHFORK" main
git_repo_remote "$PUSHFORK" origin "$ACME_WIDGETS"
git -C "$PUSHFORK" config remote.origin.pushurl "$(git_repo_bare me widgets)"

NOREMOTE="$(git_repo_scratch noremote-work)"
git_repo_init "$NOREMOTE" main

row_start
run_in "$WIDGETS" 12
assert_row 'bare number' 0 'PR 12 repo=acme/widgets\n' 0

row_start
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12
assert_row 'url' 0 'PR 12 repo=acme/widgets\n' 0

row_start
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12/files
assert_row 'url with trailing path' 0 'PR 12 repo=acme/widgets\n' 0

row_start
run_in "$WIDGETS" https://github.com/ACME/widgets/pull/12
assert_row 'case differs' 0 'PR 12 repo=acme/widgets\n' 0

row_start
run_in "$WIDGETS" https://github.com/other/elsewhere/pull/12
assert_row 'url naming another repository' 0 'STOP wrong-checkout\n' 0

row_start
run_in "$PUSHFORK" https://github.com/acme/widgets/pull/12
assert_row 'checkout pushing to a fork' 0 'PR 12 repo=acme/widgets\n' 0

row_start
run_in "$NOREMOTE" 12
assert_row 'no origin' 0 'STOP wrong-checkout\n' 0

row_start
run_in "$WIDGETS" not-a-reference
assert_row 'unparseable reference' 2 '' 0

row_start
run_in "$WIDGETS"
assert_row 'no argument' 2 '' 0

# --- 10/11. this script's normalization is the shared helper, not a copy of it
# The control row is what makes the second row's verdict about the helper: the
# same mirrored tree answers like the tree, and only after one line of the helper
# changes does this caller's answer move. A caller that kept its own copy of the
# reduction would answer the PR line in row 11.
MIRROR="${HARNESS_TMP}/mirror"
mkdir -p "${MIRROR}/skills/review-pr/scripts"
cp -a "${REPO_ROOT}/tools" "${MIRROR}/tools"
cp "$SUT" "${MIRROR}/skills/review-pr/scripts/"
SUT="${MIRROR}/skills/review-pr/scripts/${SUT##*/}"

row_start
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12
assert_row 'the copy answers like the tree' 0 'PR 12 repo=acme/widgets\n' 0

row_start
cp "${REPO_ROOT}/tests/lib/mutant/normalize-repo-path.sh" "${MIRROR}/tools/"
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12
assert_row 'a changed shared helper reaches this caller' 0 'STOP wrong-checkout\n' 0

harness_exit "$failed" "$total"
