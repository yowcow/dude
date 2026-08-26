#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/watch-copilot-review.sh: each row
# is a sequence of `gh` responses plus a baseline-file kind and an argv, against
# the exit status, the number of `gh` calls, and the exact bytes on stdout.
#
# The sibling list-copilot-reviews.sh is not stubbed — the real script runs, on
# top of the fake `gh`. So each row exercises the pair, and the `--jq` filter
# that sibling passes is pinned byte-for-byte: it is part of the argv the stub
# matches on, and an edit to it there fails every row here as "the gh stub was
# called with an argv no case stubbed". That duplication is the point. What is
# *not* exercised is what the filter computes: the stub returns bodies verbatim
# and never runs jq, so a fixture holds what `gh` prints after the filter, one
# compact JSON object per line.
#
# The call count is part of the expectation, not decoration: exit 2 divides into
# a guard that must reject before asking the API and a poll that must ask, and
# the defect fixed in 25982ae was exactly an unvalidated parameter answering
# "no new review arrived" without a single call.
#
# RED verification (each row that covers a fix must fail against the pre-fix
# script) — see tests/README.md. The sibling has to be copied next to the
# pre-fix script: watch-copilot-review.sh finds it through `dirname "$0"`, so a
# pre-fix copy sitting alone in a temp dir would fail to find it, every listing
# would come back empty, and rows would fail for the wrong reason.
#   tmp="$(mktemp -d)"
#   git show 9600d30^:skills/pr-to-ready/scripts/watch-copilot-review.sh >"$tmp/watch-copilot-review.sh"
#   cp skills/pr-to-ready/scripts/list-copilot-reviews.sh "$tmp/"
#   SUT="$tmp/watch-copilot-review.sh" tests/run.sh tests/pr-to-ready/watch-copilot-review_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/watch-copilot-review.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"
TWO="${FIXTURES}/copilot-reviews-two.jsonl"

# A verbatim copy of the --jq argument in list-copilot-reviews.sh:41-43,
# including its eight-space continuation indent. It is one argv element that
# spans three lines, which is why the manifest has to be able to hold one.
JQ_FILTER='.reviews[]
        | select((.author.login // "") | ascii_downcase | contains("copilot"))
        | {id, author: (.author.login // ""), state, submittedAt}'

# Makes the baseline file the row asked for and prints its path.
#   absent      — a path with nothing at it
#   unreadable  — a regular file that cannot be read
#   dir         — a directory
#   empty       — an empty regular file
#   all         — every line of the fixture, so nothing is new
#   first       — only the fixture's first line, so the second is new
#   id-only     — just the first line's id, a proper substring of that line.
#                 This is the malformed baseline SKILL.md used to prescribe
#                 before 9600d30 ("record the id"), and it is not a listing:
#                 a bare id is not JSON, so no `.id` can be read from it. The
#                 script has to say so and stop, rather than read the file as
#                 an empty baseline and report reviews the caller has already
#                 seen as new.
#   no-id       — one JSON object with no `id` key. Readable as JSON, unlike
#                 id-only, so it is the other way a baseline can fail to
#                 yield an id: `jq -r` would render the missing key as `null`
#                 and admit it to the set as an id no review can match.
make_baseline() {
  local kind="$1" dir path first_line id
  dir="$(mktemp -d "${HARNESS_TMP}/baseline.XXXXXX")"
  path="${dir}/baseline"
  case "$kind" in
    absent) ;;
    unreadable)
      : >"$path"
      chmod 000 "$path"
      # Asserted rather than assumed: chmod 000 does not stop uid 0, and a
      # readable "unreadable" file would send the row down the poll path and
      # report exit 1 as a defect in the script under test. Failing here says
      # the row cannot be tested in this environment, which is the honest answer.
      if [ -r "$path" ]; then
        echo "make_baseline: ${path} is still readable — running as uid $(id -u)?" >&2
        return 1
      fi
      ;;
    dir) mkdir "$path" ;;
    empty) : >"$path" ;;
    no-id) printf '%s\n' '{"author":"copilot-pull-request-reviewer","state":"COMMENTED"}' >"$path" ;;
    all) cat "$TWO" >"$path" ;;
    first) head -n 1 "$TWO" >"$path" ;;
    id-only)
      # Derived from the fixture rather than written out again, so the line
      # stays a real id of a review the listing carries — the legacy baseline
      # shape rather than an invented string. Asserted rather than assumed,
      # because `sed` prints a
      # non-matching line through unchanged: a fixture that stopped carrying
      # an `id` key would silently turn this kind into a copy of `first`, and
      # the row would go on passing with the detection power it exists for
      # gone. Same reason the `unreadable` kind above checks its own result.
      first_line="$(head -n 1 "$TWO")"
      id="$(printf '%s' "$first_line" | sed 's/.*"id":"\([^"]*\)".*/\1/')"
      if [ -z "$id" ] || [ "$id" = "$first_line" ]; then
        echo "make_baseline: no id extracted from the fixture's first line" >&2
        return 1
      fi
      printf '%s\n' "$id" >"$path"
      ;;
    *)
      echo "make_baseline: unknown kind '${kind}'" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

failed=0
total=0

while IFS='|' read -r name responses baseline args want_exit want_calls want_out; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  # Each entry answers one call; the last also answers every later call, which
  # is what lets a row hold a poll loop at one state until the cap runs out.
  IFS=',' read -ra resp_seq <<<"$responses"
  i=1
  for entry in "${resp_seq[@]}"; do
    fixture="${entry%%:*}"
    status=0
    case "$entry" in *:*) status="${entry##*:}" ;; esac
    body=/dev/null
    if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.jsonl"; fi
    if [ "$i" -eq "${#resp_seq[@]}" ]; then
      gh_stub_response '*' "$status" pr view 7 --repo acme/widgets --json reviews --jq "$JQ_FILTER" <"$body"
    else
      gh_stub_response "$i" "$status" pr view 7 --repo acme/widgets --json reviews --jq "$JQ_FILTER" <"$body"
    fi
    i=$((i + 1))
  done

  fails_here=0
  if ! baseline_path="$(make_baseline "$baseline")"; then
    printf 'FAIL %s: baseline setup failed\n' "$name"
    failed=$((failed + 1))
    continue
  fi

  read -ra argv <<<"${args//%B/$baseline_path}"
  run_sut bash "$SUT" "${argv[@]}"

  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|responses|baseline|args|exit|calls|stdout
