#!/usr/bin/env bash
# Table test for skills/review-pr/scripts/check-pr-repo.sh: the repository a
# PR reference names has to be both this checkout's origin and the repository
# gh resolves here, or the run stops before any range is resolved. A checkout
# that pushes to the reviewer's own fork passes: only the base repository is
# compared.
#
# git is not stubbed: the SUT reads `git remote get-url origin`, and a real
# repository whose origin path ends in acme/widgets.git presents that identity
# offline (see ../lib/gitrepo.sh).
#
# RED verification (see tests/README.md): dropping the gh comparison makes
# 'url matches origin, gh resolves elsewhere' answer a PR line; dropping the
# origin comparison makes 'url naming another repository' do the same.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/review-pr/scripts/check-pr-repo.sh}"

failed=0
total=0

ACME_WIDGETS="$(git_repo_bare acme widgets)"

WIDGETS="$(git_repo_scratch widgets-work)"
git_repo_init "$WIDGETS" main
git_repo_remote "$WIDGETS" origin "$ACME_WIDGETS"

# Fetches acme/widgets, pushes to the reviewer's fork. Set repo-locally:
# ../lib/gitrepo.sh cuts the global config out.
PUSHFORK="$(git_repo_scratch pushfork-work)"
git_repo_init "$PUSHFORK" main
git_repo_remote "$PUSHFORK" origin "$ACME_WIDGETS"
git -C "$PUSHFORK" config remote.origin.pushurl "$(git_repo_bare me widgets)"

NOREMOTE="$(git_repo_scratch noremote-work)"
git_repo_init "$NOREMOTE" main

# stub_gh_repo <exit-status>   gh's own repository resolution, body on stdin
stub_gh_repo() {
  gh_stub_response '*' "$1" repo view --json nameWithOwner --jq .nameWithOwner
}

row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" 12
assert_row 'bare number' 0 'PR 12 repo=acme/widgets\n' 1

row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12
assert_row 'url' 0 'PR 12 repo=acme/widgets\n' 1

row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12/files
assert_row 'url with trailing path' 0 'PR 12 repo=acme/widgets\n' 1

row_start
printf 'Acme/Widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" https://github.com/ACME/widgets/pull/12
assert_row 'case differs' 0 'PR 12 repo=acme/widgets\n' 1

# The gh stub is in place and still never answers: `gh calls == 0` is the
# origin guard firing before gh is asked.
row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" https://github.com/other/elsewhere/pull/12
assert_row 'url naming another repository' 0 'STOP wrong-checkout\n' 0

row_start
printf 'fork/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" https://github.com/acme/widgets/pull/12
assert_row 'url matches origin, gh resolves elsewhere' 0 'STOP wrong-checkout\n' 1

row_start
printf 'fork/widgets\n' | stub_gh_repo 0
run_in "$WIDGETS" 12
assert_row 'bare number, gh resolves elsewhere' 0 'STOP wrong-checkout\n' 1

row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$PUSHFORK" https://github.com/acme/widgets/pull/12
assert_row 'checkout pushing to a fork' 0 'PR 12 repo=acme/widgets\n' 1

row_start
printf 'acme/widgets\n' | stub_gh_repo 0
run_in "$NOREMOTE" 12
assert_row 'no origin' 0 'STOP wrong-checkout\n' 0

row_start
: | stub_gh_repo 1
run_in "$WIDGETS" 12
assert_row 'gh cannot resolve a repository' 0 'STOP repo-lookup-failed\n' 1

row_start
run_in "$WIDGETS" not-a-reference
assert_row 'unparseable reference' 2 '' 0

row_start
run_in "$WIDGETS"
assert_row 'no argument' 2 '' 0

harness_exit "$failed" "$total"
