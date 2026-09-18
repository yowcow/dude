#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/plan-comment-payload.sh: the shared
# guard-plus-wrap both plan-work posting scripts call. The payload is compared
# byte for byte against the same hand-written golden the two caller tests use,
# so a `jq -R` (one document per line, same argv) regression is detectable here
# rather than twice over there.
#
# RED verification (mutations are not committed) — see tests/README.md:
#   tmp="$(mktemp -d)"; cp skills/plan-work/scripts/plan-comment-payload.sh "$tmp/mut.sh"
#   # edit one guard out of "$tmp/mut.sh", then:
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/plan-comment-payload_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/plan-comment-payload.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

BODY="${HERE}/fixtures/plan-body.md"
MISSING="${HARNESS_TMP}/no-such-body.md"
UNREADABLE="${HARNESS_TMP}/unreadable-body.md"
cp -- "$BODY" "$UNREADABLE"
chmod 000 "$UNREADABLE"

failed=0
total=0

row_start
run_sut bash "$SUT" "$BODY"
fails_here=0
if ! check_eq 'readable-body-prints-payload: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'readable-body-prints-payload: gh responses' 0 "$(gh_call_count)"; then fails_here=1; fi
if ! check_stdout_files 'readable-body-prints-payload: stdout' "${HERE}/expected/plan-body.payload.json"; then fails_here=1; fi
if ! check_no_violations 'readable-body-prints-payload: argv'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

row_start
run_sut bash "$SUT" "$MISSING"
assert_row 'missing-body-file' 1 '' 0

# chmod 000 does not stop uid 0: there `-r` is true and the guard rightly lets
# the body through, so the row is skipped rather than failed — same shape as
# the caller tests' @UNREADABLE skip.
if [ -r "$UNREADABLE" ]; then
  printf 'skip unreadable-body-file: chmod 000 left %s readable as uid %s\n' "$UNREADABLE" "$(id -u)"
else
  row_start
  run_sut bash "$SUT" "$UNREADABLE"
  assert_row 'unreadable-body-file' 1 '' 0
fi

row_start
run_sut bash "$SUT"
assert_row 'no-arguments' 2 '' 0

row_start
run_sut bash "$SUT" "$BODY" extra
assert_row 'two-arguments' 2 '' 0

harness_exit "$failed" "$total"
