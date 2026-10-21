#!/usr/bin/env bash
# Find the @claude review workflow and, optionally, block until one of its runs
# finishes. Completion is tied to the workflow run rather than guessed from
# comment counts, which is why this exists as a command at all.
#
# With a default branch: prints the workflow's recent runs as JSON, carrying
# databaseId, conclusion, createdAt and displayTitle so the caller can match a
# run to its own request rather than taking the newest and risking a stale one.
# With a run-id: polls that run until it completes, at most 40 times 30 s apart.
#
# Watch mode polls `gh run view --json status,conclusion` rather than
# `gh run watch --exit-status`, which blocks until the run finishes: a run left
# queued behind a pending approval never finishes, so that call is this
# repository's one unbounded wait.
#
# The loop is local rather than tools/poll.sh, for the same reason watch-checks.sh's
# is: poll.sh's predicate is the check command's exit status and every non-zero
# means "not yet" to it, so a `gh run view` that fails — a run id that is gone,
# or not this repository's — would be retried to the cap instead of stopping at
# once with gh's own status.
#
# A run is waited on while its status is not "completed". queued, in_progress,
# requested, waiting and pending all keep waiting, and `waiting` is the one an
# approval gate leaves behind: it is not a verdict, so it waits to the cap like
# the rest. The conclusion is read only once the status is completed, because gh
# leaves it empty on every other status.
#
# The listing covers runs on <branch> and on <default-branch>, because the
# trigger decides which one a run is attributed to: a review requested by an
# issue comment runs on the default branch, while pull_request_review* triggers
# run on the PR branch. Filtering on <branch> alone matches nothing for the
# issue-comment shape, so the caller polls until it times out and reports the
# review as never arriving even though it completed and posted. The default
# branch arrives as an argument, never read here: see Usage below.
#
# Match on createdAt against the moment the request was posted, but createdAt
# alone still does not identify the run: every issue-comment run in the
# repository lands on the default branch, so a review requested on another PR
# in the same window sits in this listing too, and matching on time alone
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
# Usage: watch-claude-review.sh <branch> <default-branch|run-id>
#        The second argument is the default branch in list mode and a run id in
#        watch mode, told apart by being all digits.
#        The default branch is an argument, not a read: resolving it is a live
#        `git ls-remote --symref`, measured at 2.15-2.17 s, and a caller lists
#        again on every poll of a review it is waiting for. The caller resolves
#        it once and passes it to every listing.
#
# Exit: 0 = the listing printed (list mode), or the watched run's conclusion is
#           "success" or "skipped" (watch mode). Watch mode prints nothing on
#           stdout: the caller reads only the exit status.
#       1 = in watch mode the run concluded anything else, or it had not
#           completed when the iteration cap ran out
#       2 = usage error
#       3 = no @claude workflow in this repository. This is the availability
#           answer and nothing else exits 3, so a caller may skip Claude on it
#       other = the underlying gh call failed or the origin repository could not
#           be resolved: a failing `gh run view` exits at once with gh's own
#           status, never retried to the cap
#
# Only 0, 2, and 3 identify a cause on their own. Treat every other non-zero as
# "stop and inspect" rather than as a specific answer.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <branch> <default-branch|run-id>" >&2
  exit 2
fi

BRANCH="$1"
if [ -z "$BRANCH" ] || [ -z "$2" ]; then
  echo "Usage: $0 <branch> <default-branch|run-id>" >&2
  exit 2
fi

# List mode and watch mode split on the second argument's shape: all digits is a
# run id. An all-digit default branch name reads as one too, but the run lookup
# exits at once rather than silently mis-filtering the listing.
if [[ "$2" =~ ^[0-9]+$ ]]; then
  RUN_ID="$2"
  DEFAULT_BRANCH=""
else
  RUN_ID=""
  DEFAULT_BRANCH="$2"
fi
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

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

if ! REPO="$(bash "${SCRIPT_DIR}/../../../tools/origin-repo.sh")"; then
  echo "error: failed to resolve the origin repository" >&2
  exit 1
fi

if [ -z "$RUN_ID" ]; then
  if ! gh run list -R "$REPO" --workflow="$wf" --limit 100 \
    --json databaseId,conclusion,createdAt,displayTitle,headBranch 2>/dev/null |
    jq --arg b "$BRANCH" --arg d "$DEFAULT_BRANCH" \
      '[.[] | select(.headBranch == $b or .headBranch == $d) | del(.headBranch)]' 2>/dev/null; then
    echo "error: failed to list workflow runs for $wf" >&2
    exit 1
  fi
  exit 0
fi

# Watch mode's cap: 40 polls x 30 s = 19m30s, with no sleep after the last poll.
# The same values as the same step's Copilot wait (watch-copilot-review.sh).
MAX_ITER=40
INTERVAL=30

for i in $(seq 1 "$MAX_ITER"); do
  # A failed gh call is not retried: it points at a run id gh cannot answer for
  # (gone, or not this repository's), and the next poll would only ask the same
  # wrong question. Passing the status straight to the caller is exactly why this
  # is not on tools/poll.sh, whose predicate is the check command's exit status
  # and every non-zero means "not yet" to it, so it retries to the cap.
  gh_status=0
  view="$(gh run view -R "$REPO" "$RUN_ID" --json status,conclusion)" || gh_status=$?
  if [ "$gh_status" -ne 0 ]; then
    exit "$gh_status"
  fi

  # Slurp and length == 1 for the same reason as watch-checks.sh: jq reads a
  # stream of top-level values, so a body it cannot read collapses to "it answered
  # nothing". No answer means incomplete, not complete.
  run_status="$(printf '%s' "$view" |
    jq -r -s 'select(length == 1) | .[0].status | select(type == "string")' 2>/dev/null)" || run_status=""

  if [ "$run_status" = completed ]; then
    conclusion="$(printf '%s' "$view" |
      jq -r -s 'select(length == 1) | .[0].conclusion // ""' 2>/dev/null)" || conclusion=""
    case "$conclusion" in
      success | skipped) exit 0 ;;
      *)
        echo "claude review run ${RUN_ID} concluded '${conclusion}'" >&2
        exit 1
        ;;
    esac
  fi

  if [ "$i" -lt "$MAX_ITER" ]; then
    sleep "$INTERVAL"
  fi
done

echo "claude review run ${RUN_ID} did not complete within ${MAX_ITER} polls at ${INTERVAL}s" >&2
exit 1
