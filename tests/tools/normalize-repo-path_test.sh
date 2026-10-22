#!/usr/bin/env bash
# Table test for tools/normalize-repo-path.sh: every remote URL shape git
# accepts for GitHub, plus the `<owner>/<repo>` pair a reference URL carries,
# reduced to the lowercase `<owner>/<repo>` the repository-identity checks
# compare. A value with an empty segment is answered as it reduces (`widgets/`),
# never refused: origin-repo.sh turns that shape into exit 1, and the two callers
# compare it against a repository and stop.
#
# RED verification (see tests/README.md): the script is new. Mutants measured in
# a copy under `mktemp -d`: dropping `${owner##*:}` fails only 'scp-like url';
# dropping the `tr` fails every row with an uppercase owner ('https url with
# .git', 'case fold', 'local path'); dropping `${repo%.git}` fails every `.git`
# row ('https url with .git', 'scp-like url', 'ssh url', 'local path').
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tools/normalize-repo-path.sh}"

failed=0
total=0

row_start
run_sut bash "$SUT" 'https://github.com/Acme/Widgets.git'
assert_row 'https url with .git' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" 'https://github.com/acme/widgets'
assert_row 'https url without .git' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" 'git@github.com:acme/widgets.git'
assert_row 'scp-like url' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" 'ssh://git@github.com/acme/widgets.git'
assert_row 'ssh url' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" 'Acme/Widgets'
assert_row 'case fold' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" '/srv/git/Acme/Widgets.git'
assert_row 'local path' 0 'acme/widgets\n' 0

row_start
run_sut bash "$SUT" 'https://github.com/acme/widgets.js'
assert_row 'repo name containing a dot' 0 'acme/widgets.js\n' 0

row_start
run_sut bash "$SUT" 'https://github.com/acme/widgets/'
assert_row 'url with no repo segment' 0 'widgets/\n' 0

row_start
run_sut bash "$SUT"
assert_row 'no argument' 2 '' 0

row_start
run_sut bash "$SUT" a b
assert_row 'two arguments' 2 '' 0

harness_exit "$failed" "$total"
