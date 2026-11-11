#!/usr/bin/env bash
# Print origin's repository as lowercase `<owner>/<repo>`, read from its fetch
# URL. A facts-contract script pins the
# repository its facts are read from to this answer, so a record read for a
# same-numbered PR elsewhere stops instead of answering about the wrong PR.
# Facts: skills/implement-work/references/facts.md, `repo`.
#
# Answers through its caller: no such remote, or an empty owner or repo segment,
# exits 1 with nothing on stdout and the caller prints its own slug.
#
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Usage: origin-repo.sh
# Output: <owner>/<repo>
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 2
fi

if ! URL="$(git remote get-url origin 2>/dev/null)"; then
  exit 1
fi

# A leading or trailing / in the reduction is exactly the empty owner or repo
# segment this script answers through its caller.
PAIR="$(bash "${SCRIPT_DIR}/normalize-repo-path.sh" "$URL")"
case "$PAIR" in
  /*|*/) exit 1 ;;
esac
printf '%s\n' "$PAIR"
