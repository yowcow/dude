#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/watch-claude-review.sh: the
# availability answer (exit 3 and the two ways of not being it), which runs
# survive the listing's filter, how deep that listing reaches, and watch mode's
# exit contract.
#
# git is NOT stubbed. The script resolves `git rev-parse --show-toplevel` and
# searches `$root/.github/workflows/`, so the repository *is* an input: each row
# runs with its cwd inside a throwaway real repository built by gitrepo.sh. That
# also makes the cwd an input in its own right — the `from-a-subdirectory` row
# exists because a cwd-relative search reported Claude as unavailable from any
# subdirectory (fixed in e14114a).
#
# Every fixture repository carries exactly ONE workflow mentioning @claude. The
# script picks with `grep -rl ... | head -1`, whose choice among several matches
# depends on directory order; that non-determinism is #168 item 7 and out of
# scope here (#188 「含めない」), so no row is allowed to depend on which of two
# files wins.
#
# Unlike the sibling test files, the jq expression under test here really runs:
# this script pipes `gh` stdout into its own `jq`, rather than handing `gh` a
# `--jq` filter the fake `gh` would never execute. So the fixtures are raw `gh
# run list --json` pages, and stdout is what jq made of them — which is why the
# expectations are whole-file byte comparisons against `fixtures/*.expected`.
#
# The `skipped` contract is pinned from both sides, because the script itself
# does not filter on conclusion — selecting the run is the caller's job
# (SKILL.md step 2-2 wants「a conclusion that isn't skipped」):
#   - list mode must KEEP a skipped run's `conclusion` field, which is what
#     makes the run discriminable at all (`mixed-listing-…`, run 4003);
#   - watch mode EXITS 0 on such a run, so a caller that failed to exclude it
#     would read an unrun review as a completed one
#     (`watch-a-skipped-run-still-exits-zero`).
#
# RED verification (see tests/README.md):
#   tmp="$(mktemp -d)"
#   git show 2bd1745^:skills/pr-to-ready/scripts/watch-claude-review.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/pr-to-ready/watch-claude-review_test.sh
#     -> deep-listing-keeps-the-target-run fails: --limit 20 is answered with a
#        page the target run has fallen out of, and the filter prints [] (#173).
#        Three more listing rows fail there as collateral — they stub only
#        --limit 100, so the pre-fix depth reaches them as an unstubbed argv.
#        Only the deep row fails on the symptom itself, which is the one to
#        read: exit 0, empty stderr, [] where the run belongs.
#   git show e14114a^:skills/pr-to-ready/scripts/watch-claude-review.sh >"$tmp/old.sh"
#     -> from-a-subdirectory fails with exit 3: the search was cwd-relative.
set -euo pipefail

# harness.sh is linted on its own, so following it from here buys nothing. The
# disable keeps a bare `shellcheck <file>` clean.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/pr-to-ready/scripts/watch-claude-review.sh}"
FIXTURES="$(dirname -- "${BASH_SOURCE[0]}")/fixtures"

# The script pipes `gh` output through jq itself, so a missing jq would fail
# every list-mode row for a reason that has nothing to do with the script.
# Asserted here for the same reason harness.sh asserts its own PATH.
if ! command -v jq >/dev/null 2>&1; then
  echo "watch-claude-review_test: jq is required by the script under test" >&2
  exit 1
fi

BRANCH=188-watch-claude-review-tests
# Deliberately not `master` or `main`: the script filters on the default branch
# it read from `gh repo view`, and a regression that dropped that read and
# hardcoded the usual literal instead would produce byte-identical output on
# every row here if the fixtures used that same literal. A name nobody would
# hardcode is what makes the dynamic read observable.
DEFAULT_BRANCH=trunk
RUN_ID=4242
TARGET_RUN_ID=5999
# Same argument for the workflow's filename: the script derives it with
# `basename` from whatever file carries @claude and passes it to `gh run list`.
# A name no one would write as a literal is what pins that plumbing — with
# `claude.yml` on both sides, a hardcoded `--workflow=claude.yml` would match.
WORKFLOW_FILE=ai-review.yml

