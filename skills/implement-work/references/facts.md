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

The number on the PR record read. Pinned from the script's argument.

### `pr.author.login`

The login of the PR record's author.

### `viewer.login`

The login the caller's GitHub means is authenticated as — not git's
`user.name` or `user.email`, which never equal a login and would answer
`OTHER` on the caller's own PR.
