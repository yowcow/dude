---
name: plan-work
description: Use to plan a change, including a multi-PR fix that arrives on investigation findings.
---

# Plan Work

## Orchestration model

- The orchestrator owns every decision: research, invoking `superpowers:brainstorming` and `review-plan`, drafting the TODO list, folding accepted findings in, calling convergence or escalation, and publishing.
- The orchestrator never delegates a decision, or the run publishes a plan nobody decided and reports it as agreed.
- Supply those two skills' inputs and act on their outputs.
- Never reach inside those two skills or dispatch reviewers for them, or the plan reads as reviewed without passing review.
- Fold `review-plan` findings in here and re-run `review-plan` from here, since it never edits what it reviewed, or the pre-findings list publishes as if findings were folded in.
- Draft the TODO list here against **Output contract**, since no sub-skill produces a PR-granularity breakdown.
- This skill dispatches no worker.
- Invoke `propose-alternatives` by name, since it owns its procedure.

## Boundaries

- Never touch the working tree: no worktree, no branch, no commit, no code edit, since this flow has no worktree and a commit here lands on whatever branch the session holds, usually `master`.
- Redirect a sub-skill's file-and-commit output into the comment, or it lands on the session branch with the comment carrying nothing.
- The tracking issue's comment is the canonical record.
- Use chat only when no issue tracks the work, with **Output contract** binding that version, or the next session finds nothing to pick up and the work gets planned twice.
- Every GitHub write here is a native operation: posting or editing a comment, creating a child, writing a child's body.
- Pass each body from a file, never inline or as a flag string, since inline backticks get shell-expanded and a path passed where the body belongs posts the path itself as the body.
- Read every posted or edited body back, or the record silently differs from the draft.
- A body past GitHub's size limit signals further splitting, never truncation.
- Creating a child and attaching it to its parent is one native operation, so no script wraps it.
- Never attach via the raw `sub_issues` endpoint, since it identifies the child by database id rather than issue number, so a number passed there silently attaches whichever issue holds that id from whatever repository.

## Entry

- Given an issue number, read the issue and its comments before anything else, or the plan contradicts decided context while reading as informed.
- Given a planning request with no tracking issue, run the research in **Pass** step 3, or the draft argues against unread code.
- Given a planning request with no tracking issue, ask for a tracking issue in **Splitting into sub-issues** before publishing anything, since children with no parent have no design URL to cite.
- Investigation findings enter at research (**Pass** step 3), skipping **Pass** step 2, since the root cause is established and research settles the fix shape.
- The proposed options are input to the design agreement, never the agreement itself.
- A question-shaped report (`settle-question`) carries no reproduction: its Verdict and Next items stand in for baseline and options, and the findings-report citation suffices to receive it.
- Never demand a reproduction for a question-shaped report, since that input never exists and the run stalls on it.
- Should research contradict the root cause, do not re-diagnose here: take `using-dude`'s **Escalation** back to the investigation, or a fresh guess replaces the claimed root cause.
- Receive a downstream-invalidated design only with the finding, which part of the design it undoes, the existing branch's name, and that branch's state (pushed or not, PR open or not), or items cannot name reuse or discard and an old-named item quietly resumes atop the invalidated commits.
- Re-enter at **Design agreement**, skipping **Pass** steps 2 and 3, since re-running research publishes a different design while claiming re-approval.
- Where an issue tracks the work, edit that same comment in place for the re-approved design, since a second design comment leaves children citing the older one.

## Design agreement

- Reach design agreement with `superpowers:brainstorming`, run to its self-review and the user's confirmation, or the run publishes an unapproved draft as the agreed design.
- Never follow `superpowers:brainstorming` onward, however emphatically it says to, since following its trailing pointer starts implementation inside planning and lands edits on the session branch.
- Draft the TODO list from that draft yourself.

## Output contract

