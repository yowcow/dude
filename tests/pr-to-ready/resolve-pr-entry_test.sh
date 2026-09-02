#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/resolve-pr-entry.sh: the two
# reference forms, the five STOP slugs, and the three rows that are the point
# of the script — a URL is resolved against the repository the URL itself
# names; a checkout that is not that repository stops the run before any
# lookup; and a head branch living in a fork stops it too, which the origin
# comparison cannot see because the reference names the base repository.
#
# git is not stubbed, for the reason ../lib/gitrepo.sh gives: the only git the
# SUT runs is `git remote get-url origin`, and the identity a fixture presents
# is carried by its remote's path (.../acme/widgets.git reduces to
# `acme/widgets`), so a real repository produces both "origin is this PR's
# repository" and "origin is some other repository" with no network.
#
# The gh stub serves a body and then exits with the scripted status, which is
# what lets the GraphQL error rows be written exactly as real gh behaves: on an
# `errors` array gh exits 1 and prints the raw response body on stdout
# (measured against github.com — see the SUT's header). The SUT reads that
# body, so the fixtures below are real response shapes, not post-filter bytes.
#
# Unlike its siblings, this SUT filters with its own `jq` rather than with
# `gh --jq`, so a defect in a filter expression IS visible here.
#
# RED verification (see tests/README.md): with the script absent every row
# fails; with a script that drops the origin comparison, the
# 'url naming another repository' row fails — it answers with a branch instead
# of STOP wrong-checkout.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/resolve-pr-entry.sh}"

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

failed=0
total=0

# Three checkouts, told apart by what their `origin` points at. Nothing is ever
# fetched from these bare repos — the SUT only reads the remote's URL — so they
# stay empty.
WIDGETS="$(git_repo_scratch widgets-work)"
git_repo_init "$WIDGETS" main
git_repo_remote "$WIDGETS" origin "$(git_repo_bare acme widgets)"

ELSEWHERE="$(git_repo_scratch elsewhere-work)"
git_repo_init "$ELSEWHERE" main
git_repo_remote "$ELSEWHERE" origin "$(git_repo_bare other elsewhere)"

NOREMOTE="$(git_repo_scratch noremote-work)"
git_repo_init "$NOREMOTE" main

# stub_graphql <owner> <name> <number> [<exit>]   body on stdin
stub_graphql() {
  gh_stub_response '*' "${4:-0}" api graphql -f "query=${QUERY}" \
    -F "owner=$1" -F "name=$2" -F "number=$3"
}

# pr_body <n> <head> <base> <state> <draft> [<cross-repository>]
pr_body() {
  printf '{"data":{"repository":{"pullRequest":{"number":%s,"headRefName":"%s","baseRefName":"%s","state":"%s","isDraft":%s,"isCrossRepository":%s}}}}\n' \
    "$1" "$2" "$3" "$4" "$5" "${6:-false}"
}

# run_sut_in <dir> <argv...>   -- the SUT reads the *current* repository, so
# which directory it runs in is part of every case's input.
run_sut_in() {
  local dir="$1" prev="$PWD"
  shift
  cd "$dir" || exit 1
  run_sut "$@"
  cd "$prev" || exit 1
}

