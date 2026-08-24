#!/usr/bin/env bash
# Replace the body of an existing issue comment in place, by its numeric id.
#
# This is how plan-work keeps "publish once" true: the design comment is posted
# once by post-plan-comment.sh and every later revision — appending the sub-issue
# list, re-approving an invalidated design — edits that same comment through here.
#
# The id must be the numeric REST id that post-plan-comment.sh printed. A GraphQL
# node id (`IC_...`) is rejected up front rather than sent, because this endpoint
# does not accept one, and because reaching for a node id usually means the id was
# re-read from `--json comments` long after the fact instead of kept from the post.
#
# The body comes from a file for the same reason as in post-plan-comment.sh:
# backticks never reach the shell, and `gh api` gets JSON rather than raw Markdown.
#
# Usage: edit-plan-comment.sh <owner> <repo> <comment-id> <body-file>
# Output: the comment URL
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <owner> <repo> <comment-id> <body-file>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
COMMENT_ID="$3"
BODY_FILE="$4"

if ! [[ "$COMMENT_ID" =~ ^[0-9]+$ ]]; then
  echo "error: '$COMMENT_ID' is not a numeric comment id" >&2
  echo "       a GraphQL node id (IC_...) does not work here — use the id that" >&2
  echo "       post-plan-comment.sh printed" >&2
  exit 1
fi

# `-r` as well as `-f`: with `-f` alone a file that exists with mode 000 walks
# through and only the `<"$BODY_FILE"` redirect fails, while the `gh` on the
# right of the pipeline is forked and runs regardless — one API call after all,
# which is what this guard exists to prevent. post-plan-comment.sh's identical
# guard carries the longer form of the reason.
if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then
  echo "error: body file is not readable: $BODY_FILE" >&2
  exit 1
fi

jq -Rs '{body: .}' <"$BODY_FILE" \
  | gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$COMMENT_ID" --input - \
    --jq '.html_url'
