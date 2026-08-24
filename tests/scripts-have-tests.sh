#!/usr/bin/env bash
# The coverage gate: every script under skills/*/scripts/ must have a test
# file under tests/, or a line in tests/scripts-have-tests.allowlist.
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
# the same reason run.sh has run_test.sh: its own conditions — a comment line is
# not an entry, an empty enumeration is an error, a stale entry is an error, an
# empty test file is not coverage — are prose until something runs them. As a
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
TESTS_ROOT="${ROOT}/tests"
ALLOWLIST="${TESTS_ROOT}/scripts-have-tests.allowlist"

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
# beside one covered regular script gave `1 script(s), 1 with tests, 0 exempted`
# and exit 0, the symlink named nowhere. That is this gate's own failure mode
# reached through the same door the shebang note below refuses to leave open, so
# a symlink under scripts/ needs a test or an allowlist line like anything else.
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

# The allowlist. Absent means "no exemptions" and is a success: the gate is
# permanent, so the day the last entry goes must not be the day the gate starts
# failing or has to be removed. Present-but-unreadable is an error, because
# reading it as absent would answer "could not ask" with "nothing there" and
# report every exempted script as uncovered.
#
# Entries are kept as array elements and compared whole, never joined into one
# delimited string and matched by substring. That first version asked whether a
# newline-joined `$ALLOW` contained `\n<key>\n`, which two *adjacent* entries
# reconstruct between them: with a script actually named `weird\nname.sh`, the
# pair of lines `skills/alpha/scripts/weird` and `name.sh` matched its key
# although neither line named it. Measured: the script was reported exempted,
# `no test for` was never printed for it, and the run's stderr pointed at two
# stale entries instead of the untested script. A whole-element `=` cannot be
# assembled out of two elements.
#
# A name carrying a literal newline still cannot be exempted — `read -r` splits
# there, so no single line can spell it — and that is the safe direction: such a
# script is reported as uncovered rather than quietly passed.
allow=()
if [ -e "$ALLOWLIST" ]; then
  # `-f` as well as `-r`, and `-f` is the load-bearing half: `-r` is true for a
  # directory, so a directory at this path walked straight through a guard that
  # only asked about readability, and the `done <"$ALLOWLIST"` redirection then
  # failed inside the loop. Measured: `read error: 0: Is a directory`, then
  # `line: unbound variable` — `read` never assigned it and `|| [ -n "$line" ]`
  # reads it under `set -u`. Never a false green (the exit stayed non-zero), but
  # the gate abandoned its own contract for two raw bash errors, one of them an
  # unbound-variable abort in a script that deliberately runs without `set -e`.
  #
  # A FIFO at that path is the worse half, and `-f` is what refuses it too:
  # opening one for reading blocks until a writer appears, so the `-r`-only guard
  # did not fail at all — it hung. Measured: `timeout 3` had to kill it, exit 124.
  # A gate that never returns cannot be read as pass or fail by anything.
  #
  # The message names readability alone because it stays true for both refusals,
  # the way run.sh's SUT guard words its four.
  if [ ! -f "$ALLOWLIST" ] || [ ! -r "$ALLOWLIST" ]; then
    printf 'scripts-have-tests: %s exists but cannot be read\n' "$ALLOWLIST" >&2
    exit 1
  fi
  # `|| [ -n "$line" ]` so a final line with no trailing newline is still read.
  while IFS= read -r line || [ -n "$line" ]; do
    # Trimmed, so an entry with stray indentation or a trailing space still
    # matches rather than turning into a stale entry the author cannot see.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ -z "$line" ]; then
      continue
    fi
    # Comment lines are not entries. The group separators between TODO items
    # outlive every entry, so reading one as a name would fail the gate on its
    # own allowlist through the stale-entry rule below.
    case "$line" in
      '#'*) continue ;;
    esac
    allow+=("$line")
  done <"$ALLOWLIST"
fi

# The count is checked before expanding the array: `"${allow[@]}"` on an empty
# array is an unbound-variable error under `set -u` before bash 4.4, and an empty
# allowlist is a success state here, not an edge case.
in_allowlist() {
  local entry
  if [ "${#allow[@]}" -eq 0 ]; then
    return 1
  fi
  for entry in "${allow[@]}"; do
    if [ "$entry" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

problems=0
with_tests=0
exempted=0
notes=()

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
    if in_allowlist "$key"; then
      notes+=("scripts-have-tests: allowlist entry no longer needed (the script has a test): ${key}")
    fi
    continue
  fi
  if in_allowlist "$key"; then
    exempted=$((exempted + 1))
    continue
  fi
  printf 'scripts-have-tests: no test for %s (expected %s)\n' "$key" "$want" >&2
  problems=$((problems + 1))
done

# A stale entry is an error: an exemption must not outlive the script it exempts,
# or a rename would silently carry the old script's pass to nothing at all while
# the new name goes unchecked.
if [ "${#allow[@]}" -ne 0 ]; then
  for entry in "${allow[@]}"; do
    found=0
    for rel in "${scripts[@]}"; do
      if [ "skills/${rel}" = "$entry" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      printf 'scripts-have-tests: allowlist names no script under %s/*/scripts/: %s\n' "$SKILLS_ROOT" "$entry" >&2
      problems=$((problems + 1))
    fi
  done
fi

if [ "$problems" -ne 0 ]; then
  printf 'scripts-have-tests: %s problem(s)\n' "$problems" >&2
  exit 1
fi

if [ "${#notes[@]}" -ne 0 ]; then
  printf '%s\n' "${notes[@]}"
fi
printf 'scripts-have-tests: %s script(s), %s with tests, %s exempted by the allowlist\n' \
  "${#scripts[@]}" "$with_tests" "$exempted"
