#!/usr/bin/env bash
# Table test for hooks/pre-invocation: the JSON it prints on stdout, which
# Antigravity reads as PreInvocation injectSteps[].ephemeralMessage.
#
# Every row runs the script inside a synthetic plugin tree rather than this
# repository. The script derives the install path from its own $0, so a copy
# under a directory this file built is what makes that path assertable — and
# the only way to reach a plugin root whose path carries a quote or a backslash.
#
# jq parses the output. The script itself deliberately avoids jq, and that is
# why the test needs one: the property under test is "the bytes this hand-rolled
# escaper emitted are valid JSON", and a hand-rolled checker here would
# re-encode the same belief it is supposed to be checking.
#
# Markers live under ${TMPDIR:-/tmp}/dude-preinvocation/<id>. Sharing an id
# across first-fire rows makes a correct script print {} on the later row.
# second-fire-same-id performs both fires itself so it does not depend on
# another row's marker. TMPDIR is HARNESS_TMP on every row so a marker cannot
# leak to /tmp and turn the next run into a false {}.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/hooks/pre-invocation}"

# Refused rather than skipped. A skip would report this file as green while
# asserting nothing about the escaping, which is the whole point of it.
if ! command -v jq >/dev/null 2>&1; then
  echo "pre-invocation_test: jq is required to parse the hook's output — refusing to run" >&2
  exit 1
fi

failed=0
total=0

# harness run_sut points stdin at /dev/null; this hook reads the PreInvocation
# payload from stdin, so a row that used run_sut would exercise empty-stdin
# every time and a broken extractor would still look like a gate.
run_sut_stdin() {
  local payload="$1"
  shift
  # shellcheck disable=SC2034
  SUT_STATUS=0
  # shellcheck disable=SC2034
  "$@" >"${SUT_STDOUT}" 2>"${SUT_STDERR}" <"$payload" || SUT_STATUS=$?
}

BODY="${HARNESS_TMP}/body.md"
{
  printf '# Using dude\n\n'
  printf 'A quote: "q", a backslash: \\ and a tab:\there.\n'
  printf 'A carriage return follows this word:\r end.\n\n'
  printf '## Last section\n\nThe final line, which truncation would drop.\n'
} >"$BODY"

PAYLOAD="${HARNESS_TMP}/stdin.json"

write_payload() {
  local id="$1" num="${2:-0}"
  printf '{"conversationId":"%s","invocationNum":%s}\n' "$id" "$num" >"$PAYLOAD"
}

build_tree() {
  local root="$1"
  rm -rf -- "$root"
  mkdir -p -- "${root}/hooks" "${root}/skills/using-dude"
  cp -- "$SUT" "${root}/hooks/pre-invocation"
  chmod +x -- "${root}/hooks/pre-invocation"
  { printf -- '---\nname: using-dude\ndescription: fixture\n---\n\n'; cat -- "$BODY"; } \
    >"${root}/skills/using-dude/SKILL.md"
}

check_json() {
  local label="$1"
  if ! jq -e . <"$SUT_STDOUT" >/dev/null 2>&1; then
    printf 'FAIL %s: stdout is not valid JSON\n  got: %s\n' \
      "$label" "$(head -c 400 "$SUT_STDOUT")"
    return 1
  fi
  if ! jq -e '.injectSteps[0].ephemeralMessage | type == "string"' <"$SUT_STDOUT" >/dev/null 2>&1; then
    printf 'FAIL %s: stdout carries no .injectSteps[0].ephemeralMessage string\n' "$label"
    return 1
  fi
}

check_no_inject() {
  local label="$1" n
  if ! jq -e . <"$SUT_STDOUT" >/dev/null 2>&1; then
    printf 'FAIL %s: stdout is not valid JSON\n  got: %s\n' \
      "$label" "$(head -c 400 "$SUT_STDOUT")"
    return 1
  fi
  n="$(jq -r '(.injectSteps // []) | length' <"$SUT_STDOUT")"
  if [ "$n" = 0 ]; then
    return 0
  fi
  printf 'FAIL %s: expected no injectSteps, got: %s\n' \
    "$label" "$(head -c 400 "$SUT_STDOUT")"
  return 1
}

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
  if ! jq -r '.injectSteps[0].ephemeralMessage' <"$SUT_STDOUT" >"$got" 2>/dev/null; then
    printf 'FAIL %s: stdout carries no .injectSteps[0].ephemeralMessage string\n' "$label"
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

check_context_has() {
  local label="$1" want="$2" got
  got="$(jq -r '.injectSteps[0].ephemeralMessage' <"$SUT_STDOUT" 2>/dev/null)" || {
    printf 'FAIL %s: stdout carries no .injectSteps[0].ephemeralMessage string\n' "$label"
    return 1
  }
  case "$got" in
    *"$want"*) return 0 ;;
  esac
  printf 'FAIL %s: the injected context does not carry [%s]\n  got: %s\n' \
    "$label" "$want" "$(printf '%s' "$got" | head -c 400)"
  return 1
}

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

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.plain"
build_tree "$ROOT"
write_payload 'id-plain' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'plain-tree'; then fails=1; fi
if ! check_context 'plain-tree: context' "$ROOT"; then fails=1; fi
row_done 'plain-tree' "$fails"

