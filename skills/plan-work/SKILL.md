---
name: plan-work
description: Use to turn an issue, a planning request, or an investigation's findings into an agreed design and a numbered TODO list at PR granularity, before any code is touched. Triggers on "plan this", "plan issue <n>", "turn this into a plan", "break this into PRs", "brainstorm and plan this".
---

# Plan Work

Turns an issue or a planning request into work `implement-work` can pick up one PR at a time.

## Orchestration model

**This skill dispatches no workers of its own.** It runs in the main loop as the orchestrator, and the only workers in this flow are the reviewers `review-plan` dispatches under its own declaration.

- The orchestrator owns everything that decides: research, invoking `superpowers:brainstorming` and `review-plan`, drafting the TODO list, judging findings and folding the accepted ones in, calling convergence or escalation, and publishing.
- Those two skills own their own internal procedures — dispatch model, lenses, self-review, user gate. Supply their inputs and act on their outputs; never reach inside them, dispatch reviewers yourself, or reimplement what they already do. `review-plan` never edits what it reviewed, so folding findings in and re-running belong here.
- **Nothing else drafts the TODO list.** No sub-skill produces a PR-granularity breakdown, so don't go looking for one to delegate to — write it here, against **Output contract**.

## Boundaries

- **Never touch the working tree** — no worktree, no branch, no commit, no code edit, throughout rather than only at the end. This flow has no worktree, so a design document committed here lands on whatever branch the session is on, usually `master`. A sub-skill that assumes it should write a file and commit it does neither: redirect that output into the comment.
- The canonical record is the tracking issue's comment — chat only when no issue tracks the work, and **Output contract** binds that version just the same, not as a lesser one.
- `<skill-dir>/scripts/` holds the GitHub mechanism — `<skill-dir>` being this skill's own directory inside the installed plugin, `skills/plan-work/` — one script per operation, each closing a way of getting it silently wrong: `<skill-dir>/scripts/post-plan-comment.sh` for anything this flow posts, the design comment and the findings report alike, and `<skill-dir>/scripts/edit-plan-comment.sh` for revising it, taking the numeric id the first prints; `<skill-dir>/scripts/set-prerequisites.sh` for the native relation. Use them rather than hand-built calls — a body passed as a flag string hands its backticks to the shell.
- **Creating a child and attaching it to its parent is one native `gh` operation**, so no script wraps it: create the child with `gh issue create --parent`, reading its body from a file, and attach one that already exists with `gh issue edit --add-sub-issue`. Never attach through the raw `sub_issues` endpoint — it identifies the child by database id rather than by issue number, so a number passed there attaches whichever issue happens to hold that id, silently and from whatever repository.

## Entry

- **An issue number** — read the issue and its comments before anything else.
- **A planning request with no tracking issue** — the research in **Pass** step 2 still runs. **Splitting into sub-issues** asks for a tracking issue before anything is published.
- **Investigation findings** — arrives with three things: the findings report, the reproduction or observation baseline, and the fix options the investigation proposed. Enter at research like the entries above rather than at **Design agreement**: the root cause is established, so what research settles is the shape of the fix, and those options are input to that agreement, never the agreement itself. Should research contradict the root cause, don't re-diagnose it here — take the guidelines' **Escalation** back to the investigation.
- **A design invalidated downstream** — arrives with three things: the finding and which part of the design it undoes, the existing branch's name, and that branch's state, meaning whether it is pushed and whether a PR is open on it. Re-enter at **Design agreement**, since the design is what needs re-approval. Where an issue tracks the work it is still the canonical record, so the re-approved design edits that same comment in place rather than adding another.

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

- **From investigation findings** — the reproduction goes into the completion criteria of the item that owns the fix, per the guidelines' **Investigation → Change transition**. It takes one of two forms: a regression test that fails before the fix and passes after, or, for a symptom observable only in production, the observation window and the metric that shows it. The steps behind either stay in the findings report, so cite that report here by URL — a sub-issue carries this comment's URL and nothing else, so an uncited report is one it cannot reach.
- **From a design invalidated downstream** — every item accounts for the existing branch: **reuse** it and the item names it, or **discard** it and the item names a **new** one. `implement-work`'s isolation ladder reuses whatever branch it finds and has no rung that discards one, so an item carrying the old name would quietly resume work on top of the very commits the invalidated design produced. Name the discarded branch in the artifact as a person's cleanup, with the worktree checked out on it — identified by that branch rather than by a path, since this flow is never handed one — and any open PR by number: its body still holds the closing keyword, so merging it later would land the invalidated commits *and* close the child behind them. Each item also names, by number, the existing child it corresponds to, so **Publish** acts on a match that was visible in the list under review rather than re-derived afterwards. Work already finished before the invalidation stays out of the numbered list and goes in the split policy instead, each entry carrying its child's number and the fact that its PR merged — recorded either way, because work dropped from the record gets rebuilt.

