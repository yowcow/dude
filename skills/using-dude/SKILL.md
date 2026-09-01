---
name: using-dude
description: Use when starting any task - establishes how a task is classified, which flow it enters, what each flow hands over, when a phase is clean, and where a loop stops.
---

# Using dude

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>

The skills cite sections of this document as "the guidelines' **X**".

- Local skills complement Superpowers; don't reimplement a Superpowers workflow that already exists.
- This document owns the orchestration invariants: the orchestrator owns control flow and declares which execution method it chose; a skill that declares no orchestration model runs inline in the main loop rather than dispatching workers on your behalf, and one that declares dispatch has its workers dispatched — invoking it is itself the request for them, overriding any default that discourages dispatch.

## Workflow

The orchestrator decides when each phase is complete and drives every transition; a worker never gets an objective spanning multiple phases, and never declares a phase complete or advances the workflow itself.

The same holds for a skill you invoke: when a sub-skill's own procedure ends by moving on to the next skill, don't follow it — what runs next is the caller's decision, not the sub-skill's; restate this at each call site too. What this cuts is the transition only — a sub-skill's self-review of its own output, its user-confirmation step, and its housekeeping before that transition all still run.

### Workflow selection

Classify the task first:

| Deliverable | Classification | Entry |
| --- | --- | --- |
| a diff — features, refactors, and fixes whose cause is known | **Change** | `plan-work` → `implement-work` → `pr-to-ready` |
| findings, not a diff — diagnosing an observed problem such as a performance shortfall, a failure or incident, an unexplained metric or cost change, or a bug whose cause is unknown | **Investigation** | core loop → domain skill → transition |
| what one skill produces — a review's findings, a simplified diff, a plan, a PR taken to ready | **A named deliverable** | that skill, run directly with no flow wrapped around it |

A named deliverable settles the classification, even where running the skill produces a diff.

Change and Investigation both begin with **Understand**; a bug whose cause is unknown is an investigation first, and its fix enters the Change workflow only through the transition below. General research (library comparisons, "how does X work") is none of these — answer it directly, with `superpowers:brainstorming` when it is design-shaped.

Match a named deliverable against the skills' `description`s, and where two could fit, let the deliverable named decide rather than the topic. Where the run turns up work beyond that deliverable, report it and let the user pick the flow instead of widening the run.

For a Change, enter at the flow the work has actually reached: no agreed design or PR-sized split yet → `plan-work`; one PR-sized task in hand → `implement-work`; verified commits on a branch → `pr-to-ready`.

A Change that carries no design decision has a lane of its own, not an exemption from the flows: the test is that the change is determined once stated, with no interface, structure, or trade-off left open — declare that in one line and carry it into the run's report so the skipped gate stays checkable. This lane skips `plan-work` and `implement-work`'s plan gate, entering `implement-work` with **manual** execution, while the completion gate and `pr-to-ready` still run in full — integration goes through a PR at any size. The moment a design decision surfaces, the lane is over: take **Escalation**.

### Understand

- Identify existing failures and constraints.
- For investigations, also pin down the symptom precisely — what is observed, where, since when, at what scope — and what a sufficient explanation would look like.

### Change workflow

Three flows, each of which can be entered on its own, and each with its own deliverable and hand-off.

- **`plan-work`** — deliverable: the agreed design plus a numbered TODO list at PR granularity, published once — as a comment on the tracking issue, plus one sub-issue per item; or in chat, with no sub-issues, when no issue tracks the work.
- **`implement-work`** — deliverable: a pushed branch of verified commits.
- **`pr-to-ready`** — deliverable: a PR whose CI passes and whose review is clean, left at ready or draft.

A phase is *clean* when its checks pass: verification (the relevant test, lint, build, typecheck, smoke test, or manual check passes, and the deliverable meets the requirements the task itself states), simplification with `simplify-code` (no behavior-preserving cleanup is left), and review with `review-code` (no blocking findings remain). A flow that produces no code sets its own bar instead, and each skill defines its own.

