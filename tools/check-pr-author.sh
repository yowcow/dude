#!/usr/bin/env bash
# Answer whether a PR's author is the user the agent's GitHub means acts as.
#
# One answer, two callers that stop on opposite sides of it: review-pr stops on
# SELF (your own PR belongs to pr-to-ready), and review-code stops on OTHER,
# since its loop applies fixes to the working tree and would rewrite somebody
# else's code.
#
# It reads no GitHub itself. Without facts it answers NEED, pinning the PR to
# origin's repository and the number given: a PR read under the same number
# in another repository (an upstream the means defaults to) is a mismatch and
# stops, never an answer about the wrong PR. A login that could not be read is
# a STOP, never a guess: reading it as OTHER sends review-code's caller away
# from their own PR, and reading it as SELF sends review-pr's caller to
# pr-to-ready, which would push to somebody else's branch.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: check-pr-author.sh <pr-number> [--facts <file>]
# Output: SELF | OTHER | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 <pr-number> [--facts <file>]" >&2
  exit 2
}

FACTS=''
case "$#" in
  1) ;;
  3)
    if [ "$2" != --facts ] || [ -z "$3" ]; then usage; fi
    FACTS="$3"
    ;;
  *) usage ;;
esac
if ! [[ "$1" =~ ^[0-9]+$ ]]; then usage; fi
PR="$1"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

VERDICT="$(bash "${SCRIPT_DIR}/facts.sh" check "$FACTS" \
  "repo=${REPO}" "pr.number=${PR}" pr.author.login viewer.login)"
if [ "$VERDICT" != OK ]; then
  echo "$VERDICT"
  exit 0
fi

AUTHOR="$(bash "${SCRIPT_DIR}/facts.sh" get "$FACTS" pr.author.login)"
ME="$(bash "${SCRIPT_DIR}/facts.sh" get "$FACTS" viewer.login)"

if [ "$AUTHOR" = "$ME" ]; then
  echo "SELF"
else
  echo "OTHER"
fi
