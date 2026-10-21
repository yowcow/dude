#!/usr/bin/env bash
# Tests tests/lint.sh's prune list: the four directories the walk must not enter,
# and the three files it must still select — one at the root, one under a nested
# node_modules that is not .opencode's, and one under .opencode that is not in
# its node_modules. The last two are what a prune widened to a bare `.opencode`
# or `-name node_modules` would hide.
#
# lint.sh anchors its tree on its own location, so the case cannot plant its
# fixtures in the real checkout. Each case builds a miniature checkout, copies
# $SUT into it as tests/lint.sh, and runs that copy — the probe tests/README.md
# describes by hand. $SUT is honoured so a pre-fix lint.sh can be measured.
#
# RED verification (see tests/README.md). The pre-fix lint.sh prunes three
# directories, so the probe's own .opencode/node_modules copy is selected:
#   tmp="$(mktemp -d)"
#   git show b15ee47:tests/lint.sh >"$tmp/old.sh"
#   SUT="$tmp/old.sh" tests/run.sh tests/lint_test.sh
#   -> selected 5 shell file(s), not 4: the count row fails, and the
#      .opencode/node_modules row fails because that leak reached the listing.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tests/lint.sh}"

failed=0
total=0

# probe_new -- a miniature checkout carrying one shebanged file in each pruned
# directory, one at the root, one under a node_modules that is not .opencode's,
# and one under .opencode that is not in its node_modules; prints its path. The
# .git file is `#!/bin/sh` like the real
# hooks/*.sample, so the prune is shown to be path-based and not shebang-based.
# The nested node_modules is what makes a `-name node_modules` spelling fail:
# lint.sh prunes by path precisely so a directory called that elsewhere stays in
# the walk.
probe_new() {
  local root
  root="$(mktemp -d "${HARNESS_TMP}/probe.XXXXXX")"
  mkdir -p "$root/tests" "$root/.git/hooks" "$root/.worktrees/x" \
    "$root/.claude/worktrees/y" "$root/.opencode/node_modules/dep" \
    "$root/pkg/node_modules"
  cp "$SUT" "$root/tests/lint.sh"
  printf '#!/bin/sh\nexit 0\n' >"$root/.git/hooks/pre-commit.sample"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.worktrees/x/leak"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.claude/worktrees/y/leak"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.opencode/node_modules/dep/leak"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.opencode/keep-shell"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/pkg/node_modules/keep"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/keep"
  printf '%s\n' "$root"
}

# check_stdout_has / check_stdout_lacks <label> <needle>
# -F and -- because every needle is a literal path, free to begin with a dash.
check_stdout_has() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$SUT_STDOUT"; then return 0; fi
  printf 'FAIL %s: the listing does not name %s\n  got: %s\n' \
    "$label" "$needle" "$(head -c 600 "$SUT_STDOUT")"
  return 1
}

check_stdout_lacks() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$SUT_STDOUT"; then
    printf 'FAIL %s: a pruned path reached the listing: %s\n' "$label" "$needle"
    return 1
  fi
}

# A ShellCheck stub for the probe run. The SUT runs the real ShellCheck after
# the listing, and this file is about the prune, not about ShellCheck: without
# the stub the row needs the tool installed, and a finding in some unrelated
# file would fail a test that asserts nothing about it. Same trick, same reason,
# as harness.sh putting the fake gh first on PATH. The resolution is asserted
# rather than assumed, because a PATH mistake would leave the real tool in play
# and the row could pass or fail for the wrong reason.
#
# The stub also logs its argv, so a lint.sh that stopped invoking ShellCheck at
# all fails here instead of passing a file that asserts nothing about it.
SHELLCHECK_BIN="$(mktemp -d "${HARNESS_TMP}/bin-shellcheck.XXXXXX")"
SHELLCHECK_LOG="${HARNESS_TMP}/shellcheck.argv"
export SHELLCHECK_LOG
cat >"${SHELLCHECK_BIN}/shellcheck" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$SHELLCHECK_LOG"
for a in "$@"; do
  if [ "$a" = "${SHELLCHECK_FAIL_FILE:-}" ]; then exit 1; fi
