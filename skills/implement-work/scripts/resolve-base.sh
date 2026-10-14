#!/usr/bin/env bash
# Resolve which branch a new task should be cut from, by the one prerequisite
# line in its issue's body (`Blocked-By: #N`, which plan-work writes; format
# and reasons in ../references/base-branch.md). Branching from the default
# while a prerequisite PR is still OPEN would simply omit that prerequisite's
# changes, so the task's own checks then fail for a reason nowhere in its diff.
#
# It reads no issue or PR itself. It answers NEED in up to three rounds — the
# issue's body, then the PRs that close the prerequisite, then that PR's state
# and head — each read pinned to origin's repository and to the number the
# round before produced, so a record read for another issue or PR stops.
#
# The closing PRs are counted, never tested for emptiness: one PR and two need
# opposite answers. A PR's state has three values and is read from that PR's
# own record: MERGED and CLOSED need opposite answers, so "not open" is never
# the test.
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
    exit 1
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

# need <spec>...: relay any answer from the self-check other than OK.
need() {
  local verdict
  verdict="$(bash "${TOOLS}/facts.sh" check "$FACTS" "$@")"
  if [ "$verdict" != OK ]; then
    echo "$verdict"
    exit 0
  fi
}

fact() {
  bash "${TOOLS}/facts.sh" get "$FACTS" "$1"
}

if [ -z "$ISSUE" ]; then
  base_default
fi

if ! REPO="$(bash "${TOOLS}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

SPECS=("repo=${REPO}" "issue.number=${ISSUE}" issue.body-file)
need "${SPECS[@]}"

if ! LINE="$(bash "${TOOLS}/prereq-line.sh" "$(fact issue.body-file)")"; then
  echo "STOP body-unreadable"
  exit 0
fi
case "$LINE" in
  NONE) base_default ;;
  MULTIPLE)
    echo "STOP ask-multiple-prereqs"
    exit 0
    ;;
  MALFORMED)
    echo "STOP prereq-line-malformed"
    exit 0
    ;;
esac
PREREQ="${LINE#PREREQ }"

SPECS+=("prereq.number=${PREREQ}" 'prereq.closing-pr[]')
need "${SPECS[@]}"
COUNT="$(fact prereq.closing-pr.total)"
if [ "$COUNT" -eq 0 ]; then
  echo "STOP not-implemented"
  exit 0
fi
if [ "$COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi
PR="$(fact prereq.closing-pr)"

SPECS+=("pr.number=${PR}" 'pr.state:OPEN,MERGED,CLOSED' pr.head.ref)
need "${SPECS[@]}"
case "$(fact pr.state)" in
  OPEN) base "$(fact pr.head.ref)" ;;
  MERGED) base_default ;;
  CLOSED) echo "STOP abandoned-prerequisite" ;;
esac
