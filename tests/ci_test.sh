#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

workflow="${REPO_ROOT}/.github/workflows/ci.yml"
fixed_claude='npm install --global @anthropic-ai/claude-code@2.1.268'
fixed_source='https://raw.githubusercontent.com/openai/codex/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/skills/src/assets/samples/plugin-creator/scripts/validate_plugin.py'
fixed_identifier='https://raw.githubusercontent.com/openai/codex/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/skills/src/assets/samples/plugin-creator/scripts/identifier_validation.py'
latest_claude='npm install --global @anthropic-ai/claude-code@latest'
latest_release='https://api.github.com/repos/openai/codex/releases/latest'
latest_condition="github.event_name == 'pull_request' || github.event_name == 'schedule'"
github_token='GH_TOKEN="${{ github.token }}" gh api'
step_token='GH_TOKEN: ${{ github.token }}'
pinned_yaml="PyYAML==6.0.2"
fixed_manifest="$(sed -n '/^  manifest:/,/^  manifest-latest:/p' "$workflow")"
latest_manifest="$(sed -n '/^  manifest-latest:/,$p' "$workflow")"

total=1
failed=0
if ! grep -Fq "$fixed_claude" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest pins Claude validator\n' >&2
  failed=1
fi
if ! grep -Fq "$fixed_source" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest pins Codex validator download\n' >&2
  failed=1
fi
if ! grep -Fq "$fixed_identifier" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest pins Codex validator dependency download\n' >&2
  failed=1
fi
if grep -Fq '@anthropic-ai/claude-code@latest' <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest must not resolve latest Claude validator\n' >&2
  failed=1
fi
if grep -Fq "$latest_release" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest must not resolve latest Codex release\n' >&2
  failed=1
fi
if ! grep -Fq "$latest_claude" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest resolves latest Claude validator\n' >&2
  failed=1
fi
if ! grep -Fq "$latest_release" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest resolves latest Codex release\n' >&2
  failed=1
fi
if ! grep -Fq "$github_token" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest authenticates latest Codex release lookup\n' >&2
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
if ! grep -Fq "$pinned_yaml" <<<"$fixed_manifest"; then
  printf 'FAIL: fixed manifest installs pinned PyYAML\n' >&2
  failed=1
fi
if ! grep -Fq "$pinned_yaml" <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest installs pinned PyYAML\n' >&2
  failed=1
fi
if grep -Fq '@anthropic-ai/claude-code@2.1.268' <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest must not pin Claude validator\n' >&2
  failed=1
fi
if grep -Fq '6b9826e3aa83b1a5947db50f4332cb9c65f1b340' <<<"$latest_manifest"; then
  printf 'FAIL: latest manifest must not pin Codex commit\n' >&2
  failed=1
fi

harness_exit "$failed" "$total"
