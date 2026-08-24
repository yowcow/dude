#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/resolve-thread.sh: each row is a
# page sequence for the one paginated lookup plus the mutations that follow it,
# against the exit status, the number of responses served, and the exact bytes
# on stdout.
#
# What the rows are built to pin:
#
# 1. The lookup happens ONCE for the whole batch. `batch-three-ids` passes three
#    comment ids and expects 4 responses — one lookup page and three mutations.
#    A per-id lookup would serve 6.
# 2. The snapshot spans every page. `two-pages` resolves a comment id that only
#    appears on page 2; `second-page-missing` asks for that same id with page 2
#    not served and gets "not found" instead. The pair is what gives the paging
#    row its detection power: the same id, one page apart, two answers.
# 3. A thread is identified by ANY of its indexed comments —
#    `later-comment-of-thread` resolves 4011, the second comment of PRRT_a, to
#    the same thread as 4001.
# 4. The index is `comments(first: 50)`, and the header says a comment id beyond
#    it will not match. `comment-at-index-fifty` (id 50, resolves) and
#    `comment-beyond-first-fifty` (id 51, not found) are the same fixture on
#    either side of that boundary.
# 5. A failing mutation is not a success. `mutation-denied` expects exit 1 where
#    gh exited 4, and `mutation-denied-then-ok` expects the batch to carry on to
#    the second id — 3 responses, not 2.
# 6. An invalid argv costs zero API calls. The three usage rows stub NOTHING, so
#    a call would be both an unstubbed-argv violation and a count mismatch.
#
# The rows also pin that a comment id the snapshot does not carry
# (`unknown-comment-id`) and a lookup that failed (`lookup-fails`) are BOTH
# non-zero. That pair is deliberate: unlike list-unresolved-threads.sh, where
# "no unresolved thread" and "could not ask" had to be told apart because one of
# them is a success, here both mean "this thread was not resolved" and both are
# a failure. They differ only in stderr, which this file does not assert.
#
# The lookup fixtures are raw GraphQL response bodies, so the script's own --jq
# (`...nodes[]`, the node stream the snapshot depends on) really runs. The
# mutation fixtures are gh's stdout: that call carries no --jq, and the script
# does not redirect it, so the response body IS the script's stdout — which is
# why the stdout column names those same fixtures.
#
# The query, the mutation and the --jq expression below are byte-identical
# copies of what the script passes, because the stub matches the exact argv.
# That is deliberate change control: editing one in the script without editing
# it here fails these rows as an unstubbed argv.
#
# RED verification — see tests/README.md:
#   tmp="$(mktemp -d)"
#   git show 8cd2953^:skills/pr-to-ready/scripts/resolve-thread.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/resolve-thread_test.sh
# The mutation rows fail: at 8cd2953^ the mutation was not wrapped in `if !`, so
# `set -e` ended the run at the first failure — `mutation-denied` exits with
# gh's 4 instead of 1, and `mutation-denied-then-ok` serves 2 responses instead
# of 3 because the second id is never reached. Measured: those two rows and no
# others.
#
#   git show a05a84f^:skills/pr-to-ready/scripts/resolve-thread.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/resolve-thread_test.sh
# a05a84f is where --paginate, `$endCursor` and the `nodes[]` --jq landed, so at
# a05a84f^ the lookup argv is a different one and every row that reaches the API
# fails as an unstubbed argv — measured 15 of 18, `two-pages` included, the
# three usage rows passing because they never call gh. That is change control
# rather than paging-specific detection, and it is why property 2 above carries
# `second-page-missing`: that pair fails on the answer, at the same argv.
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/resolve-thread.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

OWNER='acme'
REPO='widgets'
PR='7'

# Byte-identical to resolve-thread.sh's lookup `-f query='...'`, indentation and
# leading newline included.
QUERY='
    query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              comments(first: 50) {
                nodes { databaseId }
              }
            }
          }
        }
      }
    }'
JQ='.data.repository.pullRequest.reviewThreads.nodes[]'

# Byte-identical to resolve-thread.sh's mutation `-f query='...'`.
MUTATION='
      mutation($threadId: ID!) {
        resolveReviewThread(input: { threadId: $threadId }) {
          thread { isResolved }
        }
      }'

failed=0
total=0

