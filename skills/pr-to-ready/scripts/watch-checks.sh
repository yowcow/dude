#!/usr/bin/env bash
# Poll the check-runs on one commit until none is still queued or in_progress,
# then print one line per check: "<name>\t<status>\t<conclusion>".
#
# This exists as a command because the polling predicate is the whole difficulty.
# The obvious way to write it — fetch, grep for "in_progress", stop when the grep
# finds nothing — reports "all checks settled" for any response that merely fails
# to contain that word, and an error body qualifies. Ask for a SHA that is not on
# the remote and this surface answers 200-shaped JSON carrying
# {"message":"No commit found for SHA: ...","status":"422"}: no "in_progress"
# anywhere in it, so the naive predicate calls CI settled and the caller marks a
# PR ready having never read a check. So the response is validated for the
# total_count field before it is believed, and a missing commit is reported as
# its own exit status rather than as an empty run list.
#
# Whether the checks *pass* is the caller's judgement, never this script's: it
# reports the conclusions and stops there. A skipped check is not a failure, and
# an empty run list is not a pass — only the caller knows which checks the PR
# needs. Why the orchestrator keeps that judgement: ../SKILL.md, "Orchestration
# model".
#
# Usage: watch-checks.sh <owner> <repo> <sha> [max-iterations] [interval-seconds]
#        defaults: max-iterations 60, interval-seconds 20 (= 20 minutes)
#
# Exit: 0 = every check on the commit has settled, and the set of checks was
#           unchanged from the previous successfully read listing — the listing
#           printed. "Successfully read" rather than "previous poll" because a
#           poll that failed or answered something that is not a run list is
#           skipped rather than counted, so the two listings compared may sit
#           more than one interval apart; a caller must not read this as a
#           guarantee about two adjacent polls.
#       1 = still unsettled when the iteration cap ran out (the last listing printed)
#       2 = usage error
#       3 = no such commit on the remote — the SHA is wrong, or was never pushed
#       4 = no check-runs listing could be read at all — every poll either
#           failed or answered something that is not a run list
#       5 = neither this commit nor the default branch's head carries a single
#           check-run — this repository does not run checks
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  echo "Usage: $0 <owner> <repo> <sha> [max-iterations] [interval-seconds]" >&2
  exit 2
fi

OWNER="$1"
REPO="$2"
SHA="$3"
MAX_ITER="${4:-60}"
INTERVAL="${5:-20}"

# Nothing downstream stops the run on a bad value here, and each parameter fails
# its own way. `seq` reads MAX_ITER: a non-numeric one makes `for _ in $(seq 1
# abc)` run the body zero times, so the script answers "no listing could be
# read" without ever calling the API, while a fractional one is truncated (2.9
# polls twice), silently shrinking the budget the caller asked for. INTERVAL
# only reaches `sleep`, inside the loop, so a bad one dies there under `set -e`
# with exit 1 — the status this script also uses for "still unsettled".
for n in "$MAX_ITER" "$INTERVAL"; do
  if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
    echo "max-iterations and interval-seconds must be positive integers: $n" >&2
    exit 2
  fi
done

# Consecutive empty listings before the default branch is read. The window it
# buys is (EMPTY_GRACE - 1) × interval — 40 s on the defaults, since the first
# poll happens before any sleep and only the gaps between polls cost time — and
# it is there for the PR that is itself introducing CI: read too early, a
# repository whose first check has not registered yet answers exactly like one
# that runs none, and the verdict below would be "no checks" for a PR that has
# them.
EMPTY_GRACE=3

