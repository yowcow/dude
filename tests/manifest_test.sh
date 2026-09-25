#!/usr/bin/env bash
# Tests the shared manifest gate: every validator runs in order and the first
# failure stops the gate before later validators can hide it.
# The version check covers six fields; `.agents` is a versionless mirror.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tests/manifest.sh}"
failed=0
total=0
stub_bin="${HARNESS_TMP}/bin"
mkdir -p "$stub_bin"

PYTHON3_REAL="$(command -v python3)"
export PYTHON3_REAL

cat >"${stub_bin}/claude" <<'SH'
#!/usr/bin/env bash
{ printf 'claude'; printf ' %s' "$@"; printf '\n'; } >>"$CALLS"
exit "$CLAUDE_STATUS"
SH

cat >"${stub_bin}/muse" <<'SH'
#!/usr/bin/env bash
{ printf 'muse'; printf ' %s' "$@"; printf '\n'; } >>"$CALLS"
exit "$MUSE_STATUS"
SH

cat >"${stub_bin}/python3" <<'SH'
#!/usr/bin/env bash
{ printf 'python3'; printf ' %s' "$@"; printf '\n'; } >>"$CALLS"
if [ "$1" = '-m' ]; then exit "$JSON_STATUS"; fi
if [ "$1" = '-' ]; then exec "$PYTHON3_REAL" -; fi
exit "$CODEX_STATUS"
SH

chmod +x "${stub_bin}/claude" "${stub_bin}/muse" "${stub_bin}/python3"

run_manifest() {
  : >"${HARNESS_TMP}/calls"
  run_sut env \
    "HOME=${HARNESS_TMP}/home" \
    "PATH=${stub_bin}:${PATH}" \
    "CALLS=${HARNESS_TMP}/calls" \
    "CLAUDE_STATUS=${1:-0}" \
    "CODEX_STATUS=${2:-0}" \
    "MUSE_STATUS=${3:-0}" \
    "JSON_STATUS=${4:-0}" \
    bash "$SUT"
}

want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py ." \
  'muse plugins validate .' \
  'python3 -m json.tool .agents/plugins/marketplace.json' \
  'python3 -m json.tool package.json' \
  'python3 -m json.tool hooks/hooks.json' \
  'python3 -m json.tool .muse-plugin/plugin.json' \
  'python3 -m json.tool .muse-plugin/marketplace.json' \
  'python3 -')"

total=$((total + 1))
fails_here=0
run_manifest 0 0 0 0
if ! check_eq 'green exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'green calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 1 0 0 0
if ! check_eq 'Claude failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'Claude failure calls' 'claude plugin validate .' "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 0 1 0 0
want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .")"
if ! check_eq 'Codex failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'Codex failure calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 0 0 1 0
want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py ." \
  'muse plugins validate .')"
if ! check_eq 'Muse failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'Muse failure calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 0 0 0 1
want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py ." \
  'muse plugins validate .' \
  'python3 -m json.tool .agents/plugins/marketplace.json')"
if ! check_eq 'JSON failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'JSON failure calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

make_fixture() {
  root="$1"
  pkg_ver="$2"
  # No `.agents` fixture: that mirror carries no `version`, syntax-checked only.
  mkdir -p "$root/.claude-plugin" "$root/.codex-plugin" "$root/.muse-plugin"
  printf '{\n  "name": "dude",\n  "version": "1.0.0"\n}\n' >"$root/.claude-plugin/plugin.json"
  printf '{\n  "plugins": [\n    {\n      "name": "dude",\n      "version": "1.0.0"\n    }\n  ]\n}\n' >"$root/.claude-plugin/marketplace.json"
  printf '{\n  "name": "dude",\n  "version": "1.0.0"\n}\n' >"$root/.codex-plugin/plugin.json"
  printf '{\n  "name": "dude",\n  "version": "1.0.0"\n}\n' >"$root/.muse-plugin/plugin.json"
  printf '{\n  "plugins": [\n    {\n      "name": "dude",\n      "version": "1.0.0"\n    }\n  ]\n}\n' >"$root/.muse-plugin/marketplace.json"
  printf '{\n  "name": "dude",\n  "version": "%s"\n}\n' "$pkg_ver" >"$root/package.json"
}

run_fixture() {
  : >"${HARNESS_TMP}/calls"
  run_sut env \
    "HOME=${HARNESS_TMP}/home" \
    "PATH=${stub_bin}:${PATH}" \
    "CALLS=${HARNESS_TMP}/calls" \
    "CLAUDE_STATUS=0" \
    "CODEX_STATUS=0" \
    "MUSE_STATUS=0" \
    "JSON_STATUS=0" \
    "MANIFEST_ROOT=$1" \
    bash "$SUT"
}

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/aligned" "1.0.0"
run_fixture "${HARNESS_TMP}/aligned"
if ! check_eq 'aligned versions exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/drifted" "9.9.9"
run_fixture "${HARNESS_TMP}/drifted"
if ! check_eq 'drifted versions exit' 1 "$SUT_STATUS"; then fails_here=1; fi
for want in '.claude-plugin/plugin.json: 1.0.0' '.claude-plugin/marketplace.json: 1.0.0' '.codex-plugin/plugin.json: 1.0.0' '.muse-plugin/plugin.json: 1.0.0' '.muse-plugin/marketplace.json: 1.0.0' 'package.json: 9.9.9'; do
  if ! grep -Fq "$want" "$SUT_STDERR"; then
    printf 'FAIL drifted versions stderr: missing [%s]\n' "$want"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/malformed" "1.0.0"
printf '{\n  "name": "dude",\n  "version": []\n}\n' >"${HARNESS_TMP}/malformed/package.json"
run_fixture "${HARNESS_TMP}/malformed"
if ! check_eq 'malformed version exit' 1 "$SUT_STATUS"; then fails_here=1; fi
for want in '.claude-plugin/plugin.json: 1.0.0' '.claude-plugin/marketplace.json: 1.0.0' '.codex-plugin/plugin.json: 1.0.0' '.muse-plugin/plugin.json: 1.0.0' '.muse-plugin/marketplace.json: 1.0.0' 'package.json: []'; do
  if ! grep -Fq "$want" "$SUT_STDERR"; then
    printf 'FAIL malformed version stderr: missing [%s]\n' "$want"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/noversion" "1.0.0"
printf '{\n  "name": "dude"\n}\n' >"${HARNESS_TMP}/noversion/package.json"
run_fixture "${HARNESS_TMP}/noversion"
if ! check_eq 'missing version exit' 1 "$SUT_STATUS"; then fails_here=1; fi
for want in '.claude-plugin/plugin.json: 1.0.0' '.claude-plugin/marketplace.json: 1.0.0' '.codex-plugin/plugin.json: 1.0.0' '.muse-plugin/plugin.json: 1.0.0' '.muse-plugin/marketplace.json: 1.0.0' 'package.json: None'; do
  if ! grep -Fq "$want" "$SUT_STDERR"; then
    printf 'FAIL missing version stderr: missing [%s]\n' "$want"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