while IFS='|' read -r name pages mutations args want_exit want_calls want_files; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  # Indices 1..P are the pages of the single --paginate lookup; the mutations
  # that follow take P+1 onward. The stub filters by exact argv before index, so
  # the lookup's probe for index P+1 sees the mutation's argv, does not match,
  # and ends the page sequence without advancing the counter.
  i=1
  if [ "$pages" != '-' ]; then
    IFS=',' read -ra page_seq <<<"$pages"
    for entry in "${page_seq[@]}"; do
      fixture="${entry%%:*}"
      status=0
      case "$entry" in *:*) status="${entry##*:}" ;; esac
      gh_stub_raw_response "$i" "$status" \
        api graphql --paginate \
        -f "owner=${OWNER}" -f "repo=${REPO}" -F "pr=${PR}" \
        -f "query=${QUERY}" --jq "$JQ" \
        <"${HERE}/fixtures/${fixture}.json"
      i=$((i + 1))
    done
  fi

  if [ "$mutations" != '-' ]; then
    IFS=',' read -ra mut_seq <<<"$mutations"
    for entry in "${mut_seq[@]}"; do
      thread="${entry%%:*}"
      status=0
      body=resolve-thread-ok
      case "$entry" in
        *:*)
          status="${entry##*:}"
          body=resolve-thread-denied
          ;;
      esac
      gh_stub_response "$i" "$status" \
        api graphql -f "threadId=${thread}" -f "query=${MUTATION}" \
        <"${HERE}/fixtures/${body}.json"
      i=$((i + 1))
    done
  fi

  # `${argv[@]+...}` because a row with no arguments leaves the array empty, and
  # a bare "${argv[@]}" is an unbound-variable error under `set -u` on bash 3.2.
  argv=()
  if [ "$args" != '-' ]; then read -ra argv <<<"$args"; fi
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}

  want_paths=()
  if [ "$want_files" = '-' ]; then
    want_paths=(/dev/null)
  else
    IFS='+' read -ra want_list <<<"$want_files"
    for p in "${want_list[@]}"; do want_paths+=("${HERE}/${p}"); done
  fi

  fails_here=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh responses" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_stdout_files "${name}: stdout" "${want_paths[@]}"; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|pages|mutations|args|exit|calls|stdout
single-id|resolve-thread-single|PRRT_a|acme widgets 7 4001|0|2|fixtures/resolve-thread-ok.json
later-comment-of-thread|resolve-thread-single|PRRT_a|acme widgets 7 4011|0|2|fixtures/resolve-thread-ok.json
batch-three-ids|resolve-thread-single|PRRT_a,PRRT_b,PRRT_c|acme widgets 7 4001 4002 4003|0|4|fixtures/resolve-thread-ok.json+fixtures/resolve-thread-ok.json+fixtures/resolve-thread-ok.json
unknown-comment-id|resolve-thread-single|-|acme widgets 7 9999|1|1|-
batch-with-one-unknown|resolve-thread-single|PRRT_a,PRRT_b|acme widgets 7 4001 9999 4002|1|3|fixtures/resolve-thread-ok.json+fixtures/resolve-thread-ok.json
comment-at-index-fifty|resolve-thread-fifty|PRRT_fifty|acme widgets 7 50|0|2|fixtures/resolve-thread-ok.json
comment-beyond-first-fifty|resolve-thread-fifty|-|acme widgets 7 51|1|1|-
non-integer-id|resolve-thread-single|-|acme widgets 7 abc|1|1|-
non-integer-among-valid|resolve-thread-single|PRRT_a,PRRT_b|acme widgets 7 4001 not-a-number 4002|1|3|fixtures/resolve-thread-ok.json+fixtures/resolve-thread-ok.json
mutation-denied|resolve-thread-single|PRRT_a:4|acme widgets 7 4001|1|2|fixtures/resolve-thread-denied.json
mutation-denied-then-ok|resolve-thread-single|PRRT_a:4,PRRT_b|acme widgets 7 4001 4002|1|3|fixtures/resolve-thread-denied.json+fixtures/resolve-thread-ok.json
two-pages|resolve-thread-page1,resolve-thread-page2|PRRT_p2a|acme widgets 7 4102|0|3|fixtures/resolve-thread-ok.json
second-page-missing|resolve-thread-page1|-|acme widgets 7 4102|1|1|-
lookup-fails|graphql-errors:1|-|acme widgets 7 4001|1|1|-
lookup-fails-midway|resolve-thread-page1,graphql-errors:1|-|acme widgets 7 4101|1|2|-
too-few-args|-|-|acme widgets 7|1|0|-
two-args|-|-|acme widgets|1|0|-
no-args|-|-|-|1|0|-
ROWS

harness_exit "$failed" "$total"
