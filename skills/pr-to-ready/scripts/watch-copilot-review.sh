#!/usr/bin/env bash
# Poll for a Copilot review whose id is not in the baseline recorded before the
# request, and print the lines list-copilot-reviews.sh gave for it.
#
# The baseline file holds that script's output taken *before* the review was
# requested — see ../references/gh-mechanics.md, "Recording the Copilot baseline",
# for why it has to be taken first.
#
# This exists as a command because the comparison is the difficulty, and it fails
# silently in one specific way. `grep -v -F -x -f <baseline>` exits 1 when it
# filters out every line — which is exactly the "nothing new yet" case, not an
# error — so writing the usual `|| <fallback>` after it makes the fallback fire
# on success: the previous round's review comes back labelled new, and the caller
# judges the loop clean on a review submitted before the push it was meant to
# cover. Hence `|| true` here, and never a fallback that reprints the listing.
#
# An empty baseline file is normal on the first request and is handled by the
# same expression: with no patterns to match, every line survives the filter.
#
# Whether the new review is *actionable* is the caller's judgement, never this
# script's — Copilot commonly returns a comment-only verdict, so a review landing
# is not the same as feedback needing a fix.
#
# Usage: watch-copilot-review.sh <owner> <repo> <pr-number> <baseline-file> \
#          [max-iterations] [interval-seconds]
#        defaults: max-iterations 40, interval-seconds 30 (= 20 minutes)
#
# Exit: 0 = a review not in the baseline arrived — its listing printed
#       1 = none arrived before the iteration cap ran out
#       2 = usage error, or the baseline file does not exist or cannot be read
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 6 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <baseline-file> [max-iterations] [interval-seconds]" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"
BASELINE_FILE="$4"
MAX_ITER="${5:-40}"
INTERVAL="${6:-30}"

# Nothing downstream stops the run on a bad value here, and each parameter fails
# its own way. `seq` reads MAX_ITER: a non-numeric one makes `for _ in $(seq 1
# abc)` run the body zero times, so the script answers "no new review arrived"
# without ever polling, while a fractional one is truncated (2.9 polls twice),
# silently shrinking the budget the caller asked for. INTERVAL only reaches
# `sleep`, inside the loop, so a bad one dies there under `set -e` with exit 1 —
# the status this script also uses for "none arrived".
for n in "$MAX_ITER" "$INTERVAL"; do
  if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
    echo "max-iterations and interval-seconds must be positive integers: $n" >&2
    exit 2
  fi
done

# A missing or unreadable baseline file is a usage error rather than an empty
# baseline: the two are indistinguishable to the filter below, and silently
# treating "I forgot to record it" as "there was nothing" is what makes an old
# review read as new. Both tests are needed: a file that exists but cannot be
# read makes that filter exit 2, which the `|| true` below swallows as "nothing
# new yet" for the whole poll budget, and `-r` alone would admit a readable
# directory, which hits that same swallowed exit 2.
if [ ! -f "$BASELINE_FILE" ] || [ ! -r "$BASELINE_FILE" ]; then
  echo "baseline file not found or not readable: $BASELINE_FILE" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for _ in $(seq 1 "$MAX_ITER"); do
  # A failing listing is transient more often than fatal, and it prints nothing on
  # stdout either way, so it is indistinguishable here from "no review yet" — both
  # just wait for the next iteration.
  cur="$(bash "$SCRIPT_DIR/list-copilot-reviews.sh" "$OWNER" "$REPO" "$PR" 2>/dev/null || true)"

  if [ -n "$cur" ]; then
    new="$(printf '%s\n' "$cur" | grep -v -F -x -f "$BASELINE_FILE" || true)"
    if [ -n "$new" ]; then
      printf '%s\n' "$new"
      exit 0
    fi
  fi

  sleep "$INTERVAL"
done

echo "no new Copilot review on ${OWNER}/${REPO}#${PR} within the poll bound" >&2
exit 1
