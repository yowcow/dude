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
#   - drop the verdict-Input-name check: `verdict-names-wrong-input`
#   - drop the verdict-for-empty-input DOUBLE check: `verdict-for-empty-input`
#   - compare Tree to HEAD^{tree} instead of <commit>^{tree}:
#     `clean-accept-apply-fixed`
#   - use --no-merges without --first-parent: `merge-only-after-judgment`
#   - drop the stateful GAP parse, keep header-set difference only:
#     `accept-without-value`, `declined-candidate-not-reoffered`
#   - drop the candidate re-offer check: `declined-candidate-not-reoffered`
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

harness_exit "$failed" "$total"
