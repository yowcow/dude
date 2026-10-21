#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/build-review-payload.sh: a finding
# becomes an inline comment only on a line the reviewed diff adds; one on an
# unchanged line, an untouched file, a line next to a hunk, or with no line
# goes into the body.
#
# git is not stubbed: which lines a diff adds is git's answer, and a real
# repository gives it offline. base has a.txt = 1..5; head changes line 3 of
# a.txt and adds b.txt (2 lines). c.txt exists in neither.
#
# RED verification (see tests/README.md): making in_diff always succeed puts
# every pathed finding inline and fails 'mixed findings' and 'line next to a
# hunk'; going back to a diff limited to the finding's path (`-- "$path"`)
# fails 'renamed file: unchanged line'; dropping the continuation-line indent
# fails 'multi-line body stays in its item'.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/build-review-payload.sh}"
BASH_BIN="$(command -v bash)"

failed=0
total=0

REPO="$(git_repo_scratch payload-work)"
git_repo_init "$REPO" main
git_repo_commit "$REPO" a.txt '1\n2\n3\n4\n5\n' 'base'
git_repo_commit "$REPO" r.txt '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20\n' 'add r'
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
git_repo_commit "$REPO" a.txt '1\n2\nTHREE\n4\n5\n' 'change line 3'
git_repo_commit "$REPO" b.txt 'x\ny\n' 'add b'
# Rename r.txt -> s.txt and edit line 7: staged by git mv, so the commit
# below carries both the removal and the new path.
git -C "$REPO" mv r.txt s.txt
git_repo_commit "$REPO" s.txt '1\n2\n3\n4\n5\n6\nSEVEN\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20\n' 'rename r to s, edit line 7'
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

SUMMARY="${HARNESS_TMP}/summary.md"
printf 'Summary.\n' >"$SUMMARY"
FINDINGS="${HARNESS_TMP}/findings.json"

# assert_payload <name> <want-json-line>
# The output is JSON whose strings carry literal `\n`, which assert_row's
# printf '%b' expectation would turn into newlines, so the want line goes
# through a file instead.
assert_payload() {
  local name="$1" fails=0
  printf '%s\n' "$2" >"${HARNESS_TMP}/want.json"
  if ! check_eq "${name}: exit" 0 "$SUT_STATUS"; then fails=1; fi
  if ! check_stdout_files "${name}: stdout" "${HARNESS_TMP}/want.json"; then fails=1; fi
  if ! check_eq "${name}: gh calls" 0 "$(gh_call_count)"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

row_start
printf '%s' '[{"path":"a.txt","line":3,"body":"Important: in diff"},{"path":"a.txt","line":1,"body":"Minor: unchanged line"},{"path":"b.txt","line":2,"body":"Minor: new file"},{"path":"c.txt","line":1,"body":"Minor: untouched file"},{"path":"a.txt","line":null,"body":"Minor: whole file"},{"path":null,"line":null,"body":"Important: general"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'mixed findings' '{"body":"Summary.\n\n- `a.txt:1`: Minor: unchanged line\n- `c.txt:1`: Minor: untouched file\n- `a.txt`: Minor: whole file\n- Important: general","comments":[{"path":"a.txt","line":3,"side":"RIGHT","body":"Important: in diff"},{"path":"b.txt","line":2,"side":"RIGHT","body":"Minor: new file"}]}'

# GitHub would also take line 4 (diff context); this script deliberately
# does not, so it goes to the body.
row_start
printf '%s' '[{"path":"a.txt","line":4,"body":"Minor: next to the change"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'line next to a hunk' '{"body":"Summary.\n\n- `a.txt:4`: Minor: next to the change","comments":[]}'

# GitHub pairs the rename, so only line 7 of s.txt is in its diff. A diff
# limited to the new path would show all 20 lines as added.
row_start
printf '%s' '[{"path":"s.txt","line":1,"body":"Minor: unchanged line"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'renamed file: unchanged line' '{"body":"Summary.\n\n- `s.txt:1`: Minor: unchanged line","comments":[]}'

row_start
printf '%s' '[{"path":"s.txt","line":7,"body":"Minor: edited line"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'renamed file: edited line' '{"body":"Summary.","comments":[{"path":"s.txt","line":7,"side":"RIGHT","body":"Minor: edited line"}]}'

row_start
printf '%s' '[{"path":"b.txt","line":1,"body":"Minor: only inline"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'everything inline' '{"body":"Summary.","comments":[{"path":"b.txt","line":1,"side":"RIGHT","body":"Minor: only inline"}]}'

# A body line starting with `- ` must stay inside its own item, not read as
# another finding.
row_start
printf '%s' '[{"path":"c.txt","line":1,"body":"Minor: a\n- b"}]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'multi-line body stays in its item' '{"body":"Summary.\n\n- `c.txt:1`: Minor: a\n  - b","comments":[]}'

row_start
printf '[]' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_payload 'no findings' '{"body":"Summary.","comments":[]}'

row_start
printf '{}' >"$FINDINGS"
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_row 'findings not an array' 2 '' 0

row_start
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "${HARNESS_TMP}/no-such-summary.md" "$FINDINGS"
assert_row 'missing summary file' 2 '' 0

# Valid arguments and a valid findings array: the only thing wrong is the
# dependency. `env PATH=` gives the script a PATH with no jq in it; the shell is
# named by absolute path because it is looked up before that PATH applies.
row_start
printf '[]' >"$FINDINGS"
run_sut env PATH="${HARNESS_TMP}/no-path" "$BASH_BIN" "$SUT" \
  "$BASE_SHA" "$HEAD_SHA" "$SUMMARY" "$FINDINGS"
assert_row 'missing jq: named, not usage' 1 '' 0
tally check_eq 'missing jq: stderr' \
  'error: jq is required but was not found on PATH' "$(cat "$SUT_STDERR")"

row_start
run_in "$REPO" "$BASE_SHA" "$HEAD_SHA" "$SUMMARY"
assert_row 'too few arguments' 2 '' 0

harness_exit "$failed" "$total"
