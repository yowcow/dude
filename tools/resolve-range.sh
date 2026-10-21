#!/usr/bin/env bash
# Resolve the committed range this review covers, printed as two SHAs.
#
# Two input shapes, one purpose. Given a PR number, the range is the PR's own
# head and its merge-base with the base OID the PR's record carries, both
# fetched: anything derived from the local checkout instead reviews whatever
# this working copy happens to sit on, which is not the PR's diff wherever the
# two have diverged, and nothing in the findings would say so. Given no
# argument, the range runs from the base this branch was cut from to HEAD, and
# that base is read back from the Base-Branch trailer rather than assumed.
#
# Reading it back is what the reviewed range depends on. Squash and rebase
# merges rewrite a prerequisite's commits under fresh SHAs, so falling back to
# the default branch where a prerequisite is recorded puts merge-base *below*
# that prerequisite and sweeps its whole diff into the range — the reviewer
# then reports findings against code this task never wrote. See
# skills/implement-work/references/base-branch.md, "## The contract",
# "## Reading the trailer back", "### Why the state is re-read and the branch
# is not" and "## Resolving the default branch" — this script implements that
# table's `review-code`'s `<base>` column.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: resolve-range.sh [pr-number] [--facts <file>]
# Output: RANGE <sha>..<sha> | EMPTY | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 [pr-number] [--facts <file>]" >&2
  exit 2
}

PR=''
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
      if [ -n "$PR" ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then usage; fi
      PR="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

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
  if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
    echo "STOP repo-lookup-failed"
    exit 0
  fi
  need "repo=${REPO}" "pr.number=${PR}" pr.base.sha
  BASE_OID='' # printf -v in fact is invisible to shellcheck; without this SC2153 fails lint
  fact BASE_OID pr.base.sha
  # Both ends are fetched, never assumed local: a PR somebody else opened has
  # a head this clone never held, and the base oid may be the base branch's
  # current tip rather than the fork point. The left end is therefore the
  # merge-base, so commits that reached the base after the PR was opened do
  # not show up as deletions by the PR.
  if ! HEAD_SHA="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "refs/pull/${PR}/head")" ||
    ! BASE_TIP="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${BASE_OID}")"; then
    echo "STOP fetch-failed"
    exit 0
  fi
  if ! BASE_SHA="$(git merge-base "$BASE_TIP" "$HEAD_SHA")"; then
    echo "STOP merge-base-failed"
    exit 0
  fi
  emit_range "${BASE_SHA}" "${HEAD_SHA}"
  exit 0
fi

# The default branch is resolved by tools/resolve-default-branch.sh
# -- see its header for the rationale.
# Fetch-default-first with a bounded scan, mirroring
# tools/resolve-pr-base.sh: the scan must stop at the
# default-branch tip, or a branch that recorded nothing picks up whatever
# Base-Branch trailer shared history left behind. The tip is saved as a SHA
# because the prerequisite fetch below rewrites FETCH_HEAD; the saved SHA is
# also the NO-TRAILER base, so that path fetches nothing further. A
# remote-tracking ref is not named in the exclusion: it goes stale with the
# clone's fetch history, while FETCH_HEAD is what the fetch just wrote.
DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }

if ! TIP_SHA="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}")"; then
  echo "STOP default-fetch-failed"
  exit 0
fi

# The trailer scan, the prerequisite lookup, and the three answers both
# readers print identically live in
# tools/read-base-trailer.sh -- see its header. What is
# left here is base-branch.md's `review-code`'s `<base>` column: the three
# rows where the two readers disagree.
#
# The revs are chosen here rather than there because it is this caller's
# question: local HEAD, bounded by the fetched default tip, since this skill
# reviews the checkout it is in.
READ_ARGS=(HEAD "^${TIP_SHA}")
if [ -n "$FACTS" ]; then
  READ_ARGS=(--facts "$FACTS" "${READ_ARGS[@]}")
fi
if ! ANSWER="$(bash "${SCRIPT_DIR}/read-base-trailer.sh" "${READ_ARGS[@]}")"; then
  echo "STOP trailer-read-failed"
  exit 0
fi

read -r KIND RECORDED PREREQ_PR STATE <<<"$ANSWER"

case "${KIND}" in
  NO-TRAILER)
    # The default tip is already fetched: merge-base against the saved SHA
    # rather than fetching again. FETCH_HEAD still holds it, but the name
    # would not survive a later fetch, and the SHA does.
    if ! BASE_SHA="$(git merge-base "${TIP_SHA}" HEAD)"; then
      echo "STOP merge-base-failed"
      exit 0
    fi
    HEAD_SHA="$(git rev-parse HEAD)"
    emit_range "${BASE_SHA}" "${HEAD_SHA}"
    exit 0
    ;;
  STOP | NEED)
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
      *)
        printf 'unrecognised prerequisite state: %s\n' "${STATE}" >&2
        echo "STOP trailer-answer-malformed"
        exit 0
        ;;
    esac
    ;;
  *)
    printf 'unrecognised answer from read-base-trailer.sh: %s\n' "${ANSWER}" >&2
    echo "STOP trailer-answer-malformed"
    exit 0
    ;;
esac

# Every prereq row fetches, and reads the fetched SHA rather than FETCH_HEAD or a
# remote-tracking ref: a fetch always writes FETCH_HEAD, whereas updating
# `refs/remotes/origin/<name>` depends on the clone's remote.origin.fetch
# refspec — which `refs/pull/<n>/head` sits outside of in every clone, and
# which a narrowed clone need not cover for the default branch either. Left to
# a tracking ref, a branch cut from a freshly fetched tip would be measured
# against whatever an older fetch wrote, putting merge-base *below* the fork
# point and sweeping somebody else's commits into the reviewed range.
if ! FETCH_SHA="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${FETCH_SPEC}")"; then
  echo "STOP fetch-failed"
  exit 0
fi

if ! BASE_SHA="$(git merge-base "$FETCH_SHA" HEAD)"; then
  echo "STOP merge-base-failed"
  exit 0
fi

HEAD_SHA="$(git rev-parse HEAD)"

emit_range "${BASE_SHA}" "${HEAD_SHA}"
