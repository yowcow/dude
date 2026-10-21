#!/usr/bin/env bash
# The coverage gate: every script under skills/*/scripts/, every file under
# tools/, every file under hooks/ except hooks.json, and every file under the
# top-level scripts/ must have a test file under tests/ (tests/scripts/ for the last).
# Usage: scripts-have-tests.sh [<repo-root>]
#
# Why this exists: without it a script can land under skills/*/scripts/,
# tools/, hooks/, or the repository-root scripts/ with no test, nobody observes
# the absence, and the suite reports green — the amplifier #180 identified
# (nobody is running the code) reappearing through a door the per-script tests
# do not cover. The gate is permanent: it stays after coverage is complete,
# because the property it holds is about the *next* script, not the current ones.
#
# It is a script rather than a check inlined in scripts-have-tests_test.sh for
# the same reason run.sh has run_test.sh: its own conditions — an empty
# enumeration is an error, an empty test file is not coverage — are prose until
# something runs them. As a script it is drivable against synthetic trees and
# against a deliberately broken copy through the suite's documented `SUT=` path.
# What run.sh collects is still the *_test.sh, whose first cases run this gate
# against the real tree, so `make test` runs it with no Makefile or workflow
# change.
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
TOOLS_ROOT="${ROOT}/tools"
HOOKS_ROOT="${ROOT}/hooks"
ROOT_SCRIPTS="${ROOT}/scripts"

# The listing is a plain foreground pipeline into a temp file, not a process
# substitution feeding the loop. In `done < <(find ...)` the producer's exit
# status is unreachable: a `find` that dies partway through the tree — an
# unreadable subdirectory, say — leaves the loop running on whatever it managed
# to emit, and a gate that enumerated half the tree would report the half it read
# as fully covered. Measured in tests/lint.sh and tests/run.sh, which both
# hit this and record it. `pipefail` is what makes the single `if !` sufficient:
# it catches a failure in either stage.
#
LISTING="$(mktemp)"
PAIRS="$(mktemp)"
trap 'rm -f "$LISTING" "$PAIRS"' EXIT

# list_root <dir>
# A root that cannot be read reaches this message rather than the empty
# enumeration, and that is correct — the tree really was not read, so "nothing
# found" would be the wrong diagnosis. `exit 1` here leaves the script, not just
# the call: a root that could not be read is never followed by a report on half
# of it.
# A root that is itself a symlink is named here rather than below, because `find`
# does not descend into its own starting point either: the enumeration comes back
# empty and the empty guard would report a broken listing when the cause is the
# link. Both targets are named, since either one hides the same subtree.
list_root() {
  if [ -L "$1" ]; then
    if [ -d "$1" ]; then
      printf 'scripts-have-tests: %s is a symlink to a directory — its contents cannot be enumerated\n' "${1#"${ROOT}/"}" >&2
    else
      printf 'scripts-have-tests: %s is a symlink whose target is not a directory — nothing is enumerated there\n' "${1#"${ROOT}/"}" >&2
    fi
    exit 1
  fi
  if ! find "$1" \( -type f -o -type l \) -print0 | sort -z >"$LISTING"; then
    printf 'scripts-have-tests: listing %s failed — the tree was not fully read\n' "$1" >&2
    exit 1
  fi
}

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
# dangling link is reported rather than fatal. A link to a directory is visible
# but not descended into, so its contents cannot be enumerated at all; such a
# link is refused outright rather than half-read as an empty tree.
list_root "$SKILLS_ROOT"

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
hidden_dirs=()
dangling=()
while IFS= read -r -d '' abs; do
  rel="${abs#"${SKILLS_ROOT}/"}"
  if [ "$rel" = "$abs" ]; then
    continue
  fi
  # Only where this listing could have descended: the skill directory itself,
  # which find never enters, and the scripts/ subtree this gate reads. A linked
  # references/ directory holds nothing here and stays green.
  if [ -L "$abs" ] && [ -d "$abs" ]; then
    case "${rel#*/}" in
      scripts | scripts/* | "$rel") hidden_dirs+=("skills/${rel}"); continue ;;
    esac
  fi
  # A link whose target is not a directory is dropped by the selection below at
  # those same two positions: `find` lists it, neither case branch takes it, and
  # nothing says the subtree contributed nothing. A link under scripts/ is not
  # this — it is enumerated and reported as untested.
  if [ -L "$abs" ] && [ ! -d "$abs" ]; then
    case "${rel#*/}" in
      scripts | "$rel") dangling+=("skills/${rel}"); continue ;;
    esac
  fi
  case "${rel#*/}" in
    scripts/*) ;;
    *) continue ;;
  esac
  scripts+=("$rel")
done <"$LISTING"

list_root "$HOOKS_ROOT"

hooks=()
while IFS= read -r -d '' abs; do
  rel="${abs#"${HOOKS_ROOT}/"}"
  if [ "$rel" = "$abs" ]; then
    continue
  fi
  if [ -L "$abs" ] && [ -d "$abs" ]; then
    hidden_dirs+=("hooks/${rel}")
    continue
  fi
  if [ "$rel" = "hooks.json" ]; then
    continue
  fi
  hooks+=("$rel")
done <"$LISTING"

# tools/ is the shared position: mechanism every skill may call without
# creating a skill-to-skill edge. Selection is every file under it, by the
# same position rule as hooks/ — a file landing here is a shared tool whether
# or not it carries a shebang, and subdirectories mirror into tests/tools/.
list_root "$TOOLS_ROOT"

tools=()
while IFS= read -r -d '' abs; do
  rel="${abs#"${TOOLS_ROOT}/"}"
  if [ "$rel" = "$abs" ]; then
    continue
  fi
  if [ -L "$abs" ] && [ -d "$abs" ]; then
    hidden_dirs+=("tools/${rel}")
    continue
  fi
  tools+=("$rel")
done <"$LISTING"

# The top-level scripts/ holds repository mechanism that is not a skill's, not a
# shared tool and not a hook — bump.sh is the one there today. It was the last
# position the position rule skipped: an untested file here was reported as
# nothing at all. Every file under it is enumerated, subdirectories mirrored into
# tests/scripts/, by the same position rule as tools/. It has its own namespace
# because tests/ itself also holds tests whose subject is not under scripts/
# (ci_test.sh, skill-deps_test.sh), and a shared one would let those cover it.
list_root "$ROOT_SCRIPTS"

root_scripts=()
while IFS= read -r -d '' abs; do
  rel="${abs#"${ROOT_SCRIPTS}/"}"
  if [ "$rel" = "$abs" ]; then
    continue
  fi
  if [ -L "$abs" ] && [ -d "$abs" ]; then
    hidden_dirs+=("scripts/${rel}")
    continue
  fi
  root_scripts+=("$rel")
done <"$LISTING"

# A link to a directory is listed by find but never descended into, so whatever
# it holds is invisible while the rest of the tree reports itself covered. The
# target is not followed (-L would let the walk leave the tree and loop back in);
# the link is named and refused instead.
if [ "${#hidden_dirs[@]}" -gt 0 ]; then
  for key in "${hidden_dirs[@]}"; do
    printf 'scripts-have-tests: %s is a symlink to a directory — its contents cannot be enumerated\n' "$key" >&2
  done
  exit 1
fi

# A link whose target is not a directory loses its position just as quietly, so
# it is named the same way. Not refused as "to a directory": that would say the
# opposite of what was found.
if [ "${#dangling[@]}" -gt 0 ]; then
  for key in "${dangling[@]}"; do
    printf 'scripts-have-tests: %s is a symlink whose target is not a directory — nothing is enumerated there\n' "$key" >&2
  done
  exit 1
fi

# refuse_empty <count> <path-with-suffix>
# An empty enumeration can only mean the selection above broke: this repository
# has skill scripts, and a gate that reports "nothing to check, all good" is
# indistinguishable from a fully covered tree. That is the "absent" versus
# "could not ask" confusion this suite exists to catch, pointed at the gate
# itself.
refuse_empty() {
  if [ "$1" -eq 0 ]; then
    printf 'scripts-have-tests: no script found under %s — the enumeration is broken\n' "$2" >&2
    exit 1
  fi
}

refuse_empty "${#scripts[@]}" "${SKILLS_ROOT}/*/scripts/"
refuse_empty "${#hooks[@]}" "${HOOKS_ROOT}/"
refuse_empty "${#tools[@]}" "${TOOLS_ROOT}/"
refuse_empty "${#root_scripts[@]}" "${ROOT_SCRIPTS}/"

