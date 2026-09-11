#!/usr/bin/env bash
# Table test for hooks/session-start: the JSON it prints on stdout, which
# Claude Code reads as the SessionStart hook's additionalContext.
#
# Every row runs the script inside a synthetic plugin tree rather than this
# repository. The script derives what it prints from its own $0, so a copy of
# it under a directory this file built is what makes the derived path
# assertable at all -- and it is the only way to reach a plugin root whose path
# carries a quote or a backslash.
#
# jq parses the output. The script itself deliberately avoids jq -- its header
# records why: jq is not guaranteed wherever the plugin is installed -- and
# that is exactly why the test needs one. The property under test is "the bytes
# this hand-rolled escaper emitted are valid JSON", and a hand-rolled checker
# here would re-encode the same belief it is supposed to be checking. jq is
# already a dependency of this suite through tests/lib/bin/gh.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). Against the pre-change script, five
# rows fail: `plain-tree`, `weird-path-json-intact`,
# `control-chars-json-intact`, `cdpath-ignored` and `skill-body-ignored` --
# the first four on the context bytes (full body vs stub),
# `skill-body-ignored` on the leaked marker/fallback absence. `size-budget`
# passes on this tiny fixture (pre-change stdout ~0.5KB, under 2048); the
# 11,273-byte full-text figure is the real-install motivation noted in the
# row below, not a RED observation.
# Run it with:
#   SUT=<pre-change copy> tests/run.sh tests/hooks/session-start_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/hooks/session-start}"

# Refused rather than skipped. A skip would report this file as green while
# asserting nothing about the escaping, which is the whole point of it.
if ! command -v jq >/dev/null 2>&1; then
  echo "session-start_test: jq is required to parse the hook's output — refusing to run" >&2
  exit 1
fi

failed=0
total=0

# The fixture body the hook must NOT emit. The stub is static: even this
# marker sentence must never appear in additionalContext. Content that
# exercised the old escaper is gone with the old emission path on purpose --
# escaping is now asserted through the install path alone (weird-path,
# control-chars rows).
BODY="${HARNESS_TMP}/body.md"
{
  printf '# Using dude\n\n'
  printf 'MARKER-SENTENCE-THAT-MUST-NEVER-APPEAR-IN-CONTEXT\n'
} >"$BODY"

# build_tree <dir> -- a plugin tree at <dir> holding hooks/session-start (a copy
# of the script under test, so a `SUT=` override is honoured) and
# skills/using-dude/SKILL.md (the frontmatter every skill carries, followed by
# $BODY). <dir> is created afresh.
build_tree() {
  local root="$1"
  rm -rf -- "$root"
  mkdir -p -- "${root}/hooks" "${root}/skills/using-dude"
  cp -- "$SUT" "${root}/hooks/session-start"
  chmod +x -- "${root}/hooks/session-start"
  { printf -- '---\nname: using-dude\ndescription: fixture\n---\n\n'; cat -- "$BODY"; } \
    >"${root}/skills/using-dude/SKILL.md"
}

# check_json <label> -- stdout parses as JSON and carries the SessionStart
# envelope. Asserted separately from the context comparison below: a payload
# that is not JSON at all and one that carries the wrong text are different
# defects, and reporting the first as "the context differs" would point nowhere.
check_json() {
  local label="$1" ev
  if ! jq -e . <"$SUT_STDOUT" >/dev/null 2>&1; then
    printf 'FAIL %s: stdout is not valid JSON\n  got: %s\n' \
      "$label" "$(head -c 400 "$SUT_STDOUT")"
    return 1
  fi
  ev="$(jq -r '.hookSpecificOutput.hookEventName' <"$SUT_STDOUT")"
  check_eq "${label}: hookEventName" 'SessionStart' "$ev"
}

