#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/list-suppressed-comments.sh: each
# row is one `gh` response — a raw body plus an exit status — and an argv,
# against the exit status, the number of `gh` calls, and the exact bytes on
# stdout.
#
# The bodies are raw, registered with gh_stub_raw_response, because the --jq
# filter is half of what this script does: picking Copilot's *latest* review out
# of the listing. A pre-filtered fixture would decide that for it.
#
# The review bodies in the fixtures are the real ones from yowcow/dude#45 —
# review 5028804955, which carries `### Suppressed comments (1)`, and review
# 5028978936, which carries the same <details> block with no suppressed section.
# That pair is what holds detection and false detection apart.
#
# `summary-form-block-found` is the other shape Copilot emits for the same
# block: the name is carried by `<summary>` inside the block's own `<details>`,
# with no `###` heading and no `Review effort level` line. It is what holds the
# start rule to the section name plus its count rather than to the markup — the
# heading rows all pass against a rule anchored on `^### `, which is the defect
# it was added for. Its body reproduces the structure recorded in
# yowcow/dude#90; the observed review's own text was withheld there.
#
# The two latest-review rows are not a duplicate pair. `latest-review-wins` has
# the listing already in chronological order, which is how the API returns it, so
# it alone would pass against a filter that simply took the array's last element.
# `latest-review-wins-against-array-order` reverses the two, so the answer
# differs between selecting by `submittedAt` and trusting the array: only the
# former prints the block. That is what holds the filter's `sort_by` load-bearing
# rather than incidental.
#
# Empty stdout is not an answer on its own: a failing `gh` call prints nothing on
# stdout either, and neither does a review with no suppressed block.
# `no-suppressed-block` and `gh-call-fails` are the pair that holds those apart,
# and they differ only in the exit status.
#
# RED verification (see tests/README.md) -- against the script as it was before
# the start rule moved off the heading shape, `summary-form-block-found` must
# fail, because the pattern matched no line in that body and the script printed
# nothing at exit 0 (#92). Unlike the commits tests/README.md names, this one
# resolves in this repository: it is master as the fix was branched from.
#   tmp="$(mktemp -d)"
#   git show 0c685b4:skills/pr-to-ready/scripts/list-suppressed-comments.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/list-suppressed-comments_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/list-suppressed-comments.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"
EXPECTED="$(dirname -- "${BASH_SOURCE[0]}")/expected"

# A verbatim copy of the --jq argument in list-suppressed-comments.sh, including
# its eight-space continuation indent. It is one argv element that spans several
# lines, and the stub matches on its exact bytes: an edit to the filter there
# fails every row here as an unstubbed argv rather than passing quietly.
JQ_FILTER='.reviews
        | map(select((.author.login // "") | ascii_downcase | contains("copilot")))
        | sort_by(.submittedAt)
        | last
        | .body // ""'

failed=0
total=0

while IFS='|' read -r name fixture status args want_exit want_calls want_file; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  body=/dev/null
  if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
  gh_stub_raw_response '*' "$status" \
    pr view 7 --repo acme/widgets --json reviews --jq "$JQ_FILTER" <"$body"

  want=/dev/null
  if [ "$want_file" != '-' ]; then want="${EXPECTED}/${want_file}"; fi

  fails_here=0
  read -ra argv <<<"$args"
  run_sut bash "$SUT" "${argv[@]}"

  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_stdout_files "${name}: stdout" "$want"; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|fixture|gh-status|args|exit|calls|expected-file
suppressed-block-found|reviews-suppressed|0|acme widgets 7|0|1|suppressed-block.out
summary-form-block-found|reviews-suppressed-summary-form|0|acme widgets 7|0|1|suppressed-block-summary-form.out
no-suppressed-block|reviews-no-suppressed|0|acme widgets 7|0|1|-
latest-review-wins|reviews-suppressed-not-latest|0|acme widgets 7|0|1|-
latest-review-wins-against-array-order|reviews-suppressed-latest-out-of-order|0|acme widgets 7|0|1|suppressed-block.out
human-suppressed-block-ignored|reviews-suppressed-by-human|0|acme widgets 7|0|1|-
no-reviews-at-all|reviews-empty|0|acme widgets 7|0|1|-
gh-call-fails|not-found|1|acme widgets 7|1|1|-
too-few-args|reviews-suppressed|0|acme widgets|2|0|-
too-many-args|reviews-suppressed|0|acme widgets 7 extra|2|0|-
ROWS

harness_exit "$failed" "$total"
