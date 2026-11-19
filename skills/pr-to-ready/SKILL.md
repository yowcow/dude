---
name: pr-to-ready
description: Use to take an open PR to ready, or a branch with no PR yet to ready.
---

# pr-to-ready

- Take an open PR to a reviewed one.
- Loop until CI passes and the review is clean.
- Leave it ready or draft as the run was told.

## Opening questions

- Ask the user two things, once, after the entry checks pass — the author check, or `CREATE` from `ensure-draft-pr` — and before any draft PR or workspace.
- Ask whether to mark the PR ready or leave its status once CI is green and review is clean.
- Record that answer, since the finish branches on it.
- Ask which reviewers to request.
- Offer Copilot, Claude, and requesting-code-review as a pick-any choice, plus none.
- Offer all three verbatim, without omission or rename, since a dropped or respelled choice silently proceeds without the wanted review.

## Main entry: a PR reference

- Bind the run from the caller's reference — a PR number or a PR URL — before any workspace.
- Ask which repository a bare number belongs to, offering origin's own first, since a bare number names no repository and otherwise the run drives a same-numbered PR in another repository while nothing it does lands where it was asked.
- Take the owner and repo a URL names.
- Confirm the checkout's origin names that same repository through `tools/origin-repo.sh`, and stop on mismatch before creating any workspace, since otherwise the workspace attaches the same branch name on a remote that is not the PR's while every fix is committed and pushed where no reviewer watches and the PR does not move.
- Hand back a head on another remote, since it is not driven from here.
- Before any workspace, run the check-pr-author script (`tools/check-pr-author.sh`) for the PR number, and take its answer as `review-code`'s **Scope** does for a caller-supplied PR.
- On `OTHER`, change nothing and hand back, since the loop pushes fixes to a PR somebody else wrote.

## Fallback entry: a branch with no PR yet

- Where the caller gave a branch name instead of a PR reference, drive `tools/ensure-draft-pr.sh` with the closing keyword's issue, per the output contract in its header.
- On `PR <n> found`, run the same author check on that PR, and on `OTHER` change nothing and hand back, since a branch name reaches a PR whose author this run never saw.
- Open the draft PR by the agent's own means, in the repository the `CREATE` line names, which is always origin's.
- Keep the title and body to `implement-work`'s Hand off.
- Always draft.
- Carry a closing keyword on the issue this work resolves.

## Purpose check

- Read the purpose from the issue behind a closing keyword.
- Read it from the PR body only when the PR carries no closing keyword.
- Where that keyword points at a PR number rather than an issue, stop, since a closing keyword on a PR number closes nothing and leaves the issue open after the merge.
- Invoke `propose-alternatives` once with the purpose chain its **Inputs** defines, built from each issue a closing keyword names, or from the PR body where none is carried, the read-root below, and the current artifact with the designs on the way its **Inputs** names, when the purpose is named.
- Take as the read-root the SHA `tools/fetch-to-sha.sh` prints for the `pr.base.ref` fact, never `pr.base.sha`, the PR head, or the session checkout, since `pr.base.sha` may lag the base's tip.
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
- Once the legs complete or the bounded wait runs out, read the PR and send to judging, whoever posted them:
  - each unresolved thread, the vet-code review's included, except one whose last comment is the viewer's, or with no comment but the viewer's since this run judged it, replied or not;
  - each review body, suppressed-comment blocks included, and each conversation comment, by a login other than the viewer, that arrived after this run started.
- Judge each threadless item once in the run, never again in a later round, save with the answer to its needs-user verdict.
- Leave out threadless items from before this run started, naming them out of scope when the run ends.
- Read again right before handing the round to `address-findings`, and judge in that round each item that arrived since, threads included.
- Judge each finding sent to judging one by one under the judge-findings common rule — fix, decline, or ask a person, with Minor and suppressed included on objective worth.
- Past the bounded wait, end the round as partial and hand back.
- Request again once `address-findings` has pushed the accepted fixes.
- Stop on a needs-user verdict, advancing no further round until it is answered, then send the answer to judging in the next round as one item together with the finding it answers and that finding's thread or source, never judging that answer as an item of its own.

## Clean

- Hold clean only when the same commit SHA satisfies all three: CI green, mergeable, and no fix-worthy finding in the round's vet-code return or among what it sent to judging.
- Diagnose and fix a red check in a new round.
- Judge mergeability off the verdict that describes the branch, never the sibling status that describes the reader's permission, since keyed on the reader's status every PR reads as blocked.
- Hand back a conflict, or a mergeability value still UNKNOWN past the bounded re-read, for a person's explicit re-entry, since an undetermined mergeability is never taken for a clean one.
- Never fix a finding that invalidates the agreed design here.
- Take it through Escalation back to plan-work's **Entry** for re-approval, since otherwise the loop silently ships work the agreed design no longer covers.

## Replies

