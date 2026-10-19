---
name: plan-work
description: Use to plan a change, including a multi-PR fix that arrives on investigation findings.
---

# Plan Work

Turns an issue or a planning request into work `implement-work` can pick up one PR at a time.

## Orchestration model

- The orchestrator owns everything that decides: research, invoking `superpowers:brainstorming` and `review-plan`, drafting the TODO list, folding the accepted findings in, calling convergence or escalation, and publishing.
- Those two skills own their own internal procedures — dispatch model, lenses, self-review, user gate. Supply their inputs and act on their outputs; never reach inside them, dispatch reviewers yourself, or reimplement what they already do. `review-plan` never edits what it reviewed, so folding findings in and re-running belong here.
- **Nothing else drafts the TODO list.** No sub-skill produces a PR-granularity breakdown, so don't go looking for one to delegate to — write it here, against **Output contract**.
- This skill dispatches no worker of its own. Invoke `propose-alternatives` and, on a finding, `review-findings` by name; those skills own their procedures.

## Boundaries

- **Never touch the working tree** — no worktree, no branch, no commit, no code edit, throughout rather than only at the end. This flow has no worktree, so a design document committed here lands on whatever branch the session is on, usually `master`. A sub-skill that assumes it should write a file and commit it does neither: redirect that output into the comment.
- The canonical record is the tracking issue's comment — chat only when no issue tracks the work, and **Output contract** binds that version just the same, not as a lesser one.
- **Every GitHub write this flow makes is a native operation** — posting a comment, editing it, creating a child, writing a child's body — by whatever means are available, the body passed from a file rather than a flag string: inline, a plan body hands its backticks to the shell, and a path passed where the body belongs is posted as the body itself and reported as success — pass the body as file contents, never a path string. Read each posted or edited body back, comment or child, and confirm it is the drafted text. A body over GitHub's size limit is a signal to split the work further, never to truncate it.
- **Creating a child and attaching it to its parent is one native operation** (per `AUTHORING.md`'s carve-out), so no script wraps it: do it by whatever means are available. Never attach through the raw `sub_issues` endpoint — it identifies the child by database id rather than by issue number, so a number passed there silently attaches whichever issue holds that id from whatever repository.

## Entry

- **An issue number** — read the issue and its comments before anything else.
- **A planning request with no tracking issue** — the research in **Pass** step 3 still runs. **Splitting into sub-issues** asks for a tracking issue before anything is published.
- **Investigation findings** — arrives with three things: the findings report, the reproduction or observation baseline, and the fix options the investigation proposed. A **question-shaped** report (`settle-question`) carries no reproduction: its **Verdict** and **Next items** arrive in place of the baseline and the fix options, and the findings-report citation suffices to receive it. The three option names (`Remediation options` / `Fix options` / `Verdict`+`Next items`) read as that same input under their source skill's name. Enter at research (**Pass** step 3), skipping **Pass** step 2, rather than at **Design agreement**: the root cause is established, so what research settles is the shape of the fix, and those options are input to that agreement, never the agreement itself. Should research contradict the root cause, don't re-diagnose it here — take `using-dude`'s **Escalation** back to the investigation.
- **A design invalidated downstream** — arrives with three things: the finding and which part of the design it undoes, the existing branch's name, and that branch's state, meaning whether it is pushed and whether a PR is open on it. Re-enter at **Design agreement**, skipping **Pass** steps 2 and 3, since the design is what needs re-approval. Where an issue tracks the work it is still the canonical record, so the re-approved design edits that same comment in place rather than adding another.

## Design agreement

Reach it with `superpowers:brainstorming`, run to its own self-review and the user's confirmation. **Don't follow it onward to the next skill**, however emphatically it says to. What this flow takes from it is that draft alone. Then come back and draft the TODO list yourself.

## Output contract

The published artifact is the design plus a numbered list of PR-sized items, and it has to let `implement-work` pick up any one item and plan it — not implement from it directly:

- background — what problem this solves and why
- design and rationale — the approved shape, and why not the alternatives
- the split policy — where the PR boundaries fall and why
- a **numbered** TODO list, one item per PR, each stating its purpose, its scope boundary including what it excludes, and its completion criteria
- per item, whether it can be started in parallel or must be stacked on an earlier one — named, not implied — plus the dependency order wherever anything stacks. Every item must be **verifiable** on its own; being **startable** on its own is what stacking gives up, so a stacked item names the item it waits for and why.
- affected area at module or directory granularity

**Deliberately absent:** exact paths, line numbers, per-task verification commands, edge-case enumeration. Those belong to `implement-work`.

Two entries add to that list:

- **From investigation findings** — the reproduction goes into the completion criteria of the item that owns the fix, per `using-dude`'s **Investigation → Change transition**. It takes one of two forms: a regression test that fails before the fix and passes after, or, for a symptom observable only in production, the observation window and the metric that shows it. From a question-shaped report there is no reproduction to carry: the findings-report citation is the receivable baseline, and the item's criteria verify against the cited verdict instead. The steps behind either stay in the findings report, so cite that report here by URL — a sub-issue carries this comment's URL and nothing else, so an uncited report is one it cannot reach.
- **From a design invalidated downstream** — every item accounts for the existing branch.
  - **Reuse** it and the item names it, or **discard** it and the item names a **new** one.
  - `implement-work`'s isolation ladder reuses whatever branch it finds and has no rung that discards one, so an item carrying the old name would quietly resume work on top of the very commits the invalidated design produced.
  - Name the discarded branch in the artifact as a person's cleanup, with the worktree checked out on it — identified by that branch rather than by a path, since this flow is never handed one.
  - Name any open PR by number: its body still holds the closing keyword, so merging it later would land the invalidated commits *and* close the child behind them.
  - Each item also names, by number, the existing child it corresponds to, so **Publish** acts on a match that was visible in the list under review rather than re-derived afterwards.
  - Work already finished before the invalidation stays out of the numbered list and goes in the split policy instead, each entry carrying its child's number and the fact that its PR merged — recorded either way, because work dropped from the record gets rebuilt.

## Splitting into sub-issues

One sub-issue per item, whatever the count. Where a tracking issue exists they aren't optional: without them `implement-work` has no named entry for a single PR. **No tracking issue → ask for one before publishing anything.** If the user declines, publish in chat with no sub-issues and write the consequence into the artifact itself: with no named entry per PR, every item has to be carried to completion in this one session, because a later session inherits nothing to pick up.

- **The parent comment** carries the design, the split policy, and the list of sub-issues. **Each child** carries its purpose, its scope boundary, its completion criteria, its prerequisite and why (or that it has none), the parent design comment's URL, and — only where the item carries a branch name — that name. Nothing more: a PR-sized plan in the child puts the detail back where it was and defeats the split.
- **A prerequisite is one line in the child's body, `Blocked-By: #N`, alone on its line, `N` the issue number of the one earlier item it stacks on; an independent item gets no such line.** It is what `implement-work` reads to pick the base, so it never has to parse prose; the prose still carries the reason. After writing a child's body, read the body back into a file and run `tools/prereq-line.sh <file>`: it must answer `PREREQ <N>` for the intended `N`, or `NONE` for an independent item — anything else, fix the body and check again.
- Converge the `review-plan` loop against the whole, undivided TODO list before splitting.
- **On re-entry, children from the previous approval already exist, and one child per item still holds.**
  - Enumerate them from the parent's sub-issue relation, never from the parent comment's prose.
  - That prose records what was published, so a child added after the last edit is missing from it and the item it belongs to would be given a second one.
  - Match them by each item's **substance**, never its wording: items are renumbered and rephrased freely, so a rephrased one would otherwise read as an item dropped plus an item added.
  - Match before `review-plan` sees the list, since the list has to already account for what is finished.
  - Re-match any item a fold-in changed — those only.
- Update the children to match the list.
  - A surviving item's child has its body brought up to date — its prerequisite line included — keeping nothing the item no longer says.
  - An item with no child gets one, as on a first publish.
  - A child whose item is gone from the list is named in the artifact as a person's cleanup — the close is theirs, and the sub-issue link stays as the record that the item was dropped.
  - **A closed child that matches a live item stops the run, whatever it was closed for.**
  - The sub-issue relation carries no close reason, so a child closed as dropped and one whose PR merged arrive at this rule identical, and reading either as the other either drops the item silently or rebuilds work that is already merged.
  - Ask a person which it is.

## Publish

1. Converge the `review-plan` loop. Nothing reaches GitHub before that.
2. **Settle where it gets published**, before anything is posted: no tracking issue → ask, per **Splitting into sub-issues**. On the findings entry, first check the tracking issue's comments for the report itself: already there → cite that comment's URL; in chat only → post it ahead of the design comment, through `using-dude`'s **Stage boundaries** confirm-then-publish ask; the ask declined → settle with a person how the design comment meets **Output contract**'s citation rule before writing it.
3. **Post** the design, the split policy, and the numbered TODO list — one comment for this work — and take its id now, **before any child exists**; never edit your last comment on the issue instead. **On re-entry there is no new post**: that comment already exists, and its id is the `#issuecomment-<id>` fragment of the URL the children carry — recover it there and edit, because posting again would leave two design comments with the children citing the older one.
4. **Land the children** in TODO order, each carrying that comment's URL — a stacked item's body cites its prerequisite's issue number, and dependencies point back at earlier items, so working in order means that number already exists. On re-entry, update the existing children per **Splitting into sub-issues** instead of creating a fresh set. Then **edit that same comment in place** to append the list of sub-issues; editing it is not a second publish.

## Pass

1. Resolve **Entry**. A design invalidated downstream skips steps 2 and 3. Investigation findings skip step 2.
2. Invoke `propose-alternatives` once when the purpose is named.
   - **Purpose:** the tracking issue's problem; with no issue, the request's problem. Unnamed → skip; do not invoke; chat the skip; continue. No new prompt.
   - **Read-root:** the default branch. Use the session checkout only when it is already that branch; otherwise read the default-branch ref, fetched to its current tip, and do not pass the session tree. Do not create a worktree, read-only or not.
   - Else invoke `propose-alternatives` once with that purpose and read-root. Do not show the current artifact, the current means, an issue URL or body, or this session's context.
   - Compare the proposal with the work as currently framed — the issue or request and the means it asks for — on purpose, means, and cost, per `propose-alternatives`'s **Caller contract**.
   - Empty finding → no `review-findings`; do not wait; continue; chat.
   - Finding → `review-findings` one pass per `using-dude`'s **Stage boundaries**; chat; wait for **continue** vs **revisit design** (revisit: take the finding to **Design agreement**). Do not proceed to step 3 except on **continue**. **Don't follow `review-findings` onward to the next skill.** The proposal is not a finding, not `needs-user`, not Critical auto-reapproval, and is not posted to a PR.
3. Research: read the issue, where there is one, and the relevant code before asking anything or proposing a design.
4. Reach **Design agreement**.
5. Draft the design write-up and the numbered TODO list yourself, against **Output contract** — on re-entry, including the match against existing children, settled before step 6.
6. Run `review-plan` with the target declared as the TODO list. Fold every accepted finding in yourself, then re-run it with the record of the previous pass — findings accepted and fixed, findings rejected with the reason. A finding that invalidates the agreed design is not folded in at all: take **Escalation**.
7. Don't leave step 6 while a blocking finding remains.
8. **Publish**.

This is clean per `using-dude`'s **Loop convergence** loop-clean when the published artifact satisfies **Output contract** and the last `review-plan` pass returned no blocking finding.

## Escalation

This loop's stopping conditions are `using-dude`'s **Loop convergence**. One round is one `review-plan` pass plus the fold-in that follows it, and a finding repeats when a later pass makes the same objection to the same item, whatever words it arrives in. A Critical finding that invalidates the agreed design is never fixed in this loop: stop and return to **Design agreement** for re-approval.

## Report

- the entry, and what it carried — for findings, the investigation's report; for an invalidated design, the finding and the branch it came back with
- where step 2 ran: invoked or skipped and why; empty finding or finding; on a finding, that the run waited
- where the result was published: the comment URL, or that chat is the record and why
- the `review-plan` rounds run and the final verdict, with accepted findings folded in and rejected findings given their reason
- the sub-issues created — on re-entry, the breakdown of children left alone, updated, and created — or that there are none because no tracking issue backs the work and the user declined to create one
- on re-entry: which branch each item reuses, which items got a new name instead, and the branches, worktrees, open PRs, and dropped children left for a person to clean up
- assumptions made, and anything that could not be verified
