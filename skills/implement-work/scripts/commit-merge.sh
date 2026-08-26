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
trap 'rm -f "$CHANGED" "$BLOB"' EXIT
git diff --cached --name-only -z --diff-filter=d HEAD >"$CHANGED"

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

# A path whose blob already held a marker line on one side of the merge did
# not get it from this resolution. Confining the scan is what reading
# MERGE_MSG used to buy: this repository's own fixtures hold literal marker
# lines, so scanning every changed path would refuse each merge that carries
# such a file in, with no way past the guard. Asking the two parents keeps
# that property without depending on the block.
#
# The index blob is what is scanned, not the working-tree file: the index is
# what gets committed. A resolution staged with markers and then tidied in
# the working tree without a second `git add` commits the marker-laden blob,
# and a working-tree read would report the tidy copy (measured).
MARKED=""
while IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  if holds_markers "HEAD:${path}" || holds_markers "MERGE_HEAD:${path}"; then
    continue
  fi
  if holds_markers ":${path}"; then
    MARKED="${MARKED}${path} "
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
