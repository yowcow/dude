#!/usr/bin/env bash
# Resolve which branch a task branch should sit on, by reading its
# Base-Branch trailer and re-checking the prerequisite PR's *current* state —
# never by testing whether the prerequisite's branch still exists.
#
# This always prints a concrete branch name, even where the cited table says
# to omit `--base` — Step 1's base settlement compares this answer against the
# base the PR currently points at, and has nothing to compare against if the
# no-trailer case answers with an absence. Naming the default branch there
# selects exactly what omitting the flag would have.
#
# A merged prerequisite's branch commonly survives (branch deletion is a
# person's separate step), so a plain existence test would read a long-since
# merged prerequisite as "still in flight" and hand back its branch as
# --base. Merging this task into that branch then puts nothing into the
# default branch, and the change silently fails to land. See
# ../../implement-work/references/base-branch.md, "## Reading the trailer
# back" and "### Why the state is re-read and the branch is not" — this
# script implements that table's `pr-to-ready`'s `--base` column.
#
# Usage: resolve-pr-base.sh <branch>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <branch>" >&2
  exit 1
fi

BRANCH="$1"

# Two-rung ladder, never guessing a branch name: the GitHub API, then give up
# and let the caller ask a person. `.defaultBranchRef.name` gives the bare name
# this caller needs, since it compares the result against branch names rather
# than fetching a ref with it.
#
# refs/remotes/origin/HEAD is deliberately not consulted. A clone sets that
# symref once and never refreshes it, so after the repository renames its
# default branch it keeps naming the old one; while that branch still exists
# this function would answer with it, the PR would be opened or retargeted
# against the wrong base, and nothing would say so. Reading it saved one `gh`
# call and nothing else -- every path that reaches here fetches immediately
# afterwards, so there was no offline case to keep.
resolve_default_branch() {
  local ref
  if ref="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" && [ -n "$ref" ]; then
    printf '%s\n' "$ref"
    return 0
  fi
  return 1
}

fetch_ref() {
  git fetch origin "$1" >&2
}

# Resolve the default branch before the scan below rather than at the two
# places that print it: the scan's range is expressed against it, so it has
# to be both named and fetched by then.
DEFAULT="$(resolve_default_branch)" || { echo "STOP ask-default-branch"; exit 0; }

# The task branch's tip is read below as FETCH_HEAD rather than from a local
# checkout — this session may not have <branch> checked out at all. So the
# default branch is fetched first and the task branch second, because `git
# fetch` rewrites FETCH_HEAD on every call. Reversed, FETCH_HEAD would hold
# the default branch's tip, the scan below would read the empty range
# `<default> ^<default>`, and every branch would silently resolve to the
# default branch as its base.
#
# The default branch's fetch failure carries its own slug: folded into
# fetch-failed, the caller could not tell a missing task branch from a
# missing default branch, and the two want different answers from the person
# they stop for.
if ! fetch_ref "${DEFAULT}"; then
  echo "STOP default-fetch-failed"
  exit 0
fi

if ! fetch_ref "${BRANCH}"; then
  echo "STOP fetch-failed"
  exit 0
fi

# Capture the trailer scan into a variable before testing it, rather than
# piping into `grep`. A pipe would report only grep's exit status, and grep
# exits 1 on empty input whether the trailer is genuinely absent or the read
# itself failed — two causes that must not collapse to the same answer. Scan
# newest-first (git log's default order) since a trailer on a later commit
# shadows an earlier one in the same stack.
# The range stops at the default branch, and the exclusion names the
# remote-tracking ref just fetched rather than a local branch that may be
# absent or stale. Unbounded, the scan walks to root, so a branch that
# recorded nothing picks up whatever Base-Branch some unrelated commit left
# in shared history and hands that branch back as --base — which
# ensure-draft-pr.sh then passes to `gh pr create --base`, opening the PR
# against a branch this task never sat on.
# The read is guarded as well as captured: under `set -e` a failing `git log`
# inside a bare command substitution would kill the script outright, and the
# caller would get a non-zero exit with nothing on stdout instead of a STOP.
if ! TRAILER_LOG="$(git log FETCH_HEAD "^refs/remotes/origin/${DEFAULT}" --format='%(trailers:key=Base-Branch,valueonly,unfold)')"; then
  echo "STOP trailer-read-failed"
  exit 0
fi

RECORDED=""
while IFS= read -r line; do
  if [ -n "$line" ]; then
    RECORDED="$line"
    break
  fi
done <<<"$TRAILER_LOG"

if [ -z "$RECORDED" ]; then
  echo "BASE ${DEFAULT}"
  exit 0
fi

# Read the exit status and the line count together. A non-zero exit prints
# nothing and looks exactly like "no PR" — auth, network, or repo-context
# failures behave the same way — so it is "couldn't tell", not "no match".
# `.[]` rather than `.[0]` so an empty list yields zero lines and several
# matches yield several, instead of one arbitrary pick or an interpolated
# "null".
if ! PR_LOOKUP="$(gh pr list --head "$RECORDED" --state all --json number,state --jq '.[] | "\(.number) \(.state)"' 2>/dev/null)"; then
  echo "STOP prereq-lookup-failed"
  exit 0
fi

LINE_COUNT=0
if [ -n "$PR_LOOKUP" ]; then
  LINE_COUNT="$(printf '%s\n' "$PR_LOOKUP" | wc -l)"
fi

if [ "$LINE_COUNT" -eq 0 ]; then
  echo "STOP no-prereq-pr"
  exit 0
fi

if [ "$LINE_COUNT" -ge 2 ]; then
  echo "STOP ask-multiple-prs"
  exit 0
fi

STATE="${PR_LOOKUP##* }"

case "${STATE}" in
  OPEN)
    echo "BASE ${RECORDED}"
    ;;
  MERGED)
    # A merged prerequisite whose branch is still around must not be read as
    # "still in flight": that would hand back --base <merged-branch>, and
    # merging into an already-merged branch puts nothing into the default
    # branch, so the change silently fails to land there.
    echo "BASE ${DEFAULT}"
    ;;
  CLOSED)
    echo "STOP abandoned-prerequisite"
    ;;
  *)
    echo "error: unexpected PR state '${STATE}' for '${RECORDED}'" >&2
    exit 1
    ;;
esac
