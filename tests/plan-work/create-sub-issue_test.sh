#!/usr/bin/env bash
# Table test for skills/plan-work/scripts/create-sub-issue.sh.
#
# The script's header names four guards, and each row below exists for one of
# them.
#
# 1. The body is only ever read from a file and reaches `gh` on stdin as a
#    single JSON document (`jq -Rs`, -R raw and -s slurped) carrying the title
#    beside it. The payload is compared byte for byte against a hand-written
#    golden — which is what makes `jq -R` (one JSON document per line, same
#    argv) detectable — and the body fixture carries two shell substitutions
#    writing to $PLAN_CANARY, so a version that let the body reach the shell
#    leaves a file behind. The golden is hand-written rather than generated
#    with `jq`, which would check the implementation against itself. The title
#    carries a backtick, a double quote and spaces for the same reason: it is
#    passed with --arg, so it has to survive into the payload unaltered.
#
#    fixtures/plan-body.md is shared with post-plan-comment_test.sh rather than
#    copied: both scripts wrap a body the same way, the canary is already wired
#    into it, and a second copy would drift.
#
# 2. The number and URL are printed BEFORE the child is attached. The
#    `link-failure-keeps-the-number` row is the one that holds this: the
#    sibling's read-back fails, the script exits non-zero, and stdout still
#    carries both lines. Printed after the attach instead, that row's stdout is
#    empty and the caller has a created issue it cannot name.
#
# 3. Attaching is delegated to the sibling ./link-sub-issue.sh, not repeated
#    here. The happy row stubs that script's own three calls on their exact
#    argv — the number resolved to a database id, the POST keyed on that id,
#    and the paginated read-back — so a version that posts to the sub_issues
#    endpoint itself reaches an argv no case stubbed and fails as a violation.
#
# 4. The usage guards refuse before any call: `gh responses` is 0 on every
#    refusing row, so a dropped guard shows up as a call that happened. Two
#    rows cover the parent-number guard rather than one, and the second is the
#    load-bearing half: `abc` proves only that some check exists, while `42x`
#    proves the pattern is **anchored**.
#
#    The body-file guard gets two rows of its own: `missing-body-file` for a
#    path that is not there, and `unreadable-body-file` for one that is there
#    with mode 000. `-f` alone lets the second through, and the `jq -Rs ... |
#    gh` pipeline then creates the issue anyway, the redirect being the only
#    thing that failed — and under `set -o pipefail` that version exits
#    non-zero too, so the call count is what separates it from a refusal, not
#    the exit status. The unreadable file is built at run time and the row is
#    skipped under uid 0; the comments at both places say why.
#
# RED verification (mutations are not committed) — see tests/README.md. This
# script has no pre-fix version in history, so detection power is shown by
# removing one named guard at a time from a copy:
#   tmp="$(mktemp -d)"
#   cp skills/plan-work/scripts/create-sub-issue.sh "$tmp/mut.sh"
#   # guard 1: replace `jq -Rs` with `jq -R`, or pass --body "$(cat ...)"
#   # guard 2: move the printf below the sibling call
#   # guard 3: replace the sibling call with an inline POST
#   # guard 4: delete one of the argument guards
#   SUT="$tmp/mut.sh" tests/run.sh tests/plan-work/create-sub-issue_test.sh
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/plan-work/scripts/create-sub-issue.sh}"
HERE="$(dirname -- "${BASH_SOURCE[0]}")"

OWNER=acme
REPO=widgets
PARENT=42
CHILD=57
CHILD_ID=5213622913

# Spaces, a backtick and a double quote, so the payload golden is only reached
# by a version that hands the title to --arg rather than splicing it in.
TITLE='plan-work: `create-sub-issue.sh` を追加する "第 1 版"'

BODY="${HERE}/fixtures/plan-body.md"
MISSING="${HARNESS_TMP}/no-such-body.md"

# A file that exists and cannot be read. Built here rather than in fixtures/:
# git records only 100644 and 100755 for a regular file, so a mode-000 entry
# would come back readable on checkout, and `git add` refuses an unreadable
# file outright anyway. A checked-in fixture would therefore cost this row its
# detection power on exactly the non-root CI it exists for. It is a copy of the
# body rather than an empty file, so the refusal is about readability and not
# about emptiness — the guard deliberately does not check `-s`.
UNREADABLE="${HARNESS_TMP}/unreadable-body.md"
cp -- "$BODY" "$UNREADABLE"
chmod 000 "$UNREADABLE"

