#!/usr/bin/env bash
# Project the `Suppressed comments (N)` block of Copilot's latest review on a PR
# down to what the clean judgment reads — `suppressed<TAB>N`, then one
# `path:line` per entry — or print nothing when that review carries none.
# `--full` prints the block verbatim instead, for the collection that has to read
# the findings themselves.
#
# This exists as a command because Copilot's findings arrive on two paths and
# only one of them is a review thread. A finding Copilot judged low confidence is
# written into the review body instead, under a `Suppressed comments (N)` block,
# and never becomes a thread — so list-unresolved-threads.sh cannot see it, and a
# clean judgment resting on that script alone reads a review carrying an
# unaddressed finding as carrying none. Measured on yowcow/dude#45, where a
# suppressed finding was valid and the run reported clean with it outstanding.
#
# **The review body's own `Comments generated: 0 new` excludes suppressed
# findings**, so that count is not the question this script answers.
#
# Only the latest review is read. The clean judgment is a property of one commit,
# and the latest Copilot review is the one that saw it; an earlier round's
# suppressed block would raise a finding already dealt with.
#
# This is a separate script rather than a `body` field on list-copilot-reviews.sh
# because that script's output *is* the baseline file watch-copilot-review.sh
# diffs line by line. A body in those lines makes any review whose body differs
# read as new.
#
# The login falls back to "" for the same reason as in list-copilot-reviews.sh: a
# review left by a since-deleted account comes back with author: null, and
# `null | ascii_downcase` aborts the whole filter. Why the login and never the
# timestamp: ../references/gh-mechanics.md.
#
# Usage: list-suppressed-comments.sh [--full] <owner> <repo> <pr-number>
#
# Exit: 0 = the body was read — empty output means no suppressed comments
#       2 = usage error
#       4 = the heading's N and the entries parsed out of the block disagree,
#           with nothing on stdout — Copilot's format moved, so stop rather
#           than read the block as carrying no findings
#       other = the gh call failed — stop and inspect
#
# Empty output alone never means "no suppressed comments": read it together with
# the exit status, since a failing gh call prints nothing on stdout either. One
# residue survives even that pairing: if Copilot renames the section itself, no
# line carries `Suppressed comments (N)`, and this exits 0 with nothing to print
# — which no caller can tell apart from a review that truly carries none.
set -euo pipefail

FULL=0
if [ "${1:-}" = '--full' ]; then
  FULL=1
  shift
fi

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 [--full] <owner> <repo> <pr-number>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"

# The block starts at the line carrying `Suppressed comments (N)` — a `###`
# heading in one Copilot shape, a `<summary>` in another — and runs to the next
# `</details>`.
fetch_block() {
  gh pr view "$PR" --repo "$OWNER/$REPO" --json reviews \
    --jq '.reviews
        | map(select((.author.login // "") | ascii_downcase | contains("copilot")))
        | sort_by(.submittedAt)
        | last
        | .body // ""' \
    | awk '/Suppressed comments \([0-9]+\)/ { in_block = 1 }
         in_block && /^<\/details>/ { in_block = 0 }
         in_block { print }'
}

# Parsing the entries does tie this to Copilot's current formatting, and the
# guard below is the price of that: if the format changes so the entry lines
# stop matching, the awk returns zero entries, the clean judgment reads "no
# suppressed findings", and a PR goes to ready carrying an unaddressed one —
# the same miss measured on yowcow/dude#45. Comparing the parsed count against
# the N the heading declares turns that into an explicit stop (exit 4) instead.

# --full is the collection subagent's path and hands back the block's own bytes,
# so it runs the pipeline directly rather than through a command substitution,
# which would strip trailing blank lines the block may carry.
if [ "$FULL" -eq 1 ]; then
  fetch_block
  exit 0
fi

block="$(fetch_block)"
if [ -z "$block" ]; then
  exit 0
fi

# N is read off the block's own start line by the same markup-blind rule that
# found it, so the `<summary>` shape reaches the clean judgment as its entries
# rather than as a block whose declared count the guard cannot find.
printf '%s\n' "$block" | awk '
  !have_heading && match($0, /Suppressed comments \([0-9]+\)/) {
    n = substr($0, RSTART, RLENGTH)
    sub(/^Suppressed comments \(/, "", n)
    sub(/\)$/, "", n)
    declared = n
    have_heading = 1
    next
  }
  /^\*\*[^*]+:[0-9]+(-[0-9]+)?\*\*$/ {
    e = $0
    sub(/^\*\*/, "", e)
    sub(/\*\*$/, "", e)
    entries[++count] = e
    next
  }
  END {
    if (!have_heading || count != declared) { exit 4 }
    printf "suppressed\t%s\n", declared
    for (i = 1; i <= count; i++) { print entries[i] }
  }'
