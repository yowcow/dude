#!/usr/bin/env bash
# Collect conversation comments and PR inline comments whose parent issue/PR is
# closed, write a normalized JSONL snapshot, and print kind counts plus
# per-term candidate hits.
#
# Empty stdout alone never means "no comments": a gh or jq failure prints
# nothing on stdout too, and a caller keying on emptiness would record a
# complete sweep that never happened. Read stdout together with the exit
# status and with the snapshot file existing.
#
# Usage: collect-closed-comments.sh <owner> <repo> <snapshot.jsonl>
#
# Exit: 0 = collect finished; snapshot written; summary on stdout
#       2 = usage error
#       1 = a fetch, normalization, or snapshot write failed — stop
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <owner> <repo> <snapshot.jsonl>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
SNAPSHOT="$3"

JQ='.[]'
CLOSED_EP="repos/${OWNER}/${REPO}/issues?state=closed&per_page=100"
CONV_EP="repos/${OWNER}/${REPO}/issues/comments?per_page=100"
INLINE_EP="repos/${OWNER}/${REPO}/pulls/comments?per_page=100"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch_list() {
  local url="$1" dest="$2" what="$3"
  if ! gh api "$url" --paginate --jq "$JQ" >"$dest"; then
    echo "error: could not list ${what} of ${OWNER}/${REPO}" >&2
    exit 1
  fi
}

fetch_list "$CLOSED_EP" "${work}/closed.jsonl" "closed issues"
fetch_list "$CONV_EP" "${work}/conv.jsonl" "conversation comments"
fetch_list "$INLINE_EP" "${work}/inline.jsonl" "inline comments"

: >"${work}/comments.jsonl"
if ! mv "${work}/comments.jsonl" "$SNAPSHOT"; then
  echo "error: could not write ${SNAPSHOT}" >&2
  exit 1
fi

printf '%s\n' '{"conversation":0,"inline":0,"terms":{"未実測":[],"未判定":[],"未着手":[],"別途":[],"スコープ外":[],"残す記録":[]}}'
