#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/post-review.sh: the guard before the
# agent writes (a choice outside APPROVE, COMMENT, PENDING never reaches a
# write) and the read-back after it (the review record, read by its id, must
# be anchored to the reviewed head, in the state the choice asks for, with the
# body the payload carried). The script reads facts and origin only: every row
# asserts 0 gh calls, and stubs none.
#
# RED verification (see tests/README.md): against the pre-port script
# (`git show a7f4396:skills/review-pr/scripts/post-review.sh`) 25 of 35 rows
# fail, the guard, read-back and missing-jq rows, each on the old six-argument
# arity answering usage 2. The ten usage rows pass, 'request changes' and
# 'no choice' among them, since the old arity answers usage 2 for each.
# Mutants measured in a copy under `mktemp -d` (siblings beside it): dropping
# `review.commit=` from the check fails 'review pinned to another commit',
# 'commit unreadable' and 'no facts: NEED pins';
# mapping PENDING-with-APPROVE to `review-state-mismatch` fails 'submit
# failed'; dropping the body compare fails 'submitted with the body dropped',
# 'draft only, body not carried' and 'body read back differs'; comparing the
# bodies byte-exact (`cmp`) fails 'body read back with a trailing newline'.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/post-review.sh}"
BASH_BIN="$(command -v bash)"

failed=0
total=0

HEAD_SHA='c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ff'
OTHER_SHA='deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
URL='https://github.com/acme/widgets/pull/12#pullrequestreview-1'

WORK="$(git_repo_scratch work)"
git_repo_init "$WORK" main
git_repo_remote "$WORK" origin 'https://github.com/Acme/Widgets.git'
NOORIGIN="$(git_repo_scratch noorigin)"
git_repo_init "$NOORIGIN" main

PAYLOAD="${HARNESS_TMP}/payload.json"
printf '%s\n' '{"body":"Summary.","comments":[{"path":"a.txt","line":3,"side":"RIGHT","body":"Important: x"}]}' >"$PAYLOAD"
EMPTY="${HARNESS_TMP}/empty.json"
printf '%s\n' '{"body":"Summary.","comments":[]}' >"$EMPTY"
NOTJSON="${HARNESS_TMP}/notjson.json"
printf 'not json\n' >"$NOTJSON"

# The body the payload carries, as the record would hold it, and two bodies a
# write can leave behind: none (a step that dropped it) and another text.
BODY_OK="${HARNESS_TMP}/body-ok.txt"
printf '%s' 'Summary.' >"$BODY_OK"
BODY_NONE="${HARNESS_TMP}/body-none.txt"
: >"$BODY_NONE"
BODY_OTHER="${HARNESS_TMP}/body-other.txt"
printf '%s' 'Another summary.' >"$BODY_OTHER"
BODY_NL="${HARNESS_TMP}/body-nl.txt"
printf '%s\n' 'Summary.' >"$BODY_NL"

# rb <state> [<commit> [<repo> [<id> [<body-file>]]]]  prints a read-back fixture path
rb() {
  facts_file <<EOF
repo=${3:-acme/widgets}
pr.number=12
review.id=${4:-777}
review.commit=${2-$HEAD_SHA}
review.state=$1
review.body-file=${5-$BODY_OK}
review.url=${URL}
EOF
}

# Guard: the first call, before anything is written.
row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD"
assert_row 'approve' 0 "WRITE repo=acme/widgets pr=12 head=${HEAD_SHA} event=APPROVE\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" COMMENT "$PAYLOAD"
assert_row 'comment only' 0 "WRITE repo=acme/widgets pr=12 head=${HEAD_SHA} event=COMMENT\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" PENDING "$PAYLOAD"
assert_row 'draft only' 0 "WRITE repo=acme/widgets pr=12 head=${HEAD_SHA} event=PENDING\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$EMPTY"
assert_row 'no inline comments' 0 "WRITE repo=acme/widgets pr=12 head=${HEAD_SHA} event=APPROVE\n" 0

row_start
run_in "$NOORIGIN" 12 "$HEAD_SHA" APPROVE "$PAYLOAD"
assert_row 'no origin' 0 'STOP repo-lookup-failed\n' 0

