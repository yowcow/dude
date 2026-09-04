#!/usr/bin/env bash
# Report a PR's base drift and mergeability. Read-only — it measures, it
# never retargets or pushes anything.
#
# The mergeability field read here is `mergeable` (MERGEABLE / CONFLICTING /
# UNKNOWN), never the sibling field GitHub also exposes on the same query.
# That sibling varies with the caller's own push permission rather than with
# anything about the branch, so a gate keyed on it stops PRs for a reason
# having nothing to do with their content — see ../references/gh-mechanics.md,
# "## Mergeability" (the section warning against that field) for the measured
# case. `UNKNOWN` is not a third verdict, only "not computed yet": it gets a
# short, bounded re-read, per the same file's section on why that re-read is
# bounded and what backs it up. An `UNKNOWN` that outlasts the re-read is
# printed as-is — `pr-to-ready/SKILL.md` Step 1-4 already treats it as the
# same terminal state as `CONFLICTING`, so nothing here resolves it further.
# Usage: check-pr-state.sh <owner> <repo> <pr-number> <expected-base>
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <expected-base>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PR="$3"
EXPECTED_BASE="$4"

# Bounded re-read for `mergeable == UNKNOWN`. GitHub computes it lazily in a
# background job that finishes in seconds, so this bound is deliberately
# short and has nothing in common with the review-wait timeouts elsewhere in
# this skill — polling for a background computation is not polling for a
# person. 5 attempts * 3s = ~15s total.
MERGEABLE_RETRY_MAX=5
MERGEABLE_RETRY_SECONDS=3

if ! PR_INFO="$(gh pr view "$PR" -R "${OWNER}/${REPO}" \
  --json baseRefName,mergeable \
  --jq '"\(.baseRefName) \(.mergeable)"' 2>/dev/null)"; then
  echo "STOP pr-read-failed"
  exit 0
fi

read -r BASE_REF MERGEABLE <<<"$PR_INFO"

if [ "$BASE_REF" = "$EXPECTED_BASE" ]; then
  BASE_TOKEN="BASE-OK"
else
  BASE_TOKEN="BASE-DRIFT"
fi

ATTEMPTS=0
while [ "$MERGEABLE" = "UNKNOWN" ] && [ "$ATTEMPTS" -lt "$MERGEABLE_RETRY_MAX" ]; do
  sleep "$MERGEABLE_RETRY_SECONDS"
  ATTEMPTS=$((ATTEMPTS + 1))
  if ! MERGEABLE="$(gh pr view "$PR" -R "${OWNER}/${REPO}" --json mergeable --jq '.mergeable' 2>/dev/null)"; then
    echo "STOP pr-read-failed"
    exit 0
  fi
done

echo "${BASE_TOKEN} ${BASE_REF} ${MERGEABLE}"
