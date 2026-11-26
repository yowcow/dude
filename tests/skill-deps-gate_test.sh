#!/usr/bin/env bash
# Tests tests/skill-deps_test.sh through its table arguments over a synthetic tree.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tests/skill-deps_test.sh}"

failed=0
total=0

# fixture <owner> <target> [<edge-row>...]; prints the new root.
fixture() {
  local owner="$1" target="$2" root name
  shift 2
  root="$(mktemp -d "${HARNESS_TMP}/tree.XXXXXX")"
  cat >"$root/layers" <<'LAYERS'
alpha-flow flow
beta-flow flow
alpha-entry entry
beta-entry entry
alpha-part part
beta-part part
alpha-comp component
beta-comp component
alpha-prim primitive
beta-prim primitive
LAYERS
  while read -r name _; do
    mkdir -p "$root/skills/$name"
    printf '# %s\n' "$name" >"$root/skills/$name/SKILL.md"
  done <"$root/layers"
  printf 'Names alpha-prim.\n' >>"$root/skills/alpha-flow/SKILL.md"
  printf 'Names %s.\n' "$target" >>"$root/skills/$owner/SKILL.md"
  printf '%s\n' "$@" >"$root/edges"
  printf '%s\n' "$root"
}

# shellcheck disable=SC2317,SC2329 # reached only via tally
check_stdout_has() {
  if grep -qF -- "$2" "$SUT_STDOUT"; then return 0; fi
  printf 'FAIL %s: stdout does not contain [%s]\n  got: %s\n' "$1" "$2" "$(head -c 600 "$SUT_STDOUT")"
  return 1
}

# shellcheck disable=SC2317,SC2329 # reached only via tally
check_stdout_lacks() {
  if ! grep -qF -- "$2" "$SUT_STDOUT"; then return 0; fi
  printf 'FAIL %s: stdout contains [%s]\n  got: %s\n' "$1" "$2" "$(head -c 600 "$SUT_STDOUT")"
  return 1
}

internal_needle() { printf 'FAIL skill-deps: %s -> %s: internal %s names its own layer or above' "$1" "$2" "$1"; }
up_needle() { printf 'FAIL skill-deps: %s -> %s points up or sideways and has no row in EDGES' "$1" "$2"; }
rows_needle() { printf 'FAIL skill-deps: EDGES row owned by internal %s: an internal skill has no rows' "$1"; }
stale_needle() { printf 'FAIL skill-deps: EDGES row %s -> %s is stale' "$1" "$2"; }

# gate_row <label> <want-exit> <stdout-check> <needle> <owner> <target> [<edge-row>...]
gate_row() {
  local label="$1" want="$2" check="$3" needle="$4" root
  shift 4
  root="$(fixture "$@")"
  run_sut bash "$SUT" "$root" "$root/layers" "$root/edges"
  tally check_eq "${label}: exit" "$want" "$SUT_STATUS"
  tally "$check" "${label}: line" "$needle"
}

gate_row 'base tree, empty EDGES' 0 check_stdout_lacks 'FAIL' \
  alpha-flow alpha-prim
gate_row 'internal to public, no row' 1 check_stdout_has "$(internal_needle alpha-part alpha-entry)" \
  alpha-part alpha-entry
gate_row 'internal to public, row' 1 check_stdout_has "$(internal_needle alpha-comp alpha-flow)" \
  alpha-comp alpha-flow 'alpha-comp alpha-flow fixture: an upward row.'
gate_row 'internal to own layer, no row' 1 check_stdout_has "$(internal_needle alpha-part beta-part)" \
  alpha-part beta-part
gate_row 'internal to own layer, row' 1 check_stdout_has "$(internal_needle alpha-prim beta-prim)" \
  alpha-prim beta-prim 'alpha-prim beta-prim fixture: a lateral row.'
gate_row 'internal to upper internal, no row' 1 check_stdout_has "$(internal_needle alpha-prim alpha-comp)" \
  alpha-prim alpha-comp
gate_row 'internal to upper internal, row' 1 check_stdout_has "$(internal_needle alpha-comp alpha-part)" \
  alpha-comp alpha-part 'alpha-comp alpha-part fixture: an upward row.'
gate_row 'internal owner row alone' 1 check_stdout_has "$(rows_needle alpha-comp)" \
  alpha-comp alpha-prim 'alpha-comp alpha-prim fixture: a downward row.'
gate_row 'stale row' 1 check_stdout_has "$(stale_needle beta-flow alpha-prim)" \
  alpha-flow alpha-prim 'beta-flow alpha-prim fixture: a row with no mention.'
gate_row 'flow lateral, no row' 1 check_stdout_has "$(up_needle alpha-flow beta-flow)" \
  alpha-flow beta-flow
gate_row 'flow lateral, row' 0 check_stdout_lacks 'FAIL skill-deps: alpha-flow -> beta-flow' \
  alpha-flow beta-flow 'alpha-flow beta-flow fixture: a lateral row.'
gate_row 'entry lateral, no row' 1 check_stdout_has "$(up_needle alpha-entry beta-entry)" \
  alpha-entry beta-entry
gate_row 'entry lateral, row' 0 check_stdout_lacks 'FAIL skill-deps: alpha-entry -> beta-entry' \
  alpha-entry beta-entry 'alpha-entry beta-entry fixture: a lateral row.'

harness_exit "$failed" "$total"