- The artifact is the design plus a numbered TODO list of PR-sized items shaped so `implement-work` can pick up any one item: background, design and rationale, split policy, numbered list, per-item parallel-or-stacked order, affected area at module or directory granularity.
- Each item states its purpose, its scope boundary including what it excludes, and its completion criteria.
- Each item needs its exclusions boundary, or it is implemented beyond its PR and lands the next item's changes unreviewed inside it.
- Each item names whether it starts in parallel or stacks on an earlier one, never implying the order, or `implement-work` cuts the stacked branch from the default branch instead of the prerequisite's head and omits its base.
- Each item names the dependency order wherever anything stacks.
- A stacked item names the item it waits for and why, since stacking gives up independent starting.
- Keep exact paths, line numbers, per-task verification commands, and edge-case enumeration deliberately absent, since those belong to `implement-work`.
- Never enumerate paths, since they go stale and the PR edits the wrong lines while citing the plan as authority.
- From investigation findings, put the reproduction into the completion criteria of the item owning the fix, as a regression test failing before and passing after, or as the observation window and metric for a production-only symptom, or the item passes without ever exhibiting the symptom and closes the issue while the bug stands.
- From a question-shaped report there is no reproduction to carry: the findings-report citation is the baseline and the criteria verify against the cited verdict.
- Cite the report by URL, since a sub-issue carries this comment's URL and nothing else, or `implement-work` verifies against no baseline and reports success on any green run.
- From a design invalidated downstream, every item accounts for the existing branch.
- A reused branch is named by the item, and a discarded branch is replaced by a newly named one, since `implement-work` reuses whatever branch it finds and an item carrying the old name quietly resumes atop the invalidated commits.
- Name the discarded branch in the artifact as a person's cleanup, with the worktree checked out on it and identified by that branch rather than by a path, since this flow is never handed one and a path-named cleanup strands the worktree.
- Name any open PR by number, since its body still holds the closing keyword and merging it later lands the invalidated commits and closes the child behind them.
- Each item names, by number, its existing child, so **Publish** acts on the reviewed match, or a re-derived match updates the wrong child.
- Work finished before the invalidation stays out of the numbered list and goes in the split policy instead, each entry carrying its child's number and merged fact, since dropped work gets rebuilt as a duplicate PR.

## Splitting into sub-issues

- Create one sub-issue per item, whatever the count.
- Where a tracking issue exists, sub-issues are not optional, since without them `implement-work` has no named entry for a single PR and a later session finds nothing to pick up.
- With no tracking issue, ask for one before publishing.
- If the user declines, publish in chat with no sub-issues and write the consequence into the artifact: every item must finish in this one session, or a later session silently starts from zero reading it as a normal publish.
- The parent comment carries the design, the split policy, and the list of sub-issues.
- Each child carries its purpose, scope boundary, completion criteria, prerequisite and why (or that it has none), the parent design comment's URL, and, only where the item carries a branch name, that name.
- Each child needs the parent comment's URL, or `implement-work` plans from the child's fragment alone since the child cannot reach the design.
- Put nothing more in the child, since a PR-sized plan there defeats the split.
- A prerequisite is one line in the child's body, `Blocked-By: #N`, alone on its line, with `N` the issue number of the one earlier item it stacks on; an independent item gets no such line.
- Never write the prerequisite as prose, since `implement-work`'s base resolution leaves prose unread and settles the base on the default branch instead of the prerequisite's head.
- After writing a child's body, read it back into a file and check it with `tools/prereq-line.sh <file>`: it must answer `PREREQ <N>` for the intended `N`, or `NONE` for an independent item.
- A stacked child whose line was dropped answers `NONE` and cuts its task from the default branch, so fix the body and re-check on any other answer.
- Converge the `review-plan` loop against the whole, undivided TODO list before splitting: splitting first lets review renumber items, invalidating every child mapping.
- On re-entry, enumerate the existing children from the parent's sub-issue relation, never the comment's prose, since a child added after the last edit is missing there and its item gets a second child.
- Match by each item's substance, never its wording, since a rephrased item otherwise reads as one dropped plus one added, closing a live child and opening a duplicate.
- Match before `review-plan` sees the list, which must already account for what is finished, or review re-splits merged children.
- Re-match items a fold-in changed.
- Bring a surviving item's child body up to date, prerequisite line included, keeping nothing the item no longer says, since a stale line survives and cuts new work from a wrong base.
- Give an item with no child one, as on a first publish, or the item is never picked up while the list claims completeness.
- Name a child whose item is gone in the artifact as a person's cleanup, keeping the sub-issue link as the drop record, since the close is theirs.
- A closed child matching a live item stops the run, since the relation carries no close reason and proceeding either rebuilds merged work or silently drops a live item.

