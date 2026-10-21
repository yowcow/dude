#!/usr/bin/env bash
# Tests tests/run.sh itself — that a `$SUT` that does not name a readable
# non-empty script stops the run before any test file executes (cases 1-5 and
# 10), that an extensionless script still runs (case 11), and that discovery
# collects a symlinked test file, fails on a dangling link, refuses a symlinked
# directory, and descends into subdirectories (cases 6-9).
#
# Why this file exists: a $SUT pointing at a path that isn't there makes every
# `run_sut bash "$SUT"` in the selected test file exit 127, so nearly every row
# FAILs — the same shape a successful RED verification has. Reading that as
# "the test detects the defect" turns a zero-detection-power test into an
# accepted one (#214, measured while implementing #187).
#
# Whether a test actually ran (cases 1-5 and 10) is asserted by the fixture's own
# marker file, not by parsing the runner's output: a refused run under the
# guarded runner prints no summary at all, while the pre-guard runner this file
# is also pointed at for RED verification reaches its usual summary whether or
# not $SUT was honoured.
# No one output-parsing rule holds for both, so only the marker separates
# "refused before running anything" from "ran, whatever the rows did".
#
# The fixture lives under $HARNESS_TMP, which is a bare `mktemp -d` (harness.sh)
# and so sits outside the tree run.sh walks: suite discovery — `find tests
# -name '*_test.sh'` — cannot reach it whatever it is named. Not naming it
# *_test.sh is belt-and-braces for the day a fixture does land under tests.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

# The runner under test. Overridable by $SUT for RED verification, same as
# every other file in this suite; the *child* runner invocations below set
# their own SUT explicitly, so this value never leaks into them.
SUT="${SUT:-${REPO_ROOT}/tests/run.sh}"

failed=0
total=0

# A throwaway test file for the runner to select. It records that it ran, then
# passes, so "did anything run" is a file-existence question. The heredoc is
# quoted, so ${MARKER} reaches the fixture literally and is expanded when the
# fixture runs, from the environment run_case hands it.
FIXTURE="${HARNESS_TMP}/fixture-probe.sh"
MARKER="${HARNESS_TMP}/fixture-ran"
cat >"$FIXTURE" <<'FIX'
#!/usr/bin/env bash
printf 'ran\n' >"${MARKER}"
printf 'ok 1/1 fixture-probe.sh\n'
FIX

# run_case <child-sut> -- runs the runner under test with SUT set to
# <child-sut> and the fixture as the only selected test file.
run_case() {
  rm -f "$MARKER"
  run_sut env "SUT=$1" "MARKER=${MARKER}" bash "$SUT" "$FIXTURE"
}

marker_state() {
  if [ -e "$MARKER" ]; then printf 'ran\n'; else printf 'did-not-run\n'; fi
}

# assert_refused <label> <child-sut> <want-message> -- one rejection case's
# whole verdict: the runner exited 1, no test file ran, and stderr named the
# offending path in the refusal message. The message is a required argument:
# a defaulted one would let a case that forgot it pin no wording at all, the
# same dropped-argument failure assert_row's fourth argument refuses.
#
# File-local rather than in harness.sh: nothing else in the suite has a
# rejection case to assert, and the harness is sourced by every test file.
assert_refused() {
  local label="$1" child_sut="$2" want_message="$3" fails=0
  total=$((total + 1))
  run_case "$child_sut"
  if ! check_eq "${label}: exit" 1 "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${label}: no test file ran" 'did-not-run' "$(marker_state)"; then fails=1; fi
  if ! grep -qF -- "${want_message}: ${child_sut}" "$SUT_STDERR"; then
    printf 'FAIL %s: stderr does not carry the refusal message [%s] naming the path [%s]: %s\n' \
      "$label" "$want_message" "$child_sut" "$(head -c 400 "$SUT_STDERR")"
    fails=1
  fi
  if [ "$fails" -ne 0 ]; then failed=$((failed + 1)); fi
}

# assert_accepted <label> <child-sut> -- the runner exits 0, the fixture ran,
# and the override was reported on stdout.
assert_accepted() {
  local label="$1" child_sut="$2" fails=0
  total=$((total + 1))
  run_case "$child_sut"
  if ! check_eq "${label}: exit" 0 "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${label}: the test file ran" 'ran' "$(marker_state)"; then fails=1; fi
  if ! grep -qF "SUT override in effect: ${child_sut}" "$SUT_STDOUT"; then
    printf 'FAIL %s: the override was not reported: %s\n' "$label" "$(head -c 400 "$SUT_STDOUT")"
    fails=1
  fi
  if [ "$fails" -ne 0 ]; then failed=$((failed + 1)); fi
}

