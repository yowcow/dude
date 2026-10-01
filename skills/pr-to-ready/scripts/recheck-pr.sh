#!/usr/bin/env bash
# Step 3's re-confirmation (../SKILL.md, "Step 3: Finish"): measure one SHA in
# a fixed order, print every stage's exit status and output, and record in
# this worktree's git dir whether everything a machine can judge held. It
# measures only — it fixes nothing, and never judges whether a check's
# conclusion passes, which stays with the caller per watch-checks.sh's header.
#
# The order is the reason this is a script. The listings are read only after
# watch-checks.sh has returned: a review that runs as a check-run posts its
# threads when that run completes, so a listing read before or alongside the
# wait comes back empty on a PR about to carry a finding, and the PR goes
# ready on it. Measured on yowcow/dude#255 — listing read 04:46:51, Copilot's
# check-run completed 04:47:40, the finding posted 04:47:41.
#
# The record sits in the git dir rather than the tree, so check-clean.sh never
# sees it and no commit carries it. Its name and format belong to this script,
# ./mark-ready.sh, its only reader, and ./clear-recheck-record.sh.
#
# Usage: recheck-pr.sh <owner> <repo> <pr-number> <sha> <base>
#        run from the PR's workspace; <base> is the one Step 1 last resolved
#
# Output: for each stage in order — head (the PR's head SHA now),
#         watch-checks, unresolved-threads, suppressed-comments,
#         check-pr-state — a line `== <stage> exit=<n>`, then that stage's
#         stdout. Last, `RECORDED met <sha>` when the head is still <sha>, the
#         watch exited 0 or 5, both listings exited 0 with empty output, and
#         the state is `BASE-OK <base> MERGEABLE`; `RECORDED unmet <sha>`
#         otherwise.
#
# Exit: 0 = measured and recorded, met or not
#       2 = usage error
#       other = not inside a git working tree, or the record could not be
#               written — nothing was recorded
set -euo pipefail

if [ "$#" -ne 5 ] || ! [[ "$3" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <sha> <base>" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"
SHA="$4"
BASE="$5"

# An assignment, so a cwd outside any repository stops here under `set -e`
# rather than after the watch has spent its budget.
RECORD="$(git rev-parse --git-dir)/dude-pr-to-ready-recheck"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

met=yes

# stage <name> <cmd...>: run one stage, print its header and stdout, and leave
# the stdout in OUT and the status in ST for the condition that follows it.
stage() {
  local name="$1"
  shift
  ST=0
  OUT="$("$@")" || ST=$?
  printf '== %s exit=%s\n' "$name" "$ST"
  if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; fi
}

stage head gh pr view -R "${OWNER}/${REPO}" --json headRefOid --jq .headRefOid -- "$PR"
{ [ "$ST" -eq 0 ] && [ "$OUT" = "$SHA" ]; } || met=""
stage watch-checks bash "${SCRIPT_DIR}/watch-checks.sh" "$OWNER" "$REPO" "$SHA"
{ [ "$ST" -eq 0 ] || [ "$ST" -eq 5 ]; } || met=""
stage unresolved-threads bash "${SCRIPT_DIR}/list-unresolved-threads.sh" "$OWNER" "$REPO" "$PR"
{ [ "$ST" -eq 0 ] && [ -z "$OUT" ]; } || met=""
stage suppressed-comments bash "${SCRIPT_DIR}/list-suppressed-comments.sh" "$OWNER" "$REPO" "$PR"
{ [ "$ST" -eq 0 ] && [ -z "$OUT" ]; } || met=""
stage check-pr-state bash "${SCRIPT_DIR}/check-pr-state.sh" "$OWNER" "$REPO" "$PR" "$BASE"
[ "$OUT" = "BASE-OK ${BASE} MERGEABLE" ] || met=""

verdict=unmet
if [ -n "$met" ]; then verdict=met; fi
printf '%s %s\n' "$verdict" "$SHA" >"$RECORD"
printf 'RECORDED %s %s\n' "$verdict" "$SHA"
