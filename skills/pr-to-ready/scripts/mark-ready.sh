#!/usr/bin/env bash
# The only way pr-to-ready marks a PR ready (../SKILL.md, "Step 3: Finish"):
# on the record ./recheck-pr.sh left in this worktree's git dir, and only when
# that record says met for the SHA that is still the PR's head.
#
# Each refusal is a ready nobody re-confirmed. No record: Step 3's
# re-confirmation never ran in this run — 0-3's ./clear-recheck-record.sh
# removes whatever an earlier run left, so one from a ready-on-clean = no run
# on the same SHA cannot stand in for it. Unmet: a condition failed. A head
# that moved: the record is about a commit the PR no longer points at.
#
# What a record cannot carry — whether every check's conclusion passes, and
# conditions 2 and 6 — the caller has judged before calling this.
#
# Usage: mark-ready.sh <owner> <repo> <pr-number>
#        run from the PR's workspace, where ./recheck-pr.sh ran
#
# Output, one line: `READY <pr-number>`, or `STOP <slug>` — no-record,
#   conditions-unmet, pr-read-failed, head-moved, ready-failed.
#
# Exit: 0 = answered (READY or STOP)
#       2 = usage error
#       other = not inside a git working tree
set -euo pipefail

if [ "$#" -ne 3 ] || ! [[ "$3" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 <owner> <repo> <pr-number>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"
RECORD="$(git rev-parse --git-dir)/dude-pr-to-ready-recheck"

if [ ! -f "$RECORD" ]; then
  echo "STOP no-record"
  exit 0
fi

VERDICT=""
SHA=""
read -r VERDICT SHA <"$RECORD" || true
if [ "$VERDICT" != met ]; then
  echo "STOP conditions-unmet"
  exit 0
fi

if ! HEAD="$(gh pr view -R "${OWNER}/${REPO}" --json headRefOid --jq .headRefOid -- "$PR" 2>/dev/null)"; then
  echo "STOP pr-read-failed"
  exit 0
fi
if [ "$HEAD" != "$SHA" ]; then
  echo "STOP head-moved"
  exit 0
fi

if ! gh pr ready -R "${OWNER}/${REPO}" -- "$PR" >/dev/null; then
  echo "STOP ready-failed"
  exit 0
fi
echo "READY ${PR}"
