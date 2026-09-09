#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/resolve-default-branch.sh: what
# it prints and what it exits for each answer `gh repo view` can give.
#
# Three callers in three skills read this script's stdout as a branch name and
# its non-zero exit as "could not tell", so every row asserts both halves. No
# git fixture and no run_in: this script shells out to `gh` and to nothing
# else, and reads no repository of its own.
#
# Limitation: the `--jq .defaultBranchRef.name` expression is not executed --
# gh_stub_response hands back the post-jq bytes each row scripted. A defect
# confined to that filter string is invisible here, exactly as it is in the
# three caller test files.
#
# RED verification (see tests/README.md). The script is new, so there is no
# pre-fix version to point SUT= at. Each guard the script's own header names
# was mutated in a copy under `mktemp -d` -- never inside the repository, where
# lint.sh would select it by shebang -- and this file re-run against it as
# `SUT=<copy> tests/run.sh tests/implement-work/resolve-default-branch_test.sh`.
# What each mutant produced, measured:
#
#   1. The emptiness half of the guard. Dropping `&& [ -n "$ref" ]` failed
#      `api-answers-empty` alone: want exit 1 with nothing on stdout, got
#      exit 0 and a bare newline -- which a caller takes for a branch whose
#      name is the empty string.
#   2. The exit-status half. Replacing the guard with
#      `ref="$(gh ... 2>/dev/null)" || true` plus an unconditional printf
#      failed both "not knowing" rows: `api-call-fails` (want exit 1 with
#      nothing on stdout, got exit 0 and `gh: HTTP 502` -- gh's own error text
#      handed back as a branch name) and `api-answers-empty` (want exit 1 with
#      nothing on stdout, got exit 0 and a bare newline) -- an unconditional
#      printf has no way to fail on only one of the two.
#
# Not coverable here: the `2>/dev/null`. The fake `gh` writes a failing
# response's body to stdout, as real gh does with the body it received, so no
# row can produce gh stderr for that redirect to swallow and dropping it
# changes no byte this file can read -- this is read from the fake gh's own
# behavior (tests/lib/bin/gh), not measured by a mutant run.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/resolve-default-branch.sh}"

failed=0
total=0

# stub_default_branch <exit-status> -- the one `gh` call this script makes,
# body on stdin, already filtered.
stub_default_branch() {
  gh_stub_response '*' "$1" repo view --json defaultBranchRef --jq .defaultBranchRef.name
}

# ---- the API answers ----------------------------------------------------
#
# `trunk` rather than `main`: a mutant that guesses the conventional name
# instead of asking would pass a row named `main`, which is the same reason
# resolve-range_test.sh's fixture remote calls its default branch `trunk`.

row_start
printf 'trunk\n' | stub_default_branch 0
run_sut bash "$SUT"
assert_row 'api-names-the-branch' 0 'trunk\n' 1

# ---- the two ways of not knowing ----------------------------------------
#
# Both answer exit 1 with nothing on stdout, and they must: the callers turn
# either into `STOP ask-default-branch`, and any byte on stdout here is a
# branch name as far as a caller's command substitution is concerned.

row_start
: | stub_default_branch 0
run_sut bash "$SUT"
assert_row 'api-answers-empty' 1 '' 1

row_start
printf 'gh: HTTP 502\n' | stub_default_branch 1
run_sut bash "$SUT"
assert_row 'api-call-fails' 1 '' 1

harness_exit "$failed" "$total"
