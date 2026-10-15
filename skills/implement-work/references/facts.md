# Facts

The GitHub facts a script reads, defined once. A script calls no GitHub
client: it names what it lacks in a `NEED` line, the caller reads each fact
by whatever means it has and writes them to a file, and the script decides
from that file and git alone. Protocol: `script-conventions.md`, **Facts**
and **Waiting**.

## The file

- One fact per line, `name=value`, split at the first `=`; the value runs to
  the end of the line. Names are lower-case `[a-z0-9._-]`. Blank lines are
  skipped; any other line is malformed and stops the script, and so is a
  value with leading or trailing whitespace.
- A list repeats its name once per element, in the order read, and adds
  `<name>.total=<n>`, the count the source reported — not the count of lines
  written. `<name>.total=0` with no element lines is an empty list.
- An identifier the `NEED` line pinned as `name=value` is written from the
  record actually read, never copied from the `NEED` line: the copy passes
  the check whichever record was read.
- A fact that could not be read is written with an empty value; an empty
  value or `null` stops the script. Never fill it from elsewhere.

## Facts

### `repo`

`<owner>/<repo>` of the repository the record was read from, lower-case.
Pinned from origin's fetch URL. Read the PR in this repository, not in the
one the means defaults to: with an `upstream` remote present, a bare PR
number resolves there, and the same number names a different PR.

### `pr.number`

The number on the PR record read. Pinned from the script's argument or the
`NEED` line.

### `pr.author.login`

The login of the PR record's author.

### `viewer.login`

The login the caller's GitHub means is authenticated as — not git's
`user.name` or `user.email`, which never equal a login and would answer
`OTHER` on the caller's own PR.

### `issue.number`

The number on the issue record read. Pinned from the script's argument.

### `issue.body-file`

The path of a file holding that issue record's body exactly as read: every
line kept, line endings included. The body, not a comment and not the title;
the line a script looks for is written into the body.

### `prereq.number`

The number on the prerequisite issue's record read. Pinned from the `NEED`
line.

### `prereq.closing-pr` (list)

The number of each PR that record names as closing it, open or merged, with
`prereq.closing-pr.total` the count the record reports. A record that carries
the count beside a shortened reference list is written as read — fewer
elements than the total stops the script, never one PR read as the only one.

### `prereq.head`

`<owner>:<branch>` — the head the list below is filtered on, `<owner>` being
`repo`'s owner. Pinned from the `NEED` line. Filter on the head with its
owner: a filter without one has been measured ignored, returning unrelated
PRs. The PR record read next pins its own head, which is what catches a
filter the means ignored.

### `prereq.head-pr` (list)

The number of each PR in `repo`, in any state, whose head is `prereq.head`,
with `prereq.head-pr.total` the count the source reports. Read by the head
branch's name, which a PR record keeps after the branch is deleted. Only the
numbers come from the list; the state comes from each PR's own record.

### `pr.state`

`OPEN`, `MERGED` or `CLOSED`, from that one PR's record — never from a list,
which has been measured reporting a merged PR as not merged. A record that
says `closed` with a merged flag set is `MERGED`; with the flag unset,
`CLOSED`.

### `pr.head.ref`

The PR record's head branch, as the bare name: no `owner:` prefix, no
`refs/heads/`. A `NEED` line may pin it (`pr.head.ref=<branch>`); written
from the record, never from the list or the `NEED` line.
