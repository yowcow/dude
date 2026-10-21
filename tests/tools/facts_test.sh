#!/usr/bin/env bash
# Table test for tools/facts.sh: the facts contract's self-check, its read and
# the WAIT round counter. Every script on the contract relays the line `check`
# prints verbatim, so each answer gets a row, and each of the four
# self-checks (identifier, count, enum, unfilled) gets a STOP row of its own.
# No row stubs gh and every row asserts 0 gh calls.
#
# RED verification (see tests/README.md): the script is new. Mutants measured
# in a copy under `mktemp -d`: dropping the `null` test fails 'unfilled: null';
# comparing the list's line count with `-gt` fails 'count: short list';
# skipping the malformed-line scan turns 'malformed line' into a NEED;
# `-ge` to `-gt` in the round comparison fails the three rows that end on the
# final word: 'wait: the limit-th round answers the final word', 'wait: the
# sequence' and 'wait: limit 1 ends on the first round', plus the state-file tally.
# Accepting a bare `round=N` as the state fails 'wait: a counter it did not
# write is refused' and 'wait: a counter it did not write is not advanced';
# widening the round to `[0-9][0-9]*` fails 'wait: the mark does not excuse a
# bad round'.
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
reviews.total=99999999999999999999
EOF
)"
run_sut bash "$SUT" check "$F" 'reviews[]'
assert_row 'count: total past the integer range' 0 'STOP fact-count\n' 0

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
pr.state=OPEN,CLOSED
EOF
)"
run_sut bash "$SUT" check "$F" 'pr.state:OPEN,CLOSED'
assert_row 'enum: a value spelling several members' 0 'STOP fact-enum\n' 0

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
F="$(printf 'pr.author.login=me \n' | facts_file)"
run_sut bash "$SUT" check "$F" pr.author.login
assert_row 'whitespace: trailing space' 0 'STOP fact-malformed\n' 0

row_start
F="$(printf 'pr.author.login= \n' | facts_file)"
run_sut bash "$SUT" check "$F" pr.author.login
assert_row 'whitespace: only a space' 0 'STOP fact-malformed\n' 0

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

# --- wait: a WAIT sequence driven by fact fixtures alone reaches its limit ------
#
# The agent re-reads the facts every round and passes the state file back
# unchanged; only the script decides the limit. Three rounds with limit 3:
# WAIT, WAIT, then the caller's final word, and the state file is gone.
row_start
TMPDIR="$HARNESS_TMP"
export TMPDIR
STATE=''
seen=''
for round in 1 2 3; do
  F="$(printf 'reviews.total=0\nround.seen=%s\n' "$round" | facts_file)"
  run_sut bash "$SUT" check "$F" 'reviews[]'
  seen="${seen}$(cat "$SUT_STDOUT") "
  run_sut bash "$SUT" wait "$STATE" 3 5 TIMEOUT
  read -r word secs path <"$SUT_STDOUT" || true
  case "$word" in
    WAIT)
      if [ -n "$STATE" ] && [ "$path" != "$STATE" ]; then seen="${seen}moved "; fi
      STATE="$path"
      seen="${seen}${word}-${secs} "
      ;;
    *) seen="${seen}${word} " ;;
  esac
done
assert_row 'wait: the limit-th round answers the final word' 0 'TIMEOUT\n' 0
tally check_eq 'wait: the sequence' 'OK WAIT-5 OK WAIT-5 OK TIMEOUT ' "$seen"
if [ -e "$STATE" ]; then state_left=yes; else state_left=no; fi
tally check_eq 'wait: the state file is removed at the end' no "$state_left"

row_start
run_sut bash "$SUT" wait "${HARNESS_TMP}/no-such-state" 3 5 TIMEOUT
assert_row 'wait: missing state file' 0 'STOP wait-state-invalid\n' 0

row_start
BAD="$(printf 'reviews.total=0\n' | facts_file)"
run_sut bash "$SUT" wait "$BAD" 3 5 TIMEOUT
assert_row 'wait: a file it did not write' 0 'STOP wait-state-invalid\n' 0
# The trap must never own a file the caller named: a STOP here still leaves it.
tally check_eq 'wait: a caller-owned file survives the STOP' yes \
  "$([ -e "$BAD" ] && echo yes || echo no)"

row_start
COUNTED="$(printf 'round=3\n' | facts_file)"
run_sut bash "$SUT" wait "$COUNTED" 3 5 TIMEOUT
assert_row 'wait: a counter it did not write is refused' 0 'STOP wait-state-invalid\n' 0
tally check_eq 'wait: a counter it did not write keeps its bytes' 'round=3' "$(cat "$COUNTED")"

row_start
COUNTED="$(printf 'round=1\n' | facts_file)"
run_sut bash "$SUT" wait "$COUNTED" 3 5 TIMEOUT
assert_row 'wait: a counter it did not write is not advanced' 0 'STOP wait-state-invalid\n' 0
tally check_eq 'wait: a counter it did not write keeps one round' 'round=1' "$(cat "$COUNTED")"

row_start
COUNTED="$(printf 'dude-wait round=0\n' | facts_file)"
run_sut bash "$SUT" wait "$COUNTED" 3 5 TIMEOUT
assert_row 'wait: the mark does not excuse a bad round' 0 'STOP wait-state-invalid\n' 0

row_start
run_sut bash "$SUT" wait '' 1 5 TIMEOUT
assert_row 'wait: limit 1 ends on the first round' 0 'TIMEOUT\n' 0

# A WAIT whose hand-off line never reaches the caller leaves a file nobody can
# name again: the path exists only in that line. Bash's builtin `echo` fails
# when fd 1 is closed, which is how this row reaches that state. No row_start:
# the command is run directly (run_sut always hands the script a real stdout
# file) and it stubs no gh.
LEAK="${HARNESS_TMP}/wait-leak"
mkdir -p "$LEAK"
TMPDIR="$LEAK" bash "$SUT" wait '' 3 5 TIMEOUT 1>&- 2>/dev/null && st=0 || st=$?
tally check_eq 'wait: a hand-off that cannot be printed is a failure' 1 "$st"
tally check_eq 'wait: no state file left when the hand-off failed' '' "$(ls -A "$LEAK")"

row_start
run_sut bash "$SUT" wait '' 0 5 TIMEOUT
assert_row 'wait: limit 0' 2 '' 0

row_start
run_sut bash "$SUT" wait '' 3 5 timeout
assert_row 'wait: lower-case final word' 2 '' 0

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
