#!/usr/bin/env bash
# Guard a PR review before it is written and read it back after.
#
# The choice is validated before any write, so an empty choice or
# REQUEST_CHANGES cannot post: the agent has no WRITE to act on.
#
# The read-back catches what the write calls' own success does not:
#   - a review not anchored to <head> (`review.commit`): the inline line
#     numbers were computed against that head, and left to default GitHub
#     anchors them to the PR's current head, so an author who pushed meanwhile
#     gets each comment on whatever line now sits at that number;
#   - a draft that was submitted, or an APPROVE/COMMENT left pending
#     (`review.state` against the choice);
#   - a body dropped by a step that did not carry it (`review.body-file`
#     against the payload's);
#   - the record of another repository, PR or review (the pins).
#
# Facts: ../../implement-work/references/facts.md.
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: post-review.sh <pr-number> <head-sha> <APPROVE|COMMENT|PENDING> <payload-file> [--posted <review-id>] [--facts <file>]
# Output: WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<EVENT>
#         | NEED <token>... | POSTED <state> <url>
#         | STOP review-pending-left | STOP review-state-mismatch | STOP <slug>
set -euo pipefail

# Checked before any argument: without jq the guard below answers usage, and the
# caller edits its argv instead of the missing dependency.
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but was not found on PATH" >&2
  exit 1
fi

usage() {
  echo "Usage: $0 <pr-number> <head-sha> <APPROVE|COMMENT|PENDING> <payload-file> [--posted <review-id>] [--facts <file>]" >&2
  exit 2
}

POSITIONAL=()
POSTED=''
FACTS=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --posted | --facts)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      if [ "$1" = --posted ]; then POSTED="$2"; else FACTS="$2"; fi
      shift 2
      ;;
    -*) usage ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
[ "${#POSITIONAL[@]}" -eq 4 ] || usage
PR="${POSITIONAL[0]}"
HEAD="${POSITIONAL[1]}"
EVENT="${POSITIONAL[2]}"
PAYLOAD_FILE="${POSITIONAL[3]}"

[[ "$PR" =~ ^[0-9]+$ ]] || usage
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || usage
case "$EVENT" in
  APPROVE) WANT=APPROVED ;;
  COMMENT) WANT=COMMENTED ;;
  PENDING) WANT=PENDING ;;
  *) usage ;;
esac
[ -r "$PAYLOAD_FILE" ] || usage
jq -e '.comments | length' "$PAYLOAD_FILE" >/dev/null 2>&1 || usage

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
TOOLS="${SCRIPT_DIR}/../../../tools"
if ! REPO="$(bash "${TOOLS}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

if [ -z "$POSTED" ]; then
  echo "WRITE repo=${REPO} pr=${PR} head=${HEAD} event=${EVENT}"
  exit 0
fi

if ! VERDICT="$(bash "${TOOLS}/facts.sh" check "$FACTS" \
  "repo=${REPO}" "pr.number=${PR}" "review.id=${POSTED}" "review.commit=${HEAD}" \
  'review.state:PENDING,APPROVED,COMMENTED' review.body-file review.url)"; then
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
  if ! value="$(bash "${TOOLS}/facts.sh" get "$FACTS" "$2")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  printf -v "$1" '%s' "$value"
}

fact STATE review.state
fact BODY_FILE review.body-file
BODY="$(jq -j '.body' "$PAYLOAD_FILE")"
if ! READ_BACK="$(cat -- "$BODY_FILE")"; then
  echo "STOP body-unreadable"
  exit 0
fi
if [ "$STATE" != "$WANT" ] || [ "$BODY" != "$READ_BACK" ]; then
  if [ "$STATE" = PENDING ]; then
    echo "STOP review-pending-left"
  else
    echo "STOP review-state-mismatch"
  fi
  exit 0
fi
fact URL review.url
echo "POSTED ${STATE} ${URL}"
