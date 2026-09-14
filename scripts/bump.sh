#!/usr/bin/env bash
# Bump the four version fields to one value (jq-free).
# Usage: bump.sh <version>
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi
VERSION="$1"

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ESCAPED="$(printf '%s' "$VERSION" | sed -e 's/[\\&|]/\\&/g')"

for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json package.json; do
  if ! grep -q '"version":' "$f"; then
    echo "error: no version field in $f" >&2
    exit 1
  fi
  tmp="$(mktemp)"
  sed "s|\"version\": \"[^\"]*\"|\"version\": \"${ESCAPED}\"|g" "$f" >"$tmp"
  cat "$tmp" >"$f"
  rm -f "$tmp"
done
