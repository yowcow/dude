#!/usr/bin/env bash
# Stale-detection gate for the implement-work Hand off prose contract.
# Single source is skills/pr-to-ready/scripts/ensure-draft-pr.sh's header:
# skills/implement-work/SKILL.md cites it as the single source and restates
# no output literal, so a script output change cannot drift silently past the prose.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SKILL="${REPO_ROOT}/skills/implement-work/SKILL.md"
SCRIPT="${REPO_ROOT}/skills/pr-to-ready/scripts/ensure-draft-pr.sh"

failed=0
total=0

# Row 1: the SKILL cites the script as the single source.
total=$((total + 1))
if grep -qF 'ensure-draft-pr.sh' "$SKILL" && grep -qF 'single source' "$SKILL"; then
  : ok
else
  printf 'FAIL cite: SKILL does not cite ensure-draft-pr.sh as the single source\n'
  failed=$((failed + 1))
fi

# Row 2: the Hand off section restates no output literal (PR forms or STOP).
# Scoped to ## Hand off: STOP <slug> appears legitimately in the Completion
# gate above, so a whole-file grep would fail on text this gate does not own.
total=$((total + 1))
HANDOFF="$(sed -n '/^## Hand off/,/^## Report/p' "$SKILL")"
if printf '%s' "$HANDOFF" | grep -qF -e 'PR <n> found' -e 'PR <n> created' -e 'STOP <slug>'; then
  printf 'FAIL literal: Hand off restates the script output contract\n'
  failed=$((failed + 1))
else
  : ok
fi

# Row 3: the script header owns the contract (all three forms named in comments).
# Header-only: body echos use PR ${NUM} spelling, header uses PR <n>, so grepping
# comment lines distinguishes the contract from the implementation.
total=$((total + 1))
fails_here=0
if ! grep -qF '#   PR <n> found' "$SCRIPT"; then
  printf 'FAIL source: script header does not name the found form\n'
  fails_here=1
fi
if ! grep -qF '#   PR <n> created' "$SCRIPT"; then
  printf 'FAIL source: script header does not name the created form\n'
  fails_here=1
fi
if ! grep -qF '#   STOP <slug>' "$SCRIPT"; then
  printf 'FAIL source: script header does not name the STOP form\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
