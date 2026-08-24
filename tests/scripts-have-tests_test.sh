#!/usr/bin/env bash
# Tests tests/scripts-have-tests.sh — the coverage gate that fails the suite
# when a script lands under skills/*/scripts/ with no test file and no
# allowlist line.
#
# Cases 0 and 1 run the gate against the *real* repository tree. They are the
# gate: they are what turns red when an untested script lands, and they are how
# the gate reaches `make test` without a Makefile or workflow change —
# run.sh collects this file, this file runs the gate.
#
# Every other case drives the gate against a synthetic miniature repository under
# $HARNESS_TMP: <root>/skills/<skill>/scripts/... and <root>/tests/...
# built to order. A synthetic tree rather than the real one because the
# conditions under test — an empty enumeration, a stale allowlist entry, an
# unreadable subdirectory — cannot be produced in the real tree without either
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
# case 11 failed cases 1 and 11, and the extra failure had nothing to do with the
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

# mk_allowlist <root>   — content on stdin
mk_allowlist() {
  mkdir -p "$1/tests"
  cat >"$1/tests/scripts-have-tests.allowlist"
}

# check_stderr_has <label> <needle>
# A file-local assertion, the way absorb-base_test.sh has assert_row and
# check_contains: thirteen rows here hold the gate to something it must say on
# stderr, and inlining the grep-and-report at each of them buried the needle —
# the one part that differs — in boilerplate. The needle stays at the call site,
# so what a row asserts is still read there rather than here.
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
# skills, tests and allowlist. This is the row that fails when a script
# lands with neither a test nor an allowlist line.
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

# --- case 2: covered script, no allowlist file -------------------------------
# An absent allowlist means "no exemptions", not an error: the gate is permanent
# and must stay green on the day the last entry goes.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'covered, no allowlist: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'covered, no allowlist: stdout' \
  'scripts-have-tests: 1 script(s), 1 with tests, 0 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 3: uncovered script, no allowlist file -----------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
run_sut bash "$SUT" "$root"
if ! check_eq 'uncovered: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'uncovered: names the script' 'no test for skills/alpha/scripts/a.sh'; then fails_here=1; fi
if ! check_stderr_has 'uncovered: names the expected test path' 'tests/alpha/a_test.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 4: uncovered but allowlisted ---------------------------------------
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_allowlist "$root" <<'AL'
skills/alpha/scripts/a.sh
AL
run_sut bash "$SUT" "$root"
if ! check_eq 'exempted: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'exempted: stdout' \
  'scripts-have-tests: 1 script(s), 0 with tests, 1 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 5: allowlist entry naming no existing script -----------------------
# An exemption must not outlive the script it exempts.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_allowlist "$root" <<'AL'
skills/alpha/scripts/gone.sh
AL
run_sut bash "$SUT" "$root"
if ! check_eq 'stale entry: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'stale entry: names the entry' 'skills/alpha/scripts/gone.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 6: allowlist entry for a script that now has a test ----------------
# Not an error, only unnecessary. Making it an error would force a PR that lands
# a test to also delete a line it does not own — TODO items 2-10 each delete only
# their own group's lines, and #184/#186/#187/#188 delete none at all.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_allowlist "$root" <<'AL'
skills/alpha/scripts/a.sh
AL
run_sut bash "$SUT" "$root"
if ! check_eq 'unnecessary entry: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'unnecessary entry: stdout' \
  'scripts-have-tests: allowlist entry no longer needed (the script has a test): skills/alpha/scripts/a.sh\nscripts-have-tests: 1 script(s), 1 with tests, 0 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 7: comment and blank lines are not entries (covered tree) ----------
# The group separators survive the last deletion, so reading one as a name would
# make the gate fail on its own allowlist via case 5's rule.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mk_allowlist "$root" <<'AL'
# item 2: alpha

#   item 3: beta

AL
run_sut bash "$SUT" "$root"
if ! check_eq 'comments only, covered: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'comments only, covered: stdout' \
  'scripts-have-tests: 1 script(s), 1 with tests, 0 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 8: a commented-out entry grants no exemption -----------------------
# A different guard from case 7's, and not detected by the same mutation: with
# the comment skip removed outright this case still passes, because
# `# skills/...` read as a literal entry does not match the bare path either
# (measured while reviewing this plan). Case 7 is what detects a missing skip.
# What this case catches is a gate that "handles comments" by stripping the
# leading `#` and keeping the rest, which would silently exempt every
# commented-out line anyone left behind.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_allowlist "$root" <<'AL'
# skills/alpha/scripts/a.sh
AL
run_sut bash "$SUT" "$root"
if ! check_eq 'commented-out entry: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'commented-out entry: names the script' 'no test for skills/alpha/scripts/a.sh'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 9: surrounding whitespace on an entry still exempts ----------------
# Padded on *both* sides, and written with printf rather than a heredoc so the
# trailing spaces are visible in the source and cannot be lost to an editor that
# strips them. One entry carrying both is what holds both halves of the trim:
# drop either one and this entry stops matching, becomes a stale entry, and the
# row fails. A leading-only fixture measured nothing about the trailing trim —
# a gate with that half removed passed it (measured in review).
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
printf '  %s   \n' 'skills/alpha/scripts/a.sh' | mk_allowlist "$root"
run_sut bash "$SUT" "$root"
if ! check_eq 'padded entry: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'padded entry: stdout' \
  'scripts-have-tests: 1 script(s), 0 with tests, 1 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 10: an empty test file is not coverage -----------------------------
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

