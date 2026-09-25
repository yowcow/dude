#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${MANIFEST_ROOT:-$REPO_ROOT}"
cd "$ROOT" || exit 1

claude plugin validate .
python3 "${HOME}/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py" .
muse plugins validate .

for manifest in .agents/plugins/marketplace.json package.json hooks/hooks.json .muse-plugin/plugin.json .muse-plugin/marketplace.json; do
  python3 -m json.tool "$manifest" >/dev/null
done

# The six version fields stay equal; `scripts/bump.sh` is what moves them.
# The six exclude `.agents/plugins/marketplace.json`, a versionless mirror
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
muse_plugin = load('.muse-plugin/plugin.json').get('version')
muse_marketplace = load('.muse-plugin/marketplace.json')['plugins']
muse_entry = next((p for p in muse_marketplace if p.get('name') == 'dude'), {}).get('version')
package = load('package.json').get('version')

versions = {
    '.claude-plugin/plugin.json': plugin,
    '.claude-plugin/marketplace.json': entry,
    '.codex-plugin/plugin.json': codex,
    '.muse-plugin/plugin.json': muse_plugin,
    '.muse-plugin/marketplace.json': muse_entry,
    'package.json': package,
}
vals = list(versions.values())
if not all(isinstance(v, str) for v in vals) or any(v != vals[0] for v in vals):
    for name, value in versions.items():
        print("{}: {}".format(name, value), file=sys.stderr)
    sys.exit(1)
PY