done
exit 0
STUB
chmod +x "${SHELLCHECK_BIN}/shellcheck"
PATH="${SHELLCHECK_BIN}:${PATH}"
export PATH
hash -r 2>/dev/null || true
if [ "$(command -v shellcheck)" != "${SHELLCHECK_BIN}/shellcheck" ]; then
  echo "probe: shellcheck resolves to $(command -v shellcheck), not the stub — refusing to run" >&2
  exit 1
fi

PROBE="$(probe_new)"
run_sut bash "$PROBE/tests/lint.sh"

total=$((total + 1))
fails_here=0
if ! check_eq 'probe: exit' 0 "$SUT_STATUS"; then
  fails_here=1
  printf '  stderr: %s\n' "$(head -c 400 "$SUT_STDERR")"
fi
# 4 = the copy of lint.sh itself, keep, pkg/node_modules/keep, and
# .opencode/keep-shell; the four planted leaks are pruned.
if ! check_eq 'probe: selected count' 'selected 4 shell file(s):' \
  "$(head -1 "$SUT_STDOUT")"; then fails_here=1; fi
if ! check_stdout_has 'probe: the root file is selected' "$PROBE/keep"; then fails_here=1; fi
if ! check_stdout_has 'probe: a node_modules outside .opencode is selected' \
  "$PROBE/pkg/node_modules/keep"; then fails_here=1; fi
if ! check_stdout_has 'probe: a file under .opencode outside node_modules is selected' \
  "$PROBE/.opencode/keep-shell"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .git' "$PROBE/.git/hooks/pre-commit.sample"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .worktrees' "$PROBE/.worktrees/x/leak"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .claude/worktrees' "$PROBE/.claude/worktrees/y/leak"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .opencode/node_modules' \
  "$PROBE/.opencode/node_modules/dep/leak"; then fails_here=1; fi
for f in keep pkg/node_modules/keep .opencode/keep-shell tests/lint.sh; do
  if ! grep -qxF -- "$PROBE/$f" "$SHELLCHECK_LOG"; then
    printf 'FAIL probe: %s was not passed to ShellCheck\n' "$PROBE/$f"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# Batching must not drop a file: past one batch, every planted file still
# reaches ShellCheck. They sort last, so a feed that stops after the first
# batch loses them and no other row notices.
mkdir -p "$PROBE/zz-batch"
for ((i = 1; i <= 20; i++)); do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$PROBE/zz-batch/f${i}"
done
run_sut bash "$PROBE/tests/lint.sh"
total=$((total + 1))
fails_here=0
for ((i = 1; i <= 20; i++)); do
  if ! grep -qxF -- "$PROBE/zz-batch/f${i}" "$SHELLCHECK_LOG"; then
    printf 'FAIL probe: %s was dropped by batching\n' "$PROBE/zz-batch/f${i}"
    fails_here=1
  fi
done
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

# A file ShellCheck rejects still fails the run. `xargs` exits 123 when any
# batch fails and the script carries that out as its own non-zero status; a
# wrapper that swallowed it would print "shellcheck: ok" over a failing tree.
# One file of the four fails, so the row also covers a batch that is partly
# clean rather than a run where every file did.
export SHELLCHECK_FAIL_FILE="$PROBE/keep"
run_sut bash "$PROBE/tests/lint.sh"
total=$((total + 1))
if [ "$SUT_STATUS" -eq 0 ]; then
  printf 'FAIL probe: a failing file left the exit status 0\n  stdout: %s\n' \
    "$(head -c 400 "$SUT_STDOUT")"
  failed=$((failed + 1))
fi

harness_exit "$failed" "$total"
