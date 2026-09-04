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

# stub_first <repo> <mergeable> [<base-ref>]  -- the opening `gh pr view`
stub_first() {
  local repo="$1" mergeable="$2" base="${3:-main}"
  printf '%s %s\n' "$base" "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${repo}" \
      --json baseRefName,mergeable --jq "$FIRST_JQ"
}

# stub_reread <repo> <mergeable> -- every re-read answers the same
stub_reread() {
  local repo="$1" mergeable="$2"
  printf '%s\n' "$mergeable" |
    gh_stub_response '*' 0 pr view "$PR" -R "${OWNER}/${repo}" \
      --json mergeable --jq .mergeable
}

# assert_row <name> <want-exit> <want-stdout> [<want-gh-calls>]
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" want_calls="${4:-}" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if [ -n "$want_calls" ] && ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

total=$((total + 1))
stub_dir_new
stub_first "$REPO" MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'mergeable-base-ok' 0 'BASE-OK main MERGEABLE\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" CONFLICTING
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'conflicting-base-ok' 0 'BASE-OK main CONFLICTING\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" MERGEABLE develop
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'base-drift-reports-current-base' 0 'BASE-DRIFT develop MERGEABLE\n' 1

total=$((total + 1))
stub_dir_new
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json baseRefName,mergeable --jq "$FIRST_JQ"
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'first-read-fails' 0 'STOP pr-read-failed\n' 1

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
: | gh_stub_response '*' 1 pr view "$PR" -R "${OWNER}/${REPO}" \
  --json mergeable --jq .mergeable
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 're-read-fails' 0 'STOP pr-read-failed\n' 2

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" MERGEABLE
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'unknown-then-resolves-on-re-read' 0 'BASE-OK main MERGEABLE\n' 2

total=$((total + 1))
stub_dir_new
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR"
assert_row 'too-few-args' 1 '' 0

total=$((total + 1))
stub_dir_new
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main extra
assert_row 'too-many-args' 1 '' 0

# ---- exhausting the re-read leaves UNKNOWN as the terminal answer ---------
#
# Six gh calls: the opening read plus MERGEABLE_RETRY_MAX=5 re-reads, and five
# sleeps between them. Asserting both is what pins the bound; the sleeps are
# instant, so the row costs no wall clock.

total=$((total + 1))
stub_dir_new
stub_first "$REPO" UNKNOWN
stub_reread "$REPO" UNKNOWN
run_sut bash "$SUT" "$OWNER" "$REPO" "$PR" main
assert_row 'unknown-outlasts-re-read' 0 'BASE-OK main UNKNOWN\n' 6

total=$((total + 1))
if ! check_eq 'unknown-outlasts-re-read: sleeps' '5' "$(sleep_call_count)"; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
