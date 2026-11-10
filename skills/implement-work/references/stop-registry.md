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
| `abandoned-prerequisite` | `tools/read-prereq-pr.sh` |
| `ask-base-repo` | `tools/ensure-draft-pr.sh` |
| `ask-default-branch` | `implement-work/resolve-base.sh`, `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `ask-multiple-prereqs` | `tools/read-prereq-pr.sh` |
| `ask-multiple-prs` | `tools/ensure-draft-pr.sh`, `tools/read-prereq-pr.sh` |
| `ask-multiple-prs-after-create` | `tools/ensure-draft-pr.sh` |
| `ask-since-base-merged` | `review-pr/resolve-since.sh` |
| `ask-since-rewritten` | `review-pr/resolve-since.sh` |
| `base-fetch-failed` | `implement-work/absorb-base.sh`, `implement-work/resolve-base.sh` |
| `base-resolve-failed` | `tools/ensure-draft-pr.sh` |
| `branch-nowhere` | `tools/ensure-draft-pr.sh` |
| `body-unreadable` | `tools/post-review.sh`, `tools/read-prereq-pr.sh` |
| `commit-failed` | `implement-work/commit-merge.sh` |
| `default-fetch-failed` | `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `detached-head` | `implement-work/absorb-base.sh` |
| `dirty-tree` | `implement-work/absorb-base.sh` |
| `fact-count` | `tools/facts.sh` |
| `fact-enum` | `tools/facts.sh` |
| `fact-malformed` | `tools/facts.sh` |
| `fact-mismatch` | `tools/facts.sh` |
| `fact-missing` | `tools/facts.sh` |
| `facts-answer-malformed` | `tools/ensure-draft-pr.sh`, `tools/resolve-range.sh`, `tools/check-pr-author.sh`, `tools/post-review.sh`, `review-pr/resolve-since.sh`, `tools/read-prereq-pr.sh` |
| `facts-read-failed` | `tools/ensure-draft-pr.sh`, `tools/resolve-range.sh`, `tools/check-pr-author.sh`, `tools/post-review.sh`, `review-pr/resolve-since.sh`, `tools/read-prereq-pr.sh` |
| `fetch-failed` | `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `fork-unread` | `tools/ensure-draft-pr.sh` |
| `ls-remote-failed` | `tools/ensure-draft-pr.sh` |
| `merge-base-failed` | `tools/resolve-range.sh` |
| `merge-failed` | `implement-work/absorb-base.sh` |
| `no-merge-in-progress` | `implement-work/commit-merge.sh` |
| `not-implemented` | `tools/read-prereq-pr.sh` |
| `pr-not-created` | `tools/ensure-draft-pr.sh` |
| `prereq-answer-malformed` | `implement-work/resolve-base.sh`, `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `prereq-line-malformed` | `tools/read-prereq-pr.sh` |
| `prereq-read-failed` | `implement-work/resolve-base.sh`, `tools/resolve-pr-base.sh`, `tools/resolve-range.sh` |
| `push-failed` | `tools/ensure-draft-pr.sh` |
| `repo-lookup-failed` | `tools/resolve-range.sh`, `tools/ensure-draft-pr.sh`, `tools/check-pr-author.sh`, `tools/post-review.sh`, `review-pr/resolve-since.sh`, `tools/read-prereq-pr.sh` |
| `review-pending-left` | `tools/post-review.sh` |
| `review-state-mismatch` | `tools/post-review.sh` |
| `wait-state-invalid` | `tools/facts.sh` |
| `wrong-branch` | `implement-work/absorb-base.sh` |
| `wrong-checkout` | `review-pr/check-pr-repo.sh` |

## Exit codes

| Exit | Meaning |
| --- | --- |
| `0` | Answer on stdout, `NEED`/`WAIT` on stdout per `script-conventions.md`, or `STOP <slug>` on stdout where the script's header says so |
| `1` | No answer and no STOP: fetch/lookup failed with nothing on stdout (the caller prints its STOP), or timeout where the script's header says so |
| `2` | Usage error: `Usage: ...` on stderr, nothing on stdout |
