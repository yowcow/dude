#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/absorb-base.sh: the one line
# it prints for each answer, and what it leaves in the tree.
#
# git is not stubbed. Every behaviour under test is git's own -- which merge
# failures leave unmerged paths behind, and which ref a fetch updates -- and a
# stub would encode the test author's belief about that rather than git's
# behaviour. Each row therefore builds a real bare repository to play the
# remote and a real work repository whose `origin` points at it, both under
# $HARNESS_TMP and both offline.
#
# No row stubs `gh`: this script never calls it. Every row asserts zero gh
# calls, which is what holds that to being true.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version; each of the three deliberately broken variants below is one
# defect wide, and the rows it must fail are named:
#   - read an inherited `FETCH_HEAD` instead of fetching:
#     `inherited-fetch-head-is-not-trusted`, `stale-remote-ref-is-refetched`
#   - treat any non-zero `git merge` exit as a conflict:
#     `unrelated-histories-is-not-a-conflict`, `merge-failed-leaves-no-conflict`
#   - drop the is-ancestor pre-check: `already-contains-the-base`
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/absorb-base.sh}"

failed=0
total=0

# build_case <name> <base-change> -- prints the path of a work repository on
# branch `task`, whose origin is a bare repo holding `main` and `decoy`.
#
# `task` branches off main's first commit, so main's second commit is the base
# update to absorb. <base-change> picks what that second commit does:
#   clean     -- touches base.txt, which `task` never touched
#   conflict  -- rewrites shared.txt, which `task` also rewrote
#   none      -- no second commit at all; main stays an ancestor of task
build_case() {
  local name="$1" change="$2" bare w
  bare="$(git_repo_bare acme "$name")"
  w="$(git_repo_scratch "$name")"
  git_repo_init "$w" main
  git_repo_commit "$w" shared.txt 'first\n' 'c1'
  git_repo_checkout "$w" decoy main
  git_repo_commit "$w" decoy.txt 'decoy\n' 'decoy work'
  git_repo_checkout "$w" main
  git_repo_checkout "$w" task main
  git_repo_commit "$w" shared.txt 'task side\n' 'task work'
  git_repo_checkout "$w" main
  case "$change" in
    clean) git_repo_commit "$w" base.txt 'from base\n' 'base moves' ;;
    conflict) git_repo_commit "$w" shared.txt 'base side\n' 'base rewrites shared' ;;
    none) ;;
    *)
      echo "build_case: unknown change '${change}'" >&2
      exit 1
      ;;
  esac
  git_repo_remote "$w" origin "$bare"
  git_repo_push "$w" origin main decoy
  git_repo_checkout "$w" task
  printf '%s\n' "$w"
}

# run_in <work-dir> <argv...> -- the SUT reads cwd's repository, so every row
# runs from inside its own work repository and returns to the repository root.
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

# check_unmerged <label> <work-dir> <want> -- the unmerged paths, space-joined
check_unmerged() {
  local got
  got="$(git -C "$2" diff --name-only --diff-filter=U | tr '\n' ' ')"
  check_eq "$1" "$3" "${got% }"
}

# check_contains <label> <work-dir> <sha> -- is <sha> an ancestor of HEAD?
check_contains() {
  local got=yes
  git -C "$2" merge-base --is-ancestor "$3" HEAD || got=no
  check_eq "$1" 'yes' "$got"
}

# ---- the base is already contained -------------------------------------
#
# `git merge` exits 0 for a base already merged, so without the is-ancestor
# pre-check this row reads `MERGED <sha>`. That is the defect that stops the
# completion gate from ever converging: its "nothing changed" exit could never
# be reached, and the loop would spin to its round ceiling.

total=$((total + 1))
stub_dir_new
W="$(build_case uptodate none)"
BEFORE="$(git -C "$W" rev-parse HEAD)"
run_in "$W" task main
assert_row 'already-contains-the-base' 0 'UP-TO-DATE\n'
total=$((total + 1))
if ! check_eq 'already-contains-the-base: HEAD unmoved' "$BEFORE" "$(git -C "$W" rev-parse HEAD)"; then
  failed=$((failed + 1))
fi

# ---- a clean absorb ----------------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case clean clean)"
MAIN_SHA="$(git -C "$W" rev-parse main)"
run_in "$W" task main
assert_row 'absorbs-a-moved-base' 0 "MERGED ${MAIN_SHA}\n"
total=$((total + 1))
if ! check_contains 'absorbs-a-moved-base: the base tip is now an ancestor' "$W" "$MAIN_SHA"; then
  failed=$((failed + 1))
fi
total=$((total + 1))
if ! check_eq 'absorbs-a-moved-base: base file is present' 'from base' \
  "$(cat "${W}/base.txt" 2>&1)"; then
  failed=$((failed + 1))
fi
total=$((total + 1))
if ! check_eq 'absorbs-a-moved-base: tree is clean' '' "$(git -C "$W" status --porcelain)"; then
  failed=$((failed + 1))
fi

# ---- a conflict, left in the tree --------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case conflicted conflict)"
run_in "$W" task main
assert_row 'conflict-is-left-in-the-tree' 0 'CONFLICTED shared.txt\n'
total=$((total + 1))
if ! check_eq 'conflict-is-left-in-the-tree: merge is still in progress' 'yes' \
  "$([ -e "${W}/.git/MERGE_HEAD" ] && echo yes || echo no)"; then
  failed=$((failed + 1))
fi
total=$((total + 1))
if ! check_unmerged 'conflict-is-left-in-the-tree: path is unmerged' "$W" 'shared.txt'; then
  failed=$((failed + 1))
fi

