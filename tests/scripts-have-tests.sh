#!/usr/bin/env bash
# The coverage gate: every script under skills/*/scripts/ must have a test
# file under tests/.
# Usage: scripts-have-tests.sh [<repo-root>]
#
# Why this exists: without it a script can land under skills/*/scripts/ with
# no test, nobody observes the absence, and the suite reports green — the
# amplifier #180 identified (nobody is running the code) reappearing through a
# door the per-script tests do not cover. The gate is permanent: it stays after
# coverage is complete, because the property it holds is about the *next*
# script, not the current ones.
#
# It is a script rather than a check inlined in scripts-have-tests_test.sh for
# the same reason run.sh has run_test.sh: its own conditions — an empty enumeration
# is an error, an empty test file is not coverage — are prose until something
# runs them. As a
# script it is drivable against synthetic trees and against a deliberately
# broken copy through the suite's documented `SUT=` path. What run.sh collects is
# still the *_test.sh, whose first cases run this gate against the real tree, so
# `make test` runs it with no Makefile or workflow change.
#
# `set -e` is deliberately absent, as in run.sh: this is an accumulating
# reporter, and one uncovered script must not stop it from naming the rest.
set -uo pipefail

HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The root is anchored on this file's own location, never the cwd: `make test`
# runs with cwd at the repository root and a direct invocation from tests/ runs
# with cwd there. A cwd-relative default would find nothing in one of those and
# report success having checked no file — the failure recorded in
# tests/lint.sh's header. The optional argument exists so the test file can
# point the gate at a synthetic tree; it is the same shape, so the derivation
# below is the one under test rather than a second copy of it.
ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(CDPATH='' cd -- "${HERE}/.." && pwd)"
fi

SKILLS_ROOT="${ROOT}/skills"

# The listing is a plain foreground pipeline into a temp file, not a process
# substitution feeding the loop. In `done < <(find ...)` the producer's exit
# status is unreachable: a `find` that dies partway through the tree — an
# unreadable subdirectory, say — leaves the loop running on whatever it managed
# to emit, and a gate that enumerated half the tree would report the half it read
# as fully covered. Measured in tests/lint.sh and tests/run.sh, which both
# hit this and record it. `pipefail` is what makes the single `if !` sufficient:
# it catches a failure in either stage.
#
# A missing skills reaches the same message rather than an empty enumeration,
# and that is correct — the tree really was not read.
LISTING="$(mktemp)"
trap 'rm -f "$LISTING"' EXIT

# Symlinks are enumerated alongside regular files, which is where this parts
# company with tests/lint.sh. That script records leaving symlinks out as a
# deliberate decision, and for a linter it is one: ShellCheck reads a file, and
# following a link out of the tree would let the selection escape the repository
# and turn a dangling link into a hard failure. Here the question is different —
# "did something land in a scripts/ directory" — and `-type f` answers it wrongly,
# because it classifies a symlink by the link. Measured: an untested symlink
# beside one covered regular script was reported as one script, one with tests,
# and exit 0, the symlink named nowhere. That is this gate's own failure mode
# reached through the same door the shebang note below refuses to leave open, so
# a symlink under scripts/ needs a test like anything else.
# The target is never resolved and never read; only visibility is at stake, so a
# dangling link is reported rather than fatal.
if ! find "$SKILLS_ROOT" \( -type f -o -type l \) -print0 | sort -z >"$LISTING"; then
  printf 'scripts-have-tests: listing %s failed — the tree was not fully read\n' "$SKILLS_ROOT" >&2
  exit 1
fi

# Selection is by position in the tree, not by shebang: the question is "did
# something land in a scripts/ directory", and a shebang matcher restricted to
# sh and bash — which is what tests/lint.sh must use, because ShellCheck
# supports only those — would leave a python or perl script under scripts/
# silently exempt. Depth is not limited either, so scripts/<subdir>/x.sh is
# enumerated too; the expected test path mirrors the subdirectory.
#
# The second path segment must be exactly `scripts`, tested after stripping the
# skill segment rather than with a `*/scripts/*` glob: the glob also matches
# skills/<skill>/references/scripts/x.sh, which is not a skill's script
# directory.
scripts=()
while IFS= read -r -d '' abs; do
  rel="${abs#"${SKILLS_ROOT}/"}"
  if [ "$rel" = "$abs" ]; then
    continue
  fi
  case "${rel#*/}" in
    scripts/*) ;;
    *) continue ;;
  esac
  scripts+=("$rel")
done <"$LISTING"

# An empty enumeration can only mean the selection above broke: this repository
# has skill scripts, and a gate that reports "nothing to check, all good" is
# indistinguishable from a fully covered tree. That is the "absent" versus
# "could not ask" confusion this suite exists to catch, pointed at the gate
# itself.
if [ "${#scripts[@]}" -eq 0 ]; then
  printf 'scripts-have-tests: no script found under %s/*/scripts/ — the enumeration is broken\n' "$SKILLS_ROOT" >&2
  exit 1
fi

problems=0
with_tests=0

for rel in "${scripts[@]}"; do
  key="skills/${rel}"
  skill="${rel%%/*}"
  rest="${rel#*/scripts/}"
  want="tests/${skill}/${rest%.sh}_test.sh"
  abs_test="${ROOT}/${want}"
  # Non-empty and readable, not merely present. run.sh collects an empty
  # *_test.sh and `bash <empty>` exits 0, so an empty file is a passing test with
  # no detection power; counting it as coverage would let exactly the state this
  # gate exists to prevent through the front door.
  if [ -f "$abs_test" ] && [ -s "$abs_test" ] && [ -r "$abs_test" ]; then
    with_tests=$((with_tests + 1))
    continue
  fi
  printf 'scripts-have-tests: no test for %s (expected %s)\n' "$key" "$want" >&2
  problems=$((problems + 1))
done

if [ "$problems" -ne 0 ]; then
  printf 'scripts-have-tests: %s problem(s)\n' "$problems" >&2
  exit 1
fi

printf 'scripts-have-tests: %s script(s), %s with tests\n' \
  "${#scripts[@]}" "$with_tests"
