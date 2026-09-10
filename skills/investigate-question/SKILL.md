---
name: investigate-question
description: Use when the deliverable is a judgment on an open question rather than a fix — settling which of several designs holds, whether a rule or capability already exists, what a past decision actually ruled, or whether a claim about the system is true, with no runtime symptom to root-cause. Produces a findings report, not a change. Triggers on "settle this question", "which of these is right", "does this already exist", "what did we decide", "is this claim true", "check this before I open the issue".
---

# Investigate Question

Settle an open question whose deliverable is a judgment. `superpowers:systematic-debugging` owns the core loop and runs unchanged here; this skill layers on only what a question-shaped run needs — splitting the question into points that can be settled, fixing what was measured, and reporting. Its Phase 4 Implementation does not run: an Investigation ends at findings.

## Orchestration model

- The points to settle are independent of each other, so fan out one worker per point. Each verdict stays with the orchestrator.
- **The worker that sweeps for absence or exhaustiveness is marked**: dispatch it at the tier `using-dude`'s **Worker tier** sets for a marked worker. A sweep that stopped early hands back "nothing found", and neither the orchestrator nor any later reader of the report can tell that from an absence.

## Entry

A question, or an issue carrying the points to be settled. Closing any gap against `using-dude`'s **Understand** is Step 1's job — the first work here, not a precondition for starting.

## Explore

### Step 1: Split the question into settleable points

- Break the question into points that can each be settled on their own, and attach to each one what would settle it: the file, the record, the measurement, or the run whose result decides it.
- A point nothing can settle is not a point. It is a question to hand back to a person.

### Step 2: Fix the measurement base

- Record what was actually read: the revision, tree, or record. An installed tree and the repository it came from are different artifacts, and so are a branch and its base.
- Every claim of absence, exhaustiveness, or "only" names the sweep that produced it — run to completion and read whole, never a truncated or paged view of the output.

## Validate

### Step 3: Settle each point

- Run the core loop per `superpowers:systematic-debugging`: the points from Step 1 are the hypothesis pool, and what Step 1 attached to each point is the evidence that point owes.
- Separate evidence that settles a point from evidence that only suggests one answer. An unsettled point stays recorded as unsettled and is never promoted, per `using-dude`'s **Investigation workflow**.

## Synthesize

### Exit criteria

- Every point has a verdict with the decisive evidence behind it; or
- the point is recorded as unsettled, with what would settle it and who decides.

Once the report below is drafted, run `review-findings` on it. Restate flagged claims as unsettled / not measured, then publish. Nothing reaches the canonical record before that pass has finished.

### Report format

1. **Verdict** — the answer to the question, in one paragraph.
2. **Measurement base** — the revision, tree, or record measured, and the sweep behind each claim of absence.
3. **Settled points** — per point, the verdict and the evidence that decided it.
4. **Alternatives rejected** — each one considered, with why it is wrong.
5. **Next items** — what to file. Not work to start here.
6. **Not measured** — the claims left unaudited, and what would settle each.

**Verdict** and **Next items** are what `plan-work` receives — that flow's input, never work this one starts. A question-shaped run has no reproduction to carry forward.
