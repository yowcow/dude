#!/usr/bin/env bash
# Sourced by every test file. It puts the fake `gh` on PATH, hands out stub
# directories, runs the script under test, and compares results.
#
# Sourcing this file is what makes a test file offline: PATH is rewritten so
# `gh` resolves to the stub, and that resolution is asserted here rather than
# assumed, because a PATH mistake would send the whole suite to the real `gh`
# and the failure mode is a suite that still passes.

HARNESS_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# tests/lib -> tests -> the repository root.
REPO_ROOT="$(CDPATH='' cd -- "${HARNESS_LIB_DIR}/../.." && pwd)"
export REPO_ROOT

PATH="${HARNESS_LIB_DIR}/bin:${PATH}"
export PATH

if [ "$(command -v gh)" != "${HARNESS_LIB_DIR}/bin/gh" ]; then
  echo "harness: gh resolves to $(command -v gh), not the stub — refusing to run" >&2
  exit 1
fi

HARNESS_TMP="$(mktemp -d)"
trap 'rm -rf "${HARNESS_TMP}"' EXIT

SUT_STDOUT="${HARNESS_TMP}/stdout"
SUT_STDERR="${HARNESS_TMP}/stderr"
SUT_STATUS=0

stub_dir_new() {
  GH_STUB_DIR="$(mktemp -d "${HARNESS_TMP}/stub.XXXXXX")"
  export GH_STUB_DIR
  : >"${GH_STUB_DIR}/calls"
  printf '%s' 0 >"${GH_STUB_DIR}/count"
}

# Make `sleep` instant for this test file. Opt-in: a bounded poll loop in a
# script under test is worth asserting the *count* of, never the wall clock,
# and check-pr-state.sh's UNKNOWN re-read alone would otherwise cost 15s a row.
# The resolution is asserted rather than assumed, for the same reason the `gh`
# assertion above exists: a PATH mistake would leave the suite silently slow
# instead of failing.
stub_sleep_instant() {
  case ":${PATH}:" in
    *":${HARNESS_LIB_DIR}/bin-nosleep:"*) ;;
    *)
      PATH="${HARNESS_LIB_DIR}/bin-nosleep:${PATH}"
      export PATH
      hash -r 2>/dev/null || true
      ;;
  esac
  if [ "$(command -v sleep)" != "${HARNESS_LIB_DIR}/bin-nosleep/sleep" ]; then
    echo "harness: sleep resolves to $(command -v sleep), not the stub — refusing to run" >&2
    exit 1
  fi
}

sleep_call_count() {
  local n=0
  if [ -f "${GH_STUB_DIR}/sleeps" ]; then
    n="$(wc -l <"${GH_STUB_DIR}/sleeps" | tr -d ' ')"
  fi
  printf '%s\n' "$n"
}

# Two spellings, because the stub cannot tell from a body whether it is what gh
# printed or what gh received, and guessing is the failure this suite exists to
# catch — a filter applied to an already-filtered body errors, and a filter
# skipped on a raw body silently hands the caller the whole document.
#
# gh_stub_response <index|*> <exit-status> <argv...>       body on stdin
#   The body is gh's **stdout**, already filtered if the call carries --jq. The
#   stub hands it back verbatim. This is the default because it is what most
#   cases want: the script under test is being held to an output contract, and
#   the fixture states that contract directly.
#
# gh_stub_raw_response <index|*> <exit-status> <argv...>   body on stdin
#   The body is the raw **response gh received**, and the stub applies the
#   call's own --jq to it. Use it when the filter is part of what is under test:
#   list-unresolved-threads.sh's `select(.isResolved == false)` lives in the
#   script, so a pre-filtered fixture would decide the answer the test is
#   supposed to be checking, and "zero unresolved threads" would assert nothing.
gh_stub_response() {
  _gh_stub_entry filtered "$@"
}

gh_stub_raw_response() {
  _gh_stub_entry raw "$@"
}

