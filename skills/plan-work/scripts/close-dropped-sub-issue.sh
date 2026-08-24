#!/usr/bin/env bash
# Close a sub-issue whose item is gone from a re-approved TODO list: post the
# reason, then close it as **not planned**.
#
# The reason must be "not planned". Closing with the default reason records the
# item as completed, which is indistinguishable from a child whose PR merged —
# and plan-work reads a closed child as work already done, so a wrongly-closed one
# quietly drops real work out of the plan for good.
#
# The reason body comes from a file, and carries the parent design comment's URL
# so the decision is reachable from the child. The sub-issue link itself is left in
# place: the closed child is the record that the item was dropped.
#
# Usage: close-dropped-sub-issue.sh <owner> <repo> <child-number> <reason-file>
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <owner> <repo> <child-number> <reason-file>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
CHILD="$3"
REASON_FILE="$4"

if ! [[ "$CHILD" =~ ^[0-9]+$ ]]; then
  echo "error: invalid issue number '$CHILD' (must be an integer)" >&2
  exit 1
fi

# `-r` as well as `-f`: with `-f` alone a file that exists with mode 000 walks
# through and only the `<"$REASON_FILE"` redirect fails, while the `gh` on the
# right of the pipeline is forked and runs regardless — the reason gets posted
# after all, which is what this guard exists to prevent. post-plan-comment.sh's
# identical guard carries the longer form of the reason.
if [ ! -f "$REASON_FILE" ] || [ ! -r "$REASON_FILE" ]; then
  echo "error: reason file is not readable: $REASON_FILE" >&2
  exit 1
fi

jq -Rs '{body: .}' <"$REASON_FILE" \
  | gh api --method POST "repos/$OWNER/$REPO/issues/$CHILD/comments" --input - >/dev/null

gh issue close "$CHILD" --repo "$OWNER/$REPO" --reason "not planned" >/dev/null

gh issue view "$CHILD" --repo "$OWNER/$REPO" --json number,state,stateReason \
  --jq '"#\(.number) \(.state) (\(.stateReason))"'
