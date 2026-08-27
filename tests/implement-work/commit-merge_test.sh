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
#   - read the conflicted paths from MERGE_MSG's `# Conflicts:` block instead
#     of from the index: `a-rename-carrying-markers-is-refused`,
#     `a-changed-comment-char-does-not-empty-the-scan`,
#     `a-path-holding-a-newline-is-scanned`
#   - scan the working-tree file instead of the index blob:
#     `the-staged-blob-is-what-is-scanned`
#   - exempt a path because a parent's blob holds a marker line anywhere,
#     instead of scanning only the conflict set git itself reports:
#     `a-file-that-holds-marker-text-and-conflicts-is-refused`
#   - decide the scan set from what the index still shows instead of from the
#     conflict set git reports:
#     `an-auto-merged-file-holding-marker-text-is-committed`
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

# A file whose own content legitimately holds marker text -- a document about
# conflicts, or one of this suite's own fixtures -- and which the two sides then
# change in the same place. The marker text is the file's, not a resolution's.
SELF_MARKER_FIRST='This documents conflict markers.\n<<<<<<< example\none side\n=======\nother side\n>>>>>>> example\nshared: first\n'
SELF_MARKER_TASK='This documents conflict markers.\n<<<<<<< example\none side\n=======\nother side\n>>>>>>> example\nshared: task side\n'
SELF_MARKER_MAIN='This documents conflict markers.\n<<<<<<< example\none side\n=======\nother side\n>>>>>>> example\nshared: base side\n'

# A document that legitimately holds a bare `=======` rule, the way a setext
# heading underline or a table rule does, with a line at each end for the two
# sides to edit independently and enough body between them that git merges the
# two edits without conflict.
RULE_DOC_FIRST='TITLE\n=======\nbody a\nbody b\nbody c\nbody d\nbody e\nbody f\nbody g\nTAIL\n'
RULE_DOC_TASK='TITLE task\n=======\nbody a\nbody b\nbody c\nbody d\nbody e\nbody f\nbody g\nTAIL\n'
RULE_DOC_MAIN='TITLE\n=======\nbody a\nbody b\nbody c\nbody d\nbody e\nbody f\nbody g\nTAIL main\n'

