#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/close-dropped-sub-issue.sh.
#
# The script's header names two guards and one non-action, and the rows hold all
# three.
#
# 1. The reason must be "not planned". `gh issue close` is stubbed with that
#    exact argv, and the stub matches argv whole, so a version closing with the
#    default reason is an unstubbed call rather than a silent pass. The
#    read-back row pins the same thing from the other side: stdout carries the
#    stateReason a caller would see.
# 2. The reason body comes from a file and reaches gh on stdin as one JSON
#    document. The payload is compared byte for byte, so `jq -R` — same argv —
#    is detectable, and the fixture's $PLAN_CANARY substitutions catch a body
#    that reached a shell. The file guard behind that gets two rows:
#    `missing-reason-file` for a path that is not there, and
#    `unreadable-reason-file` for one that is there with mode 000, which the
#    old `-f`-only guard let through — the `jq -Rs ... | gh` pipeline then
#    posted the reason anyway, the redirect being the only thing that failed.
#    Both rows assert `gh responses` is 0, and here that is the *only* thing
#    that separates a refusal from that version: this file stubs all three
#    calls on every row, so the stray call is answered rather than reported as
#    unstubbed, and `pipefail` picks up the redirect's own 1 — the same exit
#    status a refusal gives. The unreadable file is built at run time and the
#    row is skipped under uid 0; the comments at both places say why.
# 3. Nothing removes the sub-issue link: the row asserts exactly three
#    responses, so a version that also deleted the relation makes a fourth,
#    unstubbed call.
#
# The three calls are stubbed by index, which is what pins the order — post the
# reason, then close. A version closing first answers call 1 with the comment
# entry's argv and is reported as unstubbed.
#
# The child-number guard gets two rows, and `partially-numeric-child` is the
# load-bearing one: `abc` proves only that some check exists, while `7x` proves
# the pattern is **anchored**. Measured — with only the `abc` row, weakening
# `^[0-9]+$` to `[0-9]+` left this file reporting ok 9/9.
#
# Neither row exhausts "looks numeric". Measured: under a UTF-8 locale `[0-9]`
# also matches fullwidth `２５４４` and Arabic-Indic `٢٥٤٤` (both rejected under
# `LC_ALL=C`), and the script forwards such a child number to `gh` instead of
# refusing. Deliberately given no row, and not tracked anywhere either: #229
# measured this and settled that it will not be fixed — a fullwidth issue number
# is not an input path this tool has to account for — so there is no follow-up
# for a later reader to go looking for. Pinning today's behaviour would record it
# as intended, and pinning a refusal would leave the suite red against a script
# nobody is going to change.
#
# RED verification (mutations are not committed) — see tests/README.md:
#   tmp="$(mktemp -d)"; cp skills/plan-work/scripts/close-dropped-sub-issue.sh "$tmp/mut.sh"
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/close-dropped-sub-issue_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/close-dropped-sub-issue.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

BODY="${HERE}/fixtures/plan-body.md"
MISSING="${HARNESS_TMP}/no-such-reason.md"

# A file that exists and cannot be read. Built at run time rather than checked
# into fixtures/, because git cannot carry mode 000 through a checkout and
# refuses to add an unreadable file at all — post-plan-comment_test.sh spells
# that out where it does the same. A copy of the body rather than an empty file,
# so the refusal is about readability and not about emptiness.
UNREADABLE="${HARNESS_TMP}/unreadable-reason.md"
cp -- "$BODY" "$UNREADABLE"
chmod 000 "$UNREADABLE"
PLAN_CANARY="${HARNESS_TMP}/canary"
export PLAN_CANARY

# Byte-identical to the script's own --jq expression.
VIEW_JQ='"#\(.number) \(.state) (\(.stateReason))"'

failed=0
total=0

