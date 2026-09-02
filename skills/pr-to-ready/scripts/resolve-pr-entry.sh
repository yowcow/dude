#!/usr/bin/env bash
# Resolve a PR reference — a bare number or a PR URL — into the four things a
# pr-to-ready run needs before it can touch anything: the PR number, its head
# branch, its base, and the repository the PR lives in. It also refuses to
# answer at all from a working tree that is not a checkout of that repository.
#
# The reference decides the repository, and that is the whole reason this is a
# script rather than a bare `gh pr view` in the SKILL. Run
# `gh pr view <n> --json headRefName` from a different repository's checkout
# and `<n>` resolves against *that* repository: the command exits 0 and prints
# the head branch of an unrelated PR. Step 0 then fetches that branch into a
# worktree, Step 1's diagnosis fix and 2-3's `accept` fixes are committed onto
# it, and the push lands on a branch the PR never pointed at — reviewed by
# nobody, while the PR it was meant for does not move.
#
# Naming the repository is not by itself enough to stop that, which is why the
# origin comparison below exists. ../../implement-work/scripts/attach-workspace.sh,
# which Step 0-3 calls next, works entirely against the current repository and
# its `origin`, and takes no owner or repo argument. So with a URL naming
# `acme/widgets` and a cwd whose origin is a fork or a sibling clone, that
# script finds the same branch name on the *wrong* remote and answers
# `ATTACHED`; every later fix is then committed in that tree and
# `git push origin` sends it to the wrong repository. Nothing downstream
# catches it: ./check-pr-state.sh's identical comparison lives inside its
# local-mergeability fallback, which does not run when GitHub answers
# `mergeable`, and ./retarget-pr.sh only compares HEAD against the branch name,
# which matches in the wrong repository too.
#
# ./retarget-pr.sh's `STOP checkout-required` and `STOP dirty-worktree` are NOT
# evidence for either failure above, and a reviewer applying AUTHORING.md's
# rule 2 should not read them as one. Those guards fire before that script's
# own first mutation, so they are the deletion test's (b) — the run stops and
# asks a person. They also guard only retarget-pr.sh's own merge: Step 1's fix
# and 2-3's fixes pass through no such gate, which is where the (c) lives.
#
# The lookup is `gh api graphql` rather than `gh pr view` because three answers
# have to stay apart and `gh pr view` collapses two of them: it exits non-zero
# both when the PR does not exist and when the call itself failed, and reading
# a message off stderr to tell them apart breaks the day gh rewords it.
# GraphQL reports "no such node" as a machine-readable `errors[].type ==
# "NOT_FOUND"`, and gh prints the whole response body on stdout even as it
# exits 1 on that array (measured against github.com on gh 2.x) — so the body,
# not the exit status, is what separates them. Collapsing them would answer a
# rate-limited lookup with "this PR does not exist", and the person would go
# looking for a PR that is sitting right there.
#
# Usage: resolve-pr-entry.sh <pr-number-or-url>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <pr-number-or-url>" >&2
  exit 1
fi

REF="$1"

QUERY='query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      number
      headRefName
      baseRefName
      state
      isDraft
      isCrossRepository
    }
  }
}'

# The same reduction ./check-pr-state.sh performs, kept as a copy because this
# tree has no shared library under scripts/ and adding one would put a file
# with no behaviour of its own under the coverage gate. That script's header
# carries the full account of why the scp form and the case fold are both
# load-bearing; in short, `git@host:owner/repo` hides the host inside the owner
# segment, and GitHub matches owner and repo case-insensitively.
normalize_repo_path() {
  local url="$1" owner repo
  repo="${url##*/}"
  repo="${repo%.git}"
  owner="${url%/*}"
  owner="${owner##*/}"
  owner="${owner##*:}"
  printf '%s/%s\n' "${owner}" "${repo}" | tr '[:upper:]' '[:lower:]'
}

# --- Step 1: whose checkout is this? ---

# `origin` rather than `gh`'s own repository resolution, because `origin` is
# what everything downstream actually uses — attach-workspace.sh fetches from
# it, and every fix is pushed to it. `gh repo view` can answer differently
# (GH_REPO, `gh repo set-default`, a second remote), and an identity check that
# reads a different remote than the one being written to checks nothing.
if ! ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || [ -z "$ORIGIN_URL" ]; then
  echo "STOP wrong-checkout"
  exit 0
fi
CHECKOUT="$(normalize_repo_path "$ORIGIN_URL")"

# --- Step 2: split the reference into owner, repo and number. ---

