#!/usr/bin/env bash
# Table test for tools/resolve-default-branch.sh: what it prints and what it
# exits for each answer a remote's HEAD can give.
#
# Every caller reads this script's stdout as a branch name and its non-zero
# exit as "could not tell", so every row asserts both halves and that gh was
# never called.
#
# RED verification (see tests/README.md): against the pre-port script
# (`git show master:tools/resolve-default-branch.sh` in a copy under
# `mktemp -d`, run as `SUT=<copy> tests/run.sh <this file>`) every row but the
# usage row fails on an unstubbed `gh repo view`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/resolve-default-branch.sh}"

failed=0
total=0

# seed <bare> <branch>...   a commit on each branch, pushed to <bare>; HEAD
#                           points at the first branch
SEEDS=0
seed() {
  local bare="$1" b seedwork
  shift
  SEEDS=$((SEEDS + 1))
  seedwork="$(git_repo_scratch "seed${SEEDS}")"
  git_repo_init "$seedwork" "$1"
  git_repo_commit "$seedwork" f.txt 'x\n' 'init'
  for b in "$@"; do
    if [ "$b" != "$1" ]; then git_repo_checkout "$seedwork" "$b" "$1"; fi
  done
  git_repo_remote "$seedwork" origin "$bare"
  for b in "$@"; do git_repo_push "$seedwork" origin "$b"; done
  git_repo_bare_head "$bare" "$1"
}

# `trunk` rather than `main`: a mutant that guesses the conventional name
# instead of asking would pass a row named `main`.
BARE="$(git_repo_bare acme widgets)"
seed "$BARE" trunk other
W="$(git_repo_clone work "$BARE" trunk)"

row_start
run_in "$W"
assert_row 'remote-head-names-the-branch' 0 'trunk\n' 0

row_start
git_repo_origin_head "$W" other
run_in "$W"
assert_row 'stale-local-symref-is-ignored' 0 'trunk\n' 0

# ---- the ways of not knowing ---------------------------------------------

row_start
UNBORN="$(git_repo_bare acme empty)"
git_repo_remote "$W" origin "$UNBORN"
run_in "$W"
assert_row 'remote-head-unborn' 1 '' 0

row_start
DET="$(git_repo_bare acme detached)"
seed "$DET" trunk
git -C "$DET" update-ref --no-deref HEAD "$(git -C "$DET" rev-parse refs/heads/trunk)"
git_repo_remote "$W" origin "$DET"
run_in "$W"
assert_row 'remote-head-detached' 1 '' 0

row_start
git_repo_remote "$W" origin "${HARNESS_TMP}/remotes/acme/nosuch.git"
run_in "$W"
assert_row 'ls-remote-fails' 1 '' 0

row_start
NOREMOTE="$(git_repo_scratch noremote)"
git_repo_init "$NOREMOTE" trunk
run_in "$NOREMOTE"
assert_row 'no-origin' 1 '' 0

row_start
run_in "$W" acme/widgets
assert_row 'an-argument-is-usage-error' 2 '' 0

harness_exit "$failed" "$total"
