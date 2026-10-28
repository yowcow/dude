#!/usr/bin/env bash
# Gate for vet-code's Reviewer prompt: the dispatched prompt is the
# superpowers template verbatim with its four placeholders filled, and every
# extra the reviewer needs rides inside PLAN_OR_REQUIREMENTS. A sentence that
# edits the template body (replace, drop, append after) silently hands the
# reviewer a prompt superpowers never wrote.
#
# RED: SKILL=<pre-fix SKILL.md> bash tests/vet-code/reviewer-prompt_test.sh (run.sh takes only a script as SUT)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SKILL="${SKILL:-${REPO_ROOT}/skills/vet-code/SKILL.md}"

failed=0
total=0

# Captured before matching: a negative grep on an empty extraction passes on
# nothing, so the section's headings are checked first.
SECTION="$(sed -n '/^## Reviewer prompt/,/^## Output/p' "$SKILL")"
# The part that fills PLAN_OR_REQUIREMENTS: from its paragraph to the section end.
REQS="$(printf '%s\n' "$SECTION" | sed -n '/^\*\*The requirements\*\*/,$p')"

total=$((total + 1))
fails_here=0
if ! check_eq 'scope: the section starts at ## Reviewer prompt' \
  '## Reviewer prompt' "${SECTION%%$'\n'*}"; then fails_here=1; fi
if ! check_eq 'scope: the section ends at ## Output' \
  '## Output' "${SECTION##*$'\n'}"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# The template is dispatched whole, placeholders filled, SHAs never invented.
total=$((total + 1))
fails_here=0
for needle in 'template verbatim with its four placeholders filled' \
  "fill both \`BASE_SHA\` and \`HEAD_SHA\` with \`N/A\`"; do
  if ! grep -qF -- "$needle" <<<"$SECTION"; then
    printf 'FAIL verbatim: section lacks: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# No sentence edits the template body.
total=$((total + 1))
fails_here=0
for needle in 'verbatim except' 'replacing the Git Range' 'drop the template' \
  'after the template' 'appends after it'; do
  if grep -qiF -- "$needle" <<<"$SECTION"; then
    printf 'FAIL deviation: template-editing wording remains: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# The eight extras, each inside the PLAN_OR_REQUIREMENTS paragraph's own list.
total=$((total + 1))
fails_here=0
for needle in '**Range shape**' '**Worktree**' '**Read-root**' '**Ledger rows**' \
  '**Purpose**' '**Earlier rounds**' '**Confine**' '**Tests**' \
  'does not apply and is to be ignored' 'these win'; do
  if ! grep -qF -- "$needle" <<<"$REQS"; then
    printf 'FAIL extras: PLAN_OR_REQUIREMENTS lacks: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
