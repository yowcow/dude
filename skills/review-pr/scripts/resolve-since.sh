#!/usr/bin/env bash
# Decide whether a later review round can be narrowed to the commits pushed
# since the viewer's last review of this PR, from the `viewer.review.commit`
# fact and the commit graph alone.
#
# Two silent failures this guards. A base merged into the PR after the last
# review would sweep the base's own changes into the reviewed range: the range
# since that review is only the author's work when the review commit still
# descends from the base. And a force-pushed commit gives no range at all: a
# review commit that is not in the head's history, or is absent from this
# clone, answers STOP rather than a range git cannot compute.
#
# Facts: ../../implement-work/references/facts.md.
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: resolve-since.sh <pr-number> <base-sha> <head-sha> [--facts <file>]
# Output: WHOLE | SINCE <sha> | UNCHANGED | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 <pr-number> <base-sha> <head-sha> [--facts <file>]" >&2
  exit 2
}

FACTS=''
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --facts)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      FACTS="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

[ "${#ARGS[@]}" -eq 3 ] || usage
PR="${ARGS[0]}"
BASE="${ARGS[1]}"
HEAD_SHA="${ARGS[2]}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage
if [ -z "$BASE" ] || [ -z "$HEAD_SHA" ]; then usage; fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
FACTS_SH="${SCRIPT_DIR}/../../../tools/facts.sh"

need() {
  local verdict
  if ! verdict="$(bash "$FACTS_SH" check "$FACTS" "$@")"; then
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
  if ! value="$(bash "$FACTS_SH" get "$FACTS" "$2")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  printf -v "$1" '%s' "$value"
}

if ! REPO="$(bash "${SCRIPT_DIR}/../../../tools/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi
need "repo=${REPO}" "pr.number=${PR}" 'viewer.review.commit[]'

TOTAL='' # printf -v in fact is invisible to shellcheck
COMMITS=''
fact TOTAL viewer.review.commit.total
if [ "$TOTAL" = 0 ]; then
  echo "WHOLE"
  exit 0
fi
fact COMMITS viewer.review.commit
LAST="${COMMITS##*$'\n'}"

# Exit 1 (not an ancestor) and 128 (commit absent from the clone) both mean no
# range can be computed from the review commit.
if ! git merge-base --is-ancestor "$LAST" "$HEAD_SHA"; then
  echo "STOP ask-since-rewritten"
  exit 0
fi
if ! git merge-base --is-ancestor "$BASE" "$LAST"; then
  echo "STOP ask-since-base-merged"
  exit 0
fi

if [ "$LAST" = "$HEAD_SHA" ]; then
  echo "UNCHANGED"
else
  echo "SINCE ${LAST}"
fi