new-review-prints-both|copilot-reviews-two|empty|acme widgets 7 %B 1 1|0|1|{"author":"copilot-pull-request-reviewer","id":"PRR_kwDOAZjEl88AAAABKNbcig","state":"COMMENTED","submittedAt":"2026-08-20T07:29:15Z"}\n{"author":"copilot-pull-request-reviewer","id":"PRR_kwDOAZjEl88AAAABKNnbbA","state":"COMMENTED","submittedAt":"2026-08-20T07:54:06Z"}\n
only-the-line-not-in-baseline|copilot-reviews-two|first|acme widgets 7 %B 1 1|0|1|{"author":"copilot-pull-request-reviewer","id":"PRR_kwDOAZjEl88AAAABKNnbbA","state":"COMMENTED","submittedAt":"2026-08-20T07:54:06Z"}\n
baseline-not-a-listing|copilot-reviews-two|id-only|acme widgets 7 %B 1 1|2|0|
arrives-on-the-second-poll|-,copilot-reviews-two|empty|acme widgets 7 %B 3 1|0|2|{"author":"copilot-pull-request-reviewer","id":"PRR_kwDOAZjEl88AAAABKNbcig","state":"COMMENTED","submittedAt":"2026-08-20T07:29:15Z"}\n{"author":"copilot-pull-request-reviewer","id":"PRR_kwDOAZjEl88AAAABKNnbbA","state":"COMMENTED","submittedAt":"2026-08-20T07:54:06Z"}\n
state-change-is-not-new|copilot-reviews-one-dismissed|first|acme widgets 7 %B 1 1|1|1|
everything-already-in-baseline|copilot-reviews-two|all|acme widgets 7 %B 1 1|1|1|
no-review-yet|-|empty|acme widgets 7 %B 1 1|1|1|
listing-not-a-listing|copilot-reviews-unreadable|empty|acme widgets 7 %B 1 1|1|1|
baseline-object-without-id|copilot-reviews-two|no-id|acme widgets 7 %B 1 1|2|0|
listing-fails-every-poll|-:1|empty|acme widgets 7 %B 2 1|1|2|
baseline-absent|copilot-reviews-two|absent|acme widgets 7 %B 1 1|2|0|
baseline-unreadable|copilot-reviews-two|unreadable|acme widgets 7 %B 1 1|2|0|
baseline-is-a-directory|copilot-reviews-two|dir|acme widgets 7 %B 1 1|2|0|
too-few-args|copilot-reviews-two|absent|acme widgets 7|2|0|
too-many-args|copilot-reviews-two|empty|acme widgets 7 %B 1 1 extra|2|0|
non-numeric-max-iterations|copilot-reviews-two|empty|acme widgets 7 %B abc 1|2|0|
zero-max-iterations|copilot-reviews-two|empty|acme widgets 7 %B 0 1|2|0|
fractional-max-iterations|copilot-reviews-two|empty|acme widgets 7 %B 1.5 1|2|0|
non-numeric-interval|copilot-reviews-two|empty|acme widgets 7 %B 1 xyz|2|0|
ROWS

harness_exit "$failed" "$total"
