#!/usr/bin/env bash
# Table test for skills/pr-to-ready/scripts/watch-claude-review.sh: the
# availability answer (exit 3 and the two ways of not being it), which runs
# survive the listing's filter, how deep that listing reaches, watch mode's
# exit contract, and that both gh calls pin the repository the caller names
# with -R rather than the checkout's origin.
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
# The `skipped` contract is pinned in both modes, because the listing does not
# filter on conclusion — selecting the run is the caller's job (SKILL.md
# step 2-2 wants「a conclusion that isn't skipped」). List mode must KEEP a
# skipped run's `conclusion` field, which is what makes the run discriminable
# at all (`mixed-listing-…`, run 4003); watch mode exits 1 for it, as `gh run
# watch --exit-status` did, pinned by `watch-reports-a-skipped-conclusion`. That
# row reads the conclusion out of the stubbed `gh run view` body the script
# itself parses, so it measures the script's own decision rather than an exit
# status the stub scripted.
#
# RED verification (see tests/README.md). Setting the depth back to the pre-fix
# `--limit 20` is the mutation, because a copy that predates the `-R` pin fails
# every gh-reaching row as an unstubbed argv before the depth is reached:
#   tmp="$(mktemp -d)"
#   mkdir -p "$tmp/skills/pr-to-ready/scripts"
#   sed 's/--limit 100/--limit 20/' \
#     skills/pr-to-ready/scripts/watch-claude-review.sh \
#     >"$tmp/skills/pr-to-ready/scripts/old.sh"
#   SUT="$tmp/skills/pr-to-ready/scripts/old.sh" \
#     tests/run.sh tests/pr-to-ready/watch-claude-review_test.sh
#     -> deep-listing-keeps-the-target-run is answered with the truncated page,
#        so it exits 0 printing [] where the run belongs (#173); the rows that
#        stub only --limit 100 fail as unstubbed argv.
#   The from-a-subdirectory row pins the cwd-relative regression on the current
#   script; a copy that predates that fix also predates `-R`.
#   Against a copy that predates this file's four-argument argv form, the rows
#   fail on the contract rather than on a symptom: the argument count is a usage
#   error (exit 2), and a copy that still watched with `gh run watch` hits an
#   unstubbed argv instead (exit 99). Neither is the defect the rows exist to
#   catch.
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

# watch mode は上限付きポーリングなので、回数は固定し時計は測らない。
# sleep はこのファイル全体で即時化する（tests/README.md, stub_sleep_instant）。
stub_sleep_instant

BRANCH=188-watch-claude-review-tests
# The repository the caller names. Deliberately not what any fixture's origin
# resolves to (acme/claude-ok): a script that read origin instead of its
# arguments would pass `-R acme/claude-ok`, an argv no row stubs.
OWNER=upstream-org
REPO_NAME=base-repo
NWO="${OWNER}/${REPO_NAME}"
# A second name, for the same reason as $DEFAULT_BRANCH and $WORKFLOW_FILE: with
# only one pair, hardcoding it would pass every row.
OWNER_2=other-org
REPO_NAME_2=other-repo
NWO_2="${OWNER_2}/${REPO_NAME_2}"
# Deliberately not `master` or `main`: the script filters on the default branch
# it is given as an argument, and a regression that hardcoded the usual literal
# instead would produce byte-identical output on every row here if the fixtures
# used that same literal. A name nobody would hardcode is what makes the value
# the caller passes observable.
DEFAULT_BRANCH=trunk
RUN_ID=4242
TARGET_RUN_ID=5999
# Same argument for the workflow's filename: the script derives it with
# `basename` from whatever file carries @claude and passes it to `gh run list`.
# A name no one would write as a literal is what pins that plumbing — with
# `claude.yml` on both sides, a hardcoded `--workflow=claude.yml` would match.
WORKFLOW_FILE=ai-review.yml

CLAUDE_WORKFLOW='name: claude\non: issue_comment\njobs:\n  review:\n    if: contains(github.event.comment.body, "@claude")\n'

