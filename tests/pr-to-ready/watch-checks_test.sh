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
# Each row scripts three argvs, one per column: the poll's check-runs listing,
# the repository read, and the default branch's check-runs listing. Three
# columns rather than one, because the exit 5 verdict reads the last two on top
# of the poll, and a format with one endpoint per row can only say what the poll
# answered. A column is `-`, or `;`-separated <index>=<fixture>[:<status>]
# specs; <index> is the stub's own global call number, or `*` for every call to
# that argv no exact entry claims, which is what holds a poll loop at one state
# until the cap runs out.
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

stub_sleep_instant

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/watch-checks.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"

# The three argvs a row can script, one per response column. Spelled here rather
# than per row: a row that mistyped a URL would stub an argv the script never
# calls, the call it did make would be reported as an unstubbed argv, and the
# diagnosis would point at the script instead of at the row.
#
# DEFAULT_CHECKS_ENDPOINT deliberately spells `trunk` — the default_branch the
# repo-default-branch fixture carries — rather than `main` or `master`. The stub
# matches on the exact argv, so a script that assumed a default branch name
# instead of reading the field would call an argv no row stubbed, and
# check_no_violations reports it. Spelled as a real branch name here, the
# assertion is free.
CHECKS_ENDPOINT='repos/acme/widgets/commits/deadbeef/check-runs'
REPO_ENDPOINT='repos/acme/widgets'
DEFAULT_CHECKS_ENDPOINT='repos/acme/widgets/commits/trunk/check-runs'

# Registers one response for one endpoint. `spec` is <index>=<fixture>[:<status>],
# where <index> is a positive integer or `*` and <fixture> is `-` for an empty
# body — the spelling request-copilot-review_test.sh:122 already uses.
stub_api() {
  local endpoint="$1" spec="$2" idx rest fixture status body
  idx="${spec%%=*}"
  rest="${spec#*=}"
  fixture="${rest%%:*}"
  status=0
  case "$rest" in *:*) status="${rest##*:}" ;; esac
  body=/dev/null
  if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
  gh_stub_response "$idx" "$status" api "$endpoint" <"$body"
}

# One response column: `-` for "this row never stubs that endpoint".
stub_column() {
  local endpoint="$1" column="$2" spec
  local specs
  [ "$column" != '-' ] || return 0
  IFS=';' read -ra specs <<<"$column"
  for spec in "${specs[@]}"; do stub_api "$endpoint" "$spec"; done
}

failed=0
total=0

while IFS='|' read -r name checks repo default_checks args want_exit want_calls want_out; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  # A row's three columns share one global call counter, which is what lets it
  # say "call 4 is the repo read" while the poll's own calls stay on `*`. The
  # stub matches `*` per argv rather than globally, so a `*` on the poll cannot
  # answer the repo read and mask a wrong URL.
  stub_column "$CHECKS_ENDPOINT" "$checks"
  stub_column "$REPO_ENDPOINT" "$repo"
  stub_column "$DEFAULT_CHECKS_ENDPOINT" "$default_checks"

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
# name|checks|repo|default-checks|args|exit|calls|stdout
settled-prints-rows|*=check-runs-settled|-|-|acme widgets deadbeef 1 1|0|1|build\tcompleted\tsuccess\nlint\tcompleted\tskipped\n
name-that-looks-unsettled-still-settles|*=check-runs-name-looks-unsettled|-|-|acme widgets deadbeef 1 1|0|1|e2e (in_progress shard)\tcompleted\tsuccess\nqueued-jobs monitor\tcompleted\tsuccess\n
unsettled-then-settled|1=check-runs-in-progress;*=check-runs-settled|-|-|acme widgets deadbeef 3 1|0|2|build\tcompleted\tsuccess\nlint\tcompleted\tskipped\n
still-unsettled-at-cap|*=check-runs-in-progress|-|-|acme widgets deadbeef 2 1|1|2|build\tin_progress\t-\n
empty-listing-prints-nothing|*=check-runs-empty|-|-|acme widgets deadbeef 1 1|1|1|
missing-commit|*=no-commit-for-sha|-|-|acme widgets deadbeef 3 1|3|1|
error-body-every-poll|*=not-found|-|-|acme widgets deadbeef 2 1|4|2|
gh-fails-every-poll|*=-:1|-|-|acme widgets deadbeef 1 1|4|1|
too-few-args|*=check-runs-settled|-|-|acme widgets|2|0|
too-many-args|*=check-runs-settled|-|-|acme widgets deadbeef 1 1 extra|2|0|
non-numeric-max-iterations|*=check-runs-settled|-|-|acme widgets deadbeef abc 1|2|0|
zero-max-iterations|*=check-runs-settled|-|-|acme widgets deadbeef 0 1|2|0|
fractional-max-iterations|*=check-runs-settled|-|-|acme widgets deadbeef 1.5 1|2|0|
non-numeric-interval|*=check-runs-in-progress|-|-|acme widgets deadbeef 2 xyz|2|0|
ROWS

harness_exit "$failed" "$total"
