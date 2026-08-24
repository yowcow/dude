#!/usr/bin/env bash
# Link an existing issue as a sub-issue of a parent issue, then confirm it took.
#
# Both issues are named by their **issue number**, which is what a plan holds.
# The endpoint, however, identifies the child by its database id, not its number:
# post a number as sub_issue_id and it either fails or attaches whichever issue
# happens to carry that id — a different issue, in a different repository. So the
# number is resolved to the id here rather than at the call site.
#
# The link is read back afterwards because a silently absent child is the failure
# that matters: the parent then has no record of the item, and nothing shows which
# PRs are still outstanding.
#
# Usage: link-sub-issue.sh <owner> <repo> <parent-number> <child-number>
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <owner> <repo> <parent-number> <child-number>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PARENT="$3"
CHILD="$4"

for n in "$PARENT" "$CHILD"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "error: invalid issue number '$n' (must be an integer)" >&2
    exit 1
  fi
done

CHILD_ID=$(gh api "repos/$OWNER/$REPO/issues/$CHILD" --jq '.id')

gh api --method POST "repos/$OWNER/$REPO/issues/$PARENT/sub_issues" \
  -F "sub_issue_id=$CHILD_ID" >/dev/null

# Capture the numbers before matching: grep -q exits on its first hit, which would
# SIGPIPE gh and fail the pipeline under pipefail. per_page goes in the query
# string, not through -F — a field would make gh send POST, which on this endpoint
# means "add a sub-issue" rather than "list them".
LINKED=$(gh api --paginate \
  "repos/$OWNER/$REPO/issues/$PARENT/sub_issues?per_page=100" --jq '.[].number')

if ! grep -qx "$CHILD" <<<"$LINKED"; then
  echo "error: #$CHILD is not among #$PARENT's sub-issues after the link call" >&2
  exit 1
fi

echo "linked #$CHILD (id $CHILD_ID) as a sub-issue of #$PARENT"
