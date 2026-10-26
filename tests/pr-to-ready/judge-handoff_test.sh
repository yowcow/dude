#!/usr/bin/env bash
# Stale-detection gate for the pr-to-ready judge handoff prose contract.
# Single source for the check is
# skills/implement-work/scripts/check-judge-records.sh's header:
# skills/pr-to-ready/SKILL.md cites that exact path and restates no output
# literal, so a script output change cannot drift silently past the prose.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SKILL="${REPO_ROOT}/skills/pr-to-ready/SKILL.md"
CHECK='check-judge-records.sh'

failed=0
total=0

# Row 1: the SKILL cites the implement-work judge check by script name and
# names that script's header as the single source. (A repo-root-relative
# path into another skill's scripts/ dir is banned by skill-deps, so the
# citation is by skill and script name, resolved from the worktree root.)
total=$((total + 1))
fails_here=0
if ! grep -qF "$CHECK" "$SKILL"; then
  printf 'FAIL cite: SKILL does not cite %s\n' "$CHECK"
  fails_here=1
fi
if ! grep -qF 'single source' "$SKILL"; then
  printf 'FAIL cite: SKILL names no single source for the judge check\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 2: the 2-1 requesting-code-review call carries the judge record
# directory and round with the none-covers caveat.
total=$((total + 1))
TWO_ONE="$(sed -n '/^### 2-1/,/^### 2-2/p' "$SKILL")"
fails_here=0
if ! grep -qF 'judge record' <<<"$TWO_ONE"; then
  printf 'FAIL carry: 2-1 does not name the judge record\n'
  fails_here=1
fi
if ! grep -qF 'what is missing' <<<"$TWO_ONE"; then
  printf 'FAIL carry: 2-1 names no none-covers caveat\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 3: every 2-3 fix push and the Exit batch run the judge check first.
total=$((total + 1))
TWO_THREE="$(sed -n '/^### 2-3/,/^### Clean/p' "$SKILL")"
fails_here=0
if ! grep -qF "$CHECK" <<<"$TWO_THREE"; then
  printf 'FAIL gate: 2-3 does not run the judge check before pushing\n'
  fails_here=1
fi
EXIT_BATCH="$(sed -n '/^\*\*Exit batch\.\*\*/, /Step 3/p' "$SKILL")"
if ! grep -qF "$CHECK" <<<"$EXIT_BATCH"; then
  printf 'FAIL gate: Exit batch does not run the judge check before pushing\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 4: 0-3 carries no gate handoff check. Numbering always starts at 1 in
# this run's own record dir, so a fresh ATTACHED worktree needs no carry.
total=$((total + 1))
PREP="$(sed -n '/^### 0-3/,/^## Step 1/p' "$SKILL")"
fails_here=0
if ! grep -qF 'ATTACHED' <<<"$PREP"; then
  printf 'FAIL carry: 0-3 names no ATTACHED case\n'
  fails_here=1
fi
if grep -qF 'gate-rounds' <<<"$PREP"; then
  printf 'FAIL carry: 0-3 still reads a gate-rounds value\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 5: the Exit batch marks itself single-shot and the SDD per-task and
# tail reviews are declared out of scope for this wiring.
total=$((total + 1))
fails_here=0
if ! grep -qF 'exit-batch-record.sh' <<<"$EXIT_BATCH"; then
  printf 'FAIL batch: Exit batch does not cite the batch sentinel\n'
  fails_here=1
fi
if ! grep -qF 'ALREADY-BATCHED' <<<"$EXIT_BATCH"; then
  printf 'FAIL batch: Exit batch names no already-batched refusal\n'
  fails_here=1
fi
if ! grep -qF 'subagent-driven-development' "$SKILL"; then
  printf 'FAIL scope: SKILL declares no SDD per-task/tail scope boundary\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 6: 0-1 asks two things with no gate rounds question, and 2-1 numbers
# from 1. The gate handoff input was dropped: no round is carried in.
total=$((total + 1))
ONE="$(sed -n '/^### 0-1/,/^### 0-2/p' "$SKILL")"
fails_here=0
if grep -qF 'gate-rounds' <<<"$ONE"; then
  printf 'FAIL rounds: 0-1 still records a gate-rounds value\n'
  fails_here=1
fi
if ! grep -qF 'two things' <<<"$ONE"; then
  printf 'FAIL rounds: 0-1 does not ask two things\n'
  fails_here=1
fi
if ! grep -qF 'numbering starts at 1' <<<"$TWO_ONE"; then
  printf 'FAIL rounds: 2-1 does not start numbering at 1\n'
  fails_here=1
fi
if grep -qF 'N+1' <<<"$TWO_ONE"; then
  printf 'FAIL rounds: 2-1 still continues gate numbering as N+1\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
