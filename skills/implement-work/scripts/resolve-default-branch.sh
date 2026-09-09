#!/usr/bin/env bash
# Print this repository's default branch by its bare name on stdout, or exit 1
# having printed nothing.
#
# Called as a subprocess by three scripts in three skills -- resolve-base.sh
# beside this one, ../../pr-to-ready/scripts/resolve-pr-base.sh, and
# ../../review-code/scripts/resolve-range.sh -- and by no SKILL.md, this
# skill's own included. There is deliberately no caller contract for it in
# implement-work/SKILL.md: it is one answer three skills need, and it lives
# here because the spec it implements does -- references/base-branch.md,
# "## Resolving the default branch". Without this paragraph the next reader
# takes the absent caller for an oversight and either wires a contract for it
# into a SKILL.md that never calls it, or deletes the script as unreferenced.
#
# The `STOP ask-default-branch` slug is each caller's own output contract and
# stays with the caller: the three print it on stdout as their answer, and a
# slug printed from here would land in the caller's command substitution and
# be read back as a branch name.
#
# Two rungs, never guessing a branch name: the GitHub API, then give up and let
# the caller ask a person. `.defaultBranchRef.name` is the bare name, which is
# what every caller takes -- one compares it against branch names, two hand it
# straight to `git fetch origin --`.
#
# refs/remotes/origin/HEAD is deliberately not a rung. A clone sets that symref
# once and never refreshes it, so after the repository renames its default
# branch it keeps naming the old one; while that branch still exists this
# script would answer with it. Every caller decides a base from this answer, so
# a wrong answer here is a wrong base used with nothing anywhere reporting the
# mistake. Reading it saved one `gh` call and nothing else -- every caller path
# that reaches here fetches immediately afterwards, so there was no offline
# case to keep.
#
# The exit status and the emptiness are read together, not separately. `gh`
# exits non-zero and prints its error text on an auth, network, or
# repo-context failure, and exits 0 with an empty answer where the API named no
# default branch; tolerating the status hands that error text back as a branch
# name, and tolerating an empty answer hands back the empty string, which a
# caller fetches as `git fetch origin -- ''`.
#
# Usage: resolve-default-branch.sh
set -euo pipefail

if ref="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)" && [ -n "$ref" ]; then
  printf '%s\n' "$ref"
  exit 0
fi

exit 1
