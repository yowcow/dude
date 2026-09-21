#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${MANIFEST_ROOT:-$REPO_ROOT}"
cd "$ROOT" || exit 1

claude plugin validate .
python3 "${HOME}/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py" .

for manifest in .agents/plugins/marketplace.json package.json hooks/hooks.json; do
  python3 -m json.tool "$manifest" >/dev/null
done

# The four version fields stay equal; `scripts/bump.sh` is what moves them.
# The four exclude `.agents/plugins/marketplace.json`, a versionless mirror
# with no `version` field (syntax-checked above).
python3 - <<'PY'
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


plugin = load('.claude-plugin/plugin.json').get('version')
marketplace = load('.claude-plugin/marketplace.json')['plugins']
entry = next((p for p in marketplace if p.get('name') == 'dude'), {}).get('version')
codex = load('.codex-plugin/plugin.json').get('version')
package = load('package.json').get('version')

versions = {
    '.claude-plugin/plugin.json': plugin,
    '.claude-plugin/marketplace.json': entry,
    '.codex-plugin/plugin.json': codex,
    'package.json': package,
}
vals = list(versions.values())
if not all(isinstance(v, str) for v in vals) or any(v != vals[0] for v in vals):
    for name, value in versions.items():
        print("{}: {}".format(name, value), file=sys.stderr)
    sys.exit(1)
PY
