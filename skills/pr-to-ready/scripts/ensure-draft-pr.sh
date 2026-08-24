#!/usr/bin/env bash
# Ensure a draft PR exists for a branch, creating one only if none is found.
#
# This script does NOT take a base as an argument. It resolves one itself, by
# calling the sibling ./resolve-pr-base.sh, and only at the point where it has
# already decided to create a PR — an existing PR needs no base at all.
#
# The push-if-local-only check runs FIRST, before any base resolution.
# resolve-pr-base.sh fetches the branch to read its Base-Branch trailer, so it
# hard-stops on a branch that isn't on the remote yet. Resolving the base
# before pushing would therefore stop an unpushed local branch before it ever
# got pushed, breaking the rule that an unpushed branch is not a blocker —
# push it and carry on.
#
# The existence check uses `gh pr list --head`, never `gh pr view`, and reads
# the result with `.[]`, never `.[0]` — see ../references/gh-mechanics.md,
# "## Asking whether a PR exists" and "## Reading the PR number back" for why:
# in short, exit status and line count must be read together, and a numeric
# branch name would otherwise be misread by `gh pr view` as a PR number.
#
# The sibling script is invoked through "$(dirname "${BASH_SOURCE[0]}")" —
# never a bare name or a cwd-relative path — because this script is normally
# run from somewhere other than its own directory. A bare name dies with
# "command not found" under `set -euo pipefail`, which exits non-zero with a
# bash error on stderr instead of the contracted `STOP <reason-slug>` on
# stdout; that failure mode is invisible to `bash -n`, since it never
# executes a call into another directory.
#
# Usage: ensure-draft-pr.sh <branch> <title> <body-file>
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <branch> <title> <body-file>" >&2
  exit 1
fi

BRANCH="$1"
TITLE="$2"
BODY_FILE="$3"

# Prints one line per matching PR ("<number> <isDraft>") on success, nothing
# on an empty list. Exit status and output must be read together by the
# caller — a non-zero exit here means "couldn't tell", not "no PR".
lookup_pr() {
  gh pr list --head "$BRANCH" --json number,isDraft --jq '.[] | "\(.number) \(.isDraft)"'
}

# Count the lines lookup_pr produced. An empty string has to count as zero:
# `wc -l` on it would report 1, turning "no PR" into "exactly one PR" and
# sending the caller down the found-a-PR branch with an empty number.
count_lines() {
  if [ -z "$1" ]; then
    echo 0
  else
    printf '%s\n' "$1" | wc -l
  fi
}

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

# --- Step 2: does a PR already exist for this branch? ---

if ! LOOKUP="$(lookup_pr)"; then
  # "PR none found" must not be read the same as "couldn't tell" — that
  # misreading is exactly what opens a second PR on a branch that already
  # has one.
  echo "STOP pr-lookup-failed"
  exit 0
fi

LINE_COUNT="$(count_lines "$LOOKUP")"

if [ "$LINE_COUNT" -eq 1 ]; then
  read -r NUM DRAFT <<<"$LOOKUP"
  echo "PR ${NUM} found draft=${DRAFT}"
  exit 0
fi

if [ "$LINE_COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi

# --- Step 3: no PR exists. Only now is a base resolved, and only by asking
# the sibling script — never guessed here. ---

RESOLVED="$("$(dirname "${BASH_SOURCE[0]}")/resolve-pr-base.sh" "$BRANCH")"

case "$RESOLVED" in
  STOP*)
    # Passed through unchanged: this is how base-branch.md's stop rows come
    # to bite before `gh pr create` ever runs.
    echo "$RESOLVED"
    exit 0
    ;;
  "BASE "*)
    BASE="${RESOLVED#BASE }"
    ;;
  *)
    echo "error: unexpected output from resolve-pr-base.sh: ${RESOLVED}" >&2
    exit 1
    ;;
esac

# --- Step 4: create the draft PR. ---

# --head is not optional: `gh pr create`'s head defaults to the *current*
# branch, and there is no guarantee $BRANCH is the branch checked out here.
if ! gh pr create --draft --head "$BRANCH" --base "$BASE" --title "$TITLE" --body-file "$BODY_FILE" >&2; then
  echo "STOP pr-create-failed"
  exit 0
fi

# --- Step 5: confirm creation with the same readback as Step 2, rather than
# trusting `gh pr create`'s own exit status for what the PR record actually
# says. ---

if ! LOOKUP="$(lookup_pr)"; then
  echo "STOP pr-readback-failed"
  exit 0
fi

LINE_COUNT="$(count_lines "$LOOKUP")"

if [ "$LINE_COUNT" -eq 0 ]; then
  # Not "creation failed" — `gh pr create` may have exited 0 while the
  # record still doesn't show up on readback. Report what was actually
  # observed, not an inference about the cause.
  echo "STOP pr-not-created"
  exit 0
fi

if [ "$LINE_COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs-after-create"
  exit 0
fi

read -r NUM DRAFT <<<"$LOOKUP"
echo "PR ${NUM} created draft=${DRAFT} base=${BASE}"