# ---- a merge that fails without leaving a conflict ---------------------
#
# Both rows are the first silent failure: exit status alone cannot tell a
# conflict from a merge that never produced one. Measured on git 2.43 --
# unrelated histories exit 128 with no MERGE_HEAD and nothing unmerged, and a
# merge stopped by a failing commit-msg hook exits 1 *with* MERGE_HEAD and
# still nothing unmerged. Reading either as CONFLICTED sends the caller to
# resolve a tree with no conflict in it, and `commit-merge.sh` then finds no
# unmerged path and commits an empty resolution as though the base had been
# absorbed.

total=$((total + 1))
stub_dir_new
BARE="$(git_repo_bare acme unrelated)"
SEED="$(git_repo_scratch unrelated-seed)"
git_repo_init "$SEED" main
git_repo_commit "$SEED" only.txt 'unrelated\n' 'unrelated root'
git_repo_push "$SEED" "$BARE" main
W="$(git_repo_scratch unrelated-work)"
git_repo_init "$W" task
git_repo_commit "$W" task.txt 'task\n' 'task root'
git_repo_remote "$W" origin "$BARE"
run_in "$W" task main
assert_row 'unrelated-histories-is-not-a-conflict' 0 'STOP merge-failed\n'
total=$((total + 1))
if ! check_unmerged 'unrelated-histories-is-not-a-conflict: nothing unmerged' "$W" ''; then
  failed=$((failed + 1))
fi

total=$((total + 1))
stub_dir_new
W="$(build_case hookfail clean)"
mkdir -p "${W}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' >"${W}/.git/hooks/commit-msg"
chmod +x "${W}/.git/hooks/commit-msg"
run_in "$W" task main
assert_row 'merge-failed-leaves-no-conflict' 0 'STOP merge-failed\n'
total=$((total + 1))
if ! check_unmerged 'merge-failed-leaves-no-conflict: nothing unmerged' "$W" ''; then
  failed=$((failed + 1))
fi

# ---- the tip absorbed is the one this script's own fetch resolved ------
#
# The second silent failure, in its two shapes. `git fetch` rewrites
# FETCH_HEAD on every call, so a tip inherited from an earlier fetch names
# whichever ref was fetched last -- within one round of the completion gate,
# `review-code`'s range resolution fetches too. A remote-tracking ref left by
# an earlier round is the same defect one step quieter: it is stale, so the
# base's newer commits are absent and the answer is `UP-TO-DATE` for a base
# that has in fact moved.

total=$((total + 1))
stub_dir_new
W="$(build_case inherited clean)"
MAIN_SHA="$(git -C "$W" rev-parse main)"
DECOY_SHA="$(git -C "$W" rev-parse decoy)"
# Leave FETCH_HEAD holding the decoy, as an earlier fetch in the same round
# would. A script that reads it instead of fetching absorbs `decoy`.
git -C "$W" fetch -q origin '+refs/heads/decoy:refs/remotes/origin/decoy'
if [ "$(git -C "$W" rev-parse FETCH_HEAD)" != "$DECOY_SHA" ]; then
  echo 'inherited-fetch-head-is-not-trusted: fixture failed to seed FETCH_HEAD' >&2
  exit 1
fi
run_in "$W" task main
assert_row 'inherited-fetch-head-is-not-trusted' 0 "MERGED ${MAIN_SHA}\n"
total=$((total + 1))
if ! check_eq 'inherited-fetch-head-is-not-trusted: the decoy was not absorbed' 'no' \
  "$([ -e "${W}/decoy.txt" ] && echo yes || echo no)"; then
  failed=$((failed + 1))
fi

total=$((total + 1))
stub_dir_new
W="$(build_case stalref clean)"
MAIN_SHA="$(git -C "$W" rev-parse main)"
# Roll refs/remotes/origin/main back to main's parent, as a fetch from an
# earlier round would have left it before the base moved. A script that trusts
# that ref answers UP-TO-DATE, because the parent *is* an ancestor of task.
git -C "$W" update-ref refs/remotes/origin/main "${MAIN_SHA}^"
run_in "$W" task main
assert_row 'stale-remote-ref-is-refetched' 0 "MERGED ${MAIN_SHA}\n"

# ---- the guards --------------------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case wrongbranch clean)"
git_repo_checkout "$W" main
run_in "$W" task main
assert_row 'not-on-the-named-branch' 0 'STOP wrong-branch\n'

total=$((total + 1))
stub_dir_new
W="$(build_case detached clean)"
git -C "$W" checkout -q --detach
run_in "$W" task main
assert_row 'detached-head' 0 'STOP detached-head\n'

total=$((total + 1))
stub_dir_new
W="$(build_case dirty clean)"
printf 'uncommitted\n' >"${W}/shared.txt"
run_in "$W" task main
assert_row 'dirty-tree' 0 'STOP dirty-tree\n'
total=$((total + 1))
if ! check_eq 'dirty-tree: no merge was started' 'no' \
  "$([ -e "${W}/.git/MERGE_HEAD" ] && echo yes || echo no)"; then
  failed=$((failed + 1))
fi

total=$((total + 1))
stub_dir_new
W="$(build_case nobase clean)"
run_in "$W" task nosuchbase
assert_row 'base-absent-on-the-remote' 0 'STOP base-fetch-failed\n'

# ---- argument validation -----------------------------------------------

total=$((total + 1))
stub_dir_new
W="$(build_case argsnone clean)"
run_in "$W"
assert_row 'no-arguments' 1 ''

total=$((total + 1))
stub_dir_new
W="$(build_case argsone clean)"
run_in "$W" task
assert_row 'one-argument' 1 ''

total=$((total + 1))
stub_dir_new
W="$(build_case argsthree clean)"
run_in "$W" task main extra
assert_row 'three-arguments' 1 ''

harness_exit "$failed" "$total"
