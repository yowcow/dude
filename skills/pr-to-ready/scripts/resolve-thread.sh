#!/usr/bin/env bash
# Resolve one or more GitHub PR review threads, each identified by the REST
# comment id of one of its first 50 comments — the range this script indexes,
# which covers the comment ids returned by list-unresolved-threads.sh; a
# comment id beyond that in an unusually long thread won't match. There is no
# REST endpoint for this — GitHub only exposes thread resolution via GraphQL —
# so this wraps the lookup+mutation. Pass several comment ids to batch-resolve
# a whole review round in one invocation.
# Usage: resolve-thread.sh <owner> <repo> <pr-number> <comment-id> [comment-id...]
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <comment-id> [comment-id...]" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PR="$3"
shift 3

# Fetch every thread's id together with the databaseIds of its comments once,
# then resolve each requested comment id against that snapshot. --paginate
# follows pageInfo automatically as long as the query names $endCursor and
# threads it through reviewThreads(after: $endCursor) — needed because a
# long-running PR's cumulative thread count (resolved + unresolved) can exceed
# a single page, same as list-unresolved-threads.sh. The --jq streams one
# thread node per line, so the snapshot spans every page.
THREADS_JSON=$(gh api graphql --paginate \
  -f owner="$OWNER" \
  -f repo="$REPO" \
  -F pr="$PR" \
  -f query='
    query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              comments(first: 50) {
                nodes { databaseId }
              }
            }
          }
        }
      }
    }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]')

status=0
for COMMENT_ID in "$@"; do
  if ! [[ "$COMMENT_ID" =~ ^[0-9]+$ ]]; then
    echo "error: invalid comment id '$COMMENT_ID' (must be an integer)" >&2
    status=1
    continue
  fi

  # A comment id belongs to exactly one thread, so this yields 0 or 1 id — no
  # head needed (avoiding the pipe also sidesteps SIGPIPE under pipefail).
  THREAD_ID=$(printf '%s' "$THREADS_JSON" \
    | jq -r --argjson cid "$COMMENT_ID" \
        'select(any(.comments.nodes[]; .databaseId == $cid)) | .id')

  if [ -z "$THREAD_ID" ]; then
    echo "error: review thread not found for comment id $COMMENT_ID" >&2
    status=1
    continue
  fi

  if ! gh api graphql \
    -f threadId="$THREAD_ID" \
    -f query='
      mutation($threadId: ID!) {
        resolveReviewThread(input: { threadId: $threadId }) {
          thread { isResolved }
        }
      }'; then
    echo "error: failed to resolve review thread for comment id $COMMENT_ID" >&2
    status=1
  fi
done

exit "$status"
