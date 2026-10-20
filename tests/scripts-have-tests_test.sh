#!/usr/bin/env bash
# Tests tests/scripts-have-tests.sh — the coverage gate that fails the suite
# when a script lands under skills/*/scripts/, tools/, hooks/, or scripts/ with
# no test file.
#
# Cases 0 and 1 run the gate against the *real* repository tree. They are the
# gate: they are what turns red when an untested script lands, and they are how
# the gate reaches `make test` without a Makefile or workflow change —
# run.sh collects this file, this file runs the gate.
#
# Every other case drives the gate against a synthetic miniature repository under
# $HARNESS_TMP: <root>/skills/<skill>/scripts/..., <root>/tools/...,
# <root>/hooks/..., <root>/scripts/..., and <root>/tests/... built to order. A synthetic tree rather than the real one
# because the conditions under test — an empty enumeration, an unreadable
# subdirectory, an empty test file — cannot be produced in the real tree without
# either committing them or leaving the checkout dirty.
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
# mk_file <root> <path-relative-to-root>
mk_file() {
  mkdir -p "$1/$(dirname -- "$2")"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/$2"
}

# mk_script <root> <skill> <name>
mk_script() { mk_file "$1" "skills/$2/scripts/$3"; }

# mk_test <root> <skill> <name>   — <name> is the test file's own basename
mk_test() { mk_file "$1" "tests/$2/$3"; }

# mk_hook <root> <name>  — <name> is relative to hooks/, may contain slashes
mk_hook() { mk_file "$1" "hooks/$2"; }

# mk_hook_test <root> <name>  — <name> is the test file's own basename under tests/hooks/
mk_hook_test() { mk_file "$1" "tests/hooks/$2"; }

# mk_tool <root> <name>  — <name> is relative to tools/, may contain slashes
mk_tool() { mk_file "$1" "tools/$2"; }

# mk_tool_test <root> <name>  — <name> is the test file's own basename under tests/tools/
mk_tool_test() { mk_file "$1" "tests/tools/$2"; }

# mk_root_script <root> <name>  — <name> is relative to scripts/, may contain slashes
mk_root_script() { mk_file "$1" "scripts/$2"; }

# mk_root_test <root> <name>  — <name> is the test file's own basename under tests/
mk_root_test() { mk_file "$1" "tests/$2"; }

# Each returns a fresh synthetic repo root. The shape mirrors the real one
# because the gate derives skills, tools, hooks, scripts, and tests from the root it is handed.
# A covered hook, a covered tool and a covered root script are planted here so
# existing cases do not fail the independent empty-hooks, empty-tools and
# empty-root-scripts guards once the gate lists those roots.
tree_new() {
  local root
  root="$(mktemp -d "${HARNESS_TMP}/tree.XXXXXX")"
  mkdir -p "${root}/skills" "${root}/tests"
  mk_hook "$root" session-start
  mk_hook_test "$root" session-start_test.sh
  mk_tool "$root" helper.sh
  mk_tool_test "$root" helper_test.sh
  mk_root_script "$root" planted.sh
  mk_root_test "$root" planted_test.sh
  printf '%s\n' "$root"
}

# check_stderr_has <label> <needle>
# A file-local assertion, the way absorb-base_test.sh has check_contains:
# the rows here hold the gate to something it must say on stderr, and inlining
# the grep-and-report at each of them buried the needle — the one
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
# The baseline the other synthetic cases are read against: one skill script
# with a non-empty test file, plus the planted hook, tool and root script, exit
# 0, and the counts on stdout byte-for-byte.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'covered: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'covered: stdout' \
  'scripts-have-tests: 4 script(s), 4 with tests\n'; then fails_here=1; fi
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
# segment is what rules it out. Count 4 = one skill + planted session-start +
# planted tool + planted root script.
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
  'scripts-have-tests: 4 script(s), 4 with tests\n'; then fails_here=1; fi
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

# --- case 11: an uncovered hook is named ------------------------------------
# Reproduction of yowcow/dude#326: a new hook script with no test must turn
# the gate red. Content has no shebang and no execute bit — selection is by
# position; a shebang or -x matcher would drop this file and the row would
# go green. Extensionless name, same pairing as hooks/session-start.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
printf 'echo extra\n' >"${root}/hooks/extra"
run_sut bash "$SUT" "$root"
if ! check_eq 'uncovered hook: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'uncovered hook: names the script' 'no test for hooks/extra'; then fails_here=1; fi
if ! check_stderr_has 'uncovered hook: names the expected test path' 'tests/hooks/extra_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 12: an empty hooks enumeration is an error even when skills are green
# A broken hooks selector and a fully covered skills tree are otherwise the
# same green — the defect this change exists to close.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rm -f "${root}/hooks/session-start"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'no hook found: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no hook found: broken enumeration' 'the enumeration is broken'; then fails_here=1; fi
if ! check_stderr_has 'no hook found: names hooks root' "${root}/hooks"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 13: a missing hooks/ is a listing failure, not an empty tree ------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rm -rf "${root}/hooks"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'no hooks dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no hooks dir: listing failed' 'the tree was not fully read'; then fails_here=1; fi
if ! check_stderr_has 'no hooks dir: names hooks root' "${root}/hooks"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 14: hooks.json is not enumerated ----------------------------------
# JSON manifest, already under `make manifest`. If it were listed, the
# expected test would be tests/hooks/hooks.json_test.sh (${rel%.sh} does not
# strip .json) and this row would go red. Count 4 = one skill + planted
# session-start + planted tool + planted root script; json must not bump it to 5.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
printf '{}\n' >"${root}/hooks/hooks.json"
run_sut bash "$SUT" "$root"
if ! check_eq 'hooks.json ignored: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'hooks.json ignored: stdout' \
  'scripts-have-tests: 4 script(s), 4 with tests\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 15: a nested hook gets a nested expected test path ----------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_hook "$root" 'lib/h.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'nested hook: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'nested hook: names the nested expected test path' 'tests/hooks/lib/h_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 16: a symlinked hook is enumerated, not silently exempt -----------