# assert_row <name> <want-exit> <want-stdout> [<want-gh-calls>]
assert_row() {
  local name="$1" want_exit="$2" want_out="$3" want_calls="${4:-}" fails=0
  total=$((total + 1))
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if ! check_bytes "${name}: stdout" "$want_out"; then fails=1; fi
  if [ -n "$want_calls" ] && ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# --- 1/2. a bare number resolves against the current repository -----------
stub_dir_new
pr_body 12 feature main OPEN true | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'bare number, open draft' 0 'PR 12 branch=feature base=main repo=acme/widgets draft=true\n' 1

stub_dir_new
pr_body 12 feature main OPEN false | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'bare number, open ready' 0 'PR 12 branch=feature base=main repo=acme/widgets draft=false\n' 1

# --- 3/4/5. the three URL spellings are one reference ---------------------
stub_dir_new
pr_body 12 feature main OPEN true | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" https://github.com/acme/widgets/pull/12
assert_row 'url' 0 'PR 12 branch=feature base=main repo=acme/widgets draft=true\n' 1

stub_dir_new
pr_body 12 feature main OPEN true | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" https://github.com/acme/widgets/pull/12/files
assert_row 'url with trailing path' 0 'PR 12 branch=feature base=main repo=acme/widgets draft=true\n' 1

stub_dir_new
pr_body 12 feature main OPEN true | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" github.com/acme/widgets/pull/12
assert_row 'url with no scheme' 0 'PR 12 branch=feature base=main repo=acme/widgets draft=true\n' 1

# --- 6. THE ROW: a URL naming a repository this checkout is not -----------
# The lookup is stubbed and still never runs — `gh calls == 0` is the guard
# firing ahead of it. The stub is what makes the row prove the strong property:
# drop the guard and this row answers `PR 12 branch=feature …`, a perfectly
# valid-looking line that Step 0-3 would then attach a worktree for out of
# `other/elsewhere`'s origin. Without the stub, a guardless script would only
# reach an unstubbed call and answer `STOP pr-lookup-failed`, which proves
# nothing about the guard.
stub_dir_new
pr_body 12 feature main OPEN true | stub_graphql acme widgets 12
run_sut_in "$ELSEWHERE" bash "$SUT" https://github.com/acme/widgets/pull/12
assert_row 'url naming another repository' 0 'STOP wrong-checkout\n' 0

# --- 7. a directory with no origin is not a checkout of anything ----------
stub_dir_new
run_sut_in "$NOREMOTE" bash "$SUT" 12
assert_row 'no origin remote' 0 'STOP wrong-checkout\n' 0

# --- 8. a head branch living in a fork is not on this origin at all -------
# The origin comparison above cannot see this: the reference names the base
# repository, which is exactly the repository this checkout is.
stub_dir_new
pr_body 12 main main OPEN false true | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'cross-fork head' 0 'STOP cross-fork\n' 1

# --- 9/10. a PR that is not open is not something this flow can drive -----
stub_dir_new
pr_body 12 feature main MERGED false | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'merged' 0 'STOP pr-not-open\n' 1

stub_dir_new
pr_body 12 feature main CLOSED false | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'closed' 0 'STOP pr-not-open\n' 1

# --- 11. NOT_FOUND on the pullRequest node -------------------------------
stub_dir_new
printf '%s\n' '{"data":{"repository":{"pullRequest":null}},"errors":[{"type":"NOT_FOUND","path":["repository","pullRequest"],"message":"Could not resolve to a PullRequest with the number of 12."}]}' |
  stub_graphql acme widgets 12 1
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'no such pr' 0 'STOP no-pr\n' 1

# --- 12. NOT_FOUND on the repository node reaches the same answer ---------
# The repository was renamed or deleted since this clone: origin still says
# acme/widgets, so the guard passes and GitHub is the one that says no.
stub_dir_new
printf '%s\n' '{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"message":"Could not resolve to a Repository with the name '"'"'acme/widgets'"'"'."}]}' |
  stub_graphql acme widgets 12 1
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'no such repository' 0 'STOP no-pr\n' 1

# --- 13. any other GraphQL error is "couldn't tell", not "no PR" ----------
stub_dir_new
printf '%s\n' '{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}' |
  stub_graphql acme widgets 12 1
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'rate limited' 0 'STOP pr-lookup-failed\n' 1

# --- 14. a transport failure prints nothing at all -----------------------
stub_dir_new
printf '' | stub_graphql acme widgets 12 1
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'transport failure' 0 'STOP pr-lookup-failed\n' 1

# --- 15. exit 0 with a null node, no errors array ------------------------
stub_dir_new
printf '%s\n' '{"data":{"repository":{"pullRequest":null}}}' | stub_graphql acme widgets 12
run_sut_in "$WIDGETS" bash "$SUT" 12
assert_row 'null node without errors' 0 'STOP no-pr\n' 1

# --- 16/17/18. usage errors are exits, not STOP lines --------------------
stub_dir_new
run_sut_in "$WIDGETS" bash "$SUT"
assert_row 'no argument' 1 '' 0

stub_dir_new
run_sut_in "$WIDGETS" bash "$SUT" 12 extra
assert_row 'two arguments' 1 '' 0

stub_dir_new
run_sut_in "$WIDGETS" bash "$SUT" 'not-a-reference'
assert_row 'unparseable reference' 1 '' 0

harness_exit "$failed" "$total"
