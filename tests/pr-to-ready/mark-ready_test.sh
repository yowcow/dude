#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/mark-ready.sh: the record it reads,
# the PR head it compares against, and the one `gh pr ready` it may make.
#
# git is not stubbed: the record lives in a real repository's git dir, written
# here through seed_record. RECORD_NAME and the `<verdict> <sha>` line are
# copies of what recheck-pr.sh writes; `met-and-current-goes-ready` is the row
# that fails if they drift, and recheck-pr_test.sh's
# `clean-records-met: mark-ready goes ready` pins the same pair from the
# writer's side.
#
# `gh pr ready` is stubbed only on rows that expect it to be reached, so a row
# that should refuse and calls it anyway fails as an unstubbed argv.
#
# `stale-met-record-cleared-at-0-3` is `met-and-current-goes-ready` with one
# difference, the 0-3 clear in between: an earlier run left a met record on the
# same SHA, and this run never re-confirmed.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; the broken variant drops the head comparison and fails
# `head-moved`.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/mark-ready.sh}"
CLEAR="${REPO_ROOT}/skills/pr-to-ready/scripts/clear-recheck-record.sh"
RECORD_NAME='dude-pr-to-ready-recheck'

failed=0
total=0

# new_repo <name> -- an empty repository; prints its path.
new_repo() {
  local w
  w="$(git_repo_scratch "$1")"
  git_repo_init "$w" main
  printf '%s\n' "$w"
}

# seed_record <repo> <line> -- what an earlier recheck-pr.sh run left behind.
seed_record() {
  printf '%s\n' "$2" >"$(git -C "$1" rev-parse --absolute-git-dir)/${RECORD_NAME}"
}

# stub_head <sha> -- every head read answers <sha>.
stub_head() {
  printf '%s\n' "$1" |
    gh_stub_response '*' 0 pr view -R acme/widgets --json headRefOid --jq .headRefOid -- 7
}

# stub_ready <exit-status>
stub_ready() {
  : | gh_stub_response '*' "$1" pr ready -R acme/widgets -- 7
}

row_start
W="$(new_repo no-record)"
run_in "$W" acme widgets 7
assert_row 'no-record' 0 'STOP no-record\n' 0

row_start
W="$(new_repo ready)"
seed_record "$W" 'met deadbeef'
stub_head deadbeef
stub_ready 0
run_in "$W" acme widgets 7
assert_row 'met-and-current-goes-ready' 0 'READY 7\n' 2

row_start
W="$(new_repo head-moved)"
seed_record "$W" 'met deadbeef'
stub_head cafef00d
run_in "$W" acme widgets 7
assert_row 'head-moved' 0 'STOP head-moved\n' 1

row_start
W="$(new_repo unmet)"
seed_record "$W" 'unmet deadbeef'
run_in "$W" acme widgets 7
assert_row 'unmet' 0 'STOP conditions-unmet\n' 0

row_start
W="$(new_repo stale)"
seed_record "$W" 'met deadbeef'
(cd "$W" && bash "$CLEAR")
stub_head deadbeef
stub_ready 0
run_in "$W" acme widgets 7
assert_row 'stale-met-record-cleared-at-0-3' 0 'STOP no-record\n' 0

row_start
W="$(new_repo read-fails)"
seed_record "$W" 'met deadbeef'
: | gh_stub_response '*' 1 pr view -R acme/widgets --json headRefOid --jq .headRefOid -- 7
run_in "$W" acme widgets 7
assert_row 'head-read-fails' 0 'STOP pr-read-failed\n' 1

row_start
W="$(new_repo ready-fails)"
seed_record "$W" 'met deadbeef'
stub_head deadbeef
stub_ready 1
run_in "$W" acme widgets 7
assert_row 'ready-call-fails' 0 'STOP ready-failed\n' 2

row_start
W="$(new_repo usage)"
run_in "$W" acme widgets
assert_row 'too-few-args' 2 '' 0

harness_exit "$failed" "$total"
