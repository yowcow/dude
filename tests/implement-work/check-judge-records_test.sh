#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/check-judge-records.sh: the one
# line it answers for each state of the judge input/verdict records.
#
# git is not stubbed, and neither is any recorder: every fixture commits with
# real git and writes real record files, so Commit/Tree identity lines are
# genuine (`git rev-parse HEAD` / `HEAD^{tree}` at fixture time) except where
# the row pins a doctored value. Each row builds a real throwaway repository
# under $HARNESS_TMP.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; each deliberately broken variant below is one defect wide,
# and the rows it must fail are named:
#   - drop the identical-identity DOUBLE check: `same-identity-two-rounds`
#   - drop the header-equality condition in the identical-identity DOUBLE
#     check (old over-broad behavior): `same-identity-different-findings`
#     (answers DOUBLE instead of GAP)
#   - drop the verdict-Input-name check: `verdict-names-wrong-input`
#   - drop the verdict-for-empty-input DOUBLE check: `verdict-for-empty-input`
#   - compare Tree to HEAD^{tree} instead of <commit>^{tree}:
#     `clean-accept-apply-fixed`
#   - use --no-merges without --first-parent: `merge-only-after-judgment`
#   - drop the stateful GAP parse, keep header-set difference only:
#     `accept-without-value`, `declined-candidate-not-reoffered`
#   - drop the candidate re-offer check: `declined-candidate-not-reoffered`,
#     `finding-needs-user-not-reoffered`
#   - drop the DIRTY check: `dirty-tree`, `untracked-file`,
#     `untracked-file-hidden-by-config`
#   - probe with `git status --porcelain` (no --untracked-files=normal):
#     `untracked-file-hidden-by-config`
#   - store under `git rev-parse --git-common-dir` instead of the worktree's
#     own git dir: `records-are-per-worktree`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/check-judge-records.sh}"

failed=0
total=0

# build_repo <name> -- a repository on branch `main` with one committed file,
# `tracked.txt`, and a clean working tree. Prints its path.
build_repo() {
  local w
  w="$(git_repo_scratch "$1")"
  git_repo_init "$w" main
  git_repo_commit "$w" tracked.txt 'committed\n' 'c1'
  printf '%s\n' "$w"
}

# recdir <work-dir> -- the record directory the script reads. Prints its path.
recdir() {
  local d
  d="$(git -C "$1" rev-parse --absolute-git-dir)/dude-measurements/implement-work"
  mkdir -p "$d"
  printf '%s\n' "$d"
}

# head_sha <work-dir> / head_tree <work-dir>
head_sha() {
  git -C "$1" rev-parse HEAD
}
head_tree() {
  git -C "$1" rev-parse 'HEAD^{tree}'
}

# write_input <dir> <round> <commit> <tree> -- envelope plus the headers on
# stdin. An empty stdin is an empty input: nothing to cover, never missing.
write_input() {
  local dir="$1" round="$2" commit="$3" tree="$4" f
  f="$(recdir "$dir")/judge-input-${round}.md"
  {
    printf 'Round: %s\nCommit: %s\nTree: %s\n\n' "$round" "$commit" "$tree"
    cat
  } >"$f"
}

# write_verdict <dir> <round> <input-round> <commit> <tree> -- envelope naming
# its input file, plus the judged blocks on stdin.
write_verdict() {
  local dir="$1" round="$2" iround="$3" commit="$4" tree="$5" f
  f="$(recdir "$dir")/judge-verdict-${round}.md"
  {
    printf 'Round: %s\nInput: judge-input-%s.md\nCommit: %s\nTree: %s\n\n' \
      "$round" "$iround" "$commit" "$tree"
    cat
  } >"$f"
}

# ---- no records at all ---------------------------------------------------

row_start
W="$(build_repo no-records)"
run_in "$W"
assert_row 'no-records-at-all' 0 'OK\n' 0

# ---- empty input, no verdict: nothing to cover ---------------------------

row_start
W="$(build_repo empty-input)"
write_input "$W" 1 "$(head_sha "$W")" "$(head_tree "$W")" </dev/null
run_in "$W"
assert_row 'empty-input-no-verdict' 0 'OK\n' 0

