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
  exit 2
fi

ISSUE="${1:-}"

if [ -n "$ISSUE" ] && ! [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [issue-number]" >&2
  exit 2
fi

# The default branch is resolved by resolve-default-branch.sh beside this
# script -- see its header for the rationale.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# blockedBy and closedByPullRequestsReferences must be counted, never merely
# checked for emptiness — "is it empty" cannot tell one prerequisite from
# three, and both need the opposite answer here. A task with no issue behind
# it has no relation to read, which lands on the same answer as a count of 0.
if [ -z "$ISSUE" ]; then
  BLOCKED_COUNT=0
else
  if ! BLOCKED_JSON="$(gh issue view --json blockedBy -- "${ISSUE}" 2>/dev/null)"; then
    echo "STOP blocked-lookup-failed"
    exit 0
  fi
  if ! BLOCKED_COUNT="$(printf '%s' "$BLOCKED_JSON" | jq '.blockedBy.totalCount' 2>/dev/null)"; then
    echo "STOP blocked-lookup-failed"
    exit 0
  fi
fi

if [ "${BLOCKED_COUNT}" -eq 0 ]; then
  DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }
  if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}" >/dev/null; then
    exit 1
  fi
  echo "BASE ${DEFAULT}"
  exit 0
fi

if [ "${BLOCKED_COUNT}" -ge 2 ]; then
  echo "STOP ask-multiple-prereqs"
  exit 0
fi

if ! PREREQ="$(printf '%s' "$BLOCKED_JSON" | jq -r '.blockedBy.nodes[0].number' 2>/dev/null)"; then
  echo "STOP blocked-lookup-failed"
  exit 0
fi

# closedByPullRequestsReferences comes back as a plain array here (unlike
# blockedBy's {nodes, totalCount}), so it is counted with `length`.
if ! CLOSED_JSON="$(gh issue view --json closedByPullRequestsReferences -- "${PREREQ}" 2>/dev/null)"; then
  echo "STOP prereq-lookup-failed"
  exit 0
fi
if ! PR_COUNT="$(printf '%s' "$CLOSED_JSON" | jq '.closedByPullRequestsReferences | length' 2>/dev/null)"; then
  echo "STOP prereq-lookup-failed"
  exit 0
fi

if [ "${PR_COUNT}" -eq 0 ]; then
  echo "STOP not-implemented"
  exit 0
fi

if [ "${PR_COUNT}" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi

if ! PR="$(printf '%s' "$CLOSED_JSON" | jq -r '.closedByPullRequestsReferences[0].number' 2>/dev/null)"; then
  echo "STOP prereq-lookup-failed"
  exit 0
fi

if ! PR_INFO="$(gh pr view --json headRefName,state --jq '"\(.headRefName) \(.state)"' -- "${PR}" 2>/dev/null)"; then
  echo "STOP pr-lookup-failed"
  exit 0
fi
HEAD_REF="${PR_INFO% *}"
STATE="${PR_INFO##* }"

case "${STATE}" in
  MERGED)
    DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }
    if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}" >/dev/null; then
      exit 1
    fi
    echo "BASE ${DEFAULT}"
    ;;
  OPEN)
    if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${HEAD_REF}" >/dev/null; then
      exit 1
    fi
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
