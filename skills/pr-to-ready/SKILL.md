---
name: pr-to-ready
description: Use to take an open PR to ready, or a branch with no PR yet to ready.
---

# pr-to-ready

- Take an open PR to a reviewed one.
- Loop until CI passes and the review is clean.
- Leave it ready or draft as the run was told.

## Opening questions

- Ask the user two things, once, before anything else.
- Ask whether to mark the PR ready or leave its status once CI is green and review is clean.
- Record that answer, since the finish branches on it.
- Ask which reviewers to request.
- Offer Copilot, Claude, and requesting-code-review as a pick-any choice, plus none.
- Offer all three verbatim, without omission or rename, since a dropped or respelled choice silently proceeds without the wanted review.

## Main entry: a PR reference

- Bind the run from the caller's reference — a PR number or a PR URL — after the opening questions and before any workspace.
- Ask which repository a bare number belongs to, offering origin's own first, since a bare number names no repository and otherwise the run drives a same-numbered PR in another repository while nothing it does lands where it was asked.
- Take the owner and repo a URL names.
- Confirm the checkout's origin names that same repository through `tools/origin-repo.sh`, and stop on mismatch before creating any workspace, since otherwise the workspace attaches the same branch name on a remote that is not the PR's while every fix is committed and pushed where no reviewer watches and the PR does not move.
- Hand back a head on another remote, since it is not driven from here.

## Fallback entry: a branch with no PR yet

- Where the caller gave a branch name instead of a PR reference, drive `tools/ensure-draft-pr.sh` per the output contract in its header.
- Open the draft PR by the agent's own means.
- On `STOP ask-base-repo` or `STOP fork-unread`, ask which repository the draft targets, offering origin's own first, since otherwise the draft opens against the wrong repository, a fork instead of its parent or the other way round.
- Keep the title and body to `implement-work`'s Hand off.
- Always draft.
- Carry a closing keyword on the issue this work resolves.

## Purpose check

- Read the purpose from the issue behind a closing keyword.
- Never read it from the PR body.
- Where that keyword points at a PR number rather than an issue, stop, since a closing keyword on a PR number closes nothing and leaves the issue open after the merge.
- Invoke `propose-alternatives` once when the purpose is named.
- Leave its compare, the one review-findings pass, and the ask-person continue-or-revisit to its own procedure.

## Reviewer loop

- Request each selected reviewer by the agent's own means.
- Skip a name that is unavailable or unselected.
- Probe no other.
- Complete the requesting-code-review leg on that round's local vet-code return.
- Wait for no baseline there.
- Complete each Copilot or Claude leg on the first GitHub-observed review by that login after the request baseline.
- Compare GitHub-observed reviews against that baseline, never against what this run already handled, since otherwise an older review satisfies the wait and the loop judges clean on a diff no reviewer saw.
- Attribute a GitHub-observed review by author login, never by timestamp, since a human commenting in the same window otherwise misreads as the reviewer.
- Fold a late non-inline arrival received before the verdict comment is posted into it.
- Never edit a posted comment to fold one in.
- Past the bounded wait, post the verdict comment as a partial verdict naming the missing reviewers.
- Hand back there.
- Judge each returned finding one by one under the judge-findings common rule — fix, decline, or ask a person, with Minor and suppressed included on objective worth.
- Fix what was accepted, then push and request again.
- Stop on a needs-user verdict, advancing no further round until it is answered.

## Clean

- Hold clean only when the same commit SHA satisfies all three: CI green, mergeable, and no fix-worthy findings.
- Diagnose and fix a red check in a new round.
- Judge mergeability off the verdict that describes the branch, never the sibling status that describes the reader's permission, since keyed on the reader's status every PR reads as blocked.
- Hand back a conflict, or a mergeability value still UNKNOWN past the bounded re-read, for a person's explicit re-entry, since an undetermined mergeability is never taken for a clean one.
- Never fix a finding that invalidates the agreed design here.
- Take it through Escalation back to plan-work's **Entry** for re-approval, since otherwise the loop silently ships work the agreed design no longer covers.

## Replies

- Answer each threaded finding — one with a GitHub thread — in its thread and resolve the thread.
- Post at most two standalone comments per round.
- Post the round's applicable comments before leaving the round — advancing, requesting again, or handing back — since a hand-back decided first silently drops the round's verdicts into the session where no later round re-posts them.
- Carry that round's vet-code findings in one result comment as verbatim whole plain text — finding text, severity, location, never paraphrased, with no added mentions or elaborate formatting.
- Carry a per-finding verdict for every non-inline finding, suppressed included, in one verdict comment across all selected reviewers, with Copilot and Claude substance paraphrased and never verbatim quoted and with no mentions, since otherwise the quote silently summons a fresh review of the run's own words.
  - Treat suppressed-comment blocks as a read source alongside threads.
- Open each result and verdict comment with the reviewed commit SHA, since without it a verdict posted before a merge reads as judging the merged head the reviewer never saw.
- Create no new thread.
- Send threadless vet-code-originated findings to the result comment and the verdict comment.
- Send threadless Copilot or Claude findings to the verdict comment only, never transcribed into the result comment.
- Post no result comment where the round has no findings or has only Declined lines.
- Transcribe all findings including Declined lines on mixed rounds.
- Post no verdict comment where it has no non-inline verdict target, except the timeout partial verdict naming missing reviewers.
- Put a needs-user verdict's question with the round's obtained verdicts in the same verdict comment.
- Where a round ends both needs-user and unmergeable, still post both comments and hand back once naming both causes, since reporting only the conflict strands the unanswered questions off-PR.

## Base retarget

- Re-resolve the base through `tools/resolve-pr-base.sh`.
- Where the PR drifted off the resolved base, retarget by the agent's own means.
