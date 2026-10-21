#!/usr/bin/env bash
# Run the offline test suite: every *_test.sh under this directory, each in its
# own bash process so one file's failure neither aborts nor infects the rest.
# Usage: tests/run.sh [test-file ...]
set -uo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  # Collected with `find` rather than `**`, which needs bash 4's globstar. The
  # sibling scripts this suite tests are deliberately kept running on bash 3.2
  # (skills/pr-to-ready/scripts/resolve-pr-entry.sh says so where it avoids
  # ${x,,}), and `shopt -s globstar` there fails while nullglob still applies —
  # so `**` degrades to a single `*` and silently matches only the one nesting
  # depth, dropping any test file shallower or deeper than that. Files nobody
  # noticed were skipped would read as a suite that passed.
  #
  # The listing is a plain foreground pipeline into a temp file, not a process
  # substitution feeding the loop directly. In `done < <(find ...)` the
  # producer's exit status is unreachable: a `find` that dies partway through
  # the tree — an unreadable subdirectory, say — leaves the loop running on
  # whatever it managed to emit, and the run reports the files it did collect as
  # a suite that passed. Measured: a chmod-000 subdirectory holding one test
  # file printed "all 1 test files passed", exit 0, having never run it.
  #
  # `pipefail` (set above) is what makes the single `if !` sufficient — it
  # catches a failure in either stage, so neither `find` nor `sort` can fail
  # unnoticed.
  #
  # `-type l` is there because the coverage gate counts a symlinked test file:
  # it asks `-f`, which follows the link. Discovery with only `-type f`
  # classified the link instead, leaving such a file covered but never run — a
  # suite that reports itself passed. A dangling link is collected by the same
  # expression and then run, where `bash` exits 127: the gate's `-f` fails on
  # the link, so the gate reports no test for that script rather than counting
  # it, and the link must still fail the run at `bash` rather than vanish from
  # discovery.
  LISTING="$(mktemp)"
  trap 'rm -f "$LISTING"' EXIT

  if ! find "$ROOT" \( -type f -o -type l \) -name '*_test.sh' -print0 | sort -z >"$LISTING"; then
    echo "run.sh: listing ${ROOT} failed — the tree was not fully read" >&2
    exit 1
  fi

  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done <"$LISTING"
fi

if [ "$#" -eq 0 ]; then
  # A symlinked directory is listed by find but never descended into, so a
  # *_test.sh inside it is neither discovered nor run while the coverage gate
  # still counts it (-f follows the link) — the same covered-but-never-run file
  # `-type l` collects above, one level up. Refused rather than followed: -L
  # would let the walk leave the tree and loop back into it. The listing's
  # contents are already in `files`, so the temp file is reused here.
  if ! find "$ROOT" -type l -print0 >"$LISTING"; then
    echo "run.sh: listing ${ROOT} failed — the tree was not fully read" >&2
    exit 1
  fi
  while IFS= read -r -d '' link; do
    if [ -d "$link" ]; then
      printf 'run.sh: %s is a symlink to a directory — its tests are not run\n' "$link" >&2
      exit 1
    fi
  done <"$LISTING"
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "run.sh: no test files found under ${ROOT}" >&2
  exit 1
fi

# SUT names one script under test, so applying it to a whole suite would point
# every test file at the same file. It exists for RED verification against a
# pre-fix script, which is always a single file.
if [ -n "${SUT:-}" ] && [ "${#files[@]}" -ne 1 ]; then
  echo "run.sh: SUT is set but ${#files[@]} test files were selected; name one file" >&2
  exit 1
fi

# Whether the override reaches anything is up to the selected file: one that
# never reads $SUT runs against its own default and passes, so a mistyped file
# name during RED verification would come back green and read as "this test
# cannot detect the defect". Printing what is honoured makes that visible, and
# is printed rather than enforced because a file may consume $SUT indirectly —
# grepping for the name would refuse legitimate runs.
if [ -n "${SUT:-}" ]; then
  # Checked before anything runs, and before the line below claims the override
  # is in effect. A $SUT that isn't there makes every `run_sut bash "$SUT"` exit
  # 127, so nearly every row FAILs — which is the shape of a *successful* RED
  # verification, and the "override in effect" line then reads as confirmation
  # that the right file was measured. Measured (#214): the same test file
  # reported `not ok 7/31` against the real pre-fix script and `not ok 20/31`
  # against a path that did not exist.
  #
  # Emptiness is refused too, and it is the quieter half: an empty file exists,
  # and `bash <empty>` exits 0, so the script under test appears to succeed at
  # everything and the RED comes back *green* — read as "this test cannot detect
  # the defect", which retires a test that was never run.
  #
  # Both tests are load-bearing, so the pair does not collapse to `! -s`: `-s`
  # is true for a directory (measured — a directory's size is non-zero), and
  # `bash <dir>` exits 126 on every row, which is the same false RED as a
  # missing path. `-f` is what refuses that.
  #
  # Readability is the third, and it reaches the same false RED through a
  # different door: a file that exists and is non-empty but cannot be read makes
  # `bash "$SUT"` exit 126 on every row, exactly as a directory does. Measured
  # (#217): the same test file reported `not ok 2/18` against the real pre-fix
  # script and `not ok 18/18` against a mode-000 copy of it.
  #
  # `-r` rather than an inspection of the mode bits, because it asks access(2) —
  # the same question the `bash "$SUT"` below asks — so the two cannot disagree.
  # Under root it is true for a mode-000 file, and that is correct: root's bash
  # really can read it, so there is nothing to refuse.
  #
  # `-x` is deliberately not among them. The file is run as `bash "$SUT"`, which
  # needs no execute bit, so requiring one would refuse a legitimate run.
  #
  # The message names readability alone because `-r` is false for a path that
  # isn't there as well, so one wording stays true for all four refusals —
  # missing, directory, empty, unreadable.
  if [ ! -f "$SUT" ] || [ ! -s "$SUT" ] || [ ! -r "$SUT" ]; then
    printf 'run.sh: SUT does not name a readable non-empty file: %s\n' "$SUT" >&2
    exit 1
  fi
  # A readable file that is not a script gets through the three checks above
  # and then fails every row at `bash "$SUT"`, which is the shape of a
  # successful RED verification (#687: `SUT=README.md` reported every row
  # `not ok`). A script is identified by its shebang, the same rule
  # tests/lint.sh selects by, and it has to be the first line: prose can be
  # syntactically valid bash, so `bash -n` would accept a README that happens
  # to carry no parentheses. Any shebang is enough — the file is fed to bash,
  # not executed through its interpreter.
  first_line=''
  # `read` exits non-zero at EOF without a trailing newline and still sets the
  # variable, so the status is discarded rather than read as "no shebang".
  IFS= read -r first_line <"$SUT" || true
  case "$first_line" in
    '#!'*) ;;
    *)
      printf 'run.sh: SUT does not name a script: %s\n' "$SUT" >&2
      exit 1
      ;;
  esac
  printf 'run.sh: SUT override in effect: %s\n' "$SUT"
fi

failed=0
for f in "${files[@]}"; do
  if ! bash "$f"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -ne 0 ]; then
  printf '%s of %s test files failed\n' "$failed" "${#files[@]}"
  exit 1
fi
printf 'all %s test files passed\n' "${#files[@]}"