# ---- covered round, clean tree --------------------------------------------

row_start
W="$(build_repo covered-clean)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
EOF
run_in "$W"
assert_row 'covered-round-clean' 0 'OK\n' 0

# ---- round numbering skips a round ----------------------------------------

row_start
W="$(build_repo round-gap)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_input "$W" 3 "$C" "$T" <<'EOF'
Finding: third finding text
EOF
run_in "$W"
assert_row 'round-gap' 0 'MISSING 2\n' 0

# ---- a verdict with no same-round input -----------------------------------

row_start
W="$(build_repo verdict-no-input)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 2 2 "$C" "$T" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'verdict-without-input' 0 'MISSING 2\n' 0

# ---- a lone verdict, no inputs at all --------------------------------------

row_start
W="$(build_repo verdict-only)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_verdict "$W" 2 2 "$C" "$T" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'verdict-only' 0 'MISSING 1 2\n' 0

# ---- same non-empty identity recorded as two rounds (Exit-batch shape) -----

row_start
W="$(build_repo same-identity)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_input "$W" 2 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
run_in "$W"
assert_row 'same-identity-two-rounds' 0 'DOUBLE 1 2\n' 0

# ---- same identity, different findings: a re-judgment, not a double ------

row_start
W="$(build_repo same-identity-diff)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_input "$W" 2 "$C" "$T" <<'EOF'
Finding: second finding text
EOF
run_in "$W"
assert_row 'same-identity-different-findings' 0 'GAP 1\n' 0

# ---- empty identity twice is malformed, not a double record ----

row_start
W="$(build_repo empty-identity)"
write_input "$W" 1 '' '' <<'EOF'
Finding: first finding text
EOF
write_input "$W" 2 '' '' <<'EOF'
Finding: first finding text
EOF
run_in "$W"
assert_row 'empty-identity-two-rounds' 0 'IDENTITY 1 2\n' 0

# ---- a verdict naming another round's input file ---------------------------

row_start
W="$(build_repo wrong-input)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
write_input "$W" 2 "$C" "$T" <<'EOF'
Finding: second finding text
EOF
write_verdict "$W" 2 1 "$C" "$T" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'verdict-names-wrong-input' 0 'DOUBLE 2\n' 0

# ---- a verdict filed for an empty input -------------------------------------

row_start
W="$(build_repo verdict-for-empty)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: stray finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'verdict-for-empty-input' 0 'DOUBLE 1\n' 0

# ---- Tree line does not match the Commit line -------------------------------

row_start
W="$(build_repo tree-mismatch)"
C="$(head_sha "$W")"
write_input "$W" 1 "$C" '0000000000000000000000000000000000000000' <<'EOF'
Finding: first finding text
EOF
run_in "$W"
assert_row 'tree-mismatch-commit' 0 'IDENTITY 1\n' 0

# ---- Commit line names no object ----------------------------------------------

row_start
W="$(build_repo unknown-commit)"
T="$(head_tree "$W")"
write_input "$W" 1 'ffffffffffffffffffffffffffffffffffffffff' "$T" <<'EOF'
Finding: first finding text
EOF
run_in "$W"
assert_row 'unknown-commit' 0 'IDENTITY 1\n' 0

# ---- a Commit line in the prose is not the envelope ----

row_start
W="$(build_repo prose-commit)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
{
  printf 'Round: 1\nTree: %s\n\n' "$T"
  printf 'Finding: first finding text\nCommit: %s\n' "$C"
} >"$(recdir "$W")/judge-input-1.md"
run_in "$W"
assert_row 'commit-in-prose-not-envelope' 0 'IDENTITY 1\n' 0

# ---- uncommitted edit: DIRTY, not anything else -------------------------------

row_start
W="$(build_repo dirty)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
printf 'uncommitted\n' >"${W}/tracked.txt"
run_in "$W"
assert_row 'dirty-tree' 0 'DIRTY\n' 0
tally check_eq 'dirty-tree: pending paths on stderr' ' M tracked.txt' "$(cat "$SUT_STDERR")"

# ---- untracked, non-ignored file -----------------------------------------------

