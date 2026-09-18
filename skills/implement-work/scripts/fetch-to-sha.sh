#!/usr/bin/env bash
# Fetch one ref from origin and print its tip SHA on stdout.
#
# This is the canonical fetch-to-SHA source: `resolve-range.sh` and
# `retarget-pr.sh` each inline this fetch plus a `git rev-parse FETCH_HEAD`
# today, and `resolve-pr-base.sh` inlines the fetch with its own FETCH_HEAD
# use (item 3 migrates them onto this script).
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs callers print for the exit-1 path:
# skills/implement-work/references/stop-registry.md
# (`default-fetch-failed`, `fetch-failed`, `branch-fetch-failed`).
#
# The exit-1 path prints nothing so the caller can print its own STOP slug:
# a slug printed here would land in the caller's command substitution and be
# read back as a SHA (resolve-default-branch.sh precedent). FETCH_HEAD is
# read before anything else can fetch again and rewrite it (conventions doc).
#
# Usage: fetch-to-sha.sh <ref>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <ref>" >&2
  exit 2
fi

REF="$1"

if ! git fetch origin -- "$REF" >/dev/null 2>&1; then
  exit 1
fi

if ! SHA="$(git rev-parse FETCH_HEAD 2>/dev/null)" || [ -z "$SHA" ]; then
  exit 1
fi

printf '%s\n' "$SHA"