# --- case 1: a SUT that does not exist stops the run --------------------------
missing="${HARNESS_TMP}/no-such-script.sh"
rm -f "$missing"
assert_refused 'missing SUT' "$missing" 'SUT does not name a readable non-empty file'

# --- case 2: an empty SUT file stops the run ---------------------------------
# An empty file exists, so an existence-only guard would let it through, and
# `bash <empty>` exits 0 — the script under test would appear to succeed at
# everything, which is a *green* RED verification: even more misleading.
empty="${HARNESS_TMP}/empty-script.sh"
: >"$empty"
assert_refused 'empty SUT' "$empty" 'SUT does not name a readable non-empty file'

# --- case 3: a real SUT still runs the selected file -------------------------
# The guard must not cost the mechanism it protects, and this is what would
# catch a guard whose condition is inverted.
good="${HARNESS_TMP}/good-script.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$good"
assert_accepted 'valid SUT' "$good"

# --- case 4: an unreadable SUT file stops the run -----------------------------
# A file that exists and is non-empty but cannot be read walks straight through
# an -f/-s guard, and `bash "$SUT"` then exits 126 on every row — the same false
# RED a missing path produces, differing only in what caused it (#217). `test -r`
# is what closes it, and it is the right check rather than merely a sufficient
# one: it asks access(2), which is the same question the `bash "$SUT"` below the
# guard asks.
unreadable="${HARNESS_TMP}/unreadable-script.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$unreadable"
chmod 000 "$unreadable"
if [ -r "$unreadable" ]; then
  # Skipped rather than run, and announced rather than silent. chmod 000 does not
  # stop uid 0, and under root `bash "$SUT"` really can read the file — so a guard
  # that lets it through is behaving correctly, and reporting a FAIL here would
  # charge root's correct behaviour to the script under test. Read permission has
  # no equivalent of the pre-receive hook gitrepo.sh uses to reach "the push was
  # refused" without a mode bit, so there is nothing to substitute. The line is
  # printed because a case that passes while testing nothing is the exact state
  # this suite exists to catch; the count below drops to 4/4, and this line is
  # what says why.
  printf 'skip unreadable SUT: chmod 000 left it readable as uid %s — the guard is right to accept it here\n' "$(id -u)"
else
  assert_refused 'unreadable SUT' "$unreadable" 'SUT does not name a readable non-empty file'
fi

# --- case 5: a SUT that names a directory stops the run -----------------------
# `-s` is true for a directory — a directory's size is non-zero (measured) — so
# an emptiness check alone lets one through, and `bash <dir>` then exits 126 on
# every row. That is the same false RED a missing path produces: it reads as
# "this test cannot detect the defect", and a test with real detection power is
# retired on the strength of it. `-f` in run.sh's guard is what refuses it, and
# this row is what keeps `-f` from being dropped as redundant.
dir_sut="${HARNESS_TMP}/dir-script.sh"
rm -rf "$dir_sut"
mkdir -p "$dir_sut"
assert_refused 'directory SUT' "$dir_sut" 'SUT does not name a readable non-empty file'

# --- case 6: a symlinked test file is collected and run ----------------------
# The gate accepts a symlinked test file as coverage (-f follows the link), so a
# runner that skips it leaves a covered-but-never-run file. The runner under
# test is copied into a synthetic root because discovery walks its own
# directory, which is also what makes the pre-fix copy reproduce the hole.
# `env -u SUT` because a RED run exports SUT for the file under test, and the
# copy would then refuse two selected files for a reason unrelated to discovery.
total=$((total + 1))
fails_here=0
disc="${HARNESS_TMP}/discovery"
mkdir -p "$disc"
cp "$SUT" "$disc/run.sh"
printf '#!/usr/bin/env bash\nprintf "linked ran\\n"\n' >"$disc/linked-target.sh"
ln -s "$disc/linked-target.sh" "$disc/linked_test.sh"
printf '#!/usr/bin/env bash\nprintf "plain ran\\n"\n' >"$disc/plain_test.sh"
run_sut env -u SUT bash "$disc/run.sh"
if ! check_eq 'symlinked test file: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'symlinked test file: both files ran, in sorted order' \
  'linked ran\nplain ran\nall 2 test files passed\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 7: a dangling test-file symlink fails the run ---------------------
