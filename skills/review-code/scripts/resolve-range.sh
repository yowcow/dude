#!/usr/bin/env bash
# Resolve the committed range this review covers, printed as two SHAs.
#
# Two input shapes, one purpose. Given a PR number, the range is the PR
# record's own endpoints: anything derived from the local checkout instead
# reviews whatever this working copy happens to sit on, which is not the PR's
# diff wherever the two have diverged, and nothing in the findings would say
# so. Given no argument, the range runs from the base this branch was cut
# from to HEAD, and that base is read back from the Base-Branch trailer
# rather than assumed.
#
# Reading it back is what the reviewed range depends on. Squash and rebase
# merges rewrite a prerequisite's commits under fresh SHAs, so falling back to
# the default branch where a prerequisite is recorded puts merge-base *below*
# that prerequisite and sweeps its whole diff into the range — the reviewer
# then reports findings against code this task never wrote. See
# ../../implement-work/references/base-branch.md, "## The contract",
# "## Reading the trailer back", "### Why the state is re-read and the branch
# is not" and "## Resolving the default branch" — this script implements that
# table's `review-code`'s `<base>` column.
#
# Usage: resolve-range.sh [pr-number]
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [pr-number]" >&2
  exit 1
fi

PR="${1:-}"

# Both shapes answer through here, so an empty range is EMPTY however it was
# resolved. Handed `RANGE <sha>..<sha>` for a PR whose endpoints coincide, the
# caller would dispatch a reviewer over an empty diff and read the no-findings
# that comes back as a clean review.
emit_range() {
  if [ "$1" = "$2" ]; then
    echo "EMPTY"
  else
    echo "RANGE $1..$2"
  fi
}

if [ -n "$PR" ]; then
  if ! ENDS="$(gh pr view "$PR" --json baseRefOid,headRefOid --jq '"\(.baseRefOid) \(.headRefOid)"' 2>/dev/null)"; then
    echo "STOP pr-lookup-failed"
    exit 0
  fi
  emit_range "${ENDS%% *}" "${ENDS##* }"
  exit 0
fi

# The default branch is resolved by ../../implement-work/scripts/resolve-default-branch.sh
# -- see its header for the rationale.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# The trailer scan, the prerequisite lookup, and the three answers both
# readers print identically live in
# ../../implement-work/scripts/read-base-trailer.sh -- see its header. What is
# left here is base-branch.md's `review-code`'s `<base>` column: the three
# rows where the two readers disagree.
#
# The rev is chosen here rather than there because it is this caller's
# question: local HEAD, not a fetched ref, since this skill reviews the
# checkout it is in.
#
# The call is guarded rather than left to `set -e` so that its exit-1 path --
# an unrecognised PR state, whose message it has already put on stderr --
# leaves this script exiting 1 with nothing on stdout, instead of a second
# message about the same thing.
if ! ANSWER="$(bash "${SCRIPT_DIR}/../../implement-work/scripts/read-base-trailer.sh" HEAD)"; then
  exit 1
fi

read -r KIND RECORDED PREREQ_PR STATE <<<"$ANSWER"

case "${KIND}" in
  NO-TRAILER)
    FETCH_SPEC="$(bash "${SCRIPT_DIR}/../../implement-work/scripts/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }
    ;;
  STOP)
    # Passed through unchanged: the slugs are this script's output contract,
    # and these five cases are answered identically by both readers,
    # which is why they are answered once, over there.
    printf '%s\n' "$ANSWER"
    exit 0
    ;;
  PREREQ)
    case "${STATE}" in
      OPEN)
        FETCH_SPEC="${RECORDED}"
        ;;
      MERGED)
        # The prerequisite's own head, not the default branch: it bounds the
        # range whatever the merge strategy was, and `refs/pull/<n>/head`
        # outlives both the merge and the branch's deletion.
        FETCH_SPEC="refs/pull/${PREREQ_PR}/head"
        ;;
    esac
    ;;
esac

# Every row fetches, and every row reads FETCH_HEAD rather than a
# remote-tracking ref: a fetch always writes FETCH_HEAD, whereas updating
# `refs/remotes/origin/<name>` depends on the clone's remote.origin.fetch
# refspec — which `refs/pull/<n>/head` sits outside of in every clone, and
# which a narrowed clone need not cover for the default branch either. Left to
# a tracking ref, a branch cut from a freshly fetched tip would be measured
# against whatever an older fetch wrote, putting merge-base *below* the fork
# point and sweeping somebody else's commits into the reviewed range.
if ! git fetch origin -- "${FETCH_SPEC}" >&2; then
  echo "STOP fetch-failed"
  exit 0
fi

if ! BASE_SHA="$(git merge-base FETCH_HEAD HEAD)"; then
  echo "STOP merge-base-failed"
  exit 0
fi

HEAD_SHA="$(git rev-parse HEAD)"

emit_range "${BASE_SHA}" "${HEAD_SHA}"
