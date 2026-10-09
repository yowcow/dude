---
name: review-code
description: Use to review code.
---

# Review Code

Use on code in any state — a diff just written, a branch, or an uncommitted working tree.

One invocation runs the loop to completion:

- review, judge, fix, verify, review again, until no blocking finding remains.
- What it does not own is re-entry — reviewing again after something else changes the code belongs to the caller; in the Change workflow, `implement-work`'s completion gate owns that.

## Orchestration model

**This skill dispatches no worker of its own: each round's reviewer and verdict workers are `vet-code`'s.**

- The orchestrator owns the loop: it resolves the scope, calls `vet-code` each round, applies the accepted fixes, verifies, and decides when the loop ends.

## Boundaries

- This skill applies fixes but never commits — commits are the caller's.
- Simplification belongs to `simplify-code`; don't fold it in here.
- GitHub-side review — Claude and Copilot on a PR, thread replies, thread resolution — belongs to `pr-to-ready`. Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.

## Scope

Resolve what to review in this order, and declare the resolved scope before dispatching anything:

1. **Caller-supplied** — a SHA range, paths, or a PR. Use it as given; a PR becomes the range its own record bounds, via `<skill-dir>/scripts/resolve-range.sh <pr-number>`.
2. **Uncommitted changes present** — the working tree diff: staged, unstaged, and untracked files.
3. **Clean tree, commits ahead of `<base>`** — run `<skill-dir>/scripts/resolve-range.sh` with no argument.
  - `<base>` is resolved, not assumed: the script reads back the `Base-Branch:` trailer that `implement-work` records when it cuts a branch from a prerequisite's PR, settles the base from what state that PR is now in, and falls back to the default branch where there is no trailer.
  - The trailer's contract, the state-to-base table, and why each test is written the way it is all live in `implement-work`'s `references/base-branch.md`, under **The contract**, **Reading the trailer back**, and **Resolving the default branch**.
4. **Nothing to review** — no uncommitted change, and no range with anything in it. Ask the user what to review. Never widen to the whole repository on a guess.

Either invocation answers in one line:

- `RANGE <base>..<head>` — the two SHAs to review.
- `EMPTY` — the range holds nothing; fall through to 4.
- `STOP <reason>` — the base could not be settled. Report the reason and stop, rather than reviewing a range that may be somebody else's work.

## Pass

One invocation is one pass, and a pass is as many rounds as it takes:

1. Resolve the scope per **Scope** and declare it.
2. Invoke `vet-code` once on the code as it now stands, handing it the scope, what was implemented, the requirements, and from the second round on the earlier rounds' record.
3. Take back the judged findings `vet-code` returns — each `accept` with its fix, `reject` with its reason, or `needs-user` — and re-judge none of them; carry any caveat it returns (paths-only scope, no requirements) into **Report**.
4. Count the `needs-user` verdicts before applying anything.
  - One or more ends the pass's rounds here, on the terms `pr-to-ready`'s 2-3 states: go to step 7 and leave non-clean, per **Escalation**.
  - Otherwise apply the accepted Critical and Important findings yourself — except one that invalidates the approved design, which is not fixed here at all: stop the pass, per **Escalation**.
  - When a finding describes a bug, write the failing regression test first and watch it fail, then fix it (`superpowers:test-driven-development`).
  - Record Minor findings; don't fix them.
5. Verify with the concrete commands the project defines — in the README, Makefile, package scripts, or CI — and read their actual output. When step 4 applied nothing, skip this check run only when invoked from `implement-work`'s completion gate — the covering result is step-2's check run where Simplify changed the tree this round, otherwise this round's step-1 Verify on the unchanged tree.
6. Return to step 2 while a blocking finding remains, subject to **Escalation**. A pass whose step 4 ended on a `needs-user` does not come back here.
7. Report per **Report**.

A round is one review → judge → fix → verify cycle. The pass is clean per `using-dude`'s **Loop convergence** loop-clean when a round's review produces no Critical or Important finding and no verdict came back `needs-user`. Minor findings are recorded, not blocking — except one whose verdict came back `needs-user`, per **Escalation**.

## Escalation

- This loop stops per `using-dude`'s **Loop convergence**.
  - **Pass** says what a round is here, and two findings are the same when a later round faults the same location on the same grounds, however the wording moved — including a claim restated after a fix meant to resolve it.
  - A round that trips either of **Loop convergence**'s two non-clean conditions still applies and verifies its accepted findings before the loop ends; it just doesn't start another review.
- **A `needs-user` verdict stops the pass non-clean**, on the terms `pr-to-ready`'s 2-3 and its stop condition 3 set out: the round that stopped applied nothing, and the caller hands the finding to a person.
- A Critical finding that invalidates the approved design is not fixed in this loop.
  - Per `using-dude`'s **Escalation** it goes back to `plan-work` for re-approval, and this skill is no exception.
  - What this pass hands over is the finding itself, reported separately from the ordinary verdict so the caller routes it rather than reading the pass as merely unfinished.

## Report

- the scope reviewed and how it was resolved, including whether requirements were available
- the number of rounds run
- accepted findings, with location and what changed
- rejected findings, with the reason
- on a `needs-user` stop, the stopped round's verdicts as they stand unapplied — each `accept` with its proposed fix, each `reject` with its reason, and each `needs-user` finding with why the worker put the decision to a person. Earlier rounds report in the applied form above.
- the remaining Minor findings
- what verification ran, and its actual result — or that verification was skipped as unchanged and which prior result covers the tree (step-2's check run or step-1's Verify)
- the verdict: clean, or the blocking findings that remain — flagging separately any Critical finding that invalidates the approved design, per **Escalation**