# Answers 0 only when the default branch's head demonstrably carries no
# check-run. Everything it cannot read answers non-zero, so an unreadable probe
# leaves the watch polling to its cap: a wrong "yes" tells the caller a
# repository with CI has none and the PR goes ready with no check ever read,
# while a wrong "no" costs only the wait the caller already asked for.
#
# The default branch is read from `repos/{owner}/{repo}`'s default_branch field
# rather than through the resolve_default_branch() helper the sibling scripts
# share (skills/implement-work/scripts/resolve-base.sh:19,
# skills/pr-to-ready/scripts/resolve-pr-base.sh:36,
# skills/review-code/scripts/resolve-range.sh:56). All three answer for the
# *current checkout*, and this script takes <owner> <repo> on the argv precisely
# so it can watch a repository it is not standing in; run from inside another
# checkout, that helper would resolve a different repository's default branch
# and this function would answer about that one.
#
# The default branch rather than the PR's base, because the error direction is
# the safe one: a stacked PR's base can carry no checks while the default branch
# does, and reading the base would declare a repository with CI to have none.
#
# Both requests are tested for having SUCCEEDED, rather than being wrapped in
# `|| true` and judged by their body alone. The body cannot carry that: a call
# that fails while printing something the predicate below accepts would be read
# as proof the repository runs no checks, and the invariant this function
# documents — everything it cannot read answers non-zero — would then hold only
# by accident of what a failing `gh` happens to print. The `|| return 1` form is
# what keeps a non-zero status from killing the script under `set -e`.
default_branch_runs_no_checks() {
  local repo_raw branch listing
  repo_raw="$(gh api "repos/${OWNER}/${REPO}" 2>/dev/null)" || return 1
  # `// empty` rather than a bare `.default_branch`: on an error body the field
  # is absent, `jq -r` renders that as the four characters `null`, and the
  # listing read below would then ask about a ref named "null" and treat its
  # 422 as "unreadable" — the right answer reached by accident, and only until
  # someone creates a branch by that name.
  #
  # jq's own status is kept rather than discarded, for the same reason the two
  # `gh` calls keep theirs: jq streams, so a body that is valid JSON followed by
  # trailing bytes prints the field and *then* fails. Measured: `printf
  # '{"default_branch":"trunk"} garbage' | jq -r '.default_branch // empty'`
  # prints `trunk` and exits 5. Under `|| true` that partial value survives, the
  # probe goes on to read a branch named by a response it could not parse, and
  # an empty listing there produces exit 5 — "this repository runs no checks" —
  # off a repository response that was never wholly read.
  branch="$(printf '%s' "$repo_raw" | jq -r '.default_branch // empty' 2>/dev/null)" || return 1
  [ -n "$branch" ] || return 1
  listing="$(gh api "repos/${OWNER}/${REPO}/commits/${branch}/check-runs" 2>/dev/null)" || return 1
  # `.check_runs` is tested for being an array before its length is read,
  # because `length` in jq answers 0 for null rather than erroring. Measured:
  # `printf '{"total_count":1}' | jq -e 'has("total_count") and (.check_runs |
  # length) == 0'` prints true and exits 0. Without the type test, a body
  # carrying total_count and no run array — the same malformed shape
  # check-runs-no-array.json models for the poll — reads as "demonstrably no
  # checks" and this function returns success, which is the one direction it
  # documents that it must never guess.
  # total_count is required to agree with the array, and not merely to be
  # present. `{"total_count":1,"check_runs":[]}` satisfies every other clause
  # here — the array is an array and it is empty — so without `.total_count ==
  # 0` a body that says a check-run exists is read as proof that none does, and
  # exit 5 tells the caller to mark a PR ready off a response that claimed the
  # opposite.
  printf '%s' "$listing" |
    jq -e 'has("total_count") and .total_count == 0
           and (.check_runs | type) == "array" and (.check_runs | length) == 0' >/dev/null 2>&1
}

rows=""
saw_listing=""
prev_fp=""
empty_polls=0
probed_default=""
# Whether a non-empty run list was EVER read on this commit. It is never reset,
# unlike empty_polls, and that is the point: exit 5 asserts that neither this
# commit nor the default branch's head carries a single check-run, so one
# observation of a check-run on this commit falsifies it for the rest of the
# watch. Without this, a commit whose checks were read once and whose listing
# later went empty — a transient answer, or a run deleted behind a re-run —
# reaches the grace with empty_polls reset to 0, probes, and is reported as a
# repository that runs no checks, contradicting a listing this script printed
# nothing about but did read.
saw_runs=""

