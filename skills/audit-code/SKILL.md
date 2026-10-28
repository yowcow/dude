---
name: audit-code
description: Use to scan a repository or path and report what to fix, without changing code.
---

# Audit Code

Scan a repository or path and report what to fix. This skill finds; it never edits code — an Investigation ends at findings. What it reports goes through `review-findings` before publication.

## Orchestration model

- The axes are independent of each other, so fan out one worker per axis. Each finding stays with the orchestrator.
- Hand each worker its axis as the pair written for it — the invariant attacked and how it is expected to break — never as a field's name alone. Handed a field, a worker returns what a text search can count, and the orchestrator writes an invariant beside it afterwards for something never swept.
- A worker that sweeps or runs a probe returns the command it ran and that command's raw output beside its finding.
- **Any worker that sweeps for absence or exhaustiveness, or probes a behaviour axis, is marked**: dispatch it at the `highest` tier in `using-dude`'s **Worker tier**. A sweep that stopped early hands back "nothing found", and a probe that never ran hands back a `no finding` line — neither the orchestrator nor any later reader of the report can tell that from a result.

## Entry

A repository, or a path within one. `using-dude`'s **Understand** begins at Step 1's inventory — the first work here, not a precondition for starting.

## Explore

### Step 1: Inventory the invariants

Before selecting axes, collect what the artifact is expected to do, from three layers:

- **Declared** — what the artifact says of itself, or what the issue that asked for it asked for: contract comments, README sentences, test names, schemas.
- **Observed by callers** — what a caller already relies on: output it parses or branches on, a return value it uses as-is, a file or state it expects to exist afterwards.
- **Conventional for the genre** — what that kind of artifact is ordinarily expected to do.

Keep it as your own list, separate from the axes: the axes are drawn from it, and only the pairs actually handed out are written into the report's **Invariants attacked**.

### Step 2: Select axes

- Select 3–5 axes by whether they attack a high-value invariant from Step 1, not by spreading across fields; sweep what the caller named, if any; otherwise sweep the selection. Write every axis (a caller-named one included) as the pair it is — the invariant it attacks, and how it is expected to break. The invariant is a promise the artifact makes about its output, state, or time, not a rule the codebase invents for itself; a convention the genre expects is a promise the artifact is held to. Record axes considered but not swept under Not measured.
- An axis nothing can measure is not an axis. It is a question to hand back to a person.

### Step 3: Fix the measurement base

- Record what was actually read: the revision, tree, or path, including the source of Step 1's inventory. An installed tree and the repository it came from are different artifacts, and so are a branch and its base; a promise from a tree the record does not name is not this artifact's.
- Every claim of absence, exhaustiveness, or "only" names the sweep that produced it — run to completion and read whole, never a truncated or paged view of the output.

### Step 4: Sweep each axis

- Sweep each selected axis against the tree from Step 3. Separate evidence that establishes a finding from evidence that only suggests one.
- Assume every contract external to the scanned tree is honored, and keep only the findings that hold under that assumption. A suspected contract violation — a field that may be named differently, a response shape that may change — is not a finding: it goes to Not measured as one line. A convention about the artifact's own behaviour is no such contract — nothing outside the tree can change whether the tree keeps it, so breaking it is a finding. What breaks while the contract holds is a finding: a non-zero exit swallowed as success, a write left half done at failure, state created and never removed, a wait that outlasts a stated deadline. So is what a boundary can judge without a spec: how failure is handled, whether the artifact validates input against the shape it itself expects, whether one assumption contradicts itself in two places, whether a retry is idempotent.
- An axis whose invariant is behaviour — output, state, or time — gets one probe of the expected break actually run. Running is not editing: the probe changes neither the artifact nor external state, through an unmodified throwaway copy or a read-only route. The probe runs under a bound — the deadline the axis's promise states, or a bound the probe names when the promise states none — and the bound is named among the observations; a probe stopped at a bound its promise set has observed a wait outlasting that promise. When the artifact cannot be run, or only mutation could settle the invariant, what the artifact does goes to Not measured with the reason. Invariants that only reading can settle — documentation, or the presence of a declared field — are not probed: one search would count as a probe and leave only the impression of having checked.
- The evidence is what was observed — the output, the ending exit state, the state left behind, the time taken — and, for a claim a boundary can judge without a spec, the line quoted. A path from trigger to wrong result is the shape of the claim, not evidence for it.
- A probe that found nothing still leaves one line under its axis's findings, `no finding`, with what it observed — the trigger it exercised and the result. A behaviour axis with no trace of a run, or with a run that never exercised the trigger of the expected break, is not swept as to what the artifact does: what the artifact does goes to Not measured with the reason, and a wait that outlasts a deadline the axis's promise states is the break itself and stays a finding. A probe stopped at a bound it named, with the wait still running, settles nothing past that bound: that goes to Not measured with the bound named, not to `no finding`. What a boundary can judge without a spec still stands as a finding on the line quoted.
- A finding that attacks an invariant no axis attacked is reported under that invariant in place of an axis, and Not measured records that no axis attacked it.

## Synthesize

### Exit criteria

- Every axis has its verdict and the decisive evidence behind it — the verdict of an axis whose probe found nothing being that it was swept; or
- the axis is recorded as not measured, with what would measure it and who decides.

Run `review-findings` on the report per its **Caller contract**, then confirm the report destination with a person: default is chat, or the tracking issue's comment when one tracks the work. A bare `#N` only when the posting repository is the scanned one; otherwise qualify as `owner/repo#N`. Post only on yes, per `using-dude`'s **Stage boundaries**.

### Report format

  1. **Verdict** — what to fix, in priority order, in one paragraph; a candidate that would be a finding only if an external contract is not honored is named here as conditional.
  2. **Measurement base** — the revision, tree, or path measured, and the sweep behind each claim of absence.
  3. **Invariants attacked** — per axis, the pair handed to the worker. An invariant no axis attacked and no finding names belongs to Not measured instead.
  4. **Findings** — per axis or invariant, the verdict and the observation that decided it, plus, for each finding, the `path:line` where it breaks.
  5. **Next items** — concrete next actions in order. Not work to start here.
  6. **Not measured** — a first line `Assumed: <what was treated as holding as a contract external to the scanned tree>`, or `Assumed: none — no candidate rested on an external contract`; then the invariants, axes, and claims left unaudited, and what would settle each.

**Verdict** and **Next items** arrive shaped for `plan-work`'s question-shaped **Entry** — never work this one starts. A scan has no reproduction to carry forward.

## Escalation

This run's stopping conditions are `using-dude`'s **Loop convergence**. One round is one sweep pass over an axis, and a finding repeats when a later pass faults the same axis for the same reason. A finding that invalidates the scan as asked is never settled in place: hand it back to the person who asked, per **Synthesize**'s second exit criterion.