# Usage.
row_start
run_in "$WORK" 12 "$HEAD_SHA" REQUEST_CHANGES "$PAYLOAD"
assert_row 'request changes' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" '' "$PAYLOAD"
assert_row 'no choice' 2 '' 0

row_start
run_in "$WORK" abc "$HEAD_SHA" APPROVE "$PAYLOAD"
assert_row 'non-numeric pr' 2 '' 0

row_start
run_in "$WORK" 12 abc APPROVE "$PAYLOAD"
assert_row 'head not a sha' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "${HARNESS_TMP}/absent.json"
assert_row 'missing payload' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$NOTJSON"
assert_row 'payload not json' 2 '' 0

row_start
run_sut env PATH="${HARNESS_TMP}/no-path" "$BASH_BIN" "$SUT" \
  12 "$HEAD_SHA" APPROVE "$PAYLOAD"
assert_row 'missing jq: named, not usage' 1 '' 0
tally check_eq 'missing jq: stderr' \
  'error: jq is required but was not found on PATH' "$(cat "$SUT_STDERR")"

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE
assert_row 'too few arguments' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted
assert_row '--posted without id' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts
assert_row '--facts without file' 2 '' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --state x
assert_row 'unknown option' 2 '' 0

# Read-back.
row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777
assert_row 'no facts: NEED pins' 0 "NEED repo=acme/widgets pr.number=12 review.id=777 review.commit=${HEAD_SHA} review.state review.body-file review.url\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED)"
assert_row 'approve posted' 0 "POSTED APPROVED ${URL}\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" COMMENT "$PAYLOAD" --posted 777 --facts "$(rb COMMENTED)"
assert_row 'comment posted' 0 "POSTED COMMENTED ${URL}\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" PENDING "$PAYLOAD" --posted 777 --facts "$(rb PENDING)"
assert_row 'draft left pending' 0 "POSTED PENDING ${URL}\n" 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" COMMENT "$PAYLOAD" --posted 777 --facts "$(rb PENDING)"
assert_row 'comment add failed midway' 0 'STOP review-pending-left\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb PENDING)"
assert_row 'submit failed' 0 'STOP review-pending-left\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" PENDING "$PAYLOAD" --posted 777 --facts "$(rb APPROVED)"
assert_row 'draft only but submitted' 0 'STOP review-state-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb COMMENTED)"
assert_row 'approve asked, commented' 0 'STOP review-state-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$OTHER_SHA")"
assert_row 'review pinned to another commit' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" upstream/widgets)"
assert_row 'review read in another repo' 0 'STOP fact-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" acme/widgets 778)"
assert_row "another review's record" 0 'STOP fact-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb CHANGES_REQUESTED)"
assert_row 'state outside the flow' 0 'STOP fact-enum\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED '')"
assert_row 'commit unreadable' 0 'STOP fact-missing\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" acme/widgets 777 '')"
assert_row 'body unreadable' 0 'STOP fact-missing\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" acme/widgets 777 "${HARNESS_TMP}/absent-body.txt")"
assert_row 'body file absent' 0 'STOP body-unreadable\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" acme/widgets 777 "$BODY_NONE")"
assert_row 'submitted with the body dropped' 0 'STOP review-state-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" PENDING "$PAYLOAD" --posted 777 --facts "$(rb PENDING "$HEAD_SHA" acme/widgets 777 "$BODY_NONE")"
assert_row 'draft only, body not carried' 0 'STOP review-pending-left\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" COMMENT "$PAYLOAD" --posted 777 --facts "$(rb COMMENTED "$HEAD_SHA" acme/widgets 777 "$BODY_OTHER")"
assert_row 'body read back differs' 0 'STOP review-state-mismatch\n' 0

row_start
run_in "$WORK" 12 "$HEAD_SHA" APPROVE "$PAYLOAD" --posted 777 --facts "$(rb APPROVED "$HEAD_SHA" acme/widgets 777 "$BODY_NL")"
assert_row 'body read back with a trailing newline' 0 "POSTED APPROVED ${URL}\n" 0

harness_exit "$failed" "$total"
