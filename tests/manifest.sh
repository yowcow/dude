#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

claude plugin validate .
python3 "${HOME}/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py" .

for manifest in .agents/plugins/marketplace.json package.json hooks/hooks.json; do
  python3 -m json.tool "$manifest" >/dev/null
done
