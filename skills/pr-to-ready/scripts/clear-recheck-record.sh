#!/usr/bin/env bash
# Remove the record ./recheck-pr.sh leaves in this worktree's git dir. The
# record outlives the run, so without this an earlier run's met record on the
# same SHA — a ready-on-clean = no run's, say — lets ./mark-ready.sh mark the
# PR ready in a run whose Step 3 never re-confirmed anything. Called from
# ../SKILL.md's 0-3, in the workspace just bound.
#
# Usage: clear-recheck-record.sh   (run from the workspace)
#
# Exit: 0 = no record remains, whether or not there was one
#       other = not inside a git working tree
set -euo pipefail

# An assignment rather than inline in the rm, so a failing rev-parse stops
# here: inside rm's argument it would leave `/dude-pr-to-ready-recheck` to
# remove and the script would answer 0 having cleared nothing.
RECORD="$(git rev-parse --git-dir)/dude-pr-to-ready-recheck"
rm -f -- "$RECORD"
