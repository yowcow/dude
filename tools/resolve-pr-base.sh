#!/usr/bin/env bash
# Resolve which branch a task branch should sit on, by reading its
# Base-Branch trailer and re-checking the prerequisite PR's *current* state —
# never by testing whether the prerequisite's branch still exists.
#
# This always prints a concrete branch name, even where the cited table says
# to omit `--base` — Step 1's base settlement compares this answer against the
# base the PR currently points at, and has nothing to compare against if the
# no-trailer case answers with an absence. Naming the default branch there
# selects exactly what omitting the flag would have.
#
# A merged prerequisite's branch commonly survives (branch deletion is a
# person's separate step), so a plain existence test would read a long-since
# merged prerequisite as "still in flight" and hand back its branch as
# --base. Merging this task into that branch then puts nothing into the
# default branch, and the change silently fails to land. See
# skills/implement-work/references/base-branch.md, "## Reading the trailer
# back" and "### Why the state is re-read and the branch is not" — this
# script implements that table's `pr-to-ready`'s `--base` column.
#
# Usage: resolve-pr-base.sh <branch> [repo] [--facts <file>]
# Output: BASE <branch> | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 <branch> [repo] [--facts <file>]" >&2
  exit 2
}

BRANCH=''
BASE_REPO=''
FACTS=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --facts)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      FACTS="$2"
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$1" ]; then usage; fi
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      elif [ -z "$BASE_REPO" ]; then
        BASE_REPO="$1"
      else
        usage
      fi
      shift
      ;;
  esac
done
if [ -z "$BRANCH" ]; then usage; fi

# The default branch is resolved by tools/resolve-default-branch.sh
# -- see its header for the rationale.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Resolve the default branch before the scan below rather than at the two
# places that print it: the scan's range is expressed against it, so it has
# to be both named and fetched by then.
DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh" "$BASE_REPO")" || { echo "STOP ask-default-branch"; exit 0; }

# The task branch's tip is read below as FETCH_HEAD rather than from a local
# checkout — this session may not have <branch> checked out at all. So the
# default branch is fetched first and the task branch second, because `git
# fetch` rewrites FETCH_HEAD on every call. Reversed, FETCH_HEAD would hold
# the default branch's tip, the scan below would read the empty range
# `<default> ^<default>`, and every branch would silently resolve to the
# default branch as its base.
#
# The default branch's fetch failure carries its own slug: folded into
# fetch-failed, the caller could not tell a missing task branch from a
# missing default branch, and the two want different answers from the person
# they stop for.
if ! DEFAULT_SHA="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}")"; then
  echo "STOP default-fetch-failed"
  exit 0
fi

if ! bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${BRANCH}" >/dev/null; then
  echo "STOP fetch-failed"
  exit 0
fi

# The trailer scan, the prerequisite lookup, and the three answers both
# readers print identically live in
# tools/read-base-trailer.sh -- see its header. What is
# left here is base-branch.md's `pr-to-ready`'s `--base` column: the three
# rows where the two readers disagree.
#
# The revs are chosen here rather than there because they are this caller's
# question. The scan runs from the branch tip just fetched and stops at the
# default branch, and the exclusion names the saved default-branch SHA rather than a remote-tracking ref a narrowed clone need not have updated. Unbounded,
# the scan walks to root, so a branch that recorded nothing picks up whatever
# Base-Branch some unrelated commit left in shared history and hands that
# branch back as the base -- which ensure-draft-pr.sh then answers as
# `CREATE ... base=<base>`, so the caller opens the PR against a branch this
# task never sat on.
if [ -n "$FACTS" ]; then
  ANSWER="$(bash "${SCRIPT_DIR}/read-base-trailer.sh" --facts "$FACTS" FETCH_HEAD "^${DEFAULT_SHA}")"
else
  ANSWER="$(bash "${SCRIPT_DIR}/read-base-trailer.sh" FETCH_HEAD "^${DEFAULT_SHA}")"
fi

read -r KIND RECORDED _ STATE <<<"$ANSWER"

case "${KIND}" in
  NO-TRAILER)
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
    esac
    ;;
esac
