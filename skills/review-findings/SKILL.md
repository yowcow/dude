---
name: review-findings
description: Use to review report claims.
---

# Review Findings

Use on a report whose deliverable is findings, once it is drafted and before it is published. This reviews what the report claims and what backs it, never the work that produced it and never the fix it might lead to.

## Orchestration model

**This skill always dispatches lens reviewers in a fresh context; it never reviews inline.** The main loop gathers the inputs, sizes the fan-out, takes the union of what they return, and reports. It re-judges none of those findings, and it dispatches no verdict worker.

Each reviewer goes out at the tier `using-dude`'s **Worker tier** sets for a marked worker: a miss comes back as "nothing found", and only another reader catches it.

One invocation is one pass. This skill never re-reviews on its own, never edits the report, and never declares a claim settled. Revising flagged claims to unsettled / not measured, then publishing, belongs to the caller.

## Target

One invocation reviews exactly one target, and **the caller declares it**: the findings or judgment report that is about to become the canonical record. The caller states the artifact, the question it answers, and the sources it rests on.

An `investigate-*` / `settle-question` findings report and a ruling published as an issue comment differ in format only. The failure modes read for here — evidence that does not carry the claim, a sweep that stopped early, a hypothesis promoted without a measurement — are the same in both, so they are one target rather than two.

## What counts as a finding

One test with two sides admits everything this skill reports. Side A: **left as it is, would a reader acting on this record reach a wrong conclusion or take a wrong fix?** Side B: **followed as stated, would a reader waste a fix or lose a settled conclusion?** A finding passes the bar on either side; reviewer preference passes on neither. The record outlives the run that wrote it and is read as settled, so the reader in that test is not the author.

This test overrides the lenses. A lens names a failure mode to look for; naming one does not make every instance of it worth reporting. A caveat that could be worded more carefully, a section a reviewer would have ordered differently, a measurement reported to more precision than it warrants — none of these change what a reader does, so they are not findings, whatever lens surfaced them. Reviewer preference is never a finding here.

A finding that passes the test flags that claim. It does not block publication, and it is not a note: the caller restates the claim as unsettled / not measured. Anything that fails the test is left unsaid.

## Lenses

Six, and none of them lowers the bar in **What counts as a finding**. Run the ones this report can fail under; skip the rest and say which and why.

- **Evidence sufficiency** — whether each claim names its backing artifact: a `path:line`, a command plus its measured value, or a source/window/record per claim; and whether that artifact carries the claim.
- **Sweep completeness** — every claim of absence, exhaustiveness, or "only" is met against the trace the report itself left, not by re-running the sweep: the command issued, the count it returned, and no `| head` or page cut between the two. A claim whose trace cannot be pointed at in the report is a finding.
- **Hypothesis separation** — whether anything stated as a conclusion is in fact an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**. This is that rule checked by a reader rather than by the run that has been living with the hypothesis.
- **Completeness** — whether the explanation accounts for the symptom as observed: its magnitude, its timing, and its scope, or the unknowns documented in place of them. This is the `investigate-*` exit condition re-read by someone who did not decide it was met.
- **Consistency** — claims that contradict each other, a timeline that disagrees with the narrative, terminology that shifts meaning between sections, a summary that overstates what the body establishes.
- **Reality** — mismatch with the system as it is: a version, config, code path, or constraint the report describes wrongly.

*Skip* **Necessity**, **Executability**, **Risk** and **Assumptions**, and say so in the report: the work this report may propose is not reviewed here (it enters `plan-work`), so there is nothing for the first three to bite on, and what a report takes for granted is Evidence sufficiency's business here.

## Dispatch

Each reviewer gets its assigned lenses, the target report, the question it answers, the sources it rests on, **What counts as a finding**, and **Finding contract**. Every reviewer takes the same stance: try to make a claim fail. One you cannot break passes — but a finding you cannot evidence is not a finding.

Size the fan-out for shortest wall-clock. Independence is what a split buys — neither sees the other's findings, so neither anchors on them. Use `superpowers:dispatching-parallel-agents` for the dispatch itself when there is more than one worker; this is independent fact-finding, not implementation. Don't restate its prompt-construction guidance here.

Confine every search to the project root or narrower.

On receipt and before the union, the main loop applies the intake filter: an item with no evidence pointer is rejected, not reported; items sharing one `(lens, claim)` pair are bundled into one finding under that pair. Filtering cites the bar side it failed or the pair it bundled under.

## Finding contract

Each reviewer returns findings only — never a rewritten report — with:

- **lens**
- **claim** — one sentence on what is wrong
- **evidence** — `path:line` from the repo, or the quoted line from the artifact. No evidence, no finding
- **suggested change** — the claim restated as unsettled / not measured, plus what would settle it — not a replacement conclusion

Report "no findings" explicitly rather than inventing one.

## Pass

1. Gather the inputs: the target report, the question it answers, and its stated sources. One invocation reviews exactly one target, once.
2. Dispatch reviewers, sized per **Dispatch**, always in a fresh context at the marked tier.
3. Take the union of the findings they return. Re-judge none of them: the pass is additive, so a finding any reviewer evidenced stays in (recall maximization).
4. Report per **Report**, and stop there — restating flagged claims and publishing are the caller's job. This skill never re-invokes itself.
5. The caller re-invokes for a subtractive verification pass only on the ledger: its input is the accepted entries plus rejected entries the caller routes back through intake with new evidence; it runs the Evidence sufficiency lens only, sustains or rejects each accepted entry against its evidence pointer, re-evaluates each intake-routed rejected entry under Evidence sufficiency (promoted to accepted only if the new evidence carries the claim, otherwise stays rejected), and flags nothing new. A re-flagged claim without new evidence is not a finding, and a claim with no ledger entry is never a finding even with evidence.
6. One verification pass is one round under `using-dude`'s **Loop convergence**: a re-flag without new evidence is the same finding, and the loop is clean when no accepted entry is rejected and every accepted entry is sustained.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**. Report: the target reviewed, the fan-out used, which lenses ran, which skipped with why, the union of findings per **Finding contract**, which claims no run lens flagged, and that the pass finished. The report is the ledger for any re-invocation: each flagged claim is an entry marked accepted with its evidence pointer, each unflagged-but-checked claim is an entry marked rejected with the reason it failed **What counts as a finding** plus the artifact pointer checked. The caller keeps this ledger; a later pass reads it instead of re-reading the report from scratch. The report also lists intake decisions: each rejected item with its missing-evidence reason, and each bundled group with its `(lens, claim)` pair.

## Caller contract

This holds for every caller, rather than being defined at each call site.

- **One invocation is one pass** over one declared target. A paraphrased, restated, or lightly edited version of the same report is the same target — it does not open a second invocation. The only re-invocation is the subtractive verification pass in **Pass**: the caller re-invokes with the ledger's accepted entries plus intake-routed rejected-with-new-evidence entries, and nothing else.
- **The required clean for this findings pass is that the pass finished** — every dispatched lens reported and the union was reported per **Report** — not that it returned no findings.
- **Only a claim no run lens flagged is a settled conclusion.** A flagged claim is restated by the caller as unsettled / not measured, with what would settle it. The whole report is then published. This skill is not re-run on that restatement, and it never edits the report itself.
- **Nothing is published until the pass has finished.** Report the pass to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.
