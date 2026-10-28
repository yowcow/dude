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

## Main entry: a PR reference

Bind the run from the caller's reference — a PR number or a PR URL — after the opening questions, before any workspace. A bare number names no repository: ask which repository it belongs to, offering origin's own first — otherwise the run drives a same-numbered PR in another repository, and nothing it does lands where it was asked. From a URL take the owner and repo it names; confirm the checkout's origin names that same repository through `tools/origin-repo.sh`, and stop on mismatch before creating any workspace — otherwise the workspace attaches the same branch name on a remote that is not the PR's, and every fix is committed and pushed where no reviewer watches while the PR does not move. A head on another remote is not driven from here; hand it back.

## Fallback entry: a branch with no PR yet

Where the caller gave a branch name instead of a PR reference, drive `tools/ensure-draft-pr.sh` per the output contract in its header, opening the draft PR by the agent's own means. On `STOP ask-base-repo` or `STOP fork-unread`, ask which repository the draft targets, offering origin's own first — otherwise the draft opens against the wrong repository, a fork instead of its parent or the other way round. Title and body follow `implement-work`'s Hand off: always draft, with a closing keyword on the issue this work resolves.

## Purpose check

Read the purpose from the issue behind a closing keyword, never from the PR body. Where that keyword points at a PR number rather than an issue, stop — a closing keyword on a PR number closes nothing, leaving the issue open after the merge. Invoke `propose-alternatives` once when the purpose is named; compare, the one review-findings pass, and the ask-person continue-or-revisit are propose-alternatives's own procedure.

## Reviewer loop

Request each selected reviewer by the agent's own means; skip a name that is unavailable or unselected, and probe no other. The requesting-code-review leg completes on that round's local vet-code return, with no baseline wait. Each Copilot or Claude leg completes on the first GitHub-observed review by that login after the request baseline. Compare GitHub-observed reviews against that baseline, never against what this run already handled, otherwise an older review satisfies the wait and the loop judges clean on a diff no reviewer saw. Attribute a GitHub-observed review by author login, never by timestamp — a human commenting in the same window otherwise misreads as the reviewer. Fold a late non-inline arrival received before the verdict comment is posted into it; never edit a posted comment to fold one in. Past the bounded wait, post the verdict comment as a partial verdict naming the missing reviewers and hand back. Judge each returned finding one by one under the judge-findings common rule — fix, decline, or ask a person, Minor and suppressed included on objective worth — then fix what was accepted, push, and request again. A needs-user verdict stops the loop, advancing no further round until answered.

## Clean

Clean holds when the same commit SHA satisfies all three: CI green, mergeable, and no fix-worthy findings. A red check is diagnosed and fixed in a new round. Judge mergeability off the verdict that describes the branch, never the sibling status that describes the reader's permission — keyed on the reader's status, every PR reads as blocked. A conflict, or a mergeability value still UNKNOWN past the bounded re-read, is handed back for a person's explicit re-entry — an undetermined mergeability is never taken for a clean one. A finding that invalidates the agreed design is never fixed here; it takes Escalation back to plan-work's **Entry** for re-approval — otherwise the loop silently ships work the agreed design no longer covers.

## Replies

Answer each threaded finding — one with a GitHub thread — in its thread and resolve the thread. Per round post at most two standalone comments. One result comment carries that round's vet-code findings as verbatim whole plain text — finding text, severity, location, never paraphrased, with no mentions or elaborate formatting. One verdict comment carries a per-finding verdict for every non-inline finding, suppressed included — suppressed-comment blocks are a read source alongside threads — across all selected reviewers, Copilot and Claude substance paraphrased and never verbatim quoted, with no mentions — otherwise the quote silently summons a fresh review of the run's own words. Create no new thread: threadless vet-code-originated findings go to the result comment and the verdict comment, while threadless Copilot or Claude findings go to the verdict comment only, never transcribed into the result comment. Post no result comment where the round has no findings; a round with only Declined lines posts none; mixed rounds transcribe all findings including Declined lines. Post no verdict comment where it has no non-inline verdict target, except the timeout partial verdict naming missing reviewers. A needs-user verdict puts its question with the round's obtained verdicts in the same verdict comment.

## Base retarget

Re-resolve the base through `tools/resolve-pr-base.sh`; where the PR drifted off the resolved base, retargeting is the agent's own operation.
