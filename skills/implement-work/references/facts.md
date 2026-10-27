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
  written. A source reporting no count (a paginated list) gives the elements
  read once every page is read; stopped-before-last-page is a failed read,
  written as an empty total. `<name>.total=0` with no element lines is empty.
- A `NEED`-pinned `name=value` identifier is written from the record actually
  read — or, for a read parameter (`target`, `head`, `prereq.head`), from the
  read actually made — never copied from the `NEED` line: the copy passes
  whichever record was read.
- A fact that could not be read is written empty; an empty value or `null`
  stops the script. Never fill it from elsewhere.
- One file per call sequence — one script with the same arguments. Other
  arguments, or another script, start a new file: its pins name other records
  and the check stops.

## Facts

### `repo`

`<owner>/<repo>` of the repository the record was read from, lower-case.
Pinned from origin's fetch URL. Read the PR in this repository, not the one
the means defaults to: with an `upstream` remote present, a bare PR number
resolves there, and the same number names a different PR.

### `pr.number`

The number on the PR record read. Pinned from the script's argument or the
`NEED` line. Read in the repository its list was read in: `target` for
`head.open-pr`, `repo` for `prereq.head-pr` and `prereq.closing-pr`.

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
line kept, line endings included. The body, not a comment and not the title.

### `prereq.number`

The number on the prerequisite issue's record read.

### `prereq.closing-pr` (list)

The number of each PR that record names as closing it, open or merged, with
`prereq.closing-pr.total` the count the record reports. Written as read: a
count beside a shortened reference list stops the script, never one PR read
as the only one.

### `prereq.head`

`<owner>:<branch>` — the head the list below is filtered on, `<owner>` being
`repo`'s owner. Filter with the owner: a filter without one has been measured
ignored, returning unrelated PRs. The PR record read next pins its own head —
branch and owner — which catches a filter the means ignored.

### `prereq.head-pr` (list)

The number of each PR in `repo`, in any state, whose head is `prereq.head`,
with `prereq.head-pr.total` the count the source reports. Read by the head
branch's name, which a PR record keeps after the branch is deleted. Numbers
from the list, state from each PR's own record.

### `pr.state`

`OPEN`, `MERGED` or `CLOSED`, from that one PR's record — never from a list,
which has been measured reporting a merged PR as not merged. A record saying
`closed` with the merged flag set is `MERGED`; unset, `CLOSED`.

### `pr.head.ref`

The PR record's head branch, as the bare name: no `owner:` prefix, no
`refs/heads/`.

### `pr.head.owner`

The login of the owner of the PR record's head repository, lower-case. The
branch name alone does not tell two heads apart: `other-fork:feature` and
`acme:feature` share it.

### `pr.base.sha`

The base commit OID on that one PR's record. It may be the base branch's
current tip rather than the point the PR was cut from; the script takes the
merge-base itself.

### `target`

`<owner>/<repo>`, lower-case: the repository a branch's own PR is looked up
and opened in — the base repository a person chose, else origin's.

### `head`

`<owner>:<branch>` — the head the list below is filtered on, `<owner>` being
origin's owner. Filter by head, never by looking the branch name up as a PR
reference: a numeric branch name reads as that PR's number.

### `head.open-pr` (list)

The number of each open PR in `target` whose head is `head`, with
`head.open-pr.total` the count the source reports. A failed read is written
as an empty total, never `0`: "no PR" opens a second PR on top of one that
could not be seen. Read from the repository's open-PR list filtered on `head`,
never from a search: a search index may not yet hold a PR just opened, and
the read-back after `--created` would then answer `pr-not-created` for a PR
that exists.

### `pr.draft`

`true` or `false`, from the PR record.

### `pr.url`

The PR record's web URL.

### `pr.base.ref`

The PR record's base branch, as the bare name.

### `review.id`

The id the create call returned, and the record is read by that id — never
the PR's newest review, which may be someone else's. When the create returns
none, it is the id of the viewer's one `PENDING` review on the PR, read right
after the create succeeded and before any other step. Pinned from the
script's `--posted` argument.

### `review.commit`

The commit the review record is anchored to. Pinned to the head that was
reviewed: a review created without naming that commit anchors to the PR's
current head, and after an author push each inline comment lands on whatever
line sits at its number there.

### `review.state`

`PENDING`, `APPROVED` or `COMMENTED`, from that review record — never inferred
from the submit call having returned. Any other value (`CHANGES_REQUESTED`,
`DISMISSED`) is outside what this flow posts.

### `review.body-file`

The path of a file holding that review record's body exactly as read, from
the record — never from the arguments of a create or submit call: a body the
write steps dropped reads back empty, which is what the read-back catches.

### `review.url`

The review record's web URL.

### `repo.fork` (list)

`true` or `false` for each repository record read for `repo`. `repo.fork.total`
is the number of records the read returned — 1 for the repository's own
record. A repository search returns a fork only when the query includes
forks; a search that misses it reports total 0, written as read: the script
stops on it, never reading it as "not a fork".
