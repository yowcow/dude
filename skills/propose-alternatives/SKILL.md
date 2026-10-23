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
- **The measurement record's path** — when the caller has one whose recorded identity matches the read-root, per `using-dude`'s **Measurement records**. A record sitting outside the read-root is still readable because the path names it.
- **The caller's budget for the one measurement** — when the caller has one. Without it a default this dispatch names applies.

## Pass

- Unnamed purpose: skip; do not dispatch; return that skip. This is the only skip.
- Otherwise dispatch once. Besides the purpose, the worker is handed only the read-root (it reads that ref, not the session work tree, and creates no worktree), the measurement record's path when the caller has one, the time limit for the one measurement it may take — the caller's budget when it has one, otherwise a default this dispatch names — the write directory for output too large to return, which is the directory holding the measurement record when a path was handed and otherwise a directory outside the work tree that this dispatch names, and the proposal shape: the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs. Do not show the current artifact, the current means, an issue URL or body, or this session's context.
- The worker reads the measurement record it was handed before measuring anything, and measures only what that record does not cover: one measurement at most, within that time limit, taken against that ref, returning the command and its raw output rather than a summary — or the path of each file it wrote when the output is too large to return.
- Return the worker's proposal as-is. Do not rewrite a proposal into "the current direction is fine".

## Output

Skip, or the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs — plus, when the worker measured, the command and raw output it returned, or the path of each file it wrote when that output was too large to return.

Never an empty return that means the current direction is fine.

## Caller contract

The caller compares the proposal with the current artifact on purpose, means, and cost.

- **Purpose:** whether the named purpose is a real problem; doing nothing or doing something else included.
- **Means:** whether the current work is warranted for that purpose and reaches it.
- **Cost:** whether it includes a quantitative or qualitative regression.

Only a material regression, or a purpose that is invalid or unmet, is a finding. An alternative that reaches the same result and differs only in preference is not.

This skill does not apply that bar.
