#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/commit-merge.sh: what it
# refuses to commit, and what it commits.
#
# git is not stubbed, for the same reason as absorb-base_test.sh: the central
# fact under test is git's own -- `git commit` treats a leftover conflict
# marker as ordinary text and exits 0 -- and a stub would encode a belief
# about it instead. No row stubs `gh`; every row asserts zero gh calls.
#
# Marker fixtures are written with `printf` rather than a heredoc so that no
# line of this file itself begins with a conflict marker. That keeps the file
# safe for the very scan the SUT performs, should this file ever be one of the
# paths a merge conflicts in.
#
# RED verification (see tests/README.md). The script is new, so the variants
# below are deliberately broken copies, one defect wide each:
#   - drop the marker scan: `markers-left-behind-are-refused`
#   - drop the unmerged-path check: `unresolved-paths-are-refused`
#   - scan the whole merge change set instead of the conflicted paths:
#     `markers-outside-the-conflict-are-ignored`
#   - ignore whether the commit succeeded: `commit-hook-rejects-the-resolution`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/commit-merge.sh}"

failed=0
total=0

MARKER_BODY='<<<<<<< HEAD\ntask side\n=======\nbase side\n>>>>>>> origin/main\n'
# Half-removed marker sets: the outer two lines deleted, the inner one missed.
# Both hold both sides' text, so neither is a resolution.
PARTIAL_BODY='task side\n=======\nbase side\n'
DIFF3_BODY='task side\n||||||| 1a2b3c4\nfirst\nbase side\n'

# build_conflict <name> [extra-base-file] -- prints the path of a work
# repository on branch `task` with a conflict in shared.txt already left in
# the tree by a real `git merge`. With <extra-base-file>, main also adds that
# file carrying conflict-marker text of its own, which merges cleanly: it is
# in the merge's change set but was never conflicted.
build_conflict() {
  local name="$1" extra="${2:-}" w
  w="$(git_repo_scratch "$name")"
  git_repo_init "$w" main
  git_repo_commit "$w" shared.txt 'first\n' 'c1'
  git_repo_checkout "$w" task main
  git_repo_commit "$w" shared.txt 'task side\n' 'task work'
  git_repo_checkout "$w" main
  git_repo_commit "$w" shared.txt 'base side\n' 'base rewrites shared'
  if [ -n "$extra" ]; then
    git_repo_commit "$w" "$extra" "$MARKER_BODY" 'base adds a file holding marker text'
  fi
  git_repo_checkout "$w" task
  # The conflict is produced by a real merge, so MERGE_HEAD and the
  # `# Conflicts:` block in MERGE_MSG are git's own and not a fixture's guess.
  git -C "$w" merge -m 'Merge origin/main into task' main >/dev/null 2>&1 || true
  printf '%s\n' "$w"
}

# run_in <work-dir> <argv...>
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

# check_not_committed <name> <work-dir> -- the merge is still in progress and
# HEAD has not moved.
check_not_committed() {
  local name="$1" w="$2"
  total=$((total + 1))
  if ! check_eq "${name}: merge still in progress" 'yes' \
    "$([ -e "${w}/.git/MERGE_HEAD" ] && echo yes || echo no)"; then
    failed=$((failed + 1))
  fi
}

# ---- a resolved merge is committed -------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_conflict resolved)"
printf 'resolved by hand\n' >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
MERGE_SHA="$(git -C "$W" rev-parse HEAD)"
assert_row 'a-resolved-merge-is-committed' 0 "COMMITTED ${MERGE_SHA}\n"
total=$((total + 1))
if ! check_eq 'a-resolved-merge-is-committed: two parents' 3 \
  "$(git -C "$W" rev-list --parents -1 HEAD | wc -w | tr -d ' ')"; then
  failed=$((failed + 1))
fi
total=$((total + 1))
if ! check_eq 'a-resolved-merge-is-committed: tree is clean' '' \
  "$(git -C "$W" status --porcelain)"; then
  failed=$((failed + 1))
fi

# ---- a marker left behind is refused -----------------------------------
#
# The third silent failure. `git commit` treats a conflict marker as ordinary
# text and exits 0 (measured), so the broken tree is committed and **Hand
# off** pushes it. The unmerged-path check cannot catch this: `git add` of a
# marker-laden file clears the unmerged state while leaving the markers.

total=$((total + 1))
stub_dir_new
W="$(build_conflict markers)"
printf '%b' "$MARKER_BODY" >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
assert_row 'markers-left-behind-are-refused' 0 'MARKERS shared.txt\n'
check_not_committed 'markers-left-behind-are-refused' "$W"