row_start
W="$(build_repo untracked)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
printf 'new\n' >"${W}/new.txt"
run_in "$W"
assert_row 'untracked-file' 0 'DIRTY\n' 0
tally check_eq 'untracked-file: pending paths on stderr' '?? new.txt' "$(cat "$SUT_STDERR")"

# ---- the same, under status.showUntrackedFiles=no -------------------------------

row_start
W="$(build_repo untracked-hidden)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
git -C "$W" config status.showUntrackedFiles no
printf 'new\n' >"${W}/new.txt"
run_in "$W"
assert_row 'untracked-file-hidden-by-config' 0 'DIRTY\n' 0
tally check_eq 'untracked-file-hidden-by-config: pending paths on stderr' '?? new.txt' "$(cat "$SUT_STDERR")"

# ---- records belong to the worktree that made them -------------------------------

row_start
W="$(build_repo perworktree)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
L="$(git_repo_scratch perworktree-linked)"
git -C "$W" worktree add -q --detach "$L"
run_in "$L"
assert_row 'records-are-per-worktree' 0 'OK\n' 0

# ---- argument validation ----------------------------------------------------------

row_start
W="$(build_repo args)"
run_in "$W" extra
assert_row 'one-argument' 2 '' 0

# ---- accept+apply, then a fix commit: covered ----------------------------------

row_start
W="$(build_repo apply-fixed)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
EOF
git_repo_commit "$W" tracked.txt 'fixed\n' 'c2'
run_in "$W"
assert_row 'clean-accept-apply-fixed' 0 'OK\n' 0

# ---- all reject, tree unmoved -----------------------------------------------------

row_start
W="$(build_repo all-reject)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'all-reject-no-change' 0 'OK\n' 0

# ---- empty latest input, tree moved: nothing to cover -------------------------------

row_start
W="$(build_repo empty-moved)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" </dev/null
git_repo_commit "$W" tracked.txt 'unjudged work\n' 'c2'
run_in "$W"
assert_row 'empty-input-tree-moved' 0 'OK\n' 0

# ---- an input item missing from the verdict --------------------------------------------

row_start
W="$(build_repo gap-missing)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
Finding: second finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
EOF
run_in "$W"
assert_row 'input-item-missing-from-verdict' 0 'GAP 1\n' 0

# ---- gaps in two rounds report both, ascending ----------------------------------------

row_start
W="$(build_repo gap-two-rounds)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Finding: first extra text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Finding: second extra text
EOF
write_verdict "$W" 2 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'gap-in-two-rounds' 0 'GAP 1 2\n' 0

# ---- a skipped non-latest round is named once a later round exists -----------------------

row_start
W="$(build_repo gap-skipped)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
EOF
write_verdict "$W" 2 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Verdict: accept
Value: apply
fix it
EOF
run_in "$W"
assert_row 'skipped-non-latest-verdict' 0 'GAP 1\n' 0

# ---- a Verdict line that is not first is prose, not a verdict -------------------------

row_start
W="$(build_repo gap-prose-verdict)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
note: holding for a second look
Verdict: accept
Value: apply
fix it
EOF
run_in "$W"
assert_row 'verdict-not-first-line' 0 'GAP 1\n' 0

# ---- a Value line that is not second is prose, not a value -------------------------------

row_start
W="$(build_repo gap-prose-value)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
fix it first
Value: apply
EOF
run_in "$W"
assert_row 'value-not-second-line' 0 'GAP 1\n' 0

# ---- an accept with no value: an incomplete record, never a judgment ---------------------

row_start
W="$(build_repo gap-no-value)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
fix it
EOF
run_in "$W"
assert_row 'accept-without-value' 0 'GAP 1\n' 0

# ---- a reworded header is a different header -----------------------------------------------

row_start
W="$(build_repo gap-reword)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text, fixed
Verdict: accept
Value: apply
fix it
EOF
run_in "$W"
assert_row 'reworded-header' 0 'GAP 1\n' 0

# ---- a rejected candidate dropped instead of re-offered ---------------------------------------

row_start
W="$(build_repo gap-dropped)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Candidate: declined line text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
Candidate: declined line text
Verdict: reject
already judged
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
EOF
write_verdict "$W" 2 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'declined-candidate-not-reoffered' 0 'GAP 1\n' 0

