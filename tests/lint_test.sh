#!/usr/bin/env bash
# Tests tests/lint.sh's prune list: the four directories the walk must not enter,
# and a file at the root it must still select.
#
# lint.sh anchors its tree on its own location, so the case cannot plant its
# fixtures in the real checkout. Each case builds a miniature checkout, copies
# $SUT into it as tests/lint.sh, and runs that copy — the probe tests/README.md
# describes by hand. $SUT is honoured so a pre-fix lint.sh can be measured.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tests/lint.sh}"

failed=0
total=0

# probe_new -- a miniature checkout carrying one shebanged file in each pruned
# directory plus one at the root; prints its path. The .git file is `#!/bin/sh`
# like the real hooks/*.sample, so the prune is shown to be path-based and not
# shebang-based.
probe_new() {
  local root
  root="$(mktemp -d "${HARNESS_TMP}/probe.XXXXXX")"
  mkdir -p "$root/tests" "$root/.git/hooks" "$root/.worktrees/x" \
    "$root/.claude/worktrees/y" "$root/.opencode/node_modules/dep"
  cp "$SUT" "$root/tests/lint.sh"
  printf '#!/bin/sh\nexit 0\n' >"$root/.git/hooks/pre-commit.sample"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.worktrees/x/leak"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.claude/worktrees/y/leak"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/.opencode/node_modules/dep/leak"
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

PROBE="$(probe_new)"
run_sut bash "$PROBE/tests/lint.sh"

total=$((total + 1))
fails_here=0
if ! check_eq 'probe: exit' 0 "$SUT_STATUS"; then fails_here=1; fi
# 2 = the copy of lint.sh itself and keep; the four planted leaks are pruned.
if ! check_eq 'probe: selected count' 'selected 2 shell file(s):' \
  "$(head -1 "$SUT_STDOUT")"; then fails_here=1; fi
if ! check_stdout_has 'probe: the root file is selected' "$PROBE/keep"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .git' "$PROBE/.git/hooks/pre-commit.sample"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .worktrees' "$PROBE/.worktrees/x/leak"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .claude/worktrees' "$PROBE/.claude/worktrees/y/leak"; then fails_here=1; fi
if ! check_stdout_lacks 'probe: .opencode/node_modules' \
  "$PROBE/.opencode/node_modules/dep/leak"; then fails_here=1; fi
if [ "$fails_here" -ne 0 ]; then failed=$((failed + 1)); fi

harness_exit "$failed" "$total"
