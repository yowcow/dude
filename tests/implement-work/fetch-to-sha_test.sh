#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/fetch-to-sha.sh: the SHA it
# prints for a fetchable ref, and the empty-stdout exit 1 for anything it
# cannot fetch.
#
# git is not stubbed (tests/lib/gitrepo.sh builders make a real bare remote
# and a real clone under $HARNESS_TMP; GIT_ALLOW_PROTOCOL=file keeps it
# offline). gh is never called: every row asserts 0 gh calls.
#
# RED verification: copy this file's SUT to a mktemp dir (never inside the
# repository, where lint.sh would select it by shebang), replace the
# `git rev-parse FETCH_HEAD` line with `git rev-parse HEAD`, and re-run as
# `SUT=<copy> tests/run.sh tests/implement-work/fetch-to-sha_test.sh`:
# `fetches-branch-tip` must fail with the work clone's HEAD where the
# remote's tip is wanted.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/fetch-to-sha.sh}"

failed=0
total=0

REMOTE="$(git_repo_bare acme fetchsha)"
SEED="$(git_repo_scratch seed-fetchsha)"
git_repo_init "$SEED" trunk
git_repo_commit "$SEED" trunk-file 'content\n' 'seed commit'
git_repo_push "$SEED" "$REMOTE" trunk
W="$(git_repo_clone work-fetchsha "$REMOTE" trunk)"
git_repo_commit "$SEED" trunk-file-2 'content2\n' 'second commit'
git_repo_push "$SEED" "$REMOTE" trunk
TIP_SHA="$(git -C "$REMOTE" rev-parse trunk)"

row_start
run_in "$W" trunk
assert_row 'fetches-branch-tip' 0 "${TIP_SHA}\n" 0

row_start
run_in "$W" "refs/heads/trunk"
assert_row 'fetches-fully-qualified-ref' 0 "${TIP_SHA}\n" 0

row_start
run_in "$W" no-such-branch
assert_row 'unknown-ref-fails-empty' 1 '' 0

row_start
run_in "$W"
assert_row 'no-arguments' 2 '' 0

row_start
run_in "$W" trunk extra
assert_row 'too-many-arguments' 2 '' 0

harness_exit "$failed" "$total"
