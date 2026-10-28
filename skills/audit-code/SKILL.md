---
name: audit-code
description: Use to scan a repository or path and report what to fix, without changing code.
---

# Audit Code

- Scan a repository or path and report what to fix.
- Never edit code here, since an Investigation ends at findings.
- Run what this skill reports through `review-findings` before publication.

## Orchestration model

- Fan out one worker per axis, since the axes are independent of each other.
- Keep each finding with the orchestrator.
- Hand each worker its axis as the pair written for it — the invariant attacked and how it is expected to break.
- Never hand a field's name alone.
  - Handed a field, a worker returns what a text search can count, and the orchestrator writes an invariant beside it afterwards for something never swept.
- Return from a worker that sweeps or runs a probe the command it ran and that command's raw output beside its finding.
- Mark any worker that sweeps for absence or exhaustiveness, or that probes a behaviour axis.
- Dispatch a marked worker at the `highest` tier in `using-dude`'s **Worker tier**, since a sweep that stopped early hands back "nothing found" and a probe that never ran hands back a `no finding` line — neither the orchestrator nor any later reader of the report can tell that from a result.

## Entry

- Take a repository, or a path within one.
- Begin `using-dude`'s **Understand** at Step 1's inventory, since the inventory is the first work here and not a precondition for starting.

## Explore

### Step 1: Inventory the invariants

- Collect what the artifact is expected to do before selecting axes.
- Collect it from three layers:
  - **Declared** — what the artifact says of itself, or what the issue that asked for it asked for: contract comments, README sentences, test names, schemas.
  - **Observed by callers** — what a caller already relies on: output it parses or branches on, a return value it uses as-is, a file or state it expects to exist afterwards.
  - **Conventional for the genre** — what that kind of artifact is ordinarily expected to do.

- Keep the inventory as your own list separate from the axes, since the axes are drawn from it.
- Write into the report's **Invariants attacked** only the pairs actually handed out.

### Step 2: Select axes

- Select 3–5 axes by whether they attack a high-value invariant from Step 1, never by spreading across fields.
- Sweep what the caller named when the caller named any, else the selection.
- Write every axis, a caller-named one included, as the pair it is — the invariant it attacks, and how it is expected to break.
- Treat the invariant as a promise the artifact makes about its output, state, or time, never as a rule the codebase invents for itself.
- Treat a convention the genre expects as a promise the artifact is held to.
- Record axes considered but not swept under Not measured.
- Treat an axis nothing can measure as not an axis.
- Hand such an axis back to a person as a question.

### Step 3: Fix the measurement base

- Record what was actually read: the revision, tree, or path.
- Record the source of Step 1's inventory too.
- Treat an installed tree and the repository it came from as different artifacts.
- Treat a branch and its base as different artifacts too, since a promise from a tree the record does not name is not this artifact's.
- Name the sweep behind every claim of absence, exhaustiveness, or "only".
- Run that sweep to completion and read its output whole, never a truncated or paged view of the output.

### Step 4: Sweep each axis

- Sweep each selected axis against the tree from Step 3.
- Separate evidence that establishes a finding from evidence that only suggests one.
- Assume every contract external to the scanned tree is honored.
- Keep only the findings that hold under that assumption.
- Treat a suspected contract violation as not a finding — a field that may be named differently, a response shape that may change.
- Record such a violation as one line under Not measured.
- Treat a convention about the artifact's own behaviour as no such contract, since nothing outside the tree can change whether the tree keeps it.
- Treat breaking such a convention as a finding.
- Treat what breaks while the contract holds as a finding: a non-zero exit swallowed as success, a write left half done at failure, state created and never removed, a wait that outlasts a stated deadline.
- Treat what a boundary can judge without a spec as a finding too: how failure is handled, whether the artifact validates input against the shape it itself expects, whether one assumption contradicts itself in two places, whether a retry is idempotent.
- Give an axis whose invariant is behaviour — output, state, or time — one probe of the expected break actually run.
- Change neither the artifact nor external state when running, since running is not editing.
- Run through an unmodified throwaway copy or a read-only route.
- Run the probe under a bound — the deadline the axis's promise states, or a bound the probe names when the promise states none.
- Name the bound among the observations.
- Treat a probe stopped at a bound its promise set as observing a wait outlasting that promise.
- Record what the artifact does under Not measured with the reason, when the artifact cannot be run or only mutation could settle the invariant.
- Never probe invariants that only reading can settle — documentation, or the presence of a declared field, since one search would count as a probe and leave only the impression of having checked.
- Treat as evidence what was observed — the output, the ending exit state, the state left behind, the time taken.
- Quote the line for a claim a boundary can judge without a spec.
- Treat a path from trigger to wrong result as the shape of the claim, never as evidence for it.
- Leave one line under its axis's findings even for a probe that found nothing: `no finding`, with what it observed — the trigger it exercised and the result.
- Treat a behaviour axis with no trace of a run, or with a run that never exercised the trigger of the expected break, as not swept as to what the artifact does.
- Record what the artifact does under Not measured with the reason for the missing run.
- Treat a wait that outlasts a deadline the axis's promise states as the break itself and keep it as a finding.
- Record a probe stopped at a bound it named with the wait still running as settling nothing past that bound.
- Record that probe under Not measured with the bound named, never as `no finding`.
- Keep what a boundary can judge without a spec as a finding on the line quoted.
- Report a finding that attacks another axis's invariant under that axis.
- Report a finding that attacks an invariant no axis attacked under that invariant in place of an axis.
- Record in Not measured that no axis attacked it there.

## Synthesize

### Exit criteria

- Give every axis its verdict and the decisive evidence behind it, with the verdict of an axis whose probe found nothing being that it was swept, or record the axis as not measured, with what would measure it and who decides.

- Run `review-findings` on the report per its **Caller contract**.
- Confirm the report destination with a person afterwards.
- Take chat as the default, or the tracking issue's comment when one tracks the work.
- Use a bare `#N` only when the posting repository is the scanned one, else qualify as `owner/repo#N`.
- Post only on yes, per `using-dude`'s **Stage boundaries**.

### Report format

  1. **Verdict** — what to fix, in priority order, in one paragraph; a candidate that would be a finding only if an external contract is not honored is named here as conditional.
  2. **Measurement base** — the revision, tree, or path measured, and the sweep behind each claim of absence.
  3. **Invariants attacked** — per axis, the pair handed to the worker. An invariant no axis attacked and no finding names belongs to Not measured instead.
  4. **Findings** — per axis or invariant, the verdict and the observation that decided it, plus, for each finding, the `path:line` where it breaks.
  5. **Next items** — concrete next actions in order. Not work to start here.
  6. **Not measured** — a first line `Assumed: <what was treated as holding as a contract external to the scanned tree>`, or `Assumed: none — no candidate rested on an external contract`; then the invariants, axes, and claims left unaudited, and what would settle each.

- Shape **Verdict** and **Next items** for `plan-work`'s question-shaped **Entry**.
- Never start work here.
- Carry forward no reproduction from a scan.

## Escalation

- Take this run's stopping conditions from `using-dude`'s **Loop convergence**.
- Count one round as one sweep pass over an axis.
- Count a finding as repeating when a later pass faults the same axis for the same reason.
- Never settle in place a finding that invalidates the scan as asked.
- Hand such a finding back to the person who asked, per **Synthesize**'s second exit criterion.