MIXED="${FIXTURES}/claude-runs-mixed.json"
DEEP="${FIXTURES}/claude-runs-deep.json"
LISTING_FIELDS=databaseId,conclusion,createdAt,displayTitle,headBranch

# gh run view --json status,conclusion の答え。1 object ずつなので fixture
# ファイルにはせず、ここで書く。
VIEW_QUEUED="${HARNESS_TMP}/run-queued.json"
VIEW_WAITING="${HARNESS_TMP}/run-waiting.json"
VIEW_COMPLETED_OK="${HARNESS_TMP}/run-completed-ok.json"
VIEW_COMPLETED_FAILED="${HARNESS_TMP}/run-completed-failed.json"
VIEW_COMPLETED_SKIPPED="${HARNESS_TMP}/run-completed-skipped.json"
VIEW_COMPLETED_BARE="${HARNESS_TMP}/run-completed-bare.json"
VIEW_TWO_DOCUMENTS="${HARNESS_TMP}/run-two-documents.json"
VIEW_UNPARSEABLE="${HARNESS_TMP}/run-unparseable.json"
printf '{"conclusion":"","status":"queued"}\n' >"$VIEW_QUEUED"
printf '{"conclusion":"","status":"waiting"}\n' >"$VIEW_WAITING"
printf '{"conclusion":"success","status":"completed"}\n' >"$VIEW_COMPLETED_OK"
printf '{"conclusion":"failure","status":"completed"}\n' >"$VIEW_COMPLETED_FAILED"
printf '{"conclusion":"skipped","status":"completed"}\n' >"$VIEW_COMPLETED_SKIPPED"
printf '{"conclusion":"","status":"completed"}\n' >"$VIEW_COMPLETED_BARE"
printf '{"conclusion":"success","status":"completed"}\n{}\n' >"$VIEW_TWO_DOCUMENTS"
printf 'not json\n' >"$VIEW_UNPARSEABLE"

failed=0
total=0

# stub_listing <repo> <body-file> [<limit>] [<exit-status>] -- one `gh run list` page.
#
# The repository is a parameter because `-R` is part of what is under test: a
# call without it is an argv no row stubbed, which the stub reports as a
# violation instead of letting gh answer about whatever repository it likes.
stub_listing() {
  local repo="$1" body="$2" limit="${3:-100}" status="${4:-0}"
  gh_stub_response '*' "$status" run list -R "$repo" \
    "--workflow=${WORKFLOW_FILE}" --limit "$limit" --json "$LISTING_FIELDS" <"$body"
}

# stub_view <repo> <index|*> <exit-status> <body-file> -- watch mode の 1 ポーリング。
# body は gh の stdout そのもの（script 側の jq が読む。script は --jq を渡さない）。
stub_view() {
  local repo="$1" idx="$2" status="$3" body="$4"
  gh_stub_response "$idx" "$status" run view -R "$repo" "$RUN_ID" \
    --json status,conclusion <"$body"
}

# repo_with_workflow <name> <kind> -- a real repository whose root holds the
# workflow shape a row wants; prints its path. The `claude` kind also gets an
# origin, which no row's `-R` value may come from.
#   claude   -- .github/workflows/$WORKFLOW_FILE mentioning @claude
#   noclaude -- .github/workflows/ci.yml with no @claude anywhere
#   nodir    -- no .github/ at all
repo_with_workflow() {
  local name="$1" kind="$2" dir bare
  dir="$(git_repo_scratch "$name")"
  git_repo_init "$dir" "$DEFAULT_BRANCH"
  case "$kind" in
    claude)
      git_repo_commit "$dir" ".github/workflows/${WORKFLOW_FILE}" \
        "$CLAUDE_WORKFLOW" \
        'add claude workflow'
      bare="$(git_repo_bare acme "$name")"
      git_repo_push "$dir" "$bare" "$DEFAULT_BRANCH"
      git_repo_remote "$dir" origin "$bare"
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

