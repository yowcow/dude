#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/watch-checks.sh: each row is a
# sequence of `gh` responses plus an argv, against the exit status, the number
# of `gh` calls, and the exact bytes on stdout.
#
# The call count is part of the expectation, not decoration: two of this
# script's documented statuses (2 and 4) differ mainly in whether the API was
# ever asked, and the defect fixed in 25982ae was exactly an exit 4 handed back
# without a single call.
#
# RED verification (each row that covers a fix must fail against the pre-fix
# script) — see tests/README.md:
#   tmp="$(mktemp -d)"
#   git show 9600d30^:skills/pr-to-ready/scripts/watch-checks.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/watch-checks_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean — verified clean under
# `shellcheck -x` too, so item 2's CI is free to invoke it either way.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/watch-checks.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"
ENDPOINT='repos/acme/widgets/commits/deadbeef/check-runs'

failed=0
total=0

while IFS='|' read -r name responses args want_exit want_calls want_out; do
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
    if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
    if [ "$i" -eq "${#resp_seq[@]}" ]; then
      gh_stub_response '*' "$status" api "$ENDPOINT" <"$body"
    else
      gh_stub_response "$i" "$status" api "$ENDPOINT" <"$body"
    fi
    i=$((i + 1))
  done

  read -ra argv <<<"$args"
  run_sut bash "$SUT" "${argv[@]}"

  fails_here=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|responses|args|exit|calls|stdout
settled-prints-rows|check-runs-settled|acme widgets deadbeef 1 1|0|1|build\tcompleted\tsuccess\nlint\tcompleted\tskipped\n
name-that-looks-unsettled-still-settles|check-runs-name-looks-unsettled|acme widgets deadbeef 1 1|0|1|e2e (in_progress shard)\tcompleted\tsuccess\nqueued-jobs monitor\tcompleted\tsuccess\n
unsettled-then-settled|check-runs-in-progress,check-runs-settled|acme widgets deadbeef 3 1|0|2|build\tcompleted\tsuccess\nlint\tcompleted\tskipped\n
still-unsettled-at-cap|check-runs-in-progress|acme widgets deadbeef 2 1|1|2|build\tin_progress\t-\n
empty-listing-prints-nothing|check-runs-empty|acme widgets deadbeef 1 1|1|1|
missing-commit|no-commit-for-sha|acme widgets deadbeef 3 1|3|1|
error-body-every-poll|not-found|acme widgets deadbeef 2 1|4|2|
gh-fails-every-poll|-:1|acme widgets deadbeef 1 1|4|1|
too-few-args|check-runs-settled|acme widgets|2|0|
too-many-args|check-runs-settled|acme widgets deadbeef 1 1 extra|2|0|
non-numeric-max-iterations|check-runs-settled|acme widgets deadbeef abc 1|2|0|
zero-max-iterations|check-runs-settled|acme widgets deadbeef 0 1|2|0|
fractional-max-iterations|check-runs-settled|acme widgets deadbeef 1.5 1|2|0|
non-numeric-interval|check-runs-in-progress|acme widgets deadbeef 2 xyz|2|0|
ROWS

harness_exit "$failed" "$total"
