#!/usr/bin/env bash
# Commit a merge whose conflicts have been resolved, refusing any tree that is
# not actually resolved. Answers in one line.
# Usage: commit-merge.sh
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 1
fi

GIT_DIR_PATH="$(git rev-parse --absolute-git-dir)"

# Repo-root-relative throughout: the change set below is listed that way, and
# a `<rev>:<path>` lookup resolves its path that way too, so the two agree
# wherever this is run from.
cd "$(git rev-parse --show-toplevel)"

# Not an error worth a non-zero exit: it is what the caller sees when the
# merge was already committed, or when it is run from the wrong workspace.
if [ ! -e "${GIT_DIR_PATH}/MERGE_HEAD" ]; then
  echo "STOP no-merge-in-progress"
  exit 0
fi

UNMERGED="$(git diff --name-only --diff-filter=U)"

if [ -n "$UNMERGED" ]; then
  printf 'UNRESOLVED %s\n' "$(printf '%s' "$UNMERGED" | tr '\n' ' ')"
  exit 0
fi

# `git commit` treats a conflict marker as ordinary text and exits 0
# (measured), so a resolution that left one behind is committed and **Hand
# off** pushes it -- and the check above cannot catch that, because `git add`
# of a marker-laden file clears the unmerged state while leaving the markers
# in the file.
#
# The paths are the ones this merge commit will actually change -- the index
# against HEAD -- rather than the `# Conflicts:` block git writes into
# MERGE_MSG. Three ways that block loses a path, all measured on git 2.43:
# it is line-oriented, so a path holding a newline is truncated at the break
# and the real file is never opened; its `#` prefix is `core.commentChar`, so
# a repository that changed the setting yields no paths at all and the scan
# refuses nothing while printing COMMITTED; and a conflict resolved by
# renaming the file leaves the block naming only the old path, with the
# markers sitting at the new one.
#
# `-z` so the listing is NUL-separated: no quoting convention has to be
# undone, and a path holding a newline survives it. `--diff-filter=d` drops
# deletions, which is how a conflict resolved by deleting the file leaves
# nothing to scan.
#
# A plain redirection into a file rather than `done < <(git diff ...)`: in a
# process substitution the producer's exit status is unreachable, so a `git
# diff` that died would leave the loop reading an empty list -- the unscanned
# tree this check exists to refuse, printing COMMITTED. `set -e` aborts on the
# redirection's own failure instead.
CHANGED="$(mktemp)"
BLOB="$(mktemp)"
trap 'rm -f "$CHANGED" "$BLOB" "${MT:-}" "${CONFLICTED:-}"' EXIT
git diff --cached --name-only -z --diff-filter=d HEAD >"$CHANGED"

# The true conflict set, recomputed from the two parents. `git add` destroys
# the unmerged stages, and both ways of guessing the set back from what
# survives have been measured wrong, in opposite directions: keyed on whether a
# parent held a marker line anywhere, a file that carries marker text *and*
# conflicts is exempted whole and its real markers are committed; keyed on the
# index blob matching a parent, a file both sides edited in different places is
# scanned and its own marker-looking text refuses a merge that never
# conflicted. Neither is a blind spot -- both are worse than the MERGE_MSG scan
# they replaced. merge-tree asks git the question instead of approximating it.
# Both tips are resolved first. `merge-tree` exits 1 for a genuine conflict
# *and* for a ref it cannot resolve -- this repository already records that
# measurement in `skills/pr-to-ready/references/gh-mechanics.md`. The guard
# above only checks that the MERGE_HEAD *file* exists; an empty or truncated
# one resolves to nothing and produces exactly the same exit 1 (measured).
# Without this, that case yields an empty conflict set, nothing is scanned, and
# COMMITTED is printed over a tree nobody looked at.
if ! git rev-parse --verify --quiet HEAD >/dev/null 2>&1 \
  || ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null 2>&1; then
  echo "STOP conflict-set-unavailable"
  exit 0
fi

MT="$(mktemp)"
# With both tips resolved, exit 1 can only mean "the merge conflicts", which is
# the ordinary case here. Above that is a real failure.
MT_STATUS=0
git merge-tree -z --write-tree --name-only HEAD MERGE_HEAD >"$MT" 2>/dev/null || MT_STATUS=$?
if [ "$MT_STATUS" -gt 1 ]; then
  echo "STOP conflict-set-unavailable"
  exit 0
