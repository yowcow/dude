# Script conventions

Applies to every executable under `tools/` and `skills/*/scripts/`. Cited by header
from each script; repeated nowhere else.

## Usage errors exit 2

```sh
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <ref>" >&2
  exit 2
fi
```

Shape, not just number: `Usage: ...` on stderr, nothing on stdout, exit 2.
Numeric arguments are validated with `[[ "$X" =~ ^[0-9]+$ ]]`
(`resolve-thread.sh` regex-shape precedent; its own exit stays 1); a non-numeric value is a usage error.
Remaining `exit 1` paths are runtime failures, not usage.
`resolve-default-branch.sh` takes an optional `[repo]` — more than one argument is a usage error.

## SCRIPT_DIR

```sh
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
```

This exact line. Calls into the shared tools go through it as
`bash "${SCRIPT_DIR}/../../../tools/<name>.sh"`
from `skills/<skill>/scripts/`; same-directory calls
as `bash "${SCRIPT_DIR}/<name>.sh"` (`tools/resolve-pr-base.sh` precedent).

## STOP contract

`STOP <slug>` goes on stdout with exit 0; the slug must be on the
registry (`stop-registry.md`). Human-readable detail goes on stderr.
Scripts that answer through a caller (`resolve-default-branch.sh`,
`fetch-to-sha.sh`) print no slug: they exit 1 with empty stdout and the
caller prints its own slug, because a slug printed from inside a command
substitution would be read back as data.

## Facts: `NEED` and `--facts`

A script that needs GitHub facts calls no GitHub client. It takes
`--facts <file>` and checks the file with `tools/facts.sh check` before it
reads a fact with `tools/facts.sh get`; the facts, their shapes, and the
file format are in `facts.md`.

- Without the file, or with a needed fact absent from it, the script answers
  `NEED <token>...` on stdout, exit 0. A bare token names a fact to read. A
  `name=value` token pins the identifier the read is for: read the record it
  names and write `name` from that record, not from the `NEED` line.
- The caller reads every named fact, writes the file, and calls the script
  again with `--facts <file>`. A fact it could not read is written with an
  empty value, never guessed; the check stops on it.
- Any line `check` prints other than `OK` is relayed verbatim and the script
  exits 0. This is the one slug that comes out of a command substitution:
  the relayed line is the script's answer, never data it goes on to use.

## Waiting: `WAIT`

A script that waits on GitHub never sleeps or polls. It answers
`WAIT <seconds> <state-file>` on stdout, exit 0, from
`tools/facts.sh wait`. The caller waits that long, reads the facts again,
and calls the script again with the same arguments plus
`--state <state-file>`, passing the path back unchanged.

- The state file is written by the script and read by nothing else; the
  first call has none.
- Whether the limit is reached or the result is stable is the script's
  decision alone. A porting script keeps the limit and interval it had.
  On the last round it answers its own final word in place of `WAIT`.

## FETCH_HEAD

`git rev-parse FETCH_HEAD` runs before any second `git fetch`: every fetch
rewrites `FETCH_HEAD`, so a value read after a later fetch names the wrong
ref. Save the SHA to a variable immediately; never rely on a
remote-tracking ref a narrowed clone need not update.

## Default branch

Call `tools/resolve-default-branch.sh`. Never guess a
name, never read `refs/remotes/origin/HEAD` (stale after a rename).
