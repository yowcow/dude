---
name: review-findings
description: Use to review a findings report or a judgment report before it becomes the canonical record — an investigation's root-cause findings, a decision or ruling comment, or any report whose claims a later flow will act on. Reports findings; it never edits what it reviewed. Triggers on "review these findings", "review this report before I publish it", "is this conclusion backed", "check this before it goes on the issue".
---

# Review Findings

Use on a report whose deliverable is findings, once it is drafted and before it is published. This reviews what the report claims and what backs it, never the work that produced it and never the fix it might lead to.

## Orchestration model

**One pass dispatches exactly one reviewer and no verdict worker.** The reviewer goes out in a fresh context at the tier `using-dude`'s **Worker tier** sets for a marked worker, carrying the report, the question it answers, its stated sources, the six lenses, and the record of past rounds. The reviewer validates each candidate finding against the target and its sources under this skill's own **What counts as a finding** before returning, and returns the final blocking findings or clean. The orchestrator gathers the inputs and reports the result and never re-judges a finding. `review-plan` is not used here; nothing here dispatches a verdict worker.

The main loop is normally the same run that wrote the report under review, so a read reached there rests on that run's own account of its evidence — which is precisely what a dispatched reader in a fresh context is bought to escape. An orchestrator that reads the report against the six lenses itself has not run this gate.

A run cannot re-judge what it never returned, and a sweep cut short is a failure of recall rather than of judgment, so nothing but another reader catches it.

## Target

One invocation reviews exactly one target, and **the caller declares it**: the findings or judgment report that is about to become the canonical record. The caller states the artifact, the question it answers, and the sources it rests on.

An `investigate-*` findings report and a ruling published as an issue comment differ in format only. The failure modes read for here — evidence that does not carry the claim, a sweep that stopped early, a hypothesis promoted without a measurement — are the same in both, so they are one target rather than two.

## What counts as a finding

One test admits everything this skill reports: **left as it is, would a reader acting on this record reach a wrong conclusion or take a wrong fix?** The record outlives the run that wrote it and is read as settled, so the reader in that test is not the author.

This test overrides the lenses. A lens names a failure mode to look for; naming one does not make every instance of it worth reporting. A caveat that could be worded more carefully, a section a reviewer would have ordered differently, a measurement reported to more precision than it warrants — none of these change what a reader does, so they are not findings, whatever lens surfaced them. Reviewer preference is never a finding here.

Both severities in **Severity** are blocking. There is no non-blocking tier: a finding that passes the test is resolved before the report is published, and anything that fails it is left unsaid rather than recorded as a note.

## Lenses

Six, and none of them lowers the bar in **What counts as a finding**. One pass gives the whole list to its single reviewer.

- **Evidence sufficiency** — whether each claim's stated evidence actually carries it: a conclusion resting on a sample, a single occurrence, or a correlation presented as though it were the measurement; a number with no command, window, or source behind it.
- **Sweep completeness** — every claim of absence, exhaustiveness, or "only" is met with the sweep that produced it: whether the sweep ran to completion and its whole output was read, rather than a truncated or paged view of it. A claim whose sweep cannot be pointed at is a finding.
- **Hypothesis separation** — whether anything stated as a conclusion is in fact an unconfirmed hypothesis, per `using-dude`'s **Investigation workflow**. This is that rule checked by a reader rather than by the run that has been living with the hypothesis.
- **Completeness** — whether the explanation accounts for the symptom as observed: its magnitude, its timing, and its scope, or the unknowns documented in place of them. This is the `investigate-*` exit condition re-read by someone who did not decide it was met.
- **Consistency** — claims that contradict each other, a timeline that disagrees with the narrative, terminology that shifts meaning between sections, a summary that overstates what the body establishes.
- **Reality** — mismatch with the system as it is: a version, config, code path, or constraint the report describes wrongly.

*Skip* **Necessity**, **Executability**, **Risk** and **Assumptions**, and say so in the report: the work this report may propose is not reviewed here (it enters `plan-work`), so there is nothing for the first three to bite on, and what a report takes for granted is Evidence sufficiency's business here.

## Severity

Each finding returns lens, severity, claim (one sentence), evidence (`path:line` or the quoted line), and suggested change. Severity says where the remedy lives, not how urgent it is. Report "no findings" explicitly rather than inventing one.

- **Critical** — the conclusion itself is unbacked. No edit to the report fixes it: the remedy lives outside a report edit, per **Caller contract**.
- **Important** — what was measured is described wrongly. Editing the report resolves it.

## Pass

1. Gather the inputs: the target report, the question it answers, its stated sources, the six lenses, and the record of earlier passes if the caller supplied one.
2. Dispatch exactly one reviewer with all of the above. Confine every search to the project root or narrower.
3. The reviewer validates each candidate finding against the target and its sources under **What counts as a finding** and returns the final blocking findings or clean.
4. Report per **Report**, and stop there — revising and re-running are the caller's job.

## Report

Report to the caller in chat, never to GitHub, per `using-dude`'s **Stage boundaries**. Report, for this pass: the target reviewed, the fixed fan-out of one, any lens skipped with why, the blocking findings per **Severity**, the round history carried forward, and the verdict — clean, or the blocking findings that remain, flagging any Critical separately.

## Caller contract

This holds for every caller, rather than being defined at each call site. The review always runs and is never conditioned on risk or claim type.

- **One round is one pass plus the caller's fold-in.** This skill never re-reviews on its own; revising the report and re-running belong to the caller.
- **After an Important finding**, re-run only the lens that produced it plus Reality, scoped to the edited scope.
- **A Critical finding returns to the evidence owner of the work that produced the target.** Every `investigate-*` caller returns to its evidence gathering / point settlement; a caller with no owning procedure asks a person where to get the missing evidence and stops.
- **Where re-measurement is impossible**, restate the conclusion as unsettled / not measured with what would settle it, leaving no unsupported certainty.
- **After Critical handling** — new evidence, or a revision to unsettled / not measured — the next pass is full scope, preserving the outer loop's total round count and same-finding history.
- **Two findings are the same** when a later pass faults the same claim on the same grounds, however the wording moved — including a claim restated after an edit meant to resolve it.
- **Stopping** is `using-dude`'s **Loop convergence**.
- **Nothing is published until the pass comes back clean.** Report each round to the caller in chat and never to GitHub, per `using-dude`'s **Stage boundaries**.
