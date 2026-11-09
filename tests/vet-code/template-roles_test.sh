#!/usr/bin/env bash
# Gate for vet-code's dependence on the superpowers template: it leans on the
# template's placeholders, its Critical / Important / Minor severities, and
# the role of each part, never on body section names or output headings. A
# rename upstream would otherwise empty the candidate list silently.
# `Declined to judge` stays as vet-code's own output term; only its use as a
# template section is barred.
#
# RED: SKILL=<pre-fix SKILL.md> bash tests/vet-code/template-roles_test.sh (run.sh takes only a script as SUT)
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SKILL="${SKILL:-${REPO_ROOT}/skills/vet-code/SKILL.md}"

failed=0
total=0

# Captured before matching: a negative grep on an empty extraction passes on
# nothing, so the Output heading is checked first.
OUT="$(sed -n '/^## Output/,$p' "$SKILL")"

total=$((total + 1))
if ! check_eq 'scope: output starts at its heading' \
  '## Output' "${OUT%%$'\n'*}"; then failed=$((failed + 1)); fi

# No rule names a part of the template by its wording.
total=$((total + 1))
fails_here=0
for needle in 'vision document' 'Git Range to Review' 'Hand every Declined to judge line' \
  'Issues finding' 'All tests passing' 'Write never a `Declined to judge`'; do
  if grep -qF -- "$needle" "$SKILL"; then
    printf 'FAIL names: template wording remains: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# No output heading routes anything.
total=$((total + 1))
fails_here=0
for needle in 'Strengths' 'Recommendations' 'Assessment'; do
  if grep -qF -- "$needle" "$SKILL"; then
    printf 'FAIL headings: SKILL routes by heading: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Classification by context, and the role-based range instruction.
total=$((total + 1))
fails_here=0
for needle in 'decide what is a candidate by context, never by the heading' \
  'wherever the reviewer wrote it' \
  'set aside as outside the plan or spec' \
  'built on `BASE_SHA` and `HEAD_SHA` does not apply'; do
  if ! grep -qF -- "$needle" "$SKILL"; then
    printf 'FAIL context: SKILL lacks: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Output returns every candidate, with no new section.
total=$((total + 1))
fails_here=0
for needle in 'Return every candidate handed to `judge-findings`, wherever in the output it came from' \
  'Open no new output section' \
  'Treat praise as not a finding' \
  'Treat an overall merge verdict, even a positive one, as not this skill declaring the code clean' \
  'with the severity `judge-findings` gave it' \
  'belongs in the finding list, `reject` included' \
  'goes back as a `Declined to judge` line'; do
  if ! grep -qF -- "$needle" <<<"$OUT"; then
    printf 'FAIL output: Output lacks: %s\n' "$needle"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
