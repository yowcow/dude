#!/usr/bin/env bash
# Print a remote's repository -- origin's unless one is named -- as lowercase
# `<owner>/<repo>`, read from its fetch URL. A facts contract script pins the
# repository its facts are read from to this answer
# (skills/implement-work/references/facts.md, `repo`), so an agent whose means
# defaults to another remote's repository reads a mismatched record and the
# check stops, instead of answering about a same-numbered PR elsewhere.
#
# Every URL shape reduces to its last two path segments. The scp-like form
# (`git@host:owner/repo`) has no separator after the host, so the host lands
# inside the owner segment and is cut at the colon. Lowercased because GitHub
# matches owner and repo case-insensitively and reports them in either case.
#
# Answers through its caller: no such remote, or no owner or repo segment,
# exits 1 with nothing on stdout and the caller prints its own slug.
#
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Usage: origin-repo.sh [<remote>]
# Output: <owner>/<repo>
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [<remote>]" >&2
  exit 2
fi
REMOTE="${1:-origin}"

if ! URL="$(git remote get-url "$REMOTE" 2>/dev/null)"; then
  exit 1
fi

repo="${URL##*/}"
repo="${repo%.git}"
owner="${URL%/*}"
owner="${owner##*/}"
owner="${owner##*:}"
if [ -z "$owner" ] || [ -z "$repo" ]; then
  exit 1
fi
printf '%s/%s\n' "$owner" "$repo" | tr '[:upper:]' '[:lower:]'
