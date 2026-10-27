#!/usr/bin/env bash
# Tests tests/word-limits.sh — the gate that fails the suite when a
# skills/*/SKILL.md or skills/*/references/*.md exceeds its cap in
# tests/word-limits.txt, or is not listed.
#
# Case 0 runs the gate against the real tree; it is how the gate reaches
# `make test`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tests/word-limits.sh}"

failed=0
total=0

tree_new() {
  local r
  r="$(mktemp -d "${HARNESS_TMP}/tree.XXXXXX")"
  mkdir -p "$r/tests"
  printf '%s\n' "$r"
}

# mk_md <root> <relpath> <nwords>
mk_md() {
  mkdir -p "$1/$(dirname -- "$2")"
  awk -v n="$3" 'BEGIN{for(i=0;i<n;i++)print "w"}' >"$1/$2"
}

# mk_list <root> <line>...
mk_list() {
  local root="$1"
  shift
  printf '%s\n' "$@" >"${root}/tests/word-limits.txt"
}

run_gate() { run_sut bash "$SUT" "$1"; }

# --- case 0: the real tree ----------------------------------------------------
total=$((total + 1))
run_sut bash "$SUT"
if ! check_eq 'real tree: exit' 0 "$SUT_STATUS"; then
  printf 'stdout: %s\nstderr: %s\n' "$(cat "$SUT_STDOUT")" "$(cat "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# --- case 1: at the cap passes; comment and blank lines are accepted ----------
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 10
mk_list "$root" '# a comment' '' '10 skills/a/SKILL.md'
run_gate "$root"
tally check_eq 'at cap: exit' 0 "$SUT_STATUS"

# --- case 2: over the cap fails, naming file, count and limit -----------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 11
mk_list "$root" '10 skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'over cap: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'over cap: message' 'skills/a/SKILL.md: 11 words, limit 10'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 3: an unlisted reference fails --------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 3
mk_md "$root" skills/a/references/x.md 3
mk_list "$root" '3 skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'unlisted: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'unlisted: path' 'skills/a/references/x.md'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 4: a listed file that does not exist fails --------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 3
mk_list "$root" '3 skills/a/SKILL.md' '5 skills/a/references/gone.md'
run_gate "$root"
if ! check_eq 'stale: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'stale: path' 'skills/a/references/gone.md'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 5: a malformed line fails -------------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 3
mk_list "$root" 'abc skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'malformed: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'malformed: message' 'malformed line'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 6: a duplicate entry fails ------------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 3
mk_list "$root" '3 skills/a/SKILL.md' '30 skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'duplicate: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'duplicate: path' 'skills/a/SKILL.md'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 7: an empty enumeration fails ---------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_list "$root" '# empty'
run_gate "$root"
if ! check_eq 'empty enumeration: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'empty enumeration: message' 'no files matched'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 8: a missing list fails ---------------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 3
run_gate "$root"
if ! check_eq 'no list: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no list: message' "cannot read ${root}/tests/word-limits.txt"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 9: every problem is reported, not just the first --------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 11
mk_md "$root" skills/b/SKILL.md 3
mk_list "$root" '10 skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'accumulate: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'accumulate: over cap' 'skills/a/SKILL.md'; then fails_here=1; fi
if ! check_stderr_has 'accumulate: unlisted' 'skills/b/SKILL.md'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 10: a zero cap for an empty file is accepted ------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_md "$root" skills/a/SKILL.md 0
mk_list "$root" '0 skills/a/SKILL.md'
run_gate "$root"
if ! check_eq 'zero cap: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
