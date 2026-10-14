#!/usr/bin/env bash
# Read the prerequisite line out of an issue body: the one line
# `Blocked-By: #<n>` plan-work writes into a stacked child, which
# implement-work's resolve-base.sh reads to pick the base. Both sides parse
# through here, so a line the writer's read-back accepts is one the reader
# accepts. Format and reasons: skills/implement-work/references/base-branch.md.
#
# A line is a prerequisite line when, after any leading whitespace, list
# marker or quote, it begins `blocked-by` or `blocked by` in any case; only
# `Blocked-By: #<n>` exactly, alone on its line, is well formed. A near-miss
# answers MALFORMED rather than being skipped: skipped, `Blocked-by #571`
# reads as no prerequisite, and the task is cut from the default branch
# without its prerequisite's changes. `owner/repo#<n>` is malformed too: the
# base is looked up in origin's repository, where that number names another
# issue.
#
# A carriage return ending a line is dropped first: a body saved from the web
# editor ends its lines in CRLF, and every such line would otherwise read as
# malformed.
#
# Answers through its caller: an unreadable file exits 1 with nothing on
# stdout, and the caller prints its own slug.
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