# check_context <label> <root> -- the parsed additionalContext against the stub
# block the hook should inject for a tree at <root>, byte for byte. Both sides
# go through files, so a mismatch is reported by cmp on bytes rather than by
# eyeballing two long strings. The final newline is jq -r's line terminator,
# not part of the string.
check_context() {
  local label="$1" root="$2"
  local want="${HARNESS_TMP}/expected.ctx" got="${HARNESS_TMP}/got.ctx"
  {
    printf '<EXTREMELY_IMPORTANT>\n'
    printf 'dude'"'"'s workflow rules — summary stub (not the full ruleset) from the dude install at %s:\n\n' "$root"
    printf 'Before any task, read the `dude:using-dude` skill and follow it. '
    printf 'The full rules live in skills/using-dude/SKILL.md of this install; this stub is only a pointer.\n\n'
    printf 'The orchestrator owns control flow and drives every transition; '
    printf 'a worker never declares a phase complete or advances the workflow. '
    printf 'A sub-skill'"'"'s trailing transition is cut — what runs next is the caller'"'"'s decision, not the sub-skill'"'"'s.\n'
    printf '</EXTREMELY_IMPORTANT>\n'
  } >"$want"
  if ! jq -r '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" >"$got" 2>/dev/null; then
    printf 'FAIL %s: stdout carries no .hookSpecificOutput.additionalContext string\n' "$label"
    return 1
  fi
  if cmp -s "$want" "$got"; then
    return 0
  fi
  printf 'FAIL %s: the injected context differs\n  want: %s\n  got:  %s\n' \
    "$label" "$(od -An -c <"$want" | tr -s ' \n' ' ')" \
    "$(od -An -c <"$got" | tr -s ' \n' ' ')"
  return 1
}

