#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

workflow="${REPO_ROOT}/.github/workflows/ci.yml"
fixed_claude='npm install --global @anthropic-ai/claude-code@2.1.268'
latest_claude='npm install --global @anthropic-ai/claude-code@latest'
latest_condition="github.event_name == 'pull_request' || github.event_name == 'schedule'"
step_token='GH_TOKEN: ${{ github.token }}'
schedule_cron="cron: '17 3 * * 1'"
job_block() {
  awk -v jobs="$1" '/^  [A-Za-z0-9_-]+:/{job=$1} job ~ "^(" jobs "):$"' "$workflow"
}
fixed_manifest="$(job_block 'manifest')"
latest_manifest="$(job_block 'manifest-latest')"
gated_blocks="$(job_block 'lint|test')"
bash32_job="$(job_block 'test-bash32')"
bash32_sha='3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4'

total=1
failed=0
if ! grep -Fq "$fixed_claude" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest pins Claude validator\n' >&2
  failed=1
fi
if grep -Fq '@anthropic-ai/claude-code@latest' <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest must not resolve latest Claude validator\n' >&2
  failed=1
fi
if ! grep -Fq "$latest_claude" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest resolves latest Claude validator\n' >&2
  failed=1
fi
if grep -Fq "$step_token" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest must not expose GH_TOKEN to installers\n' >&2
  failed=1
fi
if ! grep -Fq "$latest_condition" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest runs only for pull requests and schedules\n' >&2
  failed=1
fi
if grep -Fq "github.event_name == 'push'" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest must not run on pushes\n' >&2
  failed=1
fi
if grep -Fq '@anthropic-ai/claude-code@2.1.268' <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest must not pin Claude validator\n' >&2
  failed=1
fi
if ! grep -Fq "$schedule_cron" "$workflow"; then
  printf 'FAIL: workflow schedules weekly manifest-latest run\n' >&2
  failed=1
fi
if ! grep -Fq "github.event_name != 'schedule'" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest must not run on schedules\n' >&2
  failed=1
fi
uses_lines="$(grep -c 'uses:' <<<"$gated_blocks" || true)"
pinned_lines="$(grep -cE 'uses: [^[:space:]]+@[0-9a-f]{40} # ' <<<"$gated_blocks" || true)"
if [ "$uses_lines" -eq 0 ]; then
  printf 'FAIL: lint/test jobs declare no uses: lines — the selection is broken\n' >&2
  failed=1
fi
if [ "$uses_lines" != "$pinned_lines" ]; then
  printf 'FAIL: lint/test uses: must be SHA-pinned with tag comment (uses=%s pinned=%s)\n' "$uses_lines" "$pinned_lines" >&2
  failed=1
fi
if grep -E -q 'uses: [^[:space:]]+@(v[0-9]|main|master|latest)' <<<"$gated_blocks"; then
  printf 'FAIL: lint/test uses: must not float on a mutable tag\n' >&2
  failed=1
fi

if [ -z "$bash32_job" ]; then
  printf 'FAIL: no test-bash32 job — the selector is broken or the job is gone\n' >&2
  failed=1
fi
if ! grep -Fq 'https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz' <<<"$bash32_job"; then
  printf 'FAIL: test-bash32 fetches the bash 3.2.57 tarball\n' >&2
  failed=1
fi
if ! grep -Fq "$bash32_sha" <<<"$bash32_job" || ! grep -Fq 'sha256sum -c -' <<<"$bash32_job"; then
  printf 'FAIL: test-bash32 pins the fetched tarball by sha256 (bash32_sha here must match ci.yml)\n' >&2
  failed=1
fi
if grep -Eq 'sha256sum -c -.*\|\|' <<<"$bash32_job"; then
  printf 'FAIL: test-bash32 must not swallow a sha256 mismatch\n' >&2
  failed=1
fi
if ! grep -Fq '$GITHUB_PATH' <<<"$bash32_job"; then
  printf 'FAIL: test-bash32 puts the built bash on PATH\n' >&2
  failed=1
fi
if ! grep -Fq "github.event_name != 'schedule'" <<<"$bash32_job"; then
  printf 'FAIL: test-bash32 runs on pull requests\n' >&2
  failed=1
fi
bash32_suite="$(sed -n '/- name: make test (bash 3.2)/,/^      - /p' <<<"$bash32_job")"
if [ -z "$bash32_suite" ]; then
  printf 'FAIL: test-bash32 has no "make test (bash 3.2)" step — the step name or the job is gone\n' >&2
  failed=1
elif ! grep -Fq 'BASH_VERSINFO' <<<"$bash32_suite" \
  || ! grep -Eq '!=[[:space:]]*"?3\.2' <<<"$bash32_suite" \
  || ! grep -Eq '^[[:space:]]*make test$' <<<"$bash32_suite" \
  || ! grep -Eq '^[[:space:]]*exit [1-9]' <<<"$bash32_suite"; then
  printf 'FAIL: test-bash32 asserts bash 3.2 in the step that runs the suite\n' >&2
  failed=1
fi

harness_exit "$failed" "$total"