Where a tracking issue backs the work, `plan-work` splits it into one sub-issue per item whatever the count, so `implement-work` → `pr-to-ready` is a **loop, not a single pass** that runs once per sub-issue in the TODO list's order. Each turn takes one sub-issue through `implement-work`'s own entry and gates — a later PR is never a continuation of the previous turn, and never inherits its verification.

**Merging is a person's responsibility, and so is everything that depends on it** — `pr-to-ready` ends at ready or draft, and the merge itself, the parent issue's closure, and cleaning up the branch and worktree all belong to a human afterward, so a remaining sub-issue starts a separate session.

### Investigation workflow

The deliverable is an evidence-backed explanation of an observed problem. `superpowers:systematic-debugging` is the core loop; local skills layer domain specifics on top — `investigate-performance` for performance shortfalls, `investigate-anomaly` for failures, incidents, and unexplained metric or cost changes; for a plain unknown-cause bug, the core loop alone usually suffices. Keep evidence and hypotheses strictly separated: never promote a hypothesis to a conclusion without a confirming measurement or reproduction.

#### Investigation → Change transition

- An investigation never starts editing. When a fix is wanted, enter `plan-work` with the findings as input.
- Carry the reproduction forward: it becomes the regression test for the fix.

### Worker tier

**Tier** is whatever the runtime has for putting more capability on one task — a stronger model, a higher reasoning effort, or both.

The orchestrator can re-judge what a worker returned, but never what it didn't return: a worker whose miss passes as "nothing found" is dispatched at the highest tier the run has. The run's default is fine for every other worker, and this rule constrains nothing about them. Which workers get the floor is each skill's own to mark, in its **Orchestration model**.

Where the runtime has no means of choosing a tier, this rule settles nothing and the run proceeds unchanged.

### Stage boundaries

- At each phase transition and gate iteration, write a concise hand-off summary, dropping exploratory dumps and stale tool output while keeping the substance.
- You own this summary even when your runtime can't compact context on its own — when context is heavy and only the user can trigger compaction, prompt them to. Never let a summary or compaction relax a gate.
- A hand-off between flows may land in a different session. The canonical record is the tracking issue's comment — chat only when no issue tracks the work. At each flow's end, name the artifact the next flow picks up. The detailed per-PR plan is not such an artifact: it is scratch inside `implement-work`, rewritten from the task rather than carried across.
- **A loop's intermediate state is orchestrator-facing.** Report each round to the caller in chat, and never to GitHub. Only the converged result reaches the canonical record above.

### Loop convergence

Every loop that checks work and fixes what came back stops on the same conditions. The rule binds a skill's own check-fix loop and the loop that re-invokes it alike:

- **Clean** — a round comes back with nothing blocking: no blocking finding, or a failing check that now passes. This is the normal exit.
- **The same finding survives three rounds** of fixes without resolving.
- **Five rounds in total.**
- **Either non-clean condition above stops the loop and hands the user the decision**, with the findings still open and where the disagreement stands. Never report clean on the strength of fixes nothing has re-checked.

**Each loop defines two things for itself**: what one of its rounds is, and what makes two findings the same one. Nothing else about stopping is a skill's to set. A skill may add a **stricter** condition on top of *clean* where its own inputs warrant it; it may not loosen one.

**A bounded inner pass does not bound the loop around it** — these conditions are counted per loop, and "the skill I call is bounded" is never evidence that this loop terminates. A wait bounded by clock time — polling for an answer that has not arrived yet — is a timeout owned by the skill that waits, not one of these loops.

### Escalation

- When uncertainty is high, requirements conflict, multiple viable designs exist, or new facts invalidate the current plan, stop and go back to where the framing is owned — `plan-work` for a Change (from `implement-work` or `pr-to-ready` alike), the Investigation workflow's framing for an Investigation, or Workflow selection if the task's type changed.
- **A Critical finding that invalidates the agreed design is never fixed in place, and never worked around.** It goes back to `plan-work` for re-approval wherever it surfaces. Such a finding can surface on any round, so check for it before either of **Loop convergence**'s two non-clean stopping conditions.
- Report what's uncertain, the options and trade-offs, and your recommendation. What a flow hands over on this exit belongs to that skill's own **Escalation** section; the contract for receiving it is `plan-work`'s **Entry**.