# fail_at: which of the three calls answers non-zero (`-` for none). Every row
# stubs all three, because a row that stubbed only up to its failure could not
# tell "the script stopped there" from "the script called something nobody
# stubbed".
while IFS='|' read -r name args fail_at want_exit want_calls want_stdout want_payload; do
  case "$name" in '' | '#'*) continue ;; esac

  # chmod 000 does not stop uid 0, where `-r` is true and the guard rightly
  # lets the reason through — so the row is skipped rather than failed, since
  # failing it would charge root's correct behaviour to the script under test.
  # Not run, one line printed, not counted, and the file goes on to the end;
  # run_test.sh:125-136 chose the same shape, and post-plan-comment_test.sh
  # carries the longer form of the reason. Keyed on the placeholder rather than
  # the row's name so a rename cannot silently detach the skip from it.
  case "$args" in
    *@UNREADABLE*)
      if [ -r "$UNREADABLE" ]; then
        printf 'skip %s: chmod 000 left %s readable as uid %s — the guard is right to accept it here\n' \
          "$name" "$UNREADABLE" "$(id -u)"
        continue
      fi
      ;;
  esac

  total=$((total + 1))
  stub_dir_new

  s1=0 s2=0 s3=0
  case "$fail_at" in
    1) s1=1 ;;
    2) s2=1 ;;
    3) s3=1 ;;
  esac
  gh_stub_response 1 "$s1" \
    api --method POST "repos/acme/widgets/issues/7/comments" --input - \
    <"${HERE}/fixtures/not-found.json"
  gh_stub_response 2 "$s2" \
    issue close 7 --repo acme/widgets --reason "not planned" </dev/null
  gh_stub_raw_response 3 "$s3" \
    issue view 7 --repo acme/widgets --json number,state,stateReason --jq "$VIEW_JQ" \
    <"${HERE}/fixtures/issue-closed.json"

  args="${args//@BODY/$BODY}"
  args="${args//@MISSING/$MISSING}"
  args="${args//@UNREADABLE/$UNREADABLE}"
  read -ra argv <<<"$args"
  run_sut bash "$SUT" ${argv[@]+"${argv[@]}"}

  want_paths=(/dev/null)
  if [ "$want_stdout" != '-' ]; then want_paths=("${HERE}/${want_stdout}"); fi

  fails_here=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails_here=1; fi
  if ! check_eq "${name}: gh responses" "$want_calls" "$(gh_call_count)"; then fails_here=1; fi
  if ! check_stdout_files "${name}: stdout" "${want_paths[@]}"; then fails_here=1; fi
  if ! check_no_violations "${name}: argv"; then fails_here=1; fi
  if [ "$want_payload" != '-' ]; then
    if ! check_gh_stdin "${name}: payload" 1 "${HERE}/${want_payload}"; then fails_here=1; fi
  fi
  if [ -e "$PLAN_CANARY" ]; then
    printf 'FAIL %s: the body was interpreted by a shell (%s exists)\n' "$name" "$PLAN_CANARY"
    rm -f "$PLAN_CANARY"
    fails_here=1
  fi
  if [ "$fails_here" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
done <<'ROWS'
# name|args|fail_at|exit|calls|stdout|payload
closes-as-not-planned|acme widgets 7 @BODY|-|0|3|expected/closed.out|expected/plan-body.payload.json
reason-post-fails-nothing-is-closed|acme widgets 7 @BODY|1|1|1|-|expected/plan-body.payload.json
close-fails|acme widgets 7 @BODY|2|1|2|-|expected/plan-body.payload.json
read-back-fails|acme widgets 7 @BODY|3|1|3|fixtures/issue-closed.json|expected/plan-body.payload.json
missing-reason-file|acme widgets 7 @MISSING|-|1|0|-|-
unreadable-reason-file|acme widgets 7 @UNREADABLE|-|1|0|-|-
non-numeric-child|acme widgets abc @BODY|-|1|0|-|-
partially-numeric-child|acme widgets 7x @BODY|-|1|0|-|-
too-few-args|acme widgets 7|-|1|0|-|-
too-many-args|acme widgets 7 @BODY extra|-|1|0|-|-
no-args||-|1|0|-|-
ROWS

harness_exit "$failed" "$total"