# ---- a half-removed marker set is refused too ---------------------------
#
# Deleting the `<<<<<<<` and `>>>>>>>` lines and missing the one between them
# is the ordinary way a hand resolution goes wrong, and it leaves a file that
# still holds both sides. Keying the scan on the outer two markers alone would
# pass it: the separator git writes is a bare `=======`, and under
# `merge.conflictStyle=diff3` there is a `||||||| <sha>` ancestor marker as
# well, neither of which begins with `<` or `>`. The tree would then be
# committed with both sides' text in it and **Hand off** would push it -- the
# same silent failure `markers-left-behind-are-refused` covers, reached by a
# more likely route.

total=$((total + 1))
stub_dir_new
W="$(build_conflict partial)"
printf '%b' "$PARTIAL_BODY" >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
assert_row 'partial-marker-removal-is-refused' 0 'MARKERS shared.txt\n'
check_not_committed 'partial-marker-removal-is-refused' "$W"

total=$((total + 1))
stub_dir_new
W="$(build_conflict diff3)"
printf '%b' "$DIFF3_BODY" >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
assert_row 'diff3-ancestor-marker-is-refused' 0 'MARKERS shared.txt\n'
check_not_committed 'diff3-ancestor-marker-is-refused' "$W"

# ---- a marker outside the conflicted set is not the scan's business ----
#
# `base-marker.txt` merges cleanly and holds marker text of its own. Scanning
# the whole merge change set would refuse this merge, and refuse it for good:
# this repository's own fixtures for these scripts hold literal marker lines,
# so every merge that brings such a file in would be blocked with no way past
# the guard. The conflicted set -- read from MERGE_MSG -- is where a forgotten
# marker can actually be.

total=$((total + 1))
stub_dir_new
W="$(build_conflict scoped base-marker.txt)"
printf 'resolved by hand\n' >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
MERGE_SHA="$(git -C "$W" rev-parse HEAD)"
assert_row 'markers-outside-the-conflict-are-ignored' 0 "COMMITTED ${MERGE_SHA}\n"
total=$((total + 1))
if ! check_eq 'markers-outside-the-conflict-are-ignored: the clean file kept its text' 2 \
  "$(grep -c -e '^<<<<<<<' -e '^>>>>>>>' "${W}/base-marker.txt")"; then
  failed=$((failed + 1))
fi

# ---- unmerged paths are refused ----------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_conflict unresolved)"
run_in "$W"
assert_row 'unresolved-paths-are-refused' 0 'UNRESOLVED shared.txt\n'
check_not_committed 'unresolved-paths-are-refused' "$W"

# ---- a conflict resolved by deleting the file ---------------------------
#
# The path stays in MERGE_MSG's `# Conflicts:` block with no file in the tree
# (measured), so the scan has to tolerate a missing file rather than fail on
# it.

total=$((total + 1))
stub_dir_new
W="$(build_conflict deleted)"
git -C "$W" rm -q -f shared.txt
run_in "$W"
MERGE_SHA="$(git -C "$W" rev-parse HEAD)"
assert_row 'a-conflict-resolved-by-deletion-is-committed' 0 "COMMITTED ${MERGE_SHA}\n"

# ---- the commit itself is refused --------------------------------------
#
# A hook that rejects the merge commit leaves the resolution staged and the
# merge in progress -- a state the caller can fix and retry. Without the
# token the caller sees only a non-zero exit, which does not tell that state
# apart from the script itself being broken, and re-running blindly is the
# wrong move in one case and the right one in the other.

total=$((total + 1))
stub_dir_new
W="$(build_conflict commithook)"
printf 'resolved by hand\n' >"${W}/shared.txt"
git -C "$W" add shared.txt
mkdir -p "${W}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' >"${W}/.git/hooks/commit-msg"
chmod +x "${W}/.git/hooks/commit-msg"
run_in "$W"
assert_row 'commit-hook-rejects-the-resolution' 0 'STOP commit-failed\n'
check_not_committed 'commit-hook-rejects-the-resolution' "$W"

# ---- no merge in progress ----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(git_repo_scratch nomerge)"
git_repo_init "$W" task
git_repo_commit "$W" f.txt 'x\n' 'c1'
run_in "$W"
assert_row 'no-merge-in-progress' 0 'STOP no-merge-in-progress\n'

# ---- argument validation -----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_conflict argsextra)"
printf 'resolved by hand\n' >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W" extra
assert_row 'any-argument-is-refused' 1 ''
check_not_committed 'any-argument-is-refused' "$W"

harness_exit "$failed" "$total"
