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
#                      [<review-id> <path:line> ...]
#        run from the PR's workspace; <base> is the one Step 1 last resolved
#
# Output: for each stage in order — head (the PR's head SHA now),
#         watch-checks, unresolved-threads, suppressed-comments,
#         check-pr-state — a line `== <stage> exit=<n>`, then that stage's
#         stdout. Last, `RECORDED met <sha>` when the head is still <sha>, the
#         watch exited 0 or 5, both listings exited 0 with the thread listing
#         empty, every entry the suppressed listing printed is covered by one of
#         the recorded pairs (an empty suppressed listing is met), and the state
#         is `BASE-OK <base> MERGEABLE`;
#         `RECORDED unmet <sha>` otherwise. With no pairs the older rule stands
#         — only an empty suppressed listing is met — so a caller that records
#         nothing keeps today's answer. A pair whose id differs from the
#         listing's first line covers nothing.
#
# The pair is what makes the suppressed stage answer "is this the finding I
# already judged?" rather than "is there a finding at all": with nothing to
# compare, an entry recorded under an older review reads as unknown and the
# re-confirmation flips to unmet on a PR nobody changed. The listing's id is
# split off by parameter expansion, as ./list-suppressed-comments.sh does,
# rather than by a needless `head` in the pipeline; the first newline is where
# the id line ends and the block begins. The call site's `{ ...; } ||
# verdict=unmet` already suppresses errexit for this body, so the choice is
# consistency with the producer, not a guard against `head`'s SIGPIPE.
#
# Exit: 0 = measured and recorded, met or not
#       2 = usage error, including an odd number of pair arguments
#       other = not inside a git working tree, or the record could not be
#               written — nothing was recorded
set -euo pipefail

if [ "$#" -lt 5 ] || ! [[ "$3" =~ ^[0-9]+$ ]] || [ $(( ($# - 5) % 2 )) -ne 0 ]; then
  echo "Usage: $0 <owner> <repo> <pr-number> <sha> <base> [<review-id> <path:line> ...]" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
PR="$3"
SHA="$4"
BASE="$5"
shift 5

# An assignment, so a cwd outside any repository stops here under `set -e`
# rather than after the watch has spent its budget.
RECORD="$(git rev-parse --git-dir)/dude-pr-to-ready-recheck"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

verdict=met

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

# covered <review-id> <entry> [<review-id> <entry> ...] -- the verdict record
# holds this exact pair.
covered() {
  local review="$1" entry="$2"
  shift 2
  while [ "$#" -ge 2 ]; do
    if [ "$1" = "$review" ] && [ "$2" = "$entry" ]; then
      return 0
    fi
    shift 2
  done
  return 1
}

# suppressed_met <listing> [<review-id> <entry> ...] -- every entry the listing
# prints is covered. Empty stdout means no suppressed block and is met; with no
# pairs at all the old rule stands, so an existing caller is unaffected.
suppressed_met() {
  local listing="$1" review entry
  shift
  if [ -z "$listing" ]; then return 0; fi
  if [ "$#" -eq 0 ]; then return 1; fi
  review="${listing%%$'\n'*}"
  printf '%s\n' "$listing" | tail -n +3 | {
    while IFS= read -r entry; do
      # `if`, not `[ -z "$entry" ] && continue`: the `if` keeps the intent
      # explicit and does not lean on a failing test on the left of `&&`
      # being exempt from `set -e`.
      if [ -n "$entry" ]; then
        covered "$review" "$entry" "$@" || exit 1
      fi
    done
  }
}

stage head gh pr view -R "${OWNER}/${REPO}" --json headRefOid --jq .headRefOid -- "$PR"
{ [ "$ST" -eq 0 ] && [ "$OUT" = "$SHA" ]; } || verdict=unmet
stage watch-checks bash "${SCRIPT_DIR}/watch-checks.sh" "$OWNER" "$REPO" "$SHA"
{ [ "$ST" -eq 0 ] || [ "$ST" -eq 5 ]; } || verdict=unmet
stage unresolved-threads bash "${SCRIPT_DIR}/list-unresolved-threads.sh" "$OWNER" "$REPO" "$PR"
{ [ "$ST" -eq 0 ] && [ -z "$OUT" ]; } || verdict=unmet
stage suppressed-comments bash "${SCRIPT_DIR}/list-suppressed-comments.sh" "$OWNER" "$REPO" "$PR"
{ [ "$ST" -eq 0 ] && suppressed_met "$OUT" "$@"; } || verdict=unmet
stage check-pr-state bash "${SCRIPT_DIR}/check-pr-state.sh" "$OWNER" "$REPO" "$PR" "$BASE"
[ "$OUT" = "BASE-OK ${BASE} MERGEABLE" ] || verdict=unmet

printf '%s %s\n' "$verdict" "$SHA" >"$RECORD"
printf 'RECORDED %s %s\n' "$verdict" "$SHA"
