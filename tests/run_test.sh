#!/usr/bin/env bash
# Tests tests/run.sh itself — specifically that a $SUT that does not name a
# readable non-empty file stops the run before any test file executes.
#
# Why this file exists: a $SUT pointing at a path that isn't there makes every
# `run_sut bash "$SUT"` in the selected test file exit 127, so nearly every row
# FAILs — the same shape a successful RED verification has. Reading that as
# "the test detects the defect" turns a zero-detection-power test into an
# accepted one (#214, measured while implementing #187).
#
# Whether a test actually ran is asserted by the fixture's own marker file, not
# by parsing the runner's output: a refused run under the guarded runner prints
# no summary at all, while the pre-guard runner this file is also pointed at for
# RED verification reaches its usual summary whether or not $SUT was honoured.
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

# assert_refused <label> <child-sut> -- one rejection case's whole verdict: the
# runner exited 1, no test file ran, and stderr named both `SUT` and the
# offending path. Advances the caller's `total` once and `failed` once if any
# of the four fails, so `ok N/N` counts a rejection case exactly as it did when
# each case spelled the block out.
#
# File-local rather than in harness.sh: nothing else in the suite has a
# rejection case to assert, and the harness is sourced by every test file.
assert_refused() {
  local label="$1" child_sut="$2" fails=0
  total=$((total + 1))
  run_case "$child_sut"
  if ! check_eq "${label}: exit" 1 "$SUT_STATUS"; then fails=1; fi
  if ! check_eq "${label}: no test file ran" 'did-not-run' "$(marker_state)"; then fails=1; fi
  if ! grep -q 'SUT' "$SUT_STDERR"; then
    printf 'FAIL %s: stderr does not name SUT: %s\n' "$label" "$(head -c 400 "$SUT_STDERR")"
    fails=1
  fi
  if ! grep -qF -- "$child_sut" "$SUT_STDERR"; then
    printf 'FAIL %s: stderr does not name the path: %s\n' "$label" "$(head -c 400 "$SUT_STDERR")"
    fails=1
  fi
  if [ "$fails" -ne 0 ]; then failed=$((failed + 1)); fi
}

# --- case 1: a SUT that does not exist stops the run --------------------------
missing="${HARNESS_TMP}/no-such-script.sh"
rm -f "$missing"
assert_refused 'missing SUT' "$missing"

# --- case 2: an empty SUT file stops the run ---------------------------------
# An empty file exists, so an existence-only guard would let it through, and
# `bash <empty>` exits 0 — the script under test would appear to succeed at
# everything, which is a *green* RED verification: even more misleading.
empty="${HARNESS_TMP}/empty-script.sh"
: >"$empty"
assert_refused 'empty SUT' "$empty"

# --- case 3: a real SUT still runs the selected file -------------------------
# The guard must not cost the mechanism it protects, and this is what would
# catch a guard whose condition is inverted.
total=$((total + 1))
fails_here=0
good="${HARNESS_TMP}/good-script.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$good"
run_case "$good"
if ! check_eq 'valid SUT: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
if ! check_eq 'valid SUT: the test file ran' 'ran' "$(marker_state)"; then fails_here=1; fi
if ! grep -qF "SUT override in effect: ${good}" "$SUT_STDOUT"; then
  printf 'FAIL valid SUT: the override was not reported: %s\n' "$(head -c 400 "$SUT_STDOUT")"
  fails_here=1
fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

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
  assert_refused 'unreadable SUT' "$unreadable"
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
assert_refused 'directory SUT' "$dir_sut"

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

harness_exit "$failed" "$total"
