#!/usr/bin/env bash
# Reduce a git remote URL, or an `<owner>/<repo>` pair as a reference URL
# carries it, to the lowercase `<owner>/<repo>` the repository-identity checks
# compare. Every URL shape reduces to its last two path segments. The `##*:`
# strip is what covers the scp form (`git@host:owner/repo`), where the host sits
# with no path separator after it and so lands inside the owner segment; drop
# that line and the form git uses for a default SSH clone stops matching its own
# repository. The case fold is not cosmetic either: GitHub matches owner and
# repo case-insensitively, so `acme/Widgets` and `acme/widgets` name one
# repository and have to compare equal — done through `tr` rather than `${x,,}`
# to keep this running on the bash 3.2 this repository's scripts still run on.
#
# Empty segments are answered as they reduce (`widgets/`), never refused: one
# trailing separator is dropped above (a clone of `.../widgets/` keeps it and
# would otherwise reduce to `widgets/`), but input that still leaves one --
# `.../widgets//`, say -- reduces with an empty half, and origin-repo.sh turns
# that shape into exit 1; resolve-pr-entry.sh and check-pr-repo.sh compare the
# answer against a repository and stop.
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
