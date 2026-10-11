#!/usr/bin/env bash
# Copied from ../../implement-work/scripts/resolve-default-branch.sh to remove lateral cross-skill use; cf. check-pr-repo.sh:37-38.
# Print this repository's default branch by its bare name on stdout, or exit 1
# having printed nothing.
#
# Called as a subprocess by sibling scripts in this skill --
# `resolve-pr-base.sh` and `watch-claude-review.sh` -- and by no SKILL.md,
# this skill's own included. There is deliberately no caller contract for it
# in pr-to-ready/SKILL.md: it is one answer these scripts need, and it lives
# here because the spec it implements does --
# ../../implement-work/references/base-branch.md,
# "## Resolving the default branch". Without this paragraph the next reader
# takes the absent caller for an oversight and either wires a contract for it
# into a SKILL.md that never calls it, or deletes the script as unreferenced.
#
# The `STOP ask-default-branch` slug is `resolve-pr-base.sh`'s own output
# contract and stays with the caller: it prints it on stdout as its answer,
# and a slug printed from here would land in the caller's command
# substitution and be read back as a branch name.
#
# One per-skill copy of the "default branch name" helper (one copy per skill
# that needs it); conventions and the STOP registry live at
# ../../implement-work/references/script-conventions.md and
# ../../implement-work/references/stop-registry.md. Do not add rungs here and
# do not print a slug here — both stay with the caller per the paragraphs
# above.
#
# Two rungs, never guessing a branch name: the GitHub API, then give up and let
# the caller ask a person. `.defaultBranchRef.name` is the bare name.
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
# Usage: resolve-default-branch.sh [repo]
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [repo]" >&2
  exit 2
fi

REPO="${1:-}"
VIEW_ARGS=(repo view)
if [ -n "$REPO" ]; then VIEW_ARGS+=("$REPO"); fi
VIEW_ARGS+=(--json defaultBranchRef --jq .defaultBranchRef.name)

if ref="$(gh "${VIEW_ARGS[@]}" 2>/dev/null)" && [ -n "$ref" ]; then
  printf '%s\n' "$ref"
  exit 0
fi

exit 1
