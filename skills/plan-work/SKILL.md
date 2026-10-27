---
name: plan-work
description: Use to plan a change, including a multi-PR fix that arrives on investigation findings.
---

# Plan Work

## Orchestration model

- The orchestrator owns every decision: research, invoking `superpowers:brainstorming` and `review-plan`, drafting the TODO list, folding accepted findings in, calling convergence or escalation, and publishing. Delegated decisions publish a plan nobody decided, reported as agreed.
- Those two skills own their internal procedures: supply their inputs and act on their outputs, never reaching inside or dispatching reviewers, or the plan reads as reviewed without passing review. `review-plan` never edits what it reviewed, so folding in and re-running belong here: expecting it to apply edits publishes the pre-findings list as if findings were folded in.
- Nothing else drafts the TODO list: no sub-skill produces a PR-granularity breakdown, so write it here against **Output contract**.
- This skill dispatches no worker. Invoke `propose-alternatives` by name; it owns its procedure.

## Boundaries

- Never touch the working tree: no worktree, no branch, no commit, no code edit. This flow has no worktree, so a design committed here lands on whatever branch the session holds, usually `master`. Redirect a sub-skill's file-and-commit output into the comment, or it lands on the session branch with the comment carrying nothing.
- The canonical record is the tracking issue's comment; chat only when no issue tracks the work, with **Output contract** binding that version. A design left in chat while an issue tracks the work leaves the next session nothing to pick up, and the work gets planned twice.
- Every GitHub write here is a native operation: posting or editing a comment, creating a child, writing a child's body. Pass each body from a file, never inline or as a flag string: inline backticks get shell-expanded, and a path passed where the body belongs posts the path itself as the body. Read every posted or edited body back, or the record silently differs from the draft. A body past GitHub's size limit signals further splitting, never truncation.
- Creating a child and attaching it to its parent is one native operation, so no script wraps it. Never attach via the raw `sub_issues` endpoint: it identifies the child by database id rather than issue number, so a number passed there silently attaches whichever issue holds that id from whatever repository.

## Entry

- An issue number: read the issue and its comments before anything else, or the plan contradicts decided context while reading as informed.
- A planning request with no tracking issue: the research in **Pass** step 3 runs, and **Splitting into sub-issues** asks for a tracking issue before anything is published. Skipping research drafts against unread code; children with no parent have no design URL to cite.
- Investigation findings enter at research (**Pass** step 3), skipping **Pass** step 2: the root cause is established, so research settles the fix shape, and the proposed options are input to that agreement, never the agreement itself. A question-shaped report (`settle-question`) carries no reproduction: its Verdict and Next items stand in for baseline and options, and the findings-report citation suffices to receive it. Demanding a reproduction stalls on an input that never exists. Should research contradict the root cause, do not re-diagnose here: take `using-dude`'s **Escalation** back to the investigation, or a fresh guess replaces the claimed root cause.
- A design invalidated downstream arrives with the finding and which part of the design it undoes, the existing branch's name, and that branch's state: whether it is pushed and whether a PR is open on it. Without the name and state, items cannot name reuse or discard, and an old-named item quietly resumes atop the invalidated commits. Re-enter at **Design agreement**, skipping **Pass** steps 2 and 3: re-running research publishes a different design while claiming re-approval. Where an issue tracks the work it stays the canonical record, so the re-approved design edits that same comment in place: a second design comment leaves children citing the older one.

## Design agreement

- Reach it with `superpowers:brainstorming`, run to its self-review and the user's confirmation, or the run publishes an unapproved draft as the agreed design.
- Do not follow it onward, however emphatically it says to: take that draft and draft the TODO list yourself. Following its trailing pointer starts implementation inside planning, landing edits on the session branch.

## Output contract

- The artifact is the design plus a numbered TODO list of PR-sized items shaped so `implement-work` can pick up any one item: background, design and rationale, split policy, numbered list, per-item parallel-or-stacked order, affected area at module or directory granularity.
- Each item states its purpose, its scope boundary including what it excludes, and its completion criteria. Without an exclusions boundary the item is implemented beyond its PR, landing the next item's changes unreviewed inside it.
- Each item names whether it starts in parallel or stacks on an earlier one, never implying the order, plus the dependency order wherever anything stacks. Every item stands verifiable on its own; stacking gives up independent starting, so a stacked item names the item it waits for and why. An implied order has `implement-work` cut the stacked branch from the default branch instead of the prerequisite's head, omitting its base.
- Deliberately absent: exact paths, line numbers, per-task verification commands, edge-case enumeration. Those belong to `implement-work`. Enumerated paths go stale, and the PR edits the wrong lines while citing the plan as authority.
- From investigation findings: the reproduction goes into the completion criteria of the item owning the fix, as a regression test failing before and passing after, or the observation window and metric for a production-only symptom. Without it the item passes without ever exhibiting the symptom, closing the issue while the bug stands. From a question-shaped report there is no reproduction to carry: the findings-report citation is the baseline and the criteria verify against the cited verdict. Either way, cite the report by URL, since a sub-issue carries this comment's URL and nothing else: an uncited report is unreachable, so `implement-work` verifies against no baseline and reports success on any green run.
- From a design invalidated downstream: every item accounts for the existing branch. Reuse it and the item names it, or discard it and the item names a new one: `implement-work` reuses whatever branch it finds and has no rung discarding one, so an item carrying the old name quietly resumes atop the invalidated commits. Name the discarded branch in the artifact as a person's cleanup, with the worktree checked out on it and identified by that branch rather than by a path, since this flow is never handed one: a path-named cleanup strands the worktree. Name any open PR by number: its body still holds the closing keyword, so merging it later lands the invalidated commits and closes the child behind them. Each item also names, by number, its existing child, so **Publish** acts on the reviewed match: a re-derived match updates the wrong child. Work finished before the invalidation stays out of the numbered list and goes in the split policy instead, each entry carrying its child's number and merged fact, recorded: dropped work gets rebuilt as a duplicate PR.

