#!/usr/bin/env bash
# Check that a PR reference names the repository this checkout reviews from,
# and print the PR number with that repository.
#
# review-pr resolves its range with tools/resolve-range.sh, which fetches the
# PR's head and base from `origin`. If the reference names a repository other
# than origin's, PR <n> of that other repository resolves without complaint,
# the review is drafted against an unrelated diff, and it is posted to the PR
# the user asked about. So the URL must name this checkout's origin, compared
# before anything is resolved.
#
# Only the base repository is compared. A PR opened from a fork keeps its head
# at refs/pull/<n>/head on the base repository, which is where resolve-range
# fetches it from, and this skill pushes nothing, so neither the PR's head
# repository nor origin's push URL is read.
#
# It calls no GitHub client. That the means reads the PR from origin's
# repository, not the one it defaults to (GH_REPO, a default-repo setting, a
# second remote), is the `repo` fact's pin in facts.md, checked by every script
# that reads a record.
#
# Conventions: ../../implement-work/references/script-conventions.md.
# STOP slugs: ../../implement-work/references/stop-registry.md.
#
# Usage: check-pr-repo.sh <pr-number-or-url>
# Output: PR <n> repo=<owner>/<repo> | STOP wrong-checkout
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  echo "Usage: $0 <pr-number-or-url>" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
REF="$1"

# Reduce a remote URL or an owner/repo pair to lowercase `<owner>/<repo>`.
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

if ! CHECKOUT="$(bash "${SCRIPT_DIR}/../../../tools/origin-repo.sh")"; then
  echo "STOP wrong-checkout"
  exit 0
fi

if [ -n "$NAMED" ] && [ "$NAMED" != "$CHECKOUT" ]; then
  echo "STOP wrong-checkout"
  exit 0
fi

echo "PR ${NUMBER} repo=${CHECKOUT}"
