#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/set-prerequisites.sh: the guard its
# header names — the resulting blocked-by set is read back and compared against
# the intended one, and a mismatch exits non-zero — plus the declarative
# add-and-remove the header describes ("adds what is missing and removes what is
# no longer required. Pass none at all for an item that is independent").
#
# The edit's argv is the assertion. The script computes which numbers to add and
# which to remove, and the fake `gh` matches the argv byte for byte, so a row
# stubs the exact `--add-blocked-by`/`--remove-blocked-by` sequence it expects
# and any other computation reaches an argv no case stubbed. Rows that must not
# edit at all register no edit stub, which is stronger than a call count: it
# fails on the attempt rather than on the total.
#
# The script calls `gh issue view` twice with an identical argv — the current
# set, then the read-back — with the edit between them. The stub addresses calls
# by global index, so a row that edits stubs 1/2/3 as view/edit/view, and a row
# that does not edit stubs 1/2 as view/view. That is why the indices below are
# not uniform across rows.
#
# One row carries 9, 12 and 100 deliberately: they are the smallest set where
# lexical and numeric order disagree, so the flag order in that row's argv —
# 100, then 12, then 9 — is what pins the script's lexical sort. Measured, the
# numerically-sorted variant does not fail the way the script's header predicts:
# the header says `comm` "silently produces the wrong difference", but `comm`
# detects the disorder, writes `input is not in sorted order` and exits 1, and
# `set -euo pipefail` aborts before the edit is sent. The row catches it either
# way — on the call count, not on a wrong argv.
#
# The bodies are raw `gh issue view` responses registered with
# gh_stub_raw_response, so the script's own `--jq '.blockedBy.nodes[].number'`
# really runs.
#
# RED verification (see tests/README.md) — no usable pre-fix version exists,
# so detection power is shown by removing one named guard at a time:
#   tmp="$(mktemp -d)"
#   cp skills/plan-work/scripts/set-prerequisites.sh "$tmp/mut.sh"
#   # guard 1: delete the FINAL != DESIRED block
#   # guard 2: delete the TO_REMOVE loop that builds --remove-blocked-by
#   # guard 3: sort numerically (sort -nu) instead of lexically
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/set-prerequisites_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/set-prerequisites.sh}"

OWNER=acme
REPO=widgets
CHILD=57

failed=0
total=0

# blocked_by_body <number>...   a raw `gh issue view --json blockedBy` response
blocked_by_body() {
  local n sep='' out='{"blockedBy":{"nodes":['
  for n in "$@"; do
    out="${out}${sep}{\"number\":${n},\"title\":\"prereq ${n}\"}"
    sep=','
  done
  printf '%s]}}\n' "$out"
}

# stub_view <index> <status> <number>...   one `gh issue view` round trip
stub_view() {
  local idx="$1" status="$2"
  shift 2
  blocked_by_body "$@" |
    gh_stub_raw_response "$idx" "$status" \
      issue view "$CHILD" --repo "${OWNER}/${REPO}" --json blockedBy \
      --jq '.blockedBy.nodes[].number'
}

# stub_edit <index> <status> <flag>...   the edit, keyed on its exact argv
stub_edit() {
  local idx="$1" status="$2"
  shift 2
  : | gh_stub_response "$idx" "$status" \
    issue edit "$CHILD" --repo "${OWNER}/${REPO}" "$@"
}

# --- no prerequisites: the independent item ---------------------------------

row_start
stub_view 1 0
stub_view 2 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD"
assert_row independent-already 0 "#57 blocked-by count: 0 []\n" 2

row_start
stub_view 1 0 12
stub_edit 2 0 --remove-blocked-by 12
stub_view 3 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD"
assert_row independent-clears-a-stale-relation 0 "#57 blocked-by count: 0 []\n" 3

# --- one prerequisite -------------------------------------------------------

row_start
stub_view 1 0
stub_edit 2 0 --add-blocked-by 12
stub_view 3 0 12
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row one-prereq-added 0 "#57 blocked-by count: 1 [12 ]\n" 3

row_start
stub_view 1 0 12
stub_view 2 0 12
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row one-prereq-already-set 0 "#57 blocked-by count: 1 [12 ]\n" 2

# --- several prerequisites, and the lexical order the script depends on -----

row_start
stub_view 1 0
stub_edit 2 0 --add-blocked-by 100 --add-blocked-by 12 --add-blocked-by 9
stub_view 3 0 9 12 100
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12 9 100
assert_row three-prereqs-lexical-order 0 "#57 blocked-by count: 3 [100 12 9 ]\n" 3

row_start
stub_view 1 0
stub_edit 2 0 --add-blocked-by 12
stub_view 3 0 12
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12 12
assert_row duplicate-prereqs-collapse 0 "#57 blocked-by count: 1 [12 ]\n" 3

# --- add and remove in the same run -----------------------------------------

row_start
stub_view 1 0 9 12
stub_edit 2 0 --add-blocked-by 100 --remove-blocked-by 9
stub_view 3 0 12 100
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12 100
assert_row add-and-remove 0 "#57 blocked-by count: 2 [100 12 ]\n" 3

# --- the read-back is what decides ------------------------------------------

row_start
stub_view 1 0
stub_edit 2 0 --add-blocked-by 12
stub_view 3 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row edit-reported-success-but-nothing-stuck 1 '' 3

row_start
stub_view 1 0 12
stub_view 2 0 9 12
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row read-back-carries-an-extra-relation 1 '' 2

# --- a call that failed is not a set that is empty --------------------------

row_start
stub_view 1 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row first-view-fails 1 '' 1

row_start
stub_view 1 0
stub_edit 2 1 --add-blocked-by 12
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row edit-fails 1 '' 2

row_start
stub_view 1 0
stub_edit 2 0 --add-blocked-by 12
stub_view 3 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$CHILD" 12
assert_row read-back-fails 1 '' 3

# --- the argument guards run before any call --------------------------------

while IFS='|' read -r name args; do
  case "$name" in '' | '#'*) continue ;; esac
  row_start
  read -ra argv <<<"$args"
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}
  assert_row "$name" 1 '' 0
done <<'ROWS'
# name|args
no-args|
too-few-args|acme widgets
blocked-by-itself-among-others|acme widgets 57 12 57
ROWS

harness_exit "$failed" "$total"
