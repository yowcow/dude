#!/usr/bin/env bash
# Read the prerequisite line out of an issue body: the one line
# `Blocked-By: #<n>` plan-work writes into a stacked child, which
# implement-work's resolve-base.sh reads to pick the base.
# Format and reasons: skills/implement-work/references/base-branch.md.
#
# Only `Blocked-By: #<n>` exactly, alone on its line, is well formed; a
# near-miss answers MALFORMED rather than being skipped as no prerequisite,
# which would cut the task from the default branch without its prerequisite's
# changes. A CR ending a line is dropped first; an unreadable file exits 1 with
# nothing on stdout and the caller prints its own slug.
#
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Usage: prereq-line.sh <body-file>
# Output: NONE | PREREQ <n> | MULTIPLE | MALFORMED
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <body-file>" >&2
  exit 2
fi
if [ ! -f "$1" ] || [ ! -r "$1" ]; then
  exit 1
fi

WELL_FORMED='^Blocked-By: #([1-9][0-9]*)$'
count=0
n=''
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  lead="${line#"${line%%[![:space:]>*+0-9.)[\]xX-]*}"}"
  case "$lead" in
    [Bb][Ll][Oo][Cc][Kk][Ee][Dd][[:space:]-][Bb][Yy]*) ;;
    *) continue ;;
  esac
  count=$((count + 1))
  if [[ "$line" =~ $WELL_FORMED ]]; then
    n="${BASH_REMATCH[1]}"
  fi
done <"$1"

if [ "$count" -eq 0 ]; then
  echo NONE
elif [ "$count" -ge 2 ]; then
  echo MULTIPLE
elif [ -n "$n" ]; then
  echo "PREREQ ${n}"
else
  echo MALFORMED
fi