## Splitting into sub-issues

- One sub-issue per item, whatever the count. Where a tracking issue exists they are not optional: without them `implement-work` has no named entry for a single PR, leaving a later session nothing to pick up. With no tracking issue, ask for one before publishing; if the user declines, publish in chat with no sub-issues and write the consequence into the artifact: every item must finish in this one session. An unwritten consequence reads as a normal publish, and a later session silently starts from zero.
- The parent comment carries the design, the split policy, and the list of sub-issues. Each child carries its purpose, scope boundary, completion criteria, prerequisite and why (or that it has none), the parent design comment's URL, and, only where the item carries a branch name, that name bare and never decorated: a decorated name defeats the next session's branch search, so it cuts a second branch. A child missing the parent comment's URL cannot reach the design, so `implement-work` plans from the child's fragment alone. Nothing more belongs in the child: a PR-sized plan there defeats the split.
- A prerequisite is one line in the child's body, `Blocked-By: #N`, alone on its line, `N` the issue number of the one earlier item it stacks on; an independent item gets no such line. A prose-form prerequisite stays unread by `implement-work`'s base resolution, which settles the base on the default branch, not the prerequisite's head. After writing a child's body, read it back into a file, run `tools/prereq-line.sh <file>`: it must answer `PREREQ <N>` for the intended `N`, or `NONE` for an independent item. Otherwise fix the body and re-check: a stacked child whose line was dropped answers `NONE`, cutting its task from the default branch.
- Converge the `review-plan` loop against the whole, undivided TODO list before splitting: splitting first lets review renumber items, invalidating every child mapping.
- On re-entry, enumerate the existing children from the parent's sub-issue relation, never the comment's prose: a child added after the last edit is missing there, and its item gets a second child. Match by each item's substance, never its wording: a rephrased item otherwise reads as one dropped plus one added, closing a live child and opening a duplicate. Match before `review-plan` sees the list, which must already account for what is finished, or review re-splits merged children. Re-match items a fold-in changed.
- A surviving item's child has its body brought up to date, prerequisite line included, keeping nothing the item no longer says: a stale line survives, cutting new work from a wrong base. An item with no child gets one, as on a first publish, or the item is never picked up while the list claims completeness. A child whose item is gone is named in the artifact as a person's cleanup: the close is theirs, and the sub-issue link stays as the drop record. A closed child matching a live item stops the run: the relation carries no close reason, so proceeding either rebuilds merged work or silently drops a live item.

## Publish

- Converge the `review-plan` loop first; nothing reaches GitHub before that.
- Settle where the artifact gets published before posting anything. On the findings entry, first check the tracking issue's comments for the report itself: already there, cite that comment's URL; in chat only, post it ahead of the design comment, via `using-dude`'s **Stage boundaries** confirm-then-publish ask; if that ask is declined, settle with a person how the design comment meets **Output contract**'s citation rule. A report left in chat with no URL cited leaves children carrying a parent URL with no baseline under it.
- Post the design, the split policy, and the numbered TODO list as one comment for this work, and take its id now, before any child exists; never edit your last comment on the issue instead. Editing it instead overwrites that comment's content, such as the findings report just posted, while the run reports a fresh publish.
- On re-entry there is no new post: that comment exists, and its id is the `#issuecomment-<id>` fragment of the URL the children carry, so recover it there and edit. Posting again leaves two design comments with the children citing the older one.
- Land the children in TODO order, each carrying that comment's URL. On re-entry, update the existing children per **Splitting into sub-issues** instead of creating a fresh set: a fresh set duplicates every child with no record of which is current.
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
- This loop's stopping conditions are `using-dude`'s **Loop convergence**. One round is one `review-plan` pass plus its fold-in; a finding repeats when a later pass makes the same objection to the same item, whatever words it arrives in. A Critical finding invalidating the agreed design is never fixed in this loop: stop and return to **Design agreement** for re-approval. Fixing it in the loop ships a new design under the old agreement, showing approval that never happened.

## Report

- Entry and carried input; step-2 invoke-or-skip and why; publish location: comment URL, or chat and why.
- `review-plan` rounds and verdict, accepted findings folded in and rejected ones with reasons; sub-issues created (on re-entry: left alone, updated, created) or none, since no tracking issue backs the work and the user declined.
- On re-entry: per-item branch reuse vs new name, plus branches, worktrees, open PRs, and dropped children left for a person to clean up; assumptions and anything unverified.
