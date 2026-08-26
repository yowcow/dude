#!/usr/bin/env bash
# Poll for a Copilot review whose id is not in the baseline recorded before the
# request, and print the lines list-copilot-reviews.sh gave for it.
#
# The baseline file holds that script's output taken *before* the review was
# requested — see ../references/gh-mechanics.md, "Recording the Copilot baseline",
# for why it has to be taken first.
#
# This exists as a command because the comparison is the difficulty. What is
# compared is the **id set**, never the record: a review keeps its id while its
# other fields move, so comparing whole records reports an existing review whose
# state changed — dismissed, say — as one that has just arrived. The caller reads
# that as Copilot having reviewed the current push, and can reach "clean" on a
# review that never happened.
#
# jq reads the ids, and jq's exit status is what decides, never its output: jq
# streams, so a file whose first lines parse and whose last does not prints ids
# and *then* fails, and reading the output alone would take that partial set for
# the whole baseline. `.id` has to BE a string rather than merely be present,
# because `jq -r` renders a missing key as `null` and a number as its digits,
# and either would enter the set as an id no review can ever match — a malformed
# baseline silently reduced to an empty one, which is what makes an old review
# read as new.
#
# An empty baseline file is normal on the first request: the set is empty, so
# every review is new.
#
# A *listing* this script cannot read — jq fails on it, or a line yields no id —
# is treated as a listing that has not arrived yet, exactly as a failing gh call
# is below, and never as a usage error: the caller cannot fix it and the next
# poll may return something readable. A malformed *baseline* is the opposite: it
# cannot fix itself by being read again, so it stops the script.
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
#       2 = usage error, the baseline file does not exist or cannot be read, or
#           it is not a list-copilot-reviews.sh listing
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

# One filter, used for the baseline and for the listing, so the two can never be
# judged by different rules.
ID_FILTER='if (.id | type) == "string" then .id else error("not a listing line") end'

# Read once, before the first poll: a baseline that is not a listing is a usage
# error, and finding that out after 20 minutes of polling would be no better
# than not finding it out at all.
if ! BASELINE_IDS="$(jq -r "$ID_FILTER" <"$BASELINE_FILE" 2>/dev/null)"; then
  echo "baseline file is not a list-copilot-reviews.sh listing: $BASELINE_FILE" >&2
  exit 2
fi

for _ in $(seq 1 "$MAX_ITER"); do
  # A failing listing is transient more often than fatal, and it prints nothing on
  # stdout either way, so it is indistinguishable here from "no review yet" — both
  # just wait for the next iteration.
  cur="$(bash "$SCRIPT_DIR/list-copilot-reviews.sh" "$OWNER" "$REPO" "$PR" 2>/dev/null || true)"

  if [ -n "$cur" ]; then
    # One line at a time, so the line printed is the line that was read: stdout
    # has to carry the bytes list-copilot-reviews.sh produced, and rebuilding the
    # object through jq would put that equality at the mercy of key order and
    # escaping. A here-string rather than a pipe into grep, because `grep -q`
    # exits on its first hit and would SIGPIPE the left-hand side under pipefail.
    new=()
    unreadable=""
    while IFS= read -r line; do
      if ! id="$(printf '%s\n' "$line" | jq -r "$ID_FILTER" 2>/dev/null)" || [ -z "$id" ]; then
        unreadable=1
        break
      fi
      if ! grep -qxF -- "$id" <<<"$BASELINE_IDS"; then
        new+=("$line")
      fi
    done <<<"$cur"

    if [ -z "$unreadable" ] && [ "${#new[@]}" -gt 0 ]; then
      printf '%s\n' "${new[@]}"
      exit 0
    fi
  fi

  sleep "$INTERVAL"
done

echo "no new Copilot review on ${OWNER}/${REPO}#${PR} within the poll bound" >&2
exit 1
