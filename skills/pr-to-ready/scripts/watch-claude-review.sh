#!/usr/bin/env bash
# Find the @claude review workflow and, optionally, block until one of its runs
# finishes. Completion is tied to the workflow run rather than guessed from
# comment counts, which is why this exists as a command at all.
#
# With no run-id: prints the workflow's recent runs as JSON, carrying event,
# createdAt and displayTitle so the caller can match a run to its own request
# rather than taking the newest and risking a stale one.
# With a run-id: blocks on that run.
#
# The listing covers runs on <branch> and on the default branch, because the
# trigger decides which one a run is attributed to: a review requested by an
# issue comment runs on the default branch, while pull_request_review* triggers
# run on the PR branch. Filtering on <branch> alone matches nothing for the
# issue-comment shape, so the caller polls until it times out and reports the
# review as never arriving even though it completed and posted.
#
# headSha does not identify the push either, for the same reason: on the
# issue-comment shape it is the default branch's tip, not the PR head. Match on
# createdAt against the moment the request was posted.
#
# createdAt alone still does not identify the run: every issue-comment run in
# the repository lands on the default branch, so a review requested on another
# PR in the same window sits in this listing too, and matching on time alone
# blocks on that one and reads its verdict as this PR's. displayTitle carries
# the PR title for these runs — discriminate on it as well.
#
# The listing also has to be deep enough to still hold that run: the same
# fan-in means runs requested on other PRs pile into the window between posting
# the request and querying here. Once they outnumber the limit, the target run
# is pushed out of the listing and the filter below returns empty — the same
# false negative as above. --limit 100 is the API's single-page maximum, the
# deepest listing gh fetches without paging again.
#
# A run whose conclusion is "skipped" is one the workflow's own if: condition
# rejected — a comment carrying no @claude, including the reviewer bot's own
# reply. Watch mode returns 0 for it, so taking a skipped run as the review
# reads an unrun review as a completed one with nothing to say.
#
# Usage: watch-claude-review.sh <branch> [run-id]
#
# Exit: 0 = the listing printed (list mode), or the watched run succeeded (watch mode)
#       2 = usage error
#       3 = no @claude workflow in this repository. This is the availability
#           answer and nothing else exits 3, so a caller may skip Claude on it
#       other = the underlying gh call failed, or in watch mode the run itself
#           did not succeed: gh run watch --exit-status returns 1 for a failed
#           run, and any failing gh call exits with its own status under set -e
#
# Only 0, 2, and 3 identify a cause on their own. Treat every other non-zero as
# "stop and inspect" rather than as a specific answer.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <branch> [run-id]" >&2
  exit 2
fi

BRANCH="$1"
RUN_ID="${2:-}"

# grep exits 1 when nothing matches, which set -e would turn into an abort, so
# the substitution is guarded and the emptiness of wf is what gets tested.
#
# The search is anchored at the repository root, never the cwd: run from a
# subdirectory, a cwd-relative .github/workflows/ matches nothing, exit 3 below
# reports Claude as unavailable, and the caller skips the review entirely. A cwd
# outside a repository aborts here instead, which is "stop and inspect" rather
# than an availability answer.
root="$(git rev-parse --show-toplevel)"
wf="$({ grep -rl '@claude' "$root/.github/workflows/" 2>/dev/null || true; } | head -1)"
if [ -z "$wf" ]; then
  echo "no @claude workflow found in $root/.github/workflows/" >&2
  exit 3
fi
wf="$(basename "$wf")"

if [ -z "$RUN_ID" ]; then
  default_branch="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
  gh run list --workflow="$wf" --limit 100 \
    --json databaseId,status,conclusion,event,createdAt,displayTitle,headBranch,headSha |
    jq --arg b "$BRANCH" --arg d "$default_branch" \
      '[.[] | select(.headBranch == $b or .headBranch == $d)]'
  exit 0
fi

gh run watch "$RUN_ID" --exit-status
