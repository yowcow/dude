#!/usr/bin/env bash
# Tests tests/scripts-have-tests.sh — the coverage gate that fails the suite
# when a script lands under skills/*/scripts/ with no test file.
#
# Cases 0 and 1 run the gate against the *real* repository tree. They are the
# gate: they are what turns red when an untested script lands, and they are how
# the gate reaches `make test` without a Makefile or workflow change —
# run.sh collects this file, this file runs the gate.
#
# Every other case drives the gate against a synthetic miniature repository under
# $HARNESS_TMP: <root>/skills/<skill>/scripts/... and <root>/tests/...
# built to order. A synthetic tree rather than the real one because the
# conditions under test — an empty enumeration, an unreadable subdirectory, an
# empty test file — cannot be produced in the real tree without either
# committing them or leaving the checkout dirty.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

# The gate under test. Overridable by $SUT for RED verification, same as every
# other file in this suite.
SUT="${SUT:-${REPO_ROOT}/tests/scripts-have-tests.sh}"

# Normalised to an absolute path, which no other file in this suite needs to do.
# Case 1 runs the gate under `env -C /`, so a relative $SUT — and relative is the
# natural spelling once the RED copy sits beside the gate, `SUT=tests/mutA.sh`
# — resolves against / and exits 127 there while every other case honours it.
# Measured while reviewing this: a mutation whose only detectable effect was in
# case 5 failed cases 1 and 5, and the extra failure had nothing to do with the
# mutation. A RED verification is read by its failing case labels, so one
# unrelated label in the list is enough to misattribute the result.
#
# run.sh has already refused a $SUT that is not a readable non-empty file before
# this file runs, so this only ever normalises a path that exists.
SUT="$(CDPATH='' cd -- "$(dirname -- "$SUT")" && pwd)/${SUT##*/}"

failed=0
total=0

# --- fixture builders --------------------------------------------------------
# Each returns a fresh synthetic repo root. The shape mirrors the real one
# because the gate derives skills and tests from the root it is handed; a
# flatter fixture would test a path derivation nobody uses.
tree_new() {
  local root
  root="$(mktemp -d "${HARNESS_TMP}/tree.XXXXXX")"
  mkdir -p "${root}/skills" "${root}/tests"
  printf '%s\n' "$root"
}

# mk_script <root> <skill> <name>
mk_script() {
  mkdir -p "$1/skills/$2/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/skills/$2/scripts/$3"
}

# mk_test <root> <skill> <name>   — <name> is the test file's own basename
mk_test() {
  mkdir -p "$1/tests/$2"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/tests/$2/$3"
}

# check_stderr_has <label> <needle>
# A file-local assertion, the way absorb-base_test.sh has check_contains:
# eight rows here hold the gate to something it must say on stderr, and
# inlining the grep-and-report at each of them buried the needle — the one
# part that differs — in boilerplate. The needle stays at the call site, so
# what a row asserts is still read there rather than here.
#
# -F because every needle is a literal path or message fragment, and -- because
# a needle is free to begin with a dash.
check_stderr_has() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$SUT_STDERR"; then
    return 0
  fi
  printf 'FAIL %s: stderr does not contain [%s]\n  got: %s\n' \
    "$label" "$needle" "$(head -c 600 "$SUT_STDERR")"
  return 1
}

# --- case 0: the real tree is clean ------------------------------------------
# No argument, so the gate anchors on its own location and reads the real
# skills and tests. This is the row that fails when a script lands with no
# test.
total=$((total + 1))
run_sut bash "$SUT"
if ! check_eq 'real tree: exit' 0 "$SUT_STATUS"; then
  printf 'stdout: %s\nstderr: %s\n' "$(cat "$SUT_STDOUT")" "$(cat "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# --- case 1: the real tree is clean from any cwd -----------------------------
# The default root is derived from $BASH_SOURCE, never the cwd. A cwd-relative
# derivation would find nothing from / and report success having checked no file
# — the failure tests/lint.sh's header records.
total=$((total + 1))
run_sut env -C / bash "$SUT"
if ! check_eq 'real tree from /: exit' 0 "$SUT_STATUS"; then
  printf 'stdout: %s\nstderr: %s\n' "$(cat "$SUT_STDOUT")" "$(cat "$SUT_STDERR")"
  failed=$((failed + 1))
fi

