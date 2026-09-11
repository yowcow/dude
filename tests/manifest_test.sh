#!/usr/bin/env bash
# Tests the shared manifest gate: every validator runs in order and the first
# failure stops the gate before later validators can hide it.
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

cat >"${stub_bin}/claude" <<'SH'
#!/usr/bin/env bash
{ printf 'claude'; printf ' %s' "$@"; printf '\n'; } >>"$CALLS"
exit "$CLAUDE_STATUS"
SH

cat >"${stub_bin}/python3" <<'SH'
#!/usr/bin/env bash
{ printf 'python3'; printf ' %s' "$@"; printf '\n'; } >>"$CALLS"
if [ "$1" = '-m' ]; then exit "$JSON_STATUS"; fi
exit "$CODEX_STATUS"
SH

chmod +x "${stub_bin}/claude" "${stub_bin}/python3"

run_manifest() {
  : >"${HARNESS_TMP}/calls"
  run_sut env \
    "HOME=${HARNESS_TMP}/home" \
    "PATH=${stub_bin}:${PATH}" \
    "CALLS=${HARNESS_TMP}/calls" \
    "CLAUDE_STATUS=${1:-0}" \
    "CODEX_STATUS=${2:-0}" \
    "JSON_STATUS=${3:-0}" \
    bash "$SUT"
}

want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py ." \
  'python3 -m json.tool .agents/plugins/marketplace.json' \
  'python3 -m json.tool package.json' \
  'python3 -m json.tool hooks/hooks.json')"

total=$((total + 1))
fails_here=0
run_manifest
if ! check_eq 'green exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'green calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 1 0 0
if ! check_eq 'Claude failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'Claude failure calls' 'claude plugin validate .' "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 0 1 0
want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .")"
if ! check_eq 'Codex failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'Codex failure calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
run_manifest 0 0 1
want_calls="$(printf '%s\n' \
  'claude plugin validate .' \
  "python3 ${HARNESS_TMP}/home/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py ." \
  'python3 -m json.tool .agents/plugins/marketplace.json')"
if ! check_eq 'JSON failure exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'JSON failure calls' "$want_calls" "$(cat "${HARNESS_TMP}/calls")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
