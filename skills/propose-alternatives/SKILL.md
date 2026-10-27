---
name: propose-alternatives
description: Use as a component when another skill needs the most direct route to a named purpose, including doing nothing or doing something else.
---

# Propose Alternatives

This skill edits nothing and posts nothing.

## Orchestration model

**No named purpose, no worker. Otherwise always dispatch one read-only worker in a fresh context; never propose inline.**

- The worker is read-only: it edits nothing, commits nothing, creates no worktree, and returns a proposal, plus the command and raw output of any measurement it took — or the path of each file it wrote when that output was too large to return.
- The worker goes out at the `highest` tier in `using-dude`'s **Worker tier**: a missed alternative never appears downstream.

## Inputs

The caller hands:

- **The named purpose** — the problem to solve, not the means.
- **The read-root** — not the current work tree. Which ref that is belongs to the caller.
- **The current artifact** — the work as currently framed. The worker never sees it.
- **The caller's budget for the one measurement** — when the caller has one. Without it a default this dispatch names applies.

## Pass

- Unnamed purpose: skip; do not dispatch; return that skip. This is the only skip.
- Otherwise dispatch once. Besides the purpose, the worker is handed only the read-root (it reads that ref, not the session work tree, and creates no worktree; a measurement needing an executable copy of that ref is outside what the worker may take, so it measures only what read-only plumbing against that ref can answer), the time limit for the one measurement it may take — the caller's budget when it has one, otherwise a default this dispatch names — the write directory for output too large to return, a directory outside the work tree that this dispatch names, and the proposal shape: the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs. Do not show the current artifact, the current means, an issue URL or body, or this session's context.
- The worker measures at most once, within that time limit, taken against that ref, returning the command and its raw output rather than a summary — or the path of each file it wrote when the output is too large to return.
- Return the worker's proposal as-is. Do not rewrite a proposal into "the current direction is fine".

## Compare

This skill compares the proposal with the current artifact on purpose, means, and cost — never the worker, never the caller.

- **Purpose:** whether the named purpose is a real problem; doing nothing or doing something else included.
- **Means:** whether the current work is warranted for that purpose and reaches it.
- **Cost:** whether it includes a quantitative or qualitative regression.

Only a material regression, or a purpose that is invalid or unmet, is a finding. An alternative that reaches the same result and differs only in preference is not.

- No finding: return continue with no finding; the caller continues its work.
- Finding: run `review-findings` for exactly one pass on that comparison, and follow it nowhere further. Then chat the finding with its trade-offs and a recommendation, and wait for the person's **continue** vs **revisit design** per `using-dude`'s **Escalation**. Return that answer to the caller. A revisit returns the finding to the caller; where the revisit lands is the caller's under `using-dude`'s **Escalation**.

## Output

Skip; or continue with no finding; or the comparison, the one `review-findings` pass over it, and the person's continue-vs-revisit-design answer — alongside the worker's proposal (including doing nothing / doing something else), what it reuses, and its trade-offs — plus, when the worker measured, the command and raw output it returned, or the path of each file it wrote when that output was too large to return; and, where the measurement it needed is not one of those, what could not be measured and what would settle it.

Never an empty return that means the current direction is fine.

## Caller reference

Invoke with the named purpose, the read-root, and the current artifact; continue except on revisit design, which the caller handles under `using-dude`'s **Escalation**.
