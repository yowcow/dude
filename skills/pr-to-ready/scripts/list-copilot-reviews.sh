#!/usr/bin/env bash
# List Copilot's submitted reviews on a PR as one JSON object per line:
# {id, author, state, submittedAt}.
#
# This exists as a command because identifying the reviewer is the whole
# difficulty: the bot's login differs across GitHub's surfaces — the review
# surface returns it without the "[bot]" suffix that the reviewer-request
# surface uses — so the filter matches a lowercased substring rather than one
# exact spelling. Why the login and never the timestamp:
# ../references/gh-mechanics.md.
#
# What counts as *new* is the caller's judgement, made by comparing ids against
# the reviews it has already handled. This script only reports what is there.
#
# Usage: list-copilot-reviews.sh <owner> <repo> <pr-number>
#
# Exit: 0 = the listing printed — empty output means Copilot has not reviewed yet
#       2 = usage error
#       other = the gh call failed — stop and inspect
#
# Empty output alone never means "no review": read it together with the exit
# status, since a failing gh call prints nothing on stdout either.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"

# The login falls back to "" rather than being indexed directly: this surface is
# GraphQL, where a review left by a since-deleted account comes back with
# author: null, and `null | ascii_downcase` aborts the whole filter. One such
# review anywhere on the PR would otherwise take this script down with it, and
# the caller would read that as "the gh call failed" while Copilot's review sat
# right there.
gh pr view "$PR" --repo "$OWNER/$REPO" --json reviews \
  --jq '.reviews[]
        | select((.author.login // "") | ascii_downcase | contains("copilot"))
        | {id, author: (.author.login // ""), state, submittedAt}'
