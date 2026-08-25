#!/usr/bin/env bash
# bash -n and ShellCheck over every shell file in the repository, selected by
# shebang.
# Usage: tests/lint.sh
#
# Selection is by shebang, not by a *.sh glob. The fake `gh` at
# tests/lib/bin/gh has to be named `gh` to work as a PATH stub, so it cannot
# carry an extension, and `find -name '*.sh'` drops exactly that one file — the
# ground truth the whole offline suite rests on. ShellCheck reads the shebang
# when handed a path, so an extensionless file is checked normally.
#
# This script is in its own selection: it lives in the repository and carries
# a shebang. That is the point of it being a script rather than an inline CI
# step — the gate has to cover the code the suite trusts as ground truth, and
# a workflow's `run:` block or a Makefile recipe carries no shebang and so is
# checked by nothing.
#
# The tree is anchored at this script's own location, never the cwd: `make lint`
# runs with cwd at the repository root, `tests/lint.sh` from tests/ runs with
# cwd there, and a cwd-relative `find .` would silently check whatever the cwd
# happened to be and report success having checked the wrong tree.
#
# ShellCheck is spelled with capitals throughout these comments: a comment line
# starting "# shellcheck " parses as a directive, and prose after it is an
# SC1073 error the day anything lints this file.
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# The first line is read with `read`, not `head | grep`: `grep -q` exits on its
# first match, and the resulting SIGPIPE to `head` would fail the pipeline under
# `pipefail`, silently dropping the file.
#
# Only sh and bash are selected, because those are the shells ShellCheck
# supports. A zsh or ksh script added to the repository later is silently left
# out of the selection — not checked, and not an error either. The printed list
# below is the only signal for that, so it is printed on every run rather than
# kept quiet.
# The listing is built as a plain foreground pipeline into a temp file, not as
# a process substitution feeding the loop directly. In `done < <(find ...)` the
# producer's exit status is unreachable: a `find` that dies partway through the
# tree — an unreadable subdirectory, say — leaves the loop running on whatever
# it managed to emit before failing, the guard below still sees a non-empty
# selection, and the run prints "bash -n: ok" and "shellcheck: ok" having
# checked only part of the tree. Measured: a chmod-000 subdirectory holding one
# shell file produced exactly that false success, exit 0.
#
# `pipefail` is what makes the single `if !` sufficient here — it catches a
# failure in either stage, so neither `find` nor `sort` can fail unnoticed.
LISTING="$(mktemp)"
trap 'rm -f "$LISTING"' EXIT

# Three directories are pruned, none of which was an exclusion this needed while
# it scanned a subdirectory of the repository. The tree now starts at the
# repository root, and all three hold files that are not this repository's code:
#
#   .git               a plain checkout — CI's and the main working tree alike —
#                      carries it as a real directory, and its hooks/*.sample
#                      are shebanged `#!/bin/sh`, so 13 would be selected.
#   .worktrees         git worktrees made by hand, per .gitignore.
#   .claude/worktrees  git worktrees made by Claude Code's own worktree tool.
#                      Matched by path, not by name: `worktrees` alone would
#                      also prune a directory that happened to be called that,
#                      and over-pruning is the one direction this must not fail
#                      in. Note that .claude is *not* gitignored, so nothing
#                      else keeps this content out of the walk.
#
# Both worktree directories hold working copies of these same files, on other
# branches. A run from inside a linked worktree cannot verify this prune at all;
# `tests/README.md` says why, and how to exercise it where it bites.
#
# What forgetting a name here can never do is drop a file that should have been
# checked: it selects too much and fails loudly. That asymmetry is why the list
# is spelled out rather than derived from something cleverer such as
# `git check-ignore`, which would silently skip whatever is ignored.
if ! find "$REPO_ROOT" \
  -type d \( -name .git -o -name .worktrees -o -path '*/.claude/worktrees' \) -prune -o \
  -type f -print0 | sort -z >"$LISTING"; then
  echo "listing ${REPO_ROOT} failed — the tree was not fully read" >&2
  exit 1
fi

# Symlinks are deliberately not followed: `-type f` without `-L` classifies a
# symlink by the link, so a shell script symlinked into the tree is not
# selected. There is none today (`find . -type l` is empty) and skills are
# directories of real files. Following them with -L would let the selection
# escape the repository and would turn any dangling link into a hard failure via
# the check above.
# Recorded as a decision rather than left as an unstated gap, same as the
# zsh/ksh exclusion above.
files=()
while IFS= read -r -d '' f; do
  if [ ! -r "$f" ]; then
    echo "cannot read ${f}" >&2
    exit 1
  fi
  first=''
  IFS= read -r first <"$f" || true
  case "$first" in
    '#!'*bash* | '#!'*[[:space:]/]sh | '#!'*[[:space:]/]sh[[:space:]]*)
      files+=("$f")
      ;;
  esac
done <"$LISTING"

# An empty selection can only mean the matcher itself broke: this script is
# under REPO_ROOT and carries a shebang, so a working matcher always selects at
# least this file. Without the guard a typo in the pattern above would report
# success having checked nothing at all — the same "absent" versus "could not
# ask" confusion this whole suite exists to catch. A pattern that breaks only
# partially still slips through; the printed list above is the signal for that.
if [ "${#files[@]}" -eq 0 ]; then
  echo "no shell file found under ${REPO_ROOT} — the selection is broken" >&2
  exit 1
fi

printf 'selected %s shell file(s):\n' "${#files[@]}"
printf '  %s\n' "${files[@]}"

for f in "${files[@]}"; do
  bash -n -- "$f"
done
echo "bash -n: ok"

shellcheck --version
shellcheck -- "${files[@]}"
echo "shellcheck: ok"