# build_conflict <name> [extra-base-file] [conflict-path] [comment-char] --
# prints the path of a work repository on branch `task` with a conflict in
# <conflict-path> (default shared.txt) already left in the tree by a real
# `git merge`. With <extra-base-file>, main also adds that file carrying
# conflict-marker text of its own, which merges cleanly: it is in the merge's
# change set but was never conflicted. With <comment-char>, core.commentChar
# is set **before** the merge, so the `# Conflicts:` block MERGE_MSG receives
# is written with that character instead of `#`.
build_conflict() {
  local name="$1" extra="${2:-}" path="${3:-shared.txt}" cchar="${4:-}" w
  w="$(git_repo_scratch "$name")"
  git_repo_init "$w" main
  if [ -n "$cchar" ]; then
    git -C "$w" config core.commentChar "$cchar"
  fi
  git_repo_commit "$w" "$path" 'first\n' 'c1'
  git_repo_checkout "$w" task main
  git_repo_commit "$w" "$path" 'task side\n' 'task work'
  git_repo_checkout "$w" main
  git_repo_commit "$w" "$path" 'base side\n' 'base rewrites shared'
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
# the guard. A path that already held marker text on one side of the merge is
# exempted for that reason; what is left is where a forgotten marker can
# actually be.

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
# A deletion is not in the scanned change set at all: `--diff-filter=d` drops
# it, so there is nothing to open and nothing to refuse.

total=$((total + 1))
stub_dir_new
W="$(build_conflict deleted)"
git -C "$W" rm -q -f shared.txt
run_in "$W"
MERGE_SHA="$(git -C "$W" rev-parse HEAD)"
assert_row 'a-conflict-resolved-by-deletion-is-committed' 0 "COMMITTED ${MERGE_SHA}\n"

# ---- a conflict resolved by renaming the file ---------------------------
#
# The `# Conflicts:` block names only the path the conflict landed in, so a
# resolution that moved the file leaves the markers at a path the block never
# mentions. Reading the change set from the index instead puts the rename's
# destination in the scan.

total=$((total + 1))
stub_dir_new
W="$(build_conflict renamed)"
cp "${W}/shared.txt" "${W}/renamed.txt"
rm -f "${W}/shared.txt"
git -C "$W" add -A
run_in "$W"
assert_row 'a-rename-carrying-markers-is-refused' 0 'MARKERS renamed.txt\n'
check_not_committed 'a-rename-carrying-markers-is-refused' "$W"

# ---- core.commentChar moves the block out from under the scan -----------
#
# The `# Conflicts:` block's prefix is core.commentChar, so a repository that
# changed it gets a block the `#`-anchored scan does not recognise -- an empty
# path list, which refuses nothing while printing COMMITTED. Reading the
# change set from the index does not depend on the setting at all.

total=$((total + 1))
stub_dir_new
W="$(build_conflict commentchar '' shared.txt ';')"
printf '%b' "$MARKER_BODY" >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
assert_row 'a-changed-comment-char-does-not-empty-the-scan' 0 'MARKERS shared.txt\n'
check_not_committed 'a-changed-comment-char-does-not-empty-the-scan' "$W"

# ---- a path holding a newline ------------------------------------------
#
# The block is line-oriented, so a path holding a newline is truncated at the
# break and the real file is never opened. Nothing line-based can carry such a
# path; a NUL-separated listing can.

total=$((total + 1))
stub_dir_new
NL_PATH="$(printf 'we\nird.txt')"
W="$(build_conflict newline '' "$NL_PATH")"
printf '%b' "$MARKER_BODY" >"${W}/${NL_PATH}"
git -C "$W" add -A
run_in "$W"
assert_row 'a-path-holding-a-newline-is-scanned' 0 "MARKERS ${NL_PATH}\n"
check_not_committed 'a-path-holding-a-newline-is-scanned' "$W"

# ---- the index is what gets committed, not the working tree -------------
#
# A resolution staged with markers and then tidied in the working tree without
# a second `git add` commits the index's marker-laden blob (measured). A scan
# that reads the working-tree file sees the tidy copy and passes it.

total=$((total + 1))
stub_dir_new
W="$(build_conflict staged)"
printf '%b' "$MARKER_BODY" >"${W}/shared.txt"
git -C "$W" add shared.txt
printf 'tidied after staging\n' >"${W}/shared.txt"
run_in "$W"
assert_row 'the-staged-blob-is-what-is-scanned' 0 'MARKERS shared.txt\n'
check_not_committed 'the-staged-blob-is-what-is-scanned' "$W"

# ---- a file that holds marker text of its own, and also conflicts -------
#
# Exempting a path because a parent's blob holds a marker line *anywhere* is too
# wide. A file that carries marker text as its own content -- this repository's
# own fixtures do -- and then genuinely conflicts would never be scanned, and
# the real unresolved markers git wrote into it would be committed. Measured
# against that wider rule: COMMITTED, with git's own markers in the tree, where
# the pre-change script refused it. The scan is therefore keyed on the
# scan set being the conflict set git itself reports, which a file that merged
# cleanly is not in, whatever its own content looks like.

total=$((total + 1))
stub_dir_new
W="$(git_repo_scratch selfmarker)"
git_repo_init "$W" main
git_repo_commit "$W" doc.txt "$SELF_MARKER_FIRST" 'c1'
git_repo_checkout "$W" task main
git_repo_commit "$W" doc.txt "$SELF_MARKER_TASK" 'task work'
git_repo_checkout "$W" main
git_repo_commit "$W" doc.txt "$SELF_MARKER_MAIN" 'base rewrites the shared line'
git_repo_checkout "$W" task
git -C "$W" merge -m 'Merge origin/main into task' main >/dev/null 2>&1 || true
git -C "$W" add doc.txt
run_in "$W"
assert_row 'a-file-that-holds-marker-text-and-conflicts-is-refused' 0 'MARKERS doc.txt\n'
check_not_committed 'a-file-that-holds-marker-text-and-conflicts-is-refused' "$W"

# ---- a file both sides edited, auto-merged, holding marker text ---------
#
# The mirror of the row above, and the other way the scan set goes wrong. A
# file that carries marker text as its own content and that both sides edit in
# different places auto-merges cleanly: git never conflicted in it. Keyed on
# anything the index can still show after `git add`, it is scanned anyway, its
# own `=======` is found, and a merge that was never broken is refused with no
# way past the guard. Measured against that rule: MARKERS, where the
# pre-change script committed it. Only the conflict set git itself reports
# leaves it alone.

total=$((total + 1))
stub_dir_new
W="$(git_repo_scratch automerged)"
git_repo_init "$W" main
git_repo_commit "$W" doc.txt "$RULE_DOC_FIRST" 'c1'
git_repo_commit "$W" shared.txt 'shared: first\n' 'c2'
git_repo_checkout "$W" task main
git_repo_commit "$W" doc.txt "$RULE_DOC_TASK" 'task edits the top'
git_repo_commit "$W" shared.txt 'shared: task side\n' 'task work'
git_repo_checkout "$W" main
git_repo_commit "$W" doc.txt "$RULE_DOC_MAIN" 'base edits the bottom'
git_repo_commit "$W" shared.txt 'shared: base side\n' 'base rewrites shared'
git_repo_checkout "$W" task
git -C "$W" merge -m 'Merge origin/main into task' main >/dev/null 2>&1 || true
printf 'resolved by hand\n' >"${W}/shared.txt"
git -C "$W" add shared.txt
run_in "$W"
MERGE_SHA="$(git -C "$W" rev-parse HEAD)"
assert_row 'an-auto-merged-file-holding-marker-text-is-committed' 0 "COMMITTED ${MERGE_SHA}\n"

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
