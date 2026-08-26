#!/usr/bin/env bash
# Create a sub-issue of a parent issue and attach it to that parent, printing
# the new issue's number and URL before the attachment is attempted.
#
# The body is only ever read from a file. A sub-issue body carries backticked
# paths and fenced blocks by contract, and passing it as an inline flag string
# hands all of that to the shell. `gh api` wants a JSON payload rather than raw
# Markdown, hence the `jq -Rs` wrap (-R reads the file raw, -s slurps it into
# one string). The title is one line and rides in an argument, placed into the
# payload with --arg so it reaches the API as data rather than as jq syntax.
#
# `gh api` rather than `gh issue create`, because the number is then read
# straight out of the response: `gh issue create` prints only the URL, leaving
# the number to be parsed back out of it.
#
# The number and URL are printed **before** the child is attached. Attaching is
# a second API call that can fail on its own, and printed afterwards a failure
# would leave the caller holding a created issue it has no number for. Nothing
# lists it either — plan-work enumerates children from the native relation, so
# an unattached child is invisible there and the next run creates a second one
# for the same item.
#
# Attaching is delegated to the sibling ./link-sub-issue.sh rather than
# repeated here: that script resolves the issue number to the database id the
# endpoint actually wants, and reads the link back. A second copy of both would
# drift from it.
#
# The sibling is invoked through "$(dirname "${BASH_SOURCE[0]}")" — never a
# bare name or a cwd-relative path — because this script is normally run from
# somewhere other than its own directory. ensure-draft-pr.sh's header carries
# the longer form of that reason.
#
# Usage: create-sub-issue.sh <owner> <repo> <parent-number> <title> <body-file>
# Output: line 1 = the new issue's number, line 2 = its URL, line 3 = the
#         sibling's confirmation that it is attached
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "Usage: $0 <owner> <repo> <parent-number> <title> <body-file>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PARENT="$3"
TITLE="$4"
BODY_FILE="$5"

if ! [[ "$PARENT" =~ ^[0-9]+$ ]]; then
  echo "error: invalid issue number '$PARENT' (must be an integer)" >&2
  exit 1
fi

# `-r` as well as `-f`: with `-f` alone a file that exists with mode 000 walks
# through and only the `<"$BODY_FILE"` redirect fails, while the `gh` on the
# right of the pipeline is forked and runs regardless — the issue gets created
# after all, which is what this guard exists to prevent. post-plan-comment.sh's
# identical guard carries the longer form of the reason.
if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then
  echo "error: body file is not readable: $BODY_FILE" >&2
  exit 1
fi

# Captured rather than printed straight through, because the number is needed
# below as well; the printf puts it back on stdout before anything else runs.
CREATED="$(jq -Rs --arg t "$TITLE" '{title: $t, body: .}' <"$BODY_FILE" \
  | gh api --method POST "repos/$OWNER/$REPO/issues" --input - \
    --jq '.number, .html_url')"

printf '%s\n' "$CREATED"

CHILD="${CREATED%%$'\n'*}"

"$(dirname -- "${BASH_SOURCE[0]}")/link-sub-issue.sh" \
  "$OWNER" "$REPO" "$PARENT" "$CHILD"
