#!/usr/bin/env bash
# Replace the body of an existing issue comment in place, by its numeric id.
#
# This is how plan-work keeps "publish once" true: the design comment is posted
# once by post-plan-comment.sh and every later revision — appending the sub-issue
# list, re-approving an invalidated design — edits that same comment through here.
#
# The id must be the numeric REST id that post-plan-comment.sh printed.
#
# The body comes from a file for the same reason as in post-plan-comment.sh:
# backticks never reach the shell, and `gh api` gets JSON rather than raw Markdown.
#
# Usage: edit-plan-comment.sh <owner> <repo> <comment-id> <body-file>
# Output: the comment URL
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <owner> <repo> <comment-id> <body-file>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
COMMENT_ID="$3"
BODY_FILE="$4"

# Body guard and `jq -Rs` wrap live in plan-comment-payload.sh.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if ! PAYLOAD="$(bash "${SCRIPT_DIR}/plan-comment-payload.sh" "$BODY_FILE")"; then
  exit 1
fi

printf '%s\n' "$PAYLOAD" \
  | gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" --input - \
    --jq '.html_url'
