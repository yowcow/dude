#!/usr/bin/env bash
# Find every branch (local and remote) already cut for an issue, deduplicated
# across both. `git branch --list` exits 0 whether or not it matched, so
# branching on its exit status would silently miss an existing branch and let
# a second one get cut for the same task.
# Usage: resolve-branch.sh <issue-number>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <issue-number>" >&2
  exit 1
fi

ISSUE="$1"

# The argument becomes a glob prefix below, so a non-numeric one widens the
# search instead of failing: `foo-*` matches every branch starting with "foo-",
# and a single such match reads as "this task already has a branch", sending
# the caller to attach to another task's work.
if ! [[ "${ISSUE}" =~ ^[0-9]+$ ]]; then
  echo "error: issue number must be numeric, got '${ISSUE}'" >&2
  exit 1
fi

LOCAL="$(git branch --list "${ISSUE}-*" --format='%(refname:short)')"

# --exit-code is required: without it, ls-remote also exits 0 on no match, so
# a real match and no match become indistinguishable by exit status. With it,
# 2 means "no match" (fine), any other non-zero means the command itself
# failed (stop).
set +e
REMOTE_RAW="$(git ls-remote --exit-code --heads origin "${ISSUE}-*")"
status=$?
set -e
if [ "$status" -eq 2 ]; then
  REMOTE_RAW=""
elif [ "$status" -ne 0 ]; then
  echo "error: git ls-remote failed for '${ISSUE}-*' (exit ${status})" >&2
  exit "$status"
fi

REMOTE=""
if [ -n "$REMOTE_RAW" ]; then
  # ls-remote prints "<sha>\trefs/heads/<name>"; strip down to the bare name
  # so it compares against the bare names `git branch --list` printed.
  REMOTE="$(printf '%s\n' "$REMOTE_RAW" | cut -f2 | sed 's#^refs/heads/##')"
fi

{
  if [ -n "$LOCAL" ]; then printf '%s\n' "$LOCAL"; fi
  if [ -n "$REMOTE" ]; then printf '%s\n' "$REMOTE"; fi
} | sort -u
