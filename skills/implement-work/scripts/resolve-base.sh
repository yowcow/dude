#!/usr/bin/env bash
# Resolve which branch a new task should be cut from, by its issue's native
# `blockedBy` relation rather than issue-body prose. Branching from the
# default while a prerequisite PR is still OPEN would simply omit that
# prerequisite's changes, so the task's own checks then fail for a reason
# nowhere in its diff.
# Usage: resolve-base.sh [issue-number]
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [issue-number]" >&2
  exit 1
fi

ISSUE="${1:-}"

# Two-rung ladder, never guessing a branch name: the GitHub API, then give up
# and let the caller ask a person.
#
# refs/remotes/origin/HEAD is deliberately not consulted. A clone sets that
# symref once and never refreshes it, so after the repository renames its
# default branch it keeps naming the old one; while that branch still exists
# this function would answer with it and the task's branch would be cut from
# the wrong base, with no error anywhere. Reading it saved one `gh` call and
# nothing else -- every path that reaches here fetches immediately afterwards,
# so there was no offline case to keep.
resolve_default_branch() {
  local ref
  if ref="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" && [ -n "$ref" ]; then
    printf '%s\n' "$ref"
    return 0
  fi
  return 1
}

# Fetch the branch, so the caller can cut from origin/<name>.
fetch_ref() {
  git fetch origin "$1" >&2
}

# blockedBy and closedByPullRequestsReferences must be counted, never merely
# checked for emptiness — "is it empty" cannot tell one prerequisite from
# three, and both need the opposite answer here. A task with no issue behind
# it has no relation to read, which lands on the same answer as a count of 0.
if [ -z "$ISSUE" ]; then
  BLOCKED_COUNT=0
else
  BLOCKED_JSON="$(gh issue view "${ISSUE}" --json blockedBy)"
  BLOCKED_COUNT="$(printf '%s' "$BLOCKED_JSON" | jq '.blockedBy.totalCount')"
fi

if [ "${BLOCKED_COUNT}" -eq 0 ]; then
  DEFAULT="$(resolve_default_branch)" || { echo "STOP ask-default-branch"; exit 0; }
  fetch_ref "${DEFAULT}"
  echo "BASE ${DEFAULT}"
  exit 0
fi

if [ "${BLOCKED_COUNT}" -ge 2 ]; then
  echo "STOP ask-multiple-prereqs"
  exit 0
fi

PREREQ="$(printf '%s' "$BLOCKED_JSON" | jq -r '.blockedBy.nodes[0].number')"

# closedByPullRequestsReferences comes back as a plain array here (unlike
# blockedBy's {nodes, totalCount}), so it is counted with `length`.
CLOSED_JSON="$(gh issue view "${PREREQ}" --json closedByPullRequestsReferences)"
PR_COUNT="$(printf '%s' "$CLOSED_JSON" | jq '.closedByPullRequestsReferences | length')"

if [ "${PR_COUNT}" -eq 0 ]; then
  echo "STOP not-implemented"
  exit 0
fi

if [ "${PR_COUNT}" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi

PR="$(printf '%s' "$CLOSED_JSON" | jq -r '.closedByPullRequestsReferences[0].number')"

PR_INFO="$(gh pr view "${PR}" --json headRefName,state --jq '"\(.headRefName) \(.state)"')"
HEAD_REF="${PR_INFO% *}"
STATE="${PR_INFO##* }"

case "${STATE}" in
  MERGED)
    DEFAULT="$(resolve_default_branch)" || { echo "STOP ask-default-branch"; exit 0; }
    fetch_ref "${DEFAULT}"
    echo "BASE ${DEFAULT}"
    ;;
  OPEN)
    fetch_ref "${HEAD_REF}"
    echo "BASE ${HEAD_REF}"
    ;;
  CLOSED)
    echo "STOP abandoned-prerequisite"
    ;;
  *)
    echo "error: unexpected PR state '${STATE}' for PR ${PR}" >&2
    exit 1
    ;;
esac