for _ in $(seq 1 "$MAX_ITER"); do
  # A failing gh call is transient far more often than fatal (rate limit, a blip),
  # so it does not end the watch; the iteration cap is what ends it. The one
  # failure worth ending on is a SHA the remote does not have, because no amount
  # of waiting fixes it and every later iteration would ask the same wrong
  # question.
  # The status is kept, not discarded, because a failing call must not be able
  # to count as an OBSERVATION of anything. Only a call that succeeded can be
  # read as a listing below: without that, a poll that fails while printing
  # something shaped like an empty listing is counted toward the empty-listing
  # grace, and three of those plus an empty default branch produce exit 5 —
  # "this repository runs no checks" — for a commit whose check-runs were never
  # once read. The body alone cannot carry that distinction, since a listing
  # that is genuinely empty and a failure that merely looks empty are the same
  # bytes.
  poll_ok=yes
  raw="$(gh api "repos/${OWNER}/${REPO}/commits/${SHA}/check-runs" 2>/dev/null)" || poll_ok=""

  # This test stays OUTSIDE the status gate above: a SHA the remote does not
  # have is a 422, so `gh` exits non-zero and the body that names it arrives
  # only on a failed call. Gated, the one failure worth ending the watch on
  # would be read as an ordinary blip and every later iteration would ask the
  # same wrong question until the cap ran out.
  if printf '%s' "$raw" | grep -q 'No commit found for SHA'; then
    printf '%s\n' "$raw" >&2
    exit 3
  fi

  # total_count is the field that separates a real listing from an error body.
  # Testing for it — rather than for the absence of "in_progress" — is what keeps
  # an error from reading as "nothing is running".
  #
  # The render is then *tested* rather than assumed. `.check_runs[]` on a body
  # that carries total_count without a well-formed run array is a jq runtime
  # error, and jq's status for that is 5 — the number this script now uses for
  # "this repository runs no checks". Measured: `printf '{"total_count":1}' | jq
  # -r '.check_runs[]'` exits 5, and under `set -euo pipefail` an unguarded
  # assignment hands that status straight to the caller, who reads a malformed
  # body as a verdict about the repository and marks a PR ready having never
  # seen a check. Guarded, such a body is no listing at all, which is exit 4.
  #
  # The results land in temporaries and are committed to rows/fp only once the
  # whole chain has succeeded, because bash performs an assignment inside a
  # `&&` chain even when the command substitution fails and the chain
  # short-circuits. Measured: `rows=KEEPME; if true && rows="$(printf
  # '{"total_count":1}' | jq -r '.check_runs[]')"; then :; fi` leaves rows
  # empty. Assigned directly, a malformed body arriving after a good poll would
  # erase the listing the exit 1 path prints, and the person that timeout is
  # handed to would see an empty listing instead of the last one really read.
  # The same two agreements the default-branch probe demands are demanded here,
  # because this is the other way into the no-checks verdict. `has("total_count")`
  # alone proves neither: jq's `.check_runs[]` iterates an OBJECT's values too,
  # so `{"total_count":1,"check_runs":{}}` renders no rows and fingerprints as
  # `[]`, which walks into the empty-listing grace below and can reach exit 5;
  # and `{"total_count":1,"check_runs":[]}` is an empty array the body itself
  # contradicts. A non-empty array is accepted whatever total_count says, since
  # this call is not paginated and a truncated first page is still a real
  # listing — only an EMPTY array has to agree with total_count.
  if [ -n "$poll_ok" ] &&
    printf '%s' "$raw" | jq -e 'has("total_count") and (.check_runs | type) == "array"
       and ((.check_runs | length) > 0 or .total_count == 0)' >/dev/null 2>&1 &&
    new_rows="$(printf '%s' "$raw" | jq -r '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion // "-")"')" &&
    new_fp="$(printf '%s' "$raw" | jq -c '[.check_runs[].id] | sort')"; then
    rows="$new_rows"
    fp="$new_fp"
    saw_listing=yes

    if [ -n "$rows" ]; then
      empty_polls=0
      saw_runs=yes
      # "Every check completed" means nothing until the *set* of checks stops
      # changing. On a just-pushed commit the checks register a few at a time,
      # and a poll landing in that window sees a complete-looking listing —
      # every check in it completed, none of them failed — while the rest have
      # not been created yet. Without this comparison the caller is handed
      # "settled, nothing failed" for a subset it cannot tell from the whole,
      # and marks the PR ready before the checks that matter exist.
      #
      # The fingerprint is the sorted check_runs[].id list and not the names,
      # because .github/workflows/ci.yml runs `on: [push, pull_request]` and so
      # registers two checks of the same name: a set of names cannot tell the
      # window where only one of that pair exists from the settled state, and
      # the window it cannot see is exactly the one this guard is for.
      #
      # The status is tested on the JSON rather than by grepping the rendered
      # rows: a check whose *name* contains "in_progress" makes a row-wide match
      # read a completed check as still running, and the watch then never settles.
      if [ "$fp" = "$prev_fp" ] &&
        ! printf '%s' "$raw" | jq -e 'any(.check_runs[]; .status == "queued" or .status == "in_progress")' >/dev/null 2>&1; then
        printf '%s\n' "$rows"
        exit 0
      fi
    else
      # An empty run list is not "settled": on a just-pushed commit the checks
      # have not registered yet, and treating that as done would report a PR
      # with no CI as a PR whose CI passed. But a repository that runs no checks
      # stays empty forever, and answering that with the iteration cap spends
      # the caller's whole budget and then reports a *timeout* — which reads as
      # "CI is stuck" and sends the caller to diagnose a CI that does not exist.
      # So once the list has been empty for EMPTY_GRACE polls, the default
      # branch's head is read once to tell the two apart.
      #
      # Once, not once per poll: the probe is two API calls, and a repository
      # that genuinely runs no checks would otherwise pay them on every one of
      # the remaining polls. A probe that could not be read is not retried
      # either, because its failure already answers in the safe direction.
      empty_polls=$((empty_polls + 1))
      if [ -z "$saw_runs" ] && [ "$empty_polls" -ge "$EMPTY_GRACE" ] && [ -z "$probed_default" ]; then
        probed_default=yes
        if default_branch_runs_no_checks; then
          echo "no check-runs on ${SHA}, and none on the default branch's head: this repository does not run checks" >&2
          exit 5
        fi
      fi
    fi
    prev_fp="$fp"
  fi

  sleep "$INTERVAL"
done

if [ -z "$saw_listing" ]; then
  echo "no check-runs listing could be read for ${SHA}" >&2
  exit 4
fi

if [ -n "$rows" ]; then
  printf '%s\n' "$rows"
fi
exit 1