- Post that round's vet-code findings as one COMMENT review anchored to the reviewed commit, each finding's text, severity, and location verbatim and never paraphrased, with no added mentions and no formatting beyond the location form, list marker, and continuation indent `tools/build-review-payload.sh` gives and the `<details>` fold below.
- Hand the round's `accept` and `needs-user` vet-code findings to `tools/build-review-payload.sh` as `{path, line, body}` items — `body` the finding's severity and text, `path` relative to the repository root, `line` head-side, either null where the finding names none — with the merge base of the reviewed commit and the PR's base read afresh as `implement-work`'s `references/facts.md` defines `pr.base.sha`, as its base, never the round's own range, since the PR's diff decides which lines take an inline comment.
  - Where a finding's location is not exactly one `path:line`, put the location as stated at the head of `body`, and take `path` and `line` from its first place, since the tool carries one line only.
- Write the summary it takes as the reviewed commit SHA line followed, where the round has any, by one `<details>` block holding the round's `reject` findings and `Declined to judge` lines verbatim, since the tool appends only the findings it is handed and nothing else of the round reaches the PR.
  - Leave a blank line after `</summary>`, since otherwise the markdown inside the fold renders raw.
- Before the create, hand back where the viewer already holds a pending review on the PR, never adding to, submitting, or deleting it, since one login holds one pending review per PR and the round's review otherwise lands in, or submits, a draft the run never wrote.
- Drive `tools/post-review.sh` with the PR, the reviewed commit, `COMMENT`, and the payload, per its header's output contract:
  - On `WRITE`, create a pending review anchored to the reviewed commit in the repository it names, add each inline comment, and submit it, putting the payload's body on whichever step the means lets set and on the submit too where the submit replaces it.
  - End the write at the first failed step, since carrying on submits a review that reads as complete without the failed part.
  - Take the review's id right after the create as `implement-work`'s `references/facts.md` defines `review.id`, read the review back by it whether the write finished or stopped, and run the tool again with that id and a facts file, answering each `NEED` the same way.
  - On `POSTED COMMENTED`, go on to `address-findings`.
- Hand back, naming the failed step and each inline finding whose verdict or question went unposted, on any of these, since the PR may hold a review whose body is not the round's:
  - a `STOP` from the first call — saying nothing was posted;
  - a failed create, a successful create with no readable review id, or `STOP review-pending-left` — saying a pending review may be left on the PR for a person to check and submit or delete;
  - any other `STOP` from the read-back — saying a review may be on the PR with a state or body not confirmed to be the round's.
- On those hand-backs and the pending-review one before the create, call no `address-findings` and name each of the round's settlements in the hand-back instead, since the vet-code findings have no thread or review to be answered in and a fix pushed then lands after the hand-back.
- Keep out of the review any vet-code finding with the same claim about the same code as a finding sent to judging this round or a thread an earlier round's vet-code review opened, resolved or not, wherever that code now sits, since otherwise every round opens another thread for one finding.
  - For a finding sent to judging this round, let its one verdict and reply stand for that vet-code finding and count it no more in the vet-code return.
  - Unresolve such a thread while that finding is not settled, since a reply in a resolved thread is folded away where no one sees it.
- Never transcribe another reviewer's finding into the vet-code review.
- Post no vet-code review where no finding is left for it or only `Declined to judge` lines are.
- Hand `address-findings` the round's settlements once, after `POSTED COMMENTED` or where no vet-code review is due, and before leaving the round — advancing, requesting again, or handing back:
  - each vet-code `accept` or `needs-user` finding, with the thread its inline comment opened, or, where it went into the review body, no thread and that review as its source;
  - each vet-code finding kept out of the review for an earlier round's vet-code thread not sent to judging this round, whatever its verdict, with that thread;
  - each finding sent to judging, with its thread, or no thread and a link to its source;
  - a `needs-user` verdict as a question back.
- Pass it as lead text, every round, a heading naming the round's conclusion, one value per round exit, since otherwise the final clean round leaves nothing on the PR:
  - clean — advancing, only where the judged commit satisfies **Clean**; never a round with an accepted fix or a red check.
  - fixed and re-requested — requesting again.
  - partial — handing back on the reviewer timeout, naming the missing reviewers.
  - waiting on a person — any other hand-back: needs-user, a conflict, undetermined mergeability, Escalation, or a `using-dude`'s **Loop convergence** stop.
- Hand back after the round naming each failed reply it returns.
- Hand back naming each reply it returns unposted for a pending review.
- Hand back naming each `accept` settlement it returns, since that fix was never pushed and no later round judges its finding again.
- Carry any other unposted reply, unjudged, into the next round's call where the run advances, and otherwise name it in the hand-back.

## Base retarget

- Count only the issues of origin's repository a closing keyword names.
- With none, leave the base as it is, since its opener chose it.
- Otherwise run `tools/resolve-pr-base.sh` once per issue, answering each `NEED` within that issue's run.
- Stop on any run's `STOP`.
- Take a base only where every run answers the same `BASE`, and otherwise stop and ask a person.
- Where the PR drifted off the resolved base, retarget by the agent's own means.
