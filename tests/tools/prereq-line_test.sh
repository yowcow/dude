#!/usr/bin/env bash
# Table test for tools/prereq-line.sh: what it reads out of an issue body for
# each shape of the prerequisite line plan-work writes (`Blocked-By: #<n>`).
# implement-work's resolve-base.sh and plan-work's read-back both parse through
# it, so every near-miss a person or an agent is expected to type gets a row:
# read as "no line", each would cut a stacked task from the default branch.
# The parser reads a file and nothing else: every row asserts 0 gh calls.
#
# RED verification (see tests/README.md). The script is new; mutants measured:
#   - drop the carriage-return strip: fails 'crlf body'
#   - count only exact matches as lines: every MALFORMED row answers NONE
#   - stop at the first line found: 'two lines' and 'the same line twice' fail
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/harness.sh
# shellcheck disable=SC1091
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/harness.sh"

SUT="${SUT:-${REPO_ROOT}/tools/prereq-line.sh}"

failed=0
total=0

# body <text> -- prints the path of a new file holding <text> through printf '%b'
body() {
  local f
  f="$(mktemp "${HARNESS_TMP}/body.XXXXXX")"
  printf '%b' "$1" >"$f"
  printf '%s\n' "$f"
}

# row <want-stdout> <name> <body-text>
row() {
  row_start
  run_sut bash "$SUT" "$(body "$3")"
  assert_row "$2" 0 "$1" 0
}

row 'NONE\n' 'no line' 'purpose\n\nno prerequisite\n'
row 'NONE\n' 'empty body' ''
row 'PREREQ 77\n' 'one line' 'Blocked-By: #77\n'
row 'PREREQ 570\n' 'a real child body: the prose prerequisite bullet is not a line' \
  '- **目的：** x\n- **前提：** #570（item 2）に stack する。\n\n親の設計：https://github.com/yowcow/dude/issues/568#issuecomment-6142493208\n\nBlocked-By: #570\n'
row 'PREREQ 77\n' 'crlf body' 'purpose\r\n\r\nBlocked-By: #77\r\n'
row 'PREREQ 77\n' 'last line without newline' 'purpose\nBlocked-By: #77'
row 'MULTIPLE\n' 'two lines' 'Blocked-By: #77\nBlocked-By: #78\n'
row 'MULTIPLE\n' 'the same line twice' 'Blocked-By: #77\nx\nBlocked-By: #77\n'
row 'MULTIPLE\n' 'a line and a near-miss' 'Blocked-By: #77\nBlocked by #78\n'
row 'MALFORMED\n' 'lower-case by' 'Blocked-by: #77\n'
row 'MALFORMED\n' 'no colon' 'Blocked by #77\n'
row 'MALFORMED\n' 'no hash' 'Blocked-By: 77\n'
row 'MALFORMED\n' 'another repository' 'Blocked-By: yowcow/dude#77\n'
row 'MALFORMED\n' 'as a list item' '- Blocked-By: #77\n'
row 'MALFORMED\n' 'quoted' '> Blocked-By: #77\n'
row 'MALFORMED\n' 'indented' '  Blocked-By: #77\n'
row 'MALFORMED\n' 'two numbers on one line' 'Blocked-By: #77 #78\n'
row 'MALFORMED\n' 'trailing text' 'Blocked-By: #77 (item 1)\n'
row 'MALFORMED\n' 'issue zero' 'Blocked-By: #0\n'

row_start
run_sut bash "$SUT" "${HARNESS_TMP}/nosuch"
assert_row 'missing file' 1 '' 0

row_start
run_sut bash "$SUT"
assert_row 'no argument' 2 '' 0

row_start
run_sut bash "$SUT" a b
assert_row 'two arguments' 2 '' 0

harness_exit "$failed" "$total"