# --- case 11: an empty enumeration is an error -------------------------------
# A broken enumerator and a fully-covered tree are otherwise the same green.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
run_sut bash "$SUT" "$root"
if ! check_eq 'no script found: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no script found' 'the enumeration is broken'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 12: a missing skills is a listing failure, not an empty tree ----
total=$((total + 1))
fails_here=0
root="$(tree_new)"
rmdir "${root}/skills"
run_sut bash "$SUT" "$root"
if ! check_eq 'no skills: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'no skills' 'the tree was not fully read'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 13: a partially-readable tree is a failure, never a green ----------
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

# --- case 14: an allowlist that exists but cannot be read is an error --------
# "No exemptions" and "could not ask" must not be the same answer: an unreadable
# allowlist read as absent would exempt nothing, and every exempted script would
# be reported as uncovered.
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_allowlist "$root" <<'AL'
skills/alpha/scripts/a.sh
AL
chmod 000 "${root}/tests/scripts-have-tests.allowlist"
if [ -r "${root}/tests/scripts-have-tests.allowlist" ]; then
  printf 'skip unreadable allowlist: chmod 000 left it readable as uid %s — the gate is right to read it here\n' "$(id -u)"
else
  total=$((total + 1))
  fails_here=0
  run_sut bash "$SUT" "$root"
  if ! check_eq 'unreadable allowlist: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
  if ! check_stderr_has 'unreadable allowlist' 'cannot be read'; then fails_here=1; fi
  if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi
fi
chmod 644 "${root}/tests/scripts-have-tests.allowlist" 2>/dev/null || true

# --- case 15: a nested script gets a nested expected test path --------------
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

# --- case 16: a file outside a scripts/ directory is not enumerated ---------
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
  'scripts-have-tests: 1 script(s), 1 with tests, 0 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 17: a symlinked script is enumerated, not silently exempt ---------
# `find -type f` classifies a symlink by the link, so a script landing under
# scripts/ as a symlink is dropped from the enumeration entirely: never checked
# for a test, never reported as needing one. Measured on the first version of
# this gate — an untested symlink beside one covered regular script produced
# `1 script(s), 1 with tests, 0 exempted` and exit 0, with the symlink named
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

# --- case 18: two entries cannot combine into one exemption -----------------
# A script whose name contains a literal newline cannot be written as a single
# allowlist line at all — `read -r` splits there — so it must always come back
# as uncovered. The first version of this gate joined the entries into one
# newline-delimited string and asked whether it contained `\n<key>\n`, which two
# *adjacent* entries reconstruct between them: `skills/alpha/scripts/weird`
# followed by `name.sh` matched the key `skills/alpha/scripts/weird\nname.sh`
# although no single line named it. Measured on that version: the script was
# treated as exempted and `no test for` was never printed for it, while the two
# fragments were each reported as stale entries — output that points a reader at
# two entries to delete rather than at the untested script.
#
# The exit status alone does not separate the two versions (both exit 1, the
# broken one only because the fragments trip the stale-entry scan), so the row
# asserts the report: the script is named, and the problem count includes it.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mkdir -p "${root}/skills/alpha/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/skills/alpha/scripts/weird"$'\n'"name.sh"
mk_allowlist "$root" <<'AL'
skills/alpha/scripts/weird
name.sh
AL
run_sut bash "$SUT" "$root"
if ! check_eq 'split entry: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'split entry: the script is named, not exempted' 'no test for'; then fails_here=1; fi
if ! check_stderr_has 'split entry: the script is counted' '3 problem(s)'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 19: a non-regular file at the allowlist path is refused cleanly ----
# `-r` is true for a directory, so the readability guard alone lets one through
# and the `done <"$ALLOWLIST"` redirection then fails inside the loop. Measured:
# `read error: 0: Is a directory`, immediately followed by `line: unbound
# variable` — `read` never assigned it, and `|| [ -n "$line" ]` reads it under
# `set -u`. The exit status stays non-zero, so this was never a false green, but
# the gate abandoned its own contract for two raw bash errors, and one of them is
# an unbound-variable abort in a script that deliberately runs without `set -e`.
# The row keys on the designed message rather than on the exit status, because
# only the message separates the two versions.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mkdir -p "${root}/tests/scripts-have-tests.allowlist"
run_sut bash "$SUT" "$root"
if ! check_eq 'directory allowlist: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_stderr_has 'directory allowlist' 'cannot be read'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 20: a zero-byte allowlist is "no exemptions", not an error --------
# The third spelling of "no exemptions", after case 2's absent file and case 7's
# comments-only file. The issue names all three as success states, and this is
# the one where the reading loop runs against a file with nothing in it at all.
#
# It also pins the `read`-at-EOF half of the `|| [ -n "$line" ]` idiom. A review
# read that as an unbound-variable hazard under `set -u`; measured, it is not —
# bash's `read` assigns the variable the empty string at EOF, so the loop exits
# cleanly (the directory case that *does* abort, case 19, gets there through a
# read *error*, where nothing is assigned). This row is what would notice if that
# ever stopped being true, or if an empty file were ever made an error.
total=$((total + 1))
fails_here=0
root="$(tree_new)"
mk_script "$root" alpha 'a.sh'
mk_test "$root" alpha 'a_test.sh'
mkdir -p "${root}/tests"
: >"${root}/tests/scripts-have-tests.allowlist"
run_sut bash "$SUT" "$root"
if ! check_eq 'zero-byte allowlist: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'zero-byte allowlist: stdout' \
  'scripts-have-tests: 1 script(s), 1 with tests, 0 exempted by the allowlist\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