# --- case 2: a covered script is a green --------------------------------------
# The baseline the other synthetic cases are read against: one script with a
# non-empty test file, exit 0, and the counts on stdout byte-for-byte.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'covered: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'covered: stdout' \
  'scripts-have-tests: 1 script(s), 1 with tests\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 3: an uncovered script is named -------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'uncovered: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'uncovered: names the script' 'no test for skills/alpha/scripts/a.sh'; then fails_here=1; fi
if ! check_stderr_has 'uncovered: names the expected test path' 'tests/alpha/a_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 4: an empty test file is not coverage -----------------------------
# run.sh collects it and `bash <empty>` exits 0, so counting it would make the
# gate green over a file with no detection power at all.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mkdir -p "${root}/tests/alpha"
: >"${root}/tests/alpha/a_test.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'empty test file: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'empty test file: names the script' 'no test for skills/alpha/scripts/a.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 5: an empty enumeration is an error -------------------------------
# A broken enumerator and a fully-covered tree are otherwise the same green.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
run_sut bash "$SUT" "$root"
if ! check_eq 'no script found: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no script found' 'the enumeration is broken'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 6: a missing skills is a listing failure, not an empty tree ----
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rmdir "${root}/skills"
run_sut bash "$SUT" "$root"
if ! check_eq 'no skills: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no skills' 'the tree was not fully read'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 7: a partially-readable tree is a failure, never a green ----------
# Measured in tests/lint.sh and tests/run.sh: a chmod-000 subdirectory
# makes `find` die partway, and a loop fed by process substitution reports the
# files it did collect as a complete, passing run.
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mkdir -p "${root}/skills/beta/scripts/hidden"
printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/beta/scripts/hidden/b.sh"
chmod 000 "${root}/skills/beta/scripts/hidden"
if [ -r "${root}/skills/beta/scripts/hidden" ]; then
  # chmod 000 does not stop uid 0, so under root `find` reads the directory and
  # the gate is right not to fail. Announced rather than silent: a case that
  # passes while testing nothing is what this suite exists to catch.
  printf 'skip unreadable subdirectory: chmod 000 left it readable as uid %s — find really can read it here\n' "$(id -u)"
else
  total=$((total + 1))
  fails_here=0
  run_sut bash "$SUT" "$root"
  if ! check_eq 'unreadable subdirectory: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
  if ! check_stderr_has 'unreadable subdirectory' 'the tree was not fully read'; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi
fi
chmod 755 "${root}/skills/beta/scripts/hidden" 2>/dev/null || true

# --- case 8: a nested script gets a nested expected test path --------------
# `find` is not depth-limited, so a script added under scripts/<subdir>/ is
# enumerated rather than silently exempt.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mkdir -p "${root}/skills/alpha/scripts/lib"
printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/alpha/scripts/lib/h.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'nested script: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'nested script: names the nested expected test path' 'tests/alpha/lib/h_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 9: a file outside a scripts/ directory is not enumerated ---------
# skills/<skill>/references/*.md and SKILL.md are not scripts, and demanding
# a test for them would make the gate unusable. The references/scripts/ file is
# the sharp half: a `*/scripts/*` glob would match it, and the second path
# segment is what rules it out.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mkdir -p "${root}/skills/alpha/references/scripts"
printf 'prose\n' >"${root}/skills/alpha/references/base.md"
printf 'prose\n' >"${root}/skills/alpha/SKILL.md"
printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/alpha/references/scripts/deep.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'non-script files: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'non-script files: stdout' \
  'scripts-have-tests: 1 script(s), 1 with tests\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 10: a symlinked script is enumerated, not silently exempt ---------
# `find -type f` classifies a symlink by the link, so a script landing under
# scripts/ as a symlink is dropped from the enumeration entirely: never checked
# for a test, never reported as needing one. Measured on the first version of
# this gate — an untested symlink beside one covered regular script was
# reported as one script, one with tests, and exit 0, with the symlink named
# nowhere. That is the gate's own failure mode, so it is enumerated instead.
#
# The covered regular script is load-bearing in this fixture: with the symlink
# alone the tree enumerates empty and the run fails loudly on that guard
# instead, which would let the bypass pass this case for the wrong reason.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
ln -s /nonexistent/elsewhere.sh "${root}/skills/alpha/scripts/sneaky.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked script: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked script: names the symlink' 'no test for skills/alpha/scripts/sneaky.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
