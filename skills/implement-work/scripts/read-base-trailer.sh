#!/usr/bin/env bash
# Read a branch's Base-Branch trailer back and report the prerequisite's PR by
# its *current* state -- never by testing whether the prerequisite's branch
# still exists. One line on stdout, always:
#
#   NO-TRAILER                                  no trailer in the revs given
#   PREREQ <branch> <pr-number> <OPEN|MERGED>   the prerequisite and its state
#   STOP <slug>                                 the caller stops and says so
#
# This implements the cases of the state-to-base table where the two readers
# print the same bytes -- ../references/base-branch.md, "## Reading the trailer
# back". The rows where they differ (no trailer, OPEN, MERGED) stay with the
# callers: NO-TRAILER and PREREQ hand those decisions back rather than taking
# them here.
#
# Called as a subprocess by two scripts in two other skills --
# ../../pr-to-ready/scripts/resolve-pr-base.sh and
# ../../review-code/scripts/resolve-range.sh -- and by no SKILL.md, this
# skill's own included. There is deliberately no caller contract for it in
# implement-work/SKILL.md: it is one answer two skills need, and it lives here
# because the spec it implements does. Without this paragraph the next reader
# takes the absent caller for an oversight and either wires a contract for it
# into a SKILL.md that never calls it, or deletes the script as unreferenced.
# ../scripts/resolve-default-branch.sh sits here for the same reason and says
# the same thing.
#
# The default branch is deliberately NOT resolved here, although two of the
# three rows left to the callers name it. Resolving it would mean a `gh` call
# on every path, and resolve-range.sh reaches that lookup only on its no-trailer
# branch -- the answer is the same either way, but the extra call is observable,
# and the callers' tests assert the number of `gh` calls precisely because a
# script that stopped asking and started guessing would otherwise pass.
#
# The revs come from the caller and go straight to `git log`, because the two
# callers scan different histories: one reads a branch it has just fetched,
# bounded by the default branch; the other reads the checkout it is in. Which
# range is right is the caller's question, and a range decided here would be
# wrong for one of them with nothing reporting it.
#
# Usage: read-base-trailer.sh <rev>...
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <rev>..." >&2
  exit 1
fi

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

# The newest non-empty trailer value wins (git log's default order), so the
# scan stops at the first one. `NF` and the loop's `[ -n "$line" ]` differ
# only on a whitespace-only line, which this input cannot carry: git's own
# trailer-value parsing trims whitespace-only values to empty (independent of
# `unfold`, which only joins folded continuation lines).
RECORDED="$(awk 'NF{print;exit}' <<<"$TRAILER_LOG")"

if [ -z "$RECORDED" ]; then
  echo "NO-TRAILER"
  exit 0
fi

# Read the exit status and the line count together. A non-zero exit prints
# nothing and looks exactly like "no PR" -- auth, network, or repo-context
# failures behave the same way -- so it is "couldn't tell", not "no match".
# `.[]` rather than `.[0]` so an empty list yields zero lines and several
# matches yield several, instead of one arbitrary pick or an interpolated
# "null". The lookup is by head branch *name*, which the PR record keeps after
# the branch is gone.
if ! PR_LOOKUP="$(gh pr list --head "$RECORDED" --state all --json number,state --jq '.[] | "\(.number) \(.state)"' 2>/dev/null)"; then
  echo "STOP prereq-lookup-failed"
  exit 0
fi

# `grep -c .` counts non-empty lines, so an empty lookup counts as 0 rather
# than the 1 `wc -l` would report — "no PR" must not read as "exactly one".
# It exits 1 on a zero count while still printing it, hence `|| true`. The
# two differ only on interior blank lines, which the `--jq` above cannot
# produce.
LINE_COUNT="$(grep -c . <<<"$PR_LOOKUP" || true)"

if [ "$LINE_COUNT" -eq 0 ]; then
  echo "STOP no-prereq-pr"
  exit 0
fi

if [ "$LINE_COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi

STATE="${PR_LOOKUP##* }"

# A PR's state has three values, and "not merged" would collapse the two that
# need opposite answers: a PR closed without merging is abandoned work, not
# work still in flight. CLOSED is answered here rather than by the callers
# because both callers answer it with the same byte.
case "${STATE}" in
  OPEN | MERGED)
    echo "PREREQ ${RECORDED} ${PR_LOOKUP%% *} ${STATE}"
    ;;
  CLOSED)
    echo "STOP abandoned-prerequisite"
    ;;
  *)
    echo "error: unexpected PR state '${STATE}' for '${RECORDED}'" >&2
    exit 1
    ;;
esac
