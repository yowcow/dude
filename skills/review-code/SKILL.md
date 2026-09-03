---
name: review-code
description: Use to review code and fix what the review finds — on a diff, a branch, or an uncommitted working tree — leaving no blocking finding unresolved. Triggers on "review this code", "review and fix this", "run the review loop until it's clean".
---

# Review Code

Use on code in any state — a diff just written, a branch, or an uncommitted working tree.

One invocation runs the loop to completion: review, judge, fix, verify, review again, until no blocking finding remains. What it does not own is re-entry — reviewing again after something else changes the code belongs to the caller; in the Change workflow, `implement-work`'s completion gate owns that.

`<skill-dir>` below is this skill's own directory inside the installed plugin, `skills/review-code/`.

## Orchestration model

**This skill dispatches two kinds of worker: a read-only reviewer, and one verdict worker per finding.** Nothing else leaves the main loop.

- The orchestrator owns the loop: it resolves the scope, dispatches the reviewer, dispatches a verdict worker for every finding it returns, applies the accepted fixes, verifies, and decides when the loop ends. A reviewer never declares the code clean.
- The reviewer is a read-only worker, dispatched through `superpowers:requesting-code-review`. It gets the scope and the requirements and returns findings only. It never edits code, never runs the project's checks, and never commits.
- The reviewer goes out at the tier `using-dude`'s **Worker tier** sets for a marked worker: a finding it doesn't return leaves this loop *clean* and passes `implement-work`'s completion gate, which is itself this check.
- **Judging a finding never happens in the main loop**, on any round, and goes out at that same marked tier: the main loop wrote this code or fixed it, so a verdict reached there rests on its own account of why the code reads this way, and a real finding rejected on that account is rejected for good — no later round reads it again. One worker per finding, launched together, each applying `superpowers:receiving-code-review` to its one finding and returning `accept` with the fix, `reject` with the technical reason, or `needs-user` — the three verdicts `pr-to-ready`'s 2-3 already takes. Each gets the finding, the scope and requirements the reviewer got, and the earlier rounds' record **Reviewer prompt** already defines; the main loop's own history is what it does not get. The main loop applies the accepted fixes and verifies them against the project's checks, and re-judges no verdict.
- What a read-only worker buys is a fresh context: it reads the code without having written it, so it is not anchored on why the code ended up this way. `simplify-code`'s proposers are dispatched on the same contract, for the same reason.

## Boundaries

- This skill applies fixes but never commits — commits are the caller's.
- Simplification belongs to `simplify-code`; don't fold it in here.
- GitHub-side review — Claude and Copilot on a PR, thread replies, thread resolution — belongs to `pr-to-ready`. Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.

## Scope

Resolve what to review in this order, and declare the resolved scope before dispatching anything:

1. **Caller-supplied** — a SHA range, paths, or a PR. Use it as given; a PR becomes the range its own record bounds, via `<skill-dir>/scripts/resolve-range.sh <pr-number>`.
2. **Uncommitted changes present** — the working tree diff: staged, unstaged, and untracked files.
3. **Clean tree, commits ahead of `<base>`** — run `<skill-dir>/scripts/resolve-range.sh` with no argument. `<base>` is resolved, not assumed: the script reads back the `Base-Branch:` trailer that `implement-work` records when it cuts a branch from a prerequisite's PR, settles the base from what state that PR is now in, and falls back to the default branch where there is no trailer. The trailer's contract, the state-to-base table, and why each test is written the way it is all live in `implement-work`'s `references/base-branch.md`, under **The contract**, **Reading the trailer back**, and **Resolving the default branch**.
4. **Nothing to review** — no uncommitted change, and no range with anything in it. Ask the user what to review. Never widen to the whole repository on a guess.

Either invocation answers in one line:

- `RANGE <base>..<head>` — the two SHAs to review.
- `EMPTY` — the range holds nothing; fall through to 4.
- `STOP <reason>` — the base could not be settled. Report the reason and stop, rather than reviewing a range that may be somebody else's work.

## Reviewer prompt

`superpowers:requesting-code-review` is the dispatch mechanism; what the reviewer is told is this skill's own. Whatever shape that dispatch offers to carry it, the prompt is complete when it holds these four:

1. **The scope** — whatever **Scope** resolved, in one of these four shapes:
   - **a committed range** — the two SHAs bounding it;
   - **uncommitted changes** — where they are: staged, unstaged, and untracked alike. Don't send the reviewer to a worktree of its own here — a worktree holds a revision, and these changes are in none;
   - **paths with no range** — the paths themselves, and that the review covers their current state on this checkout rather than a diff. Say the same in the report: nothing constrains the review to recent change, so the findings may be about code this work never touched;
   - **a PR** — the range **Scope** resolved for it, handed over as a committed range. Reviewing that diff locally is this skill's job; posting anything to the PR is not — that belongs to `pr-to-ready`.
2. **What was implemented** — what the change does, or for a paths-only scope what the code is for.
3. **The requirements** — the plan, or the original request. When there is none, say so in the prompt: the review then runs against the repository's own standards and the code's evident intent. Say it in the report too, so a reader knows plan alignment was not checked.
4. **The earlier rounds** — from the second round on, findings accepted and fixed, and findings rejected with the reason. A reviewer not shown the rejections re-litigates them.

Confine every search to the project root or narrower.

## Pass

One invocation is one pass, and a pass is as many rounds as it takes:

1. Resolve the scope per **Scope** and declare it.
2. Dispatch one reviewer with the code as it now stands. One reviewer per round, fresh each round — the fan-out here is fixed at one, because a diff doesn't warrant more.
3. Dispatch one verdict worker per finding, per **Orchestration model**, and take back what each returns. A worker verifies the claim against the code before accepting it, and rejects — with a stated reason — a finding that is wrong, that only reflects reviewer preference, or that asks for work beyond the request; where the call is a person's rather than a technical one, it returns `needs-user` instead.
4. Count the `needs-user` verdicts before applying anything. One or more ends the pass's rounds here, on the terms `pr-to-ready`'s 2-3 states, with this round's accepted fixes held unapplied along with the rest: go to step 7 and leave non-clean, per **Escalation**. Otherwise apply the accepted Critical and Important findings yourself — except one that invalidates the approved design, which is not fixed here at all: stop the pass, per **Escalation**. When a finding describes a bug, write the failing regression test first and watch it fail, then fix it (`superpowers:test-driven-development`). Record Minor findings; don't fix them.
5. Verify with the concrete commands the project defines — in the README, Makefile, package scripts, or CI — and read their actual output.
6. Return to step 2 while a blocking finding remains, subject to **Escalation**. A pass whose step 4 ended on a `needs-user` does not come back here.
7. Report per **Report**.

A round is one review → judge → fix → verify cycle. The pass is clean when a round's review produces no Critical or Important finding. Minor findings are recorded, not blocking.

## Escalation

- This loop stops per `using-dude`'s **Loop convergence**. **Pass** says what a round is here, and two findings are the same when a later round faults the same location on the same grounds, however the wording moved — including a claim restated after a fix meant to resolve it. A round that trips a stopping condition still applies and verifies its accepted findings before the loop ends; it just doesn't start another review.
- **A `needs-user` verdict stops the pass non-clean**, and stops it on different terms from the two conditions above: it arrives from one round's verdict rather than from a round count, so the round that stopped applied nothing, where a **Loop convergence** stop still applies and verifies that round's accepted findings. The finding stays open, applied by nobody and rejected by nobody, and the caller hands it to a person. This is `using-dude`'s **Loop convergence** non-clean handling reached on a verdict instead of a round count, and `pr-to-ready`'s stop condition 3 is the precedent for a skill stopping itself this way.
- A Critical finding that invalidates the approved design is not fixed in this loop. Per `using-dude`'s **Escalation** it goes back to `plan-work` for re-approval, and this skill is no exception. What this pass hands over is the finding itself, reported separately from the ordinary verdict so the caller routes it rather than reading the pass as merely unfinished.

## Report

- the scope reviewed and how it was resolved, including whether requirements were available
- the number of rounds run
- accepted findings, with location and what changed
- rejected findings, with the reason
- on a `needs-user` stop, the stopped round's verdicts as they stand unapplied — each `accept` with its proposed fix, each `reject` with its reason, and each `needs-user` finding with why the worker put the decision to a person. Earlier rounds report in the applied form above.
- the remaining Minor findings
- what verification ran, and its actual result
- the verdict: clean, or the blocking findings that remain — flagging separately any Critical finding that invalidates the approved design, per **Escalation**
