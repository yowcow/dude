#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/exit-batch-record.sh: it marks
# the run batched on first set, refuses a second set, probes with check,
# and clears with clear. The record lives in the worktree's git dir.
#
# git is not stubbed: the record lives in a real repository's git dir. No row
# stubs `gh` either — this script never calls it, and every row asserts zero
# gh calls to hold that.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; the broken variant is `set` without the already-batched
# guard, which fails `second-set-refused`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/exit-batch-record.sh}"
RECORD_NAME='dude-pr-to-ready-exit-batch'

failed=0
total=0

W="$(git_repo_scratch present)"
git_repo_init "$W" main
RECORD="$(git -C "$W" rev-parse --absolute-git-dir)/${RECORD_NAME}"

row_start
run_in "$W" check
assert_row 'check-absent-is-clean' 0 'NO-BATCH
' 0
tally check_eq 'check-absent-is-clean: record' 'absent' \
  "$(if [ -e "$RECORD" ]; then echo present; else echo absent; fi)"

row_start
run_in "$W" set
assert_row 'first-set-marks-batched' 0 'BATCHED
' 0
tally check_eq 'first-set-marks-batched: record' 'present' \
  "$(if [ -e "$RECORD" ]; then echo present; else echo absent; fi)"

row_start
BEFORE="$(cat "$RECORD")"
run_in "$W" set
assert_row 'second-set-refused' 1 'ALREADY-BATCHED
' 0
tally check_eq 'second-set-refused: record unchanged' "$BEFORE" "$(cat "$RECORD")"

row_start
run_in "$W" check
assert_row 'check-after-set-refuses' 1 'ALREADY-BATCHED
' 0

row_start
run_in "$W" clear
assert_row 'clear-removes' 0 '' 0
tally check_eq 'clear-removes: record' 'absent' \
  "$(if [ -e "$RECORD" ]; then echo present; else echo absent; fi)"

row_start
run_in "$W" clear
assert_row 'clear-absent-still-succeeds' 0 '' 0

row_start
run_in "$W" bogus
assert_row 'bad-subcommand-is-usage' 2 '' 0
tally check_stderr_has 'bad-subcommand-is-usage: stderr' 'Usage:'

harness_exit "$failed" "$total"