fi

CONFLICTED="$(mktemp)"
# Field 0 is the tree oid; the conflicted paths follow; an empty field ends
# them, and the informational messages follow that.
#
# Read in bash rather than with `awk 'BEGIN { RS = "\0" }'`. Setting RS to NUL
# is not portable: measured, busybox awk ignores it, prints nothing and exits
# 0 -- handing the scan an empty set with no error anywhere, which is this
# script's own failure mode reached through the choice of awk.
mt_field=0
while IFS= read -r -d '' field; do
  mt_field=$((mt_field + 1))
  if [ "$mt_field" -eq 1 ]; then
    continue
  fi
  if [ -z "$field" ]; then
    break
  fi
  printf '%s\0' "$field"
done <"$MT" >"$CONFLICTED"

# Exit 1 said this merge conflicts, so the set cannot be empty. If it is, the
# read above did not see what merge-tree wrote, and scanning nothing is exactly
# what must not happen quietly.
if [ "$MT_STATUS" -eq 1 ] && [ ! -s "$CONFLICTED" ]; then
  echo "STOP conflict-set-unavailable"
  exit 0
fi

# The blob is written to a file and grepped there rather than piped into
# grep. `grep -q` exits at its first match, which sends SIGPIPE upstream, and
# under `pipefail` the dying `git cat-file` (141) becomes the pipeline's
# status -- so a *matching* blob large enough for the write to still be in
# flight reports non-zero and its marker is read as absent. Measured: a 17 MB
# blob whose first line is a marker gave status 141 and the marker was
# missed. That is this script's own failure mode, so no pipeline shape is
# usable here.
#
# All four of git's markers, not just the outer two. Deleting the `<<<<<<<`
# and `>>>>>>>` lines and missing the one between them is the ordinary way a
# hand resolution goes wrong, and it leaves a file still holding both sides;
# keyed on the outer two alone the scan passes it, and the tree is committed
# with both sides' text in it. The separator git writes is a bare `=======`,
# so it is anchored to exactly that -- unanchored it would also match a setext
# heading underline or a table rule, and refuse a conflicted markdown file for
# good. `|||||||` is the ancestor marker `merge.conflictStyle=diff3` adds,
# which carries a label like `<<<<<<<` does and so is left unanchored.
#
# A path absent from the given side is not an error: `git cat-file` fails,
# and "no blob there" is exactly "no markers there".
holds_markers() {
  git cat-file blob "$1" >"$BLOB" 2>/dev/null || return 1
  grep -q -e '^<<<<<<<' -e '^|||||||' -e '^=======$' -e '^>>>>>>>' -- "$BLOB"
}

# A path is scanned when git reports this merge conflicted in it, or when the
# resolution created it and neither parent has it -- a conflict resolved by
# renaming leaves the markers at a path merge-tree names nowhere. A file that
# merged cleanly is in neither, whatever its own content looks like.
in_conflict_set() {
  local c
  while IFS= read -r -d '' c; do
    if [ "$c" = "$1" ]; then
      return 0
    fi
  done <"$CONFLICTED"
  return 1
}

absent_from_both_parents() {
  git cat-file -e "HEAD:$1" 2>/dev/null && return 1
  git cat-file -e "MERGE_HEAD:$1" 2>/dev/null && return 1
  return 0
}

# The index blob is what is scanned, not the working-tree file: the index is
# what gets committed. A resolution staged with markers and then tidied in
# the working tree without a second `git add` commits the marker-laden blob,
# and a working-tree read would report the tidy copy (measured).
MARKED=""
while IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  if in_conflict_set "$path" || absent_from_both_parents "$path"; then
    if holds_markers ":${path}"; then
      MARKED="${MARKED}${path} "
    fi
  fi
done <"$CHANGED"

if [ -n "$MARKED" ]; then
  printf 'MARKERS %s\n' "${MARKED% }"
  exit 0
fi

# --no-edit takes the message git already wrote to MERGE_MSG. A hook that
# rejects it fails here rather than leaving the caller to read exit status
# from a token that says the commit happened.
if ! git commit --no-edit >&2; then
  echo "STOP commit-failed"
  exit 0
fi

printf 'COMMITTED %s\n' "$(git rev-parse HEAD)"
