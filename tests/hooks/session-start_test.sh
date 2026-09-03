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
# RED verification (see tests/README.md). Against the pre-change script, seven
# of the eight rows fail and only `frontmatter-dropped` passes -- that row
# asserts behaviour this change does not touch. The seven are `plain-tree`,
# `names-the-install-path`, `weird-path-json-intact`,
# `control-chars-json-intact`, `cdpath-ignored`, `missing-skill-file` and
# `read-failure-names-the-path`, and they fail for three distinct reasons:
#   - the wrapper named no install path, so every row reading the heading line
#     differs there;
#   - the fallback message spelled the skill file `<root>/hooks/../skills/...`,
#     because skill_file hung off hook_dir rather than off the plugin root;
#   - `cd` was left to consult CDPATH, so `cdpath-ignored` resolved the hook
#     into the decoy tree.
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

# The body of the fixture SKILL.md, from the first `# ` line on -- which is the
# span the script's `sed -n '/^# /,$p'` selects. It carries a quote, a
# backslash, a tab and a carriage return -- four of the characters
# escape_for_json rewrites; content that exercised none of them would pass
# through a broken escaper unharmed. The control characters it does not carry
# are exercised through the install path, by `control-chars-json-intact`.
BODY="${HARNESS_TMP}/body.md"
{
  printf '# Using dude\n\n'
  printf 'A quote: "q", a backslash: \\ and a tab:\there.\n'
  printf 'A carriage return follows this word:\r end.\n\n'
  printf '## Last section\n\nThe final line, which truncation would drop.\n'
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

# check_context <label> <root> -- the parsed additionalContext against the whole
# block the hook should inject for a tree at <root>, byte for byte. Both sides
# go through files, so a mismatch is reported by cmp on bytes rather than by
# eyeballing two long strings.
#
# The body is emitted through `printf '%s' "$(cat ...)"`, which strips trailing
# newlines exactly as the script's own `$(sed ...)` does. The final newline is
# jq -r's line terminator, not part of the string.
check_context() {
  local label="$1" root="$2"
  local want="${HARNESS_TMP}/expected.ctx" got="${HARNESS_TMP}/got.ctx"
  {
    printf '<EXTREMELY_IMPORTANT>\n'
    printf "dude's workflow rules — the %s skill, in full, from the dude install at %s:\n\n" \
      '`dude:using-dude`' "$root"
    printf '%s' "$(cat -- "$BODY")"
    printf '\n</EXTREMELY_IMPORTANT>\n'
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

# check_context_has <label> <substring> -- for the rows whose expectation is
# "this text appears", where the rest of the block is asserted elsewhere.
check_context_has() {
  local label="$1" want="$2" got
  got="$(jq -r '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null)" || {
    printf 'FAIL %s: stdout carries no .hookSpecificOutput.additionalContext string\n' "$label"
    return 1
  }
  case "$got" in
    *"$want"*) return 0 ;;
  esac
  printf 'FAIL %s: the injected context does not carry [%s]\n  got: %s\n' \
    "$label" "$want" "$(printf '%s' "$got" | head -c 400)"
  return 1
}

# row_done <name> <fails> -- the tail every row shares. The exit status is
# asserted here rather than per row: this script's only exit is the trailing
# `exit 0`, and its read-failure branch is a fallback assignment rather than a
# non-zero return -- so "it exited 0" is a property of every row alike, not a
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

# ---- a plain tree: the whole block, byte for byte -----------------------
#
# One row carries both "the output is JSON" and "the content arrived in full",
# because the second is only meaningful once the first holds. The exact
# comparison is what makes truncation detectable: a block cut short anywhere
# fails it, including at the last line of the fixture body.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.plain"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'plain-tree'; then fails=1; fi
if ! check_context 'plain-tree: context' "$ROOT"; then fails=1; fi
row_done 'plain-tree' "$fails"

# ---- the frontmatter is not injected ------------------------------------
#
# The `sed -n '/^# /,$p'` span is pre-existing behaviour and untested until
# now. Asserted on its own so a change that started shipping the frontmatter is
# reported as that, rather than as a byte mismatch in the row above.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.frontmatter"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
# check_json first, and it is load-bearing rather than symmetry with the other
# rows: the `case` below reports a failure only on a match, so a hook that
# stopped emitting JSON at all would leave $CTX empty, match nothing, and take
# this row green -- the one row whose assertion cannot fail open on its own.
if ! check_json 'frontmatter-dropped'; then fails=1; fi
CTX="$(jq -r '.hookSpecificOutput.additionalContext' <"$SUT_STDOUT" 2>/dev/null || true)"
case "$CTX" in
  *'name: using-dude'*)
    printf 'FAIL frontmatter-dropped: the injected context carries the frontmatter\n'
    fails=1
    ;;
esac
row_done 'frontmatter-dropped' "$fails"

# ---- the install path is named ------------------------------------------
#
# The defect this whole change exists for: two installs of dude both run their
# own copy of this hook, and two near-identical blocks with nothing naming
# their tree let a verifier read "the change is in" from one block and "nothing
# was truncated" from the other, and report a session that verified neither.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.named"
build_tree "$ROOT"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'names-the-install-path'; then fails=1; fi
if ! check_context_has 'names-the-install-path' "from the dude install at ${ROOT}:"; then fails=1; fi
row_done 'names-the-install-path' "$fails"

# ---- a plugin root carrying a quote and a backslash ---------------------
#
# The path reaches the JSON, so it has to go through the same escape the skill
# content does. Unescaped, a single `"` in an install path closes the string
# early and the whole ruleset -- not merely the path -- stops arriving. Both
# characters are legal in a POSIX filename, so this is reachable, not
# hypothetical.

total=$((total + 1))
stub_dir_new
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
# drops the block, and the hook still exits 0, so neither the ruleset nor the
# read-failure notice arrives and nothing says so.
#
# The path carries every C0 control the escaper has to convert, not a sample of
# them: the conversion spells its codes in octal, and a single mis-numbered
# entry would otherwise ship green.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.ctl"$'\b\f\001\002\003\004\005\006\007\013\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'"end"
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

total=$((total + 1))
stub_dir_new
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

# ---- the skill file cannot be read --------------------------------------
#
# The script's fallback branch. The output still has to be valid JSON: a
# session that lost the rules to a read failure must still be told so, and a
# malformed payload would drop the notice along with the rules.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.noskill"
build_tree "$ROOT"
rm -f -- "${ROOT}/skills/using-dude/SKILL.md"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'missing-skill-file'; then fails=1; fi
if ! check_context_has 'missing-skill-file' \
  "Error reading the using-dude skill at ${ROOT}/skills/using-dude/SKILL.md."; then fails=1; fi
if ! check_context_has 'missing-skill-file' 'are NOT in context'; then fails=1; fi
row_done 'missing-skill-file' "$fails"

# ---- the read failure on a path needing escaping ------------------------
#
# The two escapes meet here: the fallback message embeds the skill file path,
# and the wrapper embeds the plugin root. Either one unescaped breaks the JSON,
# and this is the branch where both appear at once.

total=$((total + 1))
stub_dir_new
ROOT="${HARNESS_TMP}/tree.q\"uote\\noskill"
build_tree "$ROOT"
rm -f -- "${ROOT}/skills/using-dude/SKILL.md"
run_sut bash "${ROOT}/hooks/session-start"
fails=0
if ! check_json 'read-failure-names-the-path'; then fails=1; fi
if ! check_context_has 'read-failure-names-the-path' "from the dude install at ${ROOT}:"; then fails=1; fi
if ! check_context_has 'read-failure-names-the-path' \
  "Error reading the using-dude skill at ${ROOT}/skills/using-dude/SKILL.md."; then fails=1; fi
row_done 'read-failure-names-the-path' "$fails"

harness_exit "$failed" "$total"
