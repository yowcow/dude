#!/usr/bin/env bash
# Hand off's guard: pass only when Verify, Simplify and Review each last
# recorded (record-tree.sh) the very tree about to be pushed, and nothing is
# left uncommitted. Answers in one line, exit 0, the first that applies:
#   MISSING <phase>...  -- these phases have no record
#   DIRTY               -- uncommitted changes; `git status --porcelain` on stderr
#   STALE <phase>...    -- these phases recorded a tree other than HEAD^{tree}
#   OK <tree>           -- all three records equal HEAD^{tree}, tree clean
# Phases are listed in the order verify simplify review. Anything but OK
# sends the caller back to the completion gate's step 1.
# Conventions: references/script-conventions.md.
#
# Each record is compared to HEAD^{tree} rather than the three to each other:
# three records that agree but predate a later commit -- a base merge absorbed
# after them -- describe a tree no phase saw, and "each equals HEAD^{tree}"
# already implies "all three agree".
#
# The record path is shared with record-tree.sh: this worktree's own git dir,
# never the common dir.
# Usage: check-tree-records.sh
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 2
fi

RECORD_DIR="$(git rev-parse --absolute-git-dir)/dude-completion-gate"
HEAD_TREE="$(git rev-parse --verify 'HEAD^{tree}')"

MISSING=""
STALE=""
for phase in verify simplify review; do
  if [ ! -s "${RECORD_DIR}/${phase}" ]; then
    MISSING="${MISSING} ${phase}"
  elif [ "$(cat "${RECORD_DIR}/${phase}")" != "$HEAD_TREE" ]; then
    STALE="${STALE} ${phase}"
  fi
done

if [ -n "$MISSING" ]; then
  echo "MISSING${MISSING}"
  exit 0
fi

# What is pushed is commits only, so an edit still in the tree is not
# delivered even when every record matches HEAD^{tree}.
PENDING="$(git status --porcelain)"
if [ -n "$PENDING" ]; then
  echo "DIRTY"
  printf '%s\n' "$PENDING" >&2
  exit 0
fi

if [ -n "$STALE" ]; then
  echo "STALE${STALE}"
  exit 0
fi

echo "OK ${HEAD_TREE}"
