#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/recheck-pr.sh: each row stubs the
# `gh` calls of the five stages in the order the script must make them, and
# asserts the exit status, the exact stdout, and the number of gh calls. The
# rows Step 3's ready depends on then run mark-ready.sh on the record the
# recheck left.
#
# The stages are the real sibling scripts, so their argvs are stubbed here
# byte-for-byte: QUERY and THREADS_JQ are verbatim copies of
# list-unresolved-threads.sh's, SUPPRESSED_JQ of list-suppressed-comments.sh's,
# STATE_JQ of check-pr-state.sh's. An edit to any of them fails these rows as an
# unstubbed argv.
#
# `dude-255-thread-after-settle-poll` is the order regression (yowcow/dude#255:
# a listing read while Copilot's check-run was still in_progress came back
# empty, the PR went ready, and the finding arrived 41 s later). The stub's
# global call index is the clock:
#   1 head read; 2 check-runs, in_progress; 3 settled but carrying a new
#   check-run id; 4 settled and unchanged — the poll watch-checks.sh settles
#   on; 5 onward: after the settle poll.
# The thread listing answers no thread at 1-3 and the thread at 5. A script
# that reads it before the wait, or alongside it, reads at 1-3 and records met
# on a PR about to carry a finding: this row then fails on stdout, and its
# mark-ready row fails because the ready goes on to read the head.
# There is no listing entry at 4, and that gap is load-bearing: --paginate
# makes consecutive exact entries one invocation's pages (tests/README.md), so
# an entry at 4 would let a call at 1-3 page forward into the thread at 5.
# The window between the check-run completing and the finding posting (1 s in
# dude#255) is out of scope: this row pins order, not that window.
#
# The dude#255 row reuses the worktree `clean-records-met` left a met record in
# on the same SHA, so its unmet verdict has to overwrite that record.
#
# The met-conditions each have a row that fails only on them, everything else
# clean: `head-moved-is-unmet`, `not-mergeable-is-unmet`,
# `suppressed-finding-is-unmet` (the listing finds a finding),
# `thread-listing-fails-is-unmet` (the listing exits 1 with empty output, so
# only the status half of its condition catches it),
# `suppressed-listing-fails-is-unmet` (the listing exits 4 on a heading/entry
# count mismatch with empty output, so only the status half of its condition
# catches it), and `watch-unsettled-is-unmet` (watch-checks.sh exits 1 after its 60 polls: 64 gh
# calls). Each is followed by a mark-ready row, so the verdict written is
# pinned and not only the stdout. Deleting the watch condition, the suppressed
# condition, or either listing's status half (leaving `[ -z "$OUT" ]`) fails
# the matching row.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; the broken variant reads the thread listing before the
# watch, and fails `dude-255-thread-after-settle-poll` and its mark-ready row:
#   tmp="$(mktemp -d)"
#   cp skills/pr-to-ready/scripts/{watch-checks,list-unresolved-threads,list-suppressed-comments,check-pr-state}.sh "$tmp/"
#   perl -0pe 's/(stage watch-checks .*\n.*\n)(stage unresolved-threads .*\n.*\n)/$2$1/' \
#     skills/pr-to-ready/scripts/recheck-pr.sh >"$tmp/recheck-pr.sh"
#   SUT="$tmp/recheck-pr.sh" tests/run.sh tests/pr-to-ready/recheck-pr_test.sh
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

stub_sleep_instant

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/recheck-pr.sh}"
READY="${REPO_ROOT}/skills/pr-to-ready/scripts/mark-ready.sh"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"

QUERY='
    query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100, after: $endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              isResolved
              comments(first: 1) {
                nodes {
                  databaseId
                  author { login }
                  path
                  line
                }
              }
            }
          }
        }
      }
    }'
THREADS_JQ='.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | .comments.nodes[0] as $c
        | "\($c.databaseId)\t\($c.author.login)\t\($c.path):\($c.line)"'