problems=0
with_tests=0

# claim_test_path <want> <key>
# One test file cannot be two scripts' coverage: ${rel%.sh} makes `foo` and
# `foo.sh` want the same path, which would count one test twice and leave the
# second script exercised by nothing.
claim_test_path() {
  local want="$1" key="$2" other
  other="$(awk -F'\t' -v w="$want" '$1 == w { print $2; exit }' "$PAIRS")"
  if [ -n "$other" ]; then
    printf 'scripts-have-tests: %s and %s share the expected test path %s — one test cannot cover two scripts\n' \
      "$other" "$key" "$want" >&2
    problems=$((problems + 1))
    return
  fi
  printf '%s\t%s\n' "$want" "$key" >>"$PAIRS"
}

# require_test <key> <want>
# Non-empty and readable, not merely present. run.sh collects an empty
# *_test.sh and `bash <empty>` exits 0, so an empty file is a passing test with
# no detection power; counting it as coverage would let exactly the state this
# gate exists to prevent through the front door.
require_test() {
  local key="$1" want="$2" abs_test
  claim_test_path "$want" "$key"
  abs_test="${ROOT}/${want}"
  if [ -f "$abs_test" ] && [ -s "$abs_test" ] && [ -r "$abs_test" ]; then
    with_tests=$((with_tests + 1))
  else
    printf 'scripts-have-tests: no test for %s (expected %s)\n' "$key" "$want" >&2
    problems=$((problems + 1))
  fi
}

for rel in "${scripts[@]}"; do
  skill="${rel%%/*}"
  rest="${rel#*/scripts/}"
  require_test "skills/${rel}" "tests/${skill}/${rest%.sh}_test.sh"
done

for rel in "${hooks[@]}"; do
  require_test "hooks/${rel}" "tests/hooks/${rel%.sh}_test.sh"
done

for rel in "${tools[@]}"; do
  require_test "tools/${rel}" "tests/tools/${rel%.sh}_test.sh"
done

for rel in "${root_scripts[@]}"; do
  require_test "scripts/${rel}" "tests/scripts/${rel%.sh}_test.sh"
done

if [ "$problems" -ne 0 ]; then
  printf 'scripts-have-tests: %s problem(s)\n' "$problems" >&2
  exit 1
fi

printf 'scripts-have-tests: %s script(s), %s with tests\n' \
  "$((${#scripts[@]} + ${#hooks[@]} + ${#tools[@]} + ${#root_scripts[@]}))" "$with_tests"
