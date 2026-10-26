#!/usr/bin/env bash
# Stale-detection gate for the implement-work Hand off prose contract.
# Single source is tools/ensure-draft-pr.sh's header:
# skills/implement-work/SKILL.md cites it as the single source and restates
# no output literal, so a script output change cannot drift silently past the prose.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SKILL="${REPO_ROOT}/skills/implement-work/SKILL.md"
SCRIPT="${REPO_ROOT}/tools/ensure-draft-pr.sh"

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

# Row 2: the range the next row inspects is the section it names. An empty
# extraction — either heading renamed — made the negative check below pass
# vacuously, and a range running to EOF would inspect text this gate does not own.
total=$((total + 1))
HANDOFF="$(sed -n '/^## Hand off/,/^## Report/p' "$SKILL")"
fails_here=0
if ! check_eq 'scope: the section starts at ## Hand off' \
  '## Hand off' "${HANDOFF%%$'\n'*}"; then fails_here=1; fi
if ! check_eq 'scope: the section ends at ## Report' \
  '## Report' "${HANDOFF##*$'\n'}"; then fails_here=1; fi
# Both headings in place still says nothing about the body between them: with
# the text emptied out, row 3's negative grep matches nothing and goes green —
# the same "a negative assertion passes on nothing" hole this PR closes.
# Captured before the match: `grep -q` exits on its first match, and a SIGPIPE
# into `sed` fails the pipeline under `pipefail` — the hazard tests/lint.sh
# records — turning a present body into a false red.
handoff_body="$(printf '%s\n' "$HANDOFF" | sed '1d;$d')"
if ! grep -q '[^[:space:]]' <<<"$handoff_body"; then
  printf 'FAIL scope: ## Hand off has no body\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 3: the Hand off section restates no output literal (PR forms or STOP).
# Scoped to ## Hand off: STOP <slug> appears legitimately in the Completion
# gate above, so a whole-file grep would fail on text this gate does not own.
total=$((total + 1))
if grep -qF -e 'PR <n> found' -e 'PR <n> created' -e 'STOP <slug>' <<<"$HANDOFF"; then
  printf 'FAIL literal: Hand off restates the script output contract\n'
  failed=$((failed + 1))
else
  : ok
fi

# Row 4: the script header owns the contract (all three forms named in comments).
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

# Row 5: Hand off cites check-judge-records.sh as the single source and
# routes any non-OK line back to the completion gate's step 1.
total=$((total + 1))
fails_here=0
if ! grep -qF 'check-judge-records.sh' <<<"$HANDOFF"; then
  printf 'FAIL judge-cite: Hand off does not cite check-judge-records.sh\n'
  fails_here=1
fi
if ! grep -qF 'single source' <<<"$HANDOFF"; then
  printf 'FAIL judge-cite: Hand off does not name the single source\n'
  fails_here=1
fi
if ! grep -qF "completion gate's step 1" <<<"$HANDOFF"; then
  printf 'FAIL judge-route: Hand off does not route back to the completion gate step 1\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Row 6: the Hand off judge prose restates no judge output literal.
# Scoped to ## Hand off like Row 3; OK already appears in the
# tree-records line above so only the judge-specific forms are checked.
total=$((total + 1))
if grep -qF -e 'MISSING' -e 'DOUBLE' -e 'IDENTITY' -e 'GAP' -e 'DIRTY' -e 'UNCOVERED' <<<"$HANDOFF"; then
  printf 'FAIL judge-literal: Hand off restates the judge output contract\n'
  failed=$((failed + 1))
else
  : ok
fi

# Row 7: vet-code names recording the judge-findings return whole and
# unreworded into judge-verdict-<round>.md with the input file's name.
total=$((total + 1))
VETCODE="${REPO_ROOT}/skills/vet-code/SKILL.md"
fails_here=0
if ! grep -qF 'judge-verdict-' "$VETCODE"; then
  printf 'FAIL verdict-cite: vet-code does not name judge-verdict-\n'
  fails_here=1
fi
if ! grep -qF 'whole and unreworded' "$VETCODE"; then
  printf 'FAIL verdict-cite: vet-code does not say whole and unreworded\n'
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
