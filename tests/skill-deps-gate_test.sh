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
  for name in alpha-flow beta-flow alpha-entry beta-entry alpha-part beta-part alpha-comp beta-comp alpha-prim beta-prim; do
    mkdir -p "$root/skills/$name"
    printf '# %s\n' "$name" >"$root/skills/$name/SKILL.md"
  done
  printf 'Names alpha-prim.\n' >>"$root/skills/alpha-flow/SKILL.md"
  printf 'Names %s.\n' "$target" >>"$root/skills/$owner/SKILL.md"
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
  {
    printf '%s\n' 'alpha-flow alpha-prim fixture: a downward row, so no table is empty.'
    if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi
  } >"$root/edges"
  printf '%s\n' "$root"
}

run_gate() { run_sut bash "$SUT" "$1" "$1/layers" "$1/edges"; }

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

# --- case 0: the base tree ----------------------------------------------------
root="$(fixture alpha-flow alpha-prim)"
run_gate "$root"
tally check_eq 'base tree: exit' 0 "$SUT_STATUS"
tally check_stdout_lacks 'base tree: line' 'FAIL'

# --- case 1: internal to public, no row ---------------------------------------
root="$(fixture alpha-part alpha-entry)"
run_gate "$root"
tally check_eq 'internal to public, no row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to public, no row: line' "$(internal_needle alpha-part alpha-entry)"

# --- case 2: internal to public, row ------------------------------------------
root="$(fixture alpha-comp alpha-flow 'alpha-comp alpha-flow fixture: an upward row.')"
run_gate "$root"
tally check_eq 'internal to public, row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to public, row: line' "$(internal_needle alpha-comp alpha-flow)"

# --- case 3: internal to own layer, no row ------------------------------------
root="$(fixture alpha-part beta-part)"
run_gate "$root"
tally check_eq 'internal to own layer, no row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to own layer, no row: line' "$(internal_needle alpha-part beta-part)"

# --- case 4: internal to own layer, row ---------------------------------------
root="$(fixture alpha-prim beta-prim 'alpha-prim beta-prim fixture: a lateral row.')"
run_gate "$root"
tally check_eq 'internal to own layer, row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to own layer, row: line' "$(internal_needle alpha-prim beta-prim)"

# --- case 5: internal to upper internal, no row -------------------------------
root="$(fixture alpha-prim alpha-comp)"
run_gate "$root"
tally check_eq 'internal to upper internal, no row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to upper internal, no row: line' "$(internal_needle alpha-prim alpha-comp)"

# --- case 6: internal to upper internal, row ----------------------------------
root="$(fixture alpha-comp alpha-part 'alpha-comp alpha-part fixture: an upward row.')"
run_gate "$root"
tally check_eq 'internal to upper internal, row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal to upper internal, row: line' "$(internal_needle alpha-comp alpha-part)"

# --- case 7: an internal owner's row alone ------------------------------------
root="$(fixture alpha-comp alpha-prim 'alpha-comp alpha-prim fixture: a downward row.')"
run_gate "$root"
tally check_eq 'internal owner row alone: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'internal owner row alone: line' "$(rows_needle alpha-comp)"

# --- case 8: flow lateral, no row ---------------------------------------------
root="$(fixture alpha-flow beta-flow)"
run_gate "$root"
tally check_eq 'flow lateral, no row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'flow lateral, no row: line' "$(up_needle alpha-flow beta-flow)"

# --- case 9: flow lateral, row ------------------------------------------------
root="$(fixture alpha-flow beta-flow 'alpha-flow beta-flow fixture: a lateral row.')"
run_gate "$root"
tally check_eq 'flow lateral, row: exit' 0 "$SUT_STATUS"
tally check_stdout_lacks 'flow lateral, row: line' 'FAIL skill-deps: alpha-flow -> beta-flow'

# --- case 10: entry lateral, no row -------------------------------------------
root="$(fixture alpha-entry beta-entry)"
run_gate "$root"
tally check_eq 'entry lateral, no row: exit' 1 "$SUT_STATUS"
tally check_stdout_has 'entry lateral, no row: line' "$(up_needle alpha-entry beta-entry)"

# --- case 11: entry lateral, row ----------------------------------------------
root="$(fixture alpha-entry beta-entry 'alpha-entry beta-entry fixture: a lateral row.')"
run_gate "$root"
tally check_eq 'entry lateral, row: exit' 0 "$SUT_STATUS"
tally check_stdout_lacks 'entry lateral, row: line' 'FAIL skill-deps: alpha-entry -> beta-entry'

harness_exit "$failed" "$total"
