#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/request-copilot-review.sh: each
# row scripts the timeline reads by global call index, against the exit status,
# the number of `gh` calls, the number of sleeps, and the exact bytes on stdout.
#
# The bodies are raw, registered with gh_stub_raw_response, so the script's own
# --jq really runs: it is what turns a timeline into a count, and a pre-counted
# fixture would state the answer instead of the input. The stub applies it once
# per page, which is why a paginated read is summed by `awk` in the script and
# why the pagination row below can put the Copilot event on page 2 alone.
#
# The three argvs are fixed and named below. EDIT and POST carry one `*` entry
# each — the stub matches `*` per argv, not globally — while TIMELINE carries
# exact indices, because *which* read sees the event is the whole subject.
#
# EDIT's and POST's exit statuses come from the row's `forms` column, and three
# rows set them non-zero. That column is not decoration: the script wraps both
# calls in `|| true` and its header rests the claim "no gh call reaches exit
# other" on exactly that. Stub both at 0 everywhere and the claim is untested —
# measured, with the flag form's `|| true` deleted, all 14 rows of the previous
# revision still passed. `flag-form-fails-and-the-rest-form-takes` covers the
# first guard, `rest-form-fails-and-the-event-is-still-read` the second, and
# `neither-form-lands-and-both-forms-failed` shows that two failed requests
# still produce exit 3 — the documented answer — rather than a leaked status.
#
# The index map, with the readback budget shared by the two forms — two reads
# after the flag, three after the REST form — and every TIMELINE call serving
# one page:
#
#   1            TIMELINE, the baseline, taken before any request is sent
#   2            EDIT
#   3..4         TIMELINE readback tries 1-2 after EDIT
#   5            POST
#   6..8         TIMELINE readback tries 3-5, the remainder of one shared budget
#
# `landed()` sleeps between tries but not after the last, so a flag readback
# that runs out costs 1 sleep and the REST form's 2. A run that lands nothing
# therefore costs 8 gh calls — 6 timeline reads and 2 writes — and 3 sleeps,
# against 13 calls and 8 sleeps when each form had its own five tries. That is
# why `neither-form-lands`'s call count is the fetch-count assertion, and what
# makes the pre-yowcow/dude#686 script red on it.
#
# TIMELINE carries --paginate, so successive indices on it are the PAGES of one
# invocation, not successive invocations. Three measured rules govern when a call
# stops, and every row's call count follows from them:
#
#   R1  a `*` match serves one page and halts — so such a call costs exactly 1.
#   R2  an exact match does NOT halt: it probes index+1 on the same argv. Another
#       exact entry there is served as the next page; a `*` entry there is served
#       as one extra page and then halts; nothing there halts at index.
#   R3  a gap is safe only mid-invocation. A *fresh* invocation whose own index
#       matches nothing is a violation, not a clean stop.
#
# Two consequences worth stating, because each one costs a row when missed. An
# exact index sitting above a `*` costs one EXTRA call (R2) — which is why
# `rest-form-takes` is 7 and not 6. And exact-index-only rows cannot express a
# mid-readback landing (R2 swallows index 4 as page 2; a gap makes try 2 an R3
# violation), so a row that lands on the second poll takes a `*` default, which
# halts try 1's invocation. `flag-takes-on-second-readback` is that row, and it
# is what makes a 1/4 split fail: without it the suite pins the five-read total
# but not the two/three split the script gives the forms.
#
# R2 is also what makes `paginated-page-lengths-are-summed` possible at all: the
# two pages of one readback are indices 3 and 4. Its BASELINE is the load-bearing
# part, and it is 1 rather than 0 on purpose. The script sums the per-page
# lengths, because --jq runs once per page; the defect it guards against is
# reading one page's number as the whole answer. With a baseline of 0 that defect
# is invisible — pages of 1 and 1 sum to 2, a single page reads as 1, and both
# clear 0, so the row passes either way. Measured: with the script's `awk` sum
# replaced by a last-value-only `awk`, a 0-baseline version of this row still
# reported ok while two other rows failed. A baseline of 1 puts the threshold
# between the two answers — 2 lands, 1 does not — so the wrong reading exhausts
# the readback and reaches index 5, which no entry answers, and the row fails
# loudly on the violation (R3).
#
# THE SUCCESS IS READ FROM THE TIMELINE, NEVER FROM requested_reviewers. Copilot
# is a Bot and never appears in GET .../requested_reviewers — keyed on that
# endpoint this script reported Copilot permanently unavailable while requesting
# the review successfully every time (#167). The `check_no_violations` on every
# row is what holds that: the GET argv is stubbed by no row, so a script that
# read it would be reported as calling an argv no case stubbed. Note that this
# is not the same argv as POST below, which is a write and is stubbed.
#
# Which is also how the two causes of exit 3 stay apart. A true absence — the
# Copilot quota is exhausted, so nothing lands — is `neither-form-lands`, where
# the timeline genuinely never carries the event. A read-side defect is the
# opposite shape: the event is on the timeline and a reader looking at the wrong
# surface misses it. `flag-takes` and `rest-form-takes` are that case, and they
# exit 0. In production a requested_reviewers-keyed reader collapses both to
# exit 3, since that endpoint answers "absent" for either — that is the #167
# defect, and it is why the two need separate rows here.
#
# The RED below does NOT reproduce that collapse, and expecting exit 3 from it
# would be a wasted hour: this suite stubs no GET of that endpoint, so the old
# script's readback hits an unstubbed argv, the fake gh exits 99, and the old
# script's own error path returns 4 before it can answer "absent" at all.
# Measured: the three exit-3 rows all report `want [3], got [4]`. What the RED
# demonstrates is the script asking the wrong surface — which is the defect —
# not the answer that surface would have given.
#
# RED verification — the pre-#167 version read requested_reviewers, so it never
# issues the TIMELINE argv at all. See tests/README.md.
#   tmp="$(mktemp -d)"
#   git show 1245a06^:skills/pr-to-ready/scripts/request-copilot-review.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/request-copilot-review_test.sh
#
# RED verification — the pre-yowcow/dude#686 version read the timeline eleven
# times per request, so these rows fail.
#   tmp="$(mktemp -d)"
#   git show d45deb2:skills/pr-to-ready/scripts/request-copilot-review.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/request-copilot-review_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

