#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/resolve-branch.sh: the branch
# names it prints for an issue number, and the two ways a caller must not read
# "no branch" out of it.
#
# git is not stubbed. Both halves of the script exist because of git's own exit
# statuses -- `git branch --list` exits 0 whether or not it matched, and
# `git ls-remote --exit-code` distinguishes 2 (no match) from a real failure --
# and a stub would encode the test author's belief about those instead of git's
# behaviour. Measured on git 2.43.0: `git branch --list` on no match is exit 0
# with empty stdout; `git ls-remote --exit-code --heads origin <glob>` is 0 on a
# match, 2 on no match, and 128 when the remote is unreachable or unset.
#
# Each row builds a real bare repository to play `origin` and a real work
# repository whose `origin` points at it, both under $HARNESS_TMP and both
# offline.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version. The header names one guard -- report by output, never by exit
# status -- and the script applies it in both halves, so there is one mutation
# per half and each is one defect wide:
#   - read `git branch --list`'s exit 0 as "no local match":
#     `local-only`, `multiple-matches`
#   - collapse the ls-remote status triage to "any non-zero means no match":
#     `ls-remote-itself-failed`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/resolve-branch.sh}"

failed=0
total=0

# build_case <name> [<local-branch>...] -- a work repository on `main` whose
# origin is a bare repo. `main` exists on both sides. Each <local-branch> is
# created locally off main and NOT pushed. Prints the work repository's path.
#
# Branches that must exist only on the remote are pushed by the row itself with
# `git_repo_push "$w" origin <local>:refs/heads/<name>` and then deleted
# locally, which is the only way to get "on the remote, not here".
build_case() {
  local name="$1" bare w b
  shift
  bare="$(git_repo_bare acme "$name")"
  w="$(git_repo_scratch "$name")"
  git_repo_init "$w" main
  git_repo_commit "$w" seed.txt 'seed\n' 'c1'
  git_repo_remote "$w" origin "$bare"
  git_repo_push "$w" origin main
  for b in "$@"; do
    git -C "$w" branch "$b" main
  done
  printf '%s\n' "$w"
}

# push_remote_only <work-dir> <name> -- create <name> on origin and nowhere
# locally.
push_remote_only() {
  git -C "$1" branch "tmp-$2" main
  git_repo_push "$1" origin "tmp-$2:refs/heads/$2"
  git -C "$1" branch -q -D "tmp-$2"
}

run_in() {
  local w="$1"
  shift
  cd "$w"
  run_sut bash "$SUT" "$@"
  cd "$REPO_ROOT"
}

# assert_row <name> <want-exit> <want-stdout>
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if ! check_eq "${name}: gh calls" 0 "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# ---- no branch for this issue ------------------------------------------
#
# The decoys are what make an empty answer mean something: `199-other` and
# `2011-later` both exist, locally and on the remote, and neither is matched by
# the glob `201-*`.

total=$((total + 1))
stub_dir_new
W="$(build_case nomatch 199-other)"
push_remote_only "$W" 2011-later
run_in "$W" 201
assert_row 'no-match' 0 ''

# ---- local only --------------------------------------------------------
#
# The first row the local-half mutation must fail: `git branch --list` exits 0
# on no match, so a script reading that exit status as the answer reports
# nothing here and the caller cuts a second branch for the same task.

total=$((total + 1))
stub_dir_new
W="$(build_case localonly 201-alpha)"
run_in "$W" 201
assert_row 'local-only' 0 '201-alpha\n'

# ---- remote only -------------------------------------------------------
#
# The branch a fresh checkout has never seen. Missing it strands pushed work
# under a diverged history, and force-push is barred.

total=$((total + 1))
stub_dir_new
W="$(build_case remoteonly)"
push_remote_only "$W" 201-beta
run_in "$W" 201
assert_row 'remote-only' 0 '201-beta\n'

# ---- on both sides, deduplicated ---------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case both 201-gamma)"
git_repo_push "$W" origin 201-gamma
run_in "$W" 201
assert_row 'both-sides-deduplicated' 0 '201-gamma\n'

# ---- more than one branch for the issue ---------------------------------
#
# Also the second row the local-half mutation must fail: `201-a` is local only,
# so a mutant that loses the local half prints two lines instead of three.

total=$((total + 1))
stub_dir_new
W="$(build_case multi 201-a 201-c)"
push_remote_only "$W" 201-b
git_repo_push "$W" origin 201-c
run_in "$W" 201
assert_row 'multiple-matches' 0 '201-a\n201-b\n201-c\n'

# ---- a non-numeric argument --------------------------------------------
#
# The argument becomes a glob prefix, so `foo` would match `foo-x` -- which
# this repository has -- and a single match reads as "this task already has a
# branch". The guard has to refuse before either query runs, so the assertion
# is exit 1 with nothing on stdout even though a match is sitting right there.

total=$((total + 1))
stub_dir_new
W="$(build_case nonnumeric foo-x)"
run_in "$W" foo
assert_row 'non-numeric-argument' 1 ''

# ---- ls-remote itself failed -------------------------------------------
#
# The row the remote-half mutation must fail. `origin` points at a path that is
# not a repository, so ls-remote exits 128 -- not the 2 that means "no match".
# Reading any non-zero as "no match" turns "could not ask" into "there is no
# branch", and the local `201-alpha` sitting here is what makes the difference
# visible: the correct script refuses to answer at all, exit 128 with nothing on
# stdout, rather than handing back a partial listing.

total=$((total + 1))
stub_dir_new
W="$(build_case lsremotefail 201-alpha)"
git -C "$W" remote set-url origin "${HARNESS_TMP}/remotes/acme/absent.git"
run_in "$W" 201
assert_row 'ls-remote-itself-failed' 128 ''
total=$((total + 1))
if ! check_eq 'ls-remote-itself-failed: names the failure on stderr' 'yes' \
  "$(grep -q 'git ls-remote failed' "$SUT_STDERR" && echo yes || echo no)"; then
  failed=$((failed + 1))
fi

# ---- argument validation -----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case argsnone)"
run_in "$W"
assert_row 'no-arguments' 1 ''

total=$((total + 1))
stub_dir_new
W="$(build_case argstwo)"
run_in "$W" 201 extra
assert_row 'two-arguments' 1 ''

harness_exit "$failed" "$total"
