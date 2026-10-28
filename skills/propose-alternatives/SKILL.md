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

- **The named purpose** — the problem to solve, not the means.
- **The read-root** — not the current work tree. Which ref that is belongs to the caller.
- **The current artifact** — the work as currently framed. The worker never sees it.
- **The caller's budget for the one measurement** — when the caller has one.
- Without it, the default this dispatch names applies.

## Pass

- Skip an unnamed purpose: dispatch nothing and return that skip.
- Allow no other skip.
- Otherwise dispatch once.
- Hand the worker the read-root besides the purpose.
- Let it read that ref, not the session work tree.
- Create no worktree for the worker.
- Take only what read-only plumbing against that ref can answer as its measurement, since a measurement needing an executable copy of that ref is outside what the worker may take.
- Limit its one measurement to the caller's budget when the caller has one.
- Otherwise limit it to the default this dispatch names.
- Name a directory outside the work tree for output too large to return.
- Ask for the proposal shape: the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs.
- Show it nothing else: neither the current artifact, the current means, an issue URL or body, nor this session's context.
- Let the worker measure at most once.
- Bound that measurement by that time limit, taken against that ref.
- Take back the command and its raw output rather than a summary.
- Take back the path of each file it wrote when the output is too large to return.
- Return the worker's proposal as-is.
- Rewrite never a proposal into "the current direction is fine".

## Compare

- Compare the proposal with the current artifact on purpose, means, and cost.
- Judge neither the worker nor the caller there.
- **Purpose:** whether the named purpose is a real problem; doing nothing or doing something else included.
- **Means:** whether the current work is warranted for that purpose and reaches it.
- **Cost:** whether it includes a quantitative or qualitative regression.
- Treat only a material regression, or a purpose that is invalid or unmet, as a finding.
- Treat never an alternative reaching the same result and differing only in preference as one.
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
