#!/usr/bin/env bash
# Canonical non-gh network guard for hooks/: sample denylist (curl/wget-class,
# not exhaustive — sweep excluded per #446). `gh` itself stays covered by
# session-start_test.sh's zero-gh rows (gh calls == 0), so the two failure
# shapes are separable: a `gh` addition fails there, a curl/wget addition
# fails here.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

failed=0
total=1

# `gh` is deliberately absent from this list: it is the kept zero-gh guard's
# domain. `hooks.json` is exempt (JSON manifest, covered by make manifest).
# Pattern is matched against hooks/* file contents, one FAIL per file.
hits="$(grep -R -E -n --exclude=hooks.json \
  -e '(^|[^a-zA-Z0-9_-])(curl|wget)([^a-zA-Z0-9_-]|$)' \
  -e '(^|[^a-zA-Z0-9_-])(ssh|nc|socat)([^a-zA-Z0-9_-]|$)' \
  -e 'urllib|HttpClient|socket\.|fetch\(|XMLHttpRequest' \
  -e 'git[[:space:]]+(ls-remote|clone|fetch|push)[[:space:]]+[^.]*(https?://|ssh://|git@)' \
  -e '(^|[^a-zA-Z0-9_-])(npm|pip)[[:space:]]+install' \
  "${REPO_ROOT}/hooks" || true)"
if [ -n "$hits" ]; then
  printf 'FAIL hooks/ non-gh network primitive found:\n%s\n' "$hits" >&2
  failed=1
fi

harness_exit "$failed" "$total"
