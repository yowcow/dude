#!/usr/bin/env bash
# Table test for tools/origin-repo.sh: a remote's fetch URL (origin's unless one
# is named) reduced to the lowercase `<owner>/<repo>` a facts contract script
# pins its reads to. Each URL shape git accepts for GitHub gets a row, and "no
# origin" exits 1 with nothing on stdout, because the caller prints its own
# slug.
#
# RED verification (see tests/README.md): the script is new. Mutants measured
# in a copy under `mktemp -d`: dropping `${owner##*:}` fails 'scp-like url';
# dropping the `tr` fails 'https url with .git'.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/gitrepo.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/gitrepo.sh"

SUT="${SUT:-${REPO_ROOT}/tools/origin-repo.sh}"

failed=0
total=0

WORK="$(git_repo_scratch work)"
git_repo_init "$WORK" main

# url_row <name> <origin-url> <want-stdout>
url_row() {
  row_start
  git_repo_remote "$WORK" origin "$2"
  run_in "$WORK"
  assert_row "$1" 0 "$3" 0
}

url_row 'https url with .git' 'https://github.com/Acme/Widgets.git' 'acme/widgets\n'
url_row 'https url without .git' 'https://github.com/acme/widgets' 'acme/widgets\n'
url_row 'scp-like url' 'git@github.com:acme/widgets.git' 'acme/widgets\n'
url_row 'ssh url' 'ssh://git@github.com/acme/widgets.git' 'acme/widgets\n'

row_start
git_repo_remote "$WORK" origin 'https://github.com/acme/widgets/'
run_in "$WORK"
assert_row 'url with no repo segment' 1 '' 0

NOORIGIN="$(git_repo_scratch noorigin)"
git_repo_init "$NOORIGIN" main
row_start
run_in "$NOORIGIN"
assert_row 'no origin' 1 '' 0

row_start
git_repo_remote "$WORK" origin 'https://github.com/acme/widgets.git'
git_repo_remote "$WORK" upstream 'git@github.com:Parent/Widgets.git'
run_in "$WORK" upstream
assert_row 'a named remote' 0 'parent/widgets\n' 0

row_start
run_in "$WORK" nosuch
assert_row 'a remote that does not exist' 1 '' 0

row_start
run_in "$WORK" upstream extra
assert_row 'two arguments' 2 '' 0

harness_exit "$failed" "$total"
