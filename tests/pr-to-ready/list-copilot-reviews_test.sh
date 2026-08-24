#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/list-copilot-reviews.sh: each row
# is one `gh` response — a raw body plus an exit status — and an argv, against
# the exit status, the number of `gh` calls, and the exact bytes on stdout.
#
# The bodies are raw, registered with gh_stub_raw_response, because the --jq
# filter is the whole subject: identifying the reviewer is what this script
# exists to do, and a pre-filtered fixture would decide that for it. So the stub
# applies the script's own filter with `jq -r -c -S`, and the expected bytes are
# in gojq's sorted-key order, which is what real gh emits.
#
# Two properties the rows are built around.
#
# The bot's login differs across GitHub's surfaces — the review surface returns
# `Copilot`, the reviewer-request surface `copilot-pull-request-reviewer[bot]` —
# so both spellings have their own row, and the bare one carries a capital C so
# the `ascii_downcase` is pinned rather than incidental.
#
# Empty stdout is not an answer on its own: a failing `gh` call prints nothing on
# stdout either. `no-reviews-at-all` and `gh-call-fails` are the pair that holds
# those apart, and they differ only in the exit status.
#
# RED verification — this script has no usable pre-fix version (it is touched by
# 1245a06, but that diff to this file is a single comment line and changes no
# behaviour), so detection power is shown by removing one guard the header names:
# the `// ""` in the select on line 42.
#
# The same sed has to hit THIS file too. The filter is part of the argv the stub
# matches byte for byte, so mutating only the script makes its call unstubbed and
# every gh-reaching row fails alike — which pins the filter text but says nothing
# about which guard went. Mutating JQ_FILTER by the same expression restores the
# match, so the mutated filter runs and only the row whose fixture trips it fails.
# The verbatim copy below is what lets one expression serve both files.
#
# The copy must live in tests/pr-to-ready/ — it sources ../lib/harness.sh off
# its own dirname — and must be removed afterwards, since lint.sh selects by
# shebang and run.sh collects *_test.sh. See tests/README.md.
#   tmp="$(mktemp -d)"
#   MUT='s/(\.author\.login \/\/ "") | ascii_downcase/(.author.login) | ascii_downcase/'
#   sed "$MUT" skills/pr-to-ready/scripts/list-copilot-reviews.sh >"$tmp/mut.sh"
#   sed "$MUT" tests/pr-to-ready/list-copilot-reviews_test.sh >tests/pr-to-ready/mut_test.sh
#   SUT="$tmp/mut.sh" tests/run.sh tests/pr-to-ready/mut_test.sh
#   rm tests/pr-to-ready/mut_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/list-copilot-reviews.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"

# A verbatim copy of the --jq argument in list-copilot-reviews.sh:41-43,
# including its eight-space continuation indent. It is one argv element that
# spans three lines, and the stub matches on its exact bytes: an edit to the
# filter there fails every row here as an unstubbed argv rather than passing
# quietly.
JQ_FILTER='.reviews[]
        | select((.author.login // "") | ascii_downcase | contains("copilot"))
        | {id, author: (.author.login // ""), state, submittedAt}'

failed=0
total=0

while IFS='|' read -r name fixture status args want_exit want_calls want_out; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  body=/dev/null
  if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
  gh_stub_raw_response '*' "$status" \
    pr view 7 --repo acme/widgets --json reviews --jq "$JQ_FILTER" <"$body"

  fails_here=0
  read -ra argv <<<"$args"
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
# name|fixture|gh-status|args|exit|calls|stdout
bot-suffix-login-identified|reviews-bot-suffix|0|acme widgets 7|0|1|{"author":"copilot-pull-request-reviewer[bot]","id":"PRR_kwDOAZjEl88AAAABKNbcig","state":"COMMENTED","submittedAt":"2026-08-20T07:29:15Z"}\n
bare-copilot-login-identified|reviews-bare-copilot|0|acme widgets 7|0|1|{"author":"Copilot","id":"PRR_kwDOAZjEl88AAAABKNnbbA","state":"APPROVED","submittedAt":"2026-08-20T07:54:06Z"}\n
both-spellings-on-one-pr|reviews-both-spellings|0|acme widgets 7|0|1|{"author":"Copilot","id":"PRR_kwDOAZjEl88AAAABKNbcig","state":"COMMENTED","submittedAt":"2026-08-20T07:29:15Z"}\n{"author":"copilot-pull-request-reviewer[bot]","id":"PRR_kwDOAZjEl88AAAABKNnbbA","state":"COMMENTED","submittedAt":"2026-08-20T07:54:06Z"}\n
humans-and-deleted-author-skipped|reviews-humans-and-null-author|0|acme widgets 7|0|1|{"author":"copilot-pull-request-reviewer[bot]","id":"PRR_kwDOAZjEl88AAAABKNbcig","state":"CHANGES_REQUESTED","submittedAt":"2026-08-20T07:29:15Z"}\n
no-reviews-at-all|reviews-empty|0|acme widgets 7|0|1|
gh-call-fails|not-found|1|acme widgets 7|1|1|{\n  "message": "Not Found",\n  "documentation_url": "https://docs.github.com/rest",\n  "status": "404"\n}\n
too-few-args|reviews-both-spellings|0|acme widgets|2|0|
too-many-args|reviews-both-spellings|0|acme widgets 7 extra|2|0|
ROWS

harness_exit "$failed" "$total"
