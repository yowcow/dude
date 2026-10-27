#!/usr/bin/env bash
# Reduce a git remote URL, or an `<owner>/<repo>` pair as a reference URL
# carries it, to the lowercase `<owner>/<repo>` the repository-identity checks
# compare: last two path segments, `##*:` covering the scp form, `tr` case fold
# for GitHub's case-insensitive match (bash 3.2 has no `${x,,}`). Empty segments
# are answered as they reduce, never refused; the caller turns that shape into
# its own stop.
#
# Conventions: skills/implement-work/references/script-conventions.md.
#
# Usage: normalize-repo-path.sh <url-or-owner/repo>
# Output: <owner>/<repo>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <url-or-owner/repo>" >&2
  exit 2
fi

url="$1"
# `git clone https://host/owner/repo/` stores the trailing separator verbatim,
# and without this line that form reduces to `widgets/` -- an identity no
# repository answers, so a correct checkout stops as not being its own PR's.
url="${url%/}"
repo="${url##*/}"
repo="${repo%.git}"
owner="${url%/*}"
owner="${owner##*/}"
owner="${owner##*:}"
printf '%s/%s\n' "${owner}" "${repo}" | tr '[:upper:]' '[:lower:]'
