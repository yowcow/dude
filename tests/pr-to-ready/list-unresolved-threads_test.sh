#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/list-unresolved-threads.sh: each
# row is a sequence of `gh` page responses against the exit status, the number of
# responses served, and the exact bytes on stdout.
#
# What the rows are built to pin is #169: empty stdout alone never means "no
# unresolved thread". The `no-response` row and the `zero-unresolved` row print
# the same zero bytes and differ only in exit status, and the two error rows
# print non-empty bytes that are not thread JSON. Neither emptiness nor
# non-emptiness carries the answer — the exit status does.
#
# The fixtures are raw GraphQL response bodies, not pre-filtered output: the
# stub applies the script's own --jq, so `select(.isResolved == false)` really
# runs. The expected files are hand-written, so a wrong filter cannot bake
# itself into its own expectation.
#
# The fixtures still carry a `body` on every comment, which the query no longer
# asks for. That is deliberate rather than stale: the expected files show the
# projection dropping it, so a --jq that went back to printing whole nodes fails
# here on bytes rather than passing unnoticed.
#
# The query and the --jq expression below are byte-identical copies of what the
# script passes, because the stub matches the exact argv. That is deliberate
# change control: editing the query in the script without editing it here fails
# these rows as an unstubbed argv, which is the review this file is here to
# force. What it cannot check is the query's meaning — the server is not here.
#
# RED verification (the projected expectations must fail against the pre-
# projection script, which printed whole thread nodes) -- see tests/README.md:
#   tmp="$(mktemp -d)"
#   git show 0c685b4:skills/pr-to-ready/scripts/list-unresolved-threads.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/list-unresolved-threads_test.sh
# It fails on the unstubbed argv as well as on stdout: the byte-identical QUERY
# and JQ copies below are what make the old script unable to reach a stub at all.
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/list-unresolved-threads.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

OWNER='acme'
REPO='widgets'
PR='7'

# Byte-identical to list-unresolved-threads.sh's `-f query='...'`, indentation
# and leading newline included.
QUERY='
    query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              isResolved
              comments(first: 1) {
                nodes {
                  databaseId
                  author { login }
                  path
                  line
                }
              }
            }
          }
        }
      }
    }'
JQ='.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | .comments.nodes[0] as $c
        | "\(.id)\t\($c.databaseId)\t\($c.author.login)\t\($c.path):\($c.line)"'

failed=0
total=0

while IFS='|' read -r name responses args want_exit want_calls want_files; do
  case "$name" in '' | '#'*) continue ;; esac
  total=$((total + 1))
  stub_dir_new

  # Each entry is one page of the single --paginate invocation, in order:
  # `<fixture>[:<exit-status>]`, with `-` for an empty body. The usage rows stub
  # a page too; they never reach the API, so nothing consults it.
  IFS=',' read -ra resp_seq <<<"$responses"
  i=1
  for entry in "${resp_seq[@]}"; do
    fixture="${entry%%:*}"
    status=0
    case "$entry" in *:*) status="${entry##*:}" ;; esac
    body=/dev/null
    if [ "$fixture" != '-' ]; then body="${HERE}/fixtures/${fixture}.json"; fi
    gh_stub_raw_response "$i" "$status" \
      api graphql --paginate \
      -f "owner=${OWNER}" -f "repo=${REPO}" -F "pr=${PR}" \
      -f "query=${QUERY}" --jq "$JQ" <"$body"
    i=$((i + 1))
  done

  # `${argv[@]+...}` because a row with no arguments leaves the array empty, and
  # a bare "${argv[@]}" is an unbound-variable error under `set -u` on bash 3.2.
  read -ra argv <<<"$args"
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}

  # `-` means nothing on stdout; otherwise the expectation is the named files
  # concatenated, relative to this directory.
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
# name|responses|args|exit|calls|stdout
unresolved-present|threads-one-unresolved|acme widgets 7|0|1|expected/one-unresolved.out
zero-unresolved|threads-all-resolved|acme widgets 7|0|1|-
no-response|-:1|acme widgets 7|1|1|-
errors-in-a-200|graphql-errors:1|acme widgets 7|1|1|fixtures/graphql-errors.json
auth-failure|bad-credentials:1|acme widgets 7|1|1|fixtures/bad-credentials.json
two-pages|threads-page1,threads-page2|acme widgets 7|0|2|expected/page1.out+expected/page2.out
failure-midway-through-paging|threads-page1,graphql-errors:1|acme widgets 7|1|2|expected/page1.out+fixtures/graphql-errors.json
too-few-args|threads-all-resolved|acme widgets|2|0|-
too-many-args|threads-all-resolved|acme widgets 7 extra|2|0|-
no-args|threads-all-resolved||2|0|-
ROWS

harness_exit "$failed" "$total"
