#!/usr/bin/env bash
# Check that a PR reference names the repository this checkout reviews from,
# and print the PR number with that repository.
#
# review-pr resolves its range with ../../review-code/scripts/resolve-range.sh,
# which reads the PR record through `gh pr view <n>` -- answered from whichever
# repository gh resolves here -- and fetches the PR's head and base from
# `origin`. If either names a repository other than the reference's, PR <n> of
# that other repository resolves without complaint, the review is drafted
# against an unrelated diff, and it is posted to the PR the user asked about.
# gh and origin can disagree with each other (GH_REPO, `gh repo set-default`, a
# second remote), so both are compared, before anything is resolved.
#
# Only the base repository is compared. A PR opened from a fork keeps its head
# at refs/pull/<n>/head on the base repository, which is where resolve-range
# fetches it from, and this skill pushes nothing, so neither the PR's head
# repository nor origin's push URL is read -- the cross-fork and push-URL
# stops in ../../pr-to-ready/scripts/resolve-pr-entry.sh guard pushes this
# skill never makes.
#
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: check-pr-repo.sh <pr-number-or-url>
# Output: PR <n> repo=<owner>/<repo> | STOP wrong-checkout | STOP repo-lookup-failed
set -euo pipefail

usage() {
  echo "Usage: $0 <pr-number-or-url>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
REF="$1"

# Reduce a remote URL or an owner/repo pair to lowercase `<owner>/<repo>`.
# Copied from ../../pr-to-ready/scripts/resolve-pr-entry.sh, whose comment
# says why each strip and the case fold are there.
normalize_repo_path() {
  local url="$1" owner repo
  repo="${url##*/}"
  repo="${repo%.git}"
  owner="${url%/*}"
  owner="${owner##*/}"
  owner="${owner##*:}"
  printf '%s/%s\n' "${owner}" "${repo}" | tr '[:upper:]' '[:lower:]'
}

if [[ "$REF" =~ ^[0-9]+$ ]]; then
  # A bare number carries no repository, so it can only mean origin's.
  NUMBER="$REF"
  NAMED=""
elif [[ "$REF" =~ ^(https?://)?[^/]+/([^/]+)/([^/]+)/pull/([0-9]+)([/?#].*)?$ ]]; then
  NAMED="$(normalize_repo_path "${BASH_REMATCH[2]}/${BASH_REMATCH[3]}")"
  NUMBER="${BASH_REMATCH[4]}"
else
  usage
fi

if ! ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || [ -z "$ORIGIN_URL" ]; then
  echo "STOP wrong-checkout"
  exit 0
fi
CHECKOUT="$(normalize_repo_path "$ORIGIN_URL")"

if [ -n "$NAMED" ] && [ "$NAMED" != "$CHECKOUT" ]; then
  echo "STOP wrong-checkout"
  exit 0
fi

if ! RESOLVED="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
  echo "STOP repo-lookup-failed"
  exit 0
fi
if [ "$(normalize_repo_path "$RESOLVED")" != "$CHECKOUT" ]; then
  echo "STOP wrong-checkout"
  exit 0
fi

echo "PR ${NUMBER} repo=${CHECKOUT}"
