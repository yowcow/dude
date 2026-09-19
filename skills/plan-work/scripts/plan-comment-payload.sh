#!/usr/bin/env bash
# Guard a plan body file and print the JSON payload both plan-work posting
# scripts send: the single shared copy of the readability guard and the
# `jq -Rs` wrap (post-plan-comment.sh POSTs it, edit-plan-comment.sh PATCHes
# it). The callers' `check_gh_stdin` goldens pin these bytes, so this filter
# must stay `jq -Rs` (raw, slurped): `jq -R` sends one JSON document per line
# under the same argv.
#
# Usage: plan-comment-payload.sh <body-file>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <body-file>" >&2
  exit 2
fi

BODY_FILE="$1"

# `-r` as well as `-f`, because `-r` asks access(2) — the same question the
# `<"$BODY_FILE"` redirect below asks. With `-f` alone a file that exists with
# mode 000 walks through, and only the redirect fails.
if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then
  echo "error: body file is not readable: $BODY_FILE" >&2
  exit 1
fi

jq -Rs '{body: .}' <"$BODY_FILE"
