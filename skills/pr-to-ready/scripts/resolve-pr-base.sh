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
# ../../implement-work/references/base-branch.md, "## Reading the trailer
# back" and "### Why the state is re-read and the branch is not" — this
# script implements that table's `pr-to-ready`'s `--base` column.
#
# Usage: resolve-pr-base.sh <branch>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <branch>" >&2
  exit 1
fi

BRANCH="$1"

fetch_ref() {
  git fetch origin -- "$1" >&2
}

# The default branch is resolved by ../../implement-work/scripts/resolve-default-branch.sh
# -- see its header for the rationale.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Resolve the default branch before the scan below rather than at the two
# places that print it: the scan's range is expressed against it, so it has
# to be both named and fetched by then.
DEFAULT="$(bash "${SCRIPT_DIR}/../../implement-work/scripts/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }

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
if ! fetch_ref "${DEFAULT}"; then
  echo "STOP default-fetch-failed"
  exit 0
fi

if ! fetch_ref "${BRANCH}"; then
  echo "STOP fetch-failed"
  exit 0
fi

# The trailer scan, the prerequisite lookup, and the three answers both
# readers print identically live in
# ../../implement-work/scripts/read-base-trailer.sh -- see its header. What is
# left here is base-branch.md's `pr-to-ready`'s `--base` column: the three
# rows where the two readers disagree.
#
# The revs are chosen here rather than there because they are this caller's
# question. The scan runs from the branch tip just fetched and stops at the
# default branch, and the exclusion names the remote-tracking ref that fetch
# updated rather than a local branch that may be absent or stale. Unbounded,
# the scan walks to root, so a branch that recorded nothing picks up whatever
# Base-Branch some unrelated commit left in shared history and hands that
# branch back as --base -- which ensure-draft-pr.sh then passes to
# `gh pr create --base`, opening the PR against a branch this task never sat
# on.
#
# The call is guarded rather than left to `set -e` so that its exit-1 path --
# an unrecognised PR state, whose message it has already put on stderr --
# leaves this script exiting 1 with nothing on stdout, instead of a second
# message about the same thing.
if ! ANSWER="$(bash "${SCRIPT_DIR}/../../implement-work/scripts/read-base-trailer.sh" FETCH_HEAD "^refs/remotes/origin/${DEFAULT}")"; then
  exit 1
fi

read -r KIND RECORDED _ STATE <<<"$ANSWER"

case "${KIND}" in
  NO-TRAILER)
    echo "BASE ${DEFAULT}"
    ;;
  STOP)
    # Passed through unchanged: the slugs are this script's output contract,
    # and these five cases are answered identically by both readers,
    # which is why they are answered once, over there.
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