# row_done <name> <fails> -- the tail every row shares. The exit status is
# asserted here rather than per row: this script's only exit is the trailing
# `exit 0` -- so "it exited 0" is a property of every row alike, not a
# per-row expectation.
row_done() {
  local name="$1" fails="$2"
  if ! check_eq "${name}: exit" 0 "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${name}: gh calls" 0 "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# ---- a plain tree: the stub block, byte for byte ------------------------
#
# One row carries both "the output is JSON" and "the stub arrived whole",
# because the second is only meaningful once the first holds. The exact
# comparison is what makes truncation detectable: a block cut short anywhere
# fails it.

row_start
ROOT="${HARNESS_TMP}/tree.plain"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'plain-tree'; then fails=1; fi
if ! check_context 'plain-tree: context' "$ROOT"; then fails=1; fi
row_done 'plain-tree' "$fails"

# ---- a plugin root carrying a quote and a backslash ---------------------
#
# The path reaches the JSON, so it has to go through the escaper. Unescaped,
# a single `"` in an install path closes the string early and the whole stub
# -- not merely the path -- stops arriving. Both
# characters are legal in a POSIX filename, so this is reachable, not
# hypothetical.

row_start
ROOT="${HARNESS_TMP}/tree.q\"uote\\slash"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'weird-path-json-intact'; then fails=1; fi
if ! check_context 'weird-path-json-intact: context' "$ROOT"; then fails=1; fi
row_done 'weird-path-json-intact' "$fails"

# ---- a plugin root carrying C0 control characters -----------------------
#
# JSON forbids a raw U+0000..U+001F inside a string and only five of them have
# a two-character escape. The install path is not this repository's to
# constrain -- it is whatever directory the plugin was installed into -- so a
# control character there is reachable the same way the quote above is. Left
# raw it invalidates the whole object rather than merely the path: Claude Code
# drops the block, and the hook still exits 0, so the stub never arrives
# and nothing says so.
#
# The path carries every C0 control the escaper has to convert, not a sample of
# them: the conversion spells its codes in octal, and a single mis-numbered
# entry would otherwise ship green.

row_start
ROOT="${HARNESS_TMP}/tree.ctl"$'\b\f\t\n\r\001\002\003\004\005\006\007\013\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'"end"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'control-chars-json-intact'; then fails=1; fi
if ! check_context 'control-chars-json-intact: context' "$ROOT"; then fails=1; fi
row_done 'control-chars-json-intact' "$fails"

# ---- CDPATH must not redirect the derivation ----------------------------
#
# `cd` consults CDPATH for a relative operand and prints the directory it
# landed on, so an exported CDPATH holding a decoy makes the hook's own `cd`
# resolve to a tree it was never invoked from -- and hook_dir then carries that
# path plus the echoed line. Before this change that produced a failed read and
# a loud error; now the same value is printed as the block's identity, so the
# block names a tree it never ran from. That is worse than naming none: telling
# two installs apart is the whole point of the line, and a wrong one is
# believed. The repository already spells the guard this way in
# tests/lib/harness.sh and tests/run.sh.
#
# The row reaches it the only way it is reachable: an argv whose $0 is
# relative, so `dirname` yields a bare `hooks` for CDPATH to resolve.

row_start
ROOT="${HARNESS_TMP}/tree.cdpath"
build_tree "$ROOT"
DECOY="${HARNESS_TMP}/decoy.cdpath"
rm -rf -- "$DECOY"
mkdir -p -- "${DECOY}/hooks"
cd "$ROOT"
# Set for this one call rather than exported and unset afterwards, which would
# destroy a CDPATH the parent had set.
CDPATH="$DECOY" run_sut bash hooks/session-start
cd "$REPO_ROOT"
fails=0
if ! check_json 'cdpath-ignored'; then fails=1; fi
if ! check_context 'cdpath-ignored: context' "$ROOT"; then fails=1; fi
row_done 'cdpath-ignored' "$fails"

# ---- the skill body never reaches the output ---------------------------
#
# The stub is static: deleting the skill file changes nothing. The old
# read-failure branch is gone (its absence surfaces loudly at skill-read
# time, AUTHORING.md deletion-test (b)), so this row asserts the absence of
# both the marker sentence and any fallback text.

row_start
ROOT="${HARNESS_TMP}/tree.noskill"
build_tree "$ROOT"
rm -f -- "${ROOT}/skills/using-dude/SKILL.md"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'skill-body-ignored'; then fails=1; fi
if ! check_context 'skill-body-ignored: context' "$ROOT"; then fails=1; fi
if jq -r '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null | grep -q 'MARKER-SENTENCE'; then
  printf 'FAIL skill-body-ignored: skill body leaked into the stub\n'
  fails=1
fi
if jq -r '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null | grep -q 'in full'; then
  printf 'FAIL skill-body-ignored: stale "in full" claim present\n'
  fails=1
fi
row_done 'skill-body-ignored' "$fails"

# ---- size budget: the whole reason for the stub -------------------------
#
# additionalContext (decoded) must stay at or under 1536 bytes (~1.5KB) and
# the full stdout at or under 2048 bytes, both below the ~2KB truncation
# threshold that demoted the 11,273-byte full-text output to a file fallback.

row_start
ROOT="${HARNESS_TMP}/tree.plain"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'size-budget'; then fails=1; fi
ctx_bytes="$(jq -j '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null | wc -c | tr -d ' ')"
out_bytes="$(wc -c <"$SUT_STDOUT" | tr -d ' ')"
if [ "$ctx_bytes" -gt 1536 ]; then
  printf 'FAIL size-budget: additionalContext is %s bytes, budget is 1536\n' "$ctx_bytes"
  fails=1
fi
if [ "$out_bytes" -gt 2048 ]; then
  printf 'FAIL size-budget: stdout is %s bytes, budget is 2048\n' "$out_bytes"
  fails=1
fi
row_done 'size-budget' "$fails"

# ---- a long install path stays inside the budget -----------------------
#
# The identity is the only dynamic part of the stub, so a valid install
# under a long directory must not push stdout past its budget. Without
# the bound this row fails the same budget the row above passes.

row_start
COMP="$(printf '%200s' '' | tr ' ' 'a')"
ROOT="${HARNESS_TMP}/tree.long/${COMP}/${COMP}/${COMP}/${COMP}/${COMP}"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'near-limit-path'; then fails=1; fi
ctx_bytes="$(jq -j '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null | wc -c | tr -d ' ')"
out_bytes="$(wc -c <"$SUT_STDOUT" | tr -d ' ')"
if [ "$ctx_bytes" -gt 1536 ]; then
  printf 'FAIL near-limit-path: additionalContext is %s bytes, budget is 1536\n' "$ctx_bytes"
  fails=1
fi
if [ "$out_bytes" -gt 2048 ]; then
  printf 'FAIL near-limit-path: stdout is %s bytes, budget is 2048\n' "$out_bytes"
  fails=1
fi
row_done 'near-limit-path' "$fails"

harness_exit "$failed" "$total"