# ---- the frontmatter is not injected ------------------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.frontmatter"
build_tree "$ROOT"
write_payload 'id-frontmatter' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'frontmatter-dropped'; then fails=1; fi
CTX="$(jq -r '.injectSteps[0].ephemeralMessage' <"$SUT_STDOUT" 2>/dev/null || true)"
case "$CTX" in
  *'name: using-dude'*)
    printf 'FAIL frontmatter-dropped: the injected context carries the frontmatter\n'
    fails=1
    ;;
esac
row_done 'frontmatter-dropped' "$fails"

# ---- second fire of the same id is a no-op ------------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.second"
build_tree "$ROOT"
write_payload 'id-second' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_eq 'second-fire-same-id: first exit' 0 "$SUT_STATUS"; then fails=1; fi
if ! check_json 'second-fire-same-id: first'; then fails=1; fi
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
if ! check_no_inject 'second-fire-same-id: second'; then fails=1; fi
row_done 'second-fire-same-id' "$fails"

# ---- invocationNum == 1 still injects on a fresh id ---------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.nonzero"
build_tree "$ROOT"
write_payload 'id-nonzero' 1
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'nonzero-invocationnum-injects'; then fails=1; fi
if ! check_context 'nonzero-invocationnum-injects: context' "$ROOT"; then fails=1; fi
row_done 'nonzero-invocationnum-injects' "$fails"

# ---- a different id is a first fire of its own --------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.diff"
build_tree "$ROOT"
write_payload 'id-diff-a' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_eq 'different-id: first exit' 0 "$SUT_STATUS"; then fails=1; fi
if ! check_json 'different-id: a'; then fails=1; fi
write_payload 'id-diff-b' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
if ! check_json 'different-id: b'; then fails=1; fi
row_done 'different-id' "$fails"

# ---- conversationId missing ---------------------------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.missing"
build_tree "$ROOT"
printf '{"invocationNum":0}\n' >"$PAYLOAD"
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_no_inject 'missing-conversation-id'; then fails=1; fi
row_done 'missing-conversation-id' "$fails"

# ---- empty stdin --------------------------------------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.empty"
build_tree "$ROOT"
: >"$PAYLOAD"
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_no_inject 'empty-stdin'; then fails=1; fi
row_done 'empty-stdin' "$fails"

# ---- a slash in the id is not a marker path -----------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.slash"
build_tree "$ROOT"
write_payload '../x' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_no_inject 'slash-in-id'; then fails=1; fi
row_done 'slash-in-id' "$fails"

# ---- a plugin root carrying a quote and a backslash ---------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.q\"uote\\slash"
build_tree "$ROOT"
write_payload 'id-weird' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'weird-path-json-intact'; then fails=1; fi
if ! check_context 'weird-path-json-intact: context' "$ROOT"; then fails=1; fi
row_done 'weird-path-json-intact' "$fails"

# ---- a plugin root carrying C0 control characters -----------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.ctl"$'\b\f\001\002\003\004\005\006\007\013\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'"end"
build_tree "$ROOT"
write_payload 'id-ctl' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'control-chars-json-intact'; then fails=1; fi
if ! check_context 'control-chars-json-intact: context' "$ROOT"; then fails=1; fi
row_done 'control-chars-json-intact' "$fails"

# ---- CDPATH must not redirect the derivation ----------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.cdpath"
build_tree "$ROOT"
DECOY="${HARNESS_TMP}/decoy.cdpath"
rm -rf -- "$DECOY"
mkdir -p -- "${DECOY}/hooks"
write_payload 'id-cdpath' 0
cd "$ROOT"
CDPATH="$DECOY" run_sut_stdin "$PAYLOAD" bash hooks/pre-invocation
cd "$REPO_ROOT"
fails=0
if ! check_json 'cdpath-ignored'; then fails=1; fi
if ! check_context 'cdpath-ignored: context' "$ROOT"; then fails=1; fi
row_done 'cdpath-ignored' "$fails"

# ---- the skill file cannot be read --------------------------------------

total=$((total + 1))
stub_dir_new
export TMPDIR="$HARNESS_TMP"
ROOT="${HARNESS_TMP}/tree.noskill"
build_tree "$ROOT"
rm -f -- "${ROOT}/skills/using-dude/SKILL.md"
write_payload 'id-noskill' 0
run_sut_stdin "$PAYLOAD" bash "${ROOT}/hooks/pre-invocation"
fails=0
if ! check_json 'missing-skill-file'; then fails=1; fi
if ! check_context_has 'missing-skill-file' \
  "Error reading the using-dude skill at ${ROOT}/skills/using-dude/SKILL.md."; then fails=1; fi
if ! check_context_has 'missing-skill-file' 'are NOT in context'; then fails=1; fi
row_done 'missing-skill-file' "$fails"

harness_exit "$failed" "$total"
