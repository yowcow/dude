#!/usr/bin/env bash
# Print origin's repository as lowercase `<owner>/<repo>`, read from its fetch
# URL. A facts contract script pins the repository its facts are read from to
# this answer (skills/implement-work/references/facts.md, `repo`), so an agent
# whose means defaults to another remote's repository reads a mismatched
# record and the check stops, instead of answering about a same-numbered PR
# elsewhere.
#
# Every URL shape reduces to its last two path segments. The scp-like form
# (`git@host:owner/repo`) has no separator after the host, so the host lands
# inside the owner segment and is cut at the colon. Lowercased because GitHub
# matches owner and repo case-insensitively and reports them in either case.
#
# Answers through its caller: no origin, or no owner or repo segment, exits 1
# with nothing on stdout and the caller prints its own slug.
#
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Usage: origin-repo.sh
# Output: <owner>/<repo>
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 2
fi

if ! URL="$(git remote get-url origin 2>/dev/null)" || [ -z "$URL" ]; then
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
