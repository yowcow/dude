#!/usr/bin/env bash
# Print the `### Suppressed comments (N)` block of Copilot's latest review on a
# PR, verbatim, or nothing when that review carries none.
#
# This exists as a command because Copilot's findings arrive on two paths and
# only one of them is a review thread. A finding Copilot judged low confidence is
# written into the review body instead, under `### Suppressed comments (N)`, and
# never becomes a thread — so list-unresolved-threads.sh cannot see it, and a
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
# Usage: list-suppressed-comments.sh <owner> <repo> <pr-number>
#
# Exit: 0 = the body was read — empty output means no suppressed comments
#       2 = usage error
#       other = the gh call failed — stop and inspect
#
# Empty output alone never means "no suppressed comments": read it together with
# the exit status, since a failing gh call prints nothing on stdout either.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"

# The block runs from its own heading to the `</details>` that closes the
# "Review details" section it sits in, and is printed as it stands. Parsing the
# entries out of it would tie this repository to Copilot's current formatting for
# no gain: the caller evaluates the text either way.
gh pr view "$PR" --repo "$OWNER/$REPO" --json reviews \
  --jq '.reviews
        | map(select((.author.login // "") | ascii_downcase | contains("copilot")))
        | sort_by(.submittedAt)
        | last
        | .body // ""' \
  | awk '/^### Suppressed comments/ { in_block = 1 }
         in_block && /^<\/details>/ { in_block = 0 }
         in_block { print }'
