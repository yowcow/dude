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
  exit 1
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
  git worktree add "${WORKTREE_PATH}" "${BRANCH}" >&2
  echo "ATTACHED ${WORKTREE_PATH}"
  exit 0
fi

# --exit-code is required, same as resolve-branch.sh: without it, a real
# match and no match are both exit 0. With it, 2 means "no match" (fall
# through to CREATE); any other non-zero means the command itself failed, and
# that must stop the script rather than be read as "no match".
set +e
git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null
status=$?
set -e

if [ "${status}" -eq 0 ]; then
  git fetch origin -- "${BRANCH}" >&2
  git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"
  git worktree add --track -b "${BRANCH}" "${WORKTREE_PATH}" "origin/${BRANCH}" >&2
  echo "ATTACHED ${WORKTREE_PATH}"
  exit 0
elif [ "${status}" -ne 2 ]; then
  echo "error: git ls-remote failed for '${BRANCH}' (exit ${status})" >&2
  exit "${status}"
fi

echo "CREATE"
