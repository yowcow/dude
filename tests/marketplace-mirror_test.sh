#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

# The Codex mirror (.agents/plugins/marketplace.json) must stay versionless and
# agree with the Claude and Muse marketplaces on names and source; those two
# agree on everything but version (manifest.sh owns version).
total=1
failed=0
if ! REPO_ROOT="$REPO_ROOT" python3 -I - >&2 <<'PY'
import json, os, sys

root = os.environ["REPO_ROOT"]
def load(p):
    with open(os.path.join(root, p)) as f:
        return json.load(f)

agents = load(".agents/plugins/marketplace.json")
claude = load(".claude-plugin/marketplace.json")
muse = load(".muse-plugin/marketplace.json")
errs = []

def eq(label, a, b):
    if a != b:
        errs.append("FAIL: %s: %r != %r" % (label, a, b))

def has_version(o):
    if isinstance(o, dict):
        return "version" in o or any(has_version(v) for v in o.values())
    if isinstance(o, list):
        return any(has_version(v) for v in o)
    return False

def dude(m):
    return [p for p in m["plugins"] if p.get("name") == "dude"]

for label, m in (("claude", claude), ("muse", muse)):
    if len(dude(m)) != 1:
        errs.append("FAIL: %s marketplace needs exactly one dude plugin" % label)
if len(agents["plugins"]) != 1:
    errs.append("FAIL: .agents marketplace needs exactly one plugin")

eq(".agents name vs claude name", agents["name"], claude["name"])
if not errs:
    ap, cp, mp = agents["plugins"][0], dude(claude)[0], dude(muse)[0]
    eq(".agents plugin name vs claude dude", ap["name"], cp["name"])
    eq(".agents plugin name vs muse dude", ap["name"], mp["name"])
    eq(".agents source.path vs claude source", ap["source"]["path"], cp["source"])
    eq(".agents source.path vs muse source", ap["source"]["path"], mp["source"])
    for k in ("name", "description", "owner"):
        eq("claude vs muse marketplace " + k, claude.get(k), muse.get(k))
    for k in ("description", "source", "author"):
        eq("claude vs muse dude " + k, cp.get(k), mp.get(k))
if has_version(agents):
    errs.append('FAIL: .agents marketplace must carry no "version" key (versionless mirror)')

for e in errs:
    print(e)
sys.exit(1 if errs else 0)
PY
then
  failed=1
fi

harness_exit "$failed" "$total"
