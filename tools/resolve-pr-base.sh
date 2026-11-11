#!/usr/bin/env bash
# Resolve which branch a task branch should sit on, by reading its issue's
# `Blocked-By: #N` line and re-checking the prerequisite PR's *current* state --
# never by testing whether the prerequisite's branch still exists, which
# commonly survives its merge and would hand back an already-merged branch as
# --base, silently landing nothing into the default branch.
# Spec: skills/implement-work/references/base-branch.md, "## Reading the
# prerequisite back" (this script implements that table's `pr-to-ready`'s
# `--base` column; the no-prerequisite row answers the default branch so Step
# 1's settlement has something to compare against).
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: resolve-pr-base.sh <branch> [--issue <n>] [--facts <file>]
# Output: BASE <branch> | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 <branch> [--issue <n>] [--facts <file>]" >&2
  exit 2
}

BRANCH=''
FACTS=''
ISSUE=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --facts | --issue)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      if [ "$1" = --facts ]; then FACTS="$2"; else ISSUE="$2"; fi
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$1" ]; then usage; fi
      if [ -z "$BRANCH" ]; then BRANCH="$1"; else usage; fi
      shift
      ;;
  esac
done
if [ -z "$BRANCH" ]; then usage; fi
if [ -n "$ISSUE" ] && ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then usage; fi

# The default branch is resolved by tools/resolve-default-branch.sh
# -- see its header for the rationale.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# The default branch is resolved first: it is both an answer below and a ref
# the fetches name.
DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }

# Both fetches stay as a check that the default branch and the task branch are
# on the remote. The default branch's failure carries its own slug: folded into
# fetch-failed, the caller could not tell a missing task branch from a missing
# default branch, and the two want different answers from the person they stop
# for.
if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}" >/dev/null; then
  echo "STOP default-fetch-failed"
  exit 0
fi

if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${BRANCH}" >/dev/null; then
  echo "STOP fetch-failed"
  exit 0
fi

# The prerequisite lookup and the answers it prints live in
# tools/read-prereq-pr.sh -- see its header. What is left here is
# base-branch.md's `pr-to-ready`'s `--base` column. Without --issue the reader
# answers NO-PREREQ and asks for no facts.
READ_ARGS=()
if [ -n "$FACTS" ]; then READ_ARGS+=(--facts "$FACTS"); fi
if [ -n "$ISSUE" ]; then READ_ARGS+=("$ISSUE"); fi
# An empty array is an unbound-variable error under set -u before bash 4.4.
if ! ANSWER="$(bash "${SCRIPT_DIR}/read-prereq-pr.sh" ${READ_ARGS[@]+"${READ_ARGS[@]}"})"; then
  echo "STOP prereq-read-failed"
  exit 0
fi

read -r KIND RECORDED _ STATE <<<"$ANSWER"

case "${KIND}" in
  NO-PREREQ)
    echo "BASE ${DEFAULT}"
    ;;
  STOP | NEED)
    printf '%s\n' "$ANSWER"
    ;;
  PREREQ)
    case "${STATE}" in
      OPEN)
        echo "BASE ${RECORDED}"
        ;;
      MERGED)
        # A merged prerequisite whose branch is still around must not be read
        # as "still in flight": that would hand back --base <merged-branch>,
        # and merging into an already-merged branch puts nothing into the
        # default branch, so the change silently fails to land there. The PR
        # number the answer carries is `review-code`'s to use, not this
        # column's -- the base here is the default branch.
        echo "BASE ${DEFAULT}"
        ;;
      *)
        printf 'unrecognised prerequisite state: %s\n' "${STATE}" >&2
        echo "STOP prereq-answer-malformed"
        exit 0
        ;;
    esac
    ;;
  *)
    printf 'unrecognised answer from read-prereq-pr.sh: %s\n' "${ANSWER}" >&2
    echo "STOP prereq-answer-malformed"
    exit 0
    ;;
esac
