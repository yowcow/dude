#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/post-plan-comment.sh.
#
# The script's header names four guards, and each row below exists for one of
# them.
#
# 1. The body is only ever read from a file and reaches `gh` on stdin as a
#    single JSON document (`jq -Rs`, -R raw and -s slurped). Two rows hold that:
#    the payload is compared byte for byte against a hand-written golden — which
#    is what makes `jq -R` (one JSON document per line, same argv) detectable —
#    and the fixture carries two shell substitutions writing to $PLAN_CANARY, so
#    a version that let the body reach the shell leaves a file behind. The
#    golden is hand-written rather than generated with `jq`, which would check
#    the implementation against itself.
# 2. The id printed is the numeric REST id, not the GraphQL node id. The
#    response fixture is raw and carries both, so the script's own --jq runs and
#    a `.node_id` version prints IC_... instead.
# 3. Nothing here edits an existing comment: the argv is POST .../comments, and
#    the stub matches argv exactly, so a PATCH version is an unstubbed call.
# 4. The usage guards refuse before any call: `gh responses` is 0 on every
#    refusing row, so a dropped guard shows up as a call that happened. Two
#    rows cover the issue-number guard rather than one, and the second is the
#    load-bearing half: `abc` proves only that some check exists, while `7x`
#    proves the pattern is **anchored**. Measured — with only the `abc` row,
#    weakening `^[0-9]+$` to `[0-9]+` left this file reporting ok 7/7, so a
#    number like `7x` would have been forwarded to the API.
#
#    The body-file guard gets two rows of its own: `missing-body-file` for a
#    path that is not there, and `unreadable-body-file` for one that is there
#    with mode 000. `-f` alone let the second through, and the `jq -Rs ... | gh`
#    pipeline then made one API call anyway, the redirect being the only thing
#    that failed — and under `set -o pipefail` that version exits non-zero too,
#    so the call count is what separates it from a refusal, not the exit status.
#    The unreadable file is built at run time and the row is skipped under uid 0;
#    the comments at both places say why.
#
# RED verification (mutations are not committed) — see tests/README.md:
#   tmp="$(mktemp -d)"; cp skills/plan-work/scripts/post-plan-comment.sh "$tmp/mut.sh"
#   # edit one guard out of "$tmp/mut.sh", then:
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/post-plan-comment_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/post-plan-comment.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

BODY="${HERE}/fixtures/plan-body.md"
MISSING="${HARNESS_TMP}/no-such-body.md"

# A file that exists and cannot be read. Built here rather than in fixtures/:
# git records only 100644 and 100755 for a regular file, so a mode-000 entry
# would come back readable on checkout, and `git add` refuses an unreadable file
# outright anyway (measured: `error: open(...): Permission denied`, exit 128). A
# checked-in fixture would therefore cost this row its detection power on
# exactly the non-root CI it exists for. It is a copy of the body rather than an
# empty file, so the refusal is about readability and not about emptiness — the
# guard deliberately does not check `-s`.
UNREADABLE="${HARNESS_TMP}/unreadable-body.md"
cp -- "$BODY" "$UNREADABLE"
chmod 000 "$UNREADABLE"

# Exported so the fixture's `touch "$PLAN_CANARY"` would land somewhere
# observable if the body ever reached a shell. Nothing in this suite creates it.
PLAN_CANARY="${HARNESS_TMP}/canary"
export PLAN_CANARY

failed=0
total=0

while IFS='|' read -r name args response want_exit want_calls want_stdout want_payload; do
  case "$name" in '' | '#'*) continue ;; esac

  # chmod 000 does not stop uid 0: there `-r` is true, the guard rightly lets
  # the body through, and `gh responses` is 1 rather than the 0 this row wants.
  # Failing the row would charge root's correct behaviour to the script under
  # test, so it is skipped — not run, one line printed, not counted, and the
  # file goes on to the end. run_test.sh:125-136 chose the same shape for the
  # same reason. The line is printed because a row that passes while testing
  # nothing is the state this suite exists to catch: the total drops by one, and
  # this line is what says why.
  #
  # Keyed on the placeholder rather than the row's name, so renaming the row
  # cannot silently detach the skip from it — a drift that would change nothing
  # off root and show up only on it.
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

  # `<fixture>[:<exit-status>]`, or `-` for a row that never reaches the API.
  if [ "$response" != '-' ]; then
    fixture="${response%%:*}"
    status=0
    case "$response" in *:*) status="${response##*:}" ;; esac
    gh_stub_raw_response 1 "$status" \
      api --method POST "repos/acme/widgets/issues/7/comments" --input - \
      --jq '.id, .html_url' <"${HERE}/fixtures/${fixture}.json"
  fi

  # @BODY / @MISSING / @UNREADABLE keep the row table free of absolute paths.
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
# name|args|response|exit|calls|stdout|payload
posts-body-prints-numeric-id|acme widgets 7 @BODY|comment-created|0|1|expected/created.out|expected/plan-body.payload.json
api-failure-is-not-a-post|acme widgets 7 @BODY|not-found:1|1|1|fixtures/not-found.json|expected/plan-body.payload.json
missing-body-file|acme widgets 7 @MISSING|-|1|0|-|-
unreadable-body-file|acme widgets 7 @UNREADABLE|-|1|0|-|-
non-numeric-issue|acme widgets abc @BODY|-|1|0|-|-
partially-numeric-issue|acme widgets 7x @BODY|-|1|0|-|-
too-few-args|acme widgets 7|-|1|0|-|-
too-many-args|acme widgets 7 @BODY extra|-|1|0|-|-
no-args||-|1|0|-|-
ROWS

harness_exit "$failed" "$total"
