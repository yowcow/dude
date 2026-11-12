---
name: propose-alternatives
description: Use as a component when another skill needs the most direct route to a named purpose, including doing nothing or doing something else.
---

# Propose Alternatives

- Edit nothing here.
- Post nothing here.

## Orchestration model

- Dispatch no worker for an unnamed purpose.
- Otherwise always dispatch one read-only worker in a fresh context.
- Propose never inline.
- Keep the worker read-only: it edits nothing.
- Let it commit nothing.
- Let it create no worktree.
- Take back the proposal, plus the command and raw output of any measurement it took.
- Take back the path of each file it wrote when that output was too large to return.
- Send the worker out at the `highest` tier in `using-dude`'s **Worker tier**: a missed alternative never appears downstream.

## Inputs

The caller hands:

- **The named purpose** — the origin purpose: the problem to solve, not the means.
  - Where an issue backs the work, it is the problem of the issue reached by following the parent relation up until no parent remains, since a sub-issue's own purpose is a means its parent's design chose.
  - Stop at the highest issue read where a parent cannot be read, report the stop, and continue the invocation.
  - Stop at a child whose body carries no URL of its parent's design comment, take that child's purpose, report the stop, and continue the invocation.
  - An issue with no parent, or work with no issue, keeps its own purpose.
- **The read-root** — a commit SHA the caller resolved, never a ref, branch name, or work-tree path, since a stacked task's base is a feature branch whose name would otherwise enter the brief. Which commit belongs to the caller.
- **The current artifact** — the work as currently framed, with the agreed design comment of each level the walk passed, read from each child's link to its parent's design comment. The worker never sees it.
- **The caller's budget for the one measurement** — when the caller has one.
- Without it, the default this dispatch names applies.

## Pass

- Skip an unnamed purpose: dispatch nothing and return that skip.
- Allow no other skip.
- Otherwise dispatch once.
- Hand the worker the read-root SHA besides the purpose, naming no repository path, branch, or worktree.
- Let it read only with read-only plumbing named by that SHA — object reads, tree listings, searches — never a work tree, since the object store every worktree shares resolves the SHA from wherever the worker starts.
- Create no worktree for the worker.
- Take only what read-only plumbing against that SHA can answer as its measurement, since a measurement needing an executable copy of that commit is outside what the worker may take.
- Limit its one measurement to the caller's budget when the caller has one.
- Otherwise limit it to the default this dispatch names.
- Name a directory outside the work tree, its path naming no branch or worktree, for output too large to return.
- Ask for the proposal shape: the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs.
- Show it nothing else: neither the current artifact, the current means, an issue URL or body, nor this session's context.
- Let the worker measure at most once.
- Bound that measurement by that time limit, taken against that SHA.
- Take back the command and its raw output rather than a summary.
- Take back the path of each file it wrote when the output is too large to return.
- Return the worker's proposal as-is.
- Rewrite never a proposal into "the current direction is fine".

## Compare

- Compare the proposal with the current artifact.
- Judge neither the worker nor the caller there.
- Treat as a finding only what turns its reader to another direction, and only these four:
  - the current means, read with the agreed designs on the way, does not meet the origin purpose, or no longer serves it
  - the current artifact holds a step the origin purpose does not need
  - the current artifact loses a property the read-root had with no benefit worth it written down, weighing cost per `using-dude`'s **Design yardstick**
  - at the macro level, a premise the current artifact stands on has broken
- Treat never an alternative reaching the same result and differing only in preference as one.
- Treat never an alternative a design on the way declined as one, unless the proposal brings a fact that design did not have.
- Treat never a sub-issue's artifact carrying only part of the origin purpose as one.
- Count never a step a sibling sub-issue carries as one the origin purpose does not need.
- With no finding, return continue with no finding and let the caller continue its work.
- With a finding, run `review-findings` on that comparison per its **Caller contract**.
- Chat the finding with its trade-offs and a recommendation.
- Wait there for the person's **continue** vs **revisit design** per `using-dude`'s **Escalation**.
- Return that answer to the caller.
- Return a revisit with the finding, since where the revisit lands is the caller's under `using-dude`'s **Escalation**.

## Output

- On a skip, return the skip.
- On a clean comparison, return continue with no finding.
- Otherwise return the comparison, the one `review-findings` pass over it, and the person's continue-vs-revisit-design answer.
- Return alongside them the worker's proposal (including doing nothing / doing something else), what it reuses, and its trade-offs.
- When the worker measured, return the command and raw output it returned with them.
- When that output was too large to return, return the path of each file it wrote instead.
- Where the measurement it needed is none of those, return what could not be measured and what would settle it.
- Treat neither the proposal nor the comparison as a finding, `needs-user`, or Critical auto-reapproval.
- Post none of it to a PR — body, inline, or review.
- Return never empty to mean the current direction is fine.