SUPPRESSED_JQ='.reviews
        | map(select((.author.login // "") | ascii_downcase | contains("copilot")))
        | sort_by(.submittedAt)
        | last
        | .body // ""'
STATE_JQ='"\(.baseRefName) \(.mergeable)"'

# stub_head <sha> -- every head read answers <sha>.
stub_head() {
  printf '%s\n' "$1" |
    gh_stub_response '*' 0 pr view -R acme/widgets --json headRefOid --jq .headRefOid -- 7
}

# stub_checks <index|*> <fixture> -- watch-checks.sh's poll of deadbeef.
stub_checks() {
  gh_stub_response "$1" 0 api repos/acme/widgets/commits/deadbeef/check-runs \
    <"${FIXTURES}/$2.json"
}

# stub_threads <index> <fixture> -- raw, so the script's own filter runs.
# Exact indices only: a `*` entry on a --paginate argv is served as one more
# page after every exact hit.
stub_threads() {
  gh_stub_raw_response "$1" 0 api graphql --paginate \
    -f owner=acme -f repo=widgets -F pr=7 \
    -f "query=${QUERY}" --jq "$THREADS_JQ" <"${FIXTURES}/$2.json"
}

stub_no_suppressed() {
  : | gh_stub_response '*' 0 pr view --repo acme/widgets --json reviews \
    --jq "$SUPPRESSED_JQ" -- 7
}

# stub_state <base> <mergeable>
stub_state() {
  printf '%s %s\n' "$1" "$2" |
    gh_stub_response '*' 0 pr view -R acme/widgets \
      --json baseRefName,mergeable --jq "$STATE_JQ" -- 7
}

# ready_in <dir> <argv...> -- mark-ready.sh from <dir>, as Step 3 calls it.
ready_in() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "$READY" "$@"
  cd "$REPO_ROOT" || exit 1
}

failed=0
total=0

W="$(git_repo_scratch work)"
git_repo_init "$W" main

# ---- every machine-checkable condition holds -------------------------------

row_start
stub_head deadbeef
stub_checks '*' check-runs-settled
stub_threads 4 threads-all-resolved
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'clean-records-met' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED met deadbeef\n' 6

row_start
stub_head deadbeef
: | gh_stub_response '*' 0 pr ready -R acme/widgets -- 7
ready_in "$W" acme widgets 7
assert_row 'clean-records-met: mark-ready goes ready' 0 'READY 7\n' 2

# ---- dude#255: the thread arrives only after the settle poll ---------------

row_start
stub_head deadbeef
stub_checks 2 check-runs-in-progress
stub_checks '*' check-runs-settled
stub_threads 1 threads-all-resolved
stub_threads 2 threads-all-resolved
stub_threads 3 threads-all-resolved
stub_threads 5 threads-one-unresolved
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'dude-255-thread-after-settle-poll' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n1002\tyowcow\ttests/lib/bin/gh:34\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 7

row_start
ready_in "$W" acme widgets 7
assert_row 'dude-255-thread-after-settle-poll: mark-ready refuses' 0 'STOP conditions-unmet\n' 0

# ---- one condition fails, everything else clean ----------------------------

row_start
stub_head cafef00d
stub_checks '*' check-runs-settled
stub_threads 4 threads-all-resolved
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'head-moved-is-unmet' 0 '== head exit=0\ncafef00d\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 6

row_start
stub_head deadbeef
stub_checks '*' check-runs-settled
stub_threads 4 threads-all-resolved
stub_no_suppressed
stub_state main CONFLICTING
run_in "$W" acme widgets 7 deadbeef main
assert_row 'not-mergeable-is-unmet' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main CONFLICTING\nRECORDED unmet deadbeef\n' 6

row_start
stub_head deadbeef
stub_checks '*' check-runs-settled
stub_threads 4 threads-all-resolved
gh_stub_raw_response '*' 0 pr view --repo acme/widgets --json reviews \
  --jq "$SUPPRESSED_JQ" -- 7 <"${FIXTURES}/reviews-suppressed.json"
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'suppressed-finding-is-unmet' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n== suppressed-comments exit=0\nsuppressed\t1\nREADME.md:179\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 6

row_start
ready_in "$W" acme widgets 7
assert_row 'suppressed-finding-is-unmet: mark-ready refuses' 0 'STOP conditions-unmet\n' 0

row_start
stub_head deadbeef
stub_checks '*' check-runs-settled
: | gh_stub_response 4 1 api graphql --paginate \
  -f owner=acme -f repo=widgets -F pr=7 \
  -f "query=${QUERY}" --jq "$THREADS_JQ"
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'thread-listing-fails-is-unmet' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=1\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 6

row_start
ready_in "$W" acme widgets 7
assert_row 'thread-listing-fails-is-unmet: mark-ready refuses' 0 'STOP conditions-unmet\n' 0

row_start
stub_head deadbeef
stub_checks '*' check-runs-settled
stub_threads 4 threads-all-resolved
gh_stub_raw_response 5 0 pr view --repo acme/widgets --json reviews \
  --jq "$SUPPRESSED_JQ" -- 7 <"${FIXTURES}/reviews-suppressed-count-mismatch.json"
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'suppressed-listing-fails-is-unmet' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=0\nbuild\tcompleted\tsuccess\nlint\tcompleted\tskipped\n== unresolved-threads exit=0\n== suppressed-comments exit=4\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 6

row_start
ready_in "$W" acme widgets 7
assert_row 'suppressed-listing-fails-is-unmet: mark-ready refuses' 0 'STOP conditions-unmet\n' 0

# ---- the checks never settle: watch-checks.sh exit 1 is unmet --------------
#
# Every poll answers in_progress, so the watch spends its whole 60-poll budget
# (the sleep stub is instant) and exits 1: the head read (1), the polls (2-61),
# then the two listings (62, 63) and the state (64). The listings answer clean,
# so the watch is the only condition failing.

row_start
stub_head deadbeef
stub_checks '*' check-runs-in-progress
stub_threads 62 threads-all-resolved
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'watch-unsettled-is-unmet' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=1\nbuild\tin_progress\t-\n== unresolved-threads exit=0\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED unmet deadbeef\n' 64

row_start
ready_in "$W" acme widgets 7
assert_row 'watch-unsettled-is-unmet: mark-ready refuses' 0 'STOP conditions-unmet\n' 0

# ---- a repository that runs no checks: watch-checks.sh exit 5 is met --------
#
# Three empty polls (2-4) reach the grace, then the repository read (5) and the
# default branch's listing (6), as in watch-checks_test.sh's
# `no-checks-here-and-none-on-the-default-branch`, one index later.

row_start
stub_head deadbeef
stub_checks '*' check-runs-empty
gh_stub_response 5 0 api repos/acme/widgets <"${FIXTURES}/repo-default-branch.json"
gh_stub_response 6 0 api repos/acme/widgets/commits/trunk/check-runs <"${FIXTURES}/check-runs-empty.json"
stub_threads 7 threads-all-resolved
stub_no_suppressed
stub_state main MERGEABLE
run_in "$W" acme widgets 7 deadbeef main
assert_row 'no-checks-in-this-repository-is-met' 0 '== head exit=0\ndeadbeef\n== watch-checks exit=5\n== unresolved-threads exit=0\n== suppressed-comments exit=0\n== check-pr-state exit=0\nBASE-OK main MERGEABLE\nRECORDED met deadbeef\n' 9

row_start
run_in "$W" acme widgets 7 deadbeef
assert_row 'too-few-args' 2 '' 0

harness_exit "$failed" "$total"