if [[ "$REF" =~ ^[0-9]+$ ]]; then
  # A bare number carries no repository, so this checkout's is the only one it
  # can mean — and it therefore passes the comparison below by construction.
  NUMBER="$REF"
  OWNER="${CHECKOUT%%/*}"
  REPO="${CHECKOUT#*/}"
elif [[ "$REF" =~ ^(https?://)?[^/]+/([^/]+)/([^/]+)/pull/([0-9]+)([/?#].*)?$ ]]; then
  OWNER="${BASH_REMATCH[2]}"
  REPO="${BASH_REMATCH[3]}"
  NUMBER="${BASH_REMATCH[4]}"
  # Compared against what the reference *named*, never against the name GitHub
  # would call canonical: a renamed repository answers with its new name while
  # a correct checkout's origin still carries the old one, and comparing
  # against the canonical name would reject that checkout. The host is not
  # compared, which leaves the same known limitation ./check-pr-state.sh
  # records — a repository of the same owner and name on a different host.
  if [ "$(normalize_repo_path "${OWNER}/${REPO}")" != "$CHECKOUT" ]; then
    echo "STOP wrong-checkout"
    exit 0
  fi
else
  echo "error: unrecognized PR reference '${REF}'" >&2
  exit 1
fi

# --- Step 3: one lookup, read as three answers. ---

# `owner` and `name` are `-f` (raw string): `-F`'s magic type conversion would
# turn a digits-only repository or owner — e.g. github.com/gabrielecirulli/2048
# — into a JSON number against `$name:String!`, and GitHub's coercion error
# carries no `.type`, so it reads as a lookup failure for a PR that exists.
# `number` stays `-F` — it must be a JSON integer for `$number:Int!`.
#
# Guarded like the read below, because under `set -e` a non-zero `gh` inside a
# bare command substitution kills the script outright and the caller would get a
# bare non-zero exit with nothing on stdout instead of a STOP line. The body is
# captured either way — `gh` prints it even as it exits 1 on an `errors` array —
# and it is what tells the two answers below apart.
if ! RESPONSE="$(gh api graphql -f "query=${QUERY}" \
  -f "owner=${OWNER}" -f "name=${REPO}" -F "number=${NUMBER}" 2>/dev/null)"; then
  # Every error NOT_FOUND means the reference names nothing — a PR number that
  # does not exist, or a repository that no longer does. Anything else, an
  # empty body included, is the lookup itself failing.
  if printf '%s' "$RESPONSE" |
    jq -e '[.errors[]? | .type] as $t | ($t | length) > 0 and (($t - ["NOT_FOUND"]) | length) == 0' \
      >/dev/null 2>&1; then
    echo "STOP no-pr"
    exit 0
  fi
  echo "STOP pr-lookup-failed"
  exit 0
fi

# A guarded read, for the same reason the capture above is guarded: a jq that
# fails on an unexpected body must reach a STOP line rather than kill the
# script. `select(. != null)` turns a null node into no output at all, which
# the emptiness test below reads as "no PR" — the exit-0 spelling of the same
# answer the errors array gives.
if ! FIELDS="$(printf '%s' "$RESPONSE" |
  jq -r '.data.repository.pullRequest | select(. != null)
    | "\(.number) \(.headRefName) \(.baseRefName) \(.state) \(.isDraft) \(.isCrossRepository)"' 2>/dev/null)"; then
  echo "STOP pr-lookup-failed"
  exit 0
fi

if [ -z "$FIELDS" ]; then
  echo "STOP no-pr"
  exit 0
fi

read -r NUM HEAD BASE STATE DRAFT CROSS <<<"$FIELDS"

# A merged or closed PR has nothing for this flow to drive: there is no CI to
# get green and no review round that would change what lands.
if [ "$STATE" != "OPEN" ]; then
  echo "STOP pr-not-open"
  exit 0
fi

# The origin comparison above cannot catch this one: a cross-fork PR's base
# repository IS the repository the reference names, so the reference and
# `origin` agree while the head branch sits on a remote neither of them is.
# Everything downstream assumes otherwise — attach-workspace.sh looks the
# branch up on `origin`, and so does every push. Left unchecked, a PR opened
# from a fork's `main` finds this repository's own `main` on `origin`, and the
# run commits its fixes onto the default branch and pushes them there while
# the PR stays exactly as it was.
if [ "$CROSS" != "false" ]; then
  echo "STOP cross-fork"
  exit 0
fi

echo "PR ${NUM} branch=${HEAD} base=${BASE} repo=${OWNER}/${REPO} draft=${DRAFT}"
