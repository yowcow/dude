#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/check-pr-state.sh: the three
# values of `mergeable`, and the bounded re-read that `UNKNOWN` triggers.
#
# Limitation: the SUT extracts fields with `gh --jq`, and the fake `gh` does not
# run jq -- it returns the post-jq bytes a case scripted. A defect in the --jq
# expression itself is therefore invisible here.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/check-pr-state.sh}"

stub_sleep_instant

OWNER=acme
REPO=widgets
PR=7
FIRST_JQ='"\(.baseRefName) \(.mergeable)"'

failed=0
total=0

# stub_first <mergeable> [<base-ref>]  -- the opening `gh pr view`
stub_first() {
  local mergeable="$1" base="${2:-main}"
  printf '%s %s\n' "$base" "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${REPO}" \
      --json baseRefName,mergeable --jq "$FIRST_JQ"
}

# stub_reread <mergeable> -- every re-read answers the same
stub_reread() {
  local mergeable="$1"
  printf '%s\n' "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${REPO}" \
      --json mergeable --jq .mergeable
}

row_start
stub_first MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'mergeable-base-ok' 0 'BASE-OK main MERGEABLE\n' 1

row_start
stub_first CONFLICTING
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'conflicting-base-ok' 0 'BASE-OK main CONFLICTING\n' 1

row_start
stub_first MERGEABLE develop
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'base-drift-reports-current-base' 0 'BASE-DRIFT develop MERGEABLE\n' 1

row_start
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json baseRefName,mergeable --jq "$FIRST_JQ"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'first-read-fails' 0 'STOP pr-read-failed\n' 1

row_start
stub_first UNKNOWN
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json mergeable --jq .mergeable
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 're-read-fails' 0 'STOP pr-read-failed\n' 2

row_start
stub_first UNKNOWN
stub_reread MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'unknown-then-resolves-on-re-read' 0 'BASE-OK main MERGEABLE\n' 2

row_start
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR"
assert_row 'too-few-args' 1 '' 0

row_start
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main extra
assert_row 'too-many-args' 1 '' 0

# ---- exhausting the re-read leaves UNKNOWN as the terminal answer ---------
#
# Six gh calls: the opening read plus MERGEABLE_RETRY_MAX=5 re-reads, and five
# sleeps between them. Asserting both is what pins the bound; the sleeps are
# instant, so the row costs no wall clock.

row_start
stub_first UNKNOWN
stub_reread UNKNOWN
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'unknown-outlasts-re-read' 0 'BASE-OK main UNKNOWN\n' 6
tally check_eq 'unknown-outlasts-re-read: sleeps' '5' "$(sleep_call_count)"

harness_exit "$failed" "$total"
