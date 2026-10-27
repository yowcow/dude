# STOP slug registry

Every `STOP <slug>` a script prints on stdout, and the exit-code contract
around it. A slug not on this list must not be printed; add it here first.

Slugs are owned by their printing script. `fetch-to-sha.sh`, `origin-repo.sh` and
`resolve-default-branch.sh` print no slug: they exit 1 with empty stdout and
the caller prints its own slug from this list. `tools/facts.sh` prints through a
variable (`echo "STOP ${slug}"`), so a literal `STOP <slug>` grep misses
`fact-count`, `fact-enum`, `fact-mismatch` and `fact-missing`; scripts on the
facts contract relay its `check` line verbatim, reaching stdout through every
such script.

## Slugs

| Slug | Printed by |
| --- | --- |
| `abandoned-prerequisite` | `tools/read-base-trailer.sh`, `implement-work/resolve-base.sh` |
| `ask-base-repo` | `tools/ensure-draft-pr.sh` |
| `ask-default-branch` | `implement-work/resolve-base.sh`, `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `ask-multiple-prereqs` | `implement-work/resolve-base.sh` |
| `ask-multiple-prs` | `tools/read-base-trailer.sh`, `implement-work/resolve-base.sh`, `tools/ensure-draft-pr.sh` |
| `ask-multiple-prs-after-create` | `tools/ensure-draft-pr.sh` |
| `base-fetch-failed` | `implement-work/absorb-base.sh`, `implement-work/resolve-base.sh` |
| `base-resolve-failed` | `tools/ensure-draft-pr.sh` |
| `branch-nowhere` | `tools/ensure-draft-pr.sh` |
| `body-unreadable` | `implement-work/resolve-base.sh`, `review-pr/post-review.sh` |
| `commit-failed` | `implement-work/commit-merge.sh` |
| `default-fetch-failed` | `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `detached-head` | `implement-work/absorb-base.sh` |
| `dirty-tree` | `implement-work/absorb-base.sh` |
| `fact-count` | `tools/facts.sh` |
| `fact-enum` | `tools/facts.sh` |
| `fact-malformed` | `tools/facts.sh` |
| `fact-mismatch` | `tools/facts.sh` |
| `fact-missing` | `tools/facts.sh` |
| `facts-answer-malformed` | `tools/ensure-draft-pr.sh`, `tools/resolve-range.sh`, `tools/read-base-trailer.sh`, `tools/check-pr-author.sh`, `implement-work/resolve-base.sh`, `review-pr/post-review.sh` |
| `facts-read-failed` | `tools/ensure-draft-pr.sh`, `tools/resolve-range.sh`, `tools/read-base-trailer.sh`, `tools/check-pr-author.sh`, `implement-work/resolve-base.sh`, `review-pr/post-review.sh` |
| `fetch-failed` | `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `fork-unread` | `tools/ensure-draft-pr.sh` |
| `ls-remote-failed` | `tools/ensure-draft-pr.sh` |
| `merge-base-failed` | `tools/resolve-range.sh` |
| `merge-failed` | `implement-work/absorb-base.sh` |
| `no-merge-in-progress` | `implement-work/commit-merge.sh` |
| `no-prereq-pr` | `tools/read-base-trailer.sh` |
| `not-implemented` | `implement-work/resolve-base.sh` |
| `pr-not-created` | `tools/ensure-draft-pr.sh` |
| `prereq-line-malformed` | `implement-work/resolve-base.sh` |
| `push-failed` | `tools/ensure-draft-pr.sh` |
| `repo-lookup-failed` | `tools/read-base-trailer.sh`, `tools/resolve-range.sh`, `tools/ensure-draft-pr.sh`, `tools/check-pr-author.sh`, `implement-work/resolve-base.sh`, `review-pr/post-review.sh` |
| `review-pending-left` | `review-pr/post-review.sh` |
| `review-state-mismatch` | `review-pr/post-review.sh` |
| `trailer-answer-malformed` | `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `trailer-read-failed` | `tools/read-base-trailer.sh`, `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `wait-state-invalid` | `tools/facts.sh` |
| `wrong-branch` | `implement-work/absorb-base.sh` |
| `wrong-checkout` | `review-pr/check-pr-repo.sh` |

## Exit codes

| Exit | Meaning |
| --- | --- |
| `0` | Answer on stdout, `NEED`/`WAIT` on stdout per `script-conventions.md`, or `STOP <slug>` on stdout where the script's header says so |
| `1` | No answer and no STOP: fetch/lookup failed with nothing on stdout (the caller prints its STOP), or timeout where the script's header says so |
| `2` | Usage error: `Usage: ...` on stderr, nothing on stdout |
