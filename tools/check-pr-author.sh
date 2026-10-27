#!/usr/bin/env bash
# Answer whether a PR's author is the user the agent's GitHub means acts as.
#
# review-code is the caller: it stops on OTHER, since its loop applies fixes to
# the working tree and would rewrite somebody else's code.
#
# It reads no GitHub itself. Without facts it answers NEED, pinning the PR to
# origin's repository and the number given, and an unread login is a STOP,
# never a guess as OTHER.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: check-pr-author.sh <pr-number> [--facts <file>]
# Output: SELF | OTHER | NEED <token>... | STOP <slug>
set -euo pipefail

usage() {
  echo "Usage: $0 <pr-number> [--facts <file>]" >&2
  exit 2
}

FACTS=''
case "$#" in
  1) ;;
  3)
    if [ "$2" != --facts ] || [ -z "$3" ]; then usage; fi
    FACTS="$3"
    ;;
  *) usage ;;
esac
if ! [[ "$1" =~ ^[0-9]+$ ]]; then usage; fi
PR="$1"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

if ! VERDICT="$(bash "${SCRIPT_DIR}/facts.sh" check "$FACTS" \
  "repo=${REPO}" "pr.number=${PR}" pr.author.login viewer.login)"; then
  echo "STOP facts-read-failed"
  exit 0
fi
case "$VERDICT" in
  OK) ;;
  "NEED "?* | "STOP "?*) echo "$VERDICT" ;;
  *) echo "STOP facts-answer-malformed" ;;
esac
[ "$VERDICT" = OK ] || exit 0

# fact <var> <name>: assign the value into the caller's variable. The value is
# never printed: called as $(fact ...) the exit 0 above would land in a
# subshell, leaving the caller running and reading "STOP ..." back as data.
fact() {
  local value
  if ! value="$(bash "${SCRIPT_DIR}/facts.sh" get "$FACTS" "$2")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  printf -v "$1" '%s' "$value"
}

fact AUTHOR pr.author.login
fact ME viewer.login

if [ "$AUTHOR" = "$ME" ]; then
  echo "SELF"
else
  echo "OTHER"
fi
