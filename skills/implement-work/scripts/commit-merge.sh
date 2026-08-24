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

# Repo-root-relative throughout: MERGE_MSG records the conflicted paths that
# way, and the scan below opens them.
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
# The scan is confined to the paths this merge conflicted in, read from the
# `# Conflicts:` block git writes into MERGE_MSG, which survives the `git add`
# of the resolved files (measured). That is where a forgotten marker can be,
# and the wider sets are actively wrong: this repository's own fixtures for
# these scripts hold literal marker lines, so scanning the whole merge change
# set -- or the whole tree -- would refuse every merge that brings such a file
# in, with no way past the guard.
#
# The block's path lines are `#` + TAB + path. awk rather than sed, and a
# string literal rather than a regex, because both spellings of `\t` that
# would read naturally here are unportable: `\t` in a sed BRE is a literal
# `t` on the BSD sed macOS ships, and `\t` inside an awk regex is left
# undefined by POSIX. `\t` in an awk *string* literal is specified, so the
# comparison is done with substr against one. A pattern that silently matched
# nothing would hand the scan below an empty path list -- exactly the
# unscanned tree this check exists to refuse, and it would refuse nothing
# while still printing COMMITTED.
CONFLICTED="$(awk '/^# Conflicts:$/ {inblock = 1; next} inblock && substr($0, 1, 2) == "#\t" {print substr($0, 3)}' "${GIT_DIR_PATH}/MERGE_MSG")"

MARKED=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  # A conflict resolved by deleting the file keeps its path in the block with
  # nothing in the tree to scan (measured).
  [ -f "$path" ] || continue
  # All four of git's markers, not just the outer two. Deleting the `<<<<<<<`
  # and `>>>>>>>` lines and missing the one between them is the ordinary way a
  # hand resolution goes wrong, and it leaves a file still holding both sides;
  # keyed on the outer two alone the scan passes it, and the tree is committed
  # with both sides' text in it. The separator git writes is a bare `=======`,
  # so it is anchored to exactly that -- unanchored it would also match a
  # setext heading underline or a table rule, and refuse a conflicted markdown
  # file for good. `|||||||` is the ancestor marker `merge.conflictStyle=diff3`
  # adds, which carries a label like `<<<<<<<` does and so is left unanchored.
  if grep -q -e '^<<<<<<<' -e '^|||||||' -e '^=======$' -e '^>>>>>>>' -- "$path"; then
    MARKED="${MARKED}${path} "
  fi
done <<<"$CONFLICTED"

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
