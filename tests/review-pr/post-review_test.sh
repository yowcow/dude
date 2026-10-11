#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/post-review.sh: each of the three
# choices posts exactly its own review -- APPROVE and COMMENT submitted, PENDING
# left unsubmitted by omitting `event` -- anchored to the reviewed head by
# commit_id; no choice, or a request for changes, posts nothing.
#
# The payload reaches gh on stdin (`--input -`), outside the argv the stub
# matches on, so each posting row also compares those bytes (check_gh_stdin).
# The response is raw, so the SUT's own --jq runs.
#
# RED verification (see tests/README.md): sending `event` for PENDING fails
# 'draft only' on its payload; dropping commit_id fails all three payloads;
# accepting any event fails 'request changes' and 'no choice' on gh calls.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/post-review.sh}"

failed=0
total=0

HEAD_SHA='c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ff'
URL='https://github.com/acme/widgets/pull/12#pullrequestreview-1'
POST_JQ='"POSTED \(.state) \(.html_url)"'

PAYLOAD="${HARNESS_TMP}/payload.json"
printf '%s\n' '{"body":"Summary.","comments":[{"path":"a.txt","line":3,"side":"RIGHT","body":"Important: x"}]}' >"$PAYLOAD"
NOTJSON="${HARNESS_TMP}/notjson.json"
printf 'not json\n' >"$NOTJSON"

# want_stdin <event-or-empty>   the exact bytes gh must read on stdin
want_stdin() {
  local event_part=''
  if [ -n "$1" ]; then event_part=",\"event\":\"$1\""; fi
  printf '{"commit_id":"%s","body":"Summary.","comments":[{"path":"a.txt","line":3,"side":"RIGHT","body":"Important: x"}]%s}\n' \
    "$HEAD_SHA" "$event_part" >"${HARNESS_TMP}/want-stdin"
}

# stub_post <exit-status>   raw response body on stdin
stub_post() {
  gh_stub_raw_response 1 "$1" api --method POST repos/acme/widgets/pulls/12/reviews --input - --jq "$POST_JQ"
}

row_start
printf '{"state":"APPROVED","html_url":"%s"}\n' "$URL" | stub_post 0
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" APPROVE "$PAYLOAD"
assert_row 'approve' 0 "POSTED APPROVED ${URL}\n" 1
want_stdin APPROVE
tally check_gh_stdin 'approve: payload' 1 "${HARNESS_TMP}/want-stdin"

row_start
printf '{"state":"COMMENTED","html_url":"%s"}\n' "$URL" | stub_post 0
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" COMMENT "$PAYLOAD"
assert_row 'comment only' 0 "POSTED COMMENTED ${URL}\n" 1
want_stdin COMMENT
tally check_gh_stdin 'comment only: payload' 1 "${HARNESS_TMP}/want-stdin"

row_start
printf '{"state":"PENDING","html_url":"%s"}\n' "$URL" | stub_post 0
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" PENDING "$PAYLOAD"
assert_row 'draft only' 0 "POSTED PENDING ${URL}\n" 1
want_stdin ''
tally check_gh_stdin 'draft only: payload' 1 "${HARNESS_TMP}/want-stdin"

row_start
printf '{"message":"Unprocessable Entity"}\n' | stub_post 1
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" COMMENT "$PAYLOAD"
assert_row 'post fails' 0 'STOP review-post-failed\n' 1

# The stub is in place and must not be reached.
row_start
printf '{"state":"CHANGES_REQUESTED","html_url":"%s"}\n' "$URL" | stub_post 0
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" REQUEST_CHANGES "$PAYLOAD"
assert_row 'request changes' 2 '' 0

row_start
printf '{"state":"COMMENTED","html_url":"%s"}\n' "$URL" | stub_post 0
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" '' "$PAYLOAD"
assert_row 'no choice' 2 '' 0

row_start
run_sut bash "$SUT" acme widgets abc "$HEAD_SHA" COMMENT "$PAYLOAD"
assert_row 'non-numeric pr' 2 '' 0

row_start
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" COMMENT "${HARNESS_TMP}/no-such-payload.json"
assert_row 'missing payload' 2 '' 0

row_start
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" COMMENT "$NOTJSON"
assert_row 'payload not json' 2 '' 0

row_start
run_sut bash "$SUT" acme widgets 12 "$HEAD_SHA" COMMENT
assert_row 'too few arguments' 2 '' 0

harness_exit "$failed" "$total"
