#!/usr/bin/env bash
# Poll the check-runs on one commit until none is still queued or in_progress,
# then print one line per check: "<name>\t<status>\t<conclusion>".
#
# This exists as a command because the polling predicate is the whole difficulty.
# The obvious way to write it — fetch, grep for "in_progress", stop when the grep
# finds nothing — reports "all checks settled" for any response that merely fails
# to contain that word, and an error body qualifies. Ask for a SHA that is not on
# the remote and this surface answers 200-shaped JSON carrying
# {"message":"No commit found for SHA: ...","status":"422"}: no "in_progress"
# anywhere in it, so the naive predicate calls CI settled and the caller marks a
# PR ready having never read a check. So the response is validated for the
# total_count field before it is believed, and a missing commit is reported as
# its own exit status rather than as an empty run list.
#
# Whether the checks *pass* is the caller's judgement, never this script's: it
# reports the conclusions and stops there. A skipped check is not a failure, and
# an empty run list is not a pass — only the caller knows which checks the PR
# needs. Why the orchestrator keeps that judgement: ../SKILL.md, "Orchestration
# model".
#
# Usage: watch-checks.sh <owner> <repo> <sha> [max-iterations] [interval-seconds]
#        defaults: max-iterations 60, interval-seconds 20 (= 20 minutes)
#
# Exit: 0 = every check on the commit has settled — the listing printed
#       1 = still unsettled when the iteration cap ran out (the last listing printed)
#       2 = usage error
#       3 = no such commit on the remote — the SHA is wrong, or was never pushed
#       4 = no check-runs listing could be read at all — every poll either
#           failed or answered something that is not a run list
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  echo "Usage: $0 <owner> <repo> <sha> [max-iterations] [interval-seconds]" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
SHA="$3"
MAX_ITER="${4:-60}"
INTERVAL="${5:-20}"

# Nothing downstream stops the run on a bad value here, and each parameter fails
# its own way. `seq` reads MAX_ITER: a non-numeric one makes `for _ in $(seq 1
# abc)` run the body zero times, so the script answers "no listing could be
# read" without ever calling the API, while a fractional one is truncated (2.9
# polls twice), silently shrinking the budget the caller asked for. INTERVAL
# only reaches `sleep`, inside the loop, so a bad one dies there under `set -e`
# with exit 1 — the status this script also uses for "still unsettled".
for n in "$MAX_ITER" "$INTERVAL"; do
  if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
    echo "max-iterations and interval-seconds must be positive integers: $n" >&2
    exit 2
  fi
done

rows=""
saw_listing=""

for _ in $(seq 1 "$MAX_ITER"); do
  # A failing gh call is transient far more often than fatal (rate limit, a blip),
  # so it does not end the watch; the iteration cap is what ends it. The one
  # failure worth ending on is a SHA the remote does not have, because no amount
  # of waiting fixes it and every later iteration would ask the same wrong
  # question.
  raw="$(gh api "repos/${OWNER}/${REPO}/commits/${SHA}/check-runs" 2>/dev/null || true)"

  if printf '%s' "$raw" | grep -q 'No commit found for SHA'; then
    printf '%s\n' "$raw" >&2
    exit 3
  fi

  # total_count is the field that separates a real listing from an error body.
  # Testing for it — rather than for the absence of "in_progress" — is what keeps
  # an error from reading as "nothing is running".
  if printf '%s' "$raw" | jq -e 'has("total_count")' >/dev/null 2>&1; then
    saw_listing=yes
    rows="$(printf '%s' "$raw" | jq -r '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion // "-")"')"

    # An empty run list is not "settled": on a just-pushed commit the checks have
    # not registered yet, and treating that as done would report a PR with no CI
    # as a PR whose CI passed.
    # The status is tested on the JSON rather than by grepping the rendered rows:
    # a check whose *name* contains "in_progress" makes a row-wide match read a
    # completed check as still running, and the watch then never settles.
    if [ -n "$rows" ] && ! printf '%s' "$raw" | jq -e 'any(.check_runs[]; .status == "queued" or .status == "in_progress")' >/dev/null 2>&1; then
      printf '%s\n' "$rows"
      exit 0
    fi
  fi

  sleep "$INTERVAL"
done

if [ -z "$saw_listing" ]; then
  echo "no check-runs listing could be read for ${SHA}" >&2
  exit 4
fi

if [ -n "$rows" ]; then
  printf '%s\n' "$rows"
fi
exit 1