stub_sleep_instant

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/request-copilot-review.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"

# A verbatim copy of the `--jq` argument in `count_requests` in
# request-copilot-review.sh, including its 11-space continuation indent and the
# 10-space closing line. It is one argv element spanning four lines, matched on
# its exact bytes: an edit to the filter there fails every row here as an
# unstubbed argv rather than quietly.
JQ_FILTER='[.[]
           | select(.event == "review_requested")
           | select((.requested_reviewer.login // "") | ascii_downcase | contains("copilot"))
          ] | length'

# Registers one timeline entry. `spec` is <index>=<fixture>[:<status>], where
# <index> is a positive integer or `*` and <fixture> is `-` for an empty body.
stub_timeline() {
  local spec="$1" idx rest fixture status body
  idx="${spec%%=*}"
  rest="${spec#*=}"
  fixture="${rest%%:*}"
  status=0
  case "$rest" in *:*) status="${rest##*:}" ;; esac
  body=/dev/null
  if [ "$fixture" != '-' ]; then body="${FIXTURES}/${fixture}.json"; fi
  gh_stub_raw_response "$idx" "$status" \
    api "repos/acme/widgets/issues/7/timeline?per_page=100" --paginate --jq "$JQ_FILTER" <"$body"
}

failed=0
total=0

