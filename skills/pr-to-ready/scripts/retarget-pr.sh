#!/usr/bin/env bash
# Retarget a PR onto a new base once the base it currently points at has
# merged, and pull that new base's tip into the branch.
#
# A PR left pointing at an already-merged prerequisite reviews a diff that no
# longer matches what will actually land: merging such a PR puts nothing new
# into the base it is really headed for, since everything in the stale base
# is already there. Retargeting alone would still leave the PR's diff
# spanning the old base's own commits, so this also merges the new base in
# and pushes it — without that, the PR keeps showing a stack of changes that
# already shipped under a different PR.
#
# Mergeability plays no part here — this script only reads `baseRefName` and
# never branches on either mergeability field (see ../references/gh-mechanics.md,
# "## Mergeability" for why one of those two is never the right one to read).
# Its `BASE-OK <base>` output uses the identical spelling of
# ./check-pr-state.sh's own token of the same name, so a caller can treat the
# two as interchangeable vocabulary.
#
# On a run that finds stage 1 already done and stage 2 not, `RETARGETED`
# names the same base twice — old and new are the same branch, because only
# the merge was outstanding. It is deliberately not a third token: what the
# caller does next, running CI against the new tip, is identical either way.
#
# No automatic rebase, no force-push, no conflict resolution: a merge
# conflict aborts the merge and reports STOP for a person to resolve.
# Conflict resolution is a different, separately tracked concern (#111) and
# is a person's job, not this script's.
#
# Usage: retarget-pr.sh <owner> <repo> <pr-number> <branch> <base>
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <branch> <base>" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
PR="$3"
BRANCH="$4"
BASE="$5"

if ! CURRENT_BASE="$(gh pr view "$PR" -R "${OWNER}/${REPO}" --json baseRefName --jq '.baseRefName' 2>/dev/null)"; then
  echo "STOP pr-read-failed"
  exit 0
fi

# The base tip is needed twice over: by the ancestor gate below, and by the
# merge itself. Fetching it once here, above the branch on `CURRENT_BASE`,
# keeps that to one fetch and one capture. Capture the sha immediately: a
# second fetch overwrites FETCH_HEAD, and the gate below runs one
# (../references/gh-mechanics.md, "Capture the two tips as shas, one per
# fetch").
if ! git fetch origin -- "$BASE" >&2; then
  echo "STOP fetch-failed"
  exit 0
fi
BASE_SHA="$(git rev-parse FETCH_HEAD)"

# Retargeting is a job of two stages — the base moves on GitHub, then that
# base is merged in and pushed — and `baseRefName` reports only the first.
# So a matching pointer is one gate of two: the second asks whether the base
# tip has actually reached the remote branch. Without it, a run that failed
# at the push reports BASE-OK on its next attempt while the remote head is
# still the pre-merge one, and the caller reads the previous run's green CI
# as this retarget's verification.
RETARGET_ON_GITHUB=yes
if [ "$CURRENT_BASE" = "$BASE" ]; then
  if ! git fetch origin -- "$BRANCH" >&2; then
    echo "STOP branch-fetch-failed"
    exit 0
  fi
  BRANCH_SHA="$(git rev-parse FETCH_HEAD)"

  # 0 and 1 are the two verdicts; anything else is the command failing for a
  # reason of its own. Reading such a failure as either verdict would either
  # report BASE-OK over an unmerged base or push a merge nobody asked for, so
  # it stops for a person instead. (Measured on git 2.43.0: an unresolvable
  # name exits 128, keeping errors clear of both verdicts — unlike
  # `git merge-tree`, whose exit 1 collides with a genuine conflict.)
  ANCESTOR_STATUS=0
  git merge-base --is-ancestor "$BASE_SHA" "$BRANCH_SHA" || ANCESTOR_STATUS=$?
  case "$ANCESTOR_STATUS" in
    0)
      # Both gates hold: the PR points at <base> and that base is already in
      # the branch on the remote. Nothing that changes the remote or the
      # worktree runs — no `gh pr edit`, no merge, no push.
      echo "BASE-OK ${BASE}"
      exit 0
      ;;
    1)
      # Stage 1 is done and stage 2 is not: resume at the merge. Editing the
      # base to what it already is would be the one mutation with nothing to
      # do, so it is skipped and the run picks up where the last one stopped.
      RETARGET_ON_GITHUB=no
      ;;
    *)
      echo "STOP ancestor-check-failed"
      exit 0
      ;;
  esac
fi

# Both preconditions are checked BEFORE the first mutation. Were the edit done
# first, a failing check here would leave the PR retargeted with the merge
# never made: a half-applied change the next run has to reason about.
# Pulling the new base in is only possible from the branch's own checkout:
# there is no other working tree to merge into.
CURRENT_HEAD="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_HEAD" != "$BRANCH" ]; then
  echo "STOP checkout-required"
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "STOP dirty-worktree"
  exit 0
fi

if [ "$RETARGET_ON_GITHUB" = yes ]; then
  if ! gh pr edit "$PR" -R "${OWNER}/${REPO}" --base "$BASE" >&2; then
    echo "STOP retarget-failed"
    exit 0
  fi
fi

if ! git merge --no-edit "$BASE_SHA" >&2; then
  # Whatever the cause, abort rather than leaving a half-finished merge in
  # the working tree. No rebase, no force-push, no resolution attempt — see
  # the header comment: that is #111's job, done by a person.
  #
  # `|| true` because the merge can fail without leaving one in progress —
  # unrelated histories, say — and then the abort fails too. Under `set -e`
  # that would kill the script before the STOP below ever prints, turning a
  # reportable conflict into a bare non-zero exit.
  git merge --abort || true
  echo "STOP merge-conflict"
  exit 0
fi

# The merge has to reach the remote before this reports success. Left local,
# the PR's diff and every check still describe the pre-merge tip, so the
# caller's next step — watching CI — would read the previous run's green
# result as if it had verified the retarget. Explicit source and destination
# refspec, and a plain fast-forward push: never --force, per the header.
if ! git push origin "refs/heads/${BRANCH}:refs/heads/${BRANCH}" >&2; then
  echo "STOP push-failed"
  exit 0
fi

echo "RETARGETED ${CURRENT_BASE} ${BASE}"