## Splitting into sub-issues

One sub-issue per item, whatever the count. Where a tracking issue exists they aren't optional: without them `implement-work` has no named entry for a single PR. **No tracking issue → ask for one before publishing anything.** If the user declines, publish in chat with no sub-issues and write the consequence into the artifact itself: with no named entry per PR, every item has to be carried to completion in this one session, because a later session inherits nothing to pick up.

- **The parent comment** carries the design, the split policy, and the list of sub-issues. **Each child** carries its purpose, its scope boundary, its completion criteria, its prerequisites, the parent design comment's URL, and — only where the item carries a branch name — that name. Nothing more: a PR-sized plan in the child puts the detail back where it was and defeats the split.
- **The prerequisite line is always present**, and it carries the reason: either `#12 のマージが先行して必要（同一ファイルを触るため）` or `なし（並列に着手できる）`, that phrasing and its parenthetical included.
- **A prerequisite is also a native relation, and an independent item gets none at all.** The relation is what `implement-work` reads, so it never has to parse prose. Confirm the resulting count is the one intended — 0 for an independent item.
- Converge the `review-plan` loop against the whole, undivided TODO list before splitting.
- **On re-entry, children from the previous approval already exist, and one child per item still holds.** Enumerate them from the native relation, never from the parent comment's prose: that prose records what was published, so a child added after the last edit is missing from it and the item it belongs to would be given a second one. Match them by each item's **substance**, never its wording: items are renumbered and rephrased freely, so a rephrased one would otherwise read as an item dropped plus an item added. Match before `review-plan` sees the list, since the list has to already account for what is finished, and re-match any item a fold-in changed — those only.
- A surviving item's child has its body brought up to date and its relations rewired in both directions; an item with no child gets one, as on a first publish; and a child whose item is gone from the list is named in the artifact as a person's cleanup — the close is theirs, and the sub-issue link stays as the record that the item was dropped. **A closed child that matches a live item stops the run, whatever it was closed for**: the native relation carries no close reason, so a child closed as dropped and one whose PR merged arrive at this rule identical, and reading either as the other either drops the item silently or rebuilds work that is already merged. Ask a person which it is.

## Publish

1. Converge the `review-plan` loop. Nothing reaches GitHub before that.
2. **Settle where it gets published**, before anything is posted: no tracking issue → ask, per **Splitting into sub-issues**. On the findings entry the report is posted here too, ahead of the design comment, so the URL that comment has to cite already exists when it is written.
3. **Post** the design, the split policy, and the numbered TODO list — one comment for this work — and take its id now, **before any child exists**; never edit your last comment on the issue instead. **On re-entry there is no new post**: that comment already exists, and its id is the `#issuecomment-<id>` fragment of the URL the children carry — recover it there and edit, because posting again would leave two design comments with the children citing the older one.
4. **Land the children** in TODO order, each carrying that comment's URL — a stacked item's body cites its prerequisite's issue number, and dependencies point back at earlier items, so working in order means that number already exists. On re-entry, update the existing children per **Splitting into sub-issues** instead of creating a fresh set. Then **edit that same comment in place** to append the list of sub-issues; editing it is not a second publish.

## Pass

1. Resolve **Entry**. A design invalidated downstream skips step 2.
2. Research: read the issue, where there is one, and the relevant code before asking anything or proposing a design.
3. Reach **Design agreement**.
4. Draft the design write-up and the numbered TODO list yourself, against **Output contract** — on re-entry, including the match against existing children, settled before step 5.
5. Run `review-plan` with the target declared as the TODO list. Fold every accepted finding in yourself, then re-run it with the record of the previous pass — findings accepted and fixed, findings rejected with the reason — so it doesn't re-litigate what was already rejected. A finding that invalidates the agreed design is not folded in at all: take **Escalation**.
6. Don't leave step 5 while a blocking finding remains.
7. **Publish**.

This is clean when the published artifact satisfies **Output contract** and the last `review-plan` pass returned no blocking finding.

## Escalation

This loop's stopping conditions are the guidelines' **Loop convergence**. One round is one `review-plan` pass plus the fold-in that follows it, and a finding repeats when a later pass makes the same objection to the same item, whatever words it arrives in. A Critical finding that invalidates the agreed design is never fixed in this loop: stop and return to **Design agreement** for re-approval.

## Report

- the entry, and what it carried — for findings, the investigation's report; for an invalidated design, the finding and the branch it came back with
- where the result was published: the comment URL, or that chat is the record and why
- the `review-plan` rounds run and the final verdict, with accepted findings folded in and rejected findings given their reason
- the sub-issues created — on re-entry, the breakdown of children left alone, updated, and created — or that there are none because no tracking issue backs the work and the user declined to create one
- on re-entry: which branch each item reuses, which items got a new name instead, and the branches, worktrees, open PRs, and dropped children left for a person to clean up
- assumptions made, and anything that could not be verified