_gh_stub_entry() {
  local mode="$1" idx="$2" status="$3"
  shift 3
  if ! [[ "$idx" =~ ^([1-9][0-9]*|\*)$ ]]; then
    echo "${FUNCNAME[1]}: index must be a positive integer or '*', got '${idx}'" >&2
    return 1
  fi
  if ! [[ "$status" =~ ^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
    echo "${FUNCNAME[1]}: exit status must be 0-255, got '${status}'" >&2
    return 1
  fi
  local arg joined=""
  for arg in "$@"; do
    # \x1f is the element separator, so an element carrying it would make two
    # different argv lists join to the same bytes — ["a\x1fb"] and ["a","b"] —
    # and the stub would serve one case's body to the other. Tabs and newlines
    # are fine: the joined argv goes to its own file, not into the TSV manifest.
    # Real argvs need that — list-copilot-reviews.sh:41-43 passes a three-line
    # --jq filter, and list-unresolved-threads.sh a 23-line GraphQL query — and
    # refusing them would leave those calls unstubbable.
    case "$arg" in
      *$'\x1f'*)
        printf '%s\n' "${FUNCNAME[1]}: argv element contains the \\x1f separator: '${arg}'" >&2
        return 1
        ;;
    esac
    joined="${joined}${arg}"$'\x1f'
  done
  local entry_no body argv_file
  entry_no=1
  if [ -f "${GH_STUB_DIR}/manifest" ]; then
    entry_no=$(($(wc -l <"${GH_STUB_DIR}/manifest") + 1))
  fi
  body="${GH_STUB_DIR}/body.${entry_no}"
  argv_file="${GH_STUB_DIR}/argv.${entry_no}"
  cat >"$body"
  printf '%s' "$joined" >"$argv_file"
  printf '%s\t%s\t%s\t%s\t%s\n' "$idx" "$status" "$body" "$argv_file" "$mode" >>"${GH_STUB_DIR}/manifest"
}

gh_call_count() {
  local n=0
  if [ -f "${GH_STUB_DIR}/count" ]; then
    n="$(cat "${GH_STUB_DIR}/count")"
  fi
  printf '%s\n' "$n"
}

gh_violations() {
  if [ -f "${GH_STUB_DIR}/violations" ]; then
    cat "${GH_STUB_DIR}/violations"
  fi
}

run_sut() {
  # SUT_STATUS is read by the test file that sourced this, which shellcheck
  # cannot see from here; exporting it instead would push it into the
  # environment of the script under test, which has no business seeing it.
  # shellcheck disable=SC2034
  SUT_STATUS=0
  # shellcheck disable=SC2034
  "$@" >"${SUT_STDOUT}" 2>"${SUT_STDERR}" </dev/null || SUT_STATUS=$?
}

check_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    return 0
  fi
  printf 'FAIL %s: want [%s], got [%s]\n' "$label" "$want" "$got"
  return 1
}

# check_bytes <label> <expected>   expected is a printf '%b' format string
# A convenience spelling of check_stdout_files for an expectation short enough to
# write inline: it materialises the expansion and defers the comparison, so both
# helpers report a mismatch identically and there is one byte comparison to
# trust rather than two copies of one.
check_bytes() {
  local label="$1" want="$2" wantfile="${HARNESS_TMP}/want"
  printf '%b' "$want" >"$wantfile"
  check_stdout_files "$label" "$wantfile"
}

# check_stdout_files <label> <file> [<file> ...]
# The byte-for-byte stdout comparison. The expectation comes from files, several
# of them because it is sometimes "page 1's rows, then the raw error body" — two
# artifacts already on disk, which one glued golden file would duplicate. Pass
# /dev/null for "nothing on stdout".
check_stdout_files() {
  local label="$1"
  shift
  local wantfile="${HARNESS_TMP}/want.files"
  # Guarded, and the quieter half is the reason. An unreadable expectation — a
  # mistyped golden path — leaves this file empty, and the `cmp` below then
  # reports "stdout differs, want: <nothing>", charging the test's own mistake
  # to the script under test. That is this suite's defect class 1 pointed
  # inward, so the path is named instead. The louder half: `set -e` is
  # suppressed inside a function invoked in an `if` condition, which is how
  # every call site spells it today, but not when the helper is called plainly
  # — and there an unguarded `cat` would abort the whole test file (measured).
  if ! cat -- "$@" >"$wantfile" 2>/dev/null; then
    printf 'FAIL %s: cannot read the expected bytes from: %s\n' "$label" "$*"
    return 1
  fi
  if cmp -s "$wantfile" "${SUT_STDOUT}"; then
    return 0
  fi
  printf 'FAIL %s: stdout differs\n  want: %s\n  got:  %s\n' \
    "$label" "$(od -An -c <"$wantfile" | tr -s ' \n' ' ')" \
    "$(od -An -c <"${SUT_STDOUT}" | tr -s ' \n' ' ')"
  return 1
}

# check_gh_stdin <label> <call-index> <expected-file>
# gh が stdin で受け取ったバイト列の比較。「その呼び出しに payload が無い」は
# 「バイト列が違う」とは別の失敗として報告する: 本文を流すのをやめた版を「別の
# バイト列を送った」と報告すると原因を指さないし、空の期待値と突き合わせれば
# そのまま通ってしまう。これはこの suite の欠陥クラス 1 を内側に向けたものである。
check_gh_stdin() {
  local label="$1" idx="$2" want="$3" got="${GH_STUB_DIR}/stdin.${2}"
  if [ ! -f "$got" ]; then
    printf 'FAIL %s: gh read no stdin payload for call %s\n' "$label" "$idx"
    return 1
  fi
  if [ ! -r "$want" ]; then
    printf 'FAIL %s: cannot read the expected payload from: %s\n' "$label" "$want"
    return 1
  fi
  if cmp -s "$want" "$got"; then
    return 0
  fi
  printf 'FAIL %s: the payload gh received differs\n  want: %s\n  got:  %s\n' \
    "$label" "$(od -An -c <"$want" | tr -s ' \n' ' ')" \
    "$(od -An -c <"$got" | tr -s ' \n' ' ')"
  return 1
}

check_no_violations() {
  local label="$1" v
  v="$(gh_violations)"
  if [ -z "$v" ]; then
    return 0
  fi
  printf 'FAIL %s: the gh stub was called with an argv no case stubbed:\n%s\n' "$label" "$v"
  return 1
}

harness_exit() {
  local failed="$1" total="$2"
  if [ "$failed" -eq 0 ]; then
    printf 'ok %s/%s %s\n' "$total" "$total" "${0##*/}"
    exit 0
  fi
  printf 'not ok %s/%s failed in %s\n' "$failed" "$total" "${0##*/}"
  exit 1
}
