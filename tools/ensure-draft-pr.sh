#!/usr/bin/env bash
# Ensure a draft PR exists for a branch. The script reads no PR and opens
# none: it says what to read or do next, the agent opens the draft PR by its
# own means, and a second call reads the record back.
#
# The push-if-local-only check runs FIRST, on every call: resolving the base
# first would stop an unpushed local branch before it ever got pushed.
#
# After CREATE, the read-back pins head and base, so a mis-targeted create is
# never reported as created.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: ensure-draft-pr.sh <branch> [--issue <n>] [--created <base>] [--facts <file>]
#
# Output contract (single source; skills/pr-to-ready/SKILL.md cites this):
#   PR <n> found draft=<bool> url=<url> -- a PR already exists; leave its status as is.
#   CREATE repo=<owner>/<repo> head=<head> base=<base> -- no PR exists: open a
#     draft PR in <repo> from <head> onto <base>, then call again with the
#     same <branch>, plus --created <base> and facts read afresh
#     into a new file.
#     <base> is the default branch, or, when the --issue issue has a
#     `Blocked-By: #N` line whose prerequisite PR is OPEN, that PR's head.
#     Without --issue it is always the default branch: pass it only for an
#     issue of origin's repository. The read-back ignores --issue.
#   PR <n> created draft=<bool> base=<base> url=<url> -- the read-back after CREATE.
#   NEED <token>... -- read those facts and call again with --facts <file>.
#     Once a PR must be created it may also name the issue's facts
#     (`repo=... issue.number=... issue.body-file`, then `prereq.number=...
#     prereq.closing-pr`, then `pr.number=... pr.state pr.head.ref pr.head.owner=...`).
#   STOP <slug> -- no PR was opened; report the stop and hand the branch over
#     regardless.
set -euo pipefail

usage() {
  echo "Usage: $0 <branch> [--issue <n>] [--created <base>] [--facts <file>]" >&2
  exit 2
}

BRANCH=''
CREATED=''
FACTS=''
ISSUE=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --created | --facts | --issue)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      case "$1" in
        --created) CREATED="$2" ;;
        --facts) FACTS="$2" ;;
        *) ISSUE="$2" ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$1" ]; then usage; fi
      if [ -z "$BRANCH" ]; then BRANCH="$1"; else usage; fi
      shift
      ;;
  esac
done
if [ -z "$BRANCH" ]; then usage; fi
if [ -n "$ISSUE" ] && ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then usage; fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

need() {
  local verdict
  if ! verdict="$(bash "${SCRIPT_DIR}/facts.sh" check "$FACTS" "$@")"; then
    echo "STOP facts-read-failed"
    exit 0
  fi
  case "$verdict" in
    OK) return 0 ;;
    "NEED "?* | "STOP "?*) echo "$verdict" ;;
    *) echo "STOP facts-answer-malformed" ;;
  esac
  exit 0
}

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

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi
OWNER="${REPO%%/*}"

# --- Step 1: the branch must be on the remote before anything else runs. ---

# Same three-way read as attach-workspace.sh: --exit-code turns "no match"
# into a distinct status (2) instead of collapsing it into the same exit 0 as
# a real match, and any other non-zero is a genuine command failure rather
# than "not found".
set +e
git ls-remote --exit-code --heads origin -- "${BRANCH}" >/dev/null
remote_status=$?
set -e

if [ "${remote_status}" -eq 0 ]; then
  : # already on the remote, nothing to push
elif [ "${remote_status}" -eq 2 ]; then
  if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    # Explicit source and destination refspec, so this pushes exactly the
    # named branch regardless of what happens to be checked out here.
    if ! git push origin "refs/heads/${BRANCH}:refs/heads/${BRANCH}" >&2; then
      echo "STOP push-failed"
      exit 0
    fi
  else
    echo "STOP branch-nowhere"
    exit 0
  fi
else
  # A network or auth failure, not an answer about the branch. Exiting
  # non-zero here would hand the orchestrator a bare status with nothing on
  # stdout to branch on.
  echo "ls-remote failed for '${BRANCH}' (exit ${remote_status})" >&2
  echo "STOP ls-remote-failed"
  exit 0
fi

# --- Step 2: the branch's own PR. ---
SPECS=("repo=${REPO}" "head=${OWNER}:${BRANCH}" 'head.open-pr[]')
need "${SPECS[@]}"
fact COUNT head.open-pr.total

if [ -n "$CREATED" ]; then
  if [ "$COUNT" -eq 0 ]; then
    echo "STOP pr-not-created"
    exit 0
  fi
  if [ "$COUNT" -ge 2 ]; then
    echo "STOP ask-multiple-prs-after-create"
    exit 0
  fi
  fact NUM head.open-pr
  need "${SPECS[@]}" "pr.number=${NUM}" "pr.head.ref=${BRANCH}" "pr.head.owner=${OWNER}" "pr.base.ref=${CREATED}" 'pr.draft:true,false' pr.url
  fact DRAFT pr.draft
  fact URL pr.url
  echo "PR ${NUM} created draft=${DRAFT} base=${CREATED} url=${URL}"
  exit 0
fi

if [ "$COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi
if [ "$COUNT" -eq 1 ]; then
  fact NUM head.open-pr
  need "${SPECS[@]}" "pr.number=${NUM}" "pr.head.ref=${BRANCH}" "pr.head.owner=${OWNER}" 'pr.draft:true,false' pr.url
  fact DRAFT pr.draft
  fact URL pr.url
  echo "PR ${NUM} found draft=${DRAFT} url=${URL}"
  exit 0
fi

# --- Step 3: the base, from the sibling only. ---
RESOLVED_ARGS=("$BRANCH" --facts "$FACTS")
if [ -n "$ISSUE" ]; then
  RESOLVED_ARGS+=(--issue "$ISSUE")
fi
if ! RESOLVED="$(bash "${SCRIPT_DIR}/resolve-pr-base.sh" "${RESOLVED_ARGS[@]}")"; then
  echo "STOP base-resolve-failed"
  exit 0
fi
case "$RESOLVED" in
  STOP* | NEED*)
    echo "$RESOLVED"
    exit 0
    ;;
  "BASE "*) BASE="${RESOLVED#BASE }" ;;
  *)
    printf 'unexpected output from resolve-pr-base.sh: %s\n' "${RESOLVED}" >&2
    echo "STOP base-resolve-failed"
    exit 0
    ;;
esac

# --- Step 4: hand the create to the agent. The head is named, never left to
# default: a create's head defaults to the checked-out branch. ---
echo "CREATE repo=${REPO} head=${BRANCH} base=${BASE}"
