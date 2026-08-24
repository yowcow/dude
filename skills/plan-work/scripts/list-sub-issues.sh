#!/usr/bin/env bash
# List an issue's sub-issues from the native relation, as {number, state, title}.
#
# The native relation is what is true about the children — the parent comment's
# prose is a record of what was published, which drifts as children are created,
# updated and closed. Re-entry matches the new TODO list against the output of
# this script, never against that prose.
#
# --paginate with per_page=100 so a long split does not silently stop at the
# first page's worth of children. per_page goes in the query string rather than
# through -F: passing a field makes gh send POST, and this endpoint's POST is
# "add a sub-issue", which fails with a 422 instead of listing anything.
#
# Usage: list-sub-issues.sh <owner> <repo> <parent-number>
# Output: one JSON object per child, in the parent's own ordering
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <owner> <repo> <parent-number>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PARENT="$3"

if ! [[ "$PARENT" =~ ^[0-9]+$ ]]; then
  echo "error: invalid issue number '$PARENT' (must be an integer)" >&2
  exit 1
fi

gh api --paginate "repos/$OWNER/$REPO/issues/$PARENT/sub_issues?per_page=100" \
  --jq '.[] | {number, state, title}'
