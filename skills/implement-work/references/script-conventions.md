# Script conventions

Applies to every executable under `skills/*/scripts/`. Cited by header
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
(`resolve-thread.sh` precedent); a non-numeric value is a usage error.
Existing scripts `resolve-range.sh`, `resolve-pr-base.sh`, `retarget-pr.sh`,
`resolve-thread.sh`, `resolve-pr-entry.sh`, `resolve-base.sh`,
`read-base-trailer.sh`, `resolve-branch.sh`, `absorb-base.sh`,
`attach-workspace.sh`, `check-pr-state.sh`, `ensure-draft-pr.sh`,
`post-plan-comment.sh`, `set-prerequisites.sh`, `edit-plan-comment.sh` still
exit 1 on usage; item 3 (yowcow/dude#421) migrates them to exit 2.
`resolve-default-branch.sh` takes no arguments and checks none — extra args
are silently ignored; item 3 decides whether it gains an arity guard.

## SCRIPT_DIR

```sh
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
```

This exact line. Cross-skill calls go through it as
`bash "${SCRIPT_DIR}/../../<skill>/scripts/<name>.sh"`
(`resolve-range.sh`, `resolve-pr-base.sh` precedent); same-directory calls
as `bash "${SCRIPT_DIR}/<name>.sh"` (`resolve-base.sh` precedent).
`BASH_SOURCE[0]` spellings converge to this line (item 3 migrates the one
in `ensure-draft-pr.sh`).

## STOP contract

`STOP <slug>` goes on stdout with exit 0; the slug must be on the
registry (`stop-registry.md`). Human-readable detail goes on stderr.
Scripts that answer through a caller (`resolve-default-branch.sh`,
`fetch-to-sha.sh`) print no slug: they exit 1 with empty stdout and the
caller prints its own slug, because a slug printed from inside a command
substitution would be read back as data.

## FETCH_HEAD

`git rev-parse FETCH_HEAD` runs before any second `git fetch`: every fetch
rewrites `FETCH_HEAD`, so a value read after a later fetch names the wrong
ref. Save the SHA to a variable immediately; never rely on a
remote-tracking ref a narrowed clone need not update.

## Default branch

Call `implement-work/scripts/resolve-default-branch.sh`. Never guess a
name, never read `refs/remotes/origin/HEAD` (stale after a rename).
`watch-claude-review.sh` still reads `.defaultBranchRef.name` inline;
item 3 (yowcow/dude#421) converges it.
