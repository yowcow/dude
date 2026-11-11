#!/usr/bin/env bash
# Print a repository's default branch by its bare name on stdout, or exit 1
# having printed nothing. Shared by resolve-base.sh, resolve-pr-base.sh and
# resolve-range.sh, and named by pr-to-ready's Step 2-1: do not delete as
# unreferenced. Spec: skills/implement-work/references/base-branch.md,
# "## Resolving the default branch".
#
# The answer is the remote's own HEAD, read live with `git ls-remote --symref`:
# refs/remotes/origin/HEAD goes stale after a default-branch rename and would
# resolve every base from the old name with nothing reporting it. A failing
# ls-remote and a HEAD with no `ref:` line both yield no answer.
#
# Usage: resolve-default-branch.sh
set -euo pipefail

if [ "$#" -gt 0 ]; then
  echo "Usage: $0" >&2
  exit 2
fi

if ! OUT="$(git ls-remote --symref -- origin HEAD 2>/dev/null)"; then
  exit 1
fi
REF="$(awk -F'\t' '$2 == "HEAD" && $1 ~ /^ref: refs\/heads\// { sub(/^ref: refs\/heads\//, "", $1); print $1; exit }' <<<"$OUT")"
if [ -z "$REF" ]; then
  exit 1
fi
printf '%s\n' "$REF"
