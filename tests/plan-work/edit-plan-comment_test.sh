#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/edit-plan-comment.sh.
#
# The script's header names three guards, and each row below exists for one.
#
# 1. A GraphQL node id is refused **up front rather than sent**. The
#    `node-id-refused` row asserts `gh responses` is 0, so a version that
#    dropped the check and let PATCH carry an IC_... id fails on the call that
#    happened, not merely on a message. `partially-numeric-id` covers the other
#    half of that same check — that the pattern is **anchored**. Without it the
#    node-id row happens to catch a de-anchored `[0-9]+` only by accident,
#    because the fixture id `IC_kwDOAZjEl85e3xyz` contains digits; `2544x`
#    makes the anchoring deliberate rather than incidental. Neither row
#    exhausts "looks numeric": measured, under a UTF-8 locale `[0-9]` also
#    matches fullwidth `２５４４` and Arabic-Indic `٢٥٤٤` (both rejected under
#    `LC_ALL=C`), and the script PATCHes such an id rather than refusing.
#    Deliberately given no row, and not tracked anywhere either: #229 measured
#    this and settled that it will not be fixed — a fullwidth comment id is not
#    an input path this tool has to account for — so there is no follow-up for a
#    later reader to go looking for. Pinning today's behaviour would record it as
#    intended, and pinning a refusal would leave the suite red against a script
#    nobody is going to change.
# 2. The body comes from a file and reaches gh on stdin as one JSON document
#    (`jq -Rs`). The payload is compared byte for byte against the same
#    hand-written golden post-plan-comment_test.sh uses, which is what makes
#    `jq -R` — same argv, one document per line — detectable. The fixture's two
#    $PLAN_CANARY substitutions catch a body that reached a shell.
# 3. A body file that cannot be read refuses before any call, and the guard is
#    `[ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]` — two conditions because
#    `-f` asks only whether a regular file is there. Two rows hold the two
#    halves: `missing-body-file` for a path that is not there, and
#    `unreadable-body-file` for one that is there with mode 000, which `-f`
#    alone let through — the `jq -Rs ... | gh` pipeline then PATCHed anyway, the
#    redirect being the only thing that failed. Both rows assert `gh responses`
#    is 0, and that is what separates a refusal from that version: under
#    `set -o pipefail` it exits non-zero too, so the exit status tells the two
#    apart from nothing. The unreadable file is built at run time and the row is
#    skipped under uid 0; the comments at both places say why.
#
# RED verification (mutations are not committed) — see tests/README.md:
#   tmp="$(mktemp -d)"; cp skills/plan-work/scripts/edit-plan-comment.sh "$tmp/mut.sh"
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/edit-plan-comment_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/edit-plan-comment.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

BODY="${HERE}/fixtures/plan-body.md"
MISSING="${HARNESS_TMP}/no-such-body.md"

# A file that exists and cannot be read. Built at run time rather than checked
# into fixtures/, because git cannot carry mode 000 through a checkout and
# refuses to add an unreadable file at all — post-plan-comment_test.sh spells
# that out where it does the same. A copy of the body rather than an empty file,
# so the refusal is about readability and not about emptiness.
UNREADABLE="${HARNESS_TMP}/unreadable-body.md"
cp -- "$BODY" "$UNREADABLE"
chmod 000 "$UNREADABLE"
PLAN_CANARY="${HARNESS_TMP}/canary"
export PLAN_CANARY

failed=0
total=0

while IFS='|' read -r name args response want_exit want_calls want_stdout want_payload; do
  case "$name" in '' | '#'*) continue ;; esac

  # chmod 000 does not stop uid 0, where `-r` is true and the guard rightly
  # lets the body through — so the row is skipped rather than failed, since
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

  if [ "$response" != '-' ]; then
    fixture="${response%%:*}"
    status=0
    case "$response" in *:*) status="${response##*:}" ;; esac
    gh_stub_raw_response 1 "$status" \
      api --method PATCH "repos/acme/widgets/issues/comments/2544" --input - \
      --jq '.html_url' <"${HERE}/fixtures/${fixture}.json"
  fi

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
edits-by-numeric-id|acme widgets 2544 @BODY|comment-edited|0|1|expected/edited.out|expected/plan-body.payload.json
api-failure-is-not-an-edit|acme widgets 2544 @BODY|not-found:1|1|1|fixtures/not-found.json|expected/plan-body.payload.json
node-id-refused|acme widgets IC_kwDOAZjEl85e3xyz @BODY|-|1|0|-|-
partially-numeric-id|acme widgets 2544x @BODY|-|1|0|-|-
missing-body-file|acme widgets 2544 @MISSING|-|1|0|-|-
unreadable-body-file|acme widgets 2544 @UNREADABLE|-|1|0|-|-
too-few-args|acme widgets 2544|-|1|0|-|-
too-many-args|acme widgets 2544 @BODY extra|-|1|0|-|-
no-args||-|1|0|-|-
ROWS

harness_exit "$failed" "$total"
