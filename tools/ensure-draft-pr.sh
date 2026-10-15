#!/usr/bin/env bash
# Ensure a draft PR exists for a branch. The script reads no PR and opens
# none: it says what to read or do next, the agent opens the draft PR by its
# own means, and a second call reads the record back.
#
# The push-if-local-only check runs FIRST, on every call, before any fact is
# asked for. resolve-pr-base.sh fetches the branch to read its Base-Branch
# trailer, so it hard-stops on a branch that isn't on the remote yet;
# resolving the base before pushing would stop an unpushed local branch
# before it ever got pushed.
#
# The branch's PR is looked up by its owner-qualified head in the target
# repository, and the one PR found is read from its own record with its head
# pinned: a means that ignores the head filter returns unrelated PRs, and one
# of them would otherwise be reported as this branch's PR.
#
# No base is taken as an argument. The sibling ./resolve-pr-base.sh resolves
# one, only after no PR was found -- an existing PR needs no base.
#
# Which repository the PR targets is asked of a person, never detected: with
# no [base-repo], a remote beside origin or origin being a fork answers
# STOP ask-base-repo. Fork-ness is the fact `repo.fork`, asked only once no
# PR was found and no other remote decided it; an unread value, or a read that
# found no repository record, stops instead of reading as "not a fork", which
# would open the PR against the fork when its owner meant the parent.
#
# After CREATE the agent opens the PR and calls again with the same arguments
# plus --created <base>, and facts read afresh. The read-back pins the record's
# head and base: a create whose head defaulted to the checked-out branch reads
# back no PR, and one opened onto another base is a mismatch -- neither is
# reported as created.
#
# The sibling is invoked through SCRIPT_DIR (conventions): this script runs
# from anywhere, and a bare name dies under `set -e` with a bash error instead
# of the contracted STOP.
#
# Facts: skills/implement-work/references/facts.md.
# Conventions: skills/implement-work/references/script-conventions.md.
# STOP slugs: skills/implement-work/references/stop-registry.md.
#
# Usage: ensure-draft-pr.sh <branch> [<base-repo>] [--created <base>] [--facts <file>]
#
# Output contract (single source; skills/implement-work/SKILL.md cites this):
#   PR <n> found draft=<bool> url=<url> -- a PR already exists; leave its status as is.
#   CREATE repo=<owner>/<repo> head=<head> base=<base> -- no PR exists: open a
#     draft PR in <repo> from <head> onto <base>, then call again with the
#     same <branch> [<base-repo>], plus --created <base> and facts read afresh
#     into a new file; without the base-repo the read-back looks in origin.
#   PR <n> created draft=<bool> base=<base> url=<url> -- the read-back after CREATE.
#   NEED <token>... -- read those facts and call again with --facts <file>.
#   STOP ask-base-repo -- origin is a fork or has a sibling remote, and no
#     base-repo was given: ask which repository to target, call again with it.
#   STOP <slug> -- no PR was opened; report the stop and hand the branch over regardless.
#
# Parent-targeted limitation: [base-repo] reaches the PR lookup and the
# default-branch name; the fetches and the prerequisite lookup still run
# against origin, in the child's context.
set -euo pipefail

usage() {
  echo "Usage: $0 <branch> [<base-repo>] [--created <base>] [--facts <file>]" >&2
  exit 2
}

BRANCH=''
BASE_REPO=''
CREATED=''
FACTS=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --created | --facts)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      if [ "$1" = --created ]; then CREATED="$2"; else FACTS="$2"; fi
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$1" ]; then usage; fi
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      elif [ -z "$BASE_REPO" ]; then
        BASE_REPO="$1"
      else
        usage
      fi
      shift
      ;;
  esac
done
if [ -z "$BRANCH" ]; then usage; fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

need() {
  local verdict
  verdict="$(bash "${SCRIPT_DIR}/facts.sh" check "$FACTS" "$@")"
  if [ "$verdict" != OK ]; then
    echo "$verdict"
    exit 0
  fi
}

fact() {
  bash "${SCRIPT_DIR}/facts.sh" get "$FACTS" "$1"
}

if ! REPO="$(bash "${SCRIPT_DIR}/origin-repo.sh")"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi
OWNER="${REPO%%/*}"
TARGET="$(printf '%s\n' "${BASE_REPO:-$REPO}" | tr '[:upper:]' '[:lower:]')"

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
SPECS=("target=${TARGET}" "head=${OWNER}:${BRANCH}" 'head.open-pr[]')
need "${SPECS[@]}"
COUNT="$(fact head.open-pr.total)"

if [ -n "$CREATED" ]; then
  if [ "$COUNT" -eq 0 ]; then
    echo "STOP pr-not-created"
    exit 0
  fi
  if [ "$COUNT" -ge 2 ]; then
    echo "STOP ask-multiple-prs-after-create"
    exit 0
  fi
  NUM="$(fact head.open-pr)"
  need "${SPECS[@]}" "pr.number=${NUM}" "pr.head.ref=${BRANCH}" "pr.base.ref=${CREATED}" 'pr.draft:true,false' pr.url
  echo "PR ${NUM} created draft=$(fact pr.draft) base=${CREATED} url=$(fact pr.url)"
  exit 0
fi

if [ "$COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi
if [ "$COUNT" -eq 1 ]; then
  NUM="$(fact head.open-pr)"
  need "${SPECS[@]}" "pr.number=${NUM}" "pr.head.ref=${BRANCH}" 'pr.draft:true,false' pr.url
  echo "PR ${NUM} found draft=$(fact pr.draft) url=$(fact pr.url)"
  exit 0
fi

# --- Step 2b: no PR; with no base-repo, may the target be origin? ---
if [ -z "$BASE_REPO" ]; then
  OTHERS="$(git remote | grep -vx origin || true)"
  if [ -n "$OTHERS" ]; then
    echo "STOP ask-base-repo"
    exit 0
  fi
  SPECS+=("repo=${REPO}" 'repo.fork[]')
  need "${SPECS[@]}"
  # exactly one repository record: a search that missed the fork reports 0
  if [ "$(fact repo.fork.total)" -ne 1 ]; then
    echo "STOP fork-unread"
    exit 0
  fi
  need "${SPECS[@]}" 'repo.fork:true,false'
  if [ "$(fact repo.fork)" = true ]; then
    echo "STOP ask-base-repo"
    exit 0
  fi
fi

# --- Step 3: the base, from the sibling only. ---
if [ -n "$BASE_REPO" ]; then
  RESOLVED="$(bash "${SCRIPT_DIR}/resolve-pr-base.sh" "$BRANCH" "$TARGET" --facts "$FACTS")"
else
  RESOLVED="$(bash "${SCRIPT_DIR}/resolve-pr-base.sh" "$BRANCH" --facts "$FACTS")"
fi
case "$RESOLVED" in
  STOP* | NEED*)
    echo "$RESOLVED"
    exit 0
    ;;
  "BASE "*) BASE="${RESOLVED#BASE }" ;;
  *)
    echo "error: unexpected output from resolve-pr-base.sh: ${RESOLVED}" >&2
    exit 1
    ;;
esac

# --- Step 4: hand the create to the agent. The head is named, never left to
# default: a create's head defaults to the checked-out branch. ---
if [ "$TARGET" = "$REPO" ]; then
  HEAD_ARG="$BRANCH"
else
  HEAD_ARG="${OWNER}:${BRANCH}"
fi
echo "CREATE repo=${TARGET} head=${HEAD_ARG} base=${BASE}"