# Exported so the fixture's `touch "$PLAN_CANARY"` would land somewhere
# observable if the body ever reached a shell. Nothing in this suite creates it.
PLAN_CANARY="${HARNESS_TMP}/canary"
export PLAN_CANARY

# stub_link <readback-fixture>   the sibling's own three calls, indices 2-4.
stub_link() {
  gh_stub_raw_response 2 0 \
    api "repos/${OWNER}/${REPO}/issues/${CHILD}" --jq '.id' \
    <"${HERE}/fixtures/issue-57.json"
  : | gh_stub_raw_response 3 0 \
    api --method POST "repos/${OWNER}/${REPO}/issues/${PARENT}/sub_issues" \
    -F "sub_issue_id=${CHILD_ID}"
  gh_stub_raw_response 4 0 \
    api --paginate "repos/${OWNER}/${REPO}/issues/${PARENT}/sub_issues?per_page=100" \
    --jq '.[].number' <"${HERE}/fixtures/$1.json"
}

failed=0
total=0

while IFS='|' read -r name args create link want_exit want_calls want_stdout want_payload; do
  case "$name" in '' | '#'*) continue ;; esac

  # chmod 000 does not stop uid 0: there `-r` is true, the guard rightly lets
  # the body through, and `gh responses` is 1 rather than the 0 this row wants.
  # Failing the row would charge root's correct behaviour to the script under
  # test, so it is skipped — not run, one line printed, not counted, and the
  # file goes on to the end. post-plan-comment_test.sh and run_test.sh chose the
  # same shape for the same reason. The line is printed because a row that
  # passes while testing nothing is the state this suite exists to catch.
  #
  # Keyed on the placeholder rather than the row's name, so renaming the row
  # cannot silently detach the skip from it.
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
  if [ "$create" != '-' ]; then
    fixture="${create%%:*}"
    status=0
    case "$create" in *:*) status="${create##*:}" ;; esac
    gh_stub_raw_response 1 "$status" \
      api --method POST "repos/${OWNER}/${REPO}/issues" --input - \
      --jq '.number, .html_url' <"${HERE}/fixtures/${fixture}.json"
  fi

  if [ "$link" != '-' ]; then stub_link "$link"; fi

  # Placeholders are replaced element by element, after the split: @TITLE
  # expands to a value carrying spaces, and a replace-then-split would break it
  # into several arguments.
  #
  # The subscript on the assignment side is bare `i`, not `$i`: a subscript is
  # an arithmetic context, and shellcheck refuses the `$` form (SC2004).
  # tests/lint.sh runs shellcheck with no severity floor, so a style finding
  # fails `make lint`.
  read -ra argv <<<"$args"
  for i in "${!argv[@]}"; do
    case "${argv[$i]}" in
      @TITLE) argv[i]="$TITLE" ;;
      @BODY) argv[i]="$BODY" ;;
      @MISSING) argv[i]="$MISSING" ;;
      @UNREADABLE) argv[i]="$UNREADABLE" ;;
    esac
  done
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
# name|args|create|link|exit|calls|stdout|payload
creates-then-attaches|acme widgets 42 @TITLE @BODY|issue-created|sub-issues-with-57|0|4|expected/created-and-linked.out|expected/sub-issue.payload.json
link-failure-keeps-the-number|acme widgets 42 @TITLE @BODY|issue-created|sub-issues-without-57|1|4|expected/created-only.out|expected/sub-issue.payload.json
create-failure-attaches-nothing|acme widgets 42 @TITLE @BODY|not-found:1|-|1|1|-|expected/sub-issue.payload.json
missing-body-file|acme widgets 42 @TITLE @MISSING|-|-|1|0|-|-
unreadable-body-file|acme widgets 42 @TITLE @UNREADABLE|-|-|1|0|-|-
non-numeric-parent|acme widgets abc @TITLE @BODY|-|-|1|0|-|-
partially-numeric-parent|acme widgets 42x @TITLE @BODY|-|-|1|0|-|-
too-few-args|acme widgets 42 @TITLE|-|-|1|0|-|-
too-many-args|acme widgets 42 @TITLE @BODY extra|-|-|1|0|-|-
no-args||-|-|1|0|-|-
ROWS

harness_exit "$failed" "$total"
