#!/usr/bin/env bash
# Read an issue's one prerequisite line (`Blocked-By: #N`, which plan-work
# writes; format and reasons in skills/implement-work/references/base-branch.md)
# and report the prerequisite's closing PR by its *current* state. One line on
# stdout, always: NO-PREREQ | PREREQ <head-branch> <closing-pr-n> <OPEN|MERGED> |
# NEED <token>... | STOP <slug>. No issue number answers NO-PREREQ, so a caller
# keeps no branch of its own for it.
#
# It reads no issue or PR itself: answers NEED in up to three rounds, each pinned
# to origin's repository and the number the round before produced. The closing
# PRs are counted, never tested for emptiness; a PR's state is read from its own
# record, never as "not open".
#
# Shared by skills/implement-work/scripts/resolve-base.sh, tools/resolve-pr-base.sh
# and tools/resolve-range.sh, called by no SKILL.md: do not delete as
# unreferenced.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: read-prereq-pr.sh [--facts <file>] [<issue-number>]
set -euo pipefail

usage() {
  echo "Usage: $0 [--facts <file>] [<issue-number>]" >&2
  exit 2
}

FACTS=''
if [ "${1:-}" = --facts ]; then
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
  FACTS="$2"
  shift 2
fi
if [ "$#" -gt 1 ]; then usage; fi
ISSUE=''
if [ "$#" -eq 1 ]; then
  ISSUE="$1"
  if ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then usage; fi
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# need <spec>...: on OK return; otherwise answer and exit 0.
need() {
  local verdict
  if ! verdict="$(bash "${SCRIPT_DIR}/facts.sh" check "$FACTS" "$@")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  case "$verdict" in
    OK) return 0 ;;
    "NEED "?* | "STOP "?*) echo "$verdict" ;;
    *) echo "STOP facts-answer-malformed" ;;
  esac
  exit 0
}

# fact <var> <name>: assign the value into the caller's variable. The value is
# never printed: called as $(fact ...) the exit 0 above would land in a
# subshell, leaving the caller running and reading "STOP ..." back as data.
fact() {
  local value
  if ! value="$(bash "${SCRIPT_DIR}/facts.sh" get "$FACTS" "$2")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  printf -v "$1" '%s' "$value"
}

if [ -z "$ISSUE" ]; then
  echo "NO-PREREQ"
  exit 0
fi

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

SPECS=("repo=${REPO}" "issue.number=${ISSUE}" issue.body-file)
need "${SPECS[@]}"
fact BODY_FILE issue.body-file

if ! LINE="$(bash "${SCRIPT_DIR}/prereq-line.sh" "$BODY_FILE")"; then
  echo "STOP body-unreadable"
  exit 0
fi
case "$LINE" in
  NONE)
    echo "NO-PREREQ"
    exit 0
    ;;
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
fact COUNT prereq.closing-pr.total
if [ "$COUNT" -eq 0 ]; then
  echo "STOP not-implemented"
  exit 0
fi
if [ "$COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi
fact PR prereq.closing-pr

SPECS+=("pr.number=${PR}" 'pr.state:OPEN,MERGED,CLOSED' pr.head.ref "pr.head.owner=${REPO%%/*}")
need "${SPECS[@]}"
fact STATE pr.state
fact HEAD_REF pr.head.ref
case "$STATE" in
  OPEN | MERGED) echo "PREREQ ${HEAD_REF} ${PR} ${STATE}" ;;
  CLOSED) echo "STOP abandoned-prerequisite" ;;
esac
