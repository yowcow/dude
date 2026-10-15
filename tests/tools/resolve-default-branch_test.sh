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

# ---- [repo] --------------------------------------------------------------
#
# The upstream bare sits outside ${HARNESS_TMP}/remotes/ on purpose: every
# git_repo_bare path is origin's sibling, so a remote built there is also what
# the fallback derives, and the remote-match loop would go untested. The decoy
# sits at the derived sibling path and answers `trunk`, so a script that skips
# the remote match reads `trunk`, not `main`.
git_repo_remote "$W" origin "$BARE"
U="$(git_repo_scratch upstreams)/acme/parent.git"
mkdir -p "${U%/*}"
git init -q --bare "$U"
seed "$U" main
git_repo_remote "$W" upstream "$U"
D="$(git_repo_bare acme parent)"
seed "$D" trunk

row_start
run_in "$W" acme/parent
assert_row 'repo-arg-selects-its-remote' 0 'main\n' 0

row_start
run_in "$W" Acme/Parent
assert_row 'repo-arg-matches-case-insensitively' 0 'main\n' 0

row_start
run_in "$W" acme/widgets
assert_row 'repo-arg-equal-to-origin' 0 'trunk\n' 0

row_start
E="$(git_repo_bare acme elsewhere)"
seed "$E" trunk
git -C "$W" remote remove upstream
run_in "$W" acme/elsewhere
assert_row 'repo-arg-with-no-remote-reads-origins-sibling' 0 'trunk\n' 0

row_start
run_in "$W" acme/nosuch
assert_row 'repo-arg-unreachable' 1 '' 0

row_start
run_in "$W" acme/parent extra
assert_row 'two-arguments-is-usage-error' 2 '' 0

# A relative two-segment origin URL leaves nothing in front of the [repo]
# swap, so the remote handed to git is the argument itself plus `.git`; a
# leading dash makes that an option. The marker is relative and lower-case
# because the argument is lower-cased and git runs from the work dir.
row_start
DASH="$(git_repo_scratch dash)"
git_repo_init "$DASH" trunk
git_repo_remote "$DASH" origin a/b
run_in "$DASH" '--upload-pack=touch m'
assert_row 'repo-arg-with-leading-dash-is-no-option' 1 '' 0
tally check_eq 'repo-arg-with-leading-dash-is-no-option: no side effect' absent \
  "$([ -e "${DASH}/m.git" ] && echo ran || echo absent)"

harness_exit "$failed" "$total"
