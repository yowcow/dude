#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

# Pins the premises of AGENTS.md's .gitignore and ship prose to the real files.
# It cannot pin what each vendor installer actually ships.
total=4
failed=0

# row 1: the backticked /.../ tokens on the "`.gitignore` drops" line equal the
# non-comment .gitignore lines, as sets. A missing line is red, not vacuously green.
line=$(grep '^`\.gitignore` drops' "${REPO_ROOT}/AGENTS.md" || true)
if [ -z "$line" ]; then
  printf 'FAIL gitignore-list-matches: no "`.gitignore` drops" line in AGENTS.md\n' >&2
  failed=$((failed + 1))
else
  documented=$(printf '%s\n' "$line" | grep -o '`/[^`]*/`' | tr -d '`' | sort)
  actual=$(grep -v -e '^[[:space:]]*$' -e '^#' "${REPO_ROOT}/.gitignore" | sort)
  if ! diff <(printf '%s\n' "$documented") <(printf '%s\n' "$actual") >&2; then
    printf 'FAIL gitignore-list-matches: AGENTS.md list (<) differs from .gitignore (>)\n' >&2
    failed=$((failed + 1))
  fi
fi

# row 2: every marketplace points at the repository root.
if ! REPO_ROOT="$REPO_ROOT" python3 -I - >&2 <<'PY'
import json, os, sys

root = os.environ["REPO_ROOT"]
def load(p):
    with open(os.path.join(root, p)) as f:
        return json.load(f)

errs = []
for p in (".claude-plugin/marketplace.json", ".muse-plugin/marketplace.json"):
    srcs = [x.get("source") for x in load(p)["plugins"] if x.get("name") == "dude"]
    if srcs != ["./"]:
        errs.append("FAIL marketplace-source-is-root: %s dude source %r != ['./']" % (p, srcs))
a = load(".agents/plugins/marketplace.json")["plugins"][0]["source"].get("path")
if a != "./":
    errs.append("FAIL marketplace-source-is-root: .agents source.path %r != './'" % (a,))
for e in errs:
    print(e)
sys.exit(1 if errs else 0)
PY
then
  failed=$((failed + 1))
fi

# row 3: package.json has no files key (everything ships).
if python3 -I -c 'import json,sys; sys.exit(0 if "files" in json.load(open(sys.argv[1])) else 1)' "${REPO_ROOT}/package.json"; then
  printf 'FAIL package-json-has-no-files-key: package.json has a files key\n' >&2
  failed=$((failed + 1))
fi

# row 4: no .npmignore.
if [ -e "${REPO_ROOT}/.npmignore" ]; then
  printf 'FAIL no-npmignore: .npmignore exists\n' >&2
  failed=$((failed + 1))
fi

harness_exit "$failed" "$total"