## Publish

- Converge the `review-plan` loop first; nothing reaches GitHub before that.
- Settle where the artifact gets published before posting anything.
- On the findings entry, first check the tracking issue's comments for the report itself; when it is already there, cite that comment's URL.
- When the report is in chat only, post it ahead of the design comment through `using-dude`'s **Stage boundaries** confirm-then-publish ask.
- If that ask is declined, settle with a person how the design comment meets **Output contract**'s citation rule, since a report left in chat with no URL cited leaves children carrying a parent URL with no baseline under it.
- Post the design, the split policy, and the numbered TODO list as one comment for this work, and take its id now, before any child exists.
- Never edit your last comment on the issue instead, since that overwrites that comment's content, such as the findings report just posted, while the run reports a fresh publish.
- On re-entry there is no new post: recover that comment's id from the `#issuecomment-<id>` fragment of the URL the children carry, and edit that comment.
- Never post again on re-entry, since two design comments leave the children citing the older one.
- Land the children in TODO order, each carrying that comment's URL.
- On re-entry, update the existing children per **Splitting into sub-issues** instead of creating a fresh set, since a fresh set duplicates every child with no record of which is current.
- Then edit that comment in place to append the list of sub-issues; that edit is not a second publish.

## Pass

1. Resolve **Entry**. A design invalidated downstream skips steps 2 and 3. Investigation findings skip step 2.
2. Invoke `propose-alternatives` once when the purpose is named: the tracking issue's problem, or the request's problem with no issue. Hand it that purpose, the current artifact — the issue or request and the means it asks for — and the read root, the default branch: use the session checkout only when it already sits on that branch, otherwise read the default-branch ref, fetched to its current tip, never the session tree; create no worktree. Reading the session tree on a feature branch judges alternatives against unmerged commits, recommending a shape that holds only atop work that may never merge. Compare, the one review-findings pass, and the ask-person continue-vs-revisit are `propose-alternatives`'s own procedure: on return continue, and on revisit design take the finding to **Design agreement** without proceeding to step 3. Carrying a revisit-design finding onward brings an unapproved shape into the TODO list while the record claims agreement.
3. Research: read the issue, where there is one, and the relevant code before asking or proposing. Proposing before reading publishes boundaries contradicting the codebase, and `review-plan` reviews fictional scope.
4. Reach **Design agreement**.
5. Draft the design write-up and the numbered TODO list yourself against **Output contract**, on re-entry including the match against existing children, settled before step 6. Drafting without that match lets review approve a list silently duplicating or dropping existing children.
6. Run `review-plan` with the target declared as the TODO list. Fold every accepted finding in yourself, then re-run with the previous pass's findings record: accepted and fixed, rejected with the reason. Re-running without that record lets a rejected finding return reworded and get folded in, oscillating the list while each pass reads as progress. A finding invalidating the agreed design is not folded in at all: take **Escalation**. Folding it in ships a redesigned plan under an agreement never given.
7. Do not leave step 6 while a blocking finding remains: leaving open publishes while the report claims convergence, and implementation starts on an item review rejects.
8. **Publish**.

## Escalation

- This is clean per `using-dude`'s **Loop convergence** loop-clean when the published artifact satisfies **Output contract** and the last `review-plan` pass returned no blocking finding.
- This loop's stopping conditions are `using-dude`'s **Loop convergence**.
- One round is one `review-plan` pass plus its fold-in.
- A finding repeats when a later pass makes the same objection to the same item, whatever words it arrives in.
- Never fix a Critical finding invalidating the agreed design in this loop: stop and return to **Design agreement** for re-approval, since fixing it in the loop ships a new design under the old agreement, showing approval that never happened.

## Report

- Report the entry and the carried input.
- Report the step-2 invoke-or-skip and why.
- Report the publish location: comment URL, or chat and why.
- Report the `review-plan` rounds and verdict, accepted findings folded in and rejected ones with reasons.
- Report the sub-issues created, or none when no tracking issue backs the work and the user declined.
- On re-entry, report sub-issues left alone, updated, and created.
- On re-entry, report per-item branch reuse vs new name.
- On re-entry, report branches, worktrees, open PRs, and dropped children left for a person to clean up.
- Report assumptions and anything unverified.
