#!/usr/bin/env bash
# Bump the four version fields to one value (jq-free).
# Usage: bump.sh <version>
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi
VERSION="$1"

# Strict semver (semver.org): numeric cores without leading zeros, optional
# prerelease and build metadata. The anchored regex's charset also keeps the
# value JSON-safe for the sed below.
if ! printf '%s' "$VERSION" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  echo "error: version must be semver (e.g. 1.2.3)" >&2
  exit 1
fi

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${BUMP_ROOT:-$REPO_ROOT}"
cd "$ROOT"

ESCAPED="$(printf '%s' "$VERSION" | sed -e 's/[\\&|]/\\&/g')"

FILES=".claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json package.json"

for f in $FILES; do
  n="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | wc -l || true)"
  n="$(printf '%s' "$n" | tr -d ' ')"
  if [ "$n" -ne 1 ]; then
    echo "error: expected 1 version field in $f, found $n" >&2
    exit 1
  fi
done

for f in $FILES; do
  tmp="$(mktemp)"
  sed "s|\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"version\": \"${ESCAPED}\"|" "$f" >"$tmp"
  cat "$tmp" >"$f"
  rm -f "$tmp"
done