# Same door as case 10. The planted session-start plus a covered skill are
# load-bearing: if find uses -type f, the symlink is dropped, both remaining
# files are covered, and the row goes green.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
ln -s /nonexistent/elsewhere.sh "${root}/hooks/sneaky.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked hook: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked hook: names the symlink' 'no test for hooks/sneaky.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 17: an empty hook test file is not coverage -----------------------
# Same -f/-s/-r check as skills. A hooks loop that only tests presence
# would go green here.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_hook "$root" extra.sh
mkdir -p "${root}/tests/hooks"
: >"${root}/tests/hooks/extra_test.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'empty hook test file: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'empty hook test file: names the script' 'no test for hooks/extra.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 18: an uncovered tool is named ------------------------------------
# tools/ is the shared position: a file landing here with no test under
# tests/tools/ must turn the gate red, naming both paths.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_tool "$root" extra.sh
run_sut bash "$SUT" "$root"
if ! check_eq 'uncovered tool: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'uncovered tool: names the script' 'no test for tools/extra.sh'; then fails_here=1; fi
if ! check_stderr_has 'uncovered tool: names the expected test path' 'tests/tools/extra_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 19: an empty tools enumeration is an error even when the rest is green
# A broken tools selector and fully covered skills+hooks trees are otherwise
# the same green — the defect case 12 closed for hooks.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rm -f "${root}/tools/helper.sh"
rm -f "${root}/tests/tools/helper_test.sh"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'no tool found: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no tool found: broken enumeration' 'the enumeration is broken'; then fails_here=1; fi
if ! check_stderr_has 'no tool found: names tools root' "${root}/tools"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 20: a missing tools/ is a listing failure, not an empty tree ------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rm -rf "${root}/tools"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'no tools dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no tools dir: listing failed' 'the tree was not fully read'; then fails_here=1; fi
if ! check_stderr_has 'no tools dir: names tools root' "${root}/tools"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 21: a nested tool gets a nested expected test path ----------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_tool "$root" 'lib/h.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'nested tool: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'nested tool: names the nested expected test path' 'tests/tools/lib/h_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 22: a symlinked tool is enumerated, not silently exempt -----------
# Same door as cases 10 and 16.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
ln -s /nonexistent/elsewhere.sh "${root}/tools/sneaky.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked tool: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked tool: names the symlink' 'no test for tools/sneaky.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 23: an empty tool test file is not coverage -----------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_tool "$root" extra.sh
mkdir -p "${root}/tests/tools"
: >"${root}/tests/tools/extra_test.sh"
run_sut bash "$SUT" "$root"
if ! check_eq 'empty tool test file: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'empty tool test file: names the script' 'no test for tools/extra.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 24: a top-level scripts/ file needs a test -------------------------
# The gate enumerated skills/*/scripts/, tools/ and hooks/ but not scripts/,
# where bump.sh lives: an untested file there was reported as nothing at all.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_root_script "$root" 'untested.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'root script: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'root script: names the script' 'no test for scripts/untested.sh'; then fails_here=1; fi
if ! check_stderr_has 'root script: names the expected test path' 'tests/untested_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 25: a missing top-level scripts/ is a listing failure --------------
# Same rule as the other three roots: "could not ask" is not "nothing to cover".
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
rm -rf "${root}/scripts"
run_sut bash "$SUT" "$root"
if ! check_eq 'no scripts dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no scripts dir: listing failed' 'the tree was not fully read'; then fails_here=1; fi
if ! check_stderr_has 'no scripts dir: names the root' "${root}/scripts"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 26: an empty top-level scripts/ enumeration is an error even when the rest is green
# A broken root-scripts selector and fully covered skills+hooks+tools trees are
# otherwise the same green — the defect case 12 closed for hooks and case 19 for
# tools. The directory still exists here; only the last planted file is gone.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rm -f "${root}/scripts/planted.sh" "${root}/tests/planted_test.sh"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'no root script found: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no root script found: broken enumeration' 'the enumeration is broken'; then fails_here=1; fi
if ! check_stderr_has 'no root script found: names scripts root' "${root}/scripts"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 27: a symlinked scripts/ directory is refused ----------------------
# find lists the link but never descends, so every script inside it is invisible
# and the visible half reports itself fully covered — hence the second covered
# skill, without which the empty enumeration guard would fire instead and this
# case would pass for the wrong reason. Refused rather than followed: -L would
# let the enumeration leave the tree and loop back into it.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_script "$root" beta 'b.sh'
mk_test "$root" beta 'b_test.sh'
mv "${root}/skills/alpha/scripts" "${root}/skills/alpha/real"
ln -s real "${root}/skills/alpha/scripts"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked scripts dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked scripts dir: names it' \
  'skills/alpha/scripts is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 28: a symlinked hooks/ subdirectory is refused ---------------------
