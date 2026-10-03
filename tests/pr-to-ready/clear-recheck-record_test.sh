#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/clear-recheck-record.sh: it removes
# recheck-pr.sh's record from the worktree's git dir when one is there, and
# succeeds when none is.
#
# git is not stubbed: the record lives in a real repository's git dir. No row
# stubs `gh` either — this script never calls it, and every row asserts zero
# gh calls to hold that.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; the broken variant is `rm` without `-f`, which fails
# `no-record-still-succeeds`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/clear-recheck-record.sh}"
RECORD_NAME='dude-pr-to-ready-recheck'

failed=0
total=0

row_start
W="$(git_repo_scratch present)"
git_repo_init "$W" main
RECORD="$(git -C "$W" rev-parse --absolute-git-dir)/${RECORD_NAME}"
printf 'met deadbeef\n' >"$RECORD"
run_in "$W"
assert_row 'record-present-is-removed' 0 '' 0
tally check_eq 'record-present-is-removed: record' 'absent' \
  "$(if [ -e "$RECORD" ]; then echo present; else echo absent; fi)"

row_start
W="$(git_repo_scratch absent)"
git_repo_init "$W" main
run_in "$W"
assert_row 'no-record-still-succeeds' 0 '' 0

harness_exit "$failed" "$total"