MIXED="${FIXTURES}/claude-runs-mixed.json"
DEEP="${FIXTURES}/claude-runs-deep.json"
LISTING_FIELDS=databaseId,status,conclusion,event,createdAt,displayTitle,headBranch,headSha

failed=0
total=0

# stub_default_branch [<exit-status>] -- the opening `gh repo view`
stub_default_branch() {
  printf '%s\n' "$DEFAULT_BRANCH" |
    gh_stub_response '*' "${1:-0}" repo view --json defaultBranchRef -q .defaultBranchRef.name
}

# stub_listing <body-file> [<limit>] [<exit-status>] -- one `gh run list` page.
#
# The limit is a parameter because a row may need to answer more than one depth:
# the fake `gh` matches on the exact argv before the call index, so `--limit 100`
# and `--limit 20` are two independently answerable calls. That is what lets the
# deep row below behave like a server that honours --limit.
stub_listing() {
  local body="$1" limit="${2:-100}" status="${3:-0}"
  gh_stub_response '*' "$status" run list "--workflow=${WORKFLOW_FILE}" \
    --limit "$limit" --json "$LISTING_FIELDS" <"$body"
}

# stub_watch <exit-status> <body-file> -- the single call watch mode makes
stub_watch() {
  gh_stub_response '*' "$1" run watch "$RUN_ID" --exit-status <"$2"
}

# repo_with_workflow <name> <kind> -- a real repository whose root holds the
# workflow shape a row wants; prints its path.
#   claude   -- .github/workflows/$WORKFLOW_FILE mentioning @claude
#   noclaude -- .github/workflows/ci.yml with no @claude anywhere
#   nodir    -- no .github/ at all
repo_with_workflow() {
  local name="$1" kind="$2" dir
  dir="$(git_repo_scratch "$name")"
  git_repo_init "$dir" "$DEFAULT_BRANCH"
  case "$kind" in
    claude)
      git_repo_commit "$dir" ".github/workflows/${WORKFLOW_FILE}" \
        'name: claude\non: issue_comment\njobs:\n  review:\n    if: contains(github.event.comment.body, "@claude")\n' \
        'add claude workflow'
      ;;
    noclaude)
      git_repo_commit "$dir" .github/workflows/ci.yml \
        'name: ci\non: push\njobs:\n  lint:\n    runs-on: ubuntu-latest\n' \
        'add ci workflow'
      ;;
    nodir)
      git_repo_commit "$dir" README.md 'nothing here\n' 'init'
      ;;
    *)
      echo "repo_with_workflow: unknown kind '${kind}'" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$dir"
}

# truncate_listing <body-file> <n> -- the page's <n> newest entries, written
# under $HARNESS_TMP; prints the path. This emulates what the API does for
# `--limit <n>`: it truncates before the script's jq filter ever sees the page.
#
# Derived from the fixture rather than committed as a second file, so the two
# cannot drift apart, and asserted rather than assumed: a truncation that still
# carried the target run would leave the deep row green against the pre-fix
# script — that is, with the detection power it exists for gone.
truncate_listing() {
  local body="$1" n="$2" out len
  out="$(mktemp "${HARNESS_TMP}/truncated.XXXXXX")"
  jq ".[0:${n}]" "$body" >"$out"
  len="$(jq 'length' "$out")"
  if [ "$len" != "$n" ]; then
    echo "truncate_listing: expected ${n} entries, got ${len}" >&2
    exit 1
  fi
  if [ "$(count_run "$out")" != 0 ]; then
    echo "truncate_listing: the target run survived truncation to ${n}" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# count_run <page-file> -- how many entries carry TARGET_RUN_ID
count_run() {
  jq --argjson id "$TARGET_RUN_ID" 'map(select(.databaseId == $id)) | length' "$1"
}

# assert_row <name> <want-exit> <want-stdout-file|-> [<want-gh-calls>]
#
# stdout is compared byte-for-byte against a file rather than through
# check_bytes: this script prints a multi-line pretty JSON array, and the same
# expectation written as a printf '%b' string would be one unreadable line. `-`
# means stdout must be empty.
assert_row() {
  local name="$1" want_exit="$2" want_file="$3" want_calls="${4:-}" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if [ "$want_file" = '-' ]; then
    if ! check_bytes "${name}: stdout" ''; then fails=1; fi
  elif ! cmp -s "$want_file" "$SUT_STDOUT"; then
    printf 'FAIL %s: stdout differs from %s\n' "$name" "$want_file"
    diff -u "$want_file" "$SUT_STDOUT" | head -40 || true
    fails=1
  fi
  if [ -n "$want_calls" ] && ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
}

# run_in <dir> <argv...> -- run the script under test with <dir> as cwd, then
# restore it. A cd that fails would run the row against the wrong repository, so
# it stops the file instead.
run_in() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "$SUT" "$@"
  cd "$REPO_ROOT" || exit 1
}

