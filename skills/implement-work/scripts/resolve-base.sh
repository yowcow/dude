#!/usr/bin/env bash
# Resolve which branch a new task should be cut from, by the one prerequisite
# line in its issue's body (`Blocked-By: #N`, which plan-work writes; format
# and reasons in ../references/base-branch.md). Branching from the default
# while a prerequisite PR is still OPEN would simply omit that prerequisite's
# changes, so the task's own checks then fail for a reason nowhere in its diff.
#
# The prerequisite is read by ../../../tools/read-prereq-pr.sh (NEED rounds,
# closing-PR count, state); this script only turns its answer into a base.
#
# Facts: ../references/facts.md.
# Conventions: ../references/script-conventions.md.
# STOP slugs: ../references/stop-registry.md.
#
# Usage: resolve-base.sh [<issue-number> [--facts <file>]]
# Output: BASE <branch> | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 [<issue-number> [--facts <file>]]" >&2
  exit 2
}

ISSUE=''
FACTS=''
case "$#" in
  0) ;;
  1) ISSUE="$1" ;;
  3)
    if [ "$2" != --facts ] || [ -z "$3" ]; then usage; fi
    ISSUE="$1"
    FACTS="$3"
    ;;
  *) usage ;;
esac
if [ -n "$ISSUE" ] && ! [[ "$ISSUE" =~ ^[0-9]+$ ]]; then usage; fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
TOOLS="${SCRIPT_DIR}/../../../tools"

# base <branch>: fetch it, then answer it.
base() {
  if ! bash "${TOOLS}/fetch-to-sha.sh" "$1" >/dev/null; then
    echo "STOP base-fetch-failed"
    exit 0
  fi
  echo "BASE $1"
  exit 0
}

base_default() {
  local default
  if ! default="$(bash "${TOOLS}/resolve-default-branch.sh")"; then
    echo "STOP ask-default-branch"
    exit 0
  fi
  base "$default"
}

READ_ARGS=()
if [ -n "$FACTS" ]; then READ_ARGS+=(--facts "$FACTS"); fi
if [ -n "$ISSUE" ]; then READ_ARGS+=("$ISSUE"); fi
# An empty array is an unbound-variable error under set -u before bash 4.4.
if ! ANSWER="$(bash "${TOOLS}/read-prereq-pr.sh" ${READ_ARGS[@]+"${READ_ARGS[@]}"})"; then
  echo "STOP prereq-read-failed"
  exit 0
fi
read -r KIND HEAD_REF _ STATE <<<"$ANSWER"
case "$KIND" in
  NO-PREREQ) base_default ;;
  PREREQ)
    case "$STATE" in
      OPEN) base "$HEAD_REF" ;;
      MERGED) base_default ;;
    esac
    echo "unrecognised prerequisite state: ${STATE}" >&2
    ;;
  NEED | STOP)
    echo "$ANSWER"
    exit 0
    ;;
  *) echo "unrecognised answer from read-prereq-pr.sh: ${ANSWER}" >&2 ;;
esac
echo "STOP prereq-answer-malformed"
