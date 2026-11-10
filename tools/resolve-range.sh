#!/usr/bin/env bash
# Resolve the committed range this review covers, printed as two SHAs. Given a PR
# number, the range is the PR's own head and its merge-base with the base OID its
# record carries, both fetched — never derived from the local checkout. Given no PR
# number, the range runs from the base read back from the issue's
# `Blocked-By: #N` line to HEAD, never assumed: falling back to the default
# branch where a prerequisite is recorded sweeps rewritten prerequisite commits
# into the range. Without --issue the base is the default branch.
# Spec: skills/implement-work/references/base-branch.md, "## Reading the
# prerequisite back" and "## Resolving the default branch" (this script
# implements that table's `review-code`'s `<base>` column).
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: resolve-range.sh [pr-number | --issue <n>] [--facts <file>]
# Output: RANGE <sha>..<sha> | EMPTY | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 [pr-number | --issue <n>] [--facts <file>]" >&2
  exit 2
}

PR=''
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
      if [ -n "$PR" ] || ! [[ "$1" =~ ^[0-9]+$ ]]; then usage; fi
      PR="$1"
      shift
      ;;
  esac
done
if [ -n "$ISSUE" ] && ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then usage; fi
# A PR's range is read from its own record; an issue passed beside it would be
# ignored silently.
if [ -n "$PR" ] && [ -n "$ISSUE" ]; then usage; fi

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
# The tip is saved as a SHA because the prerequisite fetch below rewrites
# FETCH_HEAD; the saved SHA is also the NO-PREREQ base, so that path fetches
# nothing further. A remote-tracking ref is not named: it goes stale with the
# clone's fetch history, while FETCH_HEAD is what the fetch just wrote.
DEFAULT="$(bash "${SCRIPT_DIR}/resolve-default-branch.sh")" || { echo "STOP ask-default-branch"; exit 0; }

if ! TIP_SHA="$(bash "${SCRIPT_DIR}/fetch-to-sha.sh" "${DEFAULT}")"; then
  echo "STOP default-fetch-failed"
  exit 0
fi

# The prerequisite lookup and the answers it prints live in
# tools/read-prereq-pr.sh -- see its header. What is left here is
# base-branch.md's `review-code`'s `<base>` column. Without --issue the reader
# answers NO-PREREQ and asks for no facts.
READ_ARGS=()
if [ -n "$FACTS" ]; then READ_ARGS+=(--facts "$FACTS"); fi
if [ -n "$ISSUE" ]; then READ_ARGS+=("$ISSUE"); fi
# An empty array is an unbound-variable error under set -u before bash 4.4.
if ! ANSWER="$(bash "${SCRIPT_DIR}/read-prereq-pr.sh" ${READ_ARGS[@]+"${READ_ARGS[@]}"})"; then
  echo "STOP prereq-read-failed"
  exit 0
fi

read -r KIND RECORDED PREREQ_PR STATE <<<"$ANSWER"

case "${KIND}" in
  NO-PREREQ)
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
