#!/usr/bin/env bash
# Table test for skills/implement-work/scripts/poll.sh: when it stops, what
# it prints, and which usage errors exit 2.
#
# The check command is a counter fixture under $HARNESS_TMP: it prints
# poll-<n> on call n and exits 0 once n reaches $SUCCEED_AT. No gh, no git:
# every row asserts 0 gh calls.
#
# RED verification: copy the SUT to a mktemp dir (never inside the
# repository, where lint.sh would select it by shebang), delete the
# `if [ "$i" -lt "$MAX" ]; then sleep` guard so it sleeps after the final
# attempt too, and re-run: `sleeps-between-tries-only: sleeps` tally must
# fail (3 sleeps, not 2). Then replace `exit 1` with `exit 0` and re-run
# as `SUT=<copy> tests/run.sh tests/implement-work/poll_test.sh`:
# `cap-exhausted`, `sleeps-between-tries-only`, and `exhausted-empty-output`
# must fail on exit status alone.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/skills/implement-work/scripts/poll.sh}"

failed=0
total=0

printf '0\n' >"${HARNESS_TMP}/count"
cat >"${HARNESS_TMP}/check.sh" <<EOF
#!/usr/bin/env bash
n=\$(cat "${HARNESS_TMP}/count")
n=\$((n + 1))
printf '%s\n' "\$n" >"${HARNESS_TMP}/count"
printf 'poll-%s\n' "\$n"
if [ "\$n" -ge "\${SUCCEED_AT:-1}" ]; then
  exit 0
fi
exit 1
EOF
chmod +x "${HARNESS_TMP}/check.sh"
CHECK="${HARNESS_TMP}/check.sh"
stub_sleep_instant

row_start
SUCCEED_AT=1 run_sut bash "$SUT" 10 0 "$CHECK"
assert_row 'succeeds-first-try' 0 'poll-1\n' 0

row_start
printf '0\n' >"${HARNESS_TMP}/count"
SUCCEED_AT=3 run_sut bash "$SUT" 10 0 "$CHECK"
assert_row 'succeeds-after-retries' 0 'poll-3\n' 0

row_start
printf '0\n' >"${HARNESS_TMP}/count"
SUCCEED_AT=99 run_sut bash "$SUT" 3 0 "$CHECK"
assert_row 'cap-exhausted' 1 'poll-3\n' 0

row_start
printf '0\n' >"${HARNESS_TMP}/count"
SUCCEED_AT=99 run_sut bash "$SUT" 3 1 "$CHECK"
assert_row 'sleeps-between-tries-only' 1 'poll-3\n' 0
tally check_eq 'sleeps-between-tries-only: sleeps' '2' "$(sleep_call_count)"

row_start
SUCCEED_AT=99 run_sut bash "$SUT" 2 0 false
assert_row 'exhausted-empty-output' 1 '' 0

row_start
run_sut bash "$SUT" 10 0
assert_row 'no-command' 2 '' 0

row_start
SUCCEED_AT=1 run_sut bash "$SUT" foo 0 "$CHECK"
assert_row 'non-numeric-max' 2 '' 0

row_start
SUCCEED_AT=1 run_sut bash "$SUT" 10 bar "$CHECK"
assert_row 'non-numeric-interval' 2 '' 0

row_start
SUCCEED_AT=1 run_sut bash "$SUT" 0 0 "$CHECK"
assert_row 'zero-max' 2 '' 0

harness_exit "$failed" "$total"
