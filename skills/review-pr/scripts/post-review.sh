#!/usr/bin/env bash
# Post one PR review in the form the user chose: APPROVE or COMMENT submits it,
# PENDING leaves it unsubmitted for the user to finish on GitHub. Anything
# else -- an empty choice, REQUEST_CHANGES -- is refused before gh is called,
# so a run where nothing was chosen cannot post.
#
# PENDING is spelled by omitting `event`: that is how the REST endpoint creates
# a pending review, and sending event=PENDING is not.
#
# commit_id pins the review to the head that was reviewed. The inline line
# numbers in the payload were computed against that head; left to default,
# GitHub anchors them to the PR's current head, and an author who pushed in the
# meantime gets each comment on whatever line now sits at that number.
#
# The payload goes to gh on stdin, never through a flag string: review bodies
# carry backticks and quotes.
#
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: post-review.sh <owner> <repo> <pr-number> <head-sha> <APPROVE|COMMENT|PENDING> <payload-file>
# Output: POSTED <state> <url> | STOP review-post-failed
set -euo pipefail

usage() {
  echo "Usage: $0 <owner> <repo> <pr-number> <head-sha> <APPROVE|COMMENT|PENDING> <payload-file>" >&2
  exit 2
}

[ "$#" -eq 6 ] || usage

OWNER="$1"
REPO="$2"
PR="$3"
HEAD="$4"
EVENT="$5"
PAYLOAD_FILE="$6"

[[ "$PR" =~ ^[0-9]+$ ]] || usage
case "$EVENT" in
  APPROVE | COMMENT | PENDING) ;;
  *) usage ;;
esac
[ -r "$PAYLOAD_FILE" ] || usage

BODY="$(jq -c --arg c "$HEAD" --arg e "$EVENT" \
  '{commit_id: $c, body, comments} + (if $e == "PENDING" then {} else {event: $e} end)' \
  "$PAYLOAD_FILE" 2>/dev/null)" || usage

if ! OUT="$(printf '%s\n' "$BODY" |
  gh api --method POST "repos/${OWNER}/${REPO}/pulls/${PR}/reviews" --input - \
    --jq '"POSTED \(.state) \(.html_url)"' 2>/dev/null)"; then
  echo "STOP review-post-failed"
  exit 0
fi

printf '%s\n' "$OUT"