# The deep fixture has to carry the target run for the deep row to mean
# anything; a fixture that lost it would make the row pass for the wrong reason.
if [ "$(count_run "$DEEP")" != 1 ]; then
  echo "watch-claude-review_test: ${DEEP} does not carry run ${TARGET_RUN_ID}" >&2
  exit 1
fi

# Built once and shared: none of the rows writes to them.
REPO_CLAUDE="$(repo_with_workflow claude-ok claude)"
REPO_NOCLAUDE="$(repo_with_workflow claude-absent noclaude)"
REPO_NODIR="$(repo_with_workflow no-github nodir)"
REPO_OUTSIDE="$(git_repo_scratch outside)"
# Asserted, not assumed: everything above lives under `mktemp -d`, which honours
# TMPDIR, so a TMPDIR nested inside some repository would make this directory
# part of *that* repository. The row below would then measure git succeeding
# somewhere unrelated instead of the script's behaviour outside a repository —
# the same "passes for the wrong reason" hazard the DEEP check above guards.
if git -C "$REPO_OUTSIDE" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "watch-claude-review_test: ${REPO_OUTSIDE} is inside a git repository (TMPDIR?)" >&2
  exit 1
fi

SUBDIR="${REPO_CLAUDE}/deeply/nested"
mkdir -p "$SUBDIR"

# ---- the guard: rejected before a single API call -------------------------
#
# Each of these rows asserts zero `gh` calls *and* no stub violation, which
# together are what say the answer came from the guard rather than from an
# unstubbed call the harness let through.

total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_CLAUDE"
assert_row 'usage-no-args' 2 '-' 0

total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_CLAUDE" "$BRANCH" "$RUN_ID" extra
assert_row 'usage-three-args' 2 '-' 0

total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_NOCLAUDE" "$BRANCH"
assert_row 'no-claude-workflow' 3 '-' 0

total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_NODIR" "$BRANCH"
assert_row 'no-workflows-dir' 3 '-' 0

# 128, not 3: a cwd outside a repository is「stop and inspect」, never the
# availability answer, or a caller run from the wrong directory would silently
# skip the review. 128 is what `git rev-parse --show-toplevel` exits with there,
# and `set -e` on the assignment propagates it unchanged.
total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_OUTSIDE" "$BRANCH"
assert_row 'outside-a-repository' 128 '-' 0

# ---- list mode -----------------------------------------------------------
#
# The mixed page holds five runs: one on the branch, three on the default
# branch, one on an unrelated branch. Four survive — both attribution shapes the
# script's header describes are kept, and only the foreign branch is dropped.
#
# Run 4003 is the skipped one, and it survives *carrying* conclusion:"skipped".
# That is the contract: the script does not filter, so the field the caller
# discriminates on has to reach it. Run 4002 (in_progress, conclusion null) is
# there for the same reason — an unfinished run is not hidden from the caller.

total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$REPO_CLAUDE" "$BRANCH"
assert_row 'mixed-listing-keeps-branch-and-default' 0 "${FIXTURES}/claude-runs-mixed.expected" 2

# Same expectation from a subdirectory: the workflow search is anchored at the
# repository root, so where the caller stands cannot change the answer.
total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$MIXED"
run_in "$SUBDIR" "$BRANCH"
assert_row 'from-a-subdirectory' 0 "${FIXTURES}/claude-runs-mixed.expected" 2

