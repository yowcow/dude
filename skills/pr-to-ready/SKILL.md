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

- Where the caller gave a branch name instead of a PR reference, drive `tools/ensure-draft-pr.sh` with the closing keyword's issue, per the output contract in its header.
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

- Answer each threaded finding — one with a GitHub thread, the vet-code review's own inline comments included — in its thread with its verdict and what was done, or its needs-user question, and resolve the thread only once it is settled, since a resolved thread folds away a question no one has answered.
- Post at most one vet-code review and one verdict comment per round as standalone posts, thread replies aside.
- Post the round's applicable comments before leaving the round — advancing, requesting again, or handing back — since a hand-back decided first silently drops the round's verdicts into the session where no later round re-posts them.
- Post that round's vet-code findings as one COMMENT review anchored to the reviewed commit, each finding's text, severity, and location verbatim and never paraphrased, with no added mentions and no formatting beyond the location form, list marker, and continuation indent `tools/build-review-payload.sh` gives and the `<details>` fold below.
- Hand the round's `accept` and `needs-user` vet-code findings to `tools/build-review-payload.sh` as `{path, line, body}` items — `body` the finding's severity and text, `path` relative to the repository root, `line` head-side, either null where the finding names none — with the merge base of the reviewed commit and the PR's base read afresh as `implement-work`'s `references/facts.md` defines `pr.base.sha`, as its base, never the round's own range, since the PR's diff decides which lines take an inline comment.
  - Where a finding's location is not exactly one `path:line`, put the location as stated at the head of `body`, and take `path` and `line` from its first place, since the tool carries one line only.
- Write the summary it takes as the reviewed commit SHA line followed, where the round has any, by one `<details>` block holding the round's `reject` findings and `Declined to judge` lines verbatim, since the tool appends only the findings it is handed and nothing else of the round reaches the PR.
  - Leave a blank line after `</summary>`, since otherwise the markdown inside the fold renders raw.
- Before the create or the first thread reply, hand back where the viewer already holds a pending review on the PR, never adding to, submitting, or deleting it, since one login holds one pending review per PR and the round's comments otherwise land in, or submit, a draft the run never wrote.
- Post no thread reply while the viewer holds a pending review on the PR, and name the unposted review and replies in the hand-back instead, since a reply by some means joins that pending review unseen and is submitted with it.
- Drive `tools/post-review.sh` with the PR, the reviewed commit, `COMMENT`, and the payload, per its header's output contract:
  - Where `WRITE` names a repository other than the PR's, hand back before the create, saying nothing was posted, since the tool names origin's repository and there the PR's number names another PR or none.
  - On `WRITE`, create a pending review anchored to the reviewed commit in the repository it names, add each inline comment, and submit it, putting the payload's body on whichever step the means lets set and on the submit too where the submit replaces it.
  - End the write at the first failed step, since carrying on submits a review that reads as complete without the failed part.
  - Take the review's id right after the create as `implement-work`'s `references/facts.md` defines `review.id`, read the review back by it whether the write finished or stopped, and run the tool again with that id and a facts file, answering each `NEED` the same way.
  - On `POSTED COMMENTED`, go on to the replies in this review's own threads.
  - Resolve no thread whose reply failed, and hand back after the round's other posts naming each failed reply, since a resolved thread folds away a finding no one answered.
- Hand back, naming the failed step, on any of these, since the PR may hold a review whose body is not the round's:
  - a failed create or a `STOP` from the first call — saying nothing was posted;
  - a successful create with no readable review id, or `STOP review-pending-left` — saying a pending review may be left on the PR for a person to check and submit or delete;
  - any other `STOP` from the read-back — saying a review may be on the PR with a state or body not confirmed to be the round's.
- Keep out of the review any vet-code finding with the same claim about the same code as a thread an earlier round's vet-code review opened, resolved or not, wherever that code now sits, and answer it in that thread instead, since otherwise every round opens another thread for one finding.
  - Unresolve such a thread while that finding is not settled, since a reply in a resolved thread is folded away where no one sees it.
- Carry a per-finding verdict for every non-inline finding, suppressed included, each under its own heading, in one verdict comment across all selected reviewers, with Copilot and Claude substance paraphrased and never verbatim quoted and with no mentions, since otherwise the quote silently summons a fresh review of the run's own words.
  - Treat suppressed-comment blocks as a read source alongside threads.
- Open each vet-code review and verdict comment with the reviewed commit SHA, since without it a verdict posted before a merge reads as judging the merged head the reviewer never saw.
- Follow the verdict comment's SHA line with a heading naming the round's conclusion, one value per round exit:
  - clean — advancing, only where that SHA satisfies **Clean**; never a round with an accepted fix or a red check.
  - fixed and re-requested — requesting again.
  - partial — handing back on the reviewer timeout.
  - waiting on a person — any other hand-back: needs-user, a conflict, undetermined mergeability, Escalation, or a `using-dude`'s **Loop convergence** stop.
- Send threadless Copilot or Claude findings to the verdict comment only, never transcribed into the vet-code review.
- Post no vet-code review where no finding is left for it or only `Declined to judge` lines are.
- Post the verdict comment every round, with only the SHA and the conclusion where it has no non-inline verdict target, since otherwise the final clean round leaves nothing on the PR.
- Put a needs-user verdict's question in its thread where the finding has one, and otherwise with the round's obtained verdicts in the verdict comment.
- Where a round ends both needs-user and unmergeable, still post both applicable comments and hand back once naming both causes, since reporting only the conflict strands the unanswered questions off-PR.

## Base retarget

- Re-resolve the base through `tools/resolve-pr-base.sh` with the Purpose check's issue, never another repository's.
- Where the PR drifted off the resolved base, retarget by the agent's own means.