# The same predicate in the hooks loop: the hole is not skills-only. Before the
# fix this tree was already red, but as `no test for hooks/lib` — the directory
# itself charged with being an untested script. The assertion is on the message,
# so the cause is what this case pins.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_file "$root" hooked/h.sh
ln -s ../hooked "${root}/hooks/lib"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked hooks dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked hooks dir: names it' \
  'hooks/lib is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 29: a symlinked directory outside scripts/ is not refused ---------
# The skills loop enumerates only skills/<skill>/scripts/**, so a link to a
# references/ directory holds nothing this gate reads; refusing it would fail a
# tree the gate has no business reading.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mkdir -p "${root}/elsewhere"
printf 'prose\n' >"${root}/elsewhere/base.md"
ln -s ../../elsewhere "${root}/skills/alpha/references"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked references dir: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 30: a symlinked skills/<skill> directory is refused ----------------
# find lists the skill directory and never descends, so its scripts/ is
# invisible while the visible skills report full coverage — the same hole as
# case 27 one level up.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_file "$root" elsewhere/beta/scripts/hidden.sh
ln -s ../elsewhere/beta "${root}/skills/beta"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked skill dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked skill dir: names it' \
  'skills/beta is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 31: two scripts that map to one test path are an error -------------
# ${rel%.sh} makes `foo` and `foo.sh` want the same file, so one test counts as
# coverage for both and the second script is never separately exercised.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'foo'
mk_script "$root" alpha 'foo.sh'
mk_test "$root" alpha 'foo_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'test path collision: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'test path collision: names both and the path' \
  'skills/alpha/scripts/foo and skills/alpha/scripts/foo.sh share the expected test path tests/alpha/foo_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 32: the same collision under hooks/ -------------------------------
# The rule lives in one helper called from every loop, not in the skills loop.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_hook "$root" 'foo'
mk_hook "$root" 'foo.sh'
mk_hook_test "$root" 'foo_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'hook test path collision: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'hook test path collision: names both and the path' \
  'hooks/foo and hooks/foo.sh share the expected test path tests/hooks/foo_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 33: the same collision across roots -------------------------------
# The expected path mirrors the script's position in the tree, so a root script
# under scripts/tools/ lands on the tools/ path. tools/helper.sh is planted by
# tree_new and already covered; only the root script is added, so the one test
# would count twice and the second script is exercised by nothing.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_root_script "$root" 'tools/helper.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'cross-root test path collision: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'cross-root test path collision: names both and the path' \
  'tools/helper.sh and scripts/tools/helper.sh share the expected test path tests/tools/helper_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 34: a symlinked tools/ subdirectory is refused ---------------------
# The same predicate in the tools loop. tools/helper.sh is planted by tree_new
# and already covered, so the refusal cannot be the empty-enumeration guard
# firing instead.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_file "$root" elsewhere/lib/x.sh
ln -s ../elsewhere/lib "${root}/tools/lib"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked tools dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked tools dir: names it' \
  'tools/lib is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 35: a symlinked scripts/ subdirectory is refused -------------------
# The same predicate in the root-scripts loop. scripts/planted.sh is planted by
# tree_new and already covered, so the refusal cannot be the empty enumeration.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_file "$root" elsewhere/slib/y.sh
ln -s ../elsewhere/slib "${root}/scripts/slib"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked root-script dir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked root-script dir: names it' \
  'scripts/slib is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 36: a symlinked subdirectory under a skill's scripts/ is refused ---
# The third branch of the skills predicate, after the scripts/ directory itself
# (case 27) and the skill directory (case 30). A skill that factors a shared
# subdirectory under scripts/ would otherwise hide every script in it while the
# covered sibling reports the subtree green.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_file "$root" elsewhere/lib/x.sh
ln -s ../../../elsewhere/lib "${root}/skills/alpha/scripts/lib"
run_sut bash "$SUT" "$root"
if ! check_eq 'symlinked scripts subdir: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'symlinked scripts subdir: names it' \
  'skills/alpha/scripts/lib is a symlink to a directory'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
