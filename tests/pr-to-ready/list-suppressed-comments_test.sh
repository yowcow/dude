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
# The two summary-form rows are the other shape Copilot emits for the same
# block, read the two ways the script is read: the name is carried by
# `<summary>` inside the block's own `<details>`, with no `###` heading and no
# `Review effort level` line. Its body reproduces the structure recorded in
# yowcow/dude#90; the observed review's own text was withheld there.
# `summary-form-block-found` holds the block's start rule to the section name
# plus its count rather than to the markup — the heading rows all pass against a
# rule anchored on `^### `, which is the defect it was added for.
# `summary-form-projected` holds the projection's own read of N to that same
# markup-blind rule: with the start rule moved and the projection's left where it
# was, this fixture reaches the clean judgment as exit 4 — the block is found and
# then read as carrying a count nothing declared — so the shape #92 fixed goes
# back to being unreadable there, loudly rather than silently.
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
# The projection rows and the --full rows are the two consumers this script now
# serves. `suppressed-block-found` pins what the clean judgment reads and
# `suppressed-block-full` pins that 2-3's collection still gets the block's own
# bytes; expected/suppressed-block.out is unchanged from before the projection,
# which is what makes the second one evidence rather than a restatement. The
# summary-form pair reads its one fixture the same two ways, against
# expected/suppressed-block-summary-form.out unchanged from #92.
#
# `two-entries-projected` is the row that exists for the projection's print loop
# (`for (i = 1; i <= count; i++)`): its fixture declares N=2 so the loop runs
# past a single entry, where every heading-form row that passes declares N=1 and
# the one other N=2 heading fixture (`count-mismatch-stops`) exits 4 before the
# loop is reached. An off-by-one in that loop's bounds (say, `i < count`) would
# still satisfy the guard, since the guard compares `declared` against the count
# accumulated during the parse pass, not against what the loop actually printed
# — so the script would exit 0 with fewer `path:line` lines than its own
# `suppressed<TAB>N` header promises, and the clean judgment would read fewer
# outstanding suppressed findings than the review actually holds, taking a PR to
# ready with one left unaddressed.
#
# `count-mismatch-stops` and `count-mismatch-full-still-prints` are one fixture
# read two ways: the heading declares two entries and only one line parses, so
# the default path exits 4 with nothing on stdout while --full keeps handing back
# the block. Without the first, a Copilot format change would reach the clean
# judgment as "no suppressed findings" and take a PR to ready with one
# outstanding.
#
# RED verification (see tests/README.md). Unlike the commits tests/README.md
# names, this one resolves in this repository: 0c685b4 is master as both #87 and
# #92 were branched from. Eight of the fifteen rows fail against it — every row
# that carries a `--full` argv fails at exit 2 on the unknown flag, every
# projection row prints the block instead of the projection, `count-mismatch-stops`
# exits 0 rather than 4, and `summary-form-projected` prints nothing at exit 0
# because a start rule anchored on `^### ` matched no line in that body (#92).
# The projection's own read of N is held separately, and only by
# `summary-form-projected`: leave that rule on `^### Suppressed comments (N)$`
# while the block's start rule moves, and it alone fails, at exit 4:
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
suppressed-block-found|reviews-suppressed|0|acme widgets 7|0|1|suppressed-projection.out
two-entries-projected|reviews-suppressed-two-entries|0|acme widgets 7|0|1|suppressed-two-entries.out
suppressed-block-full|reviews-suppressed|0|--full acme widgets 7|0|1|suppressed-block.out
summary-form-projected|reviews-suppressed-summary-form|0|acme widgets 7|0|1|suppressed-summary-form-projection.out
summary-form-block-found|reviews-suppressed-summary-form|0|--full acme widgets 7|0|1|suppressed-block-summary-form.out
count-mismatch-stops|reviews-suppressed-count-mismatch|0|acme widgets 7|4|1|-
count-mismatch-full-still-prints|reviews-suppressed-count-mismatch|0|--full acme widgets 7|0|1|suppressed-block-mismatch.out
no-suppressed-block|reviews-no-suppressed|0|acme widgets 7|0|1|-
latest-review-wins|reviews-suppressed-not-latest|0|acme widgets 7|0|1|-
latest-review-wins-against-array-order|reviews-suppressed-latest-out-of-order|0|acme widgets 7|0|1|suppressed-projection.out
human-suppressed-block-ignored|reviews-suppressed-by-human|0|acme widgets 7|0|1|-
no-reviews-at-all|reviews-empty|0|acme widgets 7|0|1|-
gh-call-fails|not-found|1|acme widgets 7|1|1|-
too-few-args|reviews-suppressed|0|acme widgets|2|0|-
too-many-args|reviews-suppressed|0|acme widgets 7 extra|2|0|-
ROWS

harness_exit "$failed" "$total"
