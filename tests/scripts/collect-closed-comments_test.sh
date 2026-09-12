#!/usr/bin/env bash
# Table test for scripts/collect-closed-comments.sh.
#
# Empty stdout alone never means "no comments": a failing gh call prints
# nothing too. The no-response rows and genuine-empty print the same zero
# stdout bytes and differ by exit status and whether the snapshot file exists.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/scripts/collect-closed-comments.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"
FIXTURES="${HERE}/fixtures"

OWNER='acme'
REPO='widgets'
JQ='.[]'

CLOSED_EP="repos/${OWNER}/${REPO}/issues?state=closed&per_page=100"
CONV_EP="repos/${OWNER}/${REPO}/issues/comments?per_page=100"
INLINE_EP="repos/${OWNER}/${REPO}/pulls/comments?per_page=100"

failed=0
total=0

# stub_pages <start-index> <endpoint> <entry,entry,...>
# Each entry is `<fixture>[:<exit-status>]`, with fixture `-` for an empty body.
# Successive entries are pages of one --paginate invocation.
stub_pages() {
  local idx="$1" endpoint="$2" entries="$3"
  local entry fixture status body
  IFS=',' read -ra seq <<<"$entries"
  for entry in "${seq[@]}"; do
    fixture="${entry%%:*}"
    status=0
    case "$entry" in *:*) status="${entry##*:}" ;; esac
    body=/dev/null
    if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
    gh_stub_raw_response "$idx" "$status" \
      api "$endpoint" --paginate --jq "$JQ" <"$body"
    idx=$((idx + 1))
  done
}

# check_snapshot <label> <want-file|->
# `-` means the snapshot path must not exist. Otherwise byte-compare.
check_snapshot() {
  local label="$1" want="$2"
  if [ "$want" = '-' ]; then
    if [ -e "$SNAPSHOT" ]; then
      printf 'FAIL %s: snapshot was written\n' "$label"
      return 1
    fi
    return 0
  fi
  if [ ! -f "$SNAPSHOT" ]; then
    printf 'FAIL %s: snapshot was not written\n' "$label"
    return 1
  fi
  if cmp -s "$want" "$SNAPSHOT"; then
    return 0
  fi
  printf 'FAIL %s: snapshot differs\n  want: %s\n  got:  %s\n' \
    "$label" "$(od -An -c <"$want" | tr -s ' \n' ' ')" \
    "$(od -An -c <"$SNAPSHOT" | tr -s ' \n' ' ')"
  return 1
}

assert_case() {
  local name="$1" want_exit="$2" want_calls="$3" want_stdout="$4" want_snap="$5"
  local fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${name}: gh responses" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if [ "$want_stdout" = '-' ]; then
    if ! check_bytes "${name}: stdout" ""; then fails=1; fi
  else
    if ! check_stdout_files "${name}: stdout" "$want_stdout"; then fails=1; fi
  fi
  if ! check_snapshot "${name}: snapshot" "$want_snap"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
run_sut bash "$SUT"
assert_case 'no-args' 2 0 - -

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
run_sut bash "$SUT" "$OWNER" "$REPO"
assert_case 'missing-snapshot-arg' 2 0 - -

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT" extra
assert_case 'too-many-args' 2 0 - -

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
stub_pages 1 "$CLOSED_EP" 'empty:1'
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT"
assert_case 'closed-list-fails' 1 1 - -

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
stub_pages 1 "$CLOSED_EP" 'empty'
stub_pages 2 "$CONV_EP" 'empty'
stub_pages 3 "$INLINE_EP" 'empty'
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT"
assert_case 'genuine-empty' 0 3 "${HERE}/expected/empty-summary.json" /dev/null

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
stub_pages 1 "$CLOSED_EP" 'closed-page1,closed-page2'
stub_pages 3 "$CONV_EP" 'conv-page1,conv-page2'
stub_pages 5 "$INLINE_EP" 'inline-page1,inline-page2'
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT"
assert_case 'two-pages' 0 6 "${HERE}/expected/two-pages-summary-no-terms.json" "${HERE}/expected/two-pages.jsonl"

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
stub_pages 1 "$CLOSED_EP" 'empty'
stub_pages 2 "$CONV_EP" 'conv-page1,bad-credentials:1'
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT"
assert_case 'conv-fail-mid-page' 1 3 - -

row_start
SNAPSHOT="${GH_STUB_DIR}/snapshot.jsonl"
stub_pages 1 "$CLOSED_EP" 'closed-page1'
stub_pages 2 "$CONV_EP" 'conv-missing-url'
stub_pages 3 "$INLINE_EP" 'empty'
run_sut bash "$SUT" "$OWNER" "$REPO" "$SNAPSHOT"
assert_case 'missing-html-url' 1 3 - -

harness_exit "$failed" "$total"
