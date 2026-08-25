#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/list-sub-issues.sh: the guards its
# header names — `--paginate` so a long split does not stop at the first page,
# and per_page in the **query string** rather than through `-F`, which would
# make gh send POST ("add a sub-issue") instead of listing.
#
# Both guards live in the argv, and the fake `gh` matches the argv byte for
# byte, so either mutation reaches an argv no case stubbed and every row that
# calls gh fails as a violation. That is the change control this file exists to
# force; what it cannot check is the endpoint's own behaviour.
#
# The pagination row is asserted by the **call counter**: with --paginate the
# stub serves successive indices as the pages of one invocation, so 105 children
# across two pages is `gh responses: 2` and 105 lines of stdout. A version that
# stopped at the first page would serve 1 and print 100.
#
# The fixtures are raw API bodies, so the script's own
# `--jq '.[] | {number, state, title}'` really runs: children-three.json carries
# its keys out of alphabetical order and an html_url the projection must drop,
# and the golden file is hand-written with the keys sorted, because gh filters
# through gojq and gojq sorts them.
#
# RED verification (see tests/README.md) — no usable pre-fix version exists,
# so detection power is shown by removing one named guard at a time:
#   tmp="$(mktemp -d)"
#   cp skills/plan-work/scripts/list-sub-issues.sh "$tmp/mut.sh"
#   # guard 1: drop --paginate     guard 2: send per_page through -F
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/list-sub-issues_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/list-sub-issues.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

OWNER=acme
REPO=widgets
PARENT=42
JQ='.[] | {number, state, title}'

failed=0
total=0

# stub_page <index> <body-file> <status>
stub_page() {
  gh_stub_raw_response "$1" "$3" \
    api --paginate "repos/${OWNER}/${REPO}/issues/${PARENT}/sub_issues?per_page=100" \
    --jq "$JQ" <"$2"
}

# assert_row <name> <want-exit> <want-calls> <want-file>...
assert_row() {
  local name="$1" want_exit="$2" want_calls="$3" fails=0
  shift 3
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${name}: gh responses" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_stdout_files "${name}: stdout" "$@"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# --- one page ---------------------------------------------------------------

total=$((total + 1))
stub_dir_new
stub_page 1 "${HERE}/fixtures/children-three.json" 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT"
assert_row three-children 0 1 "${HERE}/expected/children-three.out"

total=$((total + 1))
stub_dir_new
stub_page 1 "${HERE}/fixtures/children-empty.json" 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT"
assert_row no-children 0 1 /dev/null

# --- more than one page's worth ---------------------------------------------
#
# 105 children over two pages. The fixture pages and the expectation are built
# by two separate loops on purpose: an expectation produced by running the
# script's own filter would agree with any filter at all.

page1="${HARNESS_TMP}/page1.json"
page2="${HARNESS_TMP}/page2.json"
want105="${HARNESS_TMP}/want105.out"

build_page() {
  local out="$1" first="$2" last="$3" n sep=''
  : >"$out"
  printf '[' >>"$out"
  for ((n = first; n <= last; n++)); do
    printf '%s{"title": "item %d", "state": "open", "number": %d, "html_url": "https://example.invalid/%d"}' \
      "$sep" "$n" "$n" "$n" >>"$out"
    sep=','
  done
  printf ']\n' >>"$out"
}

build_want() {
  local out="$1" first="$2" last="$3" n
  : >"$out"
  for ((n = first; n <= last; n++)); do
    printf '{"number":%d,"state":"open","title":"item %d"}\n' "$n" "$n" >>"$out"
  done
}

build_page "$page1" 1 100
build_page "$page2" 101 105
build_want "$want105" 1 105
build_want "${HARNESS_TMP}/want100.out" 1 100

total=$((total + 1))
stub_dir_new
stub_page 1 "$page1" 0
stub_page 2 "$page2" 0
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT"
assert_row one-hundred-and-five-children 0 2 "$want105"

# --- a failure is not an empty listing --------------------------------------

total=$((total + 1))
stub_dir_new
stub_page 1 "${HERE}/fixtures/api-not-found.json" 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT"
assert_row gh-fails 1 1 "${HERE}/fixtures/api-not-found.json"

total=$((total + 1))
stub_dir_new
stub_page 1 "$page1" 0
stub_page 2 "${HERE}/fixtures/api-not-found.json" 1
run_sut bash "$SUT" "$OWNER" "$REPO" "$PARENT"
assert_row failure-midway-through-paging 1 2 \
  "${HARNESS_TMP}/want100.out" "${HERE}/fixtures/api-not-found.json"

# --- the argument guards run before any call --------------------------------

while IFS='|' read -r name args; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new
  read -ra argv <<<"$args"
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}
  assert_row "$name" 1 0 /dev/null
done <<'ROWS'
# name|args
no-args|
too-few-args|acme widgets
too-many-args|acme widgets 42 extra
parent-not-a-number|acme widgets HEAD
ROWS

harness_exit "$failed" "$total"
