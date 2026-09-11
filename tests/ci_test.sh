#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

workflow="${REPO_ROOT}/.github/workflows/ci.yml"
source_url="https://raw.githubusercontent.com/openai/codex/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/skills/src/assets/samples/plugin-creator/scripts/validate_plugin.py"
identifier_url="https://raw.githubusercontent.com/openai/codex/6b9826e3aa83b1a5947db50f4332cb9c65f1b340/codex-rs/skills/src/assets/samples/plugin-creator/scripts/identifier_validation.py"

total=1
failed=0
if ! grep -Fq "$source_url" "$workflow"; then
  printf 'FAIL: pinned Codex validator download\n' >&2
  failed=1
fi
if ! grep -Fq "$identifier_url" "$workflow"; then
  printf 'FAIL: pinned Codex validator dependency download\n' >&2
  failed=1
fi

harness_exit "$failed" "$total"
