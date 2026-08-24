#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/link-sub-issue.sh: the two guards
# its header names, driven through the fake `gh`.
#
# Guard 1 — the child is identified to the endpoint by its **database id**, not
# by its issue number. The fixture carries both (`"number": 57`, `"id":
# 5213622913`) and the POST is stubbed on the exact argv carrying the id, so a
# version that posts the number instead reaches an argv no case stubbed and the
# row fails as a violation rather than as a diff.
#
# Guard 2 — the link is read back, and a child absent from the read-back is a
# non-zero exit. Three rows hold that: the child missing from a non-empty
# listing, an empty listing, and a listing carrying only numbers that contain
# `57` as a substring (which is what `grep -qx` refuses).
#
# The fixtures are raw API bodies, registered with gh_stub_raw_response, so the
# script's own `--jq '.id'` and `--jq '.[].number'` really run. A pre-filtered
# body would decide guard 1's question for it.
#
# RED verification (see tests/README.md) — this script has no usable pre-fix
# version in history, so detection power is shown by removing one named guard at
# a time from a copy:
#   tmp="$(mktemp -d)"
#   cp skills/plan-work/scripts/link-sub-issue.sh "$tmp/mut.sh"
#   # guard 1: replace CHILD_ID=$(gh api ...) with CHILD_ID="$CHILD"
#   # guard 2: delete the read-back and the grep -qx block
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/link-sub-issue_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/link-sub-issue.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

OWNER=acme
REPO=widgets
PARENT=42
CHILD=57
CHILD_ID=5213622913

failed=0
total=0

# stub_lookup <fixture> <status>   call 1: number -> database id
stub_lookup() {
  gh_stub_raw_response 1 "$2" \
    api "repos/${OWNER}/${REPO}/issues/${CHILD}" --jq '.id' <"${HERE}/fixtures/$1.json"
}

# stub_post <status>   call 2: the link itself, keyed on the database id
stub_post() {
  : | gh_stub_raw_response 2 "$1" \
    api --method POST "repos/${OWNER}/${REPO}/issues/${PARENT}/sub_issues" \
    -F "sub_issue_id=${CHILD_ID}"
}

# stub_readback <index> <fixture> <status>   call 3+: one page of the read-back
stub_readback() {
  local body=/dev/null
  if [ "$2" != '-' ]; then body="${HERE}/fixtures/$2.json"; fi
  gh_stub_raw_response "$1" "$3" \
    api --paginate "repos/${OWNER}/${REPO}/issues/${PARENT}/sub_issues?per_page=100" \
    --jq '.[].number' <"$body"
}

# assert_row <name> <want-exit> <want-stdout> <want-calls>
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" want_calls="$4" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

LINKED_LINE="linked #${CHILD} (id ${CHILD_ID}) as a sub-issue of #${PARENT}\n"

# --- the child is resolved to its database id before the POST ---------------

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 sub-issues-with-57 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row linked 0 "$LINKED_LINE" 3

# --- the read-back is what decides, not the POST's own exit -----------------

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 sub-issues-without-57 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row child-absent-from-readback 1 '' 3

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 sub-issues-empty 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row readback-empty 1 '' 3

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 sub-issues-near-misses 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row readback-substring-near-misses 1 '' 3

# --- the read-back pages ----------------------------------------------------

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 sub-issues-without-57 0
stub_readback 4 sub-issues-with-57 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row readback-second-page-carries-the-child 0 "$LINKED_LINE" 4

# --- each call's failure is distinct, and stops the ones after it -----------

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row id-lookup-fails 1 '' 1

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row post-fails 1 '' 2

total=$((total + 1))
stub_dir_new
stub_lookup issue-57 0
stub_post 0
stub_readback 3 - 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT" "$CHILD"
assert_row readback-fails 1 '' 3

# --- the argument guards run before any call --------------------------------

while IFS='|' read -r name args; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new
  read -ra argv <<<"$args"
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}
  assert_row "$name" 1 '' 0
done <<'ROWS'
# name|args
no-args|
too-few-args|acme widgets 42
too-many-args|acme widgets 42 57 extra
parent-not-a-number|acme widgets HEAD 57
child-not-a-number|acme widgets 42 fifty-seven
child-number-is-negative|acme widgets 42 -57
ROWS

harness_exit "$failed" "$total"
