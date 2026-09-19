---
name: audit-code
description: Use to scan a repository or path and report what to fix, without changing code.
---

# Audit Code

Scan a repository or path and report what to fix. This skill finds; it never edits code. What it reports goes through `review-findings` before publication.

## Orchestration model

- The axes are independent of each other, so fan out one worker per axis. Each finding stays with the orchestrator.
- **The worker that sweeps for absence or exhaustiveness is marked**: dispatch it at the tier `using-dude`'s **Worker tier** sets for a marked worker. A sweep that stopped early hands back "nothing found", and neither the orchestrator nor any later reader of the report can tell that from an absence.

## Entry

A repository, or a path within one. Closing any gap against `using-dude`'s **Understand** is Step 1's job — the first work here, not a precondition for starting.

## Explore

### Step 1: Select axes

- Select 3–5 axes from the repository's shape, spread across defects, contradictions, security, and whatever else the tree suggests rather than skewing toward one field; sweep what the caller named, if any, otherwise the selection. Record axes considered but not swept under Not measured.
- An axis nothing can measure is not an axis. It is a question to hand back to a person.

### Step 2: Fix the measurement base

- Record what was actually read: the revision, tree, or path. An installed tree and the repository it came from are different artifacts, and so are a branch and its base.
- Every claim of absence, exhaustiveness, or "only" names the sweep that produced it — run to completion and read whole, never a truncated or paged view of the output.

### Step 3: Sweep each axis

- Sweep each selected axis against the tree from Step 2. Separate evidence that establishes a finding from evidence that only suggests one.

## Synthesize

### Exit criteria

- Every axis has its findings with the decisive evidence behind each; or
- the axis is recorded as not measured, with what would measure it and who decides.

Once the report below is drafted, run `review-findings` on it for one pass, restate flagged claims as unsettled / not measured, then confirm the report destination with a person: default is the scanned repository, another repository on request, chat-only also allowed. A bare `#N` points at the scanned repository; anything else is qualified as `owner/repo#N`. Post only on yes, per `using-dude`'s **Stage boundaries**.

### Report format

  1. **Verdict** — what to fix, in priority order, in one paragraph.
  2. **Measurement base** — the revision, tree, or path measured, and the sweep behind each claim of absence.
  3. **Findings** — per axis, the verdict and the evidence that decided it, each finding backed by a `path:line`.
  4. **Next items** — concrete next actions in order. Not work to start here.
  5. **Not measured** — the axes and claims left unaudited, and what would settle each.

**Verdict** and **Next items** are what `plan-work` receives — that flow's input, never work this one starts. A scan has no reproduction to carry forward.

## Escalation

This run's stopping conditions are `using-dude`'s **Loop convergence**. One round is one sweep pass over an axis, and a finding repeats when a later pass faults the same axis for the same reason. A finding that invalidates the scan as asked is never settled in place: hand it back to the person who asked, per **Synthesize**'s second exit criterion.
