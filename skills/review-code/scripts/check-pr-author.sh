#!/usr/bin/env bash
# Copied from ../../review-pr/scripts/check-pr-author.sh to remove upward cross-skill use; cf. check-pr-repo.sh:37-38.
# Answer whether a PR's author is the user gh is logged in as.
#
# One answer, two callers that stop on opposite sides of it: review-pr stops on
# SELF (your own PR belongs to pr-to-ready), and review-code stops on OTHER,
# since its loop applies fixes to the working tree and would rewrite somebody
# else's code. The PR is resolved by number through gh's own repository
# resolution, the same one ./resolve-range.sh uses, so both read the same PR.
#
# A failed lookup is a STOP, never a guess: reading it as OTHER sends
# review-code's caller away from their own PR, and reading it as SELF sends
# review-pr's caller to pr-to-ready, which would push to somebody else's
# branch.
#
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: check-pr-author.sh <pr-number>
# Output: SELF | OTHER | STOP pr-lookup-failed
set -euo pipefail

if [ "$#" -ne 1 ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 <pr-number>" >&2
  exit 2
fi

PR="$1"

if ! ME="$(gh api user --jq .login 2>/dev/null)" ||
  ! AUTHOR="$(gh pr view --json author --jq .author.login -- "$PR" 2>/dev/null)"; then
  echo "STOP pr-lookup-failed"
  exit 0
fi

if [ "$AUTHOR" = "$ME" ]; then
  echo "SELF"
else
  echo "OTHER"
fi
