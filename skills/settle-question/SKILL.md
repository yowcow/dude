---
name: settle-question
description: Use to settle an open question whose deliverable is a judgment, with no runtime symptom to root-cause.
---

# Settle Question

- Settle an open question whose deliverable is a judgment.
- Take `superpowers:systematic-debugging` as the owner of the core loop here.
- Layer on only what a question-shaped run needs: splitting the question into points that can be settled, fixing what was measured, and reporting.
- Run none of its Phase 4 Implementation, since an Investigation ends at findings.

## Orchestration model

- Fan out one worker per point to settle, since the points are independent of each other.
- Keep each verdict with the orchestrator.
- Have a worker that measures, reads, or runs return the command it ran and its raw output.
- For a read that ran no command, have it return the file or record read and how its content was captured.
- Dispatch **the worker that sweeps for absence or exhaustiveness** at the `highest` tier in `using-dude`'s **Worker tier**, since a sweep that stopped early hands back "nothing found" and neither the orchestrator nor any later reader of the report can tell that from an absence.

## Entry

- Take a question, or an issue carrying the points to be settled.
- Treat closing any gap against `using-dude`'s **Understand** as Step 1's job, since it is the first work here rather than a precondition for starting.

## Explore

### Step 1: Split the question into settleable points

- Break the question into points that can each be settled on their own.
- Attach to each point what would settle it: the file, the record, the measurement, or the run whose result decides it.
- Treat a point nothing can settle as not a point.
- Hand such a point back to a person as a question.

### Step 2: Fix the measurement base

- Record what was actually read: the revision, tree, or record.
- Treat an installed tree and the repository it came from as different artifacts, and a branch and its base the same way.
- Name, for every claim of absence, exhaustiveness, or "only", the sweep that produced it, run to completion and read whole, never a truncated or paged view of the output.

## Validate

### Step 3: Settle each point

- Run the core loop per `superpowers:systematic-debugging`: the points from Step 1 are the hypothesis pool, and what Step 1 attached to each point is the evidence that point owes.
- Separate evidence that settles a point from evidence that only suggests one answer.
- Leave an unsettled point recorded as unsettled and never promote it, per `using-dude`'s **Investigation workflow**.

## Synthesize

### Exit criteria

- Every point has a verdict with the decisive evidence behind it; or
- the point is recorded as unsettled, with what would settle it and who decides.

- Run `review-findings` on the report per its **Caller contract**.
- Publish per `using-dude`'s **Stage boundaries**.

### Report format

1. **Verdict** — the answer to the question, in one paragraph.
2. **Measurement base** — the revision, tree, or record measured, and the sweep behind each claim of absence.
3. **Settled points** — per point, the verdict and the evidence that decided it.
4. **Alternatives rejected** — each one considered, with why it is wrong.
5. **Next items** — concrete next actions in order, each naming its owner (who decides) and its action type: file, decide, or measure. Not work to start here.
6. **Not measured** — the claims left unaudited, and what would settle each.

- Carry **Verdict** and **Next items** forward through `using-dude`'s **Investigation → Change transition**, since they are the next flow's input and never work this one starts.
- Carry no reproduction forward from a question-shaped run.

## Escalation

- Take `using-dude`'s **Loop convergence** as this run's stopping conditions.
- Count one round as one core-loop pass over a point.
- Count a finding as repeating when a later pass faults the same point for the same reason.
- Never settle a finding that invalidates the question as asked in place: hand it back to the person who asked, per **Synthesize**'s second exit criterion.
