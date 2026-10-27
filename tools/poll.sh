#!/usr/bin/env bash
# Run a check command until it exits 0 or the iteration cap runs out. The
# canonical poll loop for single-predicate retries (`watch-copilot-review.sh`
# polls through it); not `watch-checks.sh`'s stateful settle loop.
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Any non-zero check exit means "not yet", even a failing `gh` call; a check
# that can never succeed burns the whole cap to exit 1 rather than failing
# fast. On success prints the attempt's stdout and exits 0; on cap-exhausted
# prints the last attempt's stdout and exits 1.
#
# Usage: poll.sh <max-iterations> <interval-seconds> <command> [args...]
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <max-iterations> <interval-seconds> <command> [args...]" >&2
  exit 2
fi

MAX="$1"
INTERVAL="$2"
shift 2

if ! [[ "$MAX" =~ ^[0-9]+$ ]] || [ "$MAX" -lt 1 ]; then
  echo "Usage: $0 <max-iterations> <interval-seconds> <command> [args...]" >&2
  exit 2
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 <max-iterations> <interval-seconds> <command> [args...]" >&2
  exit 2
fi

LAST_OUTPUT=""

i=0
while [ "$i" -lt "$MAX" ]; do
  i=$((i + 1))
  if output="$("$@" 2>/dev/null)"; then
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
    fi
    exit 0
  fi
  LAST_OUTPUT="$output"
  if [ "$i" -lt "$MAX" ]; then
    sleep "$INTERVAL"
  fi
done

if [ -n "$LAST_OUTPUT" ]; then
  printf '%s\n' "$LAST_OUTPUT"
fi
exit 1