# Collected rather than skipped, it reaches `bash` and exits 127 — loud. The
# alternative, dropping it, is the same green the case above forbids.
total=$((total + 1))
fails_here=0
dangle="${HARNESS_TMP}/dangling"
mkdir -p "$dangle"
cp "$SUT" "$dangle/run.sh"
ln -s "${dangle}/nowhere.sh" "$dangle/dangling_test.sh"
run_sut env -u SUT bash "$dangle/run.sh"
if ! check_eq 'dangling test symlink: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'dangling test symlink: counted as a failed file' \
  '1 of 1 test files failed\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 8: a symlinked directory holding a test file is refused -------------
# The gate counts a test through a symlinked directory (-f follows the link)
# while find never descends one, so this file would be covered and never run —
# the case-6 hole one level up. A plain test is planted too, so the pre-fix
# runner goes green on it rather than falling into the zero-file refusal.
total=$((total + 1))
fails_here=0
linktree="${HARNESS_TMP}/linked-dir"
mkdir -p "$linktree/real" "$linktree/tree"
cp "$SUT" "$linktree/tree/run.sh"
printf '#!/usr/bin/env bash\nprintf "hidden ran\\n"\n' >"$linktree/real/hidden_test.sh"
printf '#!/usr/bin/env bash\nprintf "plain ran\\n"\n' >"$linktree/tree/plain_test.sh"
ln -s "$linktree/real" "$linktree/tree/linked"
run_sut env -u SUT bash "$linktree/tree/run.sh"
if ! check_eq 'symlinked test directory: exit' 1 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'symlinked test directory: nothing ran' ''; then fails_here=1; fi
if ! grep -qF -- "${linktree}/tree/linked is a symlink to a directory" "$SUT_STDERR"; then
  printf 'FAIL symlinked test directory: stderr does not name the link: %s\n' "$(head -c 400 "$SUT_STDERR")"
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 9: a test file nested under the root is discovered and run ---------
# Discovery must reach every depth the suite uses, not just the top level. The
# repository nests 40 of its 47 test files; a discovery that matched one level
# would run 7 files and report the whole suite green. A plain top-level test is
# planted too, so a depth-blind runner reports one file rather than none.
total=$((total + 1))
fails_here=0
deep="${HARNESS_TMP}/deep-discovery"
mkdir -p "$deep/a/b"
cp "$SUT" "$deep/run.sh"
printf '#!/usr/bin/env bash\nprintf "deep ran\\n"\n' >"$deep/a/b/deep_test.sh"
printf '#!/usr/bin/env bash\nprintf "top ran\\n"\n' >"$deep/top_test.sh"
run_sut env -u SUT bash "$deep/run.sh"
if ! check_eq 'nested test file: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_bytes 'nested test file: both files ran, in sorted order' \
  'deep ran\ntop ran\nall 2 test files passed\n'; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# --- case 10: a readable non-script SUT stops the run ------------------------
# A file that exists, is non-empty and is readable walks straight through
# -f/-s/-r, and `bash "$SUT"` then fails every row: exit 2 when the absolute
# path is prose bash cannot parse (`${REPO_ROOT}/README.md`), and exit 127 from
# the relative spelling `SUT=README.md`, whose path stops resolving once a row
# `cd`s into a fixture repo. Either way it is the same false RED a missing path
# produces, reached through prose (#687). Measured against the unguarded
# runner: `SUT=README.md tests/run.sh tests/tools/check-clean_test.sh` reported
# `not ok 5/5`, and `SUT=README.md tests/run.sh tests/tools/poll_test.sh`
# `not ok 7/11`, both indistinguishable from a successful RED verification.
#
# The fixture is the README because prose can be syntactically valid bash
# (`This is prose without parentheses.` parses), so `bash -n` would accept some
# READMEs and is not a substitute for the shebang. Each half of the guard has a
# fixture that only it can refuse, so neither can be dropped silently:
# `no-shebang.sh` whose body bash parses, and `not-bash.py` which carries a
# shebang.
not_script="${REPO_ROOT}/README.md"
assert_refused 'non-script SUT' "$not_script" 'SUT does not name a script'
no_shebang="${HARNESS_TMP}/no-shebang.sh"
printf 'exit 0\n' >"$no_shebang"
assert_refused 'SUT without a shebang' "$no_shebang" 'SUT does not name a script'
not_bash="${HARNESS_TMP}/not-bash.py"
printf '#!/usr/bin/env python3\nprint("hello")\n' >"$not_bash"
assert_refused 'non-bash SUT' "$not_bash" 'SUT does not name a script'

# --- case 11: an extensionless SUT still runs --------------------------------
# tests/lib/bin/gh has to stay named `gh` to work as a PATH stub, so a guard
# that classified by a `.sh` suffix would refuse the ground truth the whole
# offline suite rests on.
assert_accepted 'extensionless SUT' "${REPO_ROOT}/tests/lib/bin/gh"

harness_exit "$failed" "$total"
