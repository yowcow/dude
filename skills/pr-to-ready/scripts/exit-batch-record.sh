#!/usr/bin/env bash
# Mark the pr-to-ready run batched, probe it, or clear the mark. The Exit
# batch runs once per run: the first set marks it, a second set is refused,
# and 0-3 clears the mark so a new run starts unbatched. The record lives in
# this worktree's git dir, beside ./clear-recheck-record.sh's, never in the
# tree, so committing and pushing never carry it.
#
# Usage: exit-batch-record.sh check|set|clear   (run from the workspace)
#
# stdout, one line: NO-BATCH (check, absent), BATCHED (set, first),
# ALREADY-BATCHED (check or set, present), nothing (clear).
# Exit: 0 = NO-BATCH, BATCHED, or cleared (whether or not there was one);
#       1 = ALREADY-BATCHED; 2 = usage error, detail on stderr.
# A usage error prints `Usage: ...` on stderr, nothing on stdout.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 check|set|clear" >&2
  exit 2
fi

# An assignment rather than inline, so a failing rev-parse stops here: inside
# an argument it would leave `/dude-pr-to-ready-exit-batch` to act on and the
# script would answer about nothing.
RECORD="$(git rev-parse --git-dir)/dude-pr-to-ready-exit-batch"

case "$1" in
  check)
    if [ -e "$RECORD" ]; then
      echo 'ALREADY-BATCHED'
      exit 1
    fi
    echo 'NO-BATCH'
    ;;
  set)
    if [ -e "$RECORD" ]; then
      echo 'ALREADY-BATCHED'
      exit 1
    fi
    printf 'batched\n' >"$RECORD"
    echo 'BATCHED'
    ;;
  clear)
    rm -f -- "$RECORD"
    ;;
  *)
    echo "Usage: $0 check|set|clear" >&2
    exit 2
    ;;
esac
