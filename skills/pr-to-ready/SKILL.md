---
name: pr-to-ready
description: Use to take an open PR to ready, or a branch with no PR yet to ready.
---

# pr-to-ready

Take an open PR to a reviewed one: loop until CI passes and the review is clean, then leave it ready or draft as the run was told.

## Opening questions

Ask the user two things, once, before anything else:

- Once CI is green and review is clean, should this run mark the PR ready, or leave its status as it is? Record the answer; the finish branches on it.
- Which reviewers should this run request? Offer Copilot, Claude, and requesting-code-review as a pick-any choice, plus none. Offer all three verbatim, without omission or rename — a dropped or respelled choice silently proceeds without the wanted review.

## Fallback entry: a branch with no PR yet

Where the caller gave a branch name instead of a PR reference, drive `tools/ensure-draft-pr.sh` per the output contract in its header, opening the draft PR by the agent's own means. On `STOP ask-base-repo` or `STOP fork-unread`, ask which repository the draft targets, offering origin's own first — otherwise the draft opens against the wrong repository, a fork instead of its parent or the other way round. Title and body follow `implement-work`'s Hand off: always draft, with a closing keyword on the issue this work resolves.

## Purpose check

Read the purpose from the issue behind a closing keyword, never from the PR body. Where that keyword points at a PR number rather than an issue, stop — a closing keyword on a PR number closes nothing, leaving the issue open after the merge. Invoke `propose-alternatives` once when the purpose is named; compare, the one review-findings pass, and the ask-person continue-or-revisit are propose-alternatives's own procedure.

## Reviewer loop

Request each selected reviewer by the agent's own means; skip a name that is unavailable or unselected, and probe no other. Compare each round's reviews against the pre-request baseline, never against what this run already handled — otherwise an older review satisfies the wait and the loop judges clean on a diff no reviewer saw. Attribute a review by author login, never by timestamp — a human commenting in the same window otherwise misreads as the reviewer. Judge each returned finding one by one under the judge-findings common rule — fix, decline, or ask a person, Minor and suppressed included on objective worth — then fix what was accepted, push, and request again.

## Clean

Clean holds when the same commit SHA satisfies all three: CI green, mergeable, and no fix-worthy findings. A red check is diagnosed and fixed in a new round. Judge mergeability off the verdict that describes the branch, never the sibling status that describes the reader's permission — keyed on the reader's status, every PR reads as blocked. A conflict, or a mergeability value still UNKNOWN past the bounded re-read, is handed back for a person's explicit re-entry — an undetermined mergeability is never taken for a clean one. A finding that invalidates the agreed design is never fixed here; it takes Escalation back to plan-work for re-approval.

## Replies

Answer each threaded finding in its thread and resolve the thread; record every threadless finding in one plain comment, without elaborate formatting. Suppressed-comment blocks are a read source alongside threads: a finding that never became a thread still needs its verdict recorded, and quoting a review must never re-trigger the reviewer it came from.

## Base retarget

Re-resolve the base through `tools/resolve-pr-base.sh`; where the PR drifted off the resolved base, retargeting is the agent's own operation.