while IFS='|' read -r name timeline forms args want_exit want_calls want_sleeps; do
  case "$name" in '' | '#'*) continue ;; esac
  row_start

  # Both request forms answer every call: which of them produced the event does
  # not matter to the script, and their status is discarded on purpose. Their
  # stdout is dropped by the script, so an empty body served verbatim is the
  # honest fixture and gh_stub_response is the right helper for them.
  #
  # `forms` is <edit-status>,<post-status>, and it exists so those statuses can
  # be non-zero. The script guards both calls with `|| true` and documents that
  # as the reason its exit "other" is unreachable; with every row stubbing 0,
  # nothing held that. Measured: with the `|| true` removed from the flag form,
  # all 14 rows of the previous revision still passed.
  edit_status="${forms%%,*}"
  post_status="${forms##*,}"
  gh_stub_response '*' "$edit_status" pr edit 7 --repo acme/widgets --add-reviewer '@copilot' </dev/null
  gh_stub_response '*' "$post_status" api --method POST repos/acme/widgets/pulls/7/requested_reviewers \
    -f 'reviewers[]=copilot-pull-request-reviewer[bot]' </dev/null

  if [ "$timeline" != '-' ]; then
    IFS=';' read -ra specs <<<"$timeline"
    for spec in "${specs[@]}"; do stub_timeline "$spec"; done
  fi

  fails_here=0
  read -ra argv <<<"$args"
  run_sut bash "$SUT" "${argv[@]}"

  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_eq "${name}: sleeps" "$want_sleeps" "$(sleep_call_count)"; then fails_here=1; fi
  # Sleeps are instant here, so only their duration can see a change to the
  # interval the header's window numbers come from.
  if [ "$want_sleeps" -gt 0 ] && ! check_eq "${name}: sleep duration" 5 "$(sort -u "${GH_STUB_DIR}/sleeps")"; then fails_here=1; fi
  # Nothing this script prints goes to stdout — both request forms have theirs
  # dropped, and every diagnostic is on stderr. Asserted rather than left
  # unstated: a stray print would be the caller's parse breaking.
  if ! check_bytes "${name}: stdout" ""; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|timeline|forms|args|exit|calls|sleeps
flag-takes|1=timeline-empty;3=timeline-copilot-once|0,0|acme widgets 7|0|3|0
flag-takes-bot-suffix-spelling|1=timeline-empty;3=timeline-copilot-bot-suffix|0,0|acme widgets 7|0|3|0
flag-takes-on-second-readback|*=timeline-empty;4=timeline-copilot-once|0,0|acme widgets 7|0|5|1
rest-form-takes|*=timeline-empty;6=timeline-copilot-once|0,0|acme widgets 7|0|7|1
lands-on-the-final-readback-try|*=timeline-empty;8=timeline-copilot-once|0,0|acme widgets 7|0|9|3
flag-form-fails-and-the-rest-form-takes|*=timeline-empty;6=timeline-copilot-once|1,0|acme widgets 7|0|7|1
rest-form-fails-and-the-event-is-still-read|*=timeline-empty;6=timeline-copilot-once|0,1|acme widgets 7|0|7|1
neither-form-lands|*=timeline-empty|0,0|acme widgets 7|3|8|3
neither-form-lands-and-both-forms-failed|*=timeline-empty|1,1|acme widgets 7|3|8|3
non-copilot-events-do-not-count|*=timeline-no-copilot|0,0|acme widgets 7|3|8|3
previous-round-event-is-not-this-round|*=timeline-copilot-once|0,0|acme widgets 7|3|8|3
previous-round-event-plus-a-new-one|1=timeline-copilot-once;3=timeline-copilot-twice|0,0|acme widgets 7|0|3|0
team-request-event-does-not-abort-the-filter|1=timeline-team-only;3=timeline-team-and-copilot|0,0|acme widgets 7|0|3|0
paginated-page-lengths-are-summed|1=timeline-copilot-once;3=timeline-page1;4=timeline-page2|0,0|acme widgets 7|0|4|0
rest-readback-timeline-unreadable|*=timeline-empty;6=not-found:1|0,0|acme widgets 7|4|6|1
baseline-timeline-unreadable|1=not-found:1|0,0|acme widgets 7|4|1|0
readback-timeline-unreadable|1=timeline-empty;3=not-found:1|0,0|acme widgets 7|4|3|0
too-few-args|-|0,0|acme widgets|2|0|0
too-many-args|-|0,0|acme widgets 7 extra|2|0|0
ROWS

harness_exit "$failed" "$total"