# ---- a needs-user candidate dropped instead of re-offered ----

row_start
W="$(build_repo gap-dropped-needs-user)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Candidate: declined line text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
Candidate: declined line text
Verdict: needs-user
needs a human
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
EOF
run_in "$W"
assert_row 'needs-user-candidate-not-reoffered' 0 'GAP 1\n' 0

# ---- a needs-user finding dropped instead of re-offered ----

row_start
W="$(build_repo gap-dropped-finding-needs-user)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Finding: second finding text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
Finding: second finding text
Verdict: needs-user
needs a human
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: third finding text
EOF
write_verdict "$W" 2 2 "$C2" "$T2" <<'EOF'
Finding: third finding text
Verdict: reject
wrong
EOF
run_in "$W"
assert_row 'finding-needs-user-not-reoffered' 0 'GAP 1\n' 0

# ---- a rejected candidate re-offered in the next input ------------------------------------------

row_start
W="$(build_repo gap-reoffered)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Candidate: declined line text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
Candidate: declined line text
Verdict: reject
already judged
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Candidate: declined line text
EOF
write_verdict "$W" 2 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
Verdict: reject
wrong
Candidate: declined line text
Verdict: reject
still declined
EOF
run_in "$W"
assert_row 'declined-candidate-reoffered' 0 'OK\n' 0

# ---- a rejected candidate on the final round needs no re-offer --------------------------------------

row_start
W="$(build_repo gap-final)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
Candidate: declined line text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
Candidate: declined line text
Verdict: reject
already judged
EOF
run_in "$W"
assert_row 'declined-on-final-round' 0 'OK\n' 0

# ---- tree moved with no verdict at all: the judge bypassed -----------------------------------------------

row_start
W="$(build_repo uncovered-none)"
C1="$(head_sha "$W")"
T1="$(head_tree "$W")"
write_input "$W" 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C1" "$T1" <<'EOF'
Finding: first finding text
Verdict: accept
Value: apply
fix it
EOF
git_repo_commit "$W" tracked.txt 'round two\n' 'c2'
C2="$(head_sha "$W")"
T2="$(head_tree "$W")"
write_input "$W" 2 "$C2" "$T2" <<'EOF'
Finding: second finding text
EOF
git_repo_commit "$W" tracked.txt 'unjudged fix\n' 'c3'
run_in "$W"
assert_row 'tree-moved-no-verdict' 0 'UNCOVERED 2\n' 0

# ---- tree moved under an all-reject verdict ---------------------------------------------------

row_start
W="$(build_repo uncovered-reject)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: reject
wrong
EOF
git_repo_commit "$W" tracked.txt 'unjudged fix\n' 'c2'
run_in "$W"
assert_row 'tree-moved-all-reject' 0 'UNCOVERED 1\n' 0

# ---- tree moved under a record-only verdict -------------------------------------------------------

row_start
W="$(build_repo uncovered-record)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: accept
Value: record
noted
EOF
git_repo_commit "$W" tracked.txt 'unjudged fix\n' 'c2'
run_in "$W"
assert_row 'tree-moved-record-only' 0 'UNCOVERED 1\n' 0

# ---- a base absorb merged in after judging: first-parent is quiet --------------------------------------
#
# The base branch advances with a real non-merge commit and merges back with
# --no-ff, so the merge is a genuine merge commit rather than a fast-forward:
# only --first-parent keeps the absorbed side out of the rev-list. The verdict
# rejects, so the movement is unauthorised and the row discriminates: without
# --first-parent it answers UNCOVERED.

row_start
W="$(build_repo merge-only)"
C="$(head_sha "$W")"
T="$(head_tree "$W")"
write_input "$W" 1 "$C" "$T" <<'EOF'
Finding: first finding text
EOF
write_verdict "$W" 1 1 "$C" "$T" <<'EOF'
Finding: first finding text
Verdict: reject
wrong
EOF
git_repo_checkout "$W" base main
git_repo_commit "$W" base.txt 'from base\n' 'base moves'
git_repo_checkout "$W" main
git -C "$W" merge --no-ff --no-edit -q base
run_in "$W"
assert_row 'merge-only-after-judgment' 0 'OK\n' 0

harness_exit "$failed" "$total"
