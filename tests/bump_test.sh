#!/usr/bin/env bash
# Tests scripts/bump.sh: a trial bump rewrites the four version fields while
# leaving the rest of each file alone, and a failure leaves the tree untouched.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/scripts/bump.sh}"
failed=0
total=0

make_fixture() {
  root="$1"
  ver="$2"
  mkdir -p "$root/.claude-plugin" "$root/.codex-plugin"
  printf '{\n  "name": "dude",\n  "version": "%s"\n}\n' "$ver" >"$root/.claude-plugin/plugin.json"
  printf '{\n  "plugins": [\n    {\n      "name": "dude",\n      "version": "%s"\n    }\n  ]\n}\n' "$ver" >"$root/.claude-plugin/marketplace.json"
  printf '{\n  "name": "dude",\n  "version": "%s"\n}\n' "$ver" >"$root/.codex-plugin/plugin.json"
  printf '{\n  "name": "dude",\n  "version": "%s"\n}\n' "$ver" >"$root/package.json"
}

version_line() {
  grep -o '"version": "[^"]*"' "$1"
}

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/bump" "1.0.0"
run_sut env "BUMP_ROOT=${HARNESS_TMP}/bump" bash "$SUT" "2.0.0"
if ! check_eq 'trial bump exit' 0 "$SUT_STATUS"; then fails_here=1; fi
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json package.json; do
  if ! check_eq "trial bump $f" '"version": "2.0.0"' "$(version_line "${HARNESS_TMP}/bump/$f")"; then fails_here=1; fi
  if ! grep -q '"name": "dude"' "${HARNESS_TMP}/bump/$f"; then
    printf 'FAIL trial bump %s: surrounding content changed\n' "$f"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/tight" "1.0.0"
printf '{\n  "name": "dude",\n  "version":"1.0.0"\n}\n' >"${HARNESS_TMP}/tight/package.json"
run_sut env "BUMP_ROOT=${HARNESS_TMP}/tight" bash "$SUT" "2.0.0"
if ! check_eq 'tight whitespace exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'tight whitespace version' '"version": "2.0.0"' "$(version_line "${HARNESS_TMP}/tight/package.json")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/missing" "1.0.0"
printf '{\n  "name": "dude"\n}\n' >"${HARNESS_TMP}/missing/package.json"
run_sut env "BUMP_ROOT=${HARNESS_TMP}/missing" bash "$SUT" "2.0.0"
if [ "$SUT_STATUS" -eq 0 ]; then
  printf 'FAIL missing field exit: want non-zero, got 0\n'
  fails_here=1
fi
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json; do
  if ! check_eq "missing field untouched $f" '"version": "1.0.0"' "$(version_line "${HARNESS_TMP}/missing/$f")"; then fails_here=1; fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/dup" "1.0.0"
printf '{\n  "plugins": [\n    {\n      "name": "dude",\n      "version": "1.0.0"\n    },\n    {\n      "name": "other",\n      "version": "1.0.0"\n    }\n  ]\n}\n' >"${HARNESS_TMP}/dup/.claude-plugin/marketplace.json"
run_sut env "BUMP_ROOT=${HARNESS_TMP}/dup" bash "$SUT" "2.0.0"
if [ "$SUT_STATUS" -eq 0 ]; then
  printf 'FAIL duplicate field exit: want non-zero, got 0\n'
  fails_here=1
fi
if ! check_eq 'duplicate field untouched' '"version": "1.0.0"' "$(version_line "${HARNESS_TMP}/dup/.claude-plugin/plugin.json")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
make_fixture "${HARNESS_TMP}/badver" "1.0.0"
run_sut env "BUMP_ROOT=${HARNESS_TMP}/badver" bash "$SUT" '1.2.3"broken'
if [ "$SUT_STATUS" -eq 0 ]; then
  printf 'FAIL unsafe version exit: want non-zero, got 0\n'
  fails_here=1
fi
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json package.json; do
  if ! check_eq "unsafe version untouched $f" '"version": "1.0.0"' "$(version_line "${HARNESS_TMP}/badver/$f")"; then fails_here=1; fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
for v in 1.2.3-alpha 1.2.3+build 0.1.0; do
  root="${HARNESS_TMP}/semver-ok-${v}"
  make_fixture "$root" "1.0.0"
  run_sut env "BUMP_ROOT=${root}" bash "$SUT" "$v"
  if [ "$SUT_STATUS" -ne 0 ]; then
    printf 'FAIL semver accept %s: exit %s\n' "$v" "$SUT_STATUS"
    fails_here=1
  fi
  if ! check_eq "semver accept $v" "\"version\": \"$v\"" "$(version_line "$root/package.json")"; then fails_here=1; fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
for v in 1.2 01.2.3 1..2; do
  root="${HARNESS_TMP}/semver-bad-${v}"
  make_fixture "$root" "1.0.0"
  run_sut env "BUMP_ROOT=${root}" bash "$SUT" "$v"
  if [ "$SUT_STATUS" -eq 0 ]; then
    printf 'FAIL semver reject %s: exit 0\n' "$v"
    fails_here=1
  fi
  if ! check_eq "semver reject untouched $v" '"version": "1.0.0"' "$(version_line "$root/package.json")"; then fails_here=1; fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

total=$((total + 1))
fails_here=0
root="${HARNESS_TMP}/make-inject"
make_fixture "$root" "1.0.0"
run_sut env "BUMP_ROOT=${root}" make -C "$root" -f "${REPO_ROOT}/Makefile" bump 'VERSION=1.2.3"; touch canary #'
if [ "$SUT_STATUS" -eq 0 ]; then
  printf 'FAIL make injection exit: want non-zero, got 0\n'
  fails_here=1
fi
if [ -e "$root/canary" ]; then
  printf 'FAIL make injection: canary was created\n'
  fails_here=1
fi
if ! check_eq 'make injection untouched' '"version": "1.0.0"' "$(version_line "$root/package.json")"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