# assert_row <name> <want-exit> <want-stdout-file|-> <want-gh-calls>
#
# stdout is compared byte-for-byte against a file rather than through
# check_bytes: this script prints a multi-line pretty JSON array, and the same
# expectation written as a printf '%b' string would be one unreadable line. `-`
# means stdout must be empty.
#
# The fourth argument is required, deliberately not defaulted — same reasoning
# as harness.sh's assert_row.
assert_row() {
  local name="$1" want_exit="$2" want_file="$3" want_calls="$4" fails=0
  if ! check_eq "${name}: exit" "$want_exit" "$SUT_STATUS"; then fails=1; fi
  if [ "$want_file" = '-' ]; then
    if ! check_bytes "${name}: stdout" ''; then fails=1; fi
  elif ! cmp -s "$want_file" "$SUT_STDOUT"; then
    printf 'FAIL %s: stdout differs from %s\n' "$name" "$want_file"
    diff -u "$want_file" "$SUT_STDOUT" | head -40 || true
    fails=1
  fi
  if ! check_eq "${name}: gh calls" "$want_calls" "$(gh_call_count)"; then fails=1; fi
  if ! check_no_violations "${name}: argv"; then fails=1; fi
  if [ "$fails" -ne 0 ]; then
    failed=$((failed + 1))
    printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fi
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

row_start
run_in "$REPO_CLAUDE"
assert_row 'usage-no-args' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID" extra
assert_row 'usage-five-args' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" "$BRANCH"
assert_row 'usage-one-arg' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH"
assert_row 'usage-three-args' 2 '-' 0

# 空の既定ブランチは headBranch == "" のフィルタになり、既定ブランチ側の run を
# 静かに落とす。usage エラーとして断る。
row_start
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" ''
assert_row 'usage-empty-last-argument' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" '' "$DEFAULT_BRANCH"
assert_row 'usage-empty-branch' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" '' "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'usage-empty-owner' 2 '-' 0

row_start
run_in "$REPO_CLAUDE" "$OWNER" '' "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'usage-empty-repo' 2 '-' 0

row_start
run_in "$REPO_NOCLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'no-claude-workflow' 3 '-' 0

row_start
run_in "$REPO_NODIR" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'no-workflows-dir' 3 '-' 0

# 128, not 3: a cwd outside a repository is「stop and inspect」, never the
# availability answer, or a caller run from the wrong directory would silently
# skip the review. 128 is what `git rev-parse --show-toplevel` exits with there,
# and `set -e` on the assignment propagates it unchanged.
row_start
run_in "$REPO_OUTSIDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'outside-a-repository' 128 '-' 0

# ---- 既定ブランチは呼び手が解決する ---------------------------------------
#
# tools/resolve-default-branch.sh は毎回 `git ls-remote --symref` を打ち、実測
# 2.15–2.17 秒。listing はポーリングの各回に乗るので、解決は呼び手が 1 回だけ
# 行い、ここには値が来る。この copy の解決は必ず失敗するので、listing が解決を
# 始めたら exit 1 になる。
SHADOW="${HARNESS_TMP}/shadow"
rm -rf -- "$SHADOW"
mkdir -p -- "${SHADOW}/skills/pr-to-ready/scripts" "${SHADOW}/tools"
cp -- "$SUT" "${SHADOW}/skills/pr-to-ready/scripts/watch-claude-review.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"${SHADOW}/tools/resolve-default-branch.sh"

# run_shadow <work-dir> <argv...> -- run_in, この copy 用。
run_shadow() {
  local dir="$1"
  shift
  cd "$dir" || exit 1
  run_sut bash "${SHADOW}/skills/pr-to-ready/scripts/watch-claude-review.sh" "$@"
  cd "$REPO_ROOT" || exit 1
}

row_start
stub_listing "$NWO" "$MIXED"
run_shadow "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'listing-does-not-resolve-the-default-branch' 0 \
  "${FIXTURES}/claude-runs-mixed.expected" 1

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

row_start
stub_listing "$NWO" "$MIXED"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'mixed-listing-keeps-branch-and-default' 0 "${FIXTURES}/claude-runs-mixed.expected" 1

# The `-R` value comes from the caller's <owner> <repo>, not from a literal and
# not from origin (acme/claude-ok here): the same listing asked of a differently
# named repository must be pinned to that name.
row_start
stub_listing "$NWO_2" "$MIXED"
run_in "$REPO_CLAUDE" "$OWNER_2" "$REPO_NAME_2" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'listing-pins-a-second-repository' 0 "${FIXTURES}/claude-runs-mixed.expected" 1

# Same expectation from a subdirectory: the workflow search is anchored at the
# repository root, so where the caller stands cannot change the answer.
row_start
stub_listing "$NWO" "$MIXED"
run_in "$SUBDIR" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'from-a-subdirectory' 0 "${FIXTURES}/claude-runs-mixed.expected" 1

# The listing call fails with an empty body; `set -o pipefail` carries gh's
# status out through the jq pipeline, so nothing is printed and the status is
# neither 0 nor the availability answer.
row_start
stub_listing "$NWO" /dev/null 100 1
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'listing-call-fails' 1 '-' 1

# The depth of the listing, i.e. #173. Two listing stubs, one per depth: the
# depth this script asks for (100) is answered with the whole 21-run page, and
# the depth the pre-fix script asked for (20) with that page truncated — which
# is what the API itself would have done. The second stub is the mechanism of
# the RED, not dead weight: against 2bd1745^ with a copy of this file whose
# stubs also predate `-R`, the target run has fallen out of the answer, the
# filter prints [], and the row fails on the real symptom rather than on an
# unstubbed argv.
row_start
stub_listing "$NWO" "$DEEP" 100
TRUNCATED="$(truncate_listing "$DEEP" 20)"
stub_listing "$NWO" "$TRUNCATED" 20
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$DEFAULT_BRANCH"
assert_row 'deep-listing-keeps-the-target-run' 0 "${FIXTURES}/claude-runs-deep.expected" 1

# ---- watch mode ----------------------------------------------------------
#
# Watch mode's stdout is empty: the caller reads only the exit status. The
# script polls `gh run view --json status,conclusion` itself, so these rows stub
# the JSON body it parses rather than a status the stub scripted.

row_start
stub_view "$NWO" '*' 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-completes-successfully' 0 '-' 1

row_start
stub_view "$NWO_2" '*' 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER_2" "$REPO_NAME_2" "$BRANCH" "$RUN_ID"
assert_row 'watch-pins-a-second-repository' 0 '-' 1

row_start
stub_view "$NWO" '*' 0 "$VIEW_COMPLETED_FAILED"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-reports-a-failed-conclusion' 1 '-' 1
tally check_eq 'watch-reports-a-failed-conclusion: names the conclusion' \
  "claude review run ${RUN_ID} concluded 'failure'" "$(cat "$SUT_STDERR")"

# skipped は workflow の if: が弾いた run で、レビューは走っていない。成功として
# 返すと「走っていないレビュー」を「完了して中身なし」と読ませる。gh run watch
# --exit-status は実測で 1 を返した（gh 2.103.0）。
row_start
stub_view "$NWO" '*' 0 "$VIEW_COMPLETED_SKIPPED"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-reports-a-skipped-conclusion' 1 '-' 1
tally check_eq 'watch-reports-a-skipped-conclusion: names the conclusion' \
  "claude review run ${RUN_ID} concluded 'skipped'" "$(cat "$SUT_STDERR")"

# まだ完了していない status の conclusion は空。そこで打ち切ると、承認待ちの
# run を「完了して中身なし」と読む。
row_start
stub_view "$NWO" 1 0 "$VIEW_WAITING"
stub_view "$NWO" 2 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-waits-through-a-non-completed-status' 0 '-' 2
tally check_eq 'watch-waits-through-a-non-completed-status: sleeps' 1 "$(sleep_call_count)"

# 判定は最後のポーリングの conclusion。1 回目の waiting を verdict にしない。
row_start
stub_view "$NWO" 1 0 "$VIEW_WAITING"
stub_view "$NWO" 2 0 "$VIEW_COMPLETED_FAILED"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-reports-the-last-polls-conclusion' 1 '-' 2

# 読めない本文は「まだ」であって「完了」ではない。2 文書の本文は length == 1 の
# ガードが、jq が読めない本文は `|| run_status=""` が受ける。
row_start
stub_view "$NWO" 1 0 "$VIEW_TWO_DOCUMENTS"
stub_view "$NWO" 2 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-ignores-a-two-document-body' 0 '-' 2

row_start
stub_view "$NWO" 1 0 "$VIEW_UNPARSEABLE"
stub_view "$NWO" 2 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-ignores-an-unparseable-body' 0 '-' 2

# completed で conclusion が空なら成功ではない。
row_start
stub_view "$NWO" '*' 0 "$VIEW_COMPLETED_BARE"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-completed-without-a-conclusion' 1 '-' 1
tally check_eq 'watch-completed-without-a-conclusion: names it' \
  "claude review run ${RUN_ID} concluded ''" "$(cat "$SUT_STDERR")"

# 上限: 回数を固定する。39 個の隙間は stub_sleep_instant で無料。待ちが上限を
# 持たないことこそが、これが置き換える欠陥。
row_start
stub_view "$NWO" '*' 0 "$VIEW_QUEUED"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-stops-at-the-iteration-cap' 1 '-' 40
tally check_eq 'watch-stops-at-the-iteration-cap: sleeps' 39 "$(sleep_call_count)"
tally check_eq 'watch-stops-at-the-iteration-cap: names the cap' \
  "claude review run ${RUN_ID} did not complete within 40 polls at 30s" \
  "$(cat "$SUT_STDERR")"
tally check_eq 'watch-stops-at-the-iteration-cap: interval' 30 "$(sort -u "$GH_STUB_DIR/sleeps")"

# 上限ちょうどのポーリングで完了しても、その conclusion で exit する。
row_start
stub_view "$NWO" '*' 0 "$VIEW_QUEUED"
stub_view "$NWO" 40 0 "$VIEW_COMPLETED_OK"
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-reads-the-last-polls-conclusion' 0 '-' 40

# 失敗した gh 呼び出しはリトライせず gh の status で即 exit する
# （tools/poll.sh 経由だと上限までリトライしてしまう）。
row_start
stub_view "$NWO" '*' 4 /dev/null
run_in "$REPO_CLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-view-call-fails-at-once' 4 '-' 1
tally check_eq 'watch-view-call-fails-at-once: sleeps' 0 "$(sleep_call_count)"

# Availability is checked before the run-id branch is taken, so watch mode
# cannot be reached in a repository with no @claude workflow.
row_start
run_in "$REPO_NOCLAUDE" "$OWNER" "$REPO_NAME" "$BRANCH" "$RUN_ID"
assert_row 'watch-without-claude-workflow' 3 '-' 0

# The fourth argument is required: an empty one must fail the row's gh-call
# assertion, not skip it. Probed in its own process because a row cannot observe
# its own failure count: the delta is 0 when the assertion is skipped and 1 when
# it is compared and fails. This local copy carried `[ -n "$want_calls" ]` and
# passed every row silently until it was removed; harness.sh's assert_row was
# required from the start.
total=$((total + 1))
SUT_STATUS=3
: >"$SUT_STDOUT"
probe_status=0
probe_out="$( ( before="$failed"; assert_row 'empty-calls-argument' 3 - ''; printf 'delta=%s\n' "$((failed - before))" ) 2>&1 )" || probe_status=$?
probe_fails=0
if ! check_eq 'required fourth argument: exit' 0 "$probe_status"; then probe_fails=1; fi
case "$probe_out" in
  *delta=1*) ;;
  *)
    printf 'FAIL required fourth argument: %s\n' "$probe_out"
    probe_fails=1
    ;;
esac
if [ "$probe_fails" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
