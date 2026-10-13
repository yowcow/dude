#!/usr/bin/env bash
# Table test for tools/facts.sh: the facts contract's self-check and its read. Every script on the contract relays the line
# `check` prints verbatim, so each answer gets a row, and each of the four
# self-checks (identifier, count, enum, unfilled) gets a STOP row of its own.
# No row stubs gh and every row asserts 0 gh calls.
#
# RED verification (see tests/README.md): the script is new. Mutants measured
# in a copy under `mktemp -d`: dropping the `null` test fails 'unfilled: null';
# comparing the list's line count with `-gt` fails 'count: short list';
# skipping the malformed-line scan turns 'malformed line' into a NEED.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tools/facts.sh}"

failed=0
total=0

# --- check: NEED ---------------------------------------------------------------
row_start
run_sut bash "$SUT" check '' repo=acme/widgets pr.number=12 pr.author.login 'reviews[]' 'pr.state:OPEN,CLOSED'
assert_row 'no facts file: every fact is needed' 0 'NEED repo=acme/widgets pr.number=12 pr.author.login reviews pr.state\n' 0

row_start
F="$(facts_file <<'EOF'
repo=acme/widgets
viewer.login=me
EOF
)"
run_sut bash "$SUT" check "$F" repo=acme/widgets pr.number=12 viewer.login pr.author.login
assert_row 'partial facts: only the absent ones' 0 'NEED pr.number=12 pr.author.login\n' 0

row_start
F="$(facts_file <<'EOF'
reviews=1
EOF
)"
run_sut bash "$SUT" check "$F" 'reviews[]'
assert_row 'list without total is still needed' 0 'NEED reviews\n' 0

# --- check: OK -----------------------------------------------------------------
row_start
F="$(facts_file <<'EOF'
repo=acme/widgets
pr.number=12

pr.author.login=alice
pr.state=OPEN
reviews.total=2
reviews=101
reviews=102
EOF
)"
run_sut bash "$SUT" check "$F" repo=acme/widgets pr.number=12 pr.author.login 'pr.state:OPEN,CLOSED' 'reviews[]'
assert_row 'all facts present and consistent' 0 'OK\n' 0

row_start
F="$(facts_file <<'EOF'
reviews.total=0
EOF
)"
run_sut bash "$SUT" check "$F" 'reviews[]'
assert_row 'empty list with total 0' 0 'OK\n' 0

row_start
F="$(printf 'pr.title=a=b c' | facts_file)"
run_sut bash "$SUT" check "$F" pr.title
assert_row 'value with = and no trailing newline' 0 'OK\n' 0

# --- check: the four self-checks -------------------------------------------------
row_start
F="$(facts_file <<'EOF'
repo=acme/widgets
pr.number=13
EOF
)"
run_sut bash "$SUT" check "$F" repo=acme/widgets pr.number=12
assert_row 'identifier: another record was read' 0 'STOP fact-mismatch\n' 0

row_start
F="$(facts_file <<'EOF'
reviews.total=2
reviews=101
EOF
)"
run_sut bash "$SUT" check "$F" 'reviews[]'
assert_row 'count: short list' 0 'STOP fact-count\n' 0

row_start
F="$(facts_file <<'EOF'
pr.number=12
pr.number=13
EOF
)"
run_sut bash "$SUT" check "$F" pr.number=12
assert_row 'count: scalar given twice' 0 'STOP fact-count\n' 0

row_start
F="$(facts_file <<'EOF'
pr.state=MERGED
EOF
)"
run_sut bash "$SUT" check "$F" 'pr.state:OPEN,CLOSED'
assert_row 'enum: value outside the set' 0 'STOP fact-enum\n' 0

row_start
F="$(facts_file <<'EOF'
pr.author.login=
EOF
)"
run_sut bash "$SUT" check "$F" pr.author.login
assert_row 'unfilled: empty' 0 'STOP fact-missing\n' 0

row_start
F="$(facts_file <<'EOF'
pr.author.login=null
EOF
)"
run_sut bash "$SUT" check "$F" pr.author.login
assert_row 'unfilled: null' 0 'STOP fact-missing\n' 0

row_start
F="$(facts_file <<'EOF'
reviews.total=1
reviews=
EOF
)"
run_sut bash "$SUT" check "$F" 'reviews[]'
assert_row 'unfilled: list element' 0 'STOP fact-missing\n' 0

# --- check: malformed ------------------------------------------------------------
row_start
F="$(facts_file <<'EOF'
pr.author.login: alice
EOF
)"
run_sut bash "$SUT" check "$F" pr.author.login
assert_row 'malformed line' 0 'STOP fact-malformed\n' 0

row_start
run_sut bash "$SUT" check "${HARNESS_TMP}/no-such-facts" pr.author.login
assert_row 'unreadable facts file' 0 'STOP fact-malformed\n' 0

# --- get -----------------------------------------------------------------------
row_start
F="$(facts_file <<'EOF'
reviews.total=2
reviews=101
pr.author.login=alice
reviews=102
EOF
)"
run_sut bash "$SUT" get "$F" reviews
assert_row 'get: list in file order' 0 '101\n102\n' 0

row_start
run_sut bash "$SUT" get "$F" pr.author.login
assert_row 'get: scalar' 0 'alice\n' 0

# --- usage ---------------------------------------------------------------------
row_start
run_sut bash "$SUT"
assert_row 'no subcommand' 2 '' 0

row_start
run_sut bash "$SUT" check ''
assert_row 'check without specs' 2 '' 0

row_start
run_sut bash "$SUT" check '' 'Bad.Name'
assert_row 'check with a bad name' 2 '' 0

row_start
run_sut bash "$SUT" get "$F"
assert_row 'get without a name' 2 '' 0

harness_exit "$failed" "$total"
