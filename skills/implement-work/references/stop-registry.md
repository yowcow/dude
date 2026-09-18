# STOP slug registry

Every `STOP <slug>` a script prints on stdout, and the exit-code contract
around it. A slug not on this list must not be printed; add it here first.

Slugs are owned by their printing script. `fetch-to-sha.sh` and
`resolve-default-branch.sh` print no slug: they exit 1 with empty stdout and
the caller prints its own slug from this list. One script prints through a
variable (`ensure-draft-pr.sh`'s `echo "STOP $stop_slug"`): its slugs are
listed by call-site argument, so a literal `STOP <slug>` grep undercounts by
one (`pr-readback-failed`).

## Slugs

| Slug | Printed by |
| --- | --- |
| `abandoned-prerequisite` | `implement-work/read-base-trailer.sh`, `implement-work/resolve-base.sh` |
| `ancestor-check-failed` | `pr-to-ready/retarget-pr.sh` |
| `ask-default-branch` | `implement-work/resolve-base.sh`, `pr-to-ready/resolve-pr-base.sh`, `review-code/resolve-range.sh` |
| `ask-multiple-prereqs` | `implement-work/resolve-base.sh` |
| `ask-multiple-prs` | `implement-work/read-base-trailer.sh`, `implement-work/resolve-base.sh`, `pr-to-ready/ensure-draft-pr.sh` |
| `ask-multiple-prs-after-create` | `pr-to-ready/ensure-draft-pr.sh` |
| `base-fetch-failed` | `implement-work/absorb-base.sh` |
| `branch-fetch-failed` | `pr-to-ready/retarget-pr.sh` |
| `branch-nowhere` | `pr-to-ready/ensure-draft-pr.sh` |
| `checkout-required` | `pr-to-ready/retarget-pr.sh` |
| `commit-failed` | `implement-work/commit-merge.sh` |
| `cross-fork` | `pr-to-ready/resolve-pr-entry.sh` |
| `default-fetch-failed` | `pr-to-ready/resolve-pr-base.sh`, `review-code/resolve-range.sh` |
| `detached-head` | `implement-work/absorb-base.sh` |
| `dirty-tree` | `implement-work/absorb-base.sh` |
| `dirty-worktree` | `pr-to-ready/retarget-pr.sh` |
| `fetch-failed` | `pr-to-ready/resolve-pr-base.sh`, `pr-to-ready/retarget-pr.sh`, `review-code/resolve-range.sh` |
| `ls-remote-failed` | `pr-to-ready/ensure-draft-pr.sh` |
| `merge-base-failed` | `review-code/resolve-range.sh` |
| `merge-conflict` | `pr-to-ready/retarget-pr.sh` |
| `merge-failed` | `implement-work/absorb-base.sh` |
| `no-merge-in-progress` | `implement-work/commit-merge.sh` |
| `no-pr` | `pr-to-ready/resolve-pr-entry.sh` |
| `no-prereq-pr` | `implement-work/read-base-trailer.sh` |
| `not-implemented` | `implement-work/resolve-base.sh` |
| `pr-create-failed` | `pr-to-ready/ensure-draft-pr.sh` |
| `pr-lookup-failed` | `pr-to-ready/resolve-pr-entry.sh`, `pr-to-ready/ensure-draft-pr.sh`, `review-code/resolve-range.sh` |
| `pr-not-created` | `pr-to-ready/ensure-draft-pr.sh` |
| `pr-not-open` | `pr-to-ready/resolve-pr-entry.sh` |
| `pr-read-failed` | `pr-to-ready/check-pr-state.sh`, `pr-to-ready/retarget-pr.sh` |
| `pr-readback-failed` | `pr-to-ready/ensure-draft-pr.sh` |
| `prereq-lookup-failed` | `implement-work/read-base-trailer.sh` |
| `push-failed` | `pr-to-ready/ensure-draft-pr.sh`, `pr-to-ready/retarget-pr.sh` |
| `retarget-failed` | `pr-to-ready/retarget-pr.sh` |
| `trailer-read-failed` | `implement-work/read-base-trailer.sh` |
| `unrecognised-pr-state` | `pr-to-ready/ensure-draft-pr.sh` |
| `wrong-branch` | `implement-work/absorb-base.sh` |
| `wrong-checkout` | `pr-to-ready/resolve-pr-entry.sh` |

## Exit codes

| Exit | Meaning |
| --- | --- |
| `0` | Answer on stdout, or `STOP <slug>` on stdout where the script's header says so |
| `1` | No answer and no STOP: fetch/lookup failed with nothing on stdout (the caller prints its STOP), or timeout where the script's header says so |
| `2` | Usage error: `Usage: ...` on stderr, nothing on stdout |
| `3` | Per-script availability answer, frozen: `watch-checks.sh` = no such commit on the remote, `watch-claude-review.sh` = no `@claude` workflow, `request-copilot-review.sh` = its own header's answer. No new exit-3 meanings; collisions are item 3's (yowcow/dude#421) to resolve |
| `4`, `5` | Per-script answers owned by their headers (`watch-checks.sh`, `request-copilot-review.sh`, `list-suppressed-comments.sh`). No new meanings |
