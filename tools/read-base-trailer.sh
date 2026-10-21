#!/usr/bin/env bash
# Read a branch's Base-Branch trailer back and report the prerequisite's PR by
# its *current* state -- never by testing whether the prerequisite's branch
# still exists. One line on stdout, always:
#
#   NO-TRAILER                                  no trailer in the revs given
#   PREREQ <branch> <pr-number> <OPEN|MERGED>   the prerequisite and its state
#   NEED <token>...                             facts the caller reads, then runs again
#   STOP <slug>                                 the caller stops and says so
#
# This implements the cases of the state-to-base table where the two readers
# print the same bytes -- skills/implement-work/references/base-branch.md,
# "## Reading the trailer back". The rows where they differ (no trailer,
# OPEN, MERGED) stay with the callers: NO-TRAILER and PREREQ hand those
# decisions back rather than taking them here.
#
# Called as a subprocess by two other shared tools --
# tools/resolve-pr-base.sh and tools/resolve-range.sh -- and by no SKILL.md.
# There is deliberately no caller contract for it in any SKILL.md: it is one
# answer two skills need, and it lives here because the spec it implements
# does. Without this paragraph the next reader takes the absent caller for
# an oversight and either wires a contract for it into a SKILL.md that never
# calls it, or deletes the script as unreferenced.
# tools/resolve-default-branch.sh sits here for the same reason and says
# the same thing.
#
# The revs come from the caller and go straight to `git log`, because the two
# callers scan different histories: one reads a branch it has just fetched,
# bounded by the default branch; the other reads the checkout it is in. Which
# range is right is the caller's question, and a range decided here would be
# wrong for one of them with nothing reporting it.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: read-base-trailer.sh [--facts <file>] <rev>...
set -euo pipefail

usage() {
  echo "Usage: $0 [--facts <file>] <rev>..." >&2
  exit 2
}

FACTS=''
if [ "${1:-}" = --facts ]; then
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
  FACTS="$2"
  shift 2
fi
if [ "$#" -eq 0 ]; then usage; fi

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

# Capture the trailer scan into a variable before testing it, rather than
# piping into `grep`. A pipe would report only grep's exit status, and grep
# exits 1 on empty input whether the trailer is genuinely absent or the read
# itself failed -- two causes that must not collapse into "no trailer", since
# that answer sends both callers to the default branch. The read is guarded as
# well as captured: under `set -e` a failing `git log` inside a bare command
# substitution would kill the script outright, and the caller would get a
# non-zero exit with nothing on stdout instead of a STOP. Newest-first (git
# log's default order), since a trailer on a later commit shadows an earlier
# one in the same stack.
if ! TRAILER_LOG="$(git log "$@" --format='%(trailers:key=Base-Branch,valueonly,unfold)')"; then
  echo "STOP trailer-read-failed"
  exit 0
fi

# `NF` differs from a plain `[ -n "$line" ]` check only on a whitespace-only
# line, which this input cannot carry: git's own trailer-value parsing trims
# whitespace-only values to empty (independent of `unfold`, which only joins
# folded continuation lines).
RECORDED="$(awk 'NF{print;exit}' <<<"$TRAILER_LOG")"

if [ -z "$RECORDED" ]; then
  echo "NO-TRAILER"
  exit 0
fi

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

SPECS=("repo=${REPO}" "prereq.head=${REPO%%/*}:${RECORDED}" 'prereq.head-pr[]')
need "${SPECS[@]}"
fact COUNT prereq.head-pr.total
if [ "$COUNT" -eq 0 ]; then
  echo "STOP no-prereq-pr"
  exit 0
fi
if [ "$COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi
fact PR prereq.head-pr

# A PR's state has three values, and "not merged" would collapse the two that
# need opposite answers: a PR closed without merging is abandoned work, not
# work still in flight. CLOSED is answered here rather than by the callers
# because both callers answer it with the same byte.
SPECS+=("pr.number=${PR}" 'pr.state:OPEN,MERGED,CLOSED' "pr.head.ref=${RECORDED}" "pr.head.owner=${REPO%%/*}")
need "${SPECS[@]}"
fact STATE pr.state
case "$STATE" in
  OPEN | MERGED) echo "PREREQ ${RECORDED} ${PR} ${STATE}" ;;
  CLOSED) echo "STOP abandoned-prerequisite" ;;
esac
