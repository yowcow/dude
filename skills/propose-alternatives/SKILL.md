---
name: propose-alternatives
description: Use as a component when another skill needs the most direct route to a named purpose, including doing nothing or doing something else.
---

# Propose Alternatives

This skill edits nothing and posts nothing; comparing the proposal to the current artifact, waiting on a person, and every round decision are the caller's.

## Orchestration model

**Always dispatch one read-only worker in a fresh context; never propose inline.**

- Fan-out is fixed at one.
- The worker is read-only: it edits nothing, commits nothing, creates no worktree, and returns a proposal only.
- The worker goes out at the `high` tier in `using-dude`'s **Worker tier**. `using-dude` would mark a missed alternative `highest` (it never appears downstream); this skill is the exception, citing `yowcow/dude#630`.

## Inputs

The caller hands both:

- **The named purpose** — the problem to solve, not the means.
- **The read-root** — not the current work tree. Which ref that is belongs to the caller.

## Pass

- Unnamed purpose: skip; do not dispatch; return that skip. This is the only skip.
- Otherwise dispatch once. The brief is the purpose only. Do not show the current artifact, the current means, an issue URL or body, or this session's context.
- Confine every search to the caller-supplied read-root.
- Return the worker's proposal as-is. Do not apply the bar. Do not rewrite a proposal into "the current direction is fine".

## Output

Skip, or the most direct route to the purpose (including doing nothing / doing something else), what it reuses, and its trade-offs.

Never an empty return that means the current direction is fine.

## Caller contract

The caller compares the proposal with the current artifact on purpose, means, and cost.

- **Purpose:** whether the named purpose is a real problem; doing nothing or doing something else included.
- **Means:** whether the current work is warranted for that purpose and reaches it.
- **Cost:** whether it includes a quantitative or qualitative regression (testability, coupling, entropy, performance, irreversibility, security, defect tolerance). A loss is a regression.

Only a material regression, or a purpose that is invalid or unmet, is a finding. An alternative that reaches the same result and differs only in preference is not.

This skill does not apply that bar.
