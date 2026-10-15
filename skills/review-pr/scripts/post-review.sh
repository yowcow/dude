#!/usr/bin/env bash
# Guard a PR review before it is written and read it back after: the choice is
# APPROVE or COMMENT (submitted) or PENDING (left unsubmitted for the user to
# finish on GitHub).
#
# It writes nothing and calls no GitHub client. The first call answers WRITE;
# the agent then creates a pending review anchored to <head>, adds each inline
# comment, and submits it unless the choice is PENDING. The call with
# `--posted <review-id>` reads the record back through facts.
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
# Output: WRITE repo=<owner>/<repo> pr=<n> head=<sha> event=<EVENT> comments=<k>
#         | NEED <token>... | POSTED <state> <url>
#         | STOP review-pending-left | STOP review-state-mismatch | STOP <slug>
set -euo pipefail

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
COMMENTS="$(jq -e '.comments | length' "$PAYLOAD_FILE" 2>/dev/null)" || usage

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
TOOLS="${SCRIPT_DIR}/../../../tools"
if ! REPO="$(bash "${TOOLS}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi

if [ -z "$POSTED" ]; then
  echo "WRITE repo=${REPO} pr=${PR} head=${HEAD} event=${EVENT} comments=${COMMENTS}"
  exit 0
fi

VERDICT="$(bash "${TOOLS}/facts.sh" check "$FACTS" \
  "repo=${REPO}" "pr.number=${PR}" "review.id=${POSTED}" "review.commit=${HEAD}" \
  'review.state:PENDING,APPROVED,COMMENTED' review.body-file review.url)"
if [ "$VERDICT" != OK ]; then
  echo "$VERDICT"
  exit 0
fi

fact() { bash "${TOOLS}/facts.sh" get "$FACTS" "$1"; }
STATE="$(fact review.state)"
BODY="$(jq -j '.body' "$PAYLOAD_FILE")"
if [ "$STATE" != "$WANT" ] || [ "$BODY" != "$(cat -- "$(fact review.body-file)")" ]; then
  if [ "$STATE" = PENDING ]; then
    echo "STOP review-pending-left"
  else
    echo "STOP review-state-mismatch"
  fi
  exit 0
fi
echo "POSTED ${STATE} $(fact review.url)"
