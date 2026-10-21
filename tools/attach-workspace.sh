#!/usr/bin/env bash
# Attach a workspace to a branch that may already have a worktree, exist only
# locally, or exist only on the remote — checked in that order, remote before
# giving up. A transient failure checking the remote (network, auth, DNS)
# must not be read the same as "branch doesn't exist": either would fall
# through to CREATE and cut a fresh branch from the default, leaving
# already-pushed work stranded as a separate history under the same name
# (force-push is banned, so there is no recovering it).
# Usage: attach-workspace.sh <branch> <path>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <branch> <path>" >&2
  exit 2
fi

BRANCH="$1"
WORKTREE_PATH="$2"

WORKTREES="$(git worktree list --porcelain)"

# -F and -x are load-bearing, replacing the ^/$ anchors rather than joining
# them: a branch name may contain ".", which as a bare regex would match any
# character and could hit a different branch's line instead.
if EXISTING="$(printf '%s\n' "$WORKTREES" | grep -Fx -B2 "branch refs/heads/${BRANCH}" | sed -n 's/^worktree //p')" && [ -n "$EXISTING" ]; then
  echo "REUSE ${EXISTING}"
  exit 0
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git worktree add -- "${WORKTREE_PATH}" "${BRANCH}" >&2
  echo "ATTACHED ${WORKTREE_PATH}"
  exit 0
fi

# --exit-code is required, same as resolve-branch.sh: without it, a real
# match and no match are both exit 0. With it, 2 means "no match" (fall
# through to CREATE); any other non-zero means the command itself failed, and
# that must stop the script rather than be read as "no match".
set +e
git ls-remote --exit-code --heads origin -- "${BRANCH}" >/dev/null
status=$?
set -e

if [ "${status}" -eq 0 ]; then
  # The explicit refspec is load-bearing: `git fetch origin -- <branch>` on a
  # clone whose remote.origin.fetch does not name the branch (a
  # `--single-branch` clone) updates FETCH_HEAD alone and creates no tracking
  # ref, so a fetch without it leaves the next line nothing to attach to and
  # `set -e` exits with no line printed at all.
  TRACKING_REF="refs/remotes/origin/${BRANCH}"
  REFSPEC="+refs/heads/${BRANCH}:${TRACKING_REF}"
  git fetch origin "${REFSPEC}" >&2
  git worktree add --no-track -b "${BRANCH}" -- "${WORKTREE_PATH}" "${TRACKING_REF}" >&2
  git config "branch.${BRANCH}.remote" origin
  git config "branch.${BRANCH}.merge" "refs/heads/${BRANCH}"
  # git resolves branch.<name>.merge through remote.origin.fetch, so a narrowed
  # clone has to name this branch there before @{upstream} resolves. A clone
  # whose refspec already covers it needs no change.
  git rev-parse --abbrev-ref "${BRANCH}@{upstream}" >/dev/null 2>&1 ||
    git config --add remote.origin.fetch "${REFSPEC}"
  echo "ATTACHED ${WORKTREE_PATH}"
  exit 0
elif [ "${status}" -ne 2 ]; then
  echo "error: git ls-remote failed for '${BRANCH}' (exit ${status})" >&2
  exit "${status}"
fi

echo "CREATE"
