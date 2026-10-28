---
name: review-findings
description: Use to review report claims.
---

# Review Findings

Use on a report whose deliverable is findings, once drafted and before publication. This reviews what the report claims and what backs it, never the work that produced it and never the fix it might lead to.

## Orchestration model

**Always dispatch lens reviewers in a fresh context; never review inline.** The main loop gathers inputs, sizes the fan-out, takes the union, and reports. It re-judges none and dispatches no verdict worker.

Each reviewer goes out at the `highest` tier in `using-dude`'s **Worker tier**: a miss returns as "nothing found".

One invocation is one pass. It never re-reviews on its own, never edits the report, and never declares a claim settled. The caller restates flagged claims and publishes.

## Target

One invocation reviews exactly one target, and **the caller declares it**: the findings or judgment report about to become the canonical record, with the question it answers and the sources it rests on.

A findings report and a ruling published as an issue comment differ in format only: evidence not carrying the claim, a cut-short sweep, a hypothesis stated as concluded. One target, not two.

## What counts as a finding

One test with two sides. Side A: **left as is, would a reader acting on this record reach a wrong conclusion or wrong fix?** Side B: **followed as stated, would a reader waste a fix or lose a settled conclusion?** Either side admits it; reviewer preference admits nothing. The record outlives the run and reads as settled, so the reader is not the author.

This test overrides the lenses. A caveat worded loosely, a section ordered differently, a measurement more precise than needed — none change what a reader does, so none are findings. Reviewer preference is never a finding.

A passing finding flags the claim: the caller restates it as unsettled / not measured. Anything failing the test goes unsaid, never recorded as a note.

## Lenses

Six, none lowering the bar above. Run the ones this report can fail under; skip the rest and say which and why.

- **Evidence sufficiency** — each claim names its backing artifact (`path:line`, command plus measured value, or source/window/record) and that artifact carries the claim.
- **Sweep completeness** — each absence/exhaustiveness/"only" claim meets the trace the report left: the command issued, the count returned, no `| head` or page cut between them. Never re-run the sweep.
- **Hypothesis separation** — nothing stated as concluded is an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**.
- **Completeness** — the explanation covers the symptom as observed (magnitude, timing, scope) or documents the unknowns instead.
- **Consistency** — contradicting claims, a timeline disagreeing with the narrative, shifting terminology, a summary overstating the body.
- **Reality** — a version, config, code path, or constraint described wrongly.

*Skip* **Necessity**, **Executability**, **Risk** and **Assumptions** — four `review-plan` lenses outside these six — and say so: the work the report may propose is not reviewed here, and what a report assumes is Evidence sufficiency's business.

## Dispatch

Each reviewer gets its lenses, the target report, the question, the sources, **What counts as a finding**, and **Finding contract**. Stance: try to make a claim fail. One that will not break passes — but an unevidenced finding is not a finding.

Size for shortest wall-clock. A split buys independence — neither sees the other's findings. Use `superpowers:dispatching-parallel-agents` when dispatching more than one; this is fact-finding, not implementation.

Confine every search to the project root or narrower.

Before the union, apply the intake filter: an item with no evidence pointer is rejected as an intake decision, not a finding; items sharing one exact `(lens, claim)` pair bundle into one finding with the union of evidence pointers and suggested changes. Cite each rejection's reason and each bundle's pair.

## Finding contract

Findings only — never a rewritten report — each with:

- **lens**
- **claim** — one sentence on what is wrong
- **evidence** — `path:line` or the quoted artifact line. No evidence, no finding
- **suggested change** — the claim restated as unsettled / not measured, plus what would settle it

Report "no findings" explicitly rather than inventing one.

## Pass

1. Gather the target report, its question, and its stated sources. One invocation reviews exactly one target, once.
2. Dispatch reviewers per **Dispatch**, always fresh-context at the `highest` tier.
3. Take the union; re-judge none. The pass is additive: any evidenced finding stays in.
4. Report per **Report** and stop. Restating and publishing are the caller's; this skill never re-invokes itself.
5. The only re-invocation is the caller's subtractive verification pass on the ledger: accepted entries plus rejected entries routed back through intake with new evidence, Evidence sufficiency lens only. Sustain each accepted entry if any pointer carries the claim; promote a routed rejected entry only if the new evidence carries it; flag nothing new. A re-flag without new evidence is not a finding; a claim with no ledger entry never is, even with evidence.
6. One verification pass is one round under `using-dude`'s **Loop convergence**: a re-flag without new evidence is the same finding; clean is no accepted entry rejected and every accepted entry sustained.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**: the target, the fan-out, lenses run and skipped with why, the union per **Finding contract**, claims no lens flagged, and that the pass finished. The report is the ledger: flagged claims are accepted entries with pointers; checked-but-unflagged claims are rejected entries with the reason plus the pointer checked. The caller keeps it; a later pass reads it, not the report. List intake decisions with reasons and bundled pairs.

## Measure

Record per-lens accepted/rejected counts against the tracking issue, or chat with none, citing ledger entries and intake decisions. Only converged counts reach the issue, published by the caller per `using-dude`'s **Stage boundaries**. Reuse the ledger; keep no separate log.

## Caller contract

This holds for every caller, never redefined at a call site.

- **One invocation is one pass** over one declared target. A paraphrased or lightly edited report is the same target and opens no second invocation. The only re-invocation is the subtractive verification pass in **Pass**.
- **Clean is that the pass finished** — every lens reported and the union reported — not that it found nothing.
- **Only an unflagged claim is settled.** A flagged claim is restated by the caller as unsettled / not measured with what would settle it, then the whole report is published. Never re-run on that restatement; never edit the report here.
- **Nothing publishes until the pass finishes.** Report in chat, never GitHub, per `using-dude`'s **Stage boundaries**.