total=$((total + 1))
stub_dir_new
stub_default_branch 1
run_in "$REPO_CLAUDE" "$BRANCH"
assert_row 'default-branch-read-fails' 1 '-' 1

# The listing call fails with an empty body; `set -o pipefail` carries gh's
# status out through the jq pipeline, so nothing is printed and the status is
# neither 0 nor the availability answer.
total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing /dev/null 100 1
run_in "$REPO_CLAUDE" "$BRANCH"
assert_row 'listing-call-fails' 1 '-' 2

# The depth of the listing, i.e. #173. Two listing stubs, one per depth: the
# depth this script asks for (100) is answered with the whole 21-run page, and
# the depth the pre-fix script asked for (20) with that page truncated — which
# is what the API itself would have done. The second stub is the mechanism of
# the RED, not dead weight: against 2bd1745^ the target run has fallen out of
# the answer, the filter prints [], and the row fails on the real symptom
# rather than on an unstubbed argv.
total=$((total + 1))
stub_dir_new
stub_default_branch
stub_listing "$DEEP" 100
TRUNCATED="$(truncate_listing "$DEEP" 20)"
stub_listing "$TRUNCATED" 20
run_in "$REPO_CLAUDE" "$BRANCH"
assert_row 'deep-listing-keeps-the-target-run' 0 "${FIXTURES}/claude-runs-deep.expected" 2

# ---- watch mode ----------------------------------------------------------
#
# One call, and the script's status is that call's status. The body is asserted
# too: `gh run watch` writes the progress report a person reads, and the script
# passes it through rather than swallowing or reformatting it.

WATCH_OK="${HARNESS_TMP}/watch-ok"
WATCH_FAIL="${HARNESS_TMP}/watch-fail"
WATCH_SKIPPED="${HARNESS_TMP}/watch-skipped"
printf 'claude review run succeeded\n' >"$WATCH_OK"
printf 'claude review run failed\n' >"$WATCH_FAIL"
printf 'claude review run skipped\n' >"$WATCH_SKIPPED"

total=$((total + 1))
stub_dir_new
stub_watch 0 "$WATCH_OK"
run_in "$REPO_CLAUDE" "$BRANCH" "$RUN_ID"
assert_row 'watch-succeeds' 0 "$WATCH_OK" 1

total=$((total + 1))
stub_dir_new
stub_watch 1 "$WATCH_FAIL"
run_in "$REPO_CLAUDE" "$BRANCH" "$RUN_ID"
assert_row 'watch-fails' 1 "$WATCH_FAIL" 1

# `gh run watch --exit-status` reports a *skipped* run as a success, so watch
# mode cannot tell「the review ran and had nothing to say」from「the workflow's
# own if: rejected the comment」. Exit 0 here is therefore not evidence that a
# review happened; that discrimination exists only in list mode, on the
# conclusion field the mixed row pins. The row is here so the asymmetry stays
# visible instead of being rediscovered as a bug in the caller.
#
# What this row does NOT do is prove that claim about `gh`: with `gh` stubbed,
# the exit status is the one the row scripted, so the row *encodes* gh's
# behaviour rather than measuring it. That is class 4 of the plan's 「承知した
# 限界」 — a fixture freezes the API's shape, so a change on GitHub's side
# leaves the suite green and only reality broken. Keying the stub to the mixed
# fixture's skipped run id would not change that: the fake `gh` matches literal
# argv and never reads the listing fixture, so the two would share a number and
# nothing else. Re-measure this one against real `gh` by hand, not here.
total=$((total + 1))
stub_dir_new
stub_watch 0 "$WATCH_SKIPPED"
run_in "$REPO_CLAUDE" "$BRANCH" "$RUN_ID"
assert_row 'watch-a-skipped-run-still-exits-zero' 0 "$WATCH_SKIPPED" 1

# Availability is checked before the run-id branch is taken, so watch mode
# cannot be reached in a repository with no @claude workflow.
total=$((total + 1))
stub_dir_new
stub_watch 0 "$WATCH_OK"
run_in "$REPO_NOCLAUDE" "$BRANCH" "$RUN_ID"
assert_row 'watch-without-claude-workflow' 3 '-' 0

harness_exit "$failed" "$total"
