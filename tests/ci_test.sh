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
fixed_manifest="$(sed -n '/^  manifest:/,/^  manifest-latest:/p' "$workflow")"
latest_manifest="$(sed -n '/^  manifest-latest:/,$p' "$workflow")"
gated_blocks="$(awk '/^  [A-Za-z0-9_-]+:/{job=$1} job=="lint:" || job=="test:"' "$workflow")"

total=1
failed=0
if ! grep -Fq "$fixed_claude" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest pins Claude validator\n' >&2
  failed=1
fi
if grep -Fq 'plugin-creator' "$workflow"; then
  printf 'FAIL: workflow must not install the removed Codex validator\n' >&2
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

harness_exit "$failed" "$total"
